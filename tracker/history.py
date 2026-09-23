"""Cached historical reports; never inserted into the live notification stream."""
import json, re, threading, time, queue, urllib.parse, logging, shutil, urllib.error
from contextlib import closing
from datetime import datetime
from decimal import Decimal
from archive_source import Source, BASE, safe_url
from reports import Document, Node, ReportFormatError, normalized, parse_a1


def identity(url):
 p=urllib.parse.urlsplit(url); q=urllib.parse.parse_qs(p.query)
 return (q.get('FiledDocID') or q.get('ID') or q.get('id') or [url])[0]

def parse_archive(html, committee):
 doc=Document(html)
 field=lambda s:doc.by_id('ContentPlaceHolder1_'+s).text().strip()
 if normalized(field('lblName'))!=normalized(committee['name']): raise ReportFormatError('Committee identity mismatch')
 table=doc.by_id('ContentPlaceHolder1_gvFiledDocs')
 rows=[]
 for tr in table.all('tr'):
  cells=[n for n in tr.children if isinstance(n,Node) and n.tag=='td']
  if len(cells)!=5: continue
  links=[n for n in cells[0].all('a') if n.attrs.get('href') and not n.attrs['href'].startswith('javascript:')]
  if len(links)!=1: raise ReportFormatError('Unrecognized archive report link')
  url=safe_url(urllib.parse.urljoin(BASE,links[0].attrs['href']))
  published=cells[2].lines()[0]
  filed=datetime.strptime(published,'%m/%d/%Y %I:%M:%S %p').isoformat()
  rows.append(dict(committee_key=committee['id'],committee_name=committee['name'],report_type=' '.join(links[0].text().split()),url=url,
     published_raw=published,filed_at=filed,period=' '.join(cells[1].text().split()),clarification=' '.join(cells[4].text().split()),document_id=identity(url)))
 totals=re.findall(r'(\d[\d,]*)\s+Total Records',table.text())
 if not rows or (totals and len(rows)!=int(totals[-1].replace(',',''))) or (not totals and (len(rows)>5 or any('PageNext' in n.attrs.get('id','') for n in table.all('a')))):
  raise ReportFormatError('Archive is incomplete; refusing to label it complete')
 if len({r['document_id'] for r in rows})!=len(rows): raise ReportFormatError('Duplicate archive identities')
 return rows,field('lblCreationDate'),field('lblCommitteeID')


def unavailable(message,status='unavailable'):
 return dict(status=status,message=message,as_of=None,cash_and_investments=None,a1_total=None,estimated_cash=None)


