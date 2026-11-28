import {readFileSync} from 'node:fs';
import {serviceMonths,tenureValue} from './service-time.mjs';
export {serviceMonths} from './service-time.mjs';

// Official profiles can omit the service field for mid-session appointments.
// Use these dated records only when the member is on the current ILGA roster.
const appointments=new Map([
  ['Senate/3281',['December 2010','https://www.ilga.gov/documents/senate/journals/96/2011/SJ096140R.pdf','Senate Journal']],
  ['House/3461',['October 2025','https://www.ilga.gov/House/Members/Details/3461','ILGA biography']],
  ['House/3462',['December 2025','https://www.ilga.gov/Documents/House/journals/104/2026/HJ104062R.pdf','House Journal']],
  ['House/3465',['July 2026','https://ilhousedems.com/2026/08/10/dixon-heitman-sworn-in-as-97th-district-state-representative/','House caucus announcement']]
]);
export async function memberService(reader,url) {
  const match=new URL(url).pathname.match(/^\/(House|Senate)\/Members\/Details\/(\d+)\/?$/i);
  const record=match && appointments.get(match[1]+'/'+match[2]);
  try {
    const live=await reader.service(url);
    if (!record || serviceMonths(live.periods)!==null) return live;
  } catch(error) {
    if (!record) throw error;
  }
  return {periods:[record[0]+' - Present'],sourceUrl:record[1],sourceLabel:record[2],stale:false};
}
const records=new Map();
for (const chamber of ['House','Senate']) {
  const source=JSON.parse(readFileSync(new URL('./service-'+chamber+'.json',import.meta.url),'utf8'));
  for (const {url,periods} of source.members) records.set(url,{periods,nextCheck:Date.parse(source.retrievedAt)+(periods.length?86400000:600000)});
}
const refreshing=new Map();
export function tenureIndex(chamber,members,reader) {
  const now=Date.now(), months={}, approximate={};
  const missing=[],expired=[];
  for (const {url} of members) {
    const record=records.get(url);
    const value=tenureValue(record?.periods || []);
    months[url]=value.months;
    approximate[url]=value.approximate;
    if (!record) missing.push(url);
    else if (now>=record.nextCheck) expired.push(url);
  }
  // Readers can immediately use verified records while a shared refresh runs.
  if (!refreshing.has(chamber) && (missing.length || expired.length)) {
    const queue=[...missing,...expired];
    async function worker() {
      while (queue.length) {
        const url=queue.shift();
        const previous=records.get(url);
        try {
          const {periods}=await memberService(reader,url);
          if (serviceMonths(periods)===null) throw Error('No verified service dates');
          records.set(url,{periods,nextCheck:Date.now()+86400000});
        } catch {
          records.set(url,{periods:previous?.periods || [],nextCheck:Date.now()+600000});
        }
      }
    }
    refreshing.set(chamber,Promise.all([worker(),worker()]).finally(()=>refreshing.delete(chamber)));
  }
  return {months,approximate,done:missing.length===0,checked:members.length-missing.length,total:members.length};
}
