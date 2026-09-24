"""Curated race comparisons and official statewide PAC balance rankings."""
import hashlib,json,logging,re,threading,time,unicodedata,urllib.parse
from contextlib import closing
from concurrent.futures import ThreadPoolExecutor, as_completed
from history import identity
from datetime import datetime
from decimal import Decimal
from pathlib import Path
from flask import jsonify
from archive_source import Source,BASE,safe_url
from reports import Document,Node,ReportFormatError,normalized

PAC_NOTE='Active Political Action and Independent Expenditure committees, ranked by cash plus investments in their latest electronic reported totals. Candidate and Political Party committees are excluded. Dates can differ. These are reported balances, not estimates including later A-1s. Committees without readable reported balances are excluded. Source: Illinois State Board of Elections.'

def key_for(name):return hashlib.sha256(' '.join(unicodedata.normalize('NFKC',name).casefold().split()).encode()).hexdigest()[:32]
def fields(doc):
 values={n.attrs['name']:n.attrs.get('value','') for n in doc.root.all('input') if n.attrs.get('name') and n.attrs.get('type') in ('hidden','text')}
 for n in doc.root.all('select'):
  selected=next((o for o in n.all('option') if 'selected' in o.attrs),next(n.all('option'),None))
  if selected is not None and n.attrs.get('name'):values[n.attrs['name']]=selected.attrs.get('value','')
 return values

def query(source,page,criteria,table=None):
 url=BASE+page;doc=Document(source.read(url));values=fields(doc)
 values.update({'ctl00$ContentPlaceHolder1$'+k:v for k,v in criteria.items()})
 values['ctl00$ContentPlaceHolder1$btnSubmit']='Search'
 url=urllib.parse.urljoin(url,next(doc.root.all('form')).attrs.get('action',page))
 html=source.read(url,values)
 if table:
  action=next(Document(html).root.all('form')).attrs.get('action',url)
  html=source.all_rows(urllib.parse.urljoin(url,action),html,table)
 return html

def cells(row):return [n for n in row.children if isinstance(n,Node) and n.tag in ('td','th')]
def committee_rows(html):
 table=Document(html).by_id('ContentPlaceHolder1_gvCommittees');rows=[]
 for tr in table.all('tr'):
  cs=cells(tr)
  if len(cs)!=4 or not cs[-1].text().strip().isdigit():continue
  links=[n for n in cs[0].all('a') if 'committeedetail.aspx' in n.attrs.get('href','').lower()]
  if len(links)!=1:raise ReportFormatError('Committee search identity missing')
  name=' '.join(links[0].text().split())
  rows.append(dict(committee=dict(id=key_for(name),name=name),official_id=cs[-1].text().strip(),official_url=safe_url(urllib.parse.urljoin(BASE,links[0].attrs['href']))))
 totals=re.findall(r'(\d[\d,]*)\s+Total Records',table.text())
 if not rows or (totals and len(rows)!=int(totals[-1].replace(',',''))):raise ReportFormatError('Incomplete committee search')
 return rows

def money(value):
 text=value.strip().replace(',','').replace('$','')
 if text.startswith('(') and text.endswith(')'):text='-'+text[1:-1]
 if not re.fullmatch(r'-?\d+\.\d{2}',text):raise ReportFormatError('Unrecognized reported balance')
 return Decimal(text)

