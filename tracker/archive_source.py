"""Bounded reader for official ISBE Web Forms archives."""
import http.cookiejar, re, urllib.parse, urllib.request
from reports import Document, Node, ReportFormatError, normalized
BASE='https://www.elections.il.gov/CampaignDisclosure/'

def safe_url(url):
 p=urllib.parse.urlsplit(url)
 if p.scheme!='https' or p.hostname not in {'www.elections.il.gov','elections.il.gov'} or p.username or p.password or p.port not in (None,443) or not p.path.lower().startswith('/campaigndisclosure/'):
  raise ReportFormatError('Invalid official source URL')
 return url
class OfficialRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,req,fp,code,msg,headers,newurl):
  safe_url(newurl)
  return super().redirect_request(req,fp,code,msg,headers,newurl)
class Source:
 def __init__(self):
  self.opener=urllib.request.build_opener(OfficialRedirect(),urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
 def read(self,url,fields=None):
  safe_url(url)
  self.last_url=url
  data=urllib.parse.urlencode(fields).encode() if fields is not None else None
  req=urllib.request.Request(url,data=data,headers={'User-Agent':'IllinoisFilingTracker/0.3 (public campaign filing reader)','Accept':'text/html'})
  with self.opener.open(req,timeout=20) as r:
   safe_url(r.url)
   raw=r.read(20_000_001)
   if len(raw)>20_000_000: raise ReportFormatError('Archive exceeds reader limit')
   if raw.startswith(b'%PDF'):raise ReportFormatError('Official document is a scanned PDF, not an electronic report')
   return raw.decode(r.headers.get_content_charset() or 'utf-8')
 def all_rows(self,url,html,table_id):
  doc=Document(html)
  selectors=[s for s in doc.root.all('select') if table_id in s.attrs.get('id','') and 'PageSize' in s.attrs.get('id','')]
  if not selectors:return html
  select=selectors[0]
  options=[o for o in select.all('option') if o.text().strip()=='All']
  if len(options)!=1: raise ReportFormatError('No complete archive option')
  fields={n.attrs['name']:n.attrs.get('value','') for n in doc.root.all('input') if n.attrs.get('name') and n.attrs.get('type')=='hidden'}
  for n in doc.root.all('select'):
   selected=next((o for o in n.all('option') if 'selected' in o.attrs),next(n.all('option'),None))
   if selected and n.attrs.get('name'): fields[n.attrs['name']]=selected.attrs.get('value','')
  fields.update({select.attrs['name']:options[0].attrs['value'],'__EVENTTARGET':select.attrs['name'],'__EVENTARGUMENT':''})
  return self.read(url,fields)

 def find_committee(self,name):
  url=BASE+'CommitteeSearch.aspx'
  doc=Document(self.read(url))
  fields={n.attrs['name']:n.attrs.get('value','') for n in doc.root.all('input') if n.attrs.get('name') and n.attrs.get('type') in {'hidden','text'}}
  for n in doc.root.all('select'):
   selected=next((o for o in n.all('option') if 'selected' in o.attrs),next(n.all('option'),None))
   if selected and n.attrs.get('name'):fields[n.attrs['name']]=selected.attrs.get('value','')
  name_field=doc.by_id('ContentPlaceHolder1_txtName')
  submit=doc.by_id('ContentPlaceHolder1_btnSubmit')
  fields[name_field.attrs['name']]=name
  fields[submit.attrs['name']]=submit.attrs['value']
  result=Document(self.read(url,fields))
  return exact_committee_link(result,name,url)


def exact_committee_link(doc,name,base=BASE):
 links={safe_url(urllib.parse.urljoin(base,n.attrs['href'])) for n in doc.root.all('a') if 'committeedetail.aspx' in n.attrs.get('href','').lower() and normalized(n.text())==normalized(name)}
 if len(links)!=1:raise ReportFormatError('No unambiguous official committee match')
 return links.pop()
