"""Fetch only the PDF attached to a stored official filing."""
import io,threading,urllib.parse,urllib.request,http.cookiejar
from contextlib import closing
from flask import jsonify,send_file
from reports import Document,ReportFormatError
SLOTS=threading.BoundedSemaphore(2)
LIMIT=20_000_000

def official(url):
 p=urllib.parse.urlsplit(url)
 if p.scheme!='https' or p.hostname not in ('www.elections.il.gov','elections.il.gov') or p.username or p.password or p.port not in (None,443):raise ReportFormatError('Invalid PDF source')
 return url
class Redirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,req,fp,code,msg,headers,newurl):
  official(newurl)
  before=urllib.parse.parse_qs(urllib.parse.urlsplit(req.full_url).query).get('FiledDocID')
  after=urllib.parse.parse_qs(urllib.parse.urlsplit(newurl).query).get('FiledDocID')
  if before and after and before!=after:raise ReportFormatError('PDF redirect changed filing')
  return super().redirect_request(req,fp,code,msg,headers,newurl)
def embedded_pdf(html,url):
 doc=Document(html);links=set()
 for node in doc.root.all():
  if node.tag not in ('iframe','embed','object'):continue
  src=node.attrs.get('data' if node.tag=='object' else 'src')
  if src:links.add(official(urllib.parse.urljoin(url,src)))
 if len(links)!=1:raise ReportFormatError('No unambiguous attached PDF')
 return links.pop()
def fetch_pdf(url):
 official(url);parsed=urllib.parse.urlsplit(url)
 if parsed.path.lower()!='/campaigndisclosure/cdpdfviewer.aspx' or not urllib.parse.parse_qs(parsed.query).get('FiledDocID'):raise ReportFormatError('No official PDF linked to this filing')
 opener=urllib.request.build_opener(Redirect(),urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
 seen=set()
 for _ in range(3):
  if url in seen:raise ReportFormatError('PDF viewer loop')
  seen.add(url)
  req=urllib.request.Request(url,headers={'User-Agent':'IllinoisFilingTracker/0.3 (public campaign filing reader)','Accept':'application/pdf,text/html'})
  with opener.open(req,timeout=20) as r:
   official(r.url);raw=r.read(LIMIT+1)
   if len(raw)>LIMIT:raise ReportFormatError('PDF exceeds 20 MB viewer limit')
   if raw.lstrip().startswith(b'%PDF-'):return raw
   url=embedded_pdf(raw.decode(r.headers.get_content_charset() or 'utf-8'),r.url)
 raise ReportFormatError('Unable to resolve PDF')
def install(api,store):
 @api.get('/v1/filings/<int(signed=True):seq>/document.pdf')
 def document(seq):
  from subscriptions import lookup_filing
  if abs(seq)>2**63-1:return jsonify(error='Not found'),404
  with closing(store.connect()) as db:row=lookup_filing(db,seq)
  if row is None:return jsonify(error='Not found'),404
  if not row['url']:return jsonify(error='The official archive does not link a document for this filing.'),404
  if not SLOTS.acquire(blocking=False):return jsonify(error='Documents are busy loading. Please retry.'),503
  try:
   try:data=fetch_pdf(row['url'])
   except Exception:return jsonify(error='The official PDF could not be loaded. Retry or use Open official report.'),502
   return send_file(io.BytesIO(data),mimetype='application/pdf',download_name=f'Illinois-filing-{seq}.pdf',as_attachment=False)
  finally:SLOTS.release()
