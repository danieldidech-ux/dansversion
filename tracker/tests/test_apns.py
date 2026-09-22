import os
import time
import unittest
from unittest.mock import Mock, patch
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import serialization
import jwt
from subscriptions import ApplePush, configured

class AppleTransportTests(unittest.TestCase):
    def test_signed_payload_and_environment_credentials(self):
        key=ec.generate_private_key(ec.SECP256R1())
        pem=key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()).decode()
        env={'APNS_TEAM_ID':'TEAMTEST','APNS_TOPIC':'com.example.test','APNS_SANDBOX_KEY_ID':'SANDBOXKEY','APNS_SANDBOX_PRIVATE_KEY':pem}
        sender=ApplePush(); sender.client=Mock()
        sender.client.post.return_value.status_code=200
        sender.client.post.return_value.json.side_effect=ValueError()
        row={'environment':'sandbox','token':'f'*64,'committee_name':'Friends of Example','report_type':'A-1','filing_seq':42,'created_at':time.time()}
        with patch.dict(os.environ,env,clear=True):
            self.assertTrue(configured('sandbox')); self.assertFalse(configured('production'))
            self.assertEqual(sender.send(row),(200,''))
        args,kwargs=sender.client.post.call_args
        self.assertTrue(args[0].startswith('https://api.sandbox.push.apple.com/3/device/'))
        self.assertEqual(kwargs['json']['aps']['alert'],{'title':'Friends of Example','body':'A-1'})
        self.assertEqual(kwargs['headers']['apns-collapse-id'],'filing-42')
        claims=jwt.decode(kwargs['headers']['authorization'][7:],key.public_key(),algorithms=['ES256'])
        self.assertEqual(claims['iss'],'TEAMTEST')
