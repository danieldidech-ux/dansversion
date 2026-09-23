import json, tempfile, unittest
from pathlib import Path
from unittest.mock import patch
from contextlib import closing
from app import Store, create_app
from history import History, parse_archive, parse_quarter, unavailable
from reports import Document, ReportFormatError, parse_a1

FIX=Path(__file__).parent/'fixtures'
COM={'id':'1b5ce79b8d1251adaf13eda719fd6d7a','name':'Daniel Didech Campaign Committee'}
class HistoryTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
  self.store=Store(self.tmp.name);self.history=History(self.store)
  self.rows,self.created,self.official=parse_archive((FIX/'committee-34241.html').read_text(),COM)
 def test_complete_archive_and_identity(self):
  self.assertEqual(len(self.rows),359);self.assertEqual(self.created,'11/10/2017');self.assertEqual(self.official,'34241')
  self.assertEqual(self.rows[-1]['filed_at'][:10],'2017-11-13')
  with self.assertRaises(ReportFormatError):parse_archive((FIX/'committee-34241.html').read_text().replace('359 Total Records','360 Total Records'),COM)
  with self.assertRaises(ReportFormatError):parse_archive((FIX/'committee-34241.html').read_text(),dict(COM,name='Other committee'))
 def test_unlinked_correspondence_preserves_complete_archive(self):
  html=(FIX/'committee-34241.html').read_text()
  import re
  html=re.sub(r'<a href="A1List[^>]*>.*?</a>', 'Letter/Correspondence', html, count=1)
  rows,_,_=parse_archive(html,COM)
  self.assertEqual(len(rows),359)
  unlinked=[r for r in rows if r['url'] is None]
  self.assertEqual(len(unlinked),1)
  self.assertEqual(unlinked[0]['report_type'],'Letter/Correspondence')
  with self.assertRaisesRegex(ReportFormatError,'without a downloadable'):
   self.history.document(None,None)
 def test_distinct_unlinked_entries_with_identical_public_metadata(self):
  html=(FIX/'committee-34241.html').read_text()
  import re
  match=re.search(r'<tr[^>]*>\s*<td[^>]*><a href="A1List.*?</tr>',html,re.S)
  row=re.sub(r'<a href="A1List[^>]*>.*?</a>','Letter/Correspondence',match.group())
  html=html[:match.start()]+row+row+html[match.end():]
  html=html.replace('359 Total Records','360 Total Records')
  rows,_,_=parse_archive(html,COM)
  self.assertEqual(len(rows),360)
  unlinked=[r for r in rows if r['url'] is None]
  self.assertEqual(len(unlinked),2)
  self.assertNotEqual(unlinked[0]['document_id'],unlinked[1]['document_id'])
 def test_quarter_includes_investments(self):
  quarter=next(r for r in self.rows if r['report_type']=='D-2 Quarterly Report')
  self.assertEqual(parse_quarter((FIX/'quarter-34241.html').read_text(),quarter),'409751.99')
  with self.assertRaises(ReportFormatError):parse_quarter((FIX/'quarter-34241.html').read_text().replace('lblTotalInvest','missing'),quarter)
 def test_parenthesized_negative_cash_balance(self):
  quarter=next(r for r in self.rows if r['report_type']=='D-2 Quarterly Report')
  html=(FIX/'quarter-34241.html').read_text().replace('$189,762.56','($5,120.27)')
  self.assertEqual(parse_quarter(html,quarter),'214869.16')
 def test_new_committee_zero_baseline_only_without_quarter(self):
  with patch('history.previous_quarter_end',return_value='2026-06-30'),patch.object(self.history,'document',return_value=(FIX/'a1-34241.html').read_text()):
   result=self.history.calculate(None,COM,[self.rows[0]],'7/11/2026')
   self.assertEqual(result['status'],'ready');self.assertEqual(result['estimated_cash'],'1500.00')
   self.assertEqual(result['cash_and_investments'],'0.00');self.assertTrue(result['baseline_assumed'])
   result=self.history.calculate(None,COM,[],'1/1/2020')
   self.assertIsNone(result['estimated_cash'])
 def test_multipage_a1_complete_count(self):
  html=(FIX/'a1-34241-multipage.html').read_text()
  report=json.loads((FIX/'a1-34241-multipage.json').read_text())
  detail=parse_a1(html,report)
  self.assertEqual(len(detail['contributions']),14)
  self.assertEqual(detail['total'],'23500.00')
  with self.assertRaises(ReportFormatError):parse_a1(html.replace('14 Total Records','15 Total Records'),report)
 def test_archive_a1_link_without_rss_id(self):
  detail=parse_a1((FIX/'a1-34241.html').read_text(),self.rows[0])
  self.assertEqual(detail['total'],'1500.00')
 def test_quarter_selection_and_post_period_contributions(self):
  quarters=[r for r in self.rows if 'Quarterly' in r['report_type']]
  rows=quarters+[self.rows[0]]
  # A late amendment for an older quarter must not replace the newest period.
  rows.append(dict(quarters[-1],filed_at='2026-09-23T01:00:00'))
  def doc(source,url,*args):return (FIX/('quarter-34241.html' if 'D2Quarterly' in url else 'a1-34241.html')).read_text()
  with patch.object(self.history,'document',side_effect=doc):result=self.history.calculate(None,COM,rows)
  self.assertEqual(result['estimated_cash'],'411251.99');self.assertEqual(result['as_of'],'2026-06-30')
  with patch.object(self.history,'document',side_effect=doc):
   result=self.history.calculate(None,COM,quarters+[dict(self.rows[0],report_type='A-1 (Amendment)')])
  self.assertIsNone(result['estimated_cash']);self.assertEqual(result['cash_and_investments'],'409751.99')
 def test_history_import_does_not_enqueue_or_pollute_feed(self):
  with patch('history.Source') as source,patch.object(self.history,'calculate',return_value=unavailable('test')):
   source.return_value.all_rows.return_value=(FIX/'committee-34241.html').read_text()
   self.history.refresh(COM,0)
  with closing(self.store.connect()) as db:
   self.assertEqual(db.execute('SELECT count(*) FROM filings').fetchone()[0],0)
   self.assertEqual(db.execute('SELECT count(*) FROM outbox').fetchone()[0],0)
  seen=[];cursor=None
  while True:
   page=self.history.page(COM['id'],cursor);seen+=page['filings']
   if not page['has_more']:break
   cursor=page['next_cursor']
  self.assertEqual(len(seen),359);self.assertEqual(len({r['seq'] for r in seen}),359)
  self.assertTrue(all(r['seq']<0 for r in seen))
  app=create_app(self.tmp.name,poll=False)
  with patch.object(app.config['HISTORY'],'schedule',return_value=True):
   client=app.test_client();data=client.get('/v1/committees/'+COM['id']+'/history').get_json()
   self.assertEqual(data['history']['total'],359)
   self.assertEqual(client.get('/v1/filings/'+str(seen[0]['seq'])).status_code,200)
   self.assertEqual(client.get('/v1/filings/-9999999999999999999999999999').status_code,404)
   self.assertIsNone(client.get('/v1/committees/'+COM['id']+'/finance').get_json()['estimated_cash'])
if __name__=='__main__':unittest.main()

class LookupTests(unittest.TestCase):
 def test_exact_name_only(self):
  from archive_source import exact_committee_link
  html='<a href="CommitteeDetail.aspx?ID=a">Other Committee</a><a href="CommitteeDetail.aspx?ID=b">Daniel Didech Campaign Committee</a>'
  self.assertTrue(exact_committee_link(Document(html),COM['name']).endswith('ID=b'))
  with self.assertRaises(ReportFormatError):exact_committee_link(Document(html+'<a href="CommitteeDetail.aspx?ID=c">Daniel Didech Campaign Committee</a>'),COM['name'])
  with self.assertRaises(ReportFormatError):exact_committee_link(Document(html),'Didech')
