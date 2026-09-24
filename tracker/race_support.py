"""Dated, disclosed in-kind receipts. Never part of a candidate's cash estimate."""
import calendar, hashlib, json, logging, time
from contextlib import closing
from datetime import date, datetime, timedelta
from decimal import Decimal
from archive_source import Source, OfficialPDFError
from history import previous_quarter_end
from reports import ReportFormatError, normalized
from quarterly import parse_quarterly, fetch_schedule, money

START = '2026-03-18'
NOTE = ('In-kind goods and services received March 18, 2026 onward. Uses quarterly disclosures and A-1s outside the covered quarterly periods, by receipt date. Not cash; not added to the estimated balance. Does not include independent spending by outside groups or support not yet disclosed.')

def period(report):
    parts=report['period'].split(' to ')
    if len(parts)!=2:raise ReportFormatError('Unrecognized report period')
    start,end=(datetime.strptime(p.strip(),'%m/%d/%Y').date().isoformat() for p in parts)
    if start>end:raise ReportFormatError('Reversed report period')
    return start,end

def schedule_receipt(entry):
    fields={normalized(f['label']):f['value'] for f in entry['fields']}
    dates=[v for k,v in fields.items() if k in ('date','date received','received date','receipt date')]
    # ISBE's in-kind schedule places the receipt date on the second line
    # of Amount; other electronic layouts expose a separate date column.
    amount_lines=fields.get('amount','').split('\n')
    if not dates and len(amount_lines)==2:dates=[amount_lines[1]]
    if len(dates)!=1:raise ReportFormatError('In-kind receipt date could not be identified')
    received=datetime.strptime(dates[0].strip(),'%m/%d/%Y').date().isoformat()
    if 'amount' not in fields:raise ReportFormatError('In-kind amount missing')
    return received,Decimal(money(fields['amount'].split('\n')[0]))

