import { tenureIndex, memberService } from './tenure.mjs';
import { readFileSync } from 'node:fs';

const assets = new Map([
  ['/', ['index.html', 'text/html; charset=utf-8']],
  ['/mast.png', ['mast.png', 'image/png']],
  ['/api-url.mjs', ['api-url.mjs', 'text/javascript']],
  ['/chambers.mjs', ['chambers.mjs', 'text/javascript']],
  ['/statutes.mjs', ['statutes.mjs', 'text/javascript']],
  ...['House','Senate'].map(chamber=>['/service-'+chamber+'.json',['service-'+chamber+'.json','application/json']]),
  ['/service-time.mjs',['service-time.mjs','text/javascript']],
  ['/public-acts.mjs', ['public-acts.mjs', 'text/javascript']],
  ['/bill-rows.mjs', ['bill-rows.mjs', 'text/javascript']],
  ['/classic.mjs', ['classic.mjs', 'text/javascript']],
  ['/reader-panels.mjs', ['../reader-panels.mjs', 'text/javascript']]
].map(([path, [file, type]]) => [path, {type, body:readFileSync(new URL(file, import.meta.url))}]));

const types = new Set(['SB','HB','SR','HR','SJR','HJR','SJRCA','HJRCA','EO','JSR','AM']);
function numeric(value, max) {
  if (!/^\d{1,7}$/.test(value ?? '')) return null;
  const n = Number(value);
  return n > 0 && n <= max ? n : null;
}
function rangeUrl(type, first, last) {
  const url = new URL('https://ilga.gov/Legislation/RegularSession/' + type);
  url.search = new URLSearchParams({DocTypeID:type,GaId:'18',SessionId:'114',
    num1:String(first).padStart(4,'0'),num2:String(last).padStart(4,'0')});
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
function chamberSource(p) {
  const view=p.get('view'), chamber=p.get('chamber');
  const origin='https://www.ilga.gov';
  if (view==='legislation') return new URL('/Legislation',origin);
  if (!['House','Senate'].includes(chamber)) return null;
  const id=numeric(p.get('id'),999999);
  if (view==='rules') return new URL('/'+chamber+'/Rules',origin);
  if (view==='profile' && id) return new URL('/'+chamber+'/Members/Details/'+id+(p.get('primary')==='1'?'?Primary=True':''),origin);
  if (view==='committees') {
    if (!p.has('id')) return new URL('/'+chamber+'/Committees',origin);
    const tab=p.get('tab') || 'MembersList';
    if (id && ['MembersList','Bills','Hearings'].includes(tab)) return new URL('/'+chamber+'/Committees/'+tab+'/'+id,origin);
  }
  return null;
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
    if (route === '/api/acts') {
      const first = numeric(p.get('first'),99999);
      if (p.has('first') && (!first || first % 100 !== 1)) return answer(400,'Invalid public act range');
      result = await reader.publicActs(first);
    } else if (['/api/statutes','/api/chamber'].includes(route)) {
      const source = route === '/api/statutes' ? statuteSource(p) : chamberSource(p);
      if (!source) return answer(400,'Invalid statute reference');
      const official = await loadPage(source.href);
      const main = official.html.match(/<main\b[^>]*>([\s\S]*?)<\/main>/i);
      if (!main) return answer(502,'Official statute page unavailable');
      result = {markup:main[1].replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi,''),
        officialUrl:official.officialUrl,retrievedAt:official.retrievedAt};
    } else if (['/api/range','/api/sponsors','/api/bill-link'].includes(route)) {
      const number = numeric(p.get('number'),9999999);
      if (!types.has(type) || !number) return answer(400,'Invalid bill');
      const first = numeric(p.get('first'),9999999) || Math.floor((number-1)/100)*100+1;
      const last = numeric(p.get('last'),9999999) || first+99;
      if (last<first || last-first>=300 || number<first || number>last) return answer(400,'Invalid range');
      const index = await reader.range(rangeUrl(type,first,last));
      if (route === '/api/range') result = index;
      else {
        const bill = index.bills.find(row=> Number(row.number.slice(type.length)) === number);
        if (!bill) return answer(404,'Bill unavailable');
        if (route === '/api/bill-link') return answer(302,'','text/plain',{location:bill.url});
        result = await reader.summary(bill.url);
      }
    } else if (['/api/members','/api/service','/api/tenure'].includes(route)) {
      if (chamber !== 'House' && chamber !== 'Senate') return answer(400,'Invalid chamber');
      const id = numeric(p.get('id'),999999);
      if (route === '/api/service' && !id) return answer(400,'Invalid member');
      const index = await reader.members(chamber);
      if (route === '/api/members') result = index;
      else if (route === '/api/tenure') result = {...index,...tenureIndex(chamber,index.members,reader)};
      else {
        const member = index.members.find(m=>Number(new URL(m.url).pathname.split('/').filter(Boolean).at(-1))===id);
        if (!member) return answer(404,'Member unavailable');
        result = await memberService(reader,member.url);
      }
    } else return answer(404);
    return answer(200,JSON.stringify(result),'application/json',{'cache-control':'no-store','access-control-allow-origin':'*'});
  } catch {
    return answer(502,'Could not verify official data');
  }
}
