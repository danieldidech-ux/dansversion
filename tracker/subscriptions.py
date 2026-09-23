"""Installation-scoped subscriptions and transactional APNs outbox."""
import hashlib
import json
import os
import re
import time
import uuid
from contextlib import closing
from functools import wraps
from flask import Blueprint, jsonify, request, g
from reports import ReportReader

CATEGORIES = [
    ('executive-branch', 'Executive Branch'),
    ('house-democrats', 'House Democrats'), ('house-republicans', 'House Republicans'),
    ('senate-democrats', 'Senate Democrats'), ('senate-republicans', 'Senate Republicans'),
    ('caucus-committees', 'Caucus committees'),
]


def credentials(environment):
    prefix = 'APNS_SANDBOX_' if environment == 'sandbox' else 'APNS_PRODUCTION_'
    return (os.environ.get(prefix+'KEY_ID'), os.environ.get(prefix+'PRIVATE_KEY'))


def configured(environment=None):
    common = all(os.environ.get(k) for k in ('APNS_TEAM_ID', 'APNS_TOPIC'))
    environments = [environment] if environment else ['sandbox','production']
    return common and any(all(credentials(env)) for env in environments)


def migrate(db):
    db.executescript('''
      CREATE TABLE IF NOT EXISTS devices (
        id TEXT PRIMARY KEY, credential_hash TEXT UNIQUE NOT NULL, created_at REAL NOT NULL,
        token TEXT, environment TEXT NOT NULL DEFAULT 'sandbox', enabled INTEGER NOT NULL DEFAULT 0);
      CREATE UNIQUE INDEX IF NOT EXISTS device_token ON devices(token,environment) WHERE token IS NOT NULL;
      CREATE TABLE IF NOT EXISTS subscriptions (
        device_id TEXT NOT NULL, committee_key TEXT NOT NULL, PRIMARY KEY(device_id,committee_key));
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, verified INTEGER NOT NULL DEFAULT 0,
        reviewed_at TEXT, source_url TEXT);
      CREATE TABLE IF NOT EXISTS category_members (
        category_id TEXT NOT NULL, committee_key TEXT NOT NULL, PRIMARY KEY(category_id,committee_key));
      CREATE TABLE IF NOT EXISTS category_subscriptions (
        device_id TEXT NOT NULL, category_id TEXT NOT NULL, PRIMARY KEY(device_id,category_id));
      CREATE TABLE IF NOT EXISTS outbox (
        id INTEGER PRIMARY KEY, device_id TEXT NOT NULL, filing_seq INTEGER NOT NULL,
        created_at REAL NOT NULL, next_attempt REAL NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
        state TEXT NOT NULL DEFAULT 'pending', last_error TEXT, UNIQUE(device_id,filing_seq));
      CREATE INDEX IF NOT EXISTS outbox_due ON outbox(state,next_attempt);
      CREATE TABLE IF NOT EXISTS request_limits (bucket TEXT PRIMARY KEY, count INTEGER NOT NULL, expires REAL NOT NULL);
    ''')
    db.executemany('INSERT OR IGNORE INTO categories(id,name) VALUES (?,?)', CATEGORIES)
    from observer import migrate as observer_migrate
    observer_migrate(db)


def enqueue(db, seq, committee_key, now):
    # Called inside the same transaction as insertion of a genuinely new filing.
    db.execute('''INSERT OR IGNORE INTO outbox(device_id,filing_seq,created_at,next_attempt)
      SELECT id,?,?,? FROM devices WHERE enabled=1 AND token IS NOT NULL AND id IN (
        SELECT device_id FROM subscriptions WHERE committee_key=?
        UNION
        SELECT s.device_id FROM category_subscriptions s
          JOIN categories c ON c.id=s.category_id AND c.verified=1
          JOIN category_members m ON m.category_id=c.id WHERE m.committee_key=?
        UNION SELECT l.device_id FROM private_lists l JOIN list_members m ON m.list_id=l.id WHERE m.committee_key=?)''',
        (seq, now, now, committee_key, committee_key,committee_key))


