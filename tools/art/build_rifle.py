"""Deterministic original top-down power-armour art. Requires Pillow; no game code."""
from pathlib import Path
import math, json
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/units/rifle'
S = 4
STATES = {'idle': (6, 6, True), 'move': (8, 12, True), 'fire': (4, 16, False), 'death': (8, 10, False)}

def frame(state, f, n, direction):
    im = Image.new('RGBA', (64*S, 64*S))
    d = ImageDraw.Draw(im)
    phase = math.tau*f/n
    bob = math.sin(phase)*.45 if state in ('idle','move') else 0
    recoil = [1.8, 1, .3, 0][f] if state == 'fire' else 0
    fall = f/(n-1) if state == 'death' else 0
    def box(x,y,w,h,fill,outline='#101923',r=1.5):
        y += bob + recoil
        d.rounded_rectangle(tuple(int(v*S) for v in (32+x,32+y,32+x+w,32+y+h)),radius=int(r*S),fill=fill,outline=outline,width=S)
    # Soft contact shadow; compact body silhouette ~22 px at final display scale.
    d.ellipse((18*S,23*S,47*S,49*S),fill=(5,10,18,75))
    for side in (-1,1):
        stride = math.sin(phase)*3*side if state == 'move' else 0
        box(side*5-3,3+stride,6,11,'#293746')
        box(side*5-3,10+stride,6,5,'#52616a')
        box(side*5-2,6+stride,4,4,'#86918d')
    box(-8,-7,16,18,'#3e535b',r=4)
    box(-7,-12,14,8,'#27343c') # reactor pack, exhaust ribs
    for x in (-5,-2,1,4): box(x,-11,1,5,'#81918c',r=0)
    box(-7,-6,14,14,'#849c99',r=3)
    box(-5,-4,10,9,'#526d72',r=2)
    for x in (-12,6):
        box(x,-7,7,11,'#77908f',r=3)
        box(x+1,-6,5,3,'#bdc9b6',r=1)
        box(x+2,0,3,2,'#65d6c5',r=.5)
    box(-5,-9,10,10,'#aab7a6',r=4)
    box(-4,-9,8,4,'#132e3d',r=2)
    box(-3,-9,6,2,'#f4bf65',r=1)
    # Two gauntlets holding an offset rifle, clear barrel direction toward north.
    box(-8,0,5,7,'#536c71',r=2)
    box(5,-2,5,7,'#536c71',r=2)
    box(1,-11,5,16,'#182731',r=1)
    box(2,-17,3,9,'#52616a',r=.5)
    box(2,-7,3,7,'#83928a',r=.5)
    box(2,-4,1,3,'#efb969',r=0)
    if state == 'fire' and f < 2:
        points = [(35,-0),(32,10),(34,8),(35,15),(38,8),(40,10)]
        d.polygon([(x*S,(y+9)*S) for x,y in points], fill='#ffb743')
        d.ellipse((34*S,14*S,38*S,19*S),fill='#fff4b3')
    if state == 'death':
        # Collapse and roll, never move the ground anchor.
        im = im.resize((64*S,int((64-24*fall)*S)),Image.Resampling.LANCZOS)
        canvas = Image.new('RGBA',(64*S,64*S))
        canvas.alpha_composite(im,(int(fall*3*S),int(12*fall*S)))
        im = canvas.rotate(-65*fall,Image.Resampling.BICUBIC)
        if fall > .7:
            im.putalpha(im.getchannel('A').point(lambda a:int(a*(1-.35*(fall-.7)/.3))))
    # Authored north, atlas starts east; clockwise screen direction.
    im = im.rotate(-90-direction*45,Image.Resampling.BICUBIC)
    return im.resize((64,64),Image.Resampling.LANCZOS)

OUT.mkdir(parents=True,exist_ok=True)
for state,(count,fps,loop) in STATES.items():
    atlas=Image.new('RGBA',(count*64,8*64))
    for direction in range(8):
        for f in range(count): atlas.alpha_composite(frame(state,f,count,direction),(f*64,direction*64))
    atlas.save(OUT/f'{state}.png')
manifest={'version':1,'frame_size':[64,64],'anchor':[32,32],'display_size':[36,36], 'directions':['E','SE','S','SW','W','NW','N','NE'],'animations':{k:{'texture':k+'.png','frames':v[0],'fps':v[1],'loop':v[2]} for k,v in STATES.items()}}
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
# Review sheet at 3x, no simulation required.
review=Image.new('RGB',(8*144,4*170),'#101e30'); draw=ImageDraw.Draw(review)
for row,(state,(n,_,_)) in enumerate(STATES.items()):
    for col in range(8):
        img=frame(state, min(n-1,2 if state!='death' else 6),n,col).resize((128,128))
        review.paste(img,(col*144,row*170+24),img)
        draw.text((col*144+8,row*170+6),f'{state} {manifest["directions"][col]}',fill='#c9ddd9')
review.save(OUT/'preview.png')
