"""Render transparent Blight recruitment portraits from the original meshes.

From the project directory:
    blender -b -t 6 --python-exit-code 1 -P tools/art/recruit_portraits/render_blight.py
Set BLIGHT_PORTRAIT_OUTPUT to override the output directory. Arguments after
"--" select one or more unit IDs; without IDs, renders the whole faction.
"""
import math
import os
from pathlib import Path
import sys

import bpy
from mathutils import Euler, Vector

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import blight_forms


UNITS = [
    "swarm", "rotling", "splitter", "bloater", "spitter", "fly_swarm",
    "spore_drifter", "abomination", "plague_herald", "gravedigger", "brood_mother",
]
# Palette values are sRGB. The same palette is used across the eleven portraits.
PALETTE = {
    "hide": ("262a2b", "69725b", .56, .19, .06, 0),
    "chitin": ("252032", "685371", .35, .28, .04, 0),
    "rust_chitin": ("291927", "8a4c5a", .33, .26, .05, 0),
    "flesh": ("381e33", "98606c", .41, .22, .10, 0),
    "bone": ("796a56", "dbd2a6", .47, .21, .04, 0),
    "blade": ("3c3544", "ad97b2", .29, .23, .02, 0),
    "rot": ("405239", "9ba94a", .36, .20, .12, 0),
    "pustule": ("5b702b", "bdc447", .28, .18, .15, .04),
    "acid": ("77aa2e", "e6f985", .25, .11, .12, .35),
    "spore_glass": ("244943", "71b37e", .28, .20, .09, .13),
    "membrane": ("50536d", "c9ae91", .35, .14, .10, 0),
    "dark_membrane": ("463149", "a87c85", .38, .15, .10, 0),
    "egg": ("627369", "d6d7b1", .32, .19, .12, 0),
    "shroud": ("252237", "63596c", .71, .25, 0, 0),
    "cavity": ("100b17", "251928", .53, .12, 0, 0),
}


def srgb(hex_value):
    rgb = [int(hex_value[i:i+2], 16)/255 for i in (0, 2, 4)]
    return tuple(c/12.92 if c < .04045 else ((c+.055)/1.055)**2.4 for c in rgb) + (1,)


