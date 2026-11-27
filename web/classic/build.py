"""Build a portable visual proof from the contemporaneous state guide and official indexes."""
import base64
import json
import os
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.parse import urlencode
from html import escape
import fitz

ROOT=Path(__file__).parent
OUT=Path("classic-proof")
OUT.mkdir(exist_ok=True)
source='https://ilaging.illinois.gov/content/dam/soi/en/web/aging/programs/ltcombudsman/documents/illinois-legislative-update-march-2024-for-resident-and-family-support-council.pdf'
document=fitz.open(stream=urlopen(source,timeout=60).read(),filetype='pdf')
page=document[11]
w,h=page.rect.width,page.rect.height
# The presentation's archived browser header, excluding its browser chrome, translation
# widget, and mouse pointer. Coordinates are relative to the 2400 x 1350 reference.
clip=fitz.Rect(w*1148/2400,h*219/1350,w*2168/2400,h*353/1350)
image=page.get_pixmap(matrix=fitz.Matrix(1440/w,1440/w),clip=clip,alpha=False)
banner="data:image/png;base64,"+base64.b64encode(image.tobytes("png")).decode()
def data(route,params):
    url='http://127.0.0.1:10009/'+route+'?'+urlencode(params)
    req=Request(url,headers={'Authorization':'Bearer '+os.environ['ILGA_FEED_TOKEN']})
    return json.load(urlopen(req,timeout=30))
bills=data('range-index',{'url':'https://ilga.gov/Legislation/RegularSession/SB?DocTypeID=SB&GaId=18&SessionId=114&num1=0301&num2=0400'})
members=data('members',{'chamber':'House'})
assert len(bills['bills'])==100 and len(members['members'])>80
sections=[]
for chamber in ('Senate','House'):
    entries={'Members':'#members' if chamber=='House' else 'https://www.ilga.gov/Senate/Members/List',
             'Schedules':'Schedules','Committees':'Committees','Journals':'Journals','Transcripts':'Transcripts',
             'Rules':'Rules','Audio/Video':'AudioVideo','FOIA Information':'FOIA'}
    links=[]
    for label,href in entries.items():
        if not href.startswith(('#','https:')):
            href='https://www.ilga.gov/'+chamber+'/'+href
        links.append('<a href="'+escape(href)+'">'+escape(label)+'</a>')
    sections.append('<section class="group" id="'+chamber.lower()+'"><h2>'+chamber+'</h2><div class="links">'+''.join(links)+'</div></section>')
payload=json.dumps({'bills':bills,'members':members},ensure_ascii=False).replace('<','\\u003c')
html=(ROOT/'preview.html').read_text().replace('__MAST__',banner).replace('__DATA__',payload).replace('__CHAMBERS__','\n'.join(sections))
(OUT/'DansVersion-Classic.html').write_text(html)
