import {apiBase} from './api-url.mjs';
import {timestamp} from './reader-panels.mjs';

const clean=value=>(value||'').replace(/\s+/g,' ').trim();
const node=(tag,text)=>Object.assign(document.createElement(tag),{textContent:text||''});
const href=query=>'?'+new URLSearchParams(query);
function link(label,url) {const a=node('a',label);a.href=url;return a;}
function bar(label) {const title=node('h2',label); title.className='bar'; return title;}
function official(raw,base) {
  if (!raw || raw.includes('<')) return null;
  let url;
  try {url=new URL(raw,base);} catch {return null;}
  return url.protocol==='https:' && /(^|\.)ilga\.gov$/i.test(url.hostname)?url:null;
}
function destination(url) {
  const member=url.pathname.match(/^\/(House|Senate)\/Members\/Details\/(\d+)\/?$/i);
  const committee=url.pathname.match(/^\/(House|Senate)\/Committees\/(Members(?:List)?|Bills|Hearings)\/(\d+)\/?$/i);
  const chamber=name=>name.toLowerCase()==='senate'?'Senate':'House';
  if (member) return href({view:'profile',chamber:chamber(member[1]),id:member[2]});
  if (committee) return href({view:'committees',chamber:chamber(committee[1]),id:committee[3],tab:({bills:'Bills',hearings:'Hearings'})[committee[2].toLowerCase()]||'MembersList'});
  return url.href;
}
function cellContents(out,source,base) {
  for (const child of source.childNodes) {
    if (child.nodeType===Node.TEXT_NODE) {out.append(child.textContent);continue;}
    if (child.nodeType!==Node.ELEMENT_NODE || child.matches('.d-none,script,style,button,[hidden]')) continue;
    if (child.tagName==='BR') {out.append(document.createElement('br'));continue;}
    const url=child.tagName==='A' && official(child.getAttribute('href'),base);
    if (url && clean(child.textContent)) out.append(link(clean(child.textContent),destination(url)));
    else cellContents(out,child,base);
  }
}
function copyTable(source,base,{directory=false}={}) {
  const table=document.createElement('table');
  for (const row of source.rows) {
    const out=table.insertRow();
    for (const cell of row.cells) {
      const td=document.createElement(cell.tagName.toLowerCase());
      if (cell.colSpan>1) td.colSpan=cell.colSpan;
      cellContents(td,cell,base);
      out.append(td);
    }
    if (directory && out.cells.length>=4) {
      const url=official(row.cells[0].querySelector('a')?.getAttribute('href'),base);
      if (url) {
        const target=destination(url);
        if (target.startsWith('?')) {
          const p=new URLSearchParams(target.slice(1));p.set('tab','Bills');
          out.cells[3].replaceChildren(link('Bills',href(p)));
        }
      }
    }
  }
  const wrap=node('div');wrap.className='table-scroll';wrap.append(table);
  return wrap;
}
function tables(doc) {return [...doc.querySelectorAll('table')].filter(t=>t.rows.length);}
function legislation(body,doc,base) {
  const groups=new Map();
  for (const a of doc.querySelectorAll('a[href]')) {
    const url=official(a.getAttribute('href'),base);
    const type=url?.pathname.match(/^\/Legislation\/RegularSession\/([A-Z]+)$/i)?.[1].toUpperCase();
    if (!type) continue;
    if (!groups.has(type)) groups.set(type,{label:type,ranges:new Map()});
    const group=groups.get(type);
    const first=Number(url.searchParams.get('num1')),last=Number(url.searchParams.get('num2'));
    if (!first) {group.label=clean(a.textContent);continue;}
    if (last>=first) group.ranges.set(first,last);
  }
  if (!groups.size) throw Error('No legislation index');
  for (const [type,{label,ranges}] of groups) {
    body.append(bar(label));
    const grid=node('div');grid.className='range-grid';
    for (const [first,last] of ranges) {
      // Sparse order/message series sometimes span more than 100 numbers
      // in a single official link. Each displayed batch stays within 100.
      for (let n=first;n<=last;n+=100) {
        const end=Math.min(last,n+99);
        const text=String(n).padStart(4,'0')+'–'+String(end).padStart(4,'0');
        const a=link(text,href({view:'bills',type,first:n,last:end}));
        a.setAttribute('aria-label',type+' '+text);grid.append(a);
      }
    }
    body.append(grid.childElementCount?grid:node('p','No ranges listed.'));
  }
}
function rules(body,doc,base) {
  const list=node('ul');list.className='doc-list';
  const seen=new Set();
  for (const a of doc.querySelectorAll('a[href]')) {
    const url=official(a.getAttribute('href'),base);
    if (!url || !/\.pdf$/i.test(url.pathname) || seen.has(url.href)) continue;
    seen.add(url.href);
    const li=node('li');li.append(link(clean(a.textContent)+' (PDF)',url.href));list.append(li);
  }
  if (!list.childElementCount) throw Error('No rules documents');
  body.append(bar('Rules and amendments'),list);
}
function committees(body,doc,base,chamber,id,tab) {
  if (id) {
    const nav=node('nav');nav.setAttribute('aria-label','Committee records');
    for (const [key,label] of [['MembersList','Members'],['Hearings','Hearings'],['Bills','Bills']]) {
      if (tab===key) nav.append(node('strong',label));
      else nav.append(link(label,href({view:'committees',chamber,id,tab:key})));
    }
    body.append(nav);
  }
  const all=tables(doc);
  if (tab==='Hearings' && id) {
    const unique=new Set();
    for (const table of all) {
      const text=clean(table.textContent);
      if (!text || unique.has(text) || unique.size>=2) continue;
      body.append(bar(unique.size?'Previous hearings':'Scheduled hearings'),copyTable(table,base));unique.add(text);
    }
    if (!unique.size) body.append(node('p','No hearings listed.'));
    return;
  }
  const table=id && tab==='MembersList'?all.find(t=>t.querySelector('a[href*="/Members/Details/" i]') && t.rows[0]?.cells.length>=2):
    all.find(t=>t.rows[0]?.cells.length>=2);
  if (!table) {
    if (id) {body.append(node('p',tab==='Bills'?'No bills listed.':'No members listed.'));return;}
    throw Error('Committee list unavailable');
  }
  body.append(copyTable(table,base,{directory:!id}));
}
function profile(body,doc,base,chamber,id,primary) {
  const card=doc.querySelector('.member-photo')?.parentElement || doc.querySelector('h5')?.parentElement;
  if (!card) throw Error('No profile');
  const photo=official(card.querySelector('img')?.getAttribute('src'),base);
  if (photo) {const img=document.createElement('img');img.src=photo.href;img.alt='';body.append(img);}
  for (const p of card.querySelectorAll('p')) body.append(node('p',clean(p.textContent)));
  const contact=[...doc.querySelectorAll('h3')].find(h=>clean(h.textContent)==='Member Details')?.parentElement;
  for (const row of contact?.querySelectorAll('.card-body > .row') || []) {
    const heading=row.querySelector('.fw-bold,h3'),details=row.querySelector('.col-sm-8,p');
    if (!heading || !details) continue;
    const label=clean(heading.textContent),block=node('section');
    block.append(bar(label.replace(/:$/,'')));
    const content=node('div');cellContents(content,details,base);block.append(content);body.append(block);
  }
  for (const [label,selector] of [['Committee assignments','#pane-Committees'],['Sponsored legislation','#pane-Bills']]) {
    const source=doc.querySelector(selector+' table') || tables(doc).find(t=>label==='Committee assignments'?/Committee\s+Code/i.test(clean(t.rows[0]?.textContent)):/Bill #/i.test(t.rows[0]?.textContent));
    const details=node('details');details.append(node('summary',label));
    if (label==='Sponsored legislation') {
      details.open=primary;
      details.append(link(primary?'Show all sponsored bills':'Show primary sponsorships',href({view:'profile',chamber,id,...(primary?{}:{primary:1})})));
    }
    details.append(source?copyTable(source,base):node('p','None listed.'));
    body.append(details);
  }
}
export async function mountChamber(root,params) {
  const view=params.get('view'),chamber=params.get('chamber')==='Senate'?'Senate':'House';
  const id=params.get('id'),tab=params.get('tab')||'MembersList';
  const body=root.querySelector('.chamber-content'),nav=root.querySelector('nav'),status=root.querySelector('[role=status]');
  nav.append(link('Home','./'));
  if (view==='profile') nav.append(' / ',link(chamber+' members',href({view:'members',chamber})));
  if (view==='committees' && id) nav.append(' / ',link(chamber+' committees',href({view,chamber})));
  const title=root.querySelector('h1');
  title.textContent=({legislation:'Bills & Resolutions',committees:chamber+' Committees',rules:chamber+' Rules',profile:chamber+' Member'})[view];
  async function load() {
    status.textContent='Checking ILGA…';
    try {
      const response=await fetch(apiBase+'chamber?'+params);
      if (!response.ok) throw Error('Official page unavailable');
      const data=await response.json();
      const template=document.createElement('template');template.innerHTML=data.markup;
      const doc=template.content, content=document.createDocumentFragment();
      const heading=[...doc.querySelectorAll('h2')].find(h=>/General Assembly/i.test(h.textContent));
      if (heading) title.textContent=clean(heading.textContent);
      document.title=title.textContent+' · OGILGA';
      if (view==='legislation') legislation(content,doc,data.officialUrl);
      if (view==='committees') committees(content,doc,data.officialUrl,chamber,id,tab);
      if (view==='rules') rules(content,doc,data.officialUrl);
      if (view==='profile') profile(content,doc,data.officialUrl,chamber,id,params.get('primary')==='1');
      body.replaceChildren(content);
      status.replaceChildren(timestamp(data),' · ',link('Official ILGA source',data.officialUrl));
      if (history.state?.chamberPlace) requestAnimationFrame(()=>{
        const place=history.state.chamberPlace;
        window.scrollTo(0,place.top);
        [...body.querySelectorAll('a')].find(a=>a.href===place.url)?.focus({preventScroll:true});
      });
    } catch {
      const retry=node('button','Retry');retry.onclick=load;
      status.replaceChildren('Could not load the official record. ',retry);
    }
  }
  body.addEventListener('click',e=>{const a=e.target.closest('a');if(a)history.replaceState({...history.state,chamberPlace:{top:scrollY,url:a.href}},'');});
  await load();
}
