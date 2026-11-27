import { disclosure, timestamp } from './reader-panels.mjs';

const $ = id => document.getElementById(id);
const params = new URLSearchParams(location.search);
const types = ['SB','HB','SR','HR','SJR','HJR','SJRCA','HJRCA','EO','JSR','AM'];
const type = types.includes(params.get('type')) ? params.get('type') : 'SB';
const firstOf = n => Math.floor((n-1)/100)*100+1;
const input = Number(params.get('first'));
const first = Number.isInteger(input) && input>0 && input<=99999 ? firstOf(input) : 301;
const chamber = params.get('chamber') === 'Senate' ? 'Senate' : 'House';
const view = ['bills','members'].includes(params.get('view')) ? params.get('view') : 'home';
const billView = view === 'bills';
const filter = $(billView ? 'filterBills' : 'filterMembers');
const rows = $(billView ? 'billRows' : 'memberRows');
const message = $(billView ? 'billTime' : 'memberTime');
const place = history.state?.classicPlace;
const rangeLink = (kind,num) => '?' + new URLSearchParams({view:'bills',type:kind,first:String(firstOf(num))});
const mk = (tag,text) => Object.assign(document.createElement(tag),{textContent:text});
const digits = n=>String(n).padStart(4,'0');
async function api(route, query) {
  const response = await fetch('./api/'+route+'?'+new URLSearchParams(query));
  if (!response.ok) throw new Error('Official data unavailable');
  return response.json();
}
for (const name of ['home','bills','members']) $(name).hidden = name !== view;
$('numberform').onsubmit = async event => {
  event.preventDefault();
  const match = $('number').value.trim().toUpperCase().match(/^([A-Z]+)\s*0*(\d{1,5})$/);
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
  if (!billView) selected.sort($('sort').value==='District' ? (a,b)=>a.district-b.district : (a,b)=>a.name.localeCompare(b.name));
  const fragment = document.createDocumentFragment();
  for (const item of selected) {
    const row = document.createElement('tr');
    if (billView) {
      row.insertCell().append(rowLink(item.number,item.url,item.number));
      row.insertCell().append(rowLink(item.title||'Official bill record',item.url,item.number+'-title'));
      row.insertCell().append(disclosure('Sponsors',()=>api('sponsors',{type,number:item.number.slice(type.length)}),({summary})=>
        [summary.senateSponsor && 'Senate: '+summary.senateSponsor,summary.houseSponsor && 'House: '+summary.houseSponsor].filter(Boolean).join(' · ') ||
        (summary.sponsorStatus==='not-applicable'?'Not applicable':'Chief sponsor unavailable')));
    } else {
      const id = new URL(item.url).pathname.split('/').filter(Boolean).at(-1);
      row.insertCell().append(rowLink(item.name,item.url,'member-'+id));
      row.insertCell().textContent = item.district;
      row.insertCell().textContent = item.party;
      row.insertCell().append(disclosure('Service history',()=>api('service',{chamber,id}),data=>data.periods.join(' · ')));
    }
    fragment.append(row);
  }
  rows.replaceChildren(fragment);
  $(billView?'billEmpty':'memberEmpty').hidden = selected.length>0;
}
async function load() {
  message.textContent='Checking ILGA…';
  try {
    const data = billView ? await api('range',{type,number:first}) : await api('members',{chamber});
    entries = billView ? data.bills : data.members;
    message.replaceChildren(timestamp(data));
    fill();
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
if (view !== 'home') {
  if (billView) {
    $('billHeading').textContent=({SB:'Senate Bills',HB:'House Bills'})[type] || type+' Legislation';
    for (const kind of types) $('type').add(new Option(kind,kind));
    $('type').value=type;
    $('first').value=first;
    $('rangeBar').textContent=type+' '+digits(first)+' through '+type+' '+digits(first+99);
    $('prev').hidden=first===1;
    $('prev').href=rangeLink(type,Math.max(1,first-100));
    $('next').hidden=first+100>99999;
    $('next').href=rangeLink(type,first+100);
    $('rangeform').onsubmit=e=>{e.preventDefault(); location.assign(rangeLink($('type').value,Number($('first').value)));};
  } else {
    $('memberHeading').textContent=chamber+' Members';
    $('memberBar').textContent=chamber==='House'?'Illinois Representatives':'Illinois Senators';
  }
  if (place) { filter.value=place.filter; $('sort').value=place.sort; }
  document.title=(billView?$('rangeBar').textContent:chamber+' Members')+' · Dan’s Version';
  filter.oninput=fill;
  $('sort').onchange=fill;
  rows.addEventListener('click',event=>{
    const link=event.target.closest('a[data-place]');
    if (!link || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    history.replaceState({...history.state,classicPlace:{key:link.dataset.place,top:scrollY,filter:filter.value,sort:$('sort').value}},'');
  });
  void load();
}
