"""Pack Blender renders; requires Pillow."""
from pathlib import Path
import json
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'assets/units/rifle';CACHE=Path('/workspace/scratch/rifle3d')
STATES={'idle':(6,6,True),'move':(8,12,True),'fire':(8,24,True),'death':(16,16,False)}
settings=json.loads((OUT/'source/render-settings.json').read_text());size=192
def frame(state,d,f):
 im=Image.open(CACHE/f'{state}_{d}_{f:02d}.png').convert('RGBA')
 if im.size==(128,128):
  padded=Image.new('RGBA',(192,192));padded.alpha_composite(im,(32,32));return padded
 return im
for state,(n,fps,loop) in STATES.items():
 atlas=Image.new('RGBA',(size*n,size*8))
 for d in range(8):
  for f in range(n):
   im=frame(state,d,f);assert im.size==(size,size)
   b=im.getbbox();assert b and min(b[:2])>0 and max(b[2:])<size,(state,d,f,b)
   atlas.alpha_composite(im,(f*size,d*size))
 atlas.save(OUT/f'{state}.png')
m={'version':3,'frame_size':[size,size],'anchor':[96,114.5],'display_size':[66,66],'source':'source/special_ops.blend','directions':['E','SE','S','SW','W','NW','N','NE'],'animations':{k:{'texture':k+'.png','frames':v[0],'fps':v[1],'loop':v[2]} for k,v in STATES.items()}}
(OUT/'manifest.json').write_text(json.dumps(m,indent=2)+'\n')
review=Image.new('RGB',(8*160,4*180),'#182633');draw=ImageDraw.Draw(review)
for row,(state,(n,_,_)) in enumerate(STATES.items()):
 for d in range(8):
  im=frame(state,d,2 if state!='death' else 10).resize((128,128),Image.Resampling.LANCZOS)
  review.paste(im,(d*160+16,row*180+30),im)
  draw.text((d*160+12,row*180+10),state+' '+m['directions'][d],fill='#dce5e9')
review.save(OUT/'preview.png')
frames=[]
for t in range(72):
 im=Image.new('RGB',(960,270),'#182633');draw=ImageDraw.Draw(im)
 for col,(state,(n,fps,loop)) in enumerate(STATES.items()):
  f=int(t*fps/24);f=f%n if loop else min(f%32,n-1)
  sprite=frame(state,1,f).resize((224,224),Image.Resampling.LANCZOS)
  shift=int(min(f/11,1)*24) if state=='death' else 0
  im.paste(sprite,(col*240+shift,30),sprite)
  draw.text((col*240+30,12),state,fill='#e0e9ec')
 frames.append(im)
frames[0].save(OUT/'animations.gif',save_all=True,append_images=frames[1:],duration=42,loop=0)
print('Packed and checked 304 rendered frames')
