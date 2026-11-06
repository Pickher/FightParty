"""Blender 4.3: original power-armour model, articulated animation and orthographic sprites.
blender -b -t 4 -P tools/art/build_special_ops_3d.py -- preview|render
Assemble rendered frames with pack_special_ops.py (Pillow).
"""
import bpy, math, sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/units/rifle'
CACHE=Path('/workspace/scratch/rifle3d-refined-final');CACHE.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def mat(name,color,metal=.65,rough=.46,emission=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
 if emission:p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=emission
 return m
armor=mat('Petrol blue ceramic armour',(.032,.105,.145));light=mat('Armour bevels',(.075,.19,.23));dark=mat('Flexible graphite joints',(.018,.025,.033),.25,.6);steel=mat('Brushed gunmetal',(.18,.23,.25),.8);white=mat('Ivory identification',(.74,.76,.64));visor=mat('Amber visor',(.95,.36,.035),.72,.16);glow=mat('Cyan reactor',(.08,.8,1),.2,.25,3);flame=mat('Hot muzzle core',(1,.55,.10),0,.2,6)
def empty(name,parent=None,loc=(0,0,0)):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.parent=parent;o.location=loc;return o
# Fine cast-metal surface breaks up the broad plastic specular highlight.
for material in (armor,light,steel):
 nodes=material.node_tree.nodes;links=material.node_tree.links
 noise=nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=110;noise.inputs['Detail'].default_value=2
 bump=nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.12;bump.inputs['Distance'].default_value=.012
 links.new(noise.outputs['Fac'],bump.inputs['Height']);links.new(bump.outputs['Normal'],nodes.get('Principled BSDF').inputs['Normal'])
root=empty('Ground anchor');body=empty('Torso pivot',root,(0,0,1.15))
def mesh(name,loc,scale,material,parent=body,shape='box',bevel=.08):
 bpy.ops.object.select_all(action='DESELECT')
 curved=('Chest raised','Hip armour','Chin guard','Backpack','Reactor shell','Pauldron lower','Thigh plate','Shin armour','Shin raised','Boot','Trigger hand','Support hand')
 if shape=='box' and name.startswith(curved):shape='shell'
 if shape=='shell':
  # Rounded cross-sections with a taper, rather than a bevelled cube.
  vertices=[];faces=[];rings=[(-1,.45),(-.92,.76),(-.65,.94),(-.15,1),(.45,.93),(.82,.77),(1,.38)]
  for z,radius in rings:
   for i in range(24):
    a=i*math.tau/24;c=math.cos(a);q=math.sin(a)
    vertices.append((math.copysign(abs(c)**.72,c)*radius,math.copysign(abs(q)**.72,q)*radius,z))
  for j in range(len(rings)-1):
   for i in range(24):faces.append((j*24+i,j*24+(i+1)%24,(j+1)*24+(i+1)%24,(j+1)*24+i))
  faces.extend([tuple(reversed(range(24))),tuple((len(rings)-1)*24+i for i in range(24))])
  data=bpy.data.meshes.new(name);data.from_pydata(vertices,[],faces);data.update()
  o=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(o);bpy.context.view_layer.objects.active=o;o.select_set(True)
  sub=o.modifiers.new('Continuous cast armour curvature','SUBSURF');sub.levels=2
 elif shape=='sphere':bpy.ops.mesh.primitive_uv_sphere_add(segments=32,ring_count=20)
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
mesh('Chest raised breastplate',(0,-.23,.63),(.40,.18,.29),armor)
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
 mesh('Exhaust crown',(x,.40,1.10),(.12,.14,.07),steel,shape='sphere')
 for z in (.56,.66,.76):mesh('Reactor vent',(x,.59,z),(.11,.018,.025),dark,bevel=.01)
 mesh('Reactor light',(x,.59,.94),(.07,.02,.04),glow,bevel=.01)
# Large domed pauldrons with hard rims and asymmetric markings.
for side in (-1,1):
 x=side*.57
 mesh('Shoulder ball joint',(x,0,.72),(.20,.23,.24),dark,shape='sphere')
 mesh('Pauldron shell',(x,-.015,.89),(.33,.34,.30),armor,shape='sphere')
 mesh('Pauldron upper armour',(x,-.02,1.00),(.29,.30,.21),armor,shape='sphere')
 mesh('Pauldron lower rim',(x,-.08,.72),(.30,.28,.065),steel)
 mesh('Pauldron identification',(x,-.335,.94),(.13,.025,.035),white,bevel=.02)
 for zz in (.85,.94):mesh('Shoulder rivet',(x+side*.22,-.24,zz),(.027,.035,.027),steel,shape='sphere')
# Arms bend in toward the weapon, not parallel to the torso.
def segment(name,a,b,r,material,parent=body):
 mid=(Vector(a)+Vector(b))/2; o=mesh(name,mid,(r,r,(Vector(b)-Vector(a)).length/2),material,parent,shape='sphere');o.rotation_euler=(Vector(b)-Vector(a)).to_track_quat('Z','Y').to_euler();return o
segment('Right upper arm',(.59,-.08,.70),(.57,-.28,.37),.17,armor)
segment('Right forearm',(.57,-.28,.37),(.27,-.65,.51),.135,steel)
segment('Left upper arm',(-.59,-.08,.70),(-.49,-.36,.40),.17,armor)
segment('Left forearm',(-.49,-.36,.40),(.03,-.90,.54),.13,steel)
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
 mesh('Thigh plate',(0,-.03,-.27),(.21,.23,.29),steel,hip)
 knee=empty('Knee',hip,(0,0,-.53))
 mesh('Knee dome',(0,-.21,0),(.18,.12,.17),light,knee,shape='sphere')
 mesh('Shin armour',(0,0,-.24),(.19,.21,.27),steel,knee)
 mesh('Shin raised panel',(0,-.22,-.24),(.12,.055,.19),light,knee)
 mesh('Boot',(0,-.13,-.49),(.22,.34,.15),armor,knee)
 mesh('Boot sole',(0,-.13,-.59),(.23,.35,.045),dark,knee,bevel=.025)
# Recessed circular exhausts, flexible conduits and layered knee/ankle details.
def tube(name,points,radius,material,parent=body):
 curve=bpy.data.curves.new(name,'CURVE');curve.dimensions='3D';curve.bevel_depth=radius;curve.bevel_resolution=3
 spline=curve.splines.new('BEZIER');spline.bezier_points.add(len(points)-1)
 for pt,co in zip(spline.bezier_points,points):pt.co=co;pt.handle_left_type='AUTO';pt.handle_right_type='AUTO'
 obj=bpy.data.objects.new(name,curve);bpy.context.collection.objects.link(obj);obj.parent=parent;obj.data.materials.append(material);return obj
def ring(name,loc,major,minor,material,parent=body,rotation=(math.pi/2,0,0)):
 bpy.ops.mesh.primitive_torus_add(major_radius=major,minor_radius=minor,major_segments=32,minor_segments=10)
 o=bpy.context.object;o.name=name;o.parent=parent;o.location=loc;o.rotation_euler=rotation;o.data.materials.append(material)
 for polygon in o.data.polygons:polygon.use_smooth=True
 return o
for side in (-1,1):
 x=side*.27
 ring('Recessed turbine rim',(x,.585,.94),.108,.025,steel)
 mesh('Turbine black well',(x,.583,.94),(.086,.018,.086),dark,shape='sphere')
 ring('Inner turbine ring',(x,.606,.94),.058,.012,steel)
 for angle in range(6):
  a=angle*math.tau/6
  tube('Exhaust vane',[(x+math.cos(a)*.025,.613,.94+math.sin(a)*.025),(x+math.cos(a+.4)*.079,.613,.94+math.sin(a+.4)*.079)],.009,steel)
 tube('Armoured waist conduit',[(side*.32,.16,.30),(side*.43,.22,.15),(side*.30,.16,.02)],.034,dark)
 tube('Chest curved seam',[(side*.05,-.399,.78),(side*.23,-.397,.75),(side*.34,-.33,.62)],.012,dark)
 tube('Shoulder engraved seam',[(side*.39,-.22,1.08),(side*.53,-.30,1.09),(side*.73,-.22,1.10)],.012,dark)
 tube('Pauldron layered rim',[(side*.35,-.19,.77),(side*.56,-.30,.70),(side*.79,-.18,.75)],.025,steel)
 for rib in range(4):
  tube('Elbow flexible rib',[(side*.49,-.22-rib*.024,.43),(side*.60,-.24-rib*.024,.40),(side*.64,-.29-rib*.024,.44)],.017,dark)
 for bolt in (-1,1):mesh('Chest inset fastener',(side*.32,-.35,.58+bolt*.1),(.021,.025,.021),steel,shape='sphere')
for hip in legs:
 knee=next(child for child in hip.children if child.type=='EMPTY')
 for z in (-.09,-.14,-.19):ring('Ankle flexible bellows',(0,.015,z-.25),.135,.022,dark,knee,(0,0,0))
 tube('Shin plate seam',[(-.12,-.18,-.13),(0,-.255,-.18),(.12,-.18,-.13)],.013,dark,knee)
 for y in (-.34,-.26,-.18):tube('Boot toe articulation',[(-.15,y,-.47),(0,y-.02,-.435),(.15,y,-.47)],.014,steel,knee)
# Slotted barrel shroud, charging handle, separate trigger guard and fingers.
for y in (-.98,-1.08,-1.18):
 tube('Diagonal shroud slot',[(.13,y-.025,.704),(.25,y+.025,.704)],.018,dark,weapon)
mesh('Charging handle',(.35,-.75,.64),(.045,.08,.025),steel,weapon,bevel=.015)
tube('Trigger guard',[(.29,-.55,.48),(.33,-.59,.36),(.27,-.68,.36)],.018,steel,weapon)
for y in (-.97,-1.02,-1.07):tube('Support glove finger',[(-.005,y,.53),(.045,y,.46),(.12,y,.47)],.025,dark)

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
# Keep editable actions in the saved blend, but do not let evaluation overwrite export poses.
for obj in [root,body,weapon,flash]+legs:obj.animation_data_clear()
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
 scene.render.resolution_x=640;scene.render.resolution_y=640;scene.cycles.samples=128
 for direction,name in [(1,'model-preview'),(5,'model-back'),(3,'model-side')]:
  pose('idle',0,6,direction);scene.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
