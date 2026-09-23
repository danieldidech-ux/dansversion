"""Read filing-specific A-1 tables. Never infer contributions from RSS or totals."""
import json
import re
import threading
import time
import urllib.parse
import urllib.request
from contextlib import closing
from datetime import datetime
from decimal import Decimal
from html.parser import HTMLParser


class ReportFormatError(ValueError):
    pass


class Node:
    def __init__(self, tag='', attrs=()):
        self.tag, self.attrs, self.children = tag, dict(attrs), []

    def all(self, tag=None):
        for child in self.children:
            if isinstance(child, Node):
                if tag is None or child.tag == tag:
                    yield child
                yield from child.all(tag)

    def text(self):
        return ''.join(c.text() if isinstance(c, Node) else c for c in self.children)

    def lines(self):
        return [' '.join(line.split()) for line in self.text().splitlines() if line.strip()]


class Document(HTMLParser):
    def __init__(self, html):
        super().__init__(convert_charrefs=True)
        self.root = Node()
        self.stack = [self.root]
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs)
        self.stack[-1].children.append(node)
        if tag == 'br':
            node.children.append('\n')
        if tag not in {'area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr'}:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        self.handle_endtag(tag)

    def handle_endtag(self, tag):
        for index in range(len(self.stack)-1, 0, -1):
            if self.stack[index].tag == tag:
                del self.stack[index:]
                break

    def handle_data(self, data):
        self.stack[-1].children.append(data)

    def by_id(self, identifier):
        matches = [n for n in self.root.all() if n.attrs.get('id') == identifier]
        if len(matches) != 1:
            raise ReportFormatError('Missing or ambiguous report field')
        return matches[0]


def normalized(value):
    return ' '.join(value.split()).casefold()


def filing_id(url):
    p = urllib.parse.urlsplit(url)
    q = urllib.parse.parse_qs(p.query)
    if (p.scheme != 'https' or p.hostname not in {'www.elections.il.gov','elections.il.gov'}
            or p.username or p.password or p.port not in (None,443)
            or p.path.lower() != '/campaigndisclosure/a1list.aspx'
            or len(q.get('FiledDocID', [])) != 1 or ('ID' in q and q['ID'] != q['FiledDocID'])):
        raise ReportFormatError('Not a filing-specific A-1 URL')
    return q['FiledDocID'][0]


def parse_a1(html, filing):
    expected_id = filing_id(filing['url'])
    doc = Document(html)
    field = lambda suffix: doc.by_id('ContentPlaceHolder1_'+suffix)
    if normalized(field('lblName').text()) != normalized(filing['committee_name']):
        raise ReportFormatError('Committee mismatch')
    if normalized(field('lblReportType').text()) != normalized(filing['report_type']):
        raise ReportFormatError('Report type mismatch')
    # The printable document link independently identifies the selected filing.
    printed = urllib.parse.parse_qs(urllib.parse.urlsplit(field('lnkPrintList').attrs.get('href','')).query)
    if printed.get('FiledDocID') != [expected_id]:
        raise ReportFormatError('Filing document mismatch')
    table = field('gvA1List')
    if any('Page$' in n.attrs.get('href','') for n in table.all('a')):
        raise ReportFormatError('Paginated report requires full-document reader')
    def direct_rows(node):
        for child in node.children:
            if isinstance(child, Node):
                if child.tag == 'tr': yield child
                elif child.tag in {'tbody','thead','tfoot'}: yield from direct_rows(child)
    rows = list(direct_rows(table))
    totals = re.findall(r'(\d[\d,]*)\s+Total Records', table.text())
    headings = ['Contributed By','Address','Amount','Received By','Description','Vendor Name','Vendor Address']
    if not rows or [n.text().strip() for n in rows[0].all('th')] != headings:
        raise ReportFormatError('Unrecognized A-1 columns')
    entries = []
    for row in rows[1:]:
        cells = [n for n in row.children if isinstance(n,Node) and n.tag == 'td']
        if (len(cells) == 1 and cells[0].attrs.get('colspan') == '7'
                and any(n.attrs.get('id','') == 'ContentPlaceHolder1_gvA1List_GridViewPagerTemplate' for n in cells[0].all('table'))):
            if not totals: raise ReportFormatError('Missing contribution count')
            continue
        if len(cells) != 7 or any(n.attrs.get('colspan','1') != '1' for n in cells):
            raise ReportFormatError('Unrecognized contribution row')
        contributor, address, amount, recipient, description, vendor, vendor_address = [n.lines() for n in cells]
        if (not contributor or len(amount) != 2 or len(recipient) != 2
                or normalized(recipient[1]) != normalized(filing['committee_name'])):
            raise ReportFormatError('Incomplete contribution')
        if not re.fullmatch(r'\$(?:\d{1,3}(?:,\d{3})*|\d+)\.\d{2}', amount[0]):
            raise ReportFormatError('Invalid contribution amount')
        value = Decimal(amount[0].replace('$','').replace(',',''))
        date = datetime.strptime(amount[1], '%m/%d/%Y').date().isoformat()
        entries.append(dict(id=len(entries)+1, contributor=' '.join(contributor), address='\n'.join(address),
            amount=format(value,'.2f'), received_date=date, contribution_type=recipient[0],
            description=' '.join(description), vendor=' '.join(vendor), vendor_address='\n'.join(vendor_address)))
    if totals and len(entries) != int(totals[-1].replace(',','')):
        raise ReportFormatError('Incomplete contribution table')
    if not entries or len(entries)>1000:
        raise ReportFormatError('No verified contribution rows')
    return dict(status='ready', contributions=entries, period=' '.join(field('lblReportPeriod').text().split()),
                total=format(sum((Decimal(e['amount']) for e in entries),Decimal(0)),'.2f'))


class FilingRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if filing_id(newurl) != filing_id(req.full_url):
            raise ReportFormatError('Redirect changed filing identity')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch_report(filing):
    from quarterly import is_quarter, parse_quarterly
    from archive_source import Source
    if is_quarter(filing['url']):
        return parse_quarterly(Source().read(filing['url']),filing)
    filing_id(filing['url'])
    source = Source()
    html = source.read(filing['url'])
    html = source.all_rows(filing['url'], html, 'gvA1List')
    return parse_a1(html, filing)



class ReportReader:
    def __init__(self, store):
        self.store = store
        self.slots = threading.BoundedSemaphore(2)
        self.locks = [threading.Lock() for _ in range(16)]
        with closing(store.connect()) as db, db:
            db.execute('CREATE TABLE IF NOT EXISTS schedule_cache (url TEXT PRIMARY KEY, expires REAL, payload TEXT)')
            db.execute('CREATE TABLE IF NOT EXISTS report_cache (seq INTEGER PRIMARY KEY, source_url TEXT, expires REAL, payload TEXT)')

    def read(self, filing):
        try:
            from quarterly import is_quarter, document_id
            if is_quarter(filing['url']):document_id(filing['url'])
            else:filing_id(filing['url'] or '')
        except (ValueError, TypeError):
            return dict(status='unsupported', message='This report format is not available in the app yet. Open the official report below to read it.')
        with self.locks[filing['seq'] % len(self.locks)]:
            with closing(self.store.connect()) as db:
                cached = db.execute('SELECT payload FROM report_cache WHERE seq=? AND source_url=? AND expires>?',
                    (filing['seq'],filing['url'],time.time())).fetchone()
            if cached:
                result=json.loads(cached[0])
                return self.index(filing,result)
            if not self.slots.acquire(blocking=False):
                return dict(status='unavailable',message='Reports are busy loading. Please try again shortly.')
            try:
                try:
                    result = fetch_report(filing)
                except Exception:
                    # Fail closed: never substitute another filing, a quarter total, or an empty list.
                    result = dict(status='unavailable',message='We could not read every entry in this report. Try again, or open the official report below.')
                ttl = 3600 if result['status']=='ready' else 30
                with closing(self.store.connect()) as db, db:
                    db.execute('DELETE FROM report_cache WHERE expires<?',(time.time(),))
                    db.execute('INSERT OR REPLACE INTO report_cache VALUES (?,?,?,?)',
                        (filing['seq'],filing['url'],time.time()+ttl,json.dumps(result)))
                return self.index(filing,result)
            finally:
                self.slots.release()

    def index(self,filing,result):
        from observer import index_has_space
        if result.get('status')=='ready' and index_has_space(self.store):
            with closing(self.store.connect()) as db,db:
                db.execute('INSERT OR REPLACE INTO shared_reports VALUES (?,?)',(filing['seq'],json.dumps(result)))
        if result.get('status')=='ready' and result.get('contributions'):
            from observer import index_entries
            index_entries(self.store,filing,result['contributions'])
        return result

    def schedule(self,filing,key):
        from quarterly import fetch_schedule
        parent=self.read(filing)
        if parent.get('kind')!='quarterly' or parent.get('status')!='ready':
            return dict(status='unavailable',message='Load the quarterly summary first, then try again.')
        section=next((s for s in parent['sections'] if s['id']==key and s['has_details']),None)
        if section is None:return dict(status='unsupported',message='No itemized schedule is linked for this category.')
        url=section['source_url']
        with self.locks[filing['seq'] % len(self.locks)]:
            with closing(self.store.connect()) as db:
                row=db.execute('SELECT payload FROM schedule_cache WHERE url=? AND expires>?',(url,time.time())).fetchone()
            if row:
                result=json.loads(row[0])
                from observer import index_schedule
                index_schedule(self.store,filing,key,result)
                return result
            if not self.slots.acquire(blocking=False):return dict(status='unavailable',message='Reports are busy loading. Please try again shortly.')
            try:
                try:result=fetch_schedule(filing,section,parent['period'])
                except Exception as exc:
                    import logging
                    logging.getLogger('gunicorn.error').warning('Quarterly schedule %s: %s',key,str(exc))
                    result=dict(status='unavailable',message='The itemized schedule could not be read completely. Please try again.',diagnostic=str(exc)[:200])
                with closing(self.store.connect()) as db,db:
                    db.execute('DELETE FROM schedule_cache WHERE expires<?',(time.time(),))
                    db.execute('INSERT OR REPLACE INTO schedule_cache VALUES (?,?,?)',(url,time.time()+(3600 if result['status']=='ready' else 30),json.dumps(result)))
                from observer import index_schedule
                index_schedule(self.store,filing,key,result)
                return result
            finally:self.slots.release()