class History:
 def __init__(self,store):
  self.audit_context={}
  self.store=store;self.tasks=queue.PriorityQueue();self.lock=threading.Lock();self.pending=set();self.promoted=set();self.active=None;self.worker=None;self.counter=0
  self.urls={e['committee']['id']:e['official_url'] for g in store.directory_data['groups'] for e in g['members']+g['pinned'] if e.get('committee') and e.get('official_url')}
  self.urls['1b5ce79b8d1251adaf13eda719fd6d7a']=BASE+'CommitteeDetail.aspx?ID=PFWS3Q4VBrJwLQhAj5bRtQ%3D%3D'
  with closing(store.connect()) as db,db:
   db.executescript('''CREATE TABLE IF NOT EXISTS archive_reports (seq INTEGER PRIMARY KEY AUTOINCREMENT,committee_key TEXT,document_id TEXT,payload TEXT,UNIQUE(committee_key,document_id));
   CREATE INDEX IF NOT EXISTS archive_committee ON archive_reports(committee_key);
   CREATE TABLE IF NOT EXISTS archive_state (committee_key TEXT PRIMARY KEY,checked REAL,source_seq INTEGER,complete INTEGER,payload TEXT,finance TEXT);
   CREATE TABLE IF NOT EXISTS archive_documents (url TEXT PRIMARY KEY,checked REAL,html TEXT);''')
 def document(self,source,url,all_table=None):
  with closing(self.store.connect()) as db:
   row=db.execute('SELECT html FROM archive_documents WHERE url=? AND checked>?',(url,time.time()-3600)).fetchone()
  if row: return row[0]
  html=source.read(url)
  if all_table: html=source.all_rows(url,html,all_table)
  with closing(self.store.connect()) as db,db:
   db.execute('INSERT OR REPLACE INTO archive_documents VALUES (?,?,?)',(url,time.time(),html))
   db.execute('DELETE FROM archive_documents WHERE checked<?',(time.time()-7*86400,))
   while db.execute('SELECT COALESCE(SUM(length(html)),0) FROM archive_documents').fetchone()[0]>120_000_000:
    db.execute('DELETE FROM archive_documents WHERE url=(SELECT url FROM archive_documents ORDER BY checked LIMIT 1)')
  return html
 def schedule(self,key,priority=0):
  with closing(self.store.connect()) as db:
   committee=db.execute('SELECT id,name FROM committees WHERE id=?',(key,)).fetchone()
   state=db.execute('SELECT * FROM archive_state WHERE committee_key=?',(key,)).fetchone()
   latest=db.execute('SELECT COALESCE(MAX(seq),0) FROM filings WHERE committee_key=?',(key,)).fetchone()[0]
  if not committee:return False
  if state and json.loads(state['finance']).get('status')!='loading' and state['checked']>time.time()- (900 if state['complete'] and json.loads(state['finance']).get('status')=='ready' else 300) and state['source_seq']==latest:return True
  with self.lock:
   if key not in self.pending:
    self.pending.add(key);self.counter+=1;self.tasks.put((priority,self.counter,dict(committee),latest))
   elif priority==0 and key!=self.active and key not in self.promoted:
    self.promoted.add(key);self.counter+=1;self.tasks.put((0,self.counter,dict(committee),latest))
   if self.worker is None or not self.worker.is_alive():
    self.worker=threading.Thread(target=self.run,daemon=True);self.worker.start()
  return True
 def run(self):
  while True:
   _,_,committee,latest=self.tasks.get()
   with self.lock:
    if committee['id'] not in self.pending:
     self.tasks.task_done();continue
    self.active=committee['id']
   try:self.refresh(committee,latest)
   except Exception as e:
    logging.getLogger('gunicorn.error').warning('Archive unavailable for %s: %s',committee['id'],type(e).__name__)
    with closing(self.store.connect()) as db,db:
     old=db.execute('SELECT complete,payload FROM archive_state WHERE committee_key=?',(committee['id'],)).fetchone()
     payload=json.loads(old['payload']) if old else {}
     detail=diagnose(e,self.audit_context.get(committee['id'],{}))
     payload.update(status='unavailable',message=detail['reason'],diagnostic=detail)
     db.execute('INSERT OR REPLACE INTO archive_state VALUES (?,?,?,?,?,?)',(committee['id'],time.time(),latest,0,json.dumps(payload),json.dumps(dict(unavailable(detail['reason']),diagnostic=detail))))
   finally:
    with self.lock:
     self.pending.discard(committee['id']);self.promoted.discard(committee['id']);self.active=None
    self.tasks.task_done()
   time.sleep(.5)
 def resolve(self,source,committee):
  if committee['id'] in self.urls:return self.urls[committee['id']]
  state=self.state(committee['id'])
  if state:
   saved=json.loads(state['payload']).get('official_url')
   if saved:return safe_url(saved)
  with closing(self.store.connect()) as db:
   urls=[r[0] for r in db.execute('SELECT url FROM filings WHERE committee_key=? AND url IS NOT NULL ORDER BY seq DESC LIMIT 3',(committee['id'],))]
  for url in urls:
   try:doc=Document(self.document(source,url))
   except Exception:continue
   links=[urllib.parse.urljoin(url,n.attrs['href']) for n in doc.root.all('a') if 'committeedetail.aspx' in n.attrs.get('href','').lower() and normalized(n.text())==normalized(committee['name'])]
   if len(set(links))==1:
    self.urls[committee['id']]=safe_url(links[0]);return links[0]
  url=source.find_committee(committee['name'])
  self.urls[committee['id']]=url
  return url
 def refresh(self,committee,latest):
  if shutil.disk_usage(self.store.directory).free<128*1024*1024:raise ReportFormatError('Insufficient archive storage headroom')
  self.audit_context[committee['id']]=dict(stage='committee_lookup')
  source=Source();url=self.resolve(source,committee)
  self.audit_context[committee['id']]=dict(stage='archive_index',source_url=url)
  html=source.all_rows(url,source.read(url),'gvFiledDocs')
  rows,created,official_id=parse_archive(html,committee)
  payload=dict(status='ready',total=len(rows),creation_date=created,official_id=official_id,official_url=url,message='Complete official report index loaded.')
  with closing(self.store.connect()) as db,db:
   for row in rows:
    db.execute('INSERT INTO archive_reports(committee_key,document_id,payload) VALUES (?,?,?) ON CONFLICT(committee_key,document_id) DO UPDATE SET payload=excluded.payload',(committee['id'],row['document_id'],json.dumps(row)))
   # Publish the verified index before the more expensive financial calculation.
   db.execute('INSERT OR REPLACE INTO archive_state VALUES (?,?,?,?,?,?)',(committee['id'],time.time(),latest,1,json.dumps(payload),json.dumps(unavailable('Calculating from official reports…','loading'))))
  try: finance=self.calculate(source,committee,rows)
  except Exception as exc:
   detail=diagnose(exc,self.audit_context.get(committee['id'],{}))
   finance=dict(unavailable(detail['reason']),diagnostic=detail)
  with closing(self.store.connect()) as db,db:
   db.execute('UPDATE archive_state SET finance=? WHERE committee_key=?',(json.dumps(finance),committee['id']))
 def state(self,key):
  with closing(self.store.connect()) as db: row=db.execute('SELECT * FROM archive_state WHERE committee_key=?',(key,)).fetchone()
  return dict(row) if row else None
 def finance(self,key):
  row=self.state(key)
  return json.loads(row['finance']) if row else unavailable('Loading official reports…','loading')
 def page(self,key,before=None):
  row=self.state(key)
  with closing(self.store.connect()) as db:
   records=[dict(json.loads(r['payload']),seq=-r['seq']) for r in db.execute('SELECT seq,payload FROM archive_reports WHERE committee_key=?',(key,))]
  records.sort(key=lambda r:(r['filed_at'],r['document_id']),reverse=True)
  # Stable archive record IDs act as cursors through the dated order.
  offset=0
  if before is not None:
   positions=[i for i,r in enumerate(records) if r['seq']==before]
   if positions:offset=positions[0]+1
  page=records[offset:offset+50]
  if not records:
   with closing(self.store.connect()) as db:page=[dict(r) for r in db.execute('SELECT * FROM filings WHERE committee_key=? ORDER BY seq DESC LIMIT 50',(key,))]
  status=json.loads(row['payload']) if row else dict(status='loading',message='Loading the official report history…')
  return dict(filings=page,has_more=len(records)>offset+50,next_cursor=page[-1]['seq'] if len(records)>offset+50 else None,history=status)
 def calculate(self,source,committee,rows):
  quarters=[r for r in rows if 'd-2 quarterly' in r['report_type'].lower()]
  if not quarters:return dict(unavailable('No D-2 quarterly report appears in the complete official archive.'),diagnostic=dict(stage='quarter_selection',reason='No D-2 quarterly report appears in the complete official archive.'))
  def period_end(r):
   return datetime.strptime(r['period'].split(' to ')[-1].strip(),'%m/%d/%Y').date().isoformat()
  quarter=max(quarters,key=lambda r:(period_end(r),r['filed_at']))
  end=period_end(quarter)
  self.audit_context[committee['id']]=dict(stage='quarterly_report',source_url=quarter['url'],report_type=quarter['report_type'],filed_at=quarter['filed_at'])
  base=parse_quarter(self.document(source,quarter['url']),quarter)
  result=dict(status='unavailable',as_of=end,cash_and_investments=base,a1_total=None,estimated_cash=None,message='A-1 totals could not be fully verified.')
  a1s=[r for r in rows if r['report_type'].lower().startswith('a-1') and r['filed_at'][:10]>end]
  if any('amend' in r['report_type'].lower() or r['clarification'] for r in a1s):
   result['message']='An A-1 amendment or clarification needs review before an estimate can be shown.'
   result['diagnostic']=dict(stage='a1_amendment',reason=result['message'],reports=[dict(url=r['url'],report_type=r['report_type'],filed_at=r['filed_at'],clarification=r['clarification']) for r in a1s if 'amend' in r['report_type'].lower() or r['clarification']])
   return result
  total=Decimal(0)
  try:
   for report in a1s:
    html=self.document(source,report['url'],'gvA1List')
    detail=parse_a1(html,report)
    total+=sum((Decimal(e['amount']) for e in detail['contributions'] if e['received_date']>end),Decimal(0))
  except Exception as exc:
   logging.getLogger('gunicorn.error').warning('A1 estimate incomplete for %s report %s: %s %s',committee['id'],report['document_id'],type(exc).__name__,str(exc))
   result['diagnostic']=diagnose(exc,dict(stage='a1_report',source_url=report['url'],filed_at=report['filed_at'],report_type=report['report_type']))
   result['message']=result['diagnostic']['reason']
   return result
  result.update(status='ready',a1_total=format(total,'.2f'),estimated_cash=format(Decimal(base)+total,'.2f'),message='Based on the latest quarterly report and A-1 contributions received after quarter end.')
  return result


