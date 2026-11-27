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
# Page 10 is the browser screenshot showing the old home screen with bill search.
from PIL import Image
from io import BytesIO
import numpy as np
page=document[9]
pix=page.get_pixmap(matrix=fitz.Matrix(1800/page.rect.width,1800/page.rect.width),alpha=False)
im=Image.frombytes("RGB",(pix.width,pix.height),pix.samples)
rgb=np.array(im).astype(float)
r,g,b=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
nav=(r<50)&(g<65)&(b>65)&(b>2.0*g)
ys=np.where(nav.sum(axis=1)>0.54*im.width)[0]
bands=[band for band in np.split(ys,np.where(np.diff(ys)>2)[0]+1) if len(band)>4]
if not bands: raise RuntimeError('Cannot locate the navy navigation in the reference')
top=bands[0][0]; bottom=bands[0][-1]+1
xs=np.where(nav[top:bottom].sum(axis=0)>(bottom-top)*0.4)[0]
left,right=int(xs[0]),int(xs[-1])
width=right-left; height=round(width*.064)
print("Reference dimensions",im.size,"navigation",left,int(top),right,int(bottom),flush=True)
im.save(OUT/'Original-ILGA-reference.jpg',quality=90)
mast=im.crop((left,max(0,top-height),left+round(width*.62),top))
buf=BytesIO();mast.save(buf,format='PNG')
banner="data:image/png;base64,"+base64.b64encode(buf.getvalue()).decode()
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
