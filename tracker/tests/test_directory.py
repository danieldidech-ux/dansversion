import copy
import tempfile
import unittest
from unittest.mock import patch
from contextlib import closing
from app import create_app, committee_key
from directory import sync_directory
from subscriptions import enqueue


class DirectoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.app = create_app(self.tmp.name, poll=False)
        self.client = self.app.test_client()
        self.store = self.app.config['STORE']
        self.auth = {'Authorization': 'Bearer ' + 'c' * 64}
        self.client.post('/v1/installations', headers=self.auth)

    def tearDown(self):
        self.tmp.cleanup()

    def test_directory_with_production_collector_startup(self):
        with tempfile.TemporaryDirectory() as path, patch('app.threading.Thread') as thread:
            thread.return_value.is_alive.return_value = True
            app = create_app(path, poll=True)
            try:
                client = app.test_client()
                self.assertEqual(client.get('/healthz').status_code, 200)
                self.assertEqual(client.get('/v1/directory').status_code, 200)
                self.assertEqual(thread.return_value.start.call_count, 2)
            finally:
                if app.config.get('COLLECTOR_LOCK'):
                    app.config['COLLECTOR_LOCK'].close()

    def test_approved_replacements_and_missing_entry(self):
        groups = {g['id']: g for g in self.client.get('/v1/directory').json['groups']}
        house = groups['house-democrats']['members']
        senate = groups['senate-democrats']['members']
        self.assertEqual(next(x for x in house if x['district'] == 51)['member'], 'Jenny Levin')
        self.assertEqual(next(x for x in house if x['district'] == 52)['committee']['name'], 'Maria for 52')
        self.assertEqual(next(x for x in senate if x['district'] == 26)['member'], 'Nabeela Syed')
        self.assertNotIn('Democratic Majority', str(groups))
        self.assertEqual(next(x for x in groups['senate-republicans']['members'] if x['district'] == 44)['committee']['name'], 'Friends of Sally Turner')
        for group in groups.values():
            for entry in group['members'] + group['pinned']:
                if entry['committee']:
                    self.assertEqual(entry['committee']['id'], committee_key(entry['committee']['name']))

    def test_unseen_committee_follow_and_group_dedup(self):
        key = committee_key('All in With Lilian')
        response = self.client.put('/v1/me/watchlist', headers=self.auth,
            json={'committees': [key], 'categories': ['house-democrats']})
        self.assertEqual(response.status_code, 200)
        self.client.put('/v1/me/push', headers=self.auth,
            json={'enabled': True, 'token': 'e'*64, 'environment': 'sandbox'})
        with closing(self.store.connect()) as db, db:
            enqueue(db, 100, key, 1)
            enqueue(db, 100, key, 1)
            self.assertEqual(db.execute('SELECT count(*) FROM outbox').fetchone()[0], 1)

    def test_revision_replaces_group_but_preserves_individual_watch(self):
        key = committee_key('People for Emanuel Chris Welch')
        self.client.put('/v1/me/watchlist', headers=self.auth,
            json={'committees': [key], 'categories': ['house-democrats']})
        changed = copy.deepcopy(self.store.directory_data)
        group = next(g for g in changed['groups'] if g['id'] == 'house-democrats')
        group['pinned'] = []
        group['members'] = []
        with closing(self.store.connect()) as db, db:
            sync_directory(db, changed)
            self.assertEqual(db.execute("SELECT count(*) FROM category_members WHERE category_id='house-democrats'").fetchone()[0], 0)
            self.assertEqual(db.execute('SELECT count(*) FROM subscriptions WHERE committee_key=?', (key,)).fetchone()[0], 1)
