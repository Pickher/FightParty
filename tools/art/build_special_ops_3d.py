"""Blender 4.3: original power-armour model, articulated animation and orthographic sprites.
blender -b -t 4 -P tools/art/build_special_ops_3d.py -- preview|render
Assemble rendered frames with pack_special_ops.py (Pillow).
"""
import bpy, math, sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/units/rifle'
CACHE=Path('/workspace/scratch/rifle3d');CACHE.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def mat(name,color,metal=.5,rough=.33,emission=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
 if emission:p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=emission
 return m
armor=mat('Petrol blue ceramic armour',(.055,.19,.27));light=mat('Armour bevels',(.13,.36,.44));dark=mat('Flexible graphite joints',(.018,.025,.033),.25,.6);steel=mat('Brushed gunmetal',(.18,.23,.25),.8);white=mat('Ivory identification',(.74,.76,.64));visor=mat('Amber visor',(.95,.36,.035),.72,.16);glow=mat('Cyan reactor',(.08,.8,1),.2,.25,3);flame=mat('Hot muzzle core',(1,.55,.10),0,.2,6)
def empty(name,parent=None,loc=(0,0,0)):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.parent=parent;o.location=loc;return o
root=empty('Ground anchor');body=empty('Torso pivot',root,(0,0,1.15))
def mesh(name,loc,scale,material,parent=body,shape='box',bevel=.08):
 if shape=='sphere':bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12)
 elif shape=='cone':bpy.ops.mesh.primitive_cone_add(vertices=7,radius1=1,radius2=0,depth=2)
 else:bpy.ops.mesh.primitive_cube_add()
 o=bpy.context.object;o.name=name;o.parent=parent;o.location=loc;o.scale=scale
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if shape=='box' and bevel:
  mod=o.modifiers.new('Manufactured rounded edges','BEVEL');mod.width=bevel;mod.segments=3
  o.modifiers.new('Weighted face normals','WEIGHTED_NORMAL')
 for p in o.data.polygons:p.use_smooth=True
 o.data.materials.append(material);return o
# Thoracic shell and inset segmented stomach.
mesh('Cuirass deep upper shell',(0,0,.65),(.47,.30,.43),armor,shape='sphere')
mesh('Chest raised breastplate',(0,-.24,.63),(.38,.15,.25),light)
mesh('Chest inset',(0,-.385,.66),(.22,.035,.07),dark,bevel=.02)
mesh('Chest ivory heraldry',(0,-.425,.66),(.12,.012,.025),white,bevel=.01)
for z in (.12,.25,.38):mesh('Abdominal flexible armour',(0,-.13,z),(.28,.22,.07),steel,bevel=.04)
mesh('Hip armour',(0,0,.02),(.34,.25,.15),armor)
# Neck collar, recessed amber face, ridged dome.
mesh('Armoured collar',(0,-.025,.99),(.30,.28,.15),steel,shape='sphere')
mesh('Helmet dome',(0,-.07,1.16),(.26,.25,.30),armor,shape='sphere')
mesh('Face black gasket',(0,-.275,1.17),(.22,.09,.19),dark,shape='sphere')
mesh('Curved amber faceplate',(0,-.32,1.20),(.19,.065,.14),visor,shape='sphere')
mesh('Helmet central ridge',(0,-.01,1.40),(.05,.19,.035),light,bevel=.025)
mesh('Chin guard',(0,-.29,1.00),(.15,.11,.065),steel)
for x in (-.19,.19):mesh('Helmet breathing port',(x,-.27,1.02),(.05,.07,.055),dark,shape='sphere')
# Twin rear reactor housings project clearly past shoulders in rear views.
mesh('Backpack',(0,.31,.65),(.38,.22,.39),dark)
for x in (-.27,.27):
 mesh('Reactor shell',(x,.39,.78),(.16,.19,.37),armor)
 mesh('Exhaust crown',(x,.40,1.10),(.12,.14,.07),steel)
 for z in (.56,.66,.76):mesh('Reactor vent',(x,.59,z),(.11,.018,.025),dark,bevel=.01)
 mesh('Reactor light',(x,.59,.94),(.07,.02,.04),glow,bevel=.01)
