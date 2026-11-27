// Mount in the site's existing range or directory view. The caller supplies its
// authenticated same-origin proxy, detail URL builder, and optional scroll pane.
const activePanels = new WeakMap();
function element(tag, text) {
  const node = document.createElement(tag);
  if (text) node.textContent = text;
  return node;
}
export function timestamp(result) {
  const time = element('time');
  const date = new Date(result.retrievedAt);
  if (Number.isNaN(date.valueOf())) {
    time.textContent = 'ILGA check time unavailable';
    return time;
  }
  time.dateTime = date.toISOString();
  time.textContent = (result.stale ? 'Last successful ILGA check ' : 'Checked against ILGA ') +
    new Intl.DateTimeFormat(undefined,{dateStyle:'medium',timeStyle:'short'}).format(date);
  return time;
}
export function disclosure(label, load, describe) {
  const details = element('details');
  const summary = element('summary',label);
  const result = element('div');
  result.setAttribute('aria-live','polite');
  let loading = false, complete = false;
  async function show() {
    if (!details.open || loading || complete) return;
    loading = true;
    result.textContent = 'Checking ILGA…';
    try {
      const data = await load();
      const text = describe(data);
      result.replaceChildren(element('p',text));
      if (data.sourceUrl) {
        const source=element('a',data.sourceLabel);
        source.href=data.sourceUrl;
        result.append(source);
      } else result.append(timestamp(data));
      complete = !data.stale && data.complete !== false;
    } catch {
      result.textContent = label + ' unavailable. ';
    } finally {
      loading = false;
      if (!complete) {
        const retry = element('button','Retry');
        retry.type = 'button';
        retry.addEventListener('click',show);
        result.append(' ',retry);
      }
    }
  }
  details.addEventListener('toggle',show);
  details.append(summary,result);
  return details;
}
function mount(root,{key,title,index,rows,linkFor,request=requestReader,scrollPane}) {
  activePanels.get(root)?.();
  const abort = new AbortController();
  const {signal} = abort;
  const cleanup = () => {
    abort.abort();
    if (activePanels.get(root) === cleanup) activePanels.delete(root);
  };
  activePanels.set(root,cleanup);
  const status = element('p','Checking ILGA…');
  status.setAttribute('role','status');
  root.classList.add('dv-reader');
  root.replaceChildren(element('h2',title),status);
  const scrollTarget = scrollPane || document.scrollingElement;
  const anchors = new Map();
  function remember(link) {
    history.replaceState({...history.state,dvReaderPlace:{
      key,link:link.dataset.readerLink,top:scrollTarget.scrollTop
    }},'');
  }
  root.addEventListener('click',event => {
    const link = event.target.closest('a[data-reader-link]');
    if (link && !event.ctrlKey && !event.metaKey && !event.shiftKey && !event.altKey) remember(link);
  },{signal,capture:true});
  async function render() {
    status.textContent = 'Checking ILGA…';
    try {
      const data = await index(request,signal);
      if (signal.aborted) return;
      const list = element('ul');
      const items = rows(data);
      for (const item of items) {
        const li = element('li');
        const href = linkFor(item.url);
        for (const [position,text] of item.labels.entries()) {
          if (!text) continue;
          const link = element('a',text);
          link.href = href;
          link.dataset.readerLink = item.url+'|'+position;
          anchors.set(link.dataset.readerLink,link);
          li.append(link);
        }
        if (item.meta) li.append(element('span',item.meta));
        li.append(disclosure(item.action,()=>request(item.route,{url:item.url},signal),item.describe));
        list.append(li);
      }
      status.replaceChildren(timestamp(data));
      root.append(items.length ? list : element('p','No entries listed by ILGA.'));
      const place = history.state?.dvReaderPlace;
      if (place?.key === key) {
        const anchor = anchors.get(place.link);
        requestAnimationFrame(()=>{
          if (signal.aborted || !anchor) return;
          scrollTarget.scrollTop = place.top;
          anchor.focus({preventScroll:true});
          const rect=anchor.getBoundingClientRect();
          const box=scrollPane?.getBoundingClientRect();
          if (rect.bottom < (box?.top ?? 0) || rect.top > (box?.bottom ?? innerHeight)) {
            anchor.scrollIntoView({block:'nearest'});
          }
        });
      }
    } catch {
      if (signal.aborted) return;
      const retry = element('button','Retry');
      retry.type = 'button';
      retry.addEventListener('click',render,{once:true});
      status.replaceChildren('Could not load the official list. ',retry);
    }
  }
  void render();
  return cleanup;
}
export function mountBillRange(root,options) {
  return mount(root,{...options,key:'range '+options.url,
    index:(get,signal)=>get('range-index',{url:options.url},signal),
    rows:data=>data.bills.map(row=>({url:row.url,labels:[row.number,row.title],action:'Sponsors',route:'summary',
      describe:({summary})=>{
        const names = [];
        if (summary.senateSponsor) names.push('Senate: '+summary.senateSponsor);
        if (summary.houseSponsor) names.push('House: '+summary.houseSponsor);
        if (summary.sponsorStatus==='unavailable') names.push('Chief sponsor unavailable');
        return names.join(' · ') || (summary.sponsorStatus==='not-applicable'?'Not applicable':'Sponsor unavailable');
      }}))
  });
}
export function mountMemberDirectory(root,options) {
  return mount(root,{...options,key:'members '+options.chamber,
    index:(get,signal)=>get('members',{chamber:options.chamber},signal),
    rows:data=>data.members.map(row=>({url:row.url,labels:[row.name],meta:'District '+row.district,
      action:'Service history',route:'member-service',describe:data=>data.periods.join(' · ')}))
  });
}

export async function requestReader(route,query,signal) {
  const url = new URL('/api/reader/'+route, location.origin);
  url.search = new URLSearchParams(query);
  const response = await fetch(url,{signal});
  if (!response.ok) throw new Error('Official data unavailable');
  return response.json();
}
