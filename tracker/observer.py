"""Private lists, verified disclosure index, alert preferences and public sharing."""
import csv, hashlib, io, json, re, time, uuid, shutil
from contextlib import closing
from datetime import datetime, timedelta
from decimal import Decimal, InvalidOperation
from zoneinfo import ZoneInfo
from flask import jsonify, request, g, Response, render_template_string

DEFAULTS=dict(mode='all',minimum='0',delivery='instant',quiet=False,quiet_start=22,quiet_end=7,timezone='America/Chicago')

def migrate(db):
 db.executescript('''
 CREATE TABLE IF NOT EXISTS shared_reports(seq INTEGER PRIMARY KEY,payload TEXT NOT NULL);
 CREATE TABLE IF NOT EXISTS shared_schedules(url TEXT PRIMARY KEY,payload TEXT NOT NULL);
 CREATE TABLE IF NOT EXISTS alert_preferences(device_id TEXT PRIMARY KEY,payload TEXT NOT NULL);
 CREATE TABLE IF NOT EXISTS private_lists(id TEXT PRIMARY KEY,device_id TEXT NOT NULL,name TEXT NOT NULL,seen_seq INTEGER NOT NULL DEFAULT 0,created REAL NOT NULL);
 CREATE TABLE IF NOT EXISTS list_members(list_id TEXT NOT NULL,committee_key TEXT NOT NULL,PRIMARY KEY(list_id,committee_key));
 CREATE TABLE IF NOT EXISTS list_entities(list_id TEXT NOT NULL,entity_id TEXT NOT NULL,created REAL NOT NULL,PRIMARY KEY(list_id,entity_id));
 CREATE TABLE IF NOT EXISTS entities(id TEXT PRIMARY KEY,name TEXT NOT NULL,address TEXT NOT NULL);
 CREATE TABLE IF NOT EXISTS entity_follows(device_id TEXT NOT NULL,entity_id TEXT NOT NULL,created REAL NOT NULL,PRIMARY KEY(device_id,entity_id));
 CREATE VIEW IF NOT EXISTS active_entity_follows AS SELECT * FROM entity_follows WHERE 0;
 CREATE VIEW IF NOT EXISTS active_list_entities AS SELECT * FROM list_entities WHERE 0;
 CREATE TABLE IF NOT EXISTS disclosures(id TEXT PRIMARY KEY,entity_id TEXT NOT NULL,committee_key TEXT NOT NULL,committee_name TEXT NOT NULL,seq INTEGER NOT NULL,section TEXT NOT NULL,amount TEXT NOT NULL,date TEXT NOT NULL,kind TEXT NOT NULL,source_url TEXT NOT NULL,payload TEXT NOT NULL);
 CREATE INDEX IF NOT EXISTS disclosure_entity ON disclosures(entity_id,date);
 CREATE INDEX IF NOT EXISTS disclosure_report ON disclosures(seq);
 CREATE TABLE IF NOT EXISTS index_jobs(seq INTEGER PRIMARY KEY,status TEXT NOT NULL DEFAULT 'pending',checked REAL NOT NULL DEFAULT 0,attempts INTEGER NOT NULL DEFAULT 0,message TEXT);
 ''')
 columns={r[1] for r in db.execute('PRAGMA table_info(disclosures)')}
 if 'document_key' not in columns:db.execute("ALTER TABLE disclosures ADD COLUMN document_key TEXT NOT NULL DEFAULT ''")

def index_has_space(store):
 return shutil.disk_usage(store.directory).free >= 128*1024*1024

def normal(s):return ' '.join(s.casefold().split())
def entity_id(name,address):return hashlib.sha256((normal(name)+'\n'+normal(address)).encode()).hexdigest()[:32]
def source_name(name):return re.split(r'\s+(?:Occupation|Employer):',name,maxsplit=1)[0].strip()

