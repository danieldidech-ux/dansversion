"""Temporary, bounded public-source integration diagnostic (no arbitrary URLs)."""
import threading, time, urllib.request, urllib.parse
from reports import Document
_cache={}; _lock=threading.Lock()
URL='https://www.elections.il.gov/CampaignDisclosure/CommitteeDetail.aspx?ID=PFWS3Q4VBrJwLQhAj5bRtQ%3D%3D'
def inspect():
 with _lock:
  if _cache.get('expires',0)>time.time(): return _cache['result']
  result={}
  try:
   req=urllib.request.Request(URL,headers={'User-Agent':'IllinoisFilingTracker/0.3 (public campaign filing reader)'})
   with urllib.request.urlopen(req,timeout=12) as r: html=r.read(3000000).decode('utf-8')
   from archive_source import Source
   source=Source()
   html=source.all_rows(URL,html,'gvFiledDocs')
   result={'html':html}
   doc=Document(html)
   for kind in ['D-2 Quarterly','A-1']:
    link=next((n for n in doc.root.all('a') if kind in n.text() and not n.attrs.get('href','').startswith('javascript')),None)
    if link: result[kind]=source.read(urllib.parse.urljoin(URL,link.attrs['href']))
  except Exception as e: result={'error':str(e)}
  _cache.update(expires=time.time()+300,result=result)
  return result
