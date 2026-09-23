"""Manual integration probe for public ISBE report layouts."""
import json, pathlib, urllib.request, urllib.parse
from reports import Document
out=pathlib.Path('archive-probe');out.mkdir(exist_ok=True)
url='https://www.elections.il.gov/campaigndisclosure/CommitteeDetail.aspx?ID=PFWS3Q4VBrJwLQhAj5bRtQ%3D%3D'
def read(url,name):
 with urllib.request.urlopen(url,timeout=30) as r: data=r.read().decode('utf-8')
 (out/(name+'.html')).write_text(data)
 doc=Document(data)
 print(name, len(data))
 for n in doc.root.all():
  if n.tag in ('table','select') and n.attrs.get('id','').startswith('ContentPlaceHolder1'):
   print(n.tag,n.attrs, n.text()[:16000])
 return doc
doc=read(url,'committee')
links=[{'text':n.text().strip(),'href':n.attrs.get('href')} for n in doc.root.all('a') if n.attrs.get('href')]
(out/'links.json').write_text(json.dumps(links))
print('REPORT LINKS',json.dumps([l for l in links if any(t in l['text'] for t in ['D-2','A-1','2017','Next']) or '__doPostBack' in l['href']]))
for kind in ['D-2 Quarterly','A-1']:
 link=next((l for l in links if kind in l['text'] and not l['href'].startswith('javascript')),None)
 if link: read(urllib.parse.urljoin(url,link['href']),kind[:3])
