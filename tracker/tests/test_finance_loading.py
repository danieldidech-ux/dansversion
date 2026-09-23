import json, tempfile, threading, time, unittest
from contextlib import closing
from pathlib import Path
from unittest.mock import patch
from app import Store
from history import History, unavailable
from reports import ReportFormatError

FIX=Path(__file__).parent/'fixtures'
COM={'id':'1b5ce79b8d1251adaf13eda719fd6d7a','name':'Daniel Didech Campaign Committee'}
READY=dict(unavailable('Verified'),status='ready',estimated_cash='123.45')

class FinanceLoadingTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
  self.store=Store(self.tmp.name);self.history=History(self.store)
 def save(self,finance,checked=1):
  with closing(self.store.connect()) as db,db:
   db.execute('INSERT OR REPLACE INTO archive_state VALUES (?,?,?,?,?,?)',(COM['id'],checked,0,1,json.dumps({'status':'ready'}),json.dumps(finance)))
 def test_every_category_warmed_in_interleaved_order_and_shared_members_deduped(self):
  self.store.directory_data={'groups':[{'pinned':[],'members':[{'committee':{'id':key}} for key in keys]} for keys in [['a','b','shared'],['c','shared'],['d'],['e'],['f']]]}
  with patch.object(self.history,'schedule') as schedule:
   self.history.warm_directory()
  self.assertEqual([c.args[0] for c in schedule.call_args_list],['a','c','d','e','f','b','shared'])
 def test_parallel_workers_deduplicate_and_promote_without_overlapping_same_committee(self):
  started=threading.Event();release=threading.Event();lock=threading.Lock();calls=[];active=set();peak=[0]
  with closing(self.store.connect()) as db,db:
   for key in ['x','y','z']:db.execute('INSERT INTO committees VALUES (?,?)',(key,key))
  def refresh(committee,latest):
   with lock:
    self.assertNotIn(committee['id'],active);active.add(committee['id']);calls.append(committee['id']);peak[0]=max(peak[0],len(active))
    if len(active)==2:started.set()
   release.wait(3)
   with lock:active.remove(committee['id'])
  with patch.object(self.history,'refresh',side_effect=refresh):
   self.history.schedule('x',1);self.history.schedule('y',1)
   self.assertTrue(started.wait(2))
   self.history.schedule('z',1);self.history.schedule('z',0);self.history.schedule('x',0)
   release.set();self.history.tasks.join()
  self.assertEqual(sorted(calls),['x','y','z']);self.assertEqual(peak[0],2)
  self.assertEqual(self.history.pending,set());self.assertEqual(self.history.active,set())
 def test_refresh_keeps_verified_balance_until_new_calculation_finishes(self):
  self.save(READY)
  def calculate(*args):
   interim=self.history.finance(COM['id'])
   self.assertEqual(interim['estimated_cash'],'123.45');self.assertEqual(interim['checked_at'],1)
   self.assertTrue(interim['refreshing'])
   return dict(READY,estimated_cash='678.90')
  with patch('history.Source') as source,patch.object(self.history,'calculate',side_effect=calculate):
   source.return_value.all_rows.return_value=(FIX/'committee-34241.html').read_text()
   self.history.refresh(COM,0)
  final=self.history.finance(COM['id']);self.assertEqual(final['estimated_cash'],'678.90');self.assertGreater(final['checked_at'],1)
 def test_failure_retains_saved_value_and_timestamp_but_marks_it_stale(self):
  self.save(READY)
  with patch('history.Source') as source,patch.object(self.history,'calculate',return_value=unavailable('Source timed out')):
   source.return_value.all_rows.return_value=(FIX/'committee-34241.html').read_text()
   self.history.refresh(COM,0)
  final=self.history.finance(COM['id']);self.assertEqual(final['estimated_cash'],'123.45');self.assertTrue(final['stale']);self.assertEqual(final['checked_at'],1)
 def test_obsolete_calculation_never_displayed_as_verified_during_refresh(self):
  self.save(dict(READY,calculation_version=1))
  def calculate(*args):
   self.assertIsNone(self.history.finance(COM['id'])['estimated_cash'])
   return unavailable('No verified calculation')
  with patch('history.Source') as source,patch.object(self.history,'calculate',side_effect=calculate):
   source.return_value.all_rows.return_value=(FIX/'committee-34241.html').read_text()
   self.history.refresh(COM,0)
 def test_verified_parts_reused_but_metadata_changes_and_expiry_revalidate(self):
  report={'url':'https://www.elections.il.gov/CampaignDisclosure/A1List.aspx?ID=x','committee_key':'x','document_id':'x','period':'current'}
  with patch.object(self.history,'document',return_value='html') as document,patch('history.parse_a1',return_value={'total':'100.00'}) as parse:
   self.history.part(None,report);self.history.part(None,report)
   self.assertEqual(document.call_count,1);self.assertEqual(parse.call_count,1)
   self.history.part(None,dict(report,period='changed'));self.assertEqual(parse.call_count,2)
   with closing(self.store.connect()) as db,db:db.execute('UPDATE archive_finance_parts SET checked=0')
   self.history.part(None,report);self.assertEqual(parse.call_count,3)
  with patch.object(self.history,'document',return_value='invalid'),patch('history.parse_a1',side_effect=ReportFormatError('bad')) as parse:
   for _ in range(2):
    with self.assertRaises(ReportFormatError):self.history.part(None,dict(report,document_id='invalid'))
   self.assertEqual(parse.call_count,2)
 def test_new_filing_invalidates_even_fresh_balance_and_stale_retries_earlier(self):
  self.save(READY,time.time())
  with patch('history.threading.Thread') as thread:
   thread.return_value.is_alive.return_value=True
   self.history.schedule(COM['id']);self.assertFalse(self.history.pending)
   with closing(self.store.connect()) as db,db:
    db.execute('INSERT INTO filings(guid,committee_key,committee_name,report_type,source,first_seen,baseline) VALUES (?,?,?,?,?,?,?)',('new',COM['id'],COM['name'],'A-1','test',time.time(),0))
   self.history.schedule(COM['id']);self.assertIn(COM['id'],self.history.pending)