# Large domed pauldrons with hard rims and asymmetric markings.
for side in (-1,1):
 x=side*.57
 mesh('Shoulder ball joint',(x,0,.72),(.20,.23,.24),dark,shape='sphere')
 mesh('Pauldron shell',(x,-.015,.89),(.33,.34,.30),armor,shape='sphere')
 mesh('Pauldron upper armour',(x,-.03,1.03),(.28,.28,.16),light,shape='sphere')
 mesh('Pauldron lower rim',(x,-.08,.72),(.30,.28,.065),steel)
 mesh('Pauldron identification',(x,-.335,.94),(.13,.025,.035),white,bevel=.02)
 for zz in (.85,.94):mesh('Shoulder rivet',(x+side*.22,-.24,zz),(.027,.035,.027),steel,shape='sphere')
# Arms bend in toward the weapon, not parallel to the torso.
def segment(name,a,b,r,material,parent=body):
 mid=(Vector(a)+Vector(b))/2; o=mesh(name,mid,(r,r,(Vector(b)-Vector(a)).length/2),material,parent,shape='sphere');o.rotation_euler=(Vector(b)-Vector(a)).to_track_quat('Z','Y').to_euler();return o
segment('Right upper arm',(.59,-.08,.70),(.57,-.28,.37),.17,armor)
segment('Right forearm',(.57,-.28,.37),(.27,-.65,.51),.17,light)
segment('Left upper arm',(-.59,-.08,.70),(-.49,-.36,.40),.17,armor)
segment('Left forearm',(-.49,-.36,.40),(.03,-.90,.54),.16,light)
weapon=empty('Weapon recoil',body,(0,0,0))
mesh('Rifle broad receiver',(.20,-.79,.57),(.13,.37,.12),steel,weapon,bevel=.045)
mesh('Rifle rear stock',(.20,-.38,.57),(.11,.14,.10),dark,weapon)
mesh('Rifle fore-end',(.20,-1.13,.60),(.12,.20,.10),armor,weapon,bevel=.03)
mesh('Short heavy muzzle',(.20,-1.38,.60),(.065,.10,.065),dark,weapon,bevel=.02)
mesh('Muzzle rim',(.20,-1.48,.60),(.075,.025,.075),steel,weapon,bevel=.015)
mesh('Barrel opening',(.20,-1.508,.60),(.045,.005,.045),dark,weapon,bevel=.01)
mesh('Box magazine',(.20,-.69,.36),(.085,.10,.15),dark,weapon)
mesh('Top rail',(.20,-.85,.71),(.05,.28,.025),dark,weapon,bevel=.01)
for y in (-.99,-1.08,-1.17):mesh('Gun cooling vent',(.325,y,.61),(.01,.028,.045),dark,weapon,bevel=.01)
mesh('Trigger hand',(.29,-.60,.48),(.11,.12,.10),steel)
mesh('Support hand',(.06,-1.00,.52),(.12,.12,.10),steel)
flash=mesh('Muzzle flame',(.20,-1.68,.60),(.09,.09,.22),flame,weapon,shape='cone');flash.rotation_euler.x=math.pi/2;flash.hide_render=True
# Articulated legs with independent hip / knee transforms.
legs=[]
for side in (-1,1):
 hip=empty('Hip L' if side<0 else 'Hip R',root,(side*.25,0,1.18));legs.append(hip)
 mesh('Thigh joint',(0,0,-.12),(.19,.19,.24),dark,hip,shape='sphere')
 mesh('Thigh plate',(0,-.03,-.27),(.21,.23,.29),armor,hip)
 knee=empty('Knee',hip,(0,0,-.53))
 mesh('Knee dome',(0,-.21,0),(.18,.12,.17),light,knee,shape='sphere')
 mesh('Shin armour',(0,0,-.24),(.19,.21,.27),armor,knee)
 mesh('Shin raised panel',(0,-.22,-.24),(.12,.055,.19),light,knee)
 mesh('Boot',(0,-.13,-.49),(.22,.34,.13),steel,knee)
 mesh('Boot sole',(0,-.13,-.59),(.23,.35,.045),dark,knee,bevel=.025)
