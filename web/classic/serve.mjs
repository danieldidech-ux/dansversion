import { readFileSync } from 'node:fs';

const assets = new Map([
  ['/', ['index.html', 'text/html; charset=utf-8']],
  ['/mast.png', ['mast.png', 'image/png']],
  ['/statutes.mjs', ['statutes.mjs', 'text/javascript']],
  ['/classic.mjs', ['classic.mjs', 'text/javascript']],
  ['/reader-panels.mjs', ['../reader-panels.mjs', 'text/javascript']]
].map(([path, [file, type]]) => [path, {type, body:readFileSync(new URL(file, import.meta.url))}]));

const types = new Set(['SB','HB','SR','HR','SJR','HJR','SJRCA','HJRCA','EO','JSR','AM']);
function numeric(value, max) {
  if (!/^\d{1,6}$/.test(value ?? '')) return null;
  const n = Number(value);
  return n > 0 && n <= max ? n : null;
}
function rangeUrl(type, first) {
  const url = new URL('https://ilga.gov/Legislation/RegularSession/' + type);
  url.search = new URLSearchParams({DocTypeID:type,GaId:'18',SessionId:'114',
    num1:String(first).padStart(4,'0'),num2:String(first+99).padStart(4,'0')});
  return url.href;
}
// Construct only the public ILCS directory and text URLs. Ignore client origins.
function statuteSource(params) {
  const part = params.get('part') || 'Chapters';
  if (!['Chapters','Acts','Articles','details'].includes(part)) return null;
  const url = new URL('/Legislation/ILCS/'+part,'https://www.ilga.gov');
  if (part === 'Chapters') return url;
  for (const key of ['ChapterID','ChapterNumber','ActID','SeqStart','SeqEnd','Chapter','MajorTopic','ActName','ChapAct']) {
    const value = params.get(key);
    if (!value) continue;
    if (value.length > 512 || (['ChapterID','ChapterNumber','ActID','SeqStart','SeqEnd'].includes(key) && !/^\d{1,16}$/.test(value))) return null;
    url.searchParams.set(key,value);
  }
  if (!url.searchParams.has('ChapterID') || (part !== 'Acts' && !url.searchParams.has('ActID'))) return null;
  return url;
}
export async function serveClassic(req, res, url, reader, loadPage) {
  function answer(status, body = '', type = 'text/plain', headers = {}) {
    res.writeHead(status, {'content-type':type,'x-content-type-options':'nosniff',...headers});
    res.end(req.method === 'HEAD' ? undefined : body);
  }
  if (!['GET','HEAD'].includes(req.method)) return answer(405,'','text/plain',{allow:'GET, HEAD'});
  if (url.pathname === '/classic') return answer(308,'','text/plain',{location:'/classic/'+url.search});
  const route = url.pathname.slice('/classic'.length);
  const asset = assets.get(route);
  if (asset) return answer(200,asset.body,asset.type,{'cache-control':'no-cache'});
  const p=url.searchParams, type=p.get('type'), chamber=p.get('chamber');
  let result;
  try {
    if (route === '/api/statutes') {
      const source = statuteSource(p);
      if (!source) return answer(400,'Invalid statute reference');
      const official = await loadPage(source.href);
      const main = official.html.match(/<main\b[^>]*>([\s\S]*?)<\/main>/i);
      if (!main) return answer(502,'Official statute page unavailable');
      result = {markup:main[1].replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi,''),
        officialUrl:official.officialUrl,retrievedAt:official.retrievedAt};
    } else if (route === '/api/range' || route === '/api/sponsors') {
      const number = numeric(p.get('number'),99999);
      if (!types.has(type) || !number) return answer(400,'Invalid bill');
      const first = Math.floor((number-1)/100)*100+1;
      const index = await reader.range(rangeUrl(type,first));
      if (route === '/api/statutes') {
      const source = statuteSource(p);
      if (!source) return answer(400,'Invalid statute reference');
      const official = await loadPage(source.href);
      const main = official.html.match(/<main\b[^>]*>([\s\S]*?)<\/main>/i);
      if (!main) return answer(502,'Official statute page unavailable');
      result = {markup:main[1].replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi,''),
        officialUrl:official.officialUrl,retrievedAt:official.retrievedAt};
    } else if (route === '/api/range') result = index;
      else {
        const bill = index.bills.find(row=> Number(row.number.slice(type.length)) === number);
        if (!bill) return answer(404,'Bill unavailable');
        result = await reader.summary(bill.url);
      }
    } else if (route === '/api/members' || route === '/api/service') {
      if (chamber !== 'House' && chamber !== 'Senate') return answer(400,'Invalid chamber');
      const id = numeric(p.get('id'),999999);
      if (route === '/api/service' && !id) return answer(400,'Invalid member');
      const index = await reader.members(chamber);
      if (route === '/api/members') result = index;
      else {
        const member = index.members.find(m=>Number(new URL(m.url).pathname.split('/').filter(Boolean).at(-1))===id);
        if (!member) return answer(404,'Member unavailable');
        result = await reader.service(member.url);
      }
    } else return answer(404);
    return answer(200,JSON.stringify(result),'application/json',{'cache-control':'no-store'});
  } catch {
    return answer(502,'Could not verify official data');
  }
}
