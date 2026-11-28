// Run against a local feed to regenerate the bundled, verified service records.
import {writeFile} from 'node:fs/promises';
const base=process.argv[2] || 'http://127.0.0.1:10009/classic/api/';
async function read(route,params) {
  const response=await fetch(base+route+'?'+new URLSearchParams(params));
  if (!response.ok) throw Error('Could not read '+route+' ('+response.status+')');
  return response.json();
}
for (const chamber of ['House','Senate']) {
  const {members,retrievedAt}=await read('members',{chamber});
  const records=[];
  let cursor=0;
  await Promise.all(Array.from({length:3},async()=>{
    while (cursor<members.length) {
      const index=cursor++;
      const member=members[index];
      const id=new URL(member.url).pathname.split('/').filter(Boolean).at(-1);
      let periods=[];
      try {({periods}=await read('service',{chamber,id}));}
      catch {console.warn('Service unavailable for '+chamber+' '+id);}
      records[index]={...member,periods};
    }
  }));
  if (records.filter(r=>r.periods.length).length<members.length*.9) throw Error('Insufficient coverage for '+chamber);
  await writeFile(new URL('./service-'+chamber+'.json',import.meta.url),JSON.stringify({retrievedAt,members:records},null,2)+'\n');
}
