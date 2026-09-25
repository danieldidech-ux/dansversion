import json,tempfile,unittest
from contextlib import closing
from app import create_app,parse_feed
from test_monitor import feed
from launch_features import preview

class LaunchTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.app=create_app(self.tmp.name,poll=False);self.c=self.app.test_client();self.store=self.app.config['STORE']
  self.auth={'Authorization':'Bearer '+'d'*64};self.other={'Authorization':'Bearer '+'e'*64}
  for h in (self.auth,self.other):self.c.post('/v1/installations',headers=h)
 def tearDown(self):self.tmp.cleanup()
 def test_verified_preview_and_absent_numbers(self):
  self.assertIsNone(preview({'status':'unavailable','total':'999'}))
  self.assertEqual(preview({'status':'ready','kind':'quarterly','summary':{'ending_cash':'0.00'}})['ending_cash'],'0.00')
  self.assertIsNone(preview({'status':'ready','kind':'quarterly','summary':{}})['receipts'])
 def test_preview_cleans_metadata_without_rewriting_disclosure(self):
  report={'status':'ready','total':'1000','contributions':[{'contributor':'Smith, Jane Occupation: Director Employer: Example','contribution_type':'In-kind Contribution'}]}
  result=preview(report)
  self.assertEqual(result['contributors'],['Smith, Jane']);self.assertTrue(result['includes_in_kind'])
  self.assertIn('Occupation:',report['contributions'][0]['contributor'])
 def test_feed_previews_use_only_verified_source_report(self):
  self.store.ingest(parse_feed(feed(2,1)))
  with closing(self.store.connect()) as db,db:
   seq=db.execute('SELECT max(seq) FROM filings').fetchone()[0]
   report={'status':'ready','total':'39223.24','contributions':[{'contributor':'Illinois Republican Party'}]}
   db.execute('INSERT INTO shared_reports VALUES (?,?)',(seq,json.dumps(report)))
  data=self.c.get('/v1/filings').json['filings']
  self.assertEqual(data[0]['preview']['total'],'39223.24');self.assertIsNone(data[1]['preview'])
  self.assertEqual(data[0]['preview']['contributors'],['Illinois Republican Party'])
 def test_problem_report_private_validated_rate_limited_and_deleted(self):
  body={'category':'Incorrect data','message':'The report amount appears incorrect.','context':{'filing_id':'123'}}
  self.assertEqual(self.c.post('/v1/me/problems',json=body).status_code,401)
  for _ in range(5):self.assertEqual(self.c.post('/v1/me/problems',headers=self.auth,json=body).status_code,201)
  self.assertEqual(self.c.post('/v1/me/problems',headers=self.auth,json=body).status_code,429)
  self.assertEqual(len(self.c.get('/v1/me/problems',headers=self.auth).json['reports']),5)
  self.assertEqual(self.c.get('/v1/me/problems',headers=self.other).json['reports'],[])
  self.assertEqual(self.c.post('/v1/me/problems',headers=self.other,json=dict(body,message='x')).status_code,400)
  self.c.delete('/v1/me',headers=self.auth)
  with closing(self.store.connect()) as db:self.assertEqual(db.execute('SELECT count(*) FROM problem_reports').fetchone()[0],0)

 def test_quarterly_preview_combined_balance(self):
  result=preview({'status':'ready','kind':'quarterly','summary':{'beginning_cash':'188685.01','ending_cash':'189762.56','investments':'250000.00','cash_and_investments':'439762.56'}})
  self.assertEqual(result['beginning_cash'],'188685.01')
  self.assertIsNone(preview({'status':'ready','kind':'quarterly','summary':{}})['beginning_cash'])
  self.assertEqual(result['cash_and_investments'],'439762.56')
  self.assertEqual(result['ending_cash'],'189762.56')
  self.assertIsNone(preview({'status':'ready','kind':'quarterly','summary':{'ending_cash':'189762.56'}})['cash_and_investments'])
