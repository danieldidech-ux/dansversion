import unittest
from unittest.mock import patch
import test_history
COM=test_history.COM
from history import History
from archive_source import OfficialPDFError
from reports import ReportFormatError

class EstimatePDFTests(unittest.TestCase):
 setUp=test_history.HistoryTests.setUp
 # Use the same complete official-archive fixture and temporary database.
 def test_pdf_a1_excluded_while_electronic_receipts_still_count(self):
  quarter=next(r for r in self.rows if r['report_type']=='D-2 Quarterly Report')
  a1=self.rows[0];pdf=dict(a1,document_id='pdf',url=a1['url']+'&scan=1')
  receipt=dict(contributor='Donor',amount='1500.00',received_date='2026-09-01',contribution_type='Individual Contribution')
  def part(source,report,quarter=False):
   if report['document_id']=='pdf':raise OfficialPDFError('PDF')
   return '409751.99' if quarter else {'contributions':[receipt]}
  with patch.object(self.history,'part',side_effect=part):
   result=self.history.calculate(None,COM,[quarter,a1,pdf,pdf])
  self.assertEqual(result['estimated_cash'],'411251.99')
  self.assertEqual(result['excluded_pdf_count'],1);self.assertIn('not included',result['message'])
 def test_new_committee_pdf_does_not_block_zero_baseline_and_readable_a1s(self):
  with patch('history.previous_quarter_end',return_value='2026-06-30'),patch.object(self.history,'part',side_effect=OfficialPDFError('PDF')):
   result=self.history.calculate(None,COM,[self.rows[0]],'7/11/2026')
  self.assertEqual(result['status'],'ready');self.assertEqual(result['estimated_cash'],'0.00')
  self.assertEqual(result['excluded_pdf_count'],1)
 def test_non_pdf_failure_is_never_silently_skipped(self):
  for error in [ReportFormatError('Missing totals'),TimeoutError('Network timeout')]:
   with patch('history.previous_quarter_end',return_value='2026-06-30'),patch.object(self.history,'part',side_effect=error):
    result=self.history.calculate(None,COM,[self.rows[0]],'7/11/2026')
   self.assertEqual(result['status'],'unavailable');self.assertIsNone(result['estimated_cash'])
 def test_pdf_quarter_uses_earlier_readable_quarter_without_inventing_zero(self):
  quarters=[r for r in self.rows if r['report_type']=='D-2 Quarterly Report'][:2]
  calls=[]
  def part(source,report,quarter=False):
   calls.append(report['document_id'])
   if len(calls)==1:raise OfficialPDFError('PDF')
   return '100.00'
  with patch.object(self.history,'part',side_effect=part):result=self.history.calculate(None,COM,quarters)
  self.assertEqual(result['estimated_cash'],'100.00');self.assertEqual(result['excluded_pdf_count'],1)
  with patch.object(self.history,'part',side_effect=OfficialPDFError('PDF')):result=self.history.calculate(None,COM,quarters)
  self.assertEqual(result['status'],'unavailable');self.assertIsNone(result['estimated_cash'])