class Spotlight:
 def __init__(self,store,history):
  self.store=store;self.history=history;self.lock=threading.Lock()
  self.data=json.loads(Path(__file__).with_name('hot_races.json').read_text())
  with closing(store.connect()) as db,db:
   db.execute('CREATE TABLE IF NOT EXISTS spotlight_cache (key TEXT PRIMARY KEY,checked REAL,payload TEXT)')
  for race in self.data['races']:
   for c in race['candidates']:
    saved=self.cached('candidate:'+c['id'])
    if saved:c.update(saved[1])
    if c.get('committee'):self.register(c)
  saved=self.cached('pac-ranking')
  if saved:
   for c in saved[1]['committees']:self.register(c)
 def cached(self,key):
  with closing(self.store.connect()) as db:row=db.execute('SELECT checked,payload FROM spotlight_cache WHERE key=?',(key,)).fetchone()
  return (row[0],json.loads(row[1])) if row else None
 def save(self,key,payload):
  with closing(self.store.connect()) as db,db:db.execute('INSERT OR REPLACE INTO spotlight_cache VALUES (?,?,?)',(key,time.time(),json.dumps(payload)))
 def register(self,c):
  committee=c['committee']
  with closing(self.store.connect()) as db,db:db.execute('INSERT OR IGNORE INTO committees(id,name) VALUES (?,?)',(committee['id'],committee['name']))
  if c.get('official_url'):self.history.urls[committee['id']]=c['official_url']
 def resolve_candidates(self):
  for race in self.data['races']:
   for c in race['candidates']:
    if not c.get('committee'):
     try:
      source=Source();html=query(source,'CommitteeSearch.aspx',dict(txtCommitteeID=c['official_id']),'gvCommittees')
      matched=[r for r in committee_rows(html) if r['official_id']==c['official_id']]
      if len(matched)!=1:raise ReportFormatError('Candidate committee ID not uniquely matched')
      record=matched[0];doc=Document(source.read(record['official_url']))
      if doc.by_id('ContentPlaceHolder1_lblCommitteeID').text().strip()!=c['official_id']:raise ReportFormatError('Candidate committee ID mismatch')
      if normalized(doc.by_id('ContentPlaceHolder1_lblName').text())!=normalized(record['committee']['name']):raise ReportFormatError('Candidate committee name mismatch')
      self.register(record);self.save('candidate:'+c['id'],record)
      with self.lock:c.update(record)
     except Exception:logging.getLogger('gunicorn.error').exception('Race committee lookup failed for %s',c['id'])
    if c.get('committee'):self.history.schedule(c['committee']['id'],priority=1)
 def races(self):
  with self.lock:result=json.loads(json.dumps(self.data))
  for r in result['races']:
   for c in r['candidates']:
    committee=c.get('committee');c['committee']=committee
    c['finance']=self.history.finance(committee['id']) if committee else None
  return result
 def pacs(self):
  saved=self.cached('pac-ranking')
  if not saved:return dict(status='loading',note=PAC_NOTE,checked_at=None,total=0,committees=[])
  checked,payload=saved
  return dict(payload,status=('partial' if not payload.get('complete') else 'ready' if checked>time.time()-36*3600 else 'stale'),checked_at=checked,note=PAC_NOTE)
 def maintain(self):
  next_pacs=0
  while True:
   try:self.resolve_candidates()
   except Exception:logging.getLogger('gunicorn.error').exception('Race refresh failed')
   if time.time()>=next_pacs:
    try:
     saved=self.cached('pac-ranking')
     if not saved or not saved[1].get('complete') or saved[0]<time.time()-86400:self.refresh_pacs()
     next_pacs=time.time()+900
    except Exception:
     logging.getLogger('gunicorn.error').exception('PAC ranking refresh failed');next_pacs=time.time()+120
   time.sleep(60)
 def refresh_pacs(self):
  members=[]
  for kind in ('Political Action','Independent Expenditure'):
   cached=self.cached('pac-members:'+kind)
   if cached and cached[0]>time.time()-86400:rows=cached[1]
   else:
    rows=committee_rows(query(Source(),'CommitteeSearch.aspx',dict(ddlCommitteeType=kind,chkActive='on'),'gvCommittees'))
    self.save('pac-members:'+kind,rows)
   members.extend(dict(r,committee_type=kind) for r in rows)
  by_id={m['official_id']:m for m in members}
  by_name={}
  for m in members:by_name.setdefault(normalized(m['committee']['name']),[]).append(m)
  reports={}
  for prefix in sorted({m['committee']['name'][0].upper() for m in members}):
   cached=self.cached('pac-totals:'+prefix)
   if cached and cached[0]>time.time()-86400:rows=cached[1]
   else:
    rows=balance_rows(query(Source(),'LatestCommitteeTotalsByLatest.aspx',dict(txtName=prefix,ddlNameSearchType='Starts with',chkActive='on'),'gvLatestCommitteeTotalsList'))
    self.save('pac-totals:'+prefix,rows)
   for row in rows:
    matches=by_name.get(normalized(row['name']),[])
    if len(matches)==1:
     member=matches[0]
     reports[member['committee']['id']]=(member,row)
  if not reports:raise ReportFormatError('No PAC quarterly reports located')
  amounts=[];processed=0;failed=[]
  previous=self.cached('pac-ranking');publish_progress=not previous or not previous[1].get('complete')
  def read(item):
   member,row=item
   report=dict(committee_key=member['committee']['id'],committee_name=member['committee']['name'],url=row['url'],document_id=identity(row['url']),period=row['period'],report_type=row['report_type'])
   balance=self.history.part(Source(),report,quarter=True)
   return dict(member,balance=balance,as_of=row['as_of'])
  def publish(complete):
   ranked=sorted(amounts,key=lambda r:(-Decimal(r['balance']),r['committee']['name'].casefold()))
   top=[dict(r,rank=i+1) for i,r in enumerate(ranked[:100])]
   for c in top:self.register(c)
   self.save('pac-ranking',dict(total=len(ranked),eligible=len(members),processed=processed,report_count=len(reports),excluded=len(members)-len(ranked),complete=complete,committees=top))
  with ThreadPoolExecutor(max_workers=3) as pool:
   futures={pool.submit(read,item):item[0]['committee']['id'] for item in reports.values()}
   for f in as_completed(futures):
    processed+=1
    try:amounts.append(f.result())
    except Exception as exc:failed.append(dict(committee=futures[f],error=str(exc)[:300]))
    if publish_progress and processed%25==0:publish(False)
  if not amounts:raise ReportFormatError('No readable PAC balances')
  publish(True)
  self.save('pac-exceptions',failed)

