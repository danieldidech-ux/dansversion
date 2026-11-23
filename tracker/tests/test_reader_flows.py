import json
import tempfile
import unittest
from contextlib import closing
from unittest.mock import patch

from app import create_app


class ReaderFlowTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.app = create_app(directory.name, poll=False)
        self.client = self.app.test_client()
        self.store = self.app.config['STORE']
        self.key = 'reader-flow'
        with closing(self.store.connect()) as db, db:
            db.execute('INSERT INTO committees VALUES (?,?)', (self.key, 'Example'))
            db.executemany(
                'INSERT INTO filings(guid,committee_key,committee_name,report_type,first_seen,baseline) '
                'VALUES(?,?,?, ?,0,1)',
                [(str(i), self.key, 'Example', 'Other') for i in range(103)])

    def test_feed_cursor_survives_archive_arriving_between_pages(self):
        history = self.app.config['HISTORY']
        url = '/v1/committees/' + self.key + '/history'
        with patch.object(history, 'schedule', return_value=True):
            first = self.client.get(url).get_json()
            self.assertEqual(first['next_cursor'], 54)
            with closing(self.store.connect()) as db, db:
                report = dict(committee_key=self.key, filed_at='2026-11-01', document_id='archive')
                db.execute('INSERT INTO archive_reports(committee_key,document_id,payload) VALUES(?,?,?)',
                           (self.key, 'archive', json.dumps(report)))
            second = self.client.get(url, query_string={'before': first['next_cursor']}).get_json()
            third = self.client.get(url, query_string={'before': second['next_cursor']}).get_json()
            self.assertFalse(third['has_more'])
            self.assertEqual([r['seq'] for p in (first, second, third) for r in p['filings']],
                             list(range(103, 0, -1)))

    def test_feed_reuses_preview_connection_and_share_omits_unavailable_links(self):
        with patch.object(self.store, 'connect', wraps=self.store.connect) as connect:
            page = self.client.get('/v1/filings').get_json()
            self.assertEqual(len(page['filings']), 50)
            self.assertLess(connect.call_count, 5)
        response = self.client.get('/share/filing/1')
        self.assertEqual(response.status_code, 200)
        self.assertNotIn(b'Download CSV', response.data)
        self.assertNotIn(b'View official report', response.data)