def index_entries(store,filing,entries,section='a1'):
 """Keep individual disclosures traceable; never merge identities by similar name."""
 from history import identity
 if not index_has_space(store):return entries
 with closing(store.connect()) as db,db:
  document_key=identity(filing['url']);retained=[]
  for i,e in enumerate(entries):
   name=source_name(e['contributor']);address=e.get('address','');eid=entity_id(name,address)
   rid=hashlib.sha256((filing['committee_key']+'|'+identity(filing['url'])+'|'+section+'|'+str(i)).encode()).hexdigest()[:32]
   db.execute('INSERT OR IGNORE INTO entities VALUES (?,?,?)',(eid,name,address))
   retained.append(rid)
   db.execute('''INSERT INTO disclosures(id,entity_id,committee_key,committee_name,seq,section,amount,date,kind,source_url,payload,document_key)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET entity_id=excluded.entity_id,
    seq=CASE WHEN disclosures.seq>0 THEN disclosures.seq ELSE excluded.seq END,
    amount=excluded.amount,date=excluded.date,kind=excluded.kind,source_url=excluded.source_url,payload=excluded.payload,document_key=excluded.document_key''',
    (rid,eid,filing['committee_key'],filing['committee_name'],filing['seq'],section,e['amount'],e['received_date'],e.get('contribution_type',section),filing['url'],json.dumps(e),document_key))
   e['entity_id']=eid;e['disclosure_id']=rid
  for row in db.execute('SELECT id FROM disclosures WHERE committee_key=? AND document_key=? AND section=?',(filing['committee_key'],document_key,section)).fetchall():
   if row['id'] not in retained:db.execute('DELETE FROM disclosures WHERE id=?',(row['id'],))
 return entries

def index_schedule(store,filing,section,result):
 if result.get('status')!='ready' or not index_has_space(store):return
 entries=[]
 for row in result['entries']:
  fields={f['label']:f['value'] for f in row['fields']}
  name=fields.get('Contributed By') or fields.get('Received By')
  amount=fields.get('Amount','').splitlines()
  if not name or not amount:continue
  try:
   value=Decimal(amount[0].replace('$','').replace(',','').replace('(','-').replace(')',''))
   date=datetime.strptime(amount[1],'%m/%d/%Y').date().isoformat() if len(amount)>1 else ''
  except (ValueError,InvalidOperation):continue
  e=dict(contributor=name,address=fields.get('Address',''),amount=str(value),received_date=date,contribution_type=section,description=fields.get('Description') or fields.get('Purpose/Beneficiary',''))
  entries.append(e)
  row['entity_id']=entity_id(source_name(name),e['address'])
 index_entries(store,filing,entries,section)
 with closing(store.connect()) as db,db:
  db.execute('INSERT OR REPLACE INTO shared_schedules VALUES (?,?)',(result['source_url'],json.dumps(result)))


def index_tick(store):
 """One job per tick, live first. Historical imports never trigger donor alerts."""
 from reports import ReportReader
 from subscriptions import lookup_filing
 if not index_has_space(store):return
 with closing(store.connect()) as db,db:
  db.execute("INSERT OR IGNORE INTO index_jobs(seq) SELECT seq FROM filings WHERE lower(report_type) LIKE 'a-1%' OR lower(report_type) LIKE 'd-2 quarterly%'")
  row=db.execute("SELECT * FROM index_jobs WHERE seq>0 AND status!='ready' AND checked<? ORDER BY (seq>0) DESC, (attempts=0) DESC, seq DESC LIMIT 1",(time.time()-300,)).fetchone()
  if not row:return
  filing=lookup_filing(db,row['seq'])
  db.execute('UPDATE index_jobs SET checked=?,attempts=attempts+1 WHERE seq=?',(time.time(),row['seq']))
 if not filing:return
 filing=dict(filing);reader=ReportReader(store);result=reader.read(filing);ready=result.get('status')=='ready'
 if ready and result.get('kind')=='quarterly':
  for section in result.get('sections',[]):
   if section['has_details'] and section['group'] in ('receipts','in_kind','expenditures'):
    detail=reader.schedule(filing,section['id']);ready=ready and detail.get('status')=='ready'
 with closing(store.connect()) as db,db:
  db.execute('UPDATE index_jobs SET status=?,message=? WHERE seq=?',('ready' if ready else 'unavailable',None if ready else 'Some official details remain unavailable; will retry.',row['seq']))