def routes(store):
    api = Blueprint('subscriptions', __name__)
    report_reader = ReportReader(store)

    def credential():
        value = request.headers.get('Authorization', '')
        if not re.fullmatch(r'Bearer [a-f0-9]{64}', value):
            return None
        return hashlib.sha256(value[7:].encode()).hexdigest()

    def throttle(bucket, limit):
        now = time.time()
        with closing(store.connect()) as db, db:
            db.execute('DELETE FROM request_limits WHERE expires<?', (now,))
            db.execute('INSERT INTO request_limits VALUES (?,1,?) ON CONFLICT(bucket) DO UPDATE SET count=count+1', (bucket, now+3600))
            return db.execute('SELECT count FROM request_limits WHERE bucket=?', (bucket,)).fetchone()[0] <= limit

    def authenticated(fn):
        @wraps(fn)
        def wrapped(*args, **kwargs):
            digest = credential()
            if not digest:
                return jsonify(error='Installation credential required'), 401
            with closing(store.connect()) as db:
                device = db.execute('SELECT * FROM devices WHERE credential_hash=?', (digest,)).fetchone()
            if not device:
                return jsonify(error='Register this installation first'), 401
            if not throttle('device:'+device['id'], 600):
                return jsonify(error='Too many requests; try again later'), 429
            g.device = dict(device)
            return fn(*args, **kwargs)
        return wrapped

    def body():
        data = request.get_json(silent=True)
        return data if isinstance(data, dict) else {}

    @api.post('/v1/installations')
    def register():
        digest = credential()
        if not digest:
            return jsonify(error='A random 32-byte installation credential is required'), 400
        with closing(store.connect()) as db:
            existing = db.execute('SELECT id FROM devices WHERE credential_hash=?', (digest,)).fetchone()
        if existing:
            return jsonify(id=existing['id'])
        if not throttle('registration', 100):
            return jsonify(error='Registration busy; try again later'), 429
        identifier = str(uuid.uuid4())
        with closing(store.connect()) as db, db:
            db.execute('INSERT OR IGNORE INTO devices(id,credential_hash,created_at) VALUES (?,?,?)', (identifier,digest,time.time()))
            identifier = db.execute('SELECT id FROM devices WHERE credential_hash=?', (digest,)).fetchone()[0]
        return jsonify(id=identifier), 201

    @api.get('/v1/categories')
    def categories():
        with closing(store.connect()) as db:
            rows = [dict(r) for r in db.execute('SELECT c.*,count(m.committee_key) AS member_count FROM categories c LEFT JOIN category_members m ON m.category_id=c.id GROUP BY c.id ORDER BY c.name')]
        return jsonify(categories=rows)

    @api.get('/v1/me')
    @authenticated
    def me():
        with closing(store.connect()) as db:
            committees = [dict(r) for r in db.execute('SELECT c.id,c.name FROM committees c JOIN subscriptions s ON c.id=s.committee_key WHERE s.device_id=? ORDER BY c.name', (g.device['id'],))]
            categories = [r[0] for r in db.execute('SELECT category_id FROM category_subscriptions WHERE device_id=?', (g.device['id'],))]
        return jsonify(committees=committees, categories=categories, alerts_enabled=bool(g.device['enabled']), push_configured=configured())

    @api.put('/v1/me/watchlist')
    @authenticated
    def watchlist():
        data = body()
        committees, categories = data.get('committees'), data.get('categories', [])
        if not isinstance(committees,list) or not isinstance(categories,list) or len(committees)>1000 or len(categories)>20 or any(not isinstance(x,str) for x in committees+categories):
            return jsonify(error='Invalid watchlist'), 400
        with closing(store.connect()) as db, db:
            db.execute('BEGIN IMMEDIATE')
            known = {r[0] for r in db.execute('SELECT id FROM committees')}
            allowed = {r[0] for r in db.execute('SELECT id FROM categories WHERE verified=1')}
            if not set(committees)<=known or not set(categories)<=allowed:
                return jsonify(error='Unknown committee or category still under review'), 400
            db.execute('DELETE FROM subscriptions WHERE device_id=?', (g.device['id'],))
            db.execute('DELETE FROM category_subscriptions WHERE device_id=?', (g.device['id'],))
            db.executemany('INSERT INTO subscriptions VALUES (?,?)', [(g.device['id'],x) for x in set(committees)])
            db.executemany('INSERT INTO category_subscriptions VALUES (?,?)', [(g.device['id'],x) for x in set(categories)])
            db.execute("""DELETE FROM outbox WHERE device_id=? AND state='pending' AND filing_seq NOT IN (
                SELECT f.seq FROM filings f WHERE f.committee_key IN (
                  SELECT committee_key FROM subscriptions WHERE device_id=? UNION
                  SELECT m.committee_key FROM category_members m JOIN category_subscriptions s ON s.category_id=m.category_id WHERE s.device_id=? UNION
                  SELECT m.committee_key FROM list_members m JOIN private_lists l ON l.id=m.list_id WHERE l.device_id=?)
                UNION SELECT x.seq FROM disclosures x JOIN active_entity_follows e ON e.entity_id=x.entity_id WHERE e.device_id=?
                UNION SELECT x.seq FROM disclosures x JOIN active_list_entities m ON m.entity_id=x.entity_id JOIN private_lists l ON l.id=m.list_id WHERE l.device_id=?)""",(g.device['id'],)*6)
        return jsonify(ok=True)

    @api.put('/v1/me/push')
    @authenticated
    def push():
        data = body()
        enabled, token, environment = data.get('enabled'), data.get('token'), data.get('environment', 'sandbox')
        if not isinstance(enabled,bool) or environment not in ('sandbox','production') or (enabled and (not isinstance(token,str) or not re.fullmatch('[a-fA-F0-9]{32,512}',token))):
            return jsonify(error='Invalid push registration'), 400
        with closing(store.connect()) as db, db:
            db.execute('BEGIN IMMEDIATE')
            if enabled:
                token = token.lower()
                other = db.execute('SELECT id FROM devices WHERE token=? AND environment=? AND id!=?', (token,environment,g.device['id'])).fetchone()
                if other:
                    return jsonify(error='Push token belongs to another installation'), 409
            db.execute('UPDATE devices SET token=?,environment=?,enabled=? WHERE id=?', (token if enabled else None,environment,int(enabled),g.device['id']))
            if not enabled:
                db.execute("DELETE FROM outbox WHERE device_id=? AND state='pending'",(g.device['id'],))
        return jsonify(ok=True, push_configured=configured())

    @api.delete('/v1/me')
    @authenticated
    def delete():
        with closing(store.connect()) as db, db:
            db.execute('DELETE FROM list_members WHERE list_id IN (SELECT id FROM private_lists WHERE device_id=?)',(g.device['id'],))
            db.execute('DELETE FROM list_entities WHERE list_id IN (SELECT id FROM private_lists WHERE device_id=?)',(g.device['id'],))
            for table in ('problem_reports','private_lists','alert_preferences','entity_follows','subscriptions','category_subscriptions','outbox'):
                db.execute('DELETE FROM '+table+' WHERE device_id=?', (g.device['id'],))
            db.execute('DELETE FROM devices WHERE id=?',(g.device['id'],))
        return jsonify(ok=True)

    @api.get('/v1/me/filings')
    @authenticated
    def watched_filings():
        try:
            before = int(request.args.get('before', str(2**63-1)))
            if before<0 or before>2**63-1: raise ValueError()
        except ValueError:
            return jsonify(error='Invalid cursor'), 400
        with closing(store.connect()) as db:
            rows = [dict(r) for r in db.execute('''SELECT * FROM filings WHERE seq<? AND (committee_key IN (
              SELECT committee_key FROM subscriptions WHERE device_id=? UNION
              SELECT m.committee_key FROM category_members m JOIN category_subscriptions s ON s.category_id=m.category_id
              JOIN categories c ON c.id=m.category_id AND c.verified=1 WHERE s.device_id=? UNION
              SELECT m.committee_key FROM list_members m JOIN private_lists l ON l.id=m.list_id WHERE l.device_id=?)
              OR seq IN (SELECT x.seq FROM disclosures x JOIN active_entity_follows e ON e.entity_id=x.entity_id WHERE e.device_id=?
                UNION SELECT x.seq FROM disclosures x JOIN active_list_entities m ON m.entity_id=x.entity_id JOIN private_lists l ON l.id=m.list_id WHERE l.device_id=?))
              ORDER BY seq DESC LIMIT 51''', (before,)+(g.device['id'],)*5)]
        return jsonify(filings=rows[:50],has_more=len(rows)>50,next_cursor=rows[49]['seq'] if len(rows)>50 else None)

    @api.get('/v1/filings/<int(signed=True):seq>')
    def filing(seq):
        if abs(seq)>2**63-1: return jsonify(error='Not found'),404
        with closing(store.connect()) as db:
            row=lookup_filing(db,seq)
        return (jsonify(dict(row)),200) if row else (jsonify(error='Not found'),404)

    @api.get('/v1/filings/<int(signed=True):seq>/contents')
    @authenticated
    def report_contents(seq):
        if abs(seq) > 2**63-1:
            return jsonify(error='Not found'), 404
        with closing(store.connect()) as db:
            row = lookup_filing(db,seq)
        if row is None:
            return jsonify(error='Not found'), 404
        return jsonify(report_reader.read(dict(row)))

    @api.get('/v1/filings/<int(signed=True):seq>/schedules/<key>')
    @authenticated
    def quarterly_schedule(seq,key):
        if abs(seq)>2**63-1:return jsonify(error='Not found'),404
        with closing(store.connect()) as db:row=lookup_filing(db,seq)
        if row is None:return jsonify(error='Not found'),404
        return jsonify(report_reader.schedule(dict(row),key))

    from observer import install_routes
    install_routes(api,store,authenticated,report_reader)
    from launch_features import install
    install(api,store,authenticated)
    return api


