import json,tempfile,threading,unittest
from contextlib import closing
from unittest.mock import Mock,patch
from app import create_app
from reports import ReportReader
from summary_loader import SummaryLoader

class SummaryTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.app=create_app(self.tmp.name,poll=False)
  self.store=self.app.config['STORE'];self.client=self.app.test_client()
  self.loader=SummaryLoader(self.store,ReportReader(self.store))
  self.filing=dict(seq=123,committee_key='committee-one',committee_name='Example',report_type='A-1',url='https://www.elections.il.gov/CampaignDisclosure/A1List.aspx?FiledDocID=example')
  self.report=dict(status='ready',contributions=[dict(contributor='Example Donor',amount='1000.00')],total='1000.00')
 def tearDown(self):self.tmp.cleanup()
 def test_alias_ids_reuse_verified_summary_and_keep_committees_separate(self):
  with closing(self.store.connect()) as db,db:db.execute('INSERT INTO shared_reports VALUES (?,?)',(123,json.dumps(self.report)))
  self.assertEqual(self.loader.snapshot(self.filing)['preview']['total'],'1000.00')
  self.assertEqual(self.loader.snapshot(dict(self.filing,seq=-999))['status'],'ready')
  self.assertEqual(self.loader.snapshot(dict(self.filing,seq=-999,committee_key='different'))['status'],'loading')
 def test_background_deduplicates_and_finishes_without_network_in_request(self):
  started=threading.Event();release=threading.Event();calls=[]
  def fetch(filing):calls.append(filing);started.set();release.wait(5);return self.report
  self.loader.fetch=fetch
  self.assertTrue(self.loader.schedule(self.filing));self.assertTrue(started.wait(2))
  self.assertFalse(self.loader.schedule(dict(self.filing,seq=-999)))
  release.set();self.loader.tasks.join()
  self.assertEqual(len(calls),1)
  self.assertEqual(self.loader.snapshot(dict(self.filing,seq=-999))['status'],'ready')
 def test_failures_back_off_without_fabricating_values(self):
  self.loader.fetch=lambda f:dict(status='unavailable')
  self.loader.schedule(self.filing);self.loader.tasks.join()
  self.assertEqual(self.loader.snapshot(self.filing),dict(status='unavailable',preview=None))
  self.assertFalse(self.loader.schedule(self.filing))
 def test_batch_authenticated_bounded_and_ready_alias(self):
  self.assertEqual(self.client.get('/v1/summary-previews?ids=1').status_code,401)
  headers={'Authorization':'Bearer '+'c'*64};self.client.post('/v1/installations',headers=headers)
  self.assertEqual(self.client.get('/v1/summary-previews?ids='+','.join(map(str,range(51))),headers=headers).status_code,400)
  self.assertEqual(self.client.get('/v1/summary-previews?ids=no',headers=headers).status_code,400)
  with closing(self.store.connect()) as db,db:
   f=dict(self.filing);f.pop('seq')
   db.execute('INSERT INTO archive_reports(seq,committee_key,document_id,payload) VALUES (?,?,?,?)',(999,'committee-one','example',json.dumps(f)))
   db.execute('INSERT INTO shared_reports VALUES (?,?)',(-999,json.dumps(self.report)))
  result=self.client.get('/v1/summary-previews?ids=-999',headers=headers)
  self.assertEqual(result.status_code,200)
  self.assertEqual(result.json['summaries'][0]['preview']['total'],'1000.00')