def preferences(db,device):
 row=db.execute('SELECT payload FROM alert_preferences WHERE device_id=?',(device,)).fetchone()
 return dict(DEFAULTS,**(json.loads(row[0]) if row else {}))

def delivery_time(p,created,now):
 tz=ZoneInfo(p['timezone']);dt=datetime.fromtimestamp(now,tz);origin=datetime.fromtimestamp(created,tz)
 if p['delivery'] in ('morning','evening'):
  hour=8 if p['delivery']=='morning' else 18
  target=origin.replace(hour=hour,minute=0,second=0,microsecond=0)
  if target<=origin:target+=timedelta(days=1)
  if target.timestamp()>now:dt=target
 if p['quiet']:
  start,end=p['quiet_start'],p['quiet_end'];hour=dt.hour
  inside=(start<=hour<end) if start<end else (hour>=start or hour<end)
  if inside:
   target=dt.replace(hour=end,minute=0,second=0,microsecond=0)
   if target<=dt:target+=timedelta(days=1)
   dt=target
 return dt.timestamp() if dt.timestamp()>now+0.001 else now

def alert_summary(db,row,p):
 typ=row['report_type'].lower()
 if p['mode']=='quarterly' and 'd-2 quarterly' not in typ:return False,None
 records=[dict(r) for r in db.execute('SELECT * FROM disclosures WHERE seq=?',(row['filing_seq'],))]
 if p['mode']=='amount':
  if not typ.startswith('a-1'):return False,None
  if not records:return None,None
  records=[r for r in records if Decimal(r['amount'])>=Decimal(p['minimum'])]
  if not records:return False,None
 if not records and typ.startswith('a-1') and time.time()-row['created_at']<120:
  return None,None
 if records and typ.startswith('a-1'):
  total=sum((Decimal(r['amount']) for r in records),Decimal(0))
  name=db.execute('SELECT name FROM entities WHERE id=?',(records[0]['entity_id'],)).fetchone()[0]
  body=f"${total:,.2f} from {name}" if len(records)==1 else f"${total:,.2f} across {len(records)} contributions"
  if len(records)==1:body+=' · '+records[0]['kind']
  return True,body
 return True,row['report_type']


