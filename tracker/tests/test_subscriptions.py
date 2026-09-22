import tempfile
import unittest
from contextlib import closing
from unittest.mock import Mock, patch
from app import Store, create_app, parse_feed
from subscriptions import dispatch
from test_monitor import feed

class SubscriptionTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.app=create_app(self.tmp.name,poll=False)
        self.store=self.app.config['STORE']; self.client=self.app.test_client()
        self.a={'Authorization':'Bearer '+'a'*64}; self.b={'Authorization':'Bearer '+'b'*64}
        for h in (self.a,self.b): self.client.post('/v1/installations',headers=h)
        self.store.ingest(parse_feed(feed(1)))
        self.key=parse_feed(feed(1))[0]['committee_key']
    def tearDown(self): self.tmp.cleanup()
    def follow(self): return self.client.put('/v1/me/watchlist',headers=self.a,json={'committees':[self.key]})
    def enable(self): return self.client.put('/v1/me/push',headers=self.a,json={'enabled':True,'token':'f'*64,'environment':'sandbox'})
    def queue(self):
        with closing(self.store.connect()) as db: return [dict(r) for r in db.execute('SELECT * FROM outbox')]
    def test_isolation_and_auth(self):
        self.assertEqual(self.client.get('/v1/me').status_code,401); self.follow()
        self.assertEqual(len(self.client.get('/v1/me',headers=self.a).json['committees']),1)
        self.assertEqual(self.client.get('/v1/me',headers=self.b).json['committees'],[])
        self.assertEqual(self.client.get('/v1/me/filings',headers=self.b).json['filings'],[])
    def test_new_only_dedup_and_restart(self):
        self.follow(); self.enable(); self.assertEqual(self.queue(),[])
        self.store.ingest(parse_feed(feed(2,1))); Store(self.tmp.name).ingest(parse_feed(feed(2,1)))
        self.assertEqual(len(self.queue()),1)
    def test_atomic_queue(self):
        self.follow(); self.enable()
        with patch('app.enqueue',side_effect=RuntimeError('rollback')):
            with self.assertRaises(RuntimeError): self.store.ingest(parse_feed(feed(2,1)))
        self.assertEqual(self.queue(),[]); self.assertEqual(self.store.status()['stored_filings'],1)
    def test_unfollow_and_pause_cancel_queue(self):
        self.follow(); self.enable(); self.store.ingest(parse_feed(feed(2,1)))
        self.client.put('/v1/me/watchlist',headers=self.a,json={'committees':[]}); self.assertEqual(self.queue(),[])
        self.follow(); self.store.ingest(parse_feed(feed(3,2,1)))
        self.client.put('/v1/me/push',headers=self.a,json={'enabled':False}); self.assertEqual(self.queue(),[])
    def test_delete(self):
        self.follow(); self.enable(); self.store.ingest(parse_feed(feed(2,1)))
        self.assertEqual(self.client.delete('/v1/me',headers=self.a).status_code,200)
        self.assertEqual(self.client.get('/v1/me',headers=self.a).status_code,401)
        self.assertEqual(self.queue(),[]); self.assertEqual(self.store.status()['stored_filings'],2)
    def test_verified_categories_and_union_dedup(self):
        data={'committees':[self.key],'categories':['house-democrats']}
        with closing(self.store.connect()) as db,db:
            db.execute("UPDATE categories SET verified=0 WHERE id='house-democrats'")
        self.assertEqual(self.client.put('/v1/me/watchlist',headers=self.a,json=data).status_code,400)
        with closing(self.store.connect()) as db,db:
            db.execute("UPDATE categories SET verified=1 WHERE id='house-democrats'")
            db.execute("INSERT INTO category_members VALUES ('house-democrats',?)",(self.key,))
        self.assertEqual(self.client.put('/v1/me/watchlist',headers=self.a,json=data).status_code,200)
        self.enable(); self.store.ingest(parse_feed(feed(2,1))); self.assertEqual(len(self.queue()),1)
    def test_retry_then_success(self):
        self.follow(); self.enable(); self.store.ingest(parse_feed(feed(2,1)))
        sender=Mock(); sender.send.return_value=(503,'ServiceUnavailable')
        dispatch(self.store,sender,enabled=True); self.assertEqual(self.queue()[0]['state'],'pending')
        dispatch(self.store,sender,enabled=True); self.assertEqual(sender.send.call_count,1)
        with closing(self.store.connect()) as db,db: db.execute('UPDATE outbox SET next_attempt=0')
        sender.send.return_value=(200,''); dispatch(self.store,sender,enabled=True); dispatch(self.store,sender,enabled=True)
        self.assertEqual(sender.send.call_count,2); self.assertEqual(self.queue()[0]['state'],'sent')
    def test_disabled_delivery_and_invalid_token(self):
        self.follow(); self.enable(); self.store.ingest(parse_feed(feed(2,1)))
        sender=Mock(); sender.send.return_value=(410,'Unregistered')
        dispatch(self.store,sender,enabled=False); sender.send.assert_not_called()
        dispatch(self.store,sender,enabled=True)
        self.assertFalse(self.client.get('/v1/me',headers=self.a).json['alerts_enabled'])
    def test_validation_and_token_ownership(self):
        self.assertEqual(self.client.put('/v1/me/watchlist',headers=self.a,json={'committees':['made-up']}).status_code,400)
        self.assertEqual(self.client.put('/v1/me/push',headers=self.a,json={'enabled':True,'token':'bad'}).status_code,400)
        self.enable()
        self.assertEqual(self.client.put('/v1/me/push',headers=self.b,json={'enabled':True,'token':'f'*64,'environment':'sandbox'}).status_code,409)
    def test_pagination_and_detail(self):
        self.follow(); self.store.ingest(parse_feed(feed(*range(60,0,-1))))
        first=self.client.get('/v1/me/filings',headers=self.a).json
        self.assertEqual(len(first['filings']),50)
        second=self.client.get('/v1/me/filings?before='+str(first['next_cursor']),headers=self.a).json
        self.assertEqual(len(second['filings']),10)
        seq=first['filings'][0]['seq']; self.assertEqual(self.client.get('/v1/filings/'+str(seq)).json['seq'],seq)
    def test_registration_idempotent(self):
        self.assertEqual(self.client.post('/v1/installations',headers=self.a).json,self.client.post('/v1/installations',headers=self.a).json)
