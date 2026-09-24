"""Durable filing collector, installation watchlists, and APNs dispatch."""
import fcntl
import hashlib
import html
import json
import logging
import os
import re
import shutil
import sqlite3
import threading
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path

from defusedxml import ElementTree as ET
from flask import Flask, jsonify, request, render_template, send_file
from subscriptions import migrate, enqueue, routes, configured, dispatch, ApplePush
from directory import load_directory, sync_directory
from history import History

SOURCE = 'https://www.elections.il.gov/rss/LatestReportsFiled.aspx'
PERIOD = 60
LOG = logging.getLogger('gunicorn.error')


def committee_key(name):
    normalized = ' '.join(unicodedata.normalize('NFKC', name).casefold().split())
    return hashlib.sha256(normalized.encode()).hexdigest()[:32]


def report_link(value):
    if not value:
        return None
    value = value.split('#')[0]
    if value.startswith('~/'):
        value = value[1:]
    url = urllib.parse.urljoin('https://www.elections.il.gov/', value)
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ('http', 'https') or parsed.hostname not in ('www.elections.il.gov', 'elections.il.gov') or parsed.username or parsed.password:
        return None
    return urllib.parse.urlunparse(parsed._replace(scheme='https'))


def parse_feed(data):
    root = ET.fromstring(data)
    if root.tag != 'rss' or root.find('channel') is None:
        raise ValueError('Response is not RSS')
    rows = []
    seen = set()
    for item in root.findall('./channel/item'):
        guid = (item.findtext('guid') or '').strip()
        name = (item.findtext('title') or '').strip()
        if not guid or not name or guid in seen:
            raise ValueError('Missing or duplicate filing identity')
        seen.add(guid)
        description = html.unescape(item.findtext('description') or '')
        parts = re.split(r'<br\s*/?>', description, flags=re.I)
        fields = dict(p.split(':', 1) for p in parts if ':' in p)
        rows.append({
            'guid': guid, 'committee_key': committee_key(name), 'committee_name': name,
            'report_type': fields.get('Report Type', '').strip() or 'Unspecified filing',
            'source': fields.get('Source', '').strip(),
            'published_raw': item.findtext('pubDate'),
            'url': report_link(item.findtext('link')) or report_link(guid),
        })
    if not rows:
        raise ValueError('Empty RSS requires investigation')
    return rows


