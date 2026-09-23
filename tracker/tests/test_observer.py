import json,tempfile,time,unittest
from contextlib import closing
from datetime import datetime
from zoneinfo import ZoneInfo
from unittest.mock import patch,Mock
from decimal import Decimal
from app import create_app,parse_feed
from test_monitor import feed
from observer import index_entries,entity_id,delivery_time,DEFAULTS
from subscriptions import dispatch

class ObserverTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.app=create_app(self.tmp.name,poll=False);self.c=self.app.test_client();self.store=self.app.config['STORE']
  self.auth={'Authorization':'Bearer '+'a'*64};self.other={'Authorization':'Bearer '+'b'*64}
  for h in (self.auth,self.other):self.c.post('/v1/installations',headers=h)
  self.store.ingest(parse_feed(feed(1)));self.key=parse_feed(feed(1))[0]['committee_key']
 def tearDown(self):self.tmp.cleanup()
 def create(self):return self.c.post('/v1/me/lists',headers=self.auth,json={'name':'My races'}).json['id']
 def test_list_isolation_membership_seen_and_delete(self):
  identifier=self.create();base='/v1/me/lists/'+identifier
  self.assertEqual(self.c.put(base,headers=self.other,json={'name':'stolen'}).status_code,404)
  self.assertEqual(self.c.get(base+'/filings',headers=self.other).status_code,404)
  self.assertEqual(self.c.put(base,headers=self.auth,json={'committees':[self.key]}).status_code,200)
  self.c.put('/v1/me/push',headers=self.auth,json={'enabled':True,'token':'f'*64})
  self.store.ingest(parse_feed(feed(2,1)))
  data=self.c.get('/v1/me/lists',headers=self.auth).json['lists'][0];self.assertEqual(data['new_count'],1)
  seq=self.c.get(base+'/filings',headers=self.auth).json['filings'][0]['seq']
  self.c.post(base+'/seen',headers=self.auth,json={'seq':seq});self.assertEqual(self.c.get('/v1/me/lists',headers=self.auth).json['lists'][0]['new_count'],0)
  with closing(self.store.connect()) as db:self.assertEqual(db.execute('SELECT count(*) FROM outbox').fetchone()[0],1)
  self.c.delete(base,headers=self.auth);sender=Mock();dispatch(self.store,sender,enabled=True);sender.send.assert_not_called()
 def filing(self):
  with closing(self.store.connect()) as db:return dict(db.execute('SELECT * FROM filings ORDER BY seq DESC LIMIT 1').fetchone())
 def entry(self,amount='5000.00',name='Example Inc'):
  return dict(contributor=name,address='1 Main St',amount=amount,received_date='2026-09-20',contribution_type='Individual Contribution',description='')
 def test_donor_identity_and_idempotent_index(self):
  f=self.filing();entries=[self.entry()];index_entries(self.store,f,entries);index_entries(self.store,f,entries)
  result=self.c.get('/v1/entities?q=Example').json;self.assertEqual(len(result['entities']),1)
  eid=result['entities'][0]['id'];data=self.c.get('/v1/entities/'+eid).json;self.assertEqual(len(data['disclosures']),1)
  self.assertNotEqual(eid,entity_id('Example Inc','2 Main St'))
  self.assertEqual(self.c.put('/v1/me/donors/'+eid,headers=self.auth,json={'follow':True}).status_code,200)
  self.assertEqual(self.c.get('/v1/me/donors',headers=self.other).json['entities'],[])
  identifier=self.create();self.c.put('/v1/me/lists/'+identifier,headers=self.auth,json={'donors':[eid]})
  self.assertEqual(len(self.c.get('/v1/me/lists/'+identifier+'/filings',headers=self.auth).json['filings']),1)
 def test_threshold_blocks_small_and_unread_reports(self):
  self.c.put('/v1/me/watchlist',headers=self.auth,json={'committees':[self.key]})
  self.c.put('/v1/me/push',headers=self.auth,json={'enabled':True,'token':'f'*64})
  self.c.put('/v1/me/alert-preferences',headers=self.auth,json=dict(DEFAULTS,mode='amount',minimum='1000'))
  self.store.ingest(parse_feed(feed(2,1)));sender=Mock();sender.send.return_value=(200,'')
  dispatch(self.store,sender,enabled=True);sender.send.assert_not_called()
  f=self.filing();index_entries(self.store,f,[self.entry('500')])
  with closing(self.store.connect()) as db,db:db.execute('UPDATE outbox SET next_attempt=0')
  dispatch(self.store,sender,enabled=True);sender.send.assert_not_called()
 def test_rich_alert_and_digest(self):
  self.c.put('/v1/me/watchlist',headers=self.auth,json={'committees':[self.key]});self.c.put('/v1/me/push',headers=self.auth,json={'enabled':True,'token':'f'*64})
  self.store.ingest(parse_feed(feed(3,2,1)));f=self.filing();index_entries(self.store,f,[self.entry()])
  self.c.put('/v1/me/alert-preferences',headers=self.auth,json=dict(DEFAULTS,delivery='morning'))
  # Yesterday's pending reports are eligible for a single combined digest.
  with closing(self.store.connect()) as db,db:db.execute('UPDATE outbox SET created_at=?,next_attempt=0',(time.time()-86400,))
  sender=Mock();sender.send.return_value=(200,'');dispatch(self.store,sender,enabled=True)
  self.assertEqual(sender.send.call_count,1);self.assertEqual(sender.send.call_args[0][0]['digest_count'],2)
  self.assertEqual(len(self.c.get('/v1/me/alerts',headers=self.auth).json['filings']),2)
 def test_preferences_validation(self):
  for patchdata in ({'minimum':'NaN'},{'minimum':'-1'},{'timezone':'Made/up'},{'quiet':True,'quiet_start':7,'quiet_end':7}):
   self.assertEqual(self.c.put('/v1/me/alert-preferences',headers=self.auth,json=dict(DEFAULTS,**patchdata)).status_code,400)
 def test_share_escaping_and_csv_formula_protection(self):
  f=self.filing();entry=self.entry(name='=HYPERLINK("bad")');entry['description']='<script>alert(1)</script>'
  with closing(self.store.connect()) as db,db:db.execute('INSERT INTO report_cache VALUES (?,?,?,?)',(f['seq'],f['url'],time.time()+3600,json.dumps(dict(status='ready',contributions=[entry]))))
  page=self.c.get('/share/filing/'+str(f['seq']));self.assertEqual(page.status_code,200);self.assertNotIn(b'<script>',page.data)
  csv=self.c.get('/share/filing/'+str(f['seq'])+'.csv');self.assertIn(b"'=HYPERLINK",csv.data)
  self.assertEqual(self.c.get('/share/filing/9999999999999999999999999999').status_code,404)
 def test_quiet_hours_and_dst(self):
  tz=ZoneInfo('America/Chicago');now=datetime(2026,11,1,1,30,tzinfo=tz).timestamp()
  p=dict(DEFAULTS,quiet=True,quiet_start=22,quiet_end=7)
  due=datetime.fromtimestamp(delivery_time(p,now,now),tz);self.assertEqual(due.hour,7)
  self.assertEqual(delivery_time(DEFAULTS,now,now),now)

if __name__=='__main__':unittest.main()
