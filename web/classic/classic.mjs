import {paintBill,enrichBills} from './bill-rows.mjs';
import {apiBase} from './api-url.mjs';
import { disclosure, timestamp } from './reader-panels.mjs';

const $ = id => document.getElementById(id);
const params = new URLSearchParams(location.search);
const types = ['SB','HB','SR','HR','SJR','HJR','SJRCA','HJRCA','EO','JSR','AM'];
const type = types.includes(params.get('type')) ? params.get('type') : 'SB';
const firstOf = n => Math.floor((n-1)/100)*100+1;
const input = Number(params.get('first'));
const first = Number.isInteger(input) && input>0 && input<=9999999 ? input : 301;
const limit = Number(params.get('last'));
const last = Number.isInteger(limit) && limit>=first && limit-first<100 ? limit : first+99;
const chamber = params.get('chamber') === 'Senate' ? 'Senate' : 'House';
const chamberViews=['legislation','committees','rules','profile'];
const view = ['bills','members','statutes','acts',...chamberViews].includes(params.get('view')) ? params.get('view') : 'home';
const billView = view === 'bills';
const filter = $(billView ? 'filterBills' : 'filterMembers');
const rows = $(billView ? 'billRows' : 'memberRows');
const message = $(billView ? 'billTime' : 'memberTime');
const place = history.state?.classicPlace;
const rangeLink = (kind,num) => '?' + new URLSearchParams({view:'bills',type:kind,first:String(firstOf(num))});
const mk = (tag,text) => Object.assign(document.createElement(tag),{textContent:text});
const digits = n=>String(n).padStart(4,'0');
async function api(route, query) {
  const url=apiBase+route+'?'+new URLSearchParams(query);
  let response=await fetch(url);
  if ([502,503,504].includes(response.status)) {
    await new Promise(resolve=>setTimeout(resolve,600));
    response=await fetch(url);
  }
  if (!response.ok) throw new Error('Official data unavailable');
  return response.json();
}
for (const name of ['home','bills','members','statutes','acts']) $(name).hidden = name !== view;
$('chamberPage').hidden=!chamberViews.includes(view);
$('numberform').onsubmit = async event => {
  event.preventDefault();
  const match = $('number').value.trim().toUpperCase().match(/^([A-Z]+)\s*0*(\d{1,7})$/);
  if (!match || !types.includes(match[1]) || !Number(match[2])) {
    $('hint').textContent = 'Enter a bill or resolution number, such as SB 315.';
    return;
  }
  const [,kind,num] = match;
  $('hint').textContent = 'Checking the official index…';
  try {
    const index = await api('range',{type:kind,number:num});
    const bill = index.bills.find(b=>Number(b.number.slice(kind.length))===Number(num));
    if (bill) location.assign(bill.url);
    else $('hint').textContent = 'This number is not listed in the official index.';
  } catch { $('hint').textContent = 'ILGA is unavailable. Try again.'; }
};
let entries = [];
let monthsByUrl={}, approximate={}, tenureReady=false, sortVersion=0;
const byTenure=()=>!billView && $('sort').value==='Tenure';
function duration(months) {
  if (!Number.isInteger(months)) return 'Unavailable';
  const years=Math.floor(months/12), rest=months%12;
  return [years && years+' yr',rest && rest+' mo'].filter(Boolean).join(' ') || '<1 mo';
}
async function applySort() {
  const version=++sortVersion;
  fill();
  if (!byTenure()) { $('tenureStatus').textContent=''; return; }
  if (!entries.length) return;
  while (!tenureReady && version===sortVersion) {
    $('tenureStatus').textContent='Checking service dates…';
    try {
      const data=await api('tenure',{chamber});
      if (version!==sortVersion) return;
      tenureReady=data.done;
      monthsByUrl=data.months; approximate=data.approximate;
      if (!tenureReady) {
        $('tenureStatus').textContent='Checking service dates ('+data.checked+' of '+data.total+')…';
        await new Promise(resolve=>setTimeout(resolve,2000));
      }
    } catch {
      if (version!==sortVersion) return;
      const retry=mk('button','Retry');retry.onclick=applySort;
      $('tenureStatus').replaceChildren('Could not load tenure. ',retry);
      return;
    }
  }
  if (version!==sortVersion) return;
  $('tenureStatus').textContent='Longest service first. Gaps are excluded. ≈ marks service reported only by year.';
  fill();
}
function rowLink(text,url,key) {
  const a = mk('a',text);
  a.href = url;
  a.dataset.place = key;
  return a;
}
function fill() {
  const query = filter.value.toLowerCase().replace(/\s+/g,'');
  const selected = entries.filter(row=>(billView ? row.number+row.title : row.name+' '+row.district+' '+row.party)
    .toLowerCase().replace(/\s+/g,'').includes(query));
  // ILGA supplies its directory in surname order, including compound names
  // and suffixes. Stable sorting also preserves that order for tenure ties.
  if (!billView && $('sort').value==='District') selected.sort((a,b)=>a.district-b.district);
  if (byTenure() && tenureReady) selected.sort((a,b)=>(monthsByUrl[b.url]??-1)-(monthsByUrl[a.url]??-1));
  const fragment = document.createDocumentFragment();
  for (const item of selected) {
    const row = document.createElement('tr');
    if (billView) {
      row.insertCell().append(rowLink(item.number,item.url,item.number));
      row.insertCell().append(rowLink(item.title||'Official bill record',item.url,item.number+'-title'));
      row.dataset.bill=item.number;
      row.insertCell().className='bill-sponsors';
      paintBill(row,item);

    } else {
      const id = new URL(item.url).pathname.split('/').filter(Boolean).at(-1);
      row.insertCell().append(rowLink(item.name,'?'+new URLSearchParams({view:'profile',chamber,id}),'member-'+id));
      row.insertCell().textContent = item.district;
      row.insertCell().textContent = item.party;
      const service=row.insertCell();
      if (byTenure() && tenureReady) { const label=mk('span',(approximate[item.url]?'≈ ':'')+duration(monthsByUrl[item.url])); label.className='tenure-value'; service.append(label); }
      service.append(disclosure('Service history',()=>api('service',{chamber,id}),data=>data.periods.join(' · ')));
    }
    fragment.append(row);
  }
  rows.replaceChildren(fragment);
  $(billView?'billEmpty':'memberEmpty').hidden = selected.length>0;
}
async function load() {
  message.textContent='Checking ILGA…';
  try {
    const data = billView ? await api('range',{type,number:first,first,last}) : await api('members',{chamber});
    entries = billView ? data.bills : data.members;
    if (billView) message.replaceChildren(); else message.replaceChildren(timestamp(data));
    if (byTenure()) await applySort(); else fill();
    if (billView) void enrichBills(entries,rows);
    if (place) requestAnimationFrame(()=>{
      window.scrollTo(0,place.top);
      rows.querySelector('[data-place="'+CSS.escape(place.key)+'"]')?.focus({preventScroll:true});
    });
  } catch {
    const retry=mk('button','Retry');
    retry.onclick=load;
    message.replaceChildren('Could not load the official list. ',retry);
  }
}
if (chamberViews.includes(view)) {
  const {mountChamber}=await import('./chambers.mjs');
  await mountChamber($('chamberPage'),params);
} else if (view === 'acts') {
  const {mountActs}=await import('./public-acts.mjs');
  await mountActs($('acts'),params);
} else if (view === 'statutes') {
  const {mountStatutes}=await import('./statutes.mjs');
  await mountStatutes($('statutes'),params);
} else if (view !== 'home') {
  if (billView) {
    $('billHeading').textContent=({SB:'Senate Bills',HB:'House Bills'})[type] || type+' Legislation';
    for (const kind of types) $('type').add(new Option(kind,kind));
    $('type').value=type;
    $('first').value=first;
    $('rangeBar').textContent=type+' '+digits(first)+' through '+type+' '+digits(last);
    $('prev').hidden=first===1;
    $('prev').href=rangeLink(type,Math.max(1,first-100));
    $('next').hidden=first+100>9999999;
    $('next').href=rangeLink(type,first+100);
    $('rangeform').onsubmit=e=>{e.preventDefault(); location.assign(rangeLink($('type').value,Number($('first').value)));};
  } else {
    $('memberColumn').textContent=chamber==='House'?'Representative':'Senator';
    if (params.get('sort')==='tenure') $('sort').value='Tenure';
    $('memberHeading').textContent=chamber+' Members';
    $('memberBar').textContent=chamber==='House'?'Illinois Representatives':'Illinois Senators';
  }
  if (place) { filter.value=place.filter; $('sort').value=place.sort; }
  document.title=(billView?$('rangeBar').textContent:chamber+' Members')+' · OGILGA';
  filter.oninput=fill;
  $('sort').onchange=()=>{
    const url=new URL(location.href);
    if (byTenure()) url.searchParams.set('sort','tenure'); else url.searchParams.delete('sort');
    history.replaceState(history.state,'',url);
    void applySort();
  };
  rows.addEventListener('click',event=>{
    const link=event.target.closest('a[data-place]');
    if (!link || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    history.replaceState({...history.state,classicPlace:{key:link.dataset.place,top:scrollY,filter:filter.value,sort:$('sort').value}},'');
  });
  void load();
}