def parse_quarter(html,report):
 doc=Document(html)
 field=lambda name:doc.by_id('ContentPlaceHolder1_'+name)
 if normalized(field('lblName').text())!=normalized(report['committee_name']): raise ReportFormatError('Quarterly committee mismatch')
 if identity(urllib.parse.urljoin(BASE,field('lnkPrintList').attrs.get('href','')))!=report['document_id']:raise ReportFormatError('Quarterly document mismatch')
 if normalized(field('lblReportPeriod').text())!=normalized(report['period']):raise ReportFormatError('Quarterly period mismatch')
 if 'd-2 quarterly' not in normalized(field('lblReportType').text()):raise ReportFormatError('Not a quarterly report')
 values=[]
 for name in ['lblEndFundsAvail','lblTotalInvest']:
  text=field(name).text().strip()
  if not re.fullmatch(r'-?\$[\d,]+\.\d{2}',text):raise ReportFormatError('Invalid quarterly balance')
  values.append(Decimal(text.replace('$','').replace(',','')))
 return format(sum(values),'.2f')


def diagnose(exc,context):
 if isinstance(exc,ReportFormatError):reason=str(exc)
 elif isinstance(exc,urllib.error.HTTPError):reason='Official source returned HTTP '+str(exc.code)
 elif isinstance(exc,UnicodeDecodeError):reason='Official document encoding could not be read'
 elif isinstance(exc,(TimeoutError,urllib.error.URLError)):reason='Official source request timed out or failed'
 elif isinstance(exc,ValueError):reason='Unrecognized report date or number: '+str(exc)[:160]
 else:reason='Reader error: '+type(exc).__name__
 return dict(context,reason=reason,error_type=type(exc).__name__)