class Store:
    def __init__(self, directory):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.path = self.directory / 'filings.sqlite3'
        with closing(self.connect()) as db, db:
            db.execute('PRAGMA journal_mode=WAL')
            db.executescript('''
                CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS committees (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS filings (
                    seq INTEGER PRIMARY KEY AUTOINCREMENT, guid TEXT UNIQUE NOT NULL,
                    committee_key TEXT NOT NULL, committee_name TEXT NOT NULL,
                    report_type TEXT NOT NULL, source TEXT, published_raw TEXT, url TEXT,
                    first_seen REAL NOT NULL, baseline INTEGER NOT NULL);
                CREATE INDEX IF NOT EXISTS filings_committee ON filings(committee_key,seq);
                CREATE TABLE IF NOT EXISTS checks (
                    id INTEGER PRIMARY KEY, checked_at REAL NOT NULL, ok INTEGER NOT NULL,
                    http_status INTEGER, duration REAL, item_count INTEGER, new_count INTEGER,
                    overlap INTEGER, error TEXT);
                CREATE TABLE IF NOT EXISTS gaps (
                    id INTEGER PRIMARY KEY, detected_at REAL NOT NULL, previous_success REAL,
                    reason TEXT NOT NULL, resolved INTEGER NOT NULL DEFAULT 0);
            ''')

            migrate(db)
            self.directory_data = load_directory()
            sync_directory(db, self.directory_data)

    def connect(self):
        db = sqlite3.connect(self.path, timeout=20)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA synchronous=FULL')
        return db

    def meta(self, key, default=None, db=None):
        if db is None:
            with closing(self.connect()) as conn:
                return self.meta(key, default, conn)
        r = db.execute('SELECT value FROM metadata WHERE key=?', (key,)).fetchone()
        return json.loads(r[0]) if r else default

    @staticmethod
    def setmeta(db, key, value):
        db.execute('INSERT OR REPLACE INTO metadata VALUES (?,?)', (key, json.dumps(value)))

    def ingest(self, rows, duration=0, now=None):
        now = time.time() if now is None else now
        ids = {r['guid'] for r in rows}
        with closing(self.connect()) as db, db:
            initial = not self.meta('initialized', False, db)
            previous = set(self.meta('previous_ids', [], db))
            overlap = len(ids & previous) if previous else None
            if previous and overlap == 0:
                db.execute('INSERT INTO gaps(detected_at,previous_success,reason) VALUES (?,?,?)',
                           (now, self.meta('last_success', None, db), 'No overlap with last successful snapshot; reconciliation needed'))
            inserted = 0
            # Oldest first: sequence cursors reflect discovery order, not source timestamp.
            for row in reversed(rows):
                db.execute('INSERT INTO committees VALUES (?,?) ON CONFLICT(id) DO NOTHING', (row['committee_key'], row['committee_name']))
                cur = db.execute('''INSERT INTO filings
                    (guid,committee_key,committee_name,report_type,source,published_raw,url,first_seen,baseline)
                    VALUES (:guid,:committee_key,:committee_name,:report_type,:source,:published_raw,:url,:first_seen,:baseline)
                    ON CONFLICT(guid) DO NOTHING''',
                    dict(row, first_seen=now, baseline=int(initial)))
                inserted += cur.rowcount
                if cur.rowcount and not initial:
                    enqueue(db, cur.lastrowid, row['committee_key'], now)
                # Metadata corrections must not create a second filing event.
                db.execute('UPDATE filings SET report_type=?,url=?,source=? WHERE guid=?',
                           (row['report_type'], row['url'], row['source'], row['guid']))
            new_count = 0 if initial else inserted
            db.execute('INSERT INTO checks(checked_at,ok,http_status,duration,item_count,new_count,overlap) VALUES (?,1,200,?,?,?,?)',
                       (now, duration, len(rows), new_count, overlap))
            for key, value in [('initialized', True), ('last_success', now), ('last_attempt', now),
                               ('previous_ids', sorted(ids)), ('failure_count', 0), ('last_error', None)]:
                self.setmeta(db, key, value)
            db.execute('DELETE FROM checks WHERE checked_at < ?', (now-30*86400,))
        return {'initial_baseline': initial, 'inserted': inserted, 'new_filings': new_count, 'overlap': overlap}

    def failure(self, error, status=None, duration=0):
        now = time.time()
        with closing(self.connect()) as db, db:
            db.execute('INSERT INTO checks(checked_at,ok,http_status,duration,error) VALUES (?,0,?,?,?)',
                       (now, status, duration, error[:500]))
            self.setmeta(db, 'last_attempt', now)
            self.setmeta(db, 'last_error', error[:500])
            self.setmeta(db, 'failure_count', self.meta('failure_count', 0, db) + 1)
            db.execute('DELETE FROM checks WHERE checked_at < ?', (now-30*86400,))

    def status(self):
        with closing(self.connect()) as db:
            last = self.meta('last_success', None, db)
            age = round(time.time()-last, 1) if last else None
            checks = [dict(r) for r in db.execute('SELECT * FROM checks ORDER BY id DESC LIMIT 20')]
            gaps = db.execute('SELECT count(*) FROM gaps WHERE resolved=0').fetchone()[0]
            disk = shutil.disk_usage(self.directory)
            return {'source': SOURCE, 'poll_interval_seconds': PERIOD,
                    'last_success_utc': datetime.fromtimestamp(last, timezone.utc).isoformat() if last else None,
                    'age_seconds': age, 'stale': age is None or age>900,
                    'consecutive_failures': self.meta('failure_count', 0, db),
                    'last_error': self.meta('last_error', None, db), 'unresolved_gaps': gaps,
                    'stored_filings': db.execute('SELECT count(*) FROM filings').fetchone()[0],
                    'observed_committees': db.execute('SELECT count(*) FROM committees').fetchone()[0],
                    'disk_free_bytes': disk.free, 'low_disk_space': disk.free < 100*1024*1024,
                    'recent_checks': checks, 'push_notifications_enabled': configured()}

    def backup(self):
        # SQLite's backup API gives a consistent database copy, unlike copying a WAL file.
        folder = self.directory / 'backups'
        folder.mkdir(exist_ok=True)
        target = folder / (datetime.now(timezone.utc).strftime('%Y-%m-%d')+'.sqlite3')
        if target.exists():
            return
        temporary = target.with_suffix('.tmp')
        with closing(self.connect()) as db, closing(sqlite3.connect(temporary)) as backup:
            db.backup(backup)
        os.replace(temporary, target)
        for old in sorted(folder.glob('*.sqlite3'))[:-3]:
            old.unlink()