def material(name, values):
    lower, upper, roughness, relief, subsurface, emission = values
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    link = mat.node_tree.links.new
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Subsurface Weight"].default_value = subsurface
    bsdf.inputs["Subsurface Scale"].default_value = .10
    if name in {"acid", "spore_glass", "pustule", "egg"}:
        bsdf.inputs["Coat Weight"].default_value = .30
        bsdf.inputs["Coat Roughness"].default_value = .22
    coordinate = nodes.new("ShaderNodeTexCoord")
    pigment = nodes.new("ShaderNodeTexNoise")
    pigment.inputs["Scale"].default_value = 8.0
    pigment.inputs["Roughness"].default_value = .74
    pigment.inputs["Detail"].default_value = 3.7
    link(coordinate.outputs["Object"], pigment.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = .24
    ramp.color_ramp.elements[0].color = srgb(lower)
    ramp.color_ramp.elements[1].position = .74
    ramp.color_ramp.elements[1].color = srgb(upper)
    link(pigment.outputs["Fac"], ramp.inputs[0])
    link(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    if emission:
        link(ramp.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission
    pores = nodes.new("ShaderNodeTexNoise")
    pores.inputs["Scale"].default_value = 63
    pores.inputs["Roughness"].default_value = .69
    pores.inputs["Detail"].default_value = 2
    link(coordinate.outputs["Object"], pores.inputs["Vector"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = relief
    bump.inputs["Distance"].default_value = .019
    link(pores.outputs["Fac"], bump.inputs["Height"])
    link(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def interpolate(a, b, c, d, t):
    return .5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)


class Sculpture:
    """Collect smooth organic shells, tapered limbs and curved membranes by material."""

    def __init__(self):
        self.parts = {}

    def add(self, vertices, faces, material_name):
        verts, polys = self.parts.setdefault(material_name, ([], []))
        offset = len(verts)
        verts.extend(vertices)
        polys.extend(tuple(i+offset for i in face) for face in faces)

    def form(self, center, scales, mat, turn=(0,0,0), noise=.05):
        c = Vector(center)
        r = Euler(turn).to_matrix()
        phase = len(self.parts.get(mat, ((),))[0]) % 31
        segments = 24 if max(scales) > .16 else 16
        layers = 16 if max(scales) > .16 else 10
        verts = [c + r @ Vector((0,0,scales[2]))]
        for j in range(1,layers):
            latitude = math.pi*j/layers
            for i in range(segments):
                angle = math.tau*i/segments
                wave = 1 + noise*(.60*math.sin(3*angle+phase)*math.sin(4*latitude)
                                  +.40*math.cos(5*angle-2*latitude+phase))
                local = Vector((math.sin(latitude)*math.cos(angle)*scales[0],
                                math.sin(latitude)*math.sin(angle)*scales[1],
                                math.cos(latitude)*scales[2]))
                verts.append(c+r@(local*wave))
        bottom = len(verts)
        verts.append(c-r@Vector((0,0,scales[2])))
        faces = [tuple((0,1+i,1+(i+1)%segments)) for i in range(segments)]
        for j in range(layers-2):
            upper = 1+j*segments
            lower = upper+segments
            for i in range(segments):
                nxt = (i+1)%segments
                faces.append((upper+i,lower+i,lower+nxt,upper+nxt))
        rim = bottom-segments
        faces.extend((bottom,rim+(i+1)%segments,rim+i) for i in range(segments))
        self.add(verts,faces,mat)

    def sweep(self, controls, mat, flatten=1.0):
        p = [Vector(point[:3]) for point in controls]
        sizes = [point[3] for point in controls]
        extended = [p[0]*2-p[1],*p,p[-1]*2-p[-2]]
        radii = [sizes[0],*sizes,sizes[-1]]
        points = []
        widths = []
        for i in range(len(p)-1):
            for j in range(6):
                t = j/6
                points.append(interpolate(*extended[i:i+4],t))
                widths.append(max(.002,interpolate(*radii[i:i+4],t)))
        points.append(p[-1])
        widths.append(sizes[-1])
        verts, faces = [], []
        sides = 16 if max(sizes) > .1 else 10
        direction = (points[1]-points[0]).normalized()
        ref = Vector((0,1,0)) if abs(direction.y) < .89 else Vector((1,0,0))
        cross = direction.cross(ref).normalized()
        for i,(point,radius) in enumerate(zip(points,widths)):
            direction = (points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized()
            cross = (cross-direction*cross.dot(direction)).normalized()
            binormal = direction.cross(cross)
            for j in range(sides):
                angle = math.tau*j/sides
                wave = 1+.047*math.cos(5*angle+i*.51)
                verts.append(point+radius*wave*(cross*math.cos(angle)
                                              +binormal*math.sin(angle)*flatten))
        for i in range(len(points)-1):
            for j in range(sides):
                k = (j+1)%sides
                faces.append((i*sides+j,i*sides+k,(i+1)*sides+k,(i+1)*sides+j))
        faces.append(tuple(range(sides-1,-1,-1)))
        faces.append(tuple((len(points)-1)*sides+i for i in range(sides)))
        self.add(verts, faces, mat)

    def along(self, start, end, radius, mat):
        self.sweep([(*start,radius),(*end,radius)],mat)

    def ring(self, start, end, radius, thickness, mat):
        center = Vector(end)
        normal = (center - Vector(start)).normalized()
        ref = Vector((0,0,1)) if abs(normal.z) < .9 else Vector((1,0,0))
        side = normal.cross(ref).normalized()
        up = normal.cross(side).normalized()
        verts,faces = [],[]
        segments,sides = 32,12
        for i in range(segments):
            a = math.tau*i/segments
            radial = side*math.cos(a)+up*math.sin(a)
            for j in range(sides):
                b = math.tau*j/sides
                verts.append(center+radial*(radius+thickness*math.cos(b))
                             +normal*thickness*math.sin(b))
        for i in range(segments):
            for j in range(sides):
                p,q=(i+1)%segments,(j+1)%sides
                faces.append((i*sides+j,p*sides+j,p*sides+q,i*sides+q))
        self.add(verts,faces,mat)

    def bladder(self, center, radius, mat, stretch=(1,1,1)):
        self.form(center,tuple(radius*a for a in stretch),mat,noise=.10)
        x,y,z=center
        for i in range(3):
            t=math.tau*i/3+.30
            dx,dy=math.cos(t),math.sin(t)
            self.sweep([(x+dx*radius*.49,y+dy*radius*.49,z-radius*.58,radius*.15),
                        (x+dx*radius*.81,y+dy*radius*.78,z-radius*.38,radius*.12),
                        (x+dx*radius*.94,y+dy*radius*.85,z-radius*.16,radius*.020)],
                       'flesh')

    def wing(self, corners, material_name):
        controls = [Vector(c) for c in corners]
        mid = sum(controls,Vector()) / len(controls)
        mid.z += .12
        border = []
        for i in range(len(corners)):
            for j in range(6):
                border.append(interpolate(*(controls[k%len(controls)] for k in range(i-1,i+3)),j/6))
        normal = (controls[1]-controls[0]).cross(controls[2]-controls[0]).normalized()
        verts = [mid+normal*.009]+[p+normal*.009 for p in border]
        offset=len(verts)
        verts += [mid-normal*.009]+[p-normal*.009 for p in border]
        faces=[]
        for i in range(len(border)):
            now,nxt=1+i,1+(i+1)%len(border)
            faces.extend([(0,now,nxt),(offset,offset+nxt,offset+now),
                          (now,offset+now,offset+nxt,nxt)])
        self.add(verts,faces,material_name)
        self.sweep([(*p,.027 if i==0 else .015) for i,p in enumerate(controls+[controls[0]])],'hide')
        root = controls[0]
        for joint,tip in enumerate(controls[1:-1]):
            middle=root.lerp(tip,.54)
            middle.z += .074
            self.sweep([(*root,.051),(*middle,.030-joint*.004),(*tip,.006)],'hide')
            fork=tip.lerp(controls[joint+2],.68)
            self.sweep([(*middle,.020),(*middle.lerp(fork,.46),.013),(*fork,.003)],'hide')

    def shovel(self, center, width, height):
        c=Vector(center)
        border = [(-.27,0,-.26),(-.46,0,-.02),(-.49,0,.16),(-.24,0,.39),
                  (0,0,.49),(.25,0,.39),(.49,0,.16),(.46,0,-.02),(.27,0,-.26)]
        pts=[c+Vector((x*width,y,z*height)) for x,y,z in border]
        verts=[c+Vector((0,-.107,0)),c+Vector((0,.030,0)),*pts]
        faces=[]
        for i in range(len(pts)):
            n=(i+1)%len(pts)
            faces += [(0,i+2,n+2),(1,n+2,i+2)]
        self.add(verts,faces,'blade')
        self.sweep([(*p,.020 if i not in (0,len(pts)-1) else .013) for i,p in enumerate(pts)],
                   'bone')
        self.sweep([(*tuple(c+Vector((0,-.07,-.20))),.049),
                    (*tuple(c+Vector((0,-.11,-.04))),.037),
                    (*tuple(c+Vector((0,-.07,.12))),.009)],'chitin')

    def instantiate(self, materials):
        for name,(vertices,faces) in self.parts.items():
            data=bpy.data.meshes.new(name)
            data.from_pydata(vertices,[],faces)
            data.update()
            obj=bpy.data.objects.new(name,data)
            bpy.context.scene.collection.objects.link(obj)
            data.materials.append(materials[name])
            for polygon in data.polygons:
                polygon.use_smooth = True

    def bounds(self, axis):
        values=[Vector(v).dot(axis) for vertices,_ in self.parts.values() for v in vertices]
        return min(values),max(values)


def area(name, position, color, energy, size):
    light = bpy.data.lights.new(name, "AREA")
    light.energy=energy
    light.size=size
    light.color=color
    obj = bpy.data.objects.new(name, light)
    bpy.context.scene.collection.objects.link(obj)
    obj.location=position
    obj.rotation_euler=(-obj.location).to_track_quat("-Z","Y").to_euler()


def setup_scene():
    scene=bpy.context.scene
    scene.render.engine="CYCLES"
    scene.cycles.samples=48
    scene.cycles.use_denoising=False
    scene.cycles.max_bounces=5
    scene.render.resolution_x=256
    scene.render.resolution_y=256
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format="PNG"
    scene.render.image_settings.color_mode="RGBA"
    scene.render.film_transparent=True
    scene.view_settings.view_transform="AgX"
    scene.view_settings.look="AgX - Medium High Contrast"
    scene.view_settings.exposure=.50
    scene.world.use_nodes=True
    ambient=scene.world.node_tree.nodes.get("Background")
    ambient.inputs[0].default_value=(.22,.29,.37,1)
    ambient.inputs[1].default_value=.43
    area("Cold key",(-3.2,-4.0,5.3),(.71,.83,1.0),570,3.4)
    area("Mint fill",(3.0,-4.4,2.6),(.69,.92,1.0),160,3.8)
    area("Purple rim",(3.1,2.4,4.0),(.86,.59,1.0),670,2.25)
    area("Warm edge",(-4.1,2.4,2.8),(1.0,.58,.37),310,2.4)


def create_camera(sculpture, unit):
    azimuth,elevation = {
        "fly_swarm": (17,31), "swarm": (21,25), "bloater": (26,17),
        "brood_mother": (25,34), "spore_drifter": (27,29), "gravedigger": (20,17),
        "splitter": (18,16), "spitter": (27,22), "plague_herald": (23,20),
        "rotling": (24,16), "abomination": (24,17),
    }[unit]
    azimuth,elevation=map(math.radians,(azimuth,elevation))
    backward=Vector((math.sin(azimuth)*math.cos(elevation),-math.cos(azimuth)*math.cos(elevation),math.sin(elevation)))
    rot=(-backward).to_track_quat("-Z","Y")
    right,up=rot@Vector((1,0,0)), rot@Vector((0,1,0))
    lo_x,hi_x=sculpture.bounds(right)
    lo_y,hi_y=sculpture.bounds(up)
    center=(lo_x+hi_x)/2*right+(lo_y+hi_y)/2*up
    camera_data=bpy.data.cameras.new("Recruit Portrait")
    camera_data.type="ORTHO"
    camera_data.ortho_scale=max(hi_x-lo_x,hi_y-lo_y)/.891
    camera=bpy.data.objects.new("Recruit Portrait",camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location=center+8*backward
    camera.rotation_euler=rot.to_euler()
    bpy.context.scene.camera=camera


def main():
    output=Path(os.environ.get("BLIGHT_PORTRAIT_OUTPUT",
                               Path(__file__).resolve().parents[3] / "assets/ui/recruits"))
    output.mkdir(parents=True,exist_ok=True)
    selected=sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else UNITS
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    setup_scene()
    palette={name:material(name,values) for name,values in PALETTE.items()}
    for unit in selected:
        for obj in list(bpy.context.scene.objects):
            if obj.type in {"MESH","CAMERA"}:
                data=obj.data
                bpy.data.objects.remove(obj,do_unlink=True)
                if isinstance(data,bpy.types.Mesh):
                    bpy.data.meshes.remove(data)
                else:
                    bpy.data.cameras.remove(data)
        sculpture=Sculpture()
        getattr(blight_forms,unit)(sculpture)
        sculpture.instantiate(palette)
        create_camera(sculpture,unit)
        bpy.context.scene.render.filepath=str(output / (unit+".png"))
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
