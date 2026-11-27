import { serveClassic } from './web/classic/serve.mjs';
import { createReader, officialUrl } from './reader.mjs';
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { X509Certificate, timingSafeEqual } from 'node:crypto';
import { rootCertificates, setDefaultCACertificates } from 'node:tls';

const pem = readFileSync(new URL('./sectigo-ovr40.pem', import.meta.url), 'utf8');
const issuer = new X509Certificate(pem);
if (!issuer.ca || Date.now() < Date.parse(issuer.validFrom) || Date.now() > Date.parse(issuer.validTo) || !rootCertificates.some((rootPem) => {
  const root = new X509Certificate(rootPem);
  return root.subject === issuer.issuer && issuer.verify(root.publicKey);
})) throw new Error('Unverified ILGA intermediate');
setDefaultCACertificates([...rootCertificates, pem]);
const token = process.env.ILGA_FEED_TOKEN;
if (!token || token.length < 32) throw new Error('ILGA_FEED_TOKEN must be configured');
const pages = new Map();
const inflight = new Map();
const queue = [];
const PAGE_BYTES = 24 * 1024 * 1024;
const telemetry = {upstream: 0, maxQueueWaitMs: 0, lastUpstreamMs: null};
let bytes = 0, active = 0;
async function limited(work) {
  const started = Date.now();
  const signal = AbortSignal.timeout(15000);
  if (active >= 4) {
    if (queue.length >= 64) throw new Error('Fetch queue full');
    await new Promise((resolve, reject) => {
      const admit = () => {
        signal.removeEventListener('abort', cancel);
        resolve();
      };
      const cancel = () => {
        const pos = queue.indexOf(admit);
        if (pos >= 0) queue.splice(pos, 1);
        reject(signal.reason);
      };
      queue.push(admit);
      signal.addEventListener('abort', cancel, {once: true});
    });
  } else active++;
  const fetched = Date.now();
  telemetry.maxQueueWaitMs = Math.max(telemetry.maxQueueWaitMs, fetched - started);
  telemetry.upstream++;
  try { return await work(signal); }
  finally {
    telemetry.lastUpstreamMs = Date.now() - fetched;
    const next = queue.shift();
    if (next) next();
    else active--;
  }
}
async function upstream(value) {
  return limited(async (signal) => {
    let url = officialUrl(value);
    for (let i = 0; i < 5; i++) {
      const response = await fetch(url, { redirect: 'manual', signal, headers: { accept: 'text/html', 'user-agent': 'DansVersion-ILGA-Feed/1.0', 'cache-control': 'no-cache' } });
      if ([301,302,303,307,308].includes(response.status)) {
        const location = response.headers.get('location');
        await response.body?.cancel();
        if (!location) throw new Error('Invalid ILGA redirect');
        url = officialUrl(new URL(location, url).href); continue;
      }
      if (!response.ok) { await response.body?.cancel(); throw new Error(`ILGA HTTP ${response.status}`); }
      if (!response.headers.get('content-type')?.includes('text/html')) { await response.body?.cancel(); throw new Error('ILGA did not return HTML'); }
      const html = await response.text();
      if (html.length > 6000000 || /<title>[^<]* - Error<\/title>/i.test(html)) throw new Error('Invalid ILGA page');
      return { html, officialUrl: url.href, retrievedAt: new Date().toISOString() };
    }
    throw new Error('Too many ILGA redirects');
  });
}
async function page(url, fresh = false) {
  url = officialUrl(url).href;
  const cached = pages.get(url)?.result;
  if (!fresh && cached && Date.now() - Date.parse(cached.retrievedAt) < 60000) return cached;
  const key = `page:${url}`;
  if (inflight.has(key)) return inflight.get(key);
  const pending = upstream(url).then((result) => {
    bytes -= pages.get(url)?.size || 0;
    pages.delete(url);
    const size = Buffer.byteLength(result.html);
    pages.set(url, {result,size});
    bytes += size;
    while (bytes > PAGE_BYTES || pages.size > 500) {
      const key = pages.keys().next().value;
      bytes -= pages.get(key).size;
      pages.delete(key);
    }
    return result;
  }).finally(() => inflight.delete(key));
  inflight.set(key, pending); return pending;
}
const reader = createReader(page);
async function fullRange(url, force) {
  const index = await reader.range(url, force);
  let next = 0;
  // Leave at least one upstream slot for a bill opened interactively.
  async function enrich() {
    while (next < index.bills.length) {
      const row = index.bills[next++];
      try {
        const detail = await reader.summary(row.url, force);
        Object.assign(row, {summary:detail.summary, retrievedAt:detail.retrievedAt,
          title:row.title || detail.summary.subject, stale:detail.stale,
          detailStatus:detail.stale ? 'stale' : detail.complete ? 'verified' : 'partial'});
      } catch {
        row.stale = true;
        row.detailStatus = 'unavailable';
        row.error = 'Details could not be refreshed';
      }
    }
  }
  await Promise.all(Array.from({length: Math.min(2,index.bills.length)},enrich));
  return {...index, complete:index.bills.every(row => row.detailStatus === 'verified')};
}
const send = (res,status,value) => { res.writeHead(status, {'content-type':'application/json','cache-control':'no-store'}); res.end(JSON.stringify(value)); };
const server = createServer(async (req,res) => {
  const path = new URL(req.url, 'http://localhost');
  const host = (req.headers.host || '').split(':')[0].toLowerCase();
  if (['ogilga.net','www.ogilga.net'].includes(host) && !path.pathname.startsWith('/classic')) {
    // The custom domain serves the public reader from its homepage.
    path.pathname = '/classic' + path.pathname;
    return serveClassic(req,res,path,reader,page);
  }
  if (path.pathname === '/classic' || path.pathname.startsWith('/classic/')) return serveClassic(req,res,path,reader,page);
  if (req.method === 'GET' && ['/','/health'].includes(path.pathname)) return send(res,200,{status:'ok'});
  const supplied = Buffer.from(req.headers.authorization || ''), expected = Buffer.from(`Bearer ${token}`);
  if (supplied.length !== expected.length || !timingSafeEqual(supplied,expected)) return send(res,401,{error:'Unauthorized'});
  if (req.method !== 'GET') return send(res,405,{error:'GET required'});
  try {
    const url = path.searchParams.get('url'), fresh = path.searchParams.get('refresh') === '1';
    if (path.pathname === '/range-index') return send(res,200,await reader.range(url,fresh));
    if (path.pathname === '/summary') return send(res,200,await reader.summary(url,fresh));
    if (path.pathname === '/member-service') return send(res,200,await reader.service(url,fresh));
    if (path.pathname === '/members') return send(res,200,await reader.members(path.searchParams.get('chamber'),fresh));
    if (path.pathname === '/range') return send(res,200,await fullRange(url,fresh));
    if (path.pathname === '/status') return send(res,200,{...reader.status(), ...telemetry, queued:queue.length, pageCacheBytes:bytes});
    if (path.pathname === '/page') return send(res,200,await page(url,fresh));
    return send(res,404,{error:'Not found'});
  } catch (error) { return send(res,502,{error:error.message}); }
});
server.listen(Number(process.env.PORT || 10000),'0.0.0.0',() => {
  console.log('ILGA feed ready; certificate verification enabled');
}); 
process.on('SIGTERM', () => server.close(() => process.exit(0)));