def install_routes(api,store,authenticated,reader):
 @api.before_request
 def retired_donor_history():
  if request.path=='/v1/entities' or request.path.startswith('/v1/entities/') or request.path=='/v1/me/donors' or request.path.startswith('/v1/me/donors/'):
   return jsonify(error='Donor history and donor follows have been removed because coverage and identity matching were incomplete. View contributions within individual reports.'),410

 from subscriptions import lookup_filing
 def lists_data(db):
  rows=[]
  for r in db.execute('SELECT * FROM private_lists WHERE device_id=? ORDER BY name',(g.device['id'],)):
   item=dict(r);item['committees']=[dict(c) for c in db.execute('SELECT c.id,c.name FROM committees c JOIN list_members m ON m.committee_key=c.id WHERE m.list_id=? ORDER BY c.name',(r['id'],))]
   item['donors']=[dict(e) for e in db.execute('SELECT e.* FROM entities e JOIN active_list_entities m ON m.entity_id=e.id WHERE m.list_id=? ORDER BY e.name',(r['id'],))]
   item['new_count']=db.execute('SELECT count(*) FROM filings f WHERE f.seq>? AND (f.committee_key IN (SELECT committee_key FROM list_members WHERE list_id=?) OR f.seq IN (SELECT x.seq FROM disclosures x JOIN active_list_entities m ON m.entity_id=x.entity_id WHERE m.list_id=?))',(r['seen_seq'],r['id'],r['id'])).fetchone()[0];rows.append(item)
  return rows
 @api.get('/v1/me/lists')
 @authenticated
 def lists():
  with closing(store.connect()) as db:return jsonify(lists=lists_data(db))
 @api.post('/v1/me/lists')
 @authenticated
 def create_list():
  data=request.get_json(silent=True)
  if not isinstance(data,dict):return jsonify(error='Invalid list request'),400
  name=data.get('name','');keys=data.get('committees',[])
  if not isinstance(name,str) or not 1<=len(name.strip())<=80:return jsonify(error='Use a list name of 1–80 characters.'),400
  if not isinstance(keys,list) or len(keys)>1000 or any(not isinstance(k,str) for k in keys):return jsonify(error='Invalid committees'),400
  with closing(store.connect()) as db,db:
   db.execute('BEGIN IMMEDIATE')
   if not set(keys)<={r[0] for r in db.execute('SELECT id FROM committees')}:return jsonify(error='Unknown committee'),400
   if db.execute('SELECT count(*) FROM private_lists WHERE device_id=?',(g.device['id'],)).fetchone()[0]>=30:return jsonify(error='Maximum 30 lists.'),400
   identifier=uuid.uuid4().hex;latest=db.execute('SELECT coalesce(max(seq),0) FROM filings').fetchone()[0]
   db.execute('INSERT INTO private_lists VALUES (?,?,?,?,?)',(identifier,g.device['id'],name.strip(),latest,time.time()))
   db.executemany('INSERT INTO list_members VALUES (?,?)',[(identifier,k) for k in set(keys)])
  return jsonify(id=identifier)
 @api.put('/v1/me/lists/<identifier>/committees/<committee>')
 @authenticated
 def set_list_committee(identifier,committee):
  data=request.get_json(silent=True) or {}
  if not isinstance(data,dict) or type(data.get('included')) is not bool:return jsonify(error='Choose whether to include this committee.'),400
  with closing(store.connect()) as db,db:
   db.execute('BEGIN IMMEDIATE')
   if not db.execute('SELECT 1 FROM private_lists WHERE id=? AND device_id=?',(identifier,g.device['id'])).fetchone():return jsonify(error='List not found'),404
   if not db.execute('SELECT 1 FROM committees WHERE id=?',(committee,)).fetchone():return jsonify(error='Committee not found'),404
   if data['included']:
    existing=db.execute('SELECT 1 FROM list_members WHERE list_id=? AND committee_key=?',(identifier,committee)).fetchone()
    if not existing and db.execute('SELECT count(*) FROM list_members WHERE list_id=?',(identifier,)).fetchone()[0]>=1000:return jsonify(error='Maximum 1,000 committees per list.'),400
    db.execute('INSERT OR IGNORE INTO list_members VALUES (?,?)',(identifier,committee))
   else:
    db.execute('DELETE FROM list_members WHERE list_id=? AND committee_key=?',(identifier,committee))
    from subscriptions import prune_unmatched
    prune_unmatched(db,g.device['id'])
  return jsonify(ok=True)
 @api.put('/v1/me/lists/<identifier>')
 @authenticated
 def edit_list(identifier):
  data=request.get_json(silent=True) or {};keys=data.get('committees');name=data.get('name');donors=data.get('donors')
  if donors:return jsonify(error='Donor lists are no longer supported. Lists can contain committees.'),410
  with closing(store.connect()) as db,db:
   if not db.execute('SELECT 1 FROM private_lists WHERE id=? AND device_id=?',(identifier,g.device['id'])).fetchone():return jsonify(error='List not found'),404
   # Validate the whole edit before making any mutation.
   if name is not None and (not isinstance(name,str) or not 1<=len(name.strip())<=80):return jsonify(error='Invalid name'),400
   for values,table in ((keys,'committees'),(donors,'entities')):
    if values is not None:
     if not isinstance(values,list) or len(values)>1000 or any(not isinstance(k,str) for k in values):return jsonify(error='Invalid members'),400
     if not set(values)<={r[0] for r in db.execute('SELECT id FROM '+table)}:return jsonify(error='Unknown members'),400
   if name is not None:
    if not isinstance(name,str) or not 1<=len(name.strip())<=80:return jsonify(error='Invalid name'),400
    db.execute('UPDATE private_lists SET name=? WHERE id=?',(name.strip(),identifier))
   if keys is not None:
    if not isinstance(keys,list) or len(keys)>1000 or any(not isinstance(k,str) for k in keys):return jsonify(error='Invalid committees'),400
    known={r[0] for r in db.execute('SELECT id FROM committees')}
    if not set(keys)<=known:return jsonify(error='Unknown committee'),400
    db.execute('DELETE FROM list_members WHERE list_id=?',(identifier,));db.executemany('INSERT INTO list_members VALUES (?,?)',[(identifier,k) for k in set(keys)])
   if donors is not None:
    if not isinstance(donors,list) or len(donors)>1000 or any(not isinstance(k,str) for k in donors):return jsonify(error='Invalid donors'),400
    known={r[0] for r in db.execute('SELECT id FROM entities')}
    if not set(donors)<=known:return jsonify(error='Unknown donor'),400
    existing={r['entity_id']:r['created'] for r in db.execute('SELECT entity_id,created FROM list_entities WHERE list_id=?',(identifier,))}
    db.execute('DELETE FROM list_entities WHERE list_id=?',(identifier,));db.executemany('INSERT INTO list_entities VALUES (?,?,?)',[(identifier,k,existing.get(k,time.time())) for k in set(donors)])
  return jsonify(ok=True)
 @api.delete('/v1/me/lists/<identifier>')
 @authenticated
 def remove_list(identifier):
  with closing(store.connect()) as db,db:
   if not db.execute('SELECT 1 FROM private_lists WHERE id=? AND device_id=?',(identifier,g.device['id'])).fetchone():return jsonify(error='List not found'),404
   db.execute('DELETE FROM list_entities WHERE list_id=?',(identifier,))
   db.execute('DELETE FROM list_members WHERE list_id=?',(identifier,));db.execute('DELETE FROM private_lists WHERE id=?',(identifier,))
  return jsonify(ok=True)
 @api.get('/v1/me/lists/<identifier>/filings')
 @authenticated
 def list_filings(identifier):
  try:before=int(request.args.get('before',2**63-1));assert 0<before<=2**63-1
  except (ValueError,AssertionError):return jsonify(error='Invalid cursor'),400
  with closing(store.connect()) as db:
   row=db.execute('SELECT * FROM private_lists WHERE id=? AND device_id=?',(identifier,g.device['id'])).fetchone()
   if not row:return jsonify(error='List not found'),404
   result=[dict(r) for r in db.execute('SELECT f.* FROM filings f WHERE f.seq<? AND (f.committee_key IN (SELECT committee_key FROM list_members WHERE list_id=?) OR f.seq IN (SELECT x.seq FROM disclosures x JOIN active_list_entities m ON m.entity_id=x.entity_id WHERE m.list_id=?)) ORDER BY f.seq DESC LIMIT 51',(before,identifier,identifier))]
   return jsonify(filings=result[:50],has_more=len(result)>50,next_cursor=result[49]['seq'] if len(result)>50 else None,seen_seq=row['seen_seq'])
 @api.post('/v1/me/lists/<identifier>/seen')
 @authenticated
 def seen(identifier):
  value=(request.get_json(silent=True) or {}).get('seq')
  if type(value)!=int or not 0<=value<=2**63-1:return jsonify(error='Invalid sequence'),400
  with closing(store.connect()) as db,db:db.execute('UPDATE private_lists SET seen_seq=max(seen_seq,?) WHERE id=? AND device_id=?',(value,identifier,g.device['id']))
  return jsonify(ok=True)
 @api.get('/v1/me/alert-preferences')
 @authenticated
 def get_preferences():
  with closing(store.connect()) as db:return jsonify(preferences(db,g.device['id']))
 @api.put('/v1/me/alert-preferences')
 @authenticated
 def put_preferences():
  data=request.get_json(silent=True) or {};p={k:data.get(k,v) for k,v in DEFAULTS.items()}
  try:
   assert p['mode'] in ('all','quarterly','amount') and p['delivery'] in ('instant','morning','evening')
   assert type(p['quiet'])==bool and all(type(p[k])==int and 0<=p[k]<24 for k in ('quiet_start','quiet_end'))
   assert not p['quiet'] or p['quiet_start']!=p['quiet_end']
   amount=Decimal(str(p['minimum']));assert amount.is_finite() and 0<=amount<=10**12;p['minimum']=str(amount)
   ZoneInfo(p['timezone'])
  except Exception:return jsonify(error='Check the amount, quiet hours, and time zone.'),400
  with closing(store.connect()) as db,db:
   db.execute('INSERT OR REPLACE INTO alert_preferences VALUES (?,?)',(g.device['id'],json.dumps(p)))
   db.execute("UPDATE outbox SET next_attempt=? WHERE device_id=? AND state='pending'",(time.time(),g.device['id']))
  return jsonify(ok=True)
 @api.get('/v1/entities')
 def entities():
  query=request.args.get('q','').strip()[:200]
  with closing(store.connect()) as db:
   rows=[dict(r) for r in db.execute('SELECT * FROM entities WHERE instr(lower(name),lower(?))>0 ORDER BY name,address LIMIT 101',(query,))]
   counts=dict(db.execute('SELECT status,count(*) FROM index_jobs GROUP BY status').fetchall())
  paused=" Indexing paused to preserve storage for live filings." if not index_has_space(store) else ""
  return jsonify(entities=rows[:100],has_more=len(rows)>100,coverage=paused+f"{counts.get('ready',0)} reports indexed; {sum(v for k,v in counts.items() if k!='ready')} pending or unavailable. Search covers imported disclosures, not the complete statewide archive.")
 @api.get('/v1/entities/<identifier>')
 def entity(identifier):
  try:offset=int(request.args.get('offset',0));assert 0<=offset<=1000000
  except (ValueError,AssertionError):return jsonify(error='Invalid offset'),400
  with closing(store.connect()) as db:
   person=db.execute('SELECT * FROM entities WHERE id=?',(identifier,)).fetchone()
   if not person:return jsonify(error='Donor or payee not found'),404
   rows=[dict(r) for r in db.execute('SELECT * FROM disclosures WHERE entity_id=? ORDER BY date DESC,id LIMIT 51 OFFSET ?',(identifier,offset))]
   committee=db.execute('SELECT id,name FROM committees WHERE lower(name)=lower(?)',(person['name'],)).fetchall()
  return jsonify(entity=dict(person),disclosures=rows[:50],has_more=len(rows)>50,next_offset=offset+50,committee=dict(committee[0]) if len(committee)==1 else None,coverage='Exact normalized name and address match. Different addresses remain separate. These are disclosures, not unique transactions: A-1s can reappear in quarterly reports, and amendments may restate entries. No combined dollar total is inferred.')
 @api.get('/v1/me/alerts')
 @authenticated
 def alert_inbox():
  try:before=int(request.args.get('before',2**63-1));assert 0<before<=2**63-1
  except (ValueError,AssertionError):return jsonify(error='Invalid cursor'),400
  with closing(store.connect()) as db:
   rows=[dict(r) for r in db.execute("SELECT f.* FROM filings f JOIN outbox o ON o.filing_seq=f.seq WHERE o.device_id=? AND o.state='sent' AND f.seq<? ORDER BY f.seq DESC LIMIT 51",(g.device['id'],before))]
  return jsonify(filings=rows[:50],has_more=len(rows)>50,next_cursor=rows[49]['seq'] if len(rows)>50 else None)
 @api.get('/v1/me/donors')
 @authenticated
 def followed_donors():
  with closing(store.connect()) as db:return jsonify(entities=[dict(r) for r in db.execute('SELECT e.* FROM entities e JOIN active_entity_follows f ON f.entity_id=e.id WHERE f.device_id=? ORDER BY e.name',(g.device['id'],))])
 @api.put('/v1/me/donors/<identifier>')
 @authenticated
 def follow_donor(identifier):
  follow=(request.get_json(silent=True) or {}).get('follow')
  if type(follow)!=bool:return jsonify(error='Invalid follow setting'),400
  with closing(store.connect()) as db,db:
   if not db.execute('SELECT 1 FROM entities WHERE id=?',(identifier,)).fetchone():return jsonify(error='Unknown donor'),404
   if follow:db.execute('INSERT OR IGNORE INTO entity_follows VALUES (?,?,?)',(g.device['id'],identifier,time.time()))
   else:db.execute('DELETE FROM entity_follows WHERE device_id=? AND entity_id=?',(g.device['id'],identifier))
  return jsonify(ok=True)
 @api.get('/share/filing/<int(signed=True):seq>')
 def share_filing(seq):
  if abs(seq)>2**63-1:return 'Not found',404
  with closing(store.connect()) as db:
   filing=lookup_filing(db,seq)
   cache=db.execute('SELECT payload FROM shared_reports WHERE seq=?',(seq,)).fetchone()
  if not filing:return 'Not found',404
  detail=json.loads(cache[0]) if cache else {};rows=detail.get('contributions',[])
  return render_template_string(SHARE,filing=dict(filing),detail=detail,rows=rows,seq=seq)
 @api.get('/share/filing/<int(signed=True):seq>.csv')
 def export_filing(seq):
  if abs(seq)>2**63-1:return 'Not found',404
  with closing(store.connect()) as db:
   filing=lookup_filing(db,seq);cache=db.execute('SELECT payload FROM shared_reports WHERE seq=?',(seq,)).fetchone()
   section=request.args.get('section');payload=json.loads(cache[0]) if cache else {}
   if section:
    sec=next((s for s in payload.get('sections',[]) if s['id']==section),None)
    cached=db.execute('SELECT payload FROM shared_schedules WHERE url=?',(sec['source_url'],)).fetchone() if sec else None
    payload=json.loads(cached[0]) if cached else {}
  if not filing:return 'Not found',404
  if payload.get('status')!='ready':return 'Open this report or schedule in the app first to prepare verified export data.',409
  output=io.StringIO();writer=csv.writer(output)
  def safe(value):
   s=str(value if value is not None else '')
   return "'"+s if s.lstrip().startswith(('=','+','-','@','\t','\r')) else s
  def write(row):writer.writerow([safe(v) for v in row])
  write(['Committee','Report type','Filed','Official source']);write([filing['committee_name'],filing['report_type'],filing['published_raw'],filing['url']]);write([])
  if payload.get('entries'):
   write([f['label'] for f in payload['entries'][0]['fields']])
   for e in payload['entries']:write([f['value'] for f in e['fields']])
  elif payload.get('contributions'):
   keys=['contributor','amount','received_date','contribution_type','address','description','vendor'];write(keys)
   for e in payload['contributions']:write([e.get(k,'') for k in keys])
  else:
   write(['Summary field','Amount'])
   for k,v in payload.get('summary',{}).items():write([k,v])
  return Response('\ufeff'+output.getvalue(),mimetype='text/csv',headers={'Content-Disposition':f'attachment; filename="Illinois-report-{seq}.csv"'})
 @api.get('/share/transaction/<identifier>')
 def share_transaction(identifier):
  with closing(store.connect()) as db:
   row=db.execute('SELECT d.*,e.name FROM disclosures d JOIN entities e ON e.id=d.entity_id WHERE d.id=?',(identifier,)).fetchone()
  if not row:return 'Not found',404
  return render_template_string(TRANSACTION,row=dict(row))

