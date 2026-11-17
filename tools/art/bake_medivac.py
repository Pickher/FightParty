"""Bake the supplied GLB to a fixed-view transparent sprite, without running Godot.
Blender 4.3+: blender --background --factory-startup -t 4 --python tools/art/bake_medivac.py
Keeps source geometry/materials untouched; no animation or gameplay data is generated.
"""
from pathlib import Path
import hashlib,json,math
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'assets/models/medivac/medivac.glb'
OUT=ROOT/'assets/units/medivac'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
if not meshes:raise RuntimeError('Source GLB contains no mesh')
points=[o.matrix_world@Vector(c) for o in meshes for c in o.bound_box]
minimum=Vector(tuple(min(p[i] for p in points) for i in range(3)))
maximum=Vector(tuple(max(p[i] for p in points) for i in range(3)))
center=(minimum+maximum)/2
span=max(maximum-minimum)
bpy.ops.object.camera_add(location=center+Vector((4,-6,7)).normalized()*span*4)
camera=bpy.context.object
camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO'
# Camera-space bounds guarantee consistent padding rather than hand-cropping pixels.
bpy.context.view_layer.update()
projected=[camera.matrix_world.inverted()@p for p in points]
camera.data.ortho_scale=max(max(p[i] for p in projected)-min(p[i] for p in projected) for i in (0,1))*1.10
scene=bpy.context.scene
scene.camera=camera
scene.render.engine='CYCLES'
scene.cycles.device='CPU'
scene.cycles.samples=96
scene.cycles.use_denoising=False
scene.cycles.seed=0
scene.render.film_transparent=True
scene.render.resolution_x=512
scene.render.resolution_y=512
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.image_settings.color_mode='RGBA'
scene.render.image_settings.color_depth='8'
scene.view_settings.view_transform='Standard'
scene.view_settings.look='Medium High Contrast' if 'Medium High Contrast' in [x.identifier for x in scene.view_settings.bl_rna.properties['look'].enum_items] else 'None'
scene.view_settings.exposure=0
scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(0.8,0.85,1,1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=0.65
for name,offset,power,size in [('Key',(-3,-4,6),650,4),('Fill',(4,1,4),400,5)]:
 bpy.ops.object.light_add(type='AREA',location=center+Vector(offset)*span)
 lamp=bpy.context.object;lamp.name=name;lamp.data.energy=power*span*span;lamp.data.shape='DISK';lamp.data.size=size*span
 lamp.rotation_euler=(center-lamp.location).to_track_quat('-Z','Y').to_euler()
scene.render.filepath=str(OUT/'idle.png')
bpy.ops.render.render(write_still=True)
metadata={'source':'assets/models/medivac/medivac.glb','source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'blender':bpy.app.version_string,'sprite':'idle.png','size':[512,512],'view':'fixed orthographic oblique','camera_direction':[4,-6,7],'bounds_min':list(minimum),'bounds_max':list(maximum),'vertices':sum(len(o.data.vertices) for o in meshes),'triangles':sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons),'animated':False}
(OUT/'source.json').write_text(json.dumps(metadata,indent=2)+'\n')
