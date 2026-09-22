"""Bounded diagnostic, not a production alert service. Python 3.10+; no dependencies."""
import argparse
import collections
import hashlib
import json
import os
import threading
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

URL = 'https://www.elections.il.gov/rss/LatestReportsFiled.aspx'
MAX_BYTES = 10 * 1024 * 1024
STATUS = {'state': 'starting', 'checks': []}
LOCK = threading.Lock()


def parse_feed(body):
    if b'<!DOCTYPE' in body.upper() or b'<!ENTITY' in body.upper():
        raise ValueError('Unexpected XML declaration')
    root = ET.fromstring(body)
    if root.tag != 'rss' or root.find('channel') is None:
        raise ValueError('Response is not an RSS channel')
    items = root.findall('./channel/item')
    if not items:
        raise ValueError('Empty feed requires investigation')
    ids = [i.findtext('guid', '').strip() for i in items]
    if not all(ids) or len(ids) != len(set(ids)):
        raise ValueError('Missing or duplicate filing identifiers')
    if any(not i.findtext('title', '').strip() for i in items):
        raise ValueError('Missing committee name')
    return {
        'item_count': len(items),
        'ttl_minutes': root.findtext('./channel/ttl'),
        'first_date_raw': items[0].findtext('pubDate'),
        'last_date_raw': items[-1].findtext('pubDate'),
        'report_types': dict(collections.Counter(
            i.findtext('description', '').split('<br')[0].removeprefix('Report Type: ').strip()
            or 'Unspecified' for i in items)),
        'missing_links': sum(not i.findtext('link') for i in items),
        'sha256': hashlib.sha256(body).hexdigest(),
    }, set(ids)


def fetch():
    started = time.monotonic()
    result = {'checked_at_utc': datetime.now(timezone.utc).isoformat(), 'valid_rss': False}
    request = urllib.request.Request(URL, headers={
        'User-Agent': 'IllinoisFilingTracker/0.1 (RSS availability test)',
        'Accept': 'application/rss+xml, application/xml;q=0.9',
    })
    ids = None
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            result.update(http_status=response.status,
                          content_type=response.headers.get('Content-Type'),
                          server=response.headers.get('Server'))
            body = response.read(MAX_BYTES + 1)
            if len(body) > MAX_BYTES:
                raise ValueError('Response exceeds 10 MiB limit')
            summary, ids = parse_feed(body)
            result.update(summary, valid_rss=True)
    except urllib.error.HTTPError as exc:
        result.update(http_status=exc.code, server=exc.headers.get('Server'),
                      cf_ray=exc.headers.get('CF-Ray'),
                      error='HTTP access failure; no challenge bypass attempted')
    except (urllib.error.URLError, TimeoutError, OSError, ValueError, ET.ParseError) as exc:
        result['error'] = str(exc)
    result['duration_seconds'] = round(time.monotonic() - started, 3)
    return result, ids


def run(checks, interval, output):
    previous = None
    seen = set()
    blocked = 0
    with LOCK:
        STATUS['state'] = 'running'
    for n in range(checks):
        start = time.monotonic()
        result, ids = fetch()
        result['check_number'] = n + 1
        if ids is not None:
            result['new_ids_since_baseline'] = 0 if previous is None else len(ids - seen)
            result['overlap_with_previous_success'] = None if previous is None else len(ids & previous)
            result['possible_gap'] = previous is not None and not bool(ids & previous)
            seen.update(ids)
            previous = ids
        blocked = blocked + 1 if result.get('http_status') in (401, 403, 429) else 0
        line = json.dumps(result)
        print(line, flush=True)
        with open(output, 'a', encoding='utf-8') as f:
            f.write(line + '\n')
        with LOCK:
            STATUS['checks'].append(result)
        if blocked >= 2:
            with LOCK:
                STATUS['state'] = 'stopped_after_repeated_access_denial'
            return
        if n + 1 < checks:
            time.sleep(max(0, interval - (time.monotonic() - start)))
    with LOCK:
        STATUS['state'] = 'completed'


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ('/', '/health', '/status'):
            self.send_error(404)
            return
        with LOCK:
            body = json.dumps(STATUS).encode()
        self.send_response(200)  # Process health only; valid_rss indicates feed health.
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(body)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--checks', type=int, default=3)
    parser.add_argument('--interval', type=int, default=300)
    parser.add_argument('--output', default='probe-results.jsonl')
    parser.add_argument('--serve', action='store_true')
    parser.add_argument('--file', help='Validate a saved feed only; does not test live access')
    args = parser.parse_args()
    if args.file:
        summary, _ = parse_feed(Path(args.file).read_bytes())
        print(json.dumps({'mode': 'saved_file_only', **summary}, indent=2))
    else:
        if not 1 <= args.checks <= 289 or args.interval < 300:
            parser.error('Use 1–289 checks and an interval of at least 300 seconds')
        if args.serve:
            threading.Thread(target=run, args=(args.checks, args.interval, args.output), daemon=True).start()
            ThreadingHTTPServer(('0.0.0.0', int(os.environ.get('PORT', '10000'))), Handler).serve_forever()
        else:
            run(args.checks, args.interval, args.output)
