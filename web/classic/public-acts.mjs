import {apiBase} from './api-url.mjs';
import {paintBill,enrichBills} from './bill-rows.mjs';

const node=(tag,text)=>Object.assign(document.createElement(tag),{textContent:text});
function link(label,url) {
  return Object.assign(node('a',label),{href:url});
}
const rangeUrl=first=>'?'+new URLSearchParams({view:'acts',first});
const digits=n=>String(n).padStart(4,'0');
const rangeLabel=range=>'104-'+digits(range.first)+'–104-'+digits(range.last);

export async function mountActs(root,params) {
  const content=root.querySelector('.act-content'),status=root.querySelector('[role=status]');
  const first=params.get('first');
  if (first!==null) {
    const back=root.querySelector('.back');
    back.href='?view=acts';
    back.textContent='All Public Acts';
  }
  async function load() {
    status.textContent='Loading Public Acts…';
    try {
      const url=apiBase+'acts'+(first===null?'':'?'+new URLSearchParams({first}));
      const response=await fetch(url);
      if (!response.ok) throw Error('Index unavailable');
      const {ranges,acts}=await response.json();
      content.replaceChildren();
      status.textContent='';
      document.title='Public Acts · OGILGA';
      if (first===null) {
        const grid=node('nav','');
        grid.className='range-grid';
        grid.setAttribute('aria-label','Public Act ranges');
        for (const range of ranges) grid.append(link(rangeLabel(range),rangeUrl(range.first)));
        content.append(grid);
      } else {
        const index=ranges.findIndex(range=>range.first===Number(first));
        if (index<0) {status.textContent='No Public Acts are listed in this range.';return;}
        const label=rangeLabel(ranges[index]);
        root.querySelector('.bar').textContent=label;
        document.title='Public Acts '+label+' · OGILGA';
        const nav=node('nav','');
        nav.className='rangeNav';
        nav.setAttribute('aria-label','Public Act ranges');
        if (index>0) nav.append(link('Previous 100',rangeUrl(ranges[index-1].first)));
        if (index+1<ranges.length) nav.append(link('Next 100',rangeUrl(ranges[index+1].first)));
        const table=node('table','');
        table.className='list act-list';
        const header=table.createTHead().insertRow();
        for (const name of ['Public Act','Bill Number','Sponsors']) header.append(node('th',name));
        const body=table.createTBody();
        for (const item of acts) {
          const row=body.insertRow();
          row.dataset.bill=item.number;
          row.insertCell().append(link(item.act,item.actUrl));
          const type=item.number.slice(0,2),number=Number(item.number.slice(2));
          row.insertCell().append(link(item.number,apiBase+'bill-link?'+new URLSearchParams({type,number})));
          row.insertCell().className='bill-sponsors';
          paintBill(row,item);
        }
        content.append(nav,table);
        void enrichBills(acts,body);
      }
      const place=history.state?.actPlace;
      if (place) requestAnimationFrame(()=>{
        window.scrollTo(0,place.top);
        [...content.querySelectorAll('a')].find(a=>a.href===place.url)?.focus({preventScroll:true});
      });
    } catch {
      const retry=node('button','Retry');
      retry.onclick=load;
      status.replaceChildren('Could not load Public Acts. ',retry);
    }
  }
  content.addEventListener('click',event=>{
    const a=event.target.closest('a');
    if (a) history.replaceState({...history.state,actPlace:{top:scrollY,url:a.href}},'');
  });
  await load();
}
