import unittest
from contextlib import closing
from unittest.mock import Mock
import test_subscriptions as fixtures
from app import parse_feed, Store
from test_monitor import feed
from subscriptions import dispatch

class AllReportAlertsTests(unittest.TestCase):
 setUp=fixtures.SubscriptionTests.setUp
 tearDown=fixtures.SubscriptionTests.tearDown
 follow=fixtures.SubscriptionTests.follow
 enable=fixtures.SubscriptionTests.enable
 queue=fixtures.SubscriptionTests.queue
 def scope(self,value,headers=None):return self.client.put('/v1/me/alert-scope',headers=headers or self.a,json={'all_reports':value})
 def test_validated_private_and_no_historical_notifications(self):
  self.assertEqual(self.client.put('/v1/me/alert-scope',json={'all_reports':True}).status_code,401)
  self.assertEqual(self.scope('yes').status_code,400)
  self.enable();self.assertEqual(self.scope(True).status_code,200)
  self.assertEqual(self.queue(),[])
  self.assertTrue(self.client.get('/v1/me',headers=self.a).json['all_reports'])
  self.assertFalse(self.client.get('/v1/me',headers=self.b).json['all_reports'])
  self.assertEqual(len(self.client.get('/v1/me/filings',headers=self.a).json['filings']),1)
  self.assertEqual(self.client.get('/v1/me/filings',headers=self.b).json['filings'],[])
 def test_global_alerts_deliver_unfollowed_committees_once_and_survive_restart(self):
  self.enable();self.scope(True)
  new=feed(2,1).replace(b'Friends of Example',b'Another Committee')
  self.store.ingest(parse_feed(new));Store(self.tmp.name).ingest(parse_feed(new))
  # The existing guid stays the same; only the new report queues.
  self.assertEqual(len(self.queue()),1)
  sender=Mock();sender.send.return_value=(200,'')
  with closing(self.store.connect()) as db,db:db.execute('UPDATE outbox SET created_at=created_at-180')
  dispatch(self.store,sender,enabled=True);dispatch(self.store,sender,enabled=True)
  self.assertEqual(sender.send.call_count,1)
 def test_overlap_and_turning_off_preserves_individual_selections(self):
  self.follow();self.enable();self.scope(True)
  self.store.ingest(parse_feed(feed(2,1)));self.assertEqual(len(self.queue()),1)
  self.assertEqual(self.scope(False).status_code,200)
  self.assertEqual(len(self.queue()),1)
  self.assertEqual(len(self.client.get('/v1/me',headers=self.a).json['committees']),1)
  self.scope(True)
  self.client.put('/v1/me/watchlist',headers=self.a,json={'committees':[]})
  self.assertEqual(len(self.queue()),1)
  self.scope(False);self.assertEqual(self.queue(),[])
 def test_all_reports_resets_report_type_filter_and_delete_removes_scope(self):
  self.client.put('/v1/me/alert-preferences',headers=self.a,json={'mode':'quarterly','delivery':'morning'})
  self.scope(True)
  p=self.client.get('/v1/me/alert-preferences',headers=self.a).json
  self.assertEqual(p['mode'],'all');self.assertEqual(p['delivery'],'morning')
  self.client.delete('/v1/me',headers=self.a)
  with closing(self.store.connect()) as db:self.assertEqual(db.execute('SELECT count(*) FROM all_report_subscriptions').fetchone()[0],0)