def collect(store):
    start = time.monotonic()
    try:
        req = urllib.request.Request(SOURCE, headers={
            'User-Agent': 'IllinoisFilingTracker/0.1 (public RSS monitor)',
            'Accept': 'application/rss+xml, application/xml;q=0.9'})
        with urllib.request.urlopen(req, timeout=30) as response:
            data = response.read(10*1024*1024+1)
            if len(data)>10*1024*1024:
                raise ValueError('RSS response too large')
            rows = parse_feed(data)
        result = store.ingest(rows, time.monotonic()-start)
        LOG.info('RSS check %s', json.dumps(result))
    except urllib.error.HTTPError as exc:
        store.failure('RSS HTTP '+str(exc.code), exc.code, time.monotonic()-start)
        LOG.warning('RSS HTTP %s', exc.code)
        return
    except Exception as exc:
        LOG.exception('RSS retrieval or ingestion failed')
        store.failure(type(exc).__name__+': '+str(exc), duration=time.monotonic()-start)
        return
    try:
        store.backup()
    except Exception:
        LOG.exception('Database backup failed; filings remain committed')


def polling_loop(store):
    while True:
        last = store.meta('last_attempt', 0)
        failures = store.meta('failure_count', 0)
        delay = PERIOD if failures == 0 else min(1800, 300*(2**min(failures, 3)))
        time.sleep(max(0, min(delay, last+delay-time.time())))
        try:
            collect(store)
        except Exception:
            LOG.exception('Collector failed; retrying after delay')
            time.sleep(PERIOD)


def notification_loop(store):
    sender = ApplePush()
    while True:
        try:
            dispatch(store, sender)
        except Exception:
            LOG.exception('Notification dispatch failed')
        time.sleep(5)


def observer_loop(store):
    from observer import index_tick
    while True:
        try:index_tick(store)
        except Exception:LOG.exception('Disclosure indexing failed; retrying')
        time.sleep(5)


