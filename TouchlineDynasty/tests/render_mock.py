from PIL import Image,ImageDraw,ImageFont
import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
data=json.loads((root/'tests/ui_mock.json').read_text()); nodes={n['id']:n for n in data}
image=Image.new('RGB',(1280,800),(10,16,24)); draw=ImageDraw.Draw(image)
cache={}
def rect(n):
 if n['id'] in cache:return cache[n['id']]
 p=nodes.get(n.get('parent')); px,py,pw,ph,vis=rect(p) if p else (0,0,1280,800,True)
 s=n.get('Size',{'X':{'Scale':1,'Offset':0},'Y':{'Scale':1,'Offset':0}}); pos=n.get('Position',{'X':{'Scale':0,'Offset':0},'Y':{'Scale':0,'Offset':0}})
 w=s['X']['Scale']*pw+s['X']['Offset']; h=s['Y']['Scale']*ph+s['Y']['Offset']; anchor=n.get('AnchorPoint',{'X':0,'Y':0})
 x=px+pos['X']['Scale']*pw+pos['X']['Offset']-anchor['X']*w; y=py+pos['Y']['Scale']*ph+pos['Y']['Offset']-anchor['Y']*h
 cache[n['id']]=(x,y,w,h,vis and n.get('Visible',True));return cache[n['id']]
def rgb(c): return tuple(int(c[k]*255) for k in 'RGB')
for n in data:
 if n['class'] not in ['Frame','TextLabel','TextButton','ScrollingFrame']:continue
 x,y,w,h,visible=rect(n)
 if not visible or w<=0 or h<=0:continue
 if n.get('BackgroundTransparency',0)<.9 and 'BackgroundColor3' in n:
  draw.rounded_rectangle((x,y,x+w,y+h),radius=10 if n['class']=='TextButton' or n.get('BackgroundColor3')=={'R':26/255,'G':38/255,'B':52/255} else 0,fill=rgb(n['BackgroundColor3']))
 if 'Text' in n:
  size=int(n.get('TextSize',18)); font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',size)
  text=n['Text'].replace('\n',' ')
  while text and draw.textlength(text,font=font)>w-3: text=text[:-2]+'…'
  align=n.get('TextXAlignment','Center' if n['class']=='TextButton' else 'Left')
  tw=draw.textlength(text,font=font); tx=x+(w-tw)/2 if 'Center' in align else x+w-tw if 'Right' in align else x
  draw.text((tx,y+h/2),text,font=font,anchor='lm',fill=rgb(n.get('TextColor3',{'R':1,'G':1,'B':1})))
image.save(root/'tests/dashboard_mock.png')
