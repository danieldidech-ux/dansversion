import {tenureValue,oathOrder} from './service-time.mjs';
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
let snapshotTask, liveTenure, liveRoster=false;
const tenureNote='Longest service first. Ties use known swearing-in order, then last name. ≈ marks service reported only by year.';
function showTenure(data) {
  const members=liveRoster && data.snapshot ? entries : data.members;
  const changed=!tenureReady || JSON.stringify([entries,monthsByUrl,approximate])!==JSON.stringify([members,data.months,data.approximate]);
  entries=members;
  monthsByUrl=data.months;
  approximate=data.approximate;
  tenureReady=true;
  message.replaceChildren(timestamp(data));
  $('tenureStatus').textContent=tenureNote;
  if (changed) {fill();restorePlace();}
}
async function bundledTenure() {
  const response=await fetch('./service-'+chamber+'.json');
  if (!response.ok) throw Error('Snapshot unavailable');
  const {members,retrievedAt}=await response.json();
  const months={},approximate={};
  for (const {url,periods} of members) {
    const value=tenureValue(periods);
    months[url]=value.months;
    approximate[url]=value.approximate;
  }
  return {members:members.map(({periods,...member})=>member),months,approximate,retrievedAt,snapshot:true,stale:true};
}
async function applySort() {
  const version=++sortVersion;
  if (!byTenure()) {
    $('tenureStatus').textContent='';
    if (entries.length) fill(); else await load();
    return;
  }
  if (tenureReady) fill(); else $('tenureStatus').textContent='Loading service dates…';
  if (!tenureReady) {
    snapshotTask ||= bundledTenure().catch(()=>null);
    const snapshot=await snapshotTask;
    if (version!==sortVersion) return;
    if (snapshot) showTenure(snapshot);
  }
  try {
    do {
      liveTenure ||= api('tenure',{chamber}).catch(error=>{liveTenure=null;throw error;});
      const data=await liveTenure;
      if (version!==sortVersion) return;
      liveRoster=true;
      showTenure(data);
      if (data.done) return;
      liveTenure=null;
      await new Promise(resolve=>setTimeout(resolve,1000));
    } while (version===sortVersion);
  } catch {
    if (version!==sortVersion) return;
    const retry=mk('button','Retry');retry.onclick=applySort;
    $('tenureStatus').replaceChildren(tenureReady?'Showing saved service dates. ':'Could not load service dates. ',retry);
  }
}
function rowLink(text,url,key) {
  const a = mk('a',text);
  a.href = url;
  a.dataset.place = key;
  return a;
}
function fill() {
  const query = filter.value.toLowerCase().replace(/\s+/g,'');
  const ranked=byTenure() && tenureReady;
  const ordered=[...entries];
  if (!billView && $('sort').value==='District') ordered.sort((a,b)=>a.district-b.district);
  if (ranked) ordered.sort((a,b)=>(monthsByUrl[b.url]??-1)-(monthsByUrl[a.url]??-1) || oathOrder(a)-oathOrder(b));
  if (!billView) {
    const header=$('memberColumn').parentElement;
    const rankHeader=header.querySelector('.rank-cell');
    if (ranked && !rankHeader) {
      const th=mk('th','Rank');th.className='rank-cell';th.scope='col';header.prepend(th);
    } else if (!ranked) rankHeader?.remove();
    rows.closest('table').classList.toggle('ranked',ranked);
  }
  const fragment = document.createDocumentFragment();
  for (const [index,item] of ordered.entries()) {
    const searchable=billView ? item.number+item.title : item.name+' '+item.district+' '+item.party;
    if (!searchable.toLowerCase().replace(/\s+/g,'').includes(query)) continue;
    const row = document.createElement('tr');
    if (ranked) {
      const cell=row.insertCell();
      cell.className='rank-cell';
      cell.textContent=monthsByUrl[item.url]!=null ? String(index+1) : '—';
    }
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
  $(billView?'billEmpty':'memberEmpty').hidden = rows.rows.length>0;
}
let restored=false;
function restorePlace() {
  if (!place || restored || !rows.rows.length) return;
  restored=true;
  requestAnimationFrame(()=>{
    window.scrollTo(0,place.top);
    rows.querySelector('[data-place="'+CSS.escape(place.key)+'"]')?.focus({preventScroll:true});
  });
}
async function load() {
  message.textContent='Checking ILGA…';
  try {
    if (byTenure()) {
      await applySort();
    } else {
      const data = billView ? await api('range',{type,number:first,first,last}) : await api('members',{chamber});
      if (!billView) liveRoster=true;
      entries = billView ? data.bills : data.members;
      if (billView) message.replaceChildren(); else message.replaceChildren(timestamp(data));
      if (byTenure()) await applySort(); else fill();
      if (billView) void enrichBills(entries,rows);
    }
    restorePlace();
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