def balance_rows(html):
 doc=Document(html)
 try:table=doc.by_id('ContentPlaceHolder1_gvLatestCommitteeTotalsList')
 except ReportFormatError:
  if 'no records' in normalized(doc.root.text()) or 'no results' in normalized(doc.root.text()):return []
  raise
 rows=[];count=0
 for tr in table.all('tr'):
  cs=cells(tr)
  if len(cs)!=8 or cs[0].tag!='td':continue
  count+=1
  if 'd-2 quarterly' not in normalized(cs[1].text()):continue
  links=[n for n in cs[1].all('a') if 'd2quarterly.aspx' in n.attrs.get('href','').lower()]
  if len(links)!=1:continue
  period=' '.join(cs[2].text().split())
  end=datetime.strptime(period.split(' to ')[-1],'%m/%d/%Y').date().isoformat()
  rows.append(dict(name=' '.join(cs[0].text().split()),url=safe_url(urllib.parse.urljoin(BASE,links[0].attrs['href'])),period=period,as_of=end,report_type=' '.join(cs[1].text().split())))
 totals=re.findall(r'(\d[\d,]*)\s+Total Records',table.text())
 if totals and count!=int(totals[-1].replace(',','')):raise ReportFormatError('Incomplete latest balance search')
 if not totals and count>10:raise ReportFormatError('Unverified latest balance search count')
 return rows

def routes(app,spotlight):
 @app.get('/v1/hot-races')
 def hot_races():return jsonify(spotlight.races())
 @app.get('/v1/top-pacs')
 def top_pacs():return jsonify(spotlight.pacs())
