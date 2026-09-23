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
 def test_quarter_includes_investments(self):
  quarter=next(r for r in self.rows if r['report_type']=='D-2 Quarterly Report')
  self.assertEqual(parse_quarter((FIX/'quarter-34241.html').read_text(),quarter),'409751.99')
  with self.assertRaises(ReportFormatError):parse_quarter((FIX/'quarter-34241.html').read_text().replace('lblTotalInvest','missing'),quarter)
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
