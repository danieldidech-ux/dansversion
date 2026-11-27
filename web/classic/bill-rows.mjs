import {apiBase} from './api-url.mjs';
const mk=(tag,text)=>Object.assign(document.createElement(tag),{textContent:text});
export const labels={committee:'Assigned to substantive committee',both:'Reached both chambers',passed:'Passed both / pending governor',signed:'Signed by governor',vetoed:'Vetoed'};
export function legend() {
  const out=mk('div','');out.className='bill-key';out.setAttribute('aria-label','Bill status colors');
  for(const [key,label] of Object.entries(labels)) {const span=mk('span',label);span.className=key;out.append(span);}
  return out;
}
export function paintBill(row,item) {
  const cell=row.querySelector('.bill-sponsors'), summary=item.summary;
  cell.replaceChildren();
  if(!summary) {cell.textContent=item.failed?'Sponsors unavailable':'Loading sponsors…';return;}
  row.className=summary.billStatus?'bill-'+summary.billStatus:'';
  row.title=labels[summary.billStatus]||'';
  const type=item.number.match(/^[A-Z]+/)[0];
  for(const [i,chamber] of (type.startsWith('H')?['House','Senate']:['Senate','House']).entries()) {
    const name=summary[chamber.toLowerCase()+'Sponsor'];
    if(name) {
      const line=mk('div','');
      line.setAttribute('aria-label',chamber+' sponsor: '+name);
      line.title=chamber+' sponsor';
      const text=mk(i===1?'em':'span',name);
      const id=summary[chamber.toLowerCase()+'SponsorId'];
      if (/^\d+$/.test(id||'')) {
        const a=mk('a','');
        a.href='?'+new URLSearchParams({view:'profile',chamber,id});
        a.dataset.place=item.number+'-'+chamber+'-sponsor';
        a.append(text);line.append(a);
      } else line.append(text);
      cell.append(line);
    }
    else if(i===1 && summary.bothChambers) cell.append(mk('div','No '+chamber+' sponsor'));
  }
}
const saved=new Map();
export async function enrichBills(items,root) {
  let cursor=0;
  await Promise.all(Array.from({length:3},async()=>{
    while(cursor<items.length) {
      const item=items[cursor++], type=item.number.match(/^[A-Z]+/)[0], number=Number(item.number.slice(type.length));
      if(!item.summary || item.stale || !('houseSponsorId' in item.summary)) {
        try {
          let task=saved.get(item.number);
          if(!task) {
            task=(async()=>{
              const url=apiBase+'sponsors?'+new URLSearchParams({type,number});
              let response=await fetch(url);
              if([502,503,504].includes(response.status)) {await new Promise(r=>setTimeout(r,600));response=await fetch(url);}
              if(!response.ok) throw Error('Unavailable');
              return (await response.json()).summary;
            })();
            saved.set(item.number,task);
          }
          item.summary=await task;
        } catch {saved.delete(item.number);item.failed=true;}
      }
      for(const row of root.querySelectorAll('[data-bill="'+CSS.escape(item.number)+'"]')) paintBill(row,item);
    }
  }));
}
