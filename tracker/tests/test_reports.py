import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from app import create_app
from reports import parse_a1, filing_id, FilingRedirect, ReportFormatError, ReportReader

HTML = (Path(__file__).parent/'fixtures/rezin-a1.html').read_text()
URL = 'https://www.elections.il.gov/CampaignDisclosure/A1List.aspx?ID=J0UpRIKF67qggMBlq%2bXY0g%3d%3d&FiledDocID=J0UpRIKF67qggMBlq%2bXY0g%3d%3d&ContributionType=wOGh3QTPfKqV2YWjeRmjTeStk426RfVK&Archived=Gl5sibpnFrQ%3d'
FILING = dict(seq=726000,url=URL,committee_name='Friends of Sue Rezin',report_type='A-1 ($1000+ Year Round)')

class ReportTests(unittest.TestCase):
    def test_real_filing(self):
        result=parse_a1(HTML,FILING)
        self.assertEqual(result['total'],'39223.24')
        self.assertEqual(len(result['contributions']),1)
        entry=result['contributions'][0]
        self.assertEqual(entry['contributor'],'Illinois Republican Party')
        self.assertEqual(entry['contribution_type'],'In-kind Contribution')
        self.assertEqual(entry['received_date'],'2026-09-20')
        self.assertEqual(entry['description'],'Direct mail')
        self.assertEqual(entry['vendor'],'Linc Strategy LLC')

    def test_all_rows_counted_and_decimal_total(self):
        start=HTML.index('<td align="center"')
        end=HTML.index('</tr>',start)
        row=HTML[start:end].replace('$39,223.24','$1,000.01').replace('Illinois Republican Party','Another &amp; Donor')
        result=parse_a1(HTML.replace('</table>','<tr>'+row+'</tr></table>'),FILING)
        self.assertEqual(result['total'],'40223.25')
        self.assertEqual(result['contributions'][1]['contributor'],'Another & Donor')

    def test_mismatched_filing_rejected(self):
        with self.assertRaises(ReportFormatError): parse_a1(HTML,dict(FILING,committee_name='Different Committee'))
        with self.assertRaises(ReportFormatError): parse_a1(HTML.replace('FiledDocID=J0UpRIKF67qggMBlq%2bXY0g%3d%3d','FiledDocID=Other'),FILING)
        with self.assertRaises(ReportFormatError): parse_a1(HTML,dict(FILING,report_type='Quarterly'))

    def test_partial_or_changed_tables_rejected(self):
        for changed in [HTML.replace('>Amount<','>Balance<'),HTML.replace('$39,223.24','Unknown'),
                        HTML.replace('</table>',"<a href=\"javascript:__doPostBack('table','Page$2')\">2</a></table>"),
                        HTML.replace('9/20/2026','13/20/2026')]:
            with self.assertRaises(ValueError): parse_a1(changed,FILING)

    def test_only_official_filing_specific_urls(self):
        for url in [URL.replace('www.elections.il.gov','example.com'),URL.replace('https:','http:'),URL.replace('FiledDocID=','other='),URL.replace('ID=J0','ID=XX',1)]:
            with self.assertRaises(ReportFormatError): filing_id(url)
        import urllib.request
        with self.assertRaises(ReportFormatError):
            FilingRedirect().redirect_request(urllib.request.Request(URL),None,302,'',{},'https://example.com/')

    def test_endpoint_auth_cache_and_failures(self):
        with tempfile.TemporaryDirectory() as folder:
            app=create_app(folder,poll=False); store=app.config['STORE'];client=app.test_client()
            row=dict(FILING,guid='test-report',published_raw='date',source='Filed electronically',committee_key='test-committee')
            store.ingest([row])
            seq=client.get('/v1/filings').json['filings'][0]['seq']
            path=f'/v1/filings/{seq}/contents'
            self.assertEqual(client.get(path).status_code,401)
            auth={'Authorization':'Bearer '+'f'*64};client.post('/v1/installations',headers=auth)
            with patch('reports.fetch_report',return_value=parse_a1(HTML,FILING)) as fetch:
                self.assertEqual(client.get(path,headers=auth).json['total'],'39223.24')
                self.assertEqual(client.get(path,headers=auth).json['status'],'ready')
                self.assertEqual(fetch.call_count,1)
            self.assertEqual(client.get('/v1/filings/999999999/contents',headers=auth).status_code,404)
            reader=ReportReader(store)
            with patch('reports.fetch_report',side_effect=TimeoutError):
                self.assertEqual(reader.read(dict(FILING,seq=123))['status'],'unavailable')
                self.assertEqual(reader.read(dict(FILING,seq=124,url='https://www.elections.il.gov/file.pdf'))['status'],'unsupported')

if __name__=='__main__': unittest.main()
