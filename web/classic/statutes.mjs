import {timestamp} from './reader-panels.mjs';

const parts = new Map([['chapters','Chapters'],['acts','Acts'],['articles','Articles'],['details','details']]);
const clean = text => text.replace(/\s+/g,' ').trim();
const element = (tag,text) => Object.assign(document.createElement(tag),{textContent:text});
function link(text, href) {
  const a = element('a',text);
  a.href = href;
  return a;
}
function local(part, query = new URLSearchParams()) {
  const p = new URLSearchParams({view:'statutes',part});
  for (const key of ['ChapterID','ChapterNumber','ActID','SeqStart','SeqEnd','Chapter','MajorTopic','ActName','ChapAct']) {
    if (query.get(key)) p.set(key,query.get(key));
  }
  return '?'+p;
}
function group(body, title) {
  const section=document.createElement('section');
  if (title) {
    const heading=element('h2',title);
    heading.className='bar';
    section.append(heading);
  }
  const list=document.createElement('ul');
  list.className='statute-index';
  section.append(list);
  body.append(section);
  return list;
}
function appendLink(list, text, href) {
  const item=document.createElement('li');
  item.append(link(text,href));
  list.append(item);
}
function directory(body, doc, part, origin) {
  const next = {Chapters:'Acts',Acts:'Articles',Articles:'details'}[part];
  if (!next) return 0;
  const scope = (part==='Acts' && doc.querySelector('#div_1')) || doc;
  const seen=new Set();
  let list, heading='', prior;
  for (const el of scope.querySelectorAll('h2, a.list-group-item')) {
    if (el.tagName==='H2') { heading=clean(el.textContent); continue; }
    const url=new URL(el.getAttribute('href'),origin);
    const dest=parts.get(url.pathname.split('/').at(-1).toLowerCase());
    if (dest!==next || seen.has(url.href)) continue;
    seen.add(url.href);
    const title=part==='Chapters'?url.searchParams.get('MajorTopic'):part==='Acts'?heading:'Articles and divisions';
    if (!list || title!==prior) { list=group(body,title); prior=title; }
    appendLink(list,clean(el.textContent),local(dest,url.searchParams));
  }
  return seen.size;
}