class ApplePush:
    def __init__(self):
        self.tokens = {}
        self.client = None

    def send(self, row):
        import jwt
        import httpx
        environment = row['environment']
        token, generated = self.tokens.get(environment, (None, 0))
        if not token or time.time()-generated>2700:
            generated = time.time()
            key_id, private_key = credentials(environment)
            token = jwt.encode({'iss':os.environ['APNS_TEAM_ID'],'iat':int(generated)},
                private_key.replace('\\n','\n'), algorithm='ES256', headers={'kid':key_id})
            self.tokens[environment] = (token, generated)
        if self.client is None: self.client=httpx.Client(http2=True,timeout=15)
        host='api.sandbox.push.apple.com' if row['environment']=='sandbox' else 'api.push.apple.com'
        payload={'aps':{'alert':{'title':row.get('alert_title',row['committee_name'])[:200],'body':row.get('alert_body',row['report_type'])[:500]},'sound':'default','thread-id':row.get('thread_id','committee-'+str(row.get('committee_key','')))},'filing_seq':row['filing_seq']}
        if row.get('digest_count'):payload['digest']=True
        response=self.client.post('https://'+host+'/3/device/'+row['token'],json=payload,headers={
          'authorization':'bearer '+token,'apns-topic':os.environ['APNS_TOPIC'],'apns-push-type':'alert',
          'apns-priority':'10','apns-expiration':str(int(row['created_at']+3*86400)),
          'apns-collapse-id':'filing-'+str(row['filing_seq'])})
        try: reason=response.json().get('reason','')
        except ValueError: reason=''
        return response.status_code,reason


