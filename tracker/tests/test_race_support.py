import unittest
from unittest.mock import Mock
from archive_source import OfficialPDFError
from race_support import calculate, schedule_receipt, ReportFormatError

def report(id,kind='D-2 Quarterly Report',period='4/1/2026 to 6/30/2026',filed='2026-07-15T10:00:00'):
 return dict(document_id=id,report_type=kind,period=period,filed_at=filed,url='https://www.elections.il.gov/CampaignDisclosure/D2Quarterly.aspx?ID='+id,clarification='')
def quarter(total='100.00',itemized=None,period='4/1/2026 to 6/30/2026'):
 from decimal import Decimal
 return dict(period=period,summary=dict(in_kind=total),sections=[dict(id='in_kind',itemized=itemized or total,unitemized=str(Decimal(total)-Decimal(itemized or total)))])
def entry(amount,date,kind='In-kind contribution'):
 return dict(amount=amount,received_date=date,contribution_type=kind,contributor='Example')
def schedule_entry(amount,date):
 return dict(fields=[dict(label='Amount',value='$'+amount),dict(label='Date Received',value=date)])
class SupportTests(unittest.TestCase):
 def calc(self,rows,qs,as_=None,ss=None,created='04/01/2026'):
  return calculate(rows,created,lambda r:qs[r['document_id']],lambda r,s,p:ss[r['document_id']],lambda r:dict(contributions=as_[r['document_id']]),through='2026-06-30')
 def test_quarter_replaces_a1_by_received_date_and_cash_excluded(self):
  rows=[report('q'),report('late','A-1',filed='2026-08-01T10:00:00')]
  result=self.calc(rows,{'q':quarter()}, {'late':[entry('100.00','2026-06-20'),entry('20.00','2026-07-01'),entry('5000.00','2026-07-02','Individual Contribution')]})
  self.assertEqual(result['amount'],'120.00');self.assertEqual(result['status'],'ready')
 def test_primary_day_excluded_and_partial_quarter_unitemized_disclosed(self):
  rows=[report('q1',period='1/1/2026 to 3/31/2026',filed='2026-04-15T10:00:00'),report('q')]
  result=self.calc(rows,{'q1':quarter('35.00','30.00','1/1/2026 to 3/31/2026'),'q':quarter()},ss={'q1':dict(entries=[schedule_entry('10.00','03/17/2026'),schedule_entry('20.00','03/18/2026')])},created='01/01/2020')
  self.assertEqual(result['amount'],'120.00');self.assertEqual(result['status'],'partial');self.assertIn('undated',result['issues'][0])
 def test_latest_quarter_amendment_replaces_original(self):
  rows=[report('old'),report('new','D-2 Quarterly Report (Amended)',filed='2026-07-16T10:00:00')]
  result=self.calc(rows,{'old':quarter('100.00'),'new':quarter('80.00')})
  self.assertEqual(result['amount'],'80.00');self.assertEqual(len(result['sources']),1)
 def test_duplicate_in_kind_a1_not_silently_added(self):
  rows=[report('q'),report('a','A-1',filed='2026-07-20'),report('b','A-1',filed='2026-07-21')]
  with self.assertRaisesRegex(ReportFormatError,'duplicate'):self.calc(rows,{'q':quarter()},{'a':[entry('20.00','2026-07-19')],'b':[entry('20.00','2026-07-19')]})
 def test_amended_a1_requires_review(self):
  rows=[report('q'),report('a','A-1 amended',filed='2026-07-20')]
  with self.assertRaisesRegex(ReportFormatError,'amendment'):self.calc(rows,{'q':quarter()},{'a':[entry('20.00','2026-07-19')]})
 def test_missing_quarter_not_zero_verified(self):
  result=self.calc([],{},created='01/01/2020')
  self.assertEqual(result['status'],'partial');self.assertTrue(result['issues'])
 def test_new_committee_has_no_missing_precreation_quarter(self):
  result=self.calc([],{},created='07/01/2026')
  self.assertEqual(result['status'],'ready');self.assertEqual(result['amount'],'0.00')
 def test_pdf_quarter_falls_back_to_a1_and_marks_partial(self):
  rows=[report('q'),report('a','A-1',filed='2026-06-20')]
  result=calculate(rows,'04/01/2026',Mock(side_effect=OfficialPDFError('PDF')),Mock(),lambda r:dict(contributions=[entry('20.00','2026-06-19')]),through='2026-06-30')
  self.assertEqual(result['amount'],'20.00');self.assertEqual(result['status'],'partial')
 def test_pdf_a1_excluded_with_notice(self):
  rows=[report('q'),report('a','A-1',filed='2026-07-20')]
  result=calculate(rows,'04/01/2026',lambda r:quarter(),Mock(),Mock(side_effect=OfficialPDFError('PDF')),through='2026-06-30')
  self.assertEqual(result['amount'],'100.00');self.assertEqual(result['status'],'partial')
 def test_overlapping_quarters_rejected(self):
  rows=[report('q'),report('bad',period='6/1/2026 to 6/30/2026')]
  with self.assertRaisesRegex(ReportFormatError,'Overlapping'):self.calc(rows,{'q':quarter(),'bad':quarter()})
 def test_unknown_date_column_marks_partial(self):
  rows=[report('q1',period='1/1/2026 to 3/31/2026'),report('q')]
  result=self.calc(rows,{'q1':quarter(period='1/1/2026 to 3/31/2026'),'q':quarter()},ss={'q1':dict(entries=[dict(fields=[dict(label='Unknown',value='03/18/2026')])])},created='01/01/2020')
  self.assertEqual(result['status'],'partial');self.assertEqual(result['amount'],'100.00')

 def test_official_combined_amount_date_cell(self):
  from decimal import Decimal
  value=schedule_receipt(dict(fields=[dict(label='Amount',value='$1,122.00\n6/12/2026')]))
  self.assertEqual(value,('2026-06-12',Decimal('1122.00')))
