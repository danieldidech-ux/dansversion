"""Native, filing-specific electronic D-2 summaries and itemized schedules."""
import re, urllib.parse, hashlib
from decimal import Decimal
from reports import Document, Node, ReportFormatError, normalized
from archive_source import Source, safe_url


def document_id(url):
    q=urllib.parse.parse_qs(urllib.parse.urlsplit(safe_url(url)).query)
    values=q.get('FiledDocID') or q.get('id') or q.get('ID') or []
    if len(values)!=1:raise ReportFormatError('Missing filing identity')
    return values[0]


def is_quarter(url):
    return urllib.parse.urlsplit(url or '').path.lower()=='/campaigndisclosure/d2quarterly.aspx'


def money(text):
    text=text.strip()
    if re.fullmatch(r'\(\$[\d,]+\.\d{2}\)',text):text='-'+text[1:-1]
    if not re.fullmatch(r'-?\$[\d,]+\.\d{2}',text):raise ReportFormatError('Invalid quarterly amount')
    return format(Decimal(text.replace('$','').replace(',','')),'.2f')

# Itemized and unitemized amounts remain separate, exactly as reported.
CATEGORIES=[
 ('individual','Individual contributions','receipts','IndivContrib','hypIndivContribItmzd'),
 ('transfers_in','Transfers in','receipts','XferIn','hypXferInItmzd'),
 ('loans_received','Loans received','receipts','LoanRcv','hypLoanRcvItmzd'),
 ('other_receipts','Other receipts','receipts','OtherRct','hypOtherRctItmzd'),
 ('in_kind','In-kind contributions','in_kind','InKind','hypInKindItmzd'),
 ('transfers_out','Transfers out','expenditures','XferOut','hypXferOutItmzd'),
 ('loans_made','Loans made','expenditures','LoanMade','hypLoanMadeItmzd'),
 ('expenditures','Other expenditures','expenditures','Expend','hypExpendItmzd'),
 ('independent','Independent expenditures','expenditures','IndependentExp','hypItemizedExpenditureIndependent'),
 ('debts','Debts and obligations','debts','Debts','hypDebtsItmzd')]


def parse_quarterly(html,filing):
    expected=document_id(filing['url']);doc=Document(html)
    field=lambda key:doc.by_id('ContentPlaceHolder1_'+key)
    if normalized(field('lblName').text())!=normalized(filing['committee_name']):raise ReportFormatError('Quarterly committee mismatch')
    if 'd-2 quarterly' not in normalized(field('lblReportType').text()):raise ReportFormatError('Not a quarterly report')
    printed=urllib.parse.urljoin(filing['url'],field('lnkPrintList').attrs.get('href',''))
    if document_id(printed)!=expected:raise ReportFormatError('Quarterly document mismatch')
    period=' '.join(field('lblReportPeriod').text().split())
    if filing.get('period') and normalized(period)!=normalized(filing['period']):raise ReportFormatError('Quarterly period mismatch')
    amounts={key:money(field('lbl'+suffix).text()) for key,suffix in [
        ('beginning_cash','BegFundsAvail'),('receipts','TotalReceipts'),('expenditures','TotalExpend'),
        ('ending_cash','EndFundsAvail'),('investments','TotalInvest'),('in_kind','TotalInKind'),('debts','TotalDebts')]}
    amounts['cash_and_investments']=format(Decimal(amounts['ending_cash'])+Decimal(amounts['investments']),'.2f')
    sections=[]
    # Obtain links from the same official row as each verified itemized amount.
    # This also supports older forms with different hyperlink control IDs.
    for key,title,group,prefix,linkid in CATEGORIES:
        amount_node=field('lbl'+prefix+'I')
        itemized=money(amount_node.text());unitemized=money(field('lbl'+prefix+'NI').text())
        candidates=[]
        for tr in doc.root.all('tr'):
            if any(n is amount_node for n in tr.all()):
                candidates.append(tr)
        links=[]
        if candidates:
            for a in candidates[-1].all('a'):
                href=a.attrs.get('href','')
                if 'FiledDocID=' in href:
                    url=safe_url(urllib.parse.urljoin(filing['url'],href))
                    if document_id(url)!=expected:raise ReportFormatError('Schedule linked to a different filing')
                    links.append(url)
        if len(set(links))>1:raise ReportFormatError('Ambiguous itemized schedule')
        sections.append(dict(id=key,title=title,group=group,itemized=itemized,unitemized=unitemized,
                             source_url=links[0] if links else None,has_details=bool(links)))
    investment=field('hypInvestments') if any(n.attrs.get('id')=='ContentPlaceHolder1_hypInvestments' for n in doc.root.all()) else None
    if investment and investment.attrs.get('href'):
        url=safe_url(urllib.parse.urljoin(filing['url'],investment.attrs['href']))
        if document_id(url)!=expected:raise ReportFormatError('Investment document mismatch')
        sections.append(dict(id='investments',title='Investments',group='investments',itemized=amounts['investments'],unitemized='0.00',source_url=url,has_details=True))
    return dict(status='ready',kind='quarterly',period=period,summary=amounts,sections=sections)


