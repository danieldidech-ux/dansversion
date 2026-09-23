"""Bounded, shared report-preview loading; never blocks a list on the state site."""
import json, queue, threading, time
from contextlib import closing
from reports import filing_id, ReportFormatError, parse_a1
from quarterly import is_quarter, document_id, parse_quarterly
from launch_features import preview

class SummaryLoader:
 def __init__(self,store,reader):
  self.store=store;self.reader=reader;self.tasks=queue.PriorityQueue(128)
  self.lock=threading.Lock();self.pending=set();self.started=False;self.counter=0
  with closing(store.connect()) as db,db:
   db.execute('CREATE TABLE IF NOT EXISTS summary_previews (identity TEXT PRIMARY KEY, checked REAL NOT NULL, payload TEXT NOT NULL)')
 def key(self,filing):
  try:
   url=filing.get('url') or ''
   identifier=document_id(url) if is_quarter(url) else filing_id(url)
   return json.dumps([filing['committee_key'],'quarterly' if is_quarter(url) else 'a1',identifier])
  except (ValueError,TypeError,KeyError):return None
 def save(self,key,value,status):
  payload=dict(status=status,preview=value)
  with closing(self.store.connect()) as db,db:
   db.execute('INSERT OR REPLACE INTO summary_previews VALUES (?,?,?)',(key,time.time(),json.dumps(payload)))
   db.execute('DELETE FROM summary_previews WHERE identity IN (SELECT identity FROM summary_previews ORDER BY checked DESC LIMIT -1 OFFSET 50000)')
  return payload
 def snapshot(self,filing):
  key=self.key(filing)
  if key is None:
   with closing(self.store.connect()) as db:
    row=db.execute('SELECT payload FROM shared_reports WHERE seq=?',(filing['seq'],)).fetchone()
   value=preview(json.loads(row['payload'])) if row else None
   return dict(status='ready' if value is not None else 'unsupported',preview=value)
  with closing(self.store.connect()) as db:
   row=db.execute('SELECT checked,payload FROM summary_previews WHERE identity=?',(key,)).fetchone()
   if row:
    payload=json.loads(row['payload'])
    if row['checked']>time.time()-(7*86400 if payload['status']=='ready' else 60):return payload
   row=db.execute('SELECT payload FROM shared_reports WHERE seq=?',(filing['seq'],)).fetchone()
   if not row:
    row=db.execute('SELECT payload FROM report_cache WHERE source_url=? AND expires>? ORDER BY expires DESC LIMIT 1',(filing.get('url'),time.time())).fetchone()
  if row:
   value=preview(json.loads(row['payload']))
   if value is not None:return self.save(key,value,'ready')
  return dict(status='loading',preview=None)
 def schedule(self,filing,priority=10):
  key=self.key(filing)
  if key is None or self.snapshot(filing)['status']!='loading':return False
  with self.lock:
   if key in self.pending or self.tasks.full():return False
   self.counter+=1;self.pending.add(key)
   self.tasks.put_nowait((priority,self.counter,key,dict(filing)))
   if not self.started:
    self.started=True
    for _ in range(2):threading.Thread(target=self.run,daemon=True).start()
  return True
 def fetch(self,filing):
  # Financial calculations have often already fetched these exact official pages.
  with closing(self.store.connect()) as db:
   row=db.execute('SELECT html FROM archive_documents WHERE url=? AND checked>?',(filing['url'],time.time()-3600)).fetchone()
  if row:
   try:
    result=(parse_quarterly if is_quarter(filing['url']) else parse_a1)(row['html'],filing)
    self.reader.index(filing,result)
    return result
   except (ValueError,TypeError,KeyError,ReportFormatError):pass
  return self.reader.read(filing)
 def run(self):
  while True:
   _,_,key,filing=self.tasks.get()
   try:
    result=self.snapshot(filing)
    if result['status']=='loading':
     report=self.fetch(filing)
     if 'busy loading' in report.get('message',''):continue
     value=preview(report)
     self.save(key,value,'ready' if value is not None else 'unavailable')
   except Exception:
    try:self.save(key,None,'unavailable')
    except Exception:pass
   finally:
    with self.lock:self.pending.discard(key)
    self.tasks.task_done()