def create_app(directory=None, poll=True):
    directory = directory or os.environ.get('DATA_DIR', './data')
    if os.environ.get('REQUIRE_PERSISTENT_DISK') == '1' and not os.path.ismount(directory):
        raise RuntimeError('Persistent disk not mounted; refusing to start with ephemeral history')
    store = Store(directory)
    app = Flask(__name__)
    app.config['STORE'] = store
    app.config['PRELOAD_SUMMARIES'] = poll
    history = History(store)
    app.config['HISTORY'] = history
    app.config['MAX_CONTENT_LENGTH'] = 64*1024
    app.register_blueprint(routes(store))
    worker = None
    startup_lock = threading.Lock()

    @app.before_request
    def start_collector_in_serving_process():
        # Gunicorn may load the app in its parent process. Threads do not survive
        # fork. Render's first health request starts polling in the serving worker.
        nonlocal worker
        if not poll or worker is not None:
            return
        with startup_lock:
            if worker is None:
                lock = open(Path(directory)/'collector.lock', 'a')
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except Exception:
                    lock.close()
                    raise
                app.config['COLLECTOR_LOCK'] = lock
                worker = threading.Thread(target=polling_loop, args=(store,), daemon=True)
                worker.start()
                notifications = threading.Thread(target=notification_loop, args=(store,), daemon=True)
                app.config['NOTIFICATION_WORKER'] = notifications
                notifications.start()
                indexing=threading.Thread(target=observer_loop,args=(store,),daemon=True)
                app.config['INDEX_WORKER']=indexing
                indexing.start()
                estimates=threading.Thread(target=history.maintain,daemon=True)
                app.config['ESTIMATE_WORKER']=estimates
                estimates.start()

    @app.after_request
    def security(response):
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Cache-Control'] = 'no-store'
        response.headers['Content-Security-Policy'] = "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'"
        return response

    @app.get('/v1/committees/<key>/history')
    def committee_history(key):
        if not history.schedule(key): return jsonify(error='Unknown committee'),404
        try:
            cursor=int(request.args['before']) if 'before' in request.args else None
            if cursor is not None and cursor>=0: raise ValueError()
        except ValueError: return jsonify(error='Invalid archive cursor'),400
        return jsonify(history.page(key,cursor))

    @app.get('/v1/committees/<key>/finance')
    def committee_finance(key):
        if not history.schedule(key): return jsonify(error='Unknown committee'),404
        return jsonify(history.finance(key))

    @app.get('/v1/committee-finances')
    def committee_finances():
        group=request.args.get('group')
        groups=[g for g in store.directory_data['groups'] if g['id']==group] if group else store.directory_data['groups']
        keys={e['committee']['id'] for g in groups for e in g['pinned']+g['members'] if e['committee']}
        for key in sorted(keys): history.schedule(key,priority=1)
        return jsonify(committees={key:history.finance(key) for key in keys})

    @app.get('/downloads/IllinoisTracker-v20.zip')
    def download20_observer_iphone_project():
        archive = Path(__file__).resolve().parent.parent / 'releases' / 'IllinoisTracker-iPhone-Source-v20.zip'
        return send_file(archive, mimetype='application/zip', as_attachment=True,
                         download_name='IllinoisTracker-iPhone-Source-v20.zip', conditional=True)

    @app.get('/downloads/IllinoisTracker-v19.zip')
    def download19_observer_iphone_project():
        archive = Path(__file__).resolve().parent.parent / 'releases' / 'IllinoisTracker-iPhone-Source-v19.zip'
        return send_file(archive, mimetype='application/zip', as_attachment=True,
                         download_name='IllinoisTracker-iPhone-Source-v19.zip', conditional=True)

    @app.get('/downloads/IllinoisTracker-v18.zip')
    def download18_observer_iphone_project():
        archive = Path(__file__).resolve().parent.parent / 'releases' / 'IllinoisTracker-iPhone-Source-v18.zip'
        return send_file(archive, mimetype='application/zip', as_attachment=True,
                         download_name='IllinoisTracker-iPhone-Source-v18.zip', conditional=True)

    @app.get('/downloads/IllinoisTracker-v17.zip')
    def download17_observer_iphone_project():
        archive = Path(__file__).resolve().parent.parent / 'releases' / 'IllinoisTracker-iPhone-Source-v17.zip'
        return send_file(archive, mimetype='application/zip', as_attachment=True,
                         download_name='IllinoisTracker-iPhone-Source-v17.zip', conditional=True)

    @app.get('/downloads/IllinoisTracker-v16.zip')
    def download16_observer_iphone_project():
        archive = Path(__file__).resolve().parent.parent / 'releases' / 'IllinoisTracker-iPhone-Source-v16.zip'
        return send_file(archive, mimetype='application/zip', as_attachment=True,
                         download_name='IllinoisTracker-iPhone-Source-v16.zip', conditional=True)

    @app.get('/downloads/IllinoisTracker-v15.zip')
    def download15_observer_iphone_project():
        archive = Path(__file__).resolve().parent.parent / 'releases' / 'IllinoisTracker-iPhone-Source-v15.zip'
        return send_file(archive, mimetype='application/zip', as_attachment=True,
                         download_name='IllinoisTracker-iPhone-Source-v15.zip', conditional=True)

    @app.get('/downloads/IllinoisTracker-v14.zip')
    def download14_observer_iphone_project():
        archive = Path(__file__).resolve().parent.parent / 'releases' / 'IllinoisTracker-iPhone-Source-v14.zip'
        return send_file(archive, mimetype='application/zip', as_attachment=True,
                         download_name='IllinoisTracker-iPhone-Source-v14.zip', conditional=True)

    @app.get('/downloads/IllinoisTracker-v13.zip')
    def download_observer_iphone_project():
        archive = Path(__file__).resolve().parent.parent / 'releases' / 'IllinoisTracker-iPhone-Source-v13.zip'
        return send_file(archive, mimetype='application/zip', as_attachment=True,
                         download_name='IllinoisTracker-iPhone-Source-v13.zip', conditional=True)

    @app.get('/downloads/IllinoisTracker-v11.zip')
    def download_executive_iphone_project():
        archive = Path(__file__).resolve().parent.parent / 'releases' / 'IllinoisTracker-iPhone-Source-v11.zip'
        return send_file(archive, mimetype='application/zip', as_attachment=True,
                         download_name='IllinoisTracker-iPhone-Source-v11.zip', conditional=True)

    @app.get('/downloads/IllinoisTracker-v10.zip')
    def download_refined_home_iphone_project():
        archive = Path(__file__).resolve().parent.parent / 'releases' / 'IllinoisTracker-iPhone-Source-v10.zip'
        return send_file(archive, mimetype='application/zip', as_attachment=True,
                         download_name='IllinoisTracker-iPhone-Source-v10.zip', conditional=True)

    @app.get('/downloads/IllinoisTracker-v9.zip')
    def download_colorful_iphone_project():
        archive = Path(__file__).resolve().parent.parent / 'releases' / 'IllinoisTracker-iPhone-Source-v9.zip'
        return send_file(archive, mimetype='application/zip', as_attachment=True,
                         download_name='IllinoisTracker-iPhone-Source-v9.zip', conditional=True)

    @app.get('/downloads/IllinoisTracker-v8.zip')
    def download_home_iphone_project():
        archive = Path(__file__).resolve().parent.parent / 'releases' / 'IllinoisTracker-iPhone-Source-v8.zip'
        return send_file(archive, mimetype='application/zip', as_attachment=True,
                         download_name='IllinoisTracker-iPhone-Source-v8.zip', conditional=True)

    @app.get('/downloads/IllinoisTracker-v7.zip')
    def download_themed_iphone_project():
        archive = Path(__file__).resolve().parent.parent / 'releases' / 'IllinoisTracker-iPhone-Source-v7.zip'
        return send_file(archive, mimetype='application/zip', as_attachment=True,
                         download_name='IllinoisTracker-iPhone-Source-v7.zip', conditional=True)

    @app.get('/downloads/IllinoisTracker-v6.zip')
    def download_history_iphone_project():
        archive = Path(__file__).resolve().parent.parent / 'releases' / 'IllinoisTracker-iPhone-Source-v6.zip'
        return send_file(archive, mimetype='application/zip', as_attachment=True,
                         download_name='IllinoisTracker-iPhone-Source-v6.zip', conditional=True)

    @app.get('/v1/pac-source-inspection')
    def pac_source_inspection():
        from archive_source import Source, BASE
        from reports import Document
        source=Source()
        page=request.args.get('page','CommitteeSearch.aspx')
        if page not in ('CommitteeSearch.aspx','LatestCommitteeTotalsByLatest.aspx'):return jsonify(error='Unknown source'),400
        doc=Document(source.read(BASE+page))
        return jsonify(fields=[dict(tag=n.tag,attrs={k:v for k,v in n.attrs.items() if k in ('id','name','type','value','href')},text=n.text()[:6000],options=[dict(value=o.attrs.get('value'),text=o.text()) for o in n.all('option')]) for tag in ('select','input','a') for n in doc.root.all(tag) if n.attrs.get('type')!='hidden'], text=doc.root.text()[-16000:])

    @app.get('/v1/coverage')
    def committee_coverage():
        entries=[]
        for group in store.directory_data['groups']:
            for entry in group['pinned']+group['members']:
                committee=entry['committee']
                if not committee:
                    entries.append(dict(group=group['name'],member=entry['member'],district=entry['district'],committee=None,finance=dict(status='unmapped',message='No committee assigned in directory')))
                    continue
                state=history.state(committee['id'])
                entries.append(dict(group=group['name'],member=entry['member'],district=entry['district'],committee=committee,official_url=entry.get('official_url'),
                    finance=history.finance(committee['id']),history=json.loads(state['payload']) if state else None,checked_at=state['checked'] if state else None))
        with history.lock:
            active=sorted(history.active)
            queued=len(history.pending)-len(active)
        return jsonify(revision=store.directory_data['revision'],entries=entries,queued=queued,active=active,
                       estimate_workers=sum(w.is_alive() for w in history.workers),estimate_refresh='balanced-v1')

    @app.get('/v1/directory')
    def caucus_directory():
        return jsonify(store.directory_data)

    @app.get('/downloads/IllinoisTracker-v5.zip')
    def download_directory_iphone_project():
        archive = Path(__file__).resolve().parent.parent / 'releases' / 'IllinoisTracker-iPhone-Source-v5.zip'
        return send_file(archive, mimetype='application/zip', as_attachment=True,
                         download_name='IllinoisTracker-iPhone-Source-v5.zip', conditional=True)

    @app.get('/downloads/IllinoisTracker-v4.zip')
    def download_color_coded_iphone_project():
        archive = Path(__file__).resolve().parent.parent / 'releases' / 'IllinoisTracker-iPhone-Source-v4.zip'
        return send_file(archive, mimetype='application/zip', as_attachment=True,
                         download_name='IllinoisTracker-iPhone-Source-v4.zip', conditional=True)

    @app.get('/downloads/IllinoisTracker-v3.zip')
    def download_iphone_project():
        archive = Path(__file__).resolve().parent.parent / 'releases' / 'IllinoisTracker-iPhone-Source-v3.zip'
        return send_file(archive, mimetype='application/zip', as_attachment=True,
                         download_name='IllinoisTracker-iPhone-Source-v3.zip', conditional=True)

    @app.get('/healthz')
    def health():
        notifier = app.config.get('NOTIFICATION_WORKER')
        healthy = (worker is None or worker.is_alive()) and (notifier is None or notifier.is_alive())
        with closing(store.connect()) as db:
            db.execute('SELECT 1')
        return jsonify({'ok': healthy}), 200 if healthy else 503

    @app.get('/v1/status')
    def status():
        return jsonify(store.status())

    @app.get('/readyz')
    def ready():
        state = store.status()
        good = not state['stale'] and not state['unresolved_gaps'] and not state['low_disk_space']
        return jsonify({'ready': good, 'last_success_utc': state['last_success_utc']}), 200 if good else 503

    @app.get('/v1/filings')
    def filings():
        try:
            limit = min(100, max(1, int(request.args.get('limit', '50'))))
            before = int(request.args.get('before', str(2**63-1)))
            after = int(request.args.get('after', '0'))
            if before<0 or after<0 or before>2**63-1 or after>2**63-1:
                raise ValueError()
        except ValueError:
            return jsonify({'error': 'Invalid pagination'}), 400
        ascending = 'after' in request.args
        query = 'SELECT * FROM filings WHERE seq<? AND seq>?'
        args = [before, after]
        if request.args.get('committee'):
            query += ' AND committee_key=?'
            args.append(request.args['committee'])
        query += ' ORDER BY seq '+('ASC' if ascending else 'DESC')+' LIMIT ?'
        with closing(store.connect()) as db:
            rows = [dict(r) for r in db.execute(query, args+[limit+1])]
        more = len(rows)>limit
        rows = rows[:limit]
        return jsonify({'filings': rows, 'has_more': more,
                        'next_cursor': rows[-1]['seq'] if rows else None,
                        'cursor_parameter': 'after' if ascending else 'before',
                        'ordering': 'discovery_order', 'source_timezone_confirmed': False})

    @app.get('/v1/committees')
    def committees():
        q = request.args.get('q', '')[:100]
        after = request.args.get('after', '')[:64]
        with closing(store.connect()) as db:
            rows = [dict(r) for r in db.execute(
                'SELECT id,name FROM committees WHERE instr(lower(name),lower(?))>0 AND id>? ORDER BY id LIMIT 101', (q, after))]
        more = len(rows)>100
        rows = rows[:100]
        return jsonify({'committees': rows, 'has_more': more,
                        'next_cursor': rows[-1]['id'] if rows else None,
                        'coverage': 'Reviewed legislative directory and committees observed in monitored filings; not the complete state directory',
                        'ids_are_official': False, 'categories_available': True})

    @app.get('/')
    def home():
        with closing(store.connect()) as db:
            rows = [dict(r) for r in db.execute('SELECT * FROM filings ORDER BY seq DESC LIMIT 30')]
        return render_template('status.html', status=store.status(), filings=rows)

    return app