SHARE='''<!doctype html><html lang="en"><link rel="icon" href="/static/brand/mark.png"><meta property="og:site_name" content="Checks &amp; Balances"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{{filing.committee_name}} · Checks &amp; Balances</title><meta property="og:title" content="{{filing.committee_name}} · {{filing.report_type}}"><meta property="og:description" content="Filed {{filing.published_raw}}. {% if detail.total %}Reported value: ${{detail.total}}.{% endif %} View the filing and official source."><style>body{font:17px system-ui;background:#f7f6f1;color:#092c44;max-width:760px;margin:40px auto;padding:20px}article{background:white;border-radius:18px;padding:24px;margin:18px 0}h1{font-size:30px}a{color:#007b89}dt{margin-top:12px}dd{margin-left:0;font-weight:bold}.brand{display:flex;align-items:center;gap:14px;margin-bottom:28px}.brand img{border-radius:13px;flex-shrink:0}.brand strong{font-size:20px;letter-spacing:-.5px}.brand small{display:block;font-size:12px;line-height:1.5;color:#536675;margin-top:3px}a{color:#007b89;text-underline-offset:3px}footer{font-size:13px;line-height:1.6;color:#536675}article{border:1px solid #e4e9e8;box-shadow:0 2px 8px #092c4408}h1,h2{overflow-wrap:anywhere}dd{font-variant-numeric:tabular-nums}@media(prefers-color-scheme:dark){body{background:#0b1c27;color:#f7f5ee}article{background:#142d3a;border-color:#264553}.brand small,footer{color:#b4c8d1}a{color:#83dee4}}</style><main><header class="brand"><img src="/static/brand/mark.png" alt="C&amp;B Capitol dome logo" width="56" height="56"><div><strong>Checks &amp; Balances</strong><small>The Unofficial Authority on Illinois Campaign Finance</small></div></header><h1>{{filing.committee_name}}</h1><p>{{filing.report_type}} · Filed {{filing.published_raw}}</p><p>{{detail.period or ''}}</p>{% for r in rows %}<article><h2>${{r.amount}} from {{r.contributor}}</h2><p>{{r.contribution_type}} · Received {{r.received_date}}</p><p>{{r.description}}</p></article>{% endfor %}{% if detail.summary %}<article><dl>{% for key,value in detail.summary.items() %}<dt>{{key|replace('_',' ')|title}}</dt><dd>${{value}}</dd>{% endfor %}</dl></article>{% endif %}{% if not rows and not detail.summary %}<p>Report details have not been prepared yet. View the official filing below.</p>{% endif %}<p><a href="{{filing.url}}">View official report</a> · <a href="/share/filing/{{seq}}.csv">Download CSV</a></p><footer>Independent report viewer. Source: Illinois State Board of Elections. No app or account required. Disclosures may include amendments; amounts are not necessarily current balances.</footer></main></html>'''
TRANSACTION='''<!doctype html><html lang="en"><link rel="icon" href="/static/brand/mark.png"><meta property="og:site_name" content="Checks &amp; Balances"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{{row.name}} · Checks &amp; Balances</title><style>body{font:18px system-ui;color:#092c44;background:#f7f6f1;max-width:680px;margin:40px auto;padding:24px}article{background:white;padding:24px;border-radius:18px}.brand{display:flex;align-items:center;gap:14px;margin-bottom:28px}.brand img{border-radius:13px;flex-shrink:0}.brand strong{font-size:20px;letter-spacing:-.5px}.brand small{display:block;font-size:12px;line-height:1.5;color:#536675;margin-top:3px}a{color:#007b89;text-underline-offset:3px}footer{font-size:13px;line-height:1.6;color:#536675}article{border:1px solid #e4e9e8;box-shadow:0 2px 8px #092c4408}h1,h2{overflow-wrap:anywhere}dd{font-variant-numeric:tabular-nums}@media(prefers-color-scheme:dark){body{background:#0b1c27;color:#f7f5ee}article{background:#142d3a;border-color:#264553}.brand small,footer{color:#b4c8d1}a{color:#83dee4}}</style><article><header class="brand"><img src="/static/brand/mark.png" alt="C&amp;B Capitol dome logo" width="56" height="56"><div><strong>Checks &amp; Balances</strong><small>The Unofficial Authority on Illinois Campaign Finance</small></div></header><h1>${{row.amount}}</h1><h2>{{row.name}}</h2><p>{{row.kind}} · {{row.date}}</p><p>Reported by {{row.committee_name}}</p><a href="/share/filing/{{row.seq}}">View filing</a> · <a href="{{row.source_url}}">Official source</a><p>A reported disclosure; may also appear in other reports or amendments.</p></article></html>'''