# Lighting fixed in world space: turns alter illumination rather than rotating painted highlights.
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=False
scene.render.resolution_x=128;scene.render.resolution_y=128;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.render.film_transparent=True
scene.world.color=(.22,.22,.22)
def area(name,loc,power,color,size):
 bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.color=color;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler()
area('Warm upper left key',(-3,-4,7),650,(1,.91,.79),4)
area('Cool rim',(3,3,5),850,(.58,.78,1),3)
area('Front soft fill',(1,-4,3),160,(.68,.83,1),3)
bpy.ops.object.camera_add(location=(0,-7,9));cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,1.05))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=4.8;scene.camera=cam
scene.view_settings.view_transform='AgX'
STATES={'idle':(6,6),'move':(8,12),'fire':(8,24),'death':(16,16)}
def pose(state,f,n,direction):
 phase=math.tau*f/n;t=f/(n-1)
 root.rotation_euler=(0,0,(2-direction)*math.pi/4);root.location=(0,0,0)
 body.location=(0,0,1.15);body.rotation_euler=(0,0,0);weapon.location=(0,0,0)
 for hip in legs:hip.rotation_euler=(0,0,0)
 flash.hide_render=state!='fire'
 if state=='idle':body.location.z+=math.sin(phase)*.025
 if state=='move':
  body.location.z+=abs(math.sin(phase))*.055
  for i,hip in enumerate(legs):hip.rotation_euler.x=math.sin(phase+i*math.pi)*.48
  body.rotation_euler.y=math.sin(phase)*.035
 if state=='fire':
  recoil=[.02,.065,.01,.05,.015,.07,.025,.055][f];weapon.location.y=recoil;body.rotation_euler.x=-recoil*.5
  flash.scale=(.7+(f%3)*.25,.65+(f%4)*.2,.7+(f%2)*.4)
 if state=='death':
  flight=min(t/.72,1);root.location.z=math.sin(math.pi*flight)*.80
  root.rotation_euler.x=-flight*1.45;root.location.z+=flight*.22
  body.rotation_euler.y=math.sin(flight*math.pi)*.35
  for i,hip in enumerate(legs):hip.rotation_euler.x=math.sin(flight*math.pi)*.7;hip.rotation_euler.y=(-1 if i else 1)*flight*.25
  weapon.rotation_euler.x=flight*.4
 else:weapon.rotation_euler.x=0
# Bake the procedural poses into an editable timeline in the delivered source.
scene.render.fps=24
for state,start in [('idle',1),('move',31),('fire',61),('death',91)]:
 n,fps=STATES[state];scene.timeline_markers.new(state,frame=start)
 for f in range(n):
  pose(state,f,n,1);key=start+round(f*24/fps)
  for obj in [root,body,weapon,flash]+legs:
   for prop in ('location','rotation_euler','scale'):obj.keyframe_insert(data_path=prop,frame=key)
  flash.keyframe_insert(data_path='hide_render',frame=key)
scene.frame_end=114;scene.frame_set(1)
pose('idle',0,6,1)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source/special_ops.blend'))
from bpy_extras.object_utils import world_to_camera_view
import json
bpy.context.view_layer.update()
p=world_to_camera_view(scene,cam,Vector((0,0,0)))
(OUT/'source/render-settings.json').write_text(json.dumps({'frame_size':128,'anchor':[round(p.x*128,2),round((1-p.y)*128,2)],'camera_elevation_degrees':48.6,'ortho_scale':4.8},indent=2))
mode=sys.argv[-1]
if mode=='render':
 for state,(n,fps) in STATES.items():
  for direction in range(8):
   for f in range(n):
    target=CACHE/f'{state}_{direction}_{f:02d}.png'
    if target.exists():continue
    pose(state,f,n,direction)
    scene.render.resolution_x=192 if state=='death' else 128;scene.render.resolution_y=scene.render.resolution_x
    cam.data.ortho_scale=7.2 if state=='death' else 4.8
    scene.render.filepath=str(target);bpy.ops.render.render(write_still=True)
else:
 scene.render.resolution_x=640;scene.render.resolution_y=640;scene.cycles.samples=32
 pose('idle',0,6,1);scene.render.filepath=str(OUT/'model-preview.png');bpy.ops.render.render(write_still=True)
