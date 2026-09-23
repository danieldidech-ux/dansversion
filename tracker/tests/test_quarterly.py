import unittest
from pathlib import Path
from quarterly import parse_quarterly,parse_schedule
from history import parse_archive
from reports import ReportFormatError

FIX=Path(__file__).parent/'fixtures'
class QuarterlyTests(unittest.TestCase):
 def setUp(self):
  rows,_,_=parse_archive((FIX/'committee-34241.html').read_text(),dict(id='x',name='Daniel Didech Campaign Committee'))
  self.filing=next(r for r in rows if r['report_type']=='D-2 Quarterly Report')
  self.html=(FIX/'quarter-34241.html').read_text()
 def test_official_summary_keeps_cash_investments_and_unitemized_separate(self):
  result=parse_quarterly(self.html,self.filing)
  self.assertEqual(result['summary']['ending_cash'],'189762.56')
  self.assertEqual(result['summary']['cash_and_investments'],'409751.99')
  self.assertEqual(result['summary']['receipts'],'17251.71')
  section=result['sections'][0]
  self.assertEqual(section['itemized'],'6250.00');self.assertEqual(section['unitemized'],'26.00')
  self.assertTrue(section['has_details'])
  self.assertFalse(result['sections'][2]['has_details'])
 def test_reject_wrong_committee_document_and_missing_total(self):
  with self.assertRaises(ReportFormatError):parse_quarterly(self.html,dict(self.filing,committee_name='Other committee'))
  with self.assertRaises(ReportFormatError):parse_quarterly(self.html,dict(self.filing,url=self.filing['url'].split('?')[0]+'?id=wrong'))
  with self.assertRaises(ReportFormatError):parse_quarterly(self.html.replace('lblTotalReceipts"','missing"'),self.filing)
 def test_itemized_values_preserved_and_incomplete_pages_rejected(self):
  section=dict(parse_quarterly(self.html,self.filing)['sections'][0],itemized='1000.00')
  html='''<span id="ContentPlaceHolder1_lblName">Daniel Didech Campaign Committee</span>
<span id="ContentPlaceHolder1_lblReportPeriod">4/1/2026 to 6/30/2026</span>
<table id="ContentPlaceHolder1_gvContributions"><tr><th>Contributor</th><th>Amount</th></tr>
<tr><td>Example donor<br>Example employer</td><td>$1,000.00<br>5/1/2026</td></tr>
<tr><td colspan="2"><table id="ContentPlaceHolder1_gvContributions_GridViewPagerTemplate"><tr><td>1 Total Records</td></tr></table></td></tr></table>'''
  x=parse_schedule(html,self.filing,section,'4/1/2026 to 6/30/2026')
  self.assertEqual(x['total'],1);self.assertEqual(x['entries'][0]['fields'][1]['value'],'$1,000.00\n5/1/2026')
  with self.assertRaises(ReportFormatError):parse_schedule(html.replace('$1,000.00','$500.00'),self.filing,section,'4/1/2026 to 6/30/2026')
  with self.assertRaises(ReportFormatError):parse_schedule(html.replace('1 Total Records','2 Total Records'),self.filing,section,'4/1/2026 to 6/30/2026')
  with self.assertRaises(ReportFormatError):parse_schedule(html,self.filing,section,'1/1/2026 to 3/31/2026')
