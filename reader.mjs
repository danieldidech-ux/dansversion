// Normalized official indexes are small; store these separately from raw HTML.
const MINUTE = 60_000;
export function officialUrl(value) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || !['ilga.gov', 'www.ilga.gov', 'lrb.ilga.gov'].includes(url.hostname) ||
      url.username || url.password || (url.port && url.port !== '443')) throw new Error('Only official ILGA HTTPS URLs are permitted');
  url.hash = '';
  return url;
}
function clean(s = '') {
  return s.replace(/<[^>]*>/g, '').replace(/&#(x[0-9a-f]+|\d+);/gi, (_, code) => {
    const n = code[0].toLowerCase() === 'x' ? parseInt(code.slice(1), 16) : Number(code);
    return n <= 0x10ffff ? String.fromCodePoint(n) : '�';
  }).replace(/&nbsp;/gi, ' ').replace(/&quot;/gi, '"').replace(/&apos;/gi, "'").replace(/&amp;/gi, '&').replace(/\s+/g, ' ').trim();
}
function parameters(url) {
  return Object.fromEntries([...url.searchParams].map(([k,v]) => [k.toLowerCase(),v]));
}
function rangeSpec(value) {
  const url = officialUrl(value);
  const type = url.pathname.match(/^\/Legislation\/RegularSession\/(SB|HB|SR|HR|SJR|HJR|SJRCA|HJRCA|EO|JSR|AM)\/?$/i)?.[1]?.toUpperCase();
  const p = parameters(url), first = Number(p.num1), last = Number(p.num2);
  if (!type || !Number.isSafeInteger(first) || !Number.isSafeInteger(last) || first < 1 || last < first || last-first >= 300 || last > 9999999) throw new Error('Invalid bill range');
  url.searchParams.sort();
  return {url:url.href, type, first, last, ga:p.gaid, session:p.sessionid};
}
function parseRange(page, spec) {
  const found = new Map();
  for (const m of page.html.matchAll(/<a\b[^>]*\bhref=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)) {
    const url = new URL(m[1].replace(/&amp;/gi,'&'), page.officialUrl);
    if (!/^\/Legislation\/BillStatus\/?$/i.test(url.pathname)) continue;
    officialUrl(url);
    const p = parameters(url), n = Number(p.docnum);
    if (p.doctypeid?.toUpperCase() !== spec.type || !Number.isSafeInteger(n) || n < 1 ||
        (spec.ga && p.gaid !== spec.ga) || (spec.session && p.sessionid !== spec.session)) continue;
    if (n < spec.first || n > spec.last) continue;
    const previous = found.get(n);
    const row = previous || { number: spec.type + String(n).padStart(4,'0'), url: url.href, title: '' };
    const text = clean(m[2]);
    if (text && !new RegExp('^'+spec.type+'\\s*0*'+n+'$','i').test(text)) row.title = text;
    found.set(n,row);
  }
  if (!found.size &&
      !/\bno (?:bills|legislation|records) (?:were )?(?:found|filed)\b/i.test(clean(page.html))) throw new Error('Could not verify the requested range');
  return [...found.entries()].sort((a,b)=>a[0]-b[0]).map(([,row])=>row);
}
function parsePublicActs(page) {
  const acts = new Map();
  for (const row of page.html.matchAll(/<tr\b[^>]*>([\s\S]*?)<\/tr>/gi)) {
    const cells = [...row[1].matchAll(/<td\b[^>]*>([\s\S]*?)<\/td>/gi)];
    const act = clean(cells[0]?.[1]).match(/^104-(\d{4,5})$/);
    if (!act) continue;
    const bill = clean(cells[1]?.[1]).match(/^(HB|SB)\s*0*(\d+)$/i);
    const raw = cells[0][1].match(/\bhref=["']([^"']+)["']/i)?.[1];
    if (!bill || !raw) throw Error('Public act entry incomplete');
    const url = officialUrl(new URL(raw.replace(/&amp;/gi,'&'),page.officialUrl));
    const sequence = Number(act[1]);
    acts.set(sequence,{sequence,act:act[0],actUrl:url.href,
      number:bill[1].toUpperCase()+String(Number(bill[2])).padStart(4,'0')});
  }
  if (!acts.size) throw Error('No public act index');
  return [...acts.values()].sort((a,b)=>a.sequence-b.sequence);
}
function parseSummary(page,url) {
  const at = page.html.search(/class=["'][^"']*\btab-content\b/i);
  if (at < 0) throw new Error('Bill detail section unavailable');
  const subject = clean(page.html.slice(at).match(/<h2\b[^>]*>([\s\S]*?)<\/h2>/i)?.[1]);
  if (!subject) throw new Error('Bill title unavailable');
  const block = page.html.match(/\bid=["']sponsorDiv["'][^>]*>([\s\S]*?)<\/div>/i)?.[1];
  const sponsor = chamber => clean(block?.match(new RegExp('<a\\b[^>]*href=["\'][^"\']*/'+chamber+'/Members/Details/[^"\']+["\'][^>]*>([\\s\\S]*?)</a>','i'))?.[1]);
  const sponsorId = chamber => block?.match(new RegExp('/'+chamber+'/Members/Details/(\\d+)(?:[/?#]|["\\\'])','i'))?.[1] || '';
  const senateSponsorId=sponsorId('Senate'), houseSponsorId=sponsorId('House');
  const type = parameters(url).doctypeid?.toUpperCase() || '';
  const senateSponsor = sponsor('Senate'), houseSponsor = sponsor('House');
  const primarySponsor = type.startsWith('H') ? houseSponsor : senateSponsor;
  const otherChamberSponsor = type.startsWith('H') ? senateSponsor : houseSponsor;
  const sponsorStatus = primarySponsor ? 'verified' : /^(EO|AM)$/.test(type) ? 'not-applicable' : 'unavailable';
  const actions = [...page.html.matchAll(/<tr\b[^>]*>([\s\S]*?)<\/tr>/gi)].map(row =>
    [...row[1].matchAll(/<td\b[^>]*>([\s\S]*?)<\/td>/gi)].map(cell=>clean(cell[1])))
    .filter(cells=>/^\d{1,2}\/\d{1,2}\/\d{4}$/.test(cells[0]) && /^(House|Senate)$/.test(cells[1]));
  const actionTexts=actions.map(cells=>cells.slice(2).join(' '));
  const governorSigned=actionTexts.some(text=>/^Governor Approved\b/i.test(text));
  const vetoed=actionTexts.some(text=>/^(?:Governor )?(?:Vetoed|Total Veto|Item Veto|Amendatory Veto)\b/i.test(text));
  const passedBoth=actionTexts.some(text=>/^(?:Passed Both Houses|Sent to the Governor)\b/i.test(text));
  const opposite=type.startsWith('H')?'Senate':'House';
  const bothChambers=!!otherChamberSponsor || passedBoth || governorSigned || vetoed || actions.some(cells=>cells[1]===opposite);
  let committeeAssigned=false;
  for (const cells of [...actions].sort((a,b)=>Date.parse(a[0])-Date.parse(b[0]))) {
    const text=cells.slice(2).join(' ');
    // Amendment referrals do not move the underlying bill.
    if (/Amendment|Added|Removed.*Sponsor/i.test(text)) continue;
    if (/(?:Assigned|Re-assigned|Referred|Re-referred) to /i.test(text)) {
      committeeAssigned=!/\b(?:Rules|Assignments)\b/i.test(text);
    } else if (/^(?:Do Pass|Be Adopted|Placed on Calendar|Second Reading|Third Reading|Arrive in|Passed Both|Sent to the Governor|Governor|Tabled|Session Sine Die)/i.test(text)) committeeAssigned=false;
  }
  const billStatus=governorSigned?'signed':vetoed?'vetoed':passedBoth?'passed':committeeAssigned?'committee':bothChambers?'both':'';
  return {senateSponsorId,houseSponsorId,billStatus,bothChambers,governorSigned,vetoed,passedBoth,subject,senateSponsor,houseSponsor,primarySponsor,otherChamberSponsor,sponsorStatus,complete:sponsorStatus !== 'unavailable'};
}
function parseMembers(page, chamber) {
  const members = new Map();
  for (const match of page.html.split(/Former Members/i)[0].matchAll(/<tr\b[^>]*>([\s\S]*?)<\/tr>/gi)) {
    const cells = [...match[1].matchAll(/<td\b[^>]*>([\s\S]*?)<\/td>/gi)].map(m=>m[1]);
    if (cells.length < 2) continue;
    const link = cells[0].match(/<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/i);
    if (!link) continue;
    const url = officialUrl(new URL(link[1].replace(/&amp;/gi,'&'),page.officialUrl));
    if (!new RegExp('^/'+chamber+'/members/details/','i').test(url.pathname)) continue;
    const district = Number(clean(cells[1])), name = clean(link[2]);
    if (!Number.isInteger(district) || district<1 || !name) continue;
    members.set(url.href,{name,district,party:clean(cells[2]),url:url.href});
  }
  if (!members.size) throw new Error('Member directory unavailable');
  return [...members.values()];
}
export function createReader(load, now = Date.now) {
  const entries = new Map(), pending = new Map();
  const counters = {reads:0, hits:0, coalesced:0, failures:0};
  const lastVerified = {};
  async function read(kind,url,parse,force=false) {
    counters.reads++;
    const key=kind+' '+url, old=entries.get(key);
    if (!force && old && now()-Date.parse(old.retrievedAt)<MINUTE && !old.stale) { counters.hits++; return old; }
    if (pending.has(key)) { counters.coalesced++; return pending.get(key); }
    const fetchValue = async () => {
      try {
        const page=await load(kind==='service'?new URL('?Primary=True',url).href:url,force);
        const data=parse(page);
        if (kind === 'summary' && !data.complete && old?.data.complete) {
          old.stale = true;
          counters.failures++;
          return old;
        }
        const value={data,officialUrl:page.officialUrl,retrievedAt:page.retrievedAt,stale:false};
        entries.delete(key); entries.set(key,value);
        while (entries.size>1800) entries.delete(entries.keys().next().value);
        lastVerified[kind]=page.retrievedAt;
        return value;
      } catch(error) {
        counters.failures++;
        if (!old) throw error;
        old.stale=true;
        return old;
      }
    };
    const task=fetchValue().finally(()=>pending.delete(key));
    pending.set(key,task); return task;
  }
  return {
    async publicActs(first) {
      const index = await read('acts','https://www.ilga.gov/Legislation/PublicActs',parsePublicActs);
      const ranges = new Map();
      for (const act of index.data) {
        const start = 1 + 100 * Math.floor((act.sequence - 1) / 100);
        ranges.set(start, act.sequence);
      }
      return {ranges:[...ranges].map(([first,last])=>({first,last})),
        acts:first ? index.data.filter(act=>act.sequence>=first && act.sequence<first+100) : [],
        retrievedAt:index.retrievedAt,stale:index.stale};
    },
    async range(url,force=false) {
      const spec=rangeSpec(url);
      const index=await read('range',spec.url,page=>parseRange(page,spec),force);
      const bills=index.data.map(row=>{
        const saved=entries.get('summary '+row.url);
        if (!saved) return {...row,detailStatus:'pending',stale:false};
        const stale=saved.stale || now()-Date.parse(saved.retrievedAt)>=MINUTE;
        return {...row,summary:saved.data,title:row.title || saved.data.subject,retrievedAt:saved.retrievedAt,stale,
          detailStatus:stale?'stale':saved.data.complete?'verified':'partial'};
      });
      return {officialUrl:index.officialUrl,retrievedAt:index.retrievedAt,checkedAt:index.retrievedAt,
        indexStale:index.stale,stale:index.stale,complete:bills.every(row=>row.detailStatus==='verified'),
        refreshing:false,bills,sessionId:spec.session,gaId:spec.ga};
    },
    async summary(value,force=false) {
      const url=officialUrl(value);
      if (!/^\/legislation\/billstatus\/?$/i.test(url.pathname)) throw new Error('Expected an official bill link');
      const result=await read('summary',url.href,page=>parseSummary(page,url),force);
      return {summary:result.data,officialUrl:result.officialUrl,retrievedAt:result.retrievedAt,stale:result.stale,
        complete:result.data.complete && !result.stale};
    },
    async members(chamber,force=false) {
      if (!['House','Senate'].includes(chamber)) throw new Error('Unknown chamber');
      const result=await read('members','https://www.ilga.gov/'+chamber+'/Members/List',page=>parseMembers(page,chamber),force);
      return {members:result.data,officialUrl:result.officialUrl,retrievedAt:result.retrievedAt,stale:result.stale};
    },
    async service(value,force=false) {
      const url = officialUrl(value);
      if (!/^\/(?:House|Senate)\/Members\/Details\/\d+\/?$/i.test(url.pathname)) throw new Error('Expected an official member profile');
      const result = await read('service',url.href,page => {
        const photo=page.html.match(/<img\b[^>]*class=["'][^"']*\bmember-photo\b[^"']*["'][^>]*>/i);
        let identity;
        if (photo) {
          const card=page.html.slice(photo.index+photo[0].length);
          identity=card.split(/<\/div>/i,1)[0];
        } else {
          const marker=page.html.search(/>\s*Member Details\s*</i);
          if (marker<0) throw new Error('Member details unavailable');
          identity=page.html.slice(0,marker).split(/<h1\b/i).at(-1);
        }
        const lines=identity.replace(/<\/(?:div|p|h[1-6]|li|span|strong)>|<br\s*\/?>/gi,'\n')
          .split('\n').map(line=>clean(line)).filter(Boolean);
        const periods=lines.filter(line=>line.length<240 && /\b(?:18|19|20)\d{2}\b/.test(line) &&
          /[-–—]|\bto\b/i.test(line) && !/general assembly|copyright/i.test(line));
        if (!periods.length) throw new Error('Service history could not be verified');
        return [...new Set(periods)];
      },force);
      return {periods:result.data,officialUrl:result.officialUrl,retrievedAt:result.retrievedAt,stale:result.stale};
    },
    status:()=>({...counters,inflight:pending.size,lastVerified:{...lastVerified}})
  };
}