def direct_rows(table):
    for n in table.children:
        if isinstance(n,Node):
            if n.tag=='tr':yield n
            elif n.tag in {'tbody','thead','tfoot'}:yield from direct_rows(n)


def schedule_table(doc):
    tables=[n for n in doc.root.all('table') if n.attrs.get('id','').startswith('ContentPlaceHolder1_gv') and 'GridViewPager' not in n.attrs.get('id','')]
    if len(tables)!=1:raise ReportFormatError('Unrecognized itemized schedule table')
    return tables[0]


def parse_schedule(html,filing,section,period):
    doc=Document(html)
    name=doc.by_id('ContentPlaceHolder1_lblName').text()
    if normalized(name)!=normalized(filing['committee_name']):raise ReportFormatError('Schedule committee mismatch')
    periods=[n for n in doc.root.all() if n.attrs.get('id')=='ContentPlaceHolder1_lblReportPeriod']
    if periods and normalized(periods[0].text())!=normalized(period):raise ReportFormatError('Schedule period mismatch')
    table=schedule_table(doc);rows=list(direct_rows(table))
    headings=[n.text().strip() for n in rows[0].children if isinstance(n,Node) and n.tag=='th'] if rows else []
    if not headings or any(not x for x in headings):raise ReportFormatError('Missing schedule column headings')
    totals=re.findall(r'(\d[\d,]*)\s+Total Records',table.text())
    entries=[]
    for row in rows[1:]:
        cells=[n for n in row.children if isinstance(n,Node) and n.tag=='td']
        if any('GridViewPagerTemplate' in n.attrs.get('id','') for n in row.all('table')):
            if not totals:raise ReportFormatError('Missing schedule record count')
            continue
        if len(cells)!=len(headings) or any(n.attrs.get('colspan','1')!='1' for n in cells):
            raise ReportFormatError('Unrecognized schedule row')
        entries.append(dict(id=len(entries)+1,fields=[dict(label=h,value='\n'.join(c.lines())) for h,c in zip(headings,cells)]))
    if totals and len(entries)!=int(totals[-1].replace(',','')):raise ReportFormatError('Incomplete itemized schedule')
    if not totals and any('Page$' in n.attrs.get('href','') for n in table.all('a')):raise ReportFormatError('Incomplete paginated schedule')
    if not entries:raise ReportFormatError('No verified itemized records')
    return dict(status='ready',title=section['title'],period=period,entries=entries,total=len(entries),source_url=section['source_url'])


def fetch_schedule(filing,section,period):
    url=section['source_url']
    if not url or document_id(url)!=document_id(filing['url']):raise ReportFormatError('Invalid schedule source')
    source=Source();html=source.read(url)
    table=schedule_table(Document(html))
    html=source.all_rows(url,html,table.attrs['id'])
    return parse_schedule(html,filing,section,period)
