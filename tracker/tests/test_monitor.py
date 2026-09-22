import os
import sqlite3
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch
from app import Store, create_app, parse_feed, report_link


def feed(*ids):
    return ('<rss><channel>'+''.join(
        '<item><title>Friends of Example</title><guid>~/CampaignDisclosure/A1List.aspx?ID='+str(i)+'#'+str(i)+'</guid>'
        '<pubDate>Mon, 21 Sep 2026 22:01:49</pubDate><description>Report Type: A-1&lt;br/&gt;Source: Filed electronically</description></item>'
        for i in ids)+'</channel></rss>').encode()


class MonitorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = Store(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_baseline_restart_and_duplicate_suppression(self):
        self.assertEqual(self.store.ingest(parse_feed(feed(2,1)))['new_filings'], 0)
        restarted = Store(self.tmp.name)
        self.assertEqual(restarted.ingest(parse_feed(feed(2,1)))['new_filings'], 0)
        self.assertEqual(restarted.ingest(parse_feed(feed(3,2)))['new_filings'], 1)
        self.assertEqual(restarted.status()['stored_filings'], 3)
        self.assertEqual(restarted.status()['unresolved_gaps'], 0)

    def test_transaction_rollback(self):
        rows = parse_feed(feed(2,1))
        rows[0]['committee_key'] = None
        with self.assertRaises(sqlite3.IntegrityError):
            self.store.ingest(rows)
        self.assertEqual(self.store.status()['stored_filings'], 0)
        self.assertFalse(self.store.meta('initialized', False))

    def test_gap_persists_until_reconciled(self):
        self.store.ingest(parse_feed(feed(2,1)))
        self.store.ingest(parse_feed(feed(4,3)))
        self.store.ingest(parse_feed(feed(5,4)))
        self.assertEqual(self.store.status()['unresolved_gaps'], 1)

    def test_source_timestamp_does_not_filter_late_filings(self):
        self.store.ingest(parse_feed(feed(1)))
        self.assertEqual(self.store.ingest(parse_feed(feed(2,1)))['new_filings'], 1)

    def test_http_failure_preserves_last_success(self):
        self.store.ingest(parse_feed(feed(1)))
        last = self.store.meta('last_success')
        self.store.failure('HTTP 403',403)
        self.assertEqual(self.store.meta('last_success'), last)
        self.assertEqual(self.store.status()['consecutive_failures'], 1)

    def test_missing_report_type_and_guid_link_fallback(self):
        row = parse_feed(b'<rss><channel><item><title>X</title><guid>~/CampaignDisclosure/CDPdfViewer.aspx?FiledDocID=abc#9</guid></item></channel></rss>')[0]
        self.assertEqual(row['report_type'], 'Unspecified filing')
        self.assertEqual(row['url'], 'https://www.elections.il.gov/CampaignDisclosure/CDPdfViewer.aspx?FiledDocID=abc')
        self.assertIsNone(report_link('https://evil.example/report'))
        self.assertIsNone(report_link('javascript:alert(1)'))

    def test_invalid_xml_is_not_ingested(self):
        for data in [b'<html>blocked</html>', feed(), feed(1,1), b'bad xml']:
            with self.assertRaises(Exception): parse_feed(data)

    def test_consistent_database_backup(self):
        self.store.ingest(parse_feed(feed(1)))
        self.store.backup()
        backup = next((Path(self.tmp.name)/'backups').glob('*.sqlite3'))
        with sqlite3.connect(backup) as db:
            self.assertEqual(db.execute('SELECT count(*) FROM filings').fetchone()[0], 1)
            self.assertEqual(db.execute('PRAGMA integrity_check').fetchone()[0], 'ok')

    def test_api_cursor_and_stale_health(self):
        self.store.ingest(parse_feed(feed(3,2,1)), now=time.time()-1000)
        client = create_app(self.tmp.name, poll=False).test_client()
        self.assertEqual(client.get('/healthz').status_code, 200)
        self.assertEqual(client.get('/readyz').status_code, 503)
        first = client.get('/v1/filings?limit=2').json
        self.assertEqual(len(first['filings']), 2)
        second = client.get('/v1/filings?before='+str(first['next_cursor'])).json
        self.assertEqual(len(second['filings']), 1)
        self.assertEqual(client.get('/v1/filings?before=no').status_code,400)
        self.assertEqual(client.post('/v1/filings').status_code,405)
        self.assertEqual(client.get('/').status_code,200)

    def test_disk_requirement_prevents_ephemeral_start(self):
        with patch.dict(os.environ, {'REQUIRE_PERSISTENT_DISK':'1'}):
            with self.assertRaises(RuntimeError): create_app(self.tmp.name,poll=False)


if __name__ == '__main__': unittest.main()
