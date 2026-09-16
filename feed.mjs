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
const pages = new Map(), ranges = new Map(), inflight = new Map();
const TTL = 60000, ACTIVE = 15 * 60000;
let active = 0;
const queue = [];
const clean = (s) => String(s || '').replace(/<[^>]*>/g, '').replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16))).replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n))).replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ').trim();

function officialUrl(value) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || !['ilga.gov', 'www.ilga.gov', 'lrb.ilga.gov'].includes(url.hostname) || url.username || url.password || (url.port && url.port !== '443')) throw new Error('Only official ILGA HTTPS URLs are permitted');
  url.hash = '';
  return url;
}
async function limited(work) {
  if (active >= 4) {
    if (queue.length >= 500) throw new Error('Fetch queue full');
    await new Promise((resolve) => queue.push(resolve));
  } else active++;
  try { return await work(); }
  finally { const next = queue.shift(); if (next) next(); else active--; }
}
async function upstream(value) {
  return limited(async () => {
    let url = officialUrl(value);
    const signal = AbortSignal.timeout(15000);
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
  const cached = pages.get(url);
  if (!fresh && cached && Date.now() - Date.parse(cached.retrievedAt) < TTL) return cached;
  const key = `page:${url}`;
  if (inflight.has(key)) return inflight.get(key);
  const pending = upstream(url).then((result) => {
    pages.delete(url); pages.set(url, result);
    while (pages.size > 500) pages.delete(pages.keys().next().value);
    return result;
  }).finally(() => inflight.delete(key));
  inflight.set(key, pending); return pending;
}
function parseSummary(html, url) {
  const tabAt = html.search(/class=["'][^"']*\btab-content\b/i);
  const title = clean(html.slice(Math.max(0, tabAt)).match(/<h2\b[^>]*>([\s\S]*?)<\/h2>/i)?.[1]);
  const block = html.match(/id=["']sponsorDiv["'][^>]*>([\s\S]*?)<\/div>/i)?.[1];
  const type = new URL(url).searchParams.get('DocTypeID') || '';
  const sponsor = (chamber) => clean(block?.match(new RegExp(`<a\\b[^>]*href=["'][^"']*\\/${chamber}\\/Members\\/Details\\/[^"']+["'][^>]*>([\\s\\S]*?)<\\/a>`, 'i'))?.[1]);
  const senateSponsor = sponsor('Senate'), houseSponsor = sponsor('House');
  if (!title || (!block && !['AM','EO'].includes(type))) throw new Error('Incomplete bill page');
  return { subject: title, senateSponsor, houseSponsor, primarySponsor: type.startsWith('H') ? houseSponsor : senateSponsor, otherChamberSponsor: type.startsWith('H') ? senateSponsor : houseSponsor };
}
function rangeUrl(value) {
  const url = officialUrl(value);
  const type = url.pathname.match(/^\/Legislation\/RegularSession\/(SB|HB|SR|HR|SJR|HJR|SJRCA|HJRCA|EO|JSR|AM)$/i)?.[1]?.toUpperCase();
  const first = Number(url.searchParams.get('num1')), last = Number(url.searchParams.get('num2'));
  if (!type || !Number.isSafeInteger(first) || !Number.isSafeInteger(last) || first < 1 || last < first || last - first >= 300 || last > 9999999) throw new Error('Invalid bill range');
  url.searchParams.sort();
  return { url: url.href, type, first, last };
}
async function rebuild(entry, force) {
  if (entry.pending) return entry.pending;
  entry.pending = (async () => {
    const index = await page(entry.url, force);
    const found = new Map();
    for (const match of index.html.matchAll(/<a\b[^>]*href=["']([^"']*\/Legislation\/BillStatus\?[^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)) {
      const url = officialUrl(new URL(match[1].replaceAll('&amp;', '&'), index.officialUrl).href);
      const params = Object.fromEntries([...url.searchParams].map(([k,v]) => [k.toLowerCase(),v]));
      const n = Number(params.docnum);
      if (params.doctypeid !== entry.type || n < entry.first || n > entry.last) continue;
      const item = found.get(n) || { number: `${entry.type}${String(n).padStart(4,'0')}`, url: url.href, title: '' };
      const label = clean(match[2]);
      if (label && !new RegExp(`^${entry.type}\\s*0*${n}$`, 'i').test(label)) item.title = label;
      found.set(n, item);
    }
    if (!found.size) throw new Error('ILGA returned no bills for this range');
    const prior = new Map((entry.data?.bills || []).map((b) => [b.url,b]));
    const bills = await Promise.all([...found].sort(([a],[b])=>a-b).map(async ([,bill]) => {
      try {
        const detail = await page(bill.url, force);
        const summary = parseSummary(detail.html, bill.url);
        return { ...bill, title: summary.subject || bill.title, summary, retrievedAt: detail.retrievedAt, stale: false };
      } catch {
        const old = prior.get(bill.url);
        return { ...bill, ...(old || {}), stale: true, error: 'Details could not be refreshed' };
      }
    }));
    entry.data = { officialUrl: entry.url, retrievedAt: index.retrievedAt, checkedAt: new Date().toISOString(), bills, complete: bills.every((b)=>!b.stale) };
    entry.error = null;
    return entry.data;
  })().catch((error) => { entry.error = error.message; throw error; }).finally(() => { entry.pending = null; entry.attemptedAt = Date.now(); });
  return entry.pending;
}
async function range(value, force = false) {
  const parsed = rangeUrl(value);
  let entry = ranges.get(parsed.url);
  if (!entry) {
    if (ranges.size >= 32) {
      const removable = [...ranges].filter(([,e])=>!e.pending).sort(([,a],[,b])=>a.accessedAt-b.accessedAt)[0];
      if (!removable) throw new Error('Range capacity reached');
      ranges.delete(removable[0]);
    }
    entry = { ...parsed, accessedAt: Date.now(), attemptedAt: 0 }; ranges.set(parsed.url,entry);
  }
  entry.accessedAt = Date.now();
  if (force || !entry.data) await rebuild(entry, force);
  else if (Date.now() - Date.parse(entry.data.checkedAt) >= TTL && Date.now()-entry.attemptedAt >= TTL) void rebuild(entry,false).catch(()=>{});
  return { ...entry.data, stale: !!entry.error || Date.now() - Date.parse(entry.data.checkedAt) >= TTL, refreshing: !!entry.pending };
}
const timer = setInterval(() => {
  for (const entry of ranges.values()) if (Date.now()-entry.accessedAt < ACTIVE && Date.now()-entry.attemptedAt >= TTL) void rebuild(entry,false).catch(()=>{});
}, 10000);
timer.unref();
const send = (res,status,value) => { res.writeHead(status, {'content-type':'application/json','cache-control':'no-store'}); res.end(JSON.stringify(value)); };
const server = createServer(async (req,res) => {
  const path = new URL(req.url, 'http://localhost');
  if (req.method === 'GET' && ['/','/health'].includes(path.pathname)) return send(res,200,{status:'ok'});
  const supplied = Buffer.from(req.headers.authorization || ''), expected = Buffer.from(`Bearer ${token}`);
  if (supplied.length !== expected.length || !timingSafeEqual(supplied,expected)) return send(res,401,{error:'Unauthorized'});
  if (req.method !== 'GET') return send(res,405,{error:'GET required'});
  try {
    const url = path.searchParams.get('url'), fresh = path.searchParams.get('refresh') === '1';
    if (path.pathname === '/range') return send(res,200,await range(url,fresh));
    if (path.pathname === '/page') return send(res,200,await page(url,fresh));
    return send(res,404,{error:'Not found'});
  } catch (error) { return send(res,502,{error:error.message}); }
});
server.listen(Number(process.env.PORT || 10000),'0.0.0.0',() => {
  console.log('ILGA feed ready; certificate verification enabled');
  for (const [type,first] of [['SB',301],['SB',501],['SB',2101],['HB',501]]) {
    const url = `https://ilga.gov/Legislation/RegularSession/${type}?DocTypeID=${type}&GaId=18&SessionId=114&num1=${String(first).padStart(4,'0')}&num2=${String(first+99).padStart(4,'0')}`;
    void range(url).catch((error)=>console.error(`Warmup ${type}${first}: ${error.message}`));
  }
});
process.on('SIGTERM',()=>{ clearInterval(timer); server.close(()=>process.exit(0)); });