// Copy text, line breaks, emphasis and table structure only. Source markup
// stays in an inert template, so remote styles and event handlers never run.
const allowed = new Set('table thead tbody tfoot tr td th p div span br code b strong i em u s strike sub sup ol ul li caption'.split(' '));
function copyText(node) {
  if (node.nodeType===Node.TEXT_NODE) return document.createTextNode(node.data);
  if (node.nodeType!==Node.ELEMENT_NODE || ['SCRIPT','STYLE','NOSCRIPT','TEMPLATE'].includes(node.tagName)) return document.createDocumentFragment();
  const tag=node.tagName.toLowerCase();
  const out=allowed.has(tag)?document.createElement(tag):document.createDocumentFragment();
  if (tag==='td' || tag==='th') {
    for (const attr of ['colspan','rowspan']) if (/^[1-9]\d?$/.test(node.getAttribute(attr))) out.setAttribute(attr,node.getAttribute(attr));
  }
  for (const child of node.childNodes) out.append(copyText(child));
  return out;
}
function statuteText(body, original) {
  const text=document.createElement('div');
  text.className='statute-text';
  for (const child of original.childNodes) text.append(copyText(child));
  if (!clean(text.textContent)) throw Error('Empty statute');
  const sections=document.createElement('details');
  sections.className='statute-toc';
  const list=group(sections,'');
  const seen=new Map();
  for (const code of text.querySelectorAll('code')) {
    const match=clean(code.textContent).match(/^\((\d+ ILCS [^/()]+\/[^()]+)\)$/i);
    if (!match) continue;
    const base=match[1].replace(/[^a-z\d.-]+/gi,'-');
    const n=(seen.get(base)||0)+1;
    seen.set(base,n);
    code.id='s-'+base+(n===1?'':'-'+n);
    appendLink(list,match[1],location.search+'#'+code.id);
  }
  if (list.childElementCount) {
    sections.prepend(element('summary','Sections in this text ('+list.childElementCount+')'));
    body.append(sections);
  }
  body.append(text);
}
export async function mountStatutes(root, params) {
  const part=params.get('part') || 'Chapters';
  const nav=root.querySelector('nav'), body=root.querySelector('.statute-body');
  const status=root.querySelector('[role=status]'), h1=root.querySelector('h1');
  function crumb(name,href) { nav.append(' / ',link(name,href)); }
  if (part!=='Chapters') crumb('Illinois Compiled Statutes',local('Chapters'));
  const chapter=params.get('Chapter') || 'Chapter';
  if (['Articles','details'].includes(part)) {
    const p=new URLSearchParams(params);
    for (const k of ['ActID','ActName','ChapAct','SeqStart','SeqEnd']) p.delete(k);
    crumb(chapter,local('Acts',p));
  }
  if (part==='details') {
    const p=new URLSearchParams(params);
    for (const k of ['SeqStart','SeqEnd','ChapAct','ActName']) p.delete(k);
    crumb(params.get('ActName')||'Act contents',local('Articles',p));
  }
  const fallback=new URL('https://www.ilga.gov/Legislation/ILCS/'+(parts.get(part.toLowerCase())||'Chapters'));
  fallback.search=local(part,params).slice(1);
  fallback.searchParams.delete('view');
  fallback.searchParams.delete('part');
  const sourceLink=link('View on ILGA.gov',fallback.href);
  async function load() {
    status.textContent='Checking ILGA…';
    try {
      const response=await fetch('./api/statutes?'+params);
      if (!response.ok) throw Error('Upstream unavailable');
      const data=await response.json();
      const template=document.createElement('template');
      template.innerHTML=data.markup;
      const doc=template.content;
      const officialTitle=[...doc.querySelectorAll('h2')].map(el=>clean(el.textContent)).find(t=>/\(\d+\s+ILCS\b/i.test(t));
      h1.textContent=part==='Chapters'?'Illinois Compiled Statutes':part==='Acts'?
        [params.get('ChapterNumber') && 'Chapter '+params.get('ChapterNumber'),chapter].filter(Boolean).join(' · '):
        officialTitle || params.get('ActName') || 'Act contents';
      document.title=h1.textContent+' · Dan’s Version';
      const content=document.createDocumentFragment();
      if (part==='Chapters') content.append(element('p','Browse by chapter, then select an act.'));
      const entries=directory(content,doc,part,data.officialUrl);
      const original=doc.querySelector('#billtextanchor');
      if (original && clean(original.textContent)) statuteText(content,original);
      else if (!entries) throw Error('Official content missing');
      const info=element('p','See ILGA’s ');
      info.className='notes';
      info.append(link('guide to the statutes','https://www.ilga.gov/Legislation/ILCS/Guide'),' for information about updates and effective dates.');
      body.replaceChildren(content,info);
      sourceLink.href=data.officialUrl;
      status.replaceChildren(timestamp(data),' · ',sourceLink);
      requestAnimationFrame(()=>{
        if (location.hash) document.getElementById(location.hash.slice(1))?.scrollIntoView();
        else if (history.state?.statutePlace) {
          const place=history.state.statutePlace;
          window.scrollTo(0,place.top);
          [...body.querySelectorAll('a')].find(a=>a.href===place.href)?.focus({preventScroll:true});
        }
      });
    } catch {
      const retry=element('button','Retry');
      retry.onclick=load;
      status.replaceChildren('Could not load this statute page. ',retry,' · ',sourceLink);
    }
  }
  body.addEventListener('click',event=>{
    const a=event.target.closest('a');
    if (a && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey) {
      history.replaceState({...history.state,statutePlace:{top:scrollY,href:a.href}},'');
    }
  });
  await load();
}
