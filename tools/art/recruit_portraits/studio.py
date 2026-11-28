"""Shared Blender modeling primitives and studio for the mechanical recruit miniatures.

Render with blender -b -t 3 -P tools/art/recruit_portraits/studio.py -- <unit IDs>.
Geometry uses Z up, -Y forward. Framing is fitted to the projected subject.
Protoss IDs use their original game model or painted master via render_protoss.
"""
import math
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
OUT = HERE.parents[2] / "assets/ui/recruits"


def linear(x):
    return x / 12.92 if x < .04045 else ((x + .055) / 1.055) ** 2.4


def mat(name, color, metal=0., rough=.38, glow=0.):
    found = bpy.data.materials.get(name)
    if found:
        return found
    rgb = [int(color.lstrip("#")[i:i+2],16)/255 for i in (0,2,4)] if isinstance(color,str) else color
    rgba = tuple(linear(x) for x in rgb[:3])+(1.,)
    material = bpy.data.materials.new(name)
    material.diffuse_color = rgba
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    for key,value in [("Base Color",rgba),("Metallic",metal),("Roughness",rough),("Emission Color",rgba),("Emission Strength",glow)]:
        shader.inputs[key].default_value = value
    return material


M = {k:mat("Recruit "+k,*values) for k,values in {
    "gold":("d8a245",.77,.29), "gold_dark":("996126",.68,.33),
    "bronze":("825037",.75,.33), "ivory":("eee0bb",.62,.29), "alloy":("91a6a6",.75,.32),
    "recess":("253445",.64,.38), "teal":("087f9e",.47,.22,.22), "plasma":("35dbfa",.31,.2,1.8),
    "pale":("c9ffff",.17,.18,2.3),"indigo":("293459",.59,.31)
}.items()}


def surface(obj, name, material, smooth=True):
    obj.name = name
    obj.data.materials.append(material)
    if obj.type == 'MESH' and smooth:
        for f in obj.data.polygons:
            f.use_smooth = True
    return obj


def ell(name,center,radii,mat,rot=(0,0,0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32,ring_count=18,location=center,rotation=rot)
    obj=bpy.context.object
    obj.scale=radii
    return surface(obj,name,mat)


def beam(name,start,end,r0,r1,mat,vertices=16):
    a,b=Vector(start),Vector(end)
    bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r0,radius2=r1,depth=(b-a).length,location=(a+b)*.5)
    obj=bpy.context.object
    obj.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    return surface(obj,name,mat)


def tube(name,points,radius,mat):
    crv=bpy.data.curves.new(name,'CURVE')
    crv.dimensions='3D'
    crv.resolution_u=8
    crv.bevel_depth=radius
    crv.bevel_resolution=3
    spline=crv.splines.new('BEZIER')
    spline.bezier_points.add(len(points)-1)
    for pt,xyz in zip(spline.bezier_points,points):
        pt.co=xyz
        pt.handle_left_type='AUTO'
        pt.handle_right_type='AUTO'
    crv.use_fill_caps=True
    obj=bpy.data.objects.new(name,crv)
    bpy.context.collection.objects.link(obj)
    return surface(obj,name,mat)


def rounded(obj,width):
    if width>0:
        bevel=obj.modifiers.new("Machined corners",'BEVEL')
        bevel.width=width
        bevel.segments=3
        normals=obj.modifiers.new("Face normals",'WEIGHTED_NORMAL')
        normals.keep_sharp=True
    return obj


def box(name,center,size,mat,bevel=.05,rot=(0,0,0)):
    bpy.ops.mesh.primitive_cube_add(size=1.,location=center)
    obj=bpy.context.object
    for p in obj.data.vertices:
        for i in range(3):
            p.co[i]*=size[i]
    obj.rotation_euler=rot
    return rounded(surface(obj,name,mat,False),bevel)


def mesh(name,verts,faces,material,smooth=True):
    data=bpy.data.meshes.new(name)
    data.from_pydata(verts,[],faces)
    bm=bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    obj=bpy.data.objects.new(name,data)
    bpy.context.collection.objects.link(obj)
    return surface(obj,name,material,smooth)