def calculate(rows,created,quarter,schedule,a1,through=None):
    """Quarterly periods replace A-1s for those dates, including late-filed A-1s."""
    through=through or previous_quarter_end()
    total=Decimal(0);issues=[];covered=[];sources=[];seen=set()
    def issue(message):
        if message not in issues:issues.append(message)
    quarters={}
    for r in rows:
        if 'd-2 quarterly' not in r['report_type'].lower():continue
        bounds=period(r)
        if bounds[1]<START:continue
        old=quarters.get(bounds)
        if old is None or r['filed_at']>old['filed_at']:quarters[bounds]=r
        elif r['filed_at']==old['filed_at'] and r['document_id']!=old['document_id']:
            raise ReportFormatError('Two quarterly versions have the same filing time; review required')
    previous=None
    for bounds,r in sorted(quarters.items()):
        lo,hi=bounds
        if previous and lo<=previous:raise ReportFormatError('Overlapping quarterly periods require review')
        previous=hi
        try:
            detail=quarter(r)
            section=next(s for s in detail['sections'] if s['id']=='in_kind')
            reported=Decimal(detail['summary']['in_kind'])
            if reported!=Decimal(section['itemized'])+Decimal(section['unitemized']):
                raise ReportFormatError('In-kind summary does not reconcile')
            value=reported
            if lo<START:
                value=Decimal(0)
                if Decimal(section['itemized']):
                    entries=schedule(r,section,detail['period'])['entries']
                    for entry in entries:
                        received,amount=schedule_receipt(entry)
                        if not lo<=received<=hi:raise ReportFormatError('Receipt outside quarterly period')
                        if received>=START:value+=amount
                if Decimal(section['unitemized']):
                    issue('The quarter containing the primary includes undated unitemized support; that portion cannot be assigned to the post-primary period and is excluded.')
            total+=value;covered.append(bounds)
            sources.append(dict(report_type=r['report_type'],period=r['period'],url=r['url'],amount=format(value,'.2f')))
        except OfficialPDFError:
            issue('PDF-only quarterly filings are excluded; available A-1s cover those dates instead.')
        except Exception as exc:
            issue('A quarterly period could not be fully read; available A-1s cover those dates instead.')
            logging.getLogger('gunicorn.error').warning('In-kind quarter %s: %s',r.get('document_id'),exc)
    # Never present missing historical quarterly coverage as a verified zero.
    required_start=max(START,datetime.strptime(created,'%m/%d/%Y').date().isoformat()) if created else START
    cursor=date.fromisoformat(required_start);last=date.fromisoformat(through)
    while cursor<=last:
        end_month=((cursor.month-1)//3+1)*3
        end=date(cursor.year,end_month,calendar.monthrange(cursor.year,end_month)[1])
        stop=min(end,last)
        if not any(lo<=cursor.isoformat() and hi>=stop.isoformat() for lo,hi in covered):
            issue('Quarterly coverage is incomplete for part of the post-primary period; the total includes only verified disclosures.')
        cursor=end+timedelta(days=1)
    seen_docs=set()
    for r in sorted(rows,key=lambda x:x['filed_at']):
        if not r['report_type'].lower().startswith('a-1') or r['filed_at'][:10]<START:continue
        # A-1s filed within an already covered quarter cannot add post-quarter receipts.
        if any(lo<=r['filed_at'][:10]<=hi for lo,hi in covered):continue
        if r['document_id'] in seen_docs:continue
        seen_docs.add(r['document_id'])
        try:detail=a1(r)
        except OfficialPDFError:
            issue('PDF-only A-1 filings are excluded.');continue
        except Exception:
            issue('An A-1 could not be fully read and is excluded.');continue
        relevant=[]
        for e in detail['contributions']:
            received=e['received_date']
            date.fromisoformat(received)
            if received<START or any(lo<=received<=hi for lo,hi in covered):continue
            kind=normalized(e['contribution_type']).replace('–','-')
            if 'in-kind' in kind or 'in kind' in kind:relevant.append(e)
        if not relevant:continue
        if 'amend' in r['report_type'].lower() or r.get('clarification'):
            raise ReportFormatError('An in-kind A-1 amendment or clarification needs review')
        current=set();value=Decimal(0)
        for e in relevant:
            fingerprint=tuple(normalized(str(e.get(k,''))) for k in ('contributor','address','amount','received_date','contribution_type','description','vendor'))
            if fingerprint in seen:raise ReportFormatError('Possible duplicate in-kind A-1 receipts need review')
            current.add(fingerprint);value+=Decimal(e['amount'])
        seen.update(current);total+=value
        sources.append(dict(report_type=r['report_type'],period=r.get('period',''),url=r['url'],amount=format(value,'.2f')))
    if any(r['report_type']=='Unlabeled official record' and r['filed_at'][:10]>=START for r in rows):
        issue('An unlabeled official filing needs review.')
    return dict(status='partial' if issues else 'ready',amount=format(total,'.2f'),since=START,note=NOTE,issues=issues,sources=sources)

class RaceSupport:
    def __init__(self,spotlight):self.spotlight=spotlight;self.history=spotlight.history
    def get(self,key):
        saved=self.spotlight.cached('post-primary:'+key)
        if not saved:return dict(status='loading',amount=None,since=START,note=NOTE,issues=[],sources=[])
        checked,result=saved
        # Resolve the exact archived filing so clients can open native contents.
        with closing(self.history.store.connect()) as db:
            filings={r['url']:r for row in db.execute('SELECT seq,payload FROM archive_reports WHERE committee_key=?',(key,))
                     for r in [dict(json.loads(row['payload']),seq=-row['seq'])]}
        covered=[period(source) for source in result.get('sources',[]) if 'd-2 quarterly' in source['report_type'].lower()]
        for source in result.get('sources',[]):
            source['filing']=filings.get(source['url'])
            source['excluded_periods']=covered if source['report_type'].lower().startswith('a-1') else []
        state=self.history.state(key)
        verified=min(checked,state['checked']) if state else checked
        return dict(result,checked_at=verified,stale=verified<time.time()-1800)
    def refresh(self,key):
        state=self.history.state(key)
        if not state or not state['complete']:return
        with closing(self.history.store.connect()) as db:
            rows=[json.loads(r[0]) for r in db.execute('SELECT payload FROM archive_reports WHERE committee_key=?',(key,))]
        created=json.loads(state['payload']).get('creation_date')
        signature=hashlib.sha256(json.dumps([START,created,rows],sort_keys=True).encode()).hexdigest()
        saved=self.spotlight.cached('post-primary:'+key)
        if saved:
            checked,result=saved
            if result.get('signature')==signature and checked>time.time()-300:return
            if result.get('signature')==signature and result['status']=='ready' and result.get('calculated_at',0)>time.time()-86400:
                self.spotlight.save('post-primary:'+key,result);return
        source=Source()
        try:
            result=calculate(rows,created,
                lambda r:parse_quarterly(self.history.document(source,r['url']),r),
                fetch_schedule,lambda r:self.history.part(source,r))
        except Exception as exc:
            logging.getLogger('gunicorn.error').warning('Post-primary in-kind %s: %s',key,exc)
            result=dict(status='unavailable',amount=None,since=START,note=NOTE,issues=[str(exc)],sources=[])
        self.spotlight.save('post-primary:'+key,dict(result,signature=signature,calculated_at=time.time()))
