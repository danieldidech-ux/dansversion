import unittest
from contextlib import closing
import test_observer as fixtures
from app import parse_feed
from test_monitor import feed

class ContextualListTests(unittest.TestCase):
 setUp=fixtures.ObserverTests.setUp
 tearDown=fixtures.ObserverTests.tearDown
 def create(self,keys):return self.c.post('/v1/me/lists',headers=self.auth,json={'name':'My races','committees':keys})
 def test_create_and_add_is_atomic_validated_and_new_only(self):
  self.assertEqual(self.create(['unknown']).status_code,400)
  self.assertEqual(self.c.get('/v1/me/lists',headers=self.auth).json['lists'],[])
  response=self.create([self.key,self.key]);self.assertEqual(response.status_code,200)
  lists=self.c.get('/v1/me/lists',headers=self.auth).json['lists']
  self.assertEqual(len(lists[0]['committees']),1);self.assertEqual(lists[0]['new_count'],0)
  with closing(self.store.connect()) as db:self.assertEqual(db.execute('SELECT count(*) FROM outbox').fetchone()[0],0)
 def test_membership_is_idempotent_private_and_preserves_other_members(self):
  identifier=self.create([self.key]).json['id'];path='/v1/me/lists/'+identifier+'/committees/'+self.key
  self.assertEqual(self.c.put(path,headers=self.other,json={'included':False}).status_code,404)
  self.assertEqual(self.c.put(path,headers=self.auth,json={'included':'yes'}).status_code,400)
  for _ in range(2):self.assertEqual(self.c.put(path,headers=self.auth,json={'included':True}).status_code,200)
  rows=parse_feed(feed(2).replace(b'Friends of Example',b'Other Committee'));self.store.ingest(rows);other=rows[0]['committee_key']
  otherpath='/v1/me/lists/'+identifier+'/committees/'+other
  self.assertEqual(self.c.put(otherpath,headers=self.auth,json={'included':True}).status_code,200)
  self.c.put(path,headers=self.auth,json={'included':False})
  selected=self.c.get('/v1/me/lists',headers=self.auth).json['lists'][0]['committees']
  self.assertEqual([r['id'] for r in selected],[other])
 def test_removing_list_membership_cancels_only_uncovered_pending_alerts(self):
  identifier=self.create([self.key]).json['id'];path='/v1/me/lists/'+identifier+'/committees/'+self.key
  self.c.put('/v1/me/push',headers=self.auth,json={'enabled':True,'token':'f'*64})
  self.store.ingest(parse_feed(feed(2,1)))
  with closing(self.store.connect()) as db:self.assertEqual(db.execute('SELECT count(*) FROM outbox').fetchone()[0],1)
  self.c.put('/v1/me/watchlist',headers=self.auth,json={'committees':[self.key]})
  self.c.put(path,headers=self.auth,json={'included':False})
  with closing(self.store.connect()) as db:self.assertEqual(db.execute('SELECT count(*) FROM outbox').fetchone()[0],1)
  self.c.put('/v1/me/watchlist',headers=self.auth,json={'committees':[]})
  with closing(self.store.connect()) as db:self.assertEqual(db.execute('SELECT count(*) FROM outbox').fetchone()[0],0)
