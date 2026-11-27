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
# Match the wide burgundy masthead by color and geometry; the state has served
# different paginations of this training PDF at the same URL.
from PIL import Image, ImageDraw
from io import BytesIO
import numpy as np
previews=[]
candidates=[]
for i,page in enumerate(document):
    pix=page.get_pixmap(matrix=fitz.Matrix(960/page.rect.width,960/page.rect.width),alpha=False)
    im=Image.frombytes("RGB",(pix.width,pix.height),pix.samples)
    previews.append(im)
    rgb=np.asarray(im).astype(float)
    r,g,b=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
    mask=(r>75)&(r<185)&(r>1.4*g)&(r>1.4*b)&(abs(g-b)<23)&(g>21)
    ys=np.where(mask.sum(axis=1)>135)[0]
    for ys1 in np.split(ys,np.where(np.diff(ys)>3)[0]+1):
        if len(ys1)<9: continue
        top,bottom=ys1[0],ys1[-1]+1
        cols=np.where(mask[top:bottom].sum(axis=0)>(bottom-top)*0.16)[0]
        if len(cols)<130: continue
        # Gaps in red come from the gold lettering and the Capitol illustration.
        for part in np.split(cols,np.where(np.diff(cols)>50)[0]+1):
            if len(part)<125: continue
            left,right=part[0],part[-1]+1
            if right-left<6*(bottom-top):continue
            candidates.append((i,left,top,right,bottom))
print("BANNER REGIONS", candidates,flush=True)
thumb=Image.new('RGB',(720,((len(previews)+3)//4)*118),'white')
d=ImageDraw.Draw(thumb)
for i,im in enumerate(previews):
    a=im.copy();a.thumbnail((176,98));x,y=i%4*180,i//4*118
    thumb.paste(a,(x,y+16));d.text((x,y),str(i),fill='black')
buf=BytesIO();thumb.save(buf,format='JPEG',quality=68)
print("REFERENCE_CONTACT "+base64.b64encode(buf.getvalue()).decode(),flush=True)
if not candidates:
    raise RuntimeError('Archival masthead not found')
i,left,top,right,bottom=candidates[0]
print("CHOSEN",i,left,top,right,bottom)
im=previews[i]
# Crop the complete masthead, adjusting its left boundary to the screenshot edge.
banner_img=im.crop((max(0,left-12),top,right,bottom))
buf=BytesIO();banner_img.save(buf,format='PNG')
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
