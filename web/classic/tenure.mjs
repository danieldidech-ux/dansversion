// ILGA profiles generally publish service dates to the month. Merge overlapping
// intervals and exclude gaps when a member left and later returned.
const months = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'];
const month = '(?:(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sept?(?:ember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\\.?\\s+)?';
const date = month+'((?:19|20)\\d{2})';
const ranges = new RegExp('\\b'+date+'\\s*(?:[-–—]|to)\\s*(?:(present|current)|'+date+')\\b','gi');
function dateIndex(name,year) {
  return Number(year)*12 + (name ? months.indexOf(name.slice(0,3).toLowerCase()) : 0);
}
export function serviceMonths(periods, now=new Date()) {
  const current=now.getUTCFullYear()*12+now.getUTCMonth();
  const spans=[];
  for (const line of periods) for (const match of line.matchAll(ranges)) {
    const start=dateIndex(match[1],match[2]);
    const end=match[3]?current:Math.min(current,dateIndex(match[4],match[5]));
    if (start<=end) spans.push([start,end]);
  }
  if (!spans.length) return null;
  spans.sort((a,b)=>a[0]-b[0]);
  let total=0, previous=0;
  for (const [start,end] of spans) {
    total+=Math.max(0,end-Math.max(start,previous));
    previous=Math.max(previous,end);
  }
  return total;
}
const caches=new Map();
export function tenureIndex(chamber, members, reader) {
  const key=members.map(m=>m.url).join('|');
  let cache=caches.get(chamber);
  if (!cache || cache.key!==key || Date.now()>cache.expires) {
    cache={key,expires:Infinity,done:false,checked:0,months:{}};
    caches.set(chamber,cache);
    let index=0;
    async function worker() {
      while (index<members.length) {
        const {url}=members[index++];
        try {cache.months[url]=serviceMonths((await reader.service(url)).periods);}
        catch {cache.months[url]=null;}
        cache.checked++;
      }
    }
    Promise.all([worker(),worker()]).then(()=>{
      cache.done=true;
      cache.expires=Date.now()+(Object.values(cache.months).includes(null)?10*60000:86400000);
    });
  }
  return {done:cache.done,checked:cache.checked,total:members.length,months:cache.months};
}
