import json,tempfile,unittest
from decimal import Decimal
from pathlib import Path
from unittest.mock import patch
from app import create_app
from spotlight import committee_rows,balance_rows,ReportFormatError
FIX=Path(__file__).parent/'fixtures'/'spotlight'

class SpotlightTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
  self.app=create_app(self.tmp.name,poll=False);self.spotlight=self.app.config['SPOTLIGHT'];self.client=self.app.test_client()
 def test_races_have_distinct_candidates_and_no_uncontested_seed(self):
  data=self.client.get('/v1/hot-races').json
  self.assertEqual(len(data['races']),17)
  ids=set()
  for race in data['races']:
   self.assertNotIn(race['id'],ids);ids.add(race['id'])
   self.assertEqual(len(race['candidates']),2)
   self.assertEqual({c['party'] for c in race['candidates']},{'Democratic','Republican'})
   for c in race['candidates']:
    if not c['committee']:self.assertIsNone(c['finance'])
  self.assertNotIn('house-63',ids);self.assertNotIn('senate-41',ids)
 def test_no_pac_cache_does_not_present_empty_list_as_complete(self):
  data=self.client.get('/v1/top-pacs').json
  self.assertEqual(data['status'],'loading');self.assertEqual(data['committees'],[])
 def test_incomplete_official_pagination_rejected(self):
  with self.assertRaisesRegex(ReportFormatError,'Incomplete'):committee_rows((FIX/'committees-first-page.html').read_text())
  with self.assertRaisesRegex(ReportFormatError,'Incomplete'):balance_rows((FIX/'totals-first-page.html').read_text())
 def test_complete_tables_parse_report_links_not_rounded_cash(self):
  html=(FIX/'totals-first-page.html').read_text().replace('183 Total Records','10 Total Records')
  rows=balance_rows(html);self.assertEqual(len(rows),10)
  self.assertEqual(rows[0]['as_of'],'2026-06-30');self.assertIn('D2Quarterly.aspx',rows[0]['url']);self.assertNotIn('balance',rows[0])
  html=(FIX/'committees-first-page.html').read_text().replace('1107 Total Records','10 Total Records')
  rows=committee_rows(html);self.assertEqual(len(rows),10);self.assertEqual(rows[0]['official_id'],'15316')
 def test_ranking_uses_verified_cash_plus_investments_and_decimal_order(self):
  members=[dict(committee=dict(id='a',name='Alpha'),official_id='1',official_url='https://www.elections.il.gov/CampaignDisclosure/CommitteeDetail.aspx?ID=a')]
  second=[dict(committee=dict(id='b',name='Beta'),official_id='2',official_url='https://www.elections.il.gov/CampaignDisclosure/CommitteeDetail.aspx?ID=b')]
  self.spotlight.save('pac-members:Political Action',members);self.spotlight.save('pac-members:Independent Expenditure',second)
  for letter,name in [('A','Alpha'),('B','Beta')]:
   self.spotlight.save('pac-totals:'+letter,[dict(name=name,url='https://www.elections.il.gov/CampaignDisclosure/D2Quarterly.aspx?ID='+letter,period='4/1/2026 to 6/30/2026',as_of='2026-06-30',report_type='D-2 Quarterly Report')])
  with patch.object(self.spotlight.history,'part',side_effect=lambda source,report,quarter: '100.01' if report['committee_key']=='a' else '99.99'):
   self.spotlight.refresh_pacs()
  result=self.spotlight.pacs();self.assertEqual(result['status'],'ready')
  self.assertEqual([c['committee']['id'] for c in result['committees']],['a','b'])
  self.assertEqual([c['rank'] for c in result['committees']],[1,2])
 def test_partial_and_stale_snapshots_are_labelled(self):
  self.spotlight.save('pac-ranking',dict(total=1,committees=[],complete=False))
  self.assertEqual(self.spotlight.pacs()['status'],'partial')