def dispatch(store, sender, enabled=None):
    if not (configured() if enabled is None else enabled): return
    now=time.time()
    with closing(store.connect()) as db, db:
        db.execute("UPDATE outbox SET state='expired' WHERE state='pending' AND created_at<?",(now-3*86400,))
        db.execute("DELETE FROM outbox WHERE state!='pending' AND created_at<?",(now-30*86400,))
        rows=[dict(r) for r in db.execute('''SELECT o.*, d.token,d.environment,f.committee_name,f.committee_key,f.report_type
          FROM outbox o JOIN devices d ON d.id=o.device_id JOIN filings f ON f.seq=o.filing_seq
          WHERE o.state='pending' AND o.next_attempt<=? AND d.enabled=1 AND d.token IS NOT NULL ORDER BY o.id LIMIT 200''',(now,))]
    from observer import preferences, delivery_time, alert_summary
    eligible=[]
    for row in rows:
        if enabled is None and not configured(row['environment']): continue
        with closing(store.connect()) as db, db:
            current=db.execute('SELECT token FROM devices WHERE id=? AND enabled=1',(row['device_id'],)).fetchone()
            pending=db.execute("SELECT 1 FROM outbox WHERE id=? AND state='pending'",(row['id'],)).fetchone()
            if not current or current['token']!=row['token'] or not pending:continue
            device=row['device_id'];key=row['committee_key']
            subscribed=db.execute('SELECT 1 FROM subscriptions WHERE device_id=? AND committee_key=?',(device,key)).fetchone()
            subscribed=subscribed or db.execute('SELECT 1 FROM category_subscriptions s JOIN category_members m ON s.category_id=m.category_id WHERE s.device_id=? AND m.committee_key=?',(device,key)).fetchone()
            subscribed=subscribed or db.execute('SELECT 1 FROM private_lists l JOIN list_members m ON l.id=m.list_id WHERE l.device_id=? AND m.committee_key=?',(device,key)).fetchone()
            subscribed=subscribed or db.execute('SELECT 1 FROM active_entity_follows f JOIN disclosures x ON f.entity_id=x.entity_id WHERE f.device_id=? AND x.seq=?',(device,row['filing_seq'])).fetchone()
            subscribed=subscribed or db.execute('SELECT 1 FROM private_lists l JOIN active_list_entities m ON m.list_id=l.id JOIN disclosures x ON x.entity_id=m.entity_id WHERE l.device_id=? AND x.seq=?',(device,row['filing_seq'])).fetchone()
            if not subscribed:
                db.execute("UPDATE outbox SET state='cancelled' WHERE id=?",(row['id'],));continue
            p=preferences(db,device);allowed,body=alert_summary(db,row,p)
            if allowed is False:
                db.execute("UPDATE outbox SET state='filtered' WHERE id=?",(row['id'],));continue
            if allowed is None:
                db.execute('UPDATE outbox SET next_attempt=? WHERE id=?',(now+60,row['id']));continue
            due=delivery_time(p,row['created_at'],now)
            if due>now:
                db.execute('UPDATE outbox SET next_attempt=? WHERE id=?',(due,row['id']));continue
            row['alert_body']=body;row['delivery']=p['delivery'];eligible.append(row)
    groups={}
    for row in eligible:
        # Bundle digests; instant reports use iOS thread grouping without dropping any filing.
        key=(row['device_id'],row['delivery']) if row['delivery']!='instant' else (row['id'],)
        groups.setdefault(key,[]).append(row)
    for group in groups.values():
        row=group[-1]
        if row['delivery']!='instant':
            row['digest_count']=len(group);row['alert_title']='Your Illinois filing digest'
            row['alert_body']=f"{len(group)} new reports: "+'; '.join(dict.fromkeys(r['committee_name'] for r in group))
            row['thread_id']='filing-digest'
        try: status,reason=sender.send(row)
        except Exception: status,reason=0,'Transport error'
        state='sent' if status==200 else ('failed' if status in (400,404,405,410,413) else 'pending')
        delay=max(60,min(3600,60*2**min(row['attempts'],6)))
        with closing(store.connect()) as db, db:
            for item in group:
                db.execute('UPDATE outbox SET state=?,attempts=attempts+1,next_attempt=?,last_error=? WHERE id=?',
                    (state,time.time()+delay,None if status==200 else str(status)+': '+reason[:100],item['id']))
            if status==410 or reason=='BadDeviceToken':
                db.execute('UPDATE devices SET enabled=0,token=NULL WHERE id=? AND token=?',(row['device_id'],row['token']))


def lookup_filing(db,seq):
    if seq>=0: return db.execute('SELECT * FROM filings WHERE seq=?',(seq,)).fetchone()
    row=db.execute('SELECT payload FROM archive_reports WHERE seq=?',(-seq,)).fetchone()
    return dict(json.loads(row[0]),seq=seq) if row else None

