"""Deterministic original top-down power-armour art. Requires Pillow; no game code."""
from pathlib import Path
import math, json
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/units/rifle'
S = 4
STATES = {'idle': (6, 6, True), 'move': (8, 12, True), 'fire': (8, 24, True), 'death': (16, 16, False)}

def frame(state, f, n, direction):
    im = Image.new('RGBA', (64*S, 64*S))
    d = ImageDraw.Draw(im)
    phase = math.tau*f/n
    bob = math.sin(phase)*.45 if state in ('idle','move') else 0
    recoil = [1.2, .1, 1.6, .2, 1.0, 0, 1.4, .3][f] if state == 'fire' else 0
    fall = f/(n-1) if state == 'death' else 0
    def box(x,y,w,h,fill,outline='#101923',r=1.5):
        y += bob + recoil
        d.rounded_rectangle(tuple(int(v*S) for v in (32+x,32+y,32+x+w,32+y+h)),radius=int(r*S),fill=fill,outline=outline,width=S)
    def poly(points,fill):
        d.polygon([(int((32+x)*S),int((32+y+bob+recoil)*S)) for x,y in points],fill=fill)
    def oval(x,y,w,h,fill):
        d.ellipse(tuple(int(v*S) for v in (32+x,32+y+bob+recoil,32+x+w,32+y+h+bob+recoil)),fill=fill)
    # Splayed boots, bent knees; silhouette is broad armour, not a narrow humanoid.
    for side in (-1,1):
        stride=math.sin(phase)*3.4*side if state=='move' else 0
        spread=fall*5
        x=side*(7+spread)-4
        box(x,5+stride,8,10,'#172438',r=3)
        box(x,8+stride,8,7,'#3c648d',r=2)
        box(x-1,12+stride,9,5,'#223950',r=2)
        box(x+1,8+stride,5,2,'#82abc5',r=1)
    # Twin exhaust stacks behind a domed cuirass.
    box(-10,-2,20,13,'#172536',r=4)
    for x in (-10,5):
        box(x,0,5,10,'#45667d',r=2)
        for y in (2,4,6): box(x+1,y,3,1,'#111e29',r=0)
    oval(-10,-9,20,20,'#101e30')
    oval(-9,-9,18,17,'#305882')
    oval(-7,-9,14,11,'#5489b0')
    poly([(-6,0),(0,3),(6,0),(5,7),(-5,7)],'#203c58')
    box(-3,4,6,2,'#b0bdc2',r=.5)
    # Massive layered pauldrons, two separate arms converging on the gun.
    for x in (-17,8):
        oval(x,-9,10,14,'#101c2d')
        oval(x+1,-9,9,11,'#35648f')
        oval(x+2,-9,7,6,'#70a4ca')
        box(x+2,-6,6,3,'#4b82b0')
        box(x+2,0,6,2,'#bad0d6',r=.4)
        box(x+3,-5,2,3,'#d8e3cf',r=.4)
    oval(-7,-12,14,14,'#142333')
    oval(-6,-13,12,12,'#6397bc')
    oval(-4,-13,8,7,'#8eb6cb')
    box(-5,-10,10,5,'#102234',r=2)
    box(-4,-10,8,3,'#e99b32',r=1)
    box(-3,-10,5,1,'#fff1a2',r=.3)
    box(-4,-5,8,3,'#29485f',r=1)
    # Wide receiver, vented fore-end, magazine and short muzzle: recognisably a rifle.
    poly([(-12,-1),(-10,-5),(-2,-9),(1,-6),(-6,0)],'#132536')
    poly([(-11,-2),(-9,-4),(-3,-7),(-1,-5),(-7,0)],'#527da0')
    poly([(12,1),(12,-5),(7,-10),(4,-7),(7,0)],'#284864')
    box(0,-15,8,14,'#101b26',r=1)
    box(1,-16,6,11,'#566770',r=1)
    box(2,-15,4,3,'#9ba9a8',r=.4)
    for y in (-11,-9,-7): box(2,y,4,1,'#17232e',r=0)
    box(1,-4,5,5,'#334958',r=.5)
    box(6,-5,3,5,'#182b3c',r=.5)
    box(2,-20,4,5,'#17222b',r=.5)
    box(2,-20,4,1,'#9daaaa',r=0)
    box(-1,-8,4,4,'#7894aa',r=1) # support glove wraps fore-end
    box(6,-2,4,4,'#6786a2',r=1) # trigger hand
    if state == 'fire':
        length=[7,4,8,5,7,3,6,8][f]
        poly([(4,-19),(0,-22),(3,-22),(2,-20-length),(5,-24),(8,-25),(6,-21),(9,-20)],'#fa7828')
        poly([(3,-20),(3,-24),(4,-21-length),(6,-23),(5,-20)],'#ffce51')
        poly([(3,-20),(4,-25),(5,-20)],'#fffbdc')
        box(11+f%3,-4-f%4,2,1,'#efc171',r=0)
    if state == 'death':
        # Separate airborne silhouette and ground shadow. Body rolls through the impact.
        flight=min(1,fall/.72)
        lift=math.sin(math.pi*flight)*10
        squash=1-.5*abs(math.sin(flight*math.pi*2))
        body=im.resize((64*S,int(64*S*squash)),Image.Resampling.LANCZOS)
        canvas=Image.new('RGBA',(64*S,64*S))
        canvas.alpha_composite(body,(0,int((64*S-body.height)/2)))
        im=canvas.rotate(-flight*155,Image.Resampling.BICUBIC)
        canvas=Image.new('RGBA',(64*S,64*S))
        canvas.alpha_composite(im,(0,int(-lift*S)))
        im=canvas
        dust=ImageDraw.Draw(im)
        if fall>.65:
            for k in range(7):
                angle=k*math.tau/7
                x=32+math.cos(angle)*(8+fall*10); y=36+math.sin(angle)*5
                dust.ellipse((int(x*S),int(y*S),int((x+3)*S),int((y+1)*S)),fill=(155,143,120,int(90*(1-fall))))
    # Authored north, atlas starts east; clockwise screen direction.
    im = im.rotate(-90-direction*45,Image.Resampling.BICUBIC)
    return im.resize((64,64),Image.Resampling.LANCZOS)