def loft(name,sections,mat,sides=12,subdiv=1,axis='Y'):
    plane={'Y':(0,2),'X':(1,2),'Z':(0,1)}[axis.upper()]
    vertices=[]
    for x,y,z,ra,rb in sections:
        for i in range(sides):
            point=[x,y,z]
            angle=i*2*math.pi/sides
            point[plane[0]]+=ra*math.cos(angle)
            point[plane[1]]+=rb*math.sin(angle)
            vertices.append(point)
    faces=[tuple(range(sides-1,-1,-1))]
    for j in range(len(sections)-1):
        for i in range(sides):
            a=j*sides+i
            b=j*sides+(i+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces.append(tuple(range(len(vertices)-sides,len(vertices))))
    obj=mesh(name,vertices,faces,mat)
    if subdiv:
        mod=obj.modifiers.new("Formed shell",'SUBSURF')
        mod.levels=subdiv
    return obj


def plate(name,points,thickness,mat,bevel=.025):
    points=[Vector(p) for p in points]
    normal=(points[1]-points[0]).cross(points[2]-points[0]).normalized()*(thickness*.5)
    n=len(points)
    faces=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]
    faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
    return rounded(mesh(name,[p-normal for p in points]+[p+normal for p in points],faces,mat,False),bevel)


def clear():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj,do_unlink=True)


def light(name,location,target,power,color,size):
    data=bpy.data.lights.new(name,'AREA')
    data.energy=power
    data.shape='DISK'
    data.size=size
    data.color=color
    ob=bpy.data.objects.new(name,data)
    bpy.context.collection.objects.link(ob)
    ob.location=location
    ob.rotation_euler=(target-ob.location).to_track_quat('-Z','Y').to_euler()


def render(unit,build,direction,output):
    clear()
    build()
    deps=bpy.context.evaluated_depsgraph_get()
    points=[]
    for obj in list(bpy.context.scene.objects):
        evaluated=obj.evaluated_get(deps)
        meshdata=evaluated.to_mesh()
        if meshdata:
            points.extend(evaluated.matrix_world @ v.co for v in meshdata.vertices)
            evaluated.to_mesh_clear()
    direction=Vector(direction).normalized()
    camera_rotation=(-direction).to_track_quat('-Z','Y')
    right,up=camera_rotation@Vector((1,0,0)),camera_rotation@Vector((0,1,0))
    sx=[p.dot(right) for p in points]
    sy=[p.dot(up) for p in points]
    sd=[p.dot(direction) for p in points]
    center=(right*(min(sx)+max(sx))+up*(min(sy)+max(sy))+direction*(min(sd)+max(sd)))*.5
    extent=max(max(sx)-min(sx),max(sy)-min(sy))
    camera=bpy.data.cameras.new("Recruit lens")
    ob=bpy.data.objects.new("Camera",camera)
    bpy.context.collection.objects.link(ob)
    camera.type='ORTHO'
    camera.ortho_scale=extent/.905
    camera.clip_end=200.
    ob.location=center+direction*extent*3
    ob.rotation_euler=camera_rotation.to_euler()
    scene=bpy.context.scene
    scene.camera=ob
    for key,offset,power,color,size in [
        ("Upper softbox",(-2.,-2.8,4.),340,(1.,.88,.72),2.3),("Cool fill",(3.,-1.6,1.8),185,(.63,.83,1.),2.4),
        ("Rim strip",(-.5,2.1,2.3),360,(.65,.84,1.),1.5),("Visor catchlight",(.3,-3.,.45),40,(1.,.93,.78),.8)]:
        light(key,center+Vector(offset)*extent,center,power*extent**2,color,size*extent)
    scene.render.engine='CYCLES'
    scene.cycles.samples=48
    scene.cycles.use_denoising=False
    scene.world.use_nodes=True
    bg=scene.world.node_tree.nodes.get('Background')
    bg.inputs[0].default_value=(.29,.36,.46,1.)
    bg.inputs[1].default_value=.65
    scene.render.film_transparent=True
    scene.render.resolution_x=scene.render.resolution_y=256
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    scene.render.image_settings.color_mode='RGBA'
    scene.view_settings.view_transform='AgX'
    scene.render.filepath=str(output/(unit+'.png'))
    bpy.ops.render.render(write_still=True)


def main():
    from terran import BUILDERS as terran
    from render_protoss import UNITS as protoss, rebuild

    selection = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [*terran, *protoss]
    for unit in selection:
        if unit not in terran and unit not in protoss:
            raise ValueError(f"Unknown recruit portrait: {unit}")

    OUT.mkdir(exist_ok=True,parents=True)
    angles={'agent':(3.1,-7.7,2.5),'widow_mine':(3.2,-7.,4.7),'viking':(4.6,-7.,5.8),'liberator':(4.4,-7.2,5.2)}
    # GLB import resets Blender's scene and materials. Finish the modeled Terran portraits first.
    for unit in selection:
        if unit in terran:
            render(unit,terran[unit],angles.get(unit,(4.6,-7.7,4.4)),OUT)
    rebuild([unit for unit in selection if unit in protoss])


if __name__ == '__main__':
    # Make the same material objects available to modules importing this file.
    sys.modules['studio']=sys.modules[__name__]
    main()
