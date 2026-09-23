import unittest
from unittest.mock import patch
from contextlib import closing
import test_launch_features as fixtures
from pdf_reports import official,embedded_pdf,fetch_pdf
from reports import ReportFormatError
class PDFSafetyTests(unittest.TestCase):
 def test_source_and_embedded_document_boundaries(self):
  for url in ('http://www.elections.il.gov/a.pdf','https://evil.test/a.pdf','https://www.elections.il.gov@evil.test/a.pdf'):
   with self.assertRaises(ReportFormatError):official(url)
  base='https://www.elections.il.gov/CampaignDisclosure/CDPdfViewer.aspx?FiledDocID=123'
  self.assertEqual(embedded_pdf('<iframe src="/docs/one.pdf"></iframe>',base),'https://www.elections.il.gov/docs/one.pdf')
  for html in ('<p>No document</p>','<iframe src="/a.pdf"></iframe><iframe src="/b.pdf"></iframe>','<iframe src="https://evil.test/a.pdf"></iframe>'):
   with self.assertRaises(ReportFormatError):embedded_pdf(html,base)
  with self.assertRaises(ReportFormatError):fetch_pdf('https://www.elections.il.gov/other.aspx')
class PDFEndpointTests(unittest.TestCase):
 setUp=fixtures.LaunchTests.setUp
 tearDown=fixtures.LaunchTests.tearDown
 def test_pdf_endpoint_uses_stored_filing_only(self):
  from app import parse_feed
  from test_monitor import feed
  self.store.ingest(parse_feed(feed(1)))
  with closing(self.store.connect()) as db:seq=db.execute('SELECT seq FROM filings').fetchone()[0]
  with patch('pdf_reports.fetch_pdf',return_value=b'%PDF-1.4\nexample') as fetch:
   r=self.c.get(f'/v1/filings/{seq}/document.pdf')
   self.assertEqual(r.status_code,200);self.assertEqual(r.mimetype,'application/pdf');self.assertTrue(r.data.startswith(b'%PDF-'))
   fetch.assert_called_once()
  self.assertEqual(self.c.get('/v1/filings/999999999999999999999/document.pdf').status_code,404)