OUT.mkdir(parents=True,exist_ok=True)
for state,(count,fps,loop) in STATES.items():
    atlas=Image.new('RGBA',(count*64,8*64))
    for direction in range(8):
        for f in range(count): atlas.alpha_composite(frame(state,f,count,direction),(f*64,direction*64))
    atlas.save(OUT/f'{state}.png')
manifest={'version':2,'frame_size':[64,64],'anchor':[32,32],'display_size':[36,36], 'directions':['E','SE','S','SW','W','NW','N','NE'],'animations':{k:{'texture':k+'.png','frames':v[0],'fps':v[1],'loop':v[2]} for k,v in STATES.items()}}
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
# Review sheet at 3x, no simulation required.
review=Image.new('RGB',(8*144,4*170),'#101e30'); draw=ImageDraw.Draw(review)
for row,(state,(n,_,_)) in enumerate(STATES.items()):
    for col in range(8):
        img=frame(state, min(n-1,2 if state!='death' else 6),n,col).resize((128,128))
        review.paste(img,(col*144,row*170+24),img)
        draw.text((col*144+8,row*170+6),f'{state} {manifest["directions"][col]}',fill='#c9ddd9')
review.save(OUT/'preview.png')

frames=[]
for t in range(72):
    im=Image.new('RGB',(800,230),'#101e30'); d=ImageDraw.Draw(im)
    for i,(state,(n,fps,loop)) in enumerate(STATES.items()):
        f=int(t*fps/24)
        f=f%n if loop else min(f%32,n-1)
        sprite=frame(state,f,n,7).resize((192,192))
        if state=='death':
            shift=int(min(f/11,1)*25)
            im.paste(sprite,(i*200+shift-12,28),sprite)
        else: im.paste(sprite,(i*200,28),sprite)
        d.text((i*200+30,10),state,fill='#d3e5db')
    frames.append(im)
frames[0].save(OUT/'animations.gif',save_all=True,append_images=frames[1:],duration=42,loop=0)
