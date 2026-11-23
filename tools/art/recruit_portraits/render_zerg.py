"""Build the eleven Zerg recruiting portraits with Blender 4.x.

From the repository root: blender -b -P tools/art/recruit_portraits/render_zerg.py
Append -- followed by unit IDs to render just those portraits.
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from zerg_forms import UNITS

OUTPUT = HERE.parents[2] / "assets" / "ui" / "recruits"
V = Vector
TAU = math.tau
PALETTE = {
    # Base and light pigment, roughness, subsurface weight, emission strength.
    "obsidian": ("120f22", "49425f", .30, .02, 0),
    "rust": ("361315", "9d3b2d", .36, .03, 0),
    "shell": ("29142f", "77364f", .33, .06, 0),
    "ridge": ("3e1f43", "a35872", .31, .07, 0),
    "skin": ("351520", "924537", .42, .12, 0),
    "dark": ("1b101f", "50283c", .44, .03, 0),
    "bone": ("9c745e", "f3d4a4", .34, .06, 0),
    "amber": ("e93408", "ff9e34", .19, .04, .48),
    "aqua": ("095a76", "36dcdb", .24, .09, .23),
    "acid": ("286322", "9bdf42", .26, .15, .24),
    "wing": ("441727", "bd5844", .50, .04, 0),
    "membrane": ("4a2037", "b8666a", .40, .14, 0),
    "sac": ("b8330f", "ffb83c", .28, .18, .16),
}

def linear(hex_color):
    raw = [int(hex_color[i:i+2], 16) / 255 for i in (0, 2, 4)]
    return tuple(c/12.92 if c <= .04045 else ((c+.055)/1.055)**2.4 for c in raw) + (1,)

def materials():
    result = {}
    for key, (low, high, roughness, sss, glow) in PALETTE.items():
        mat = bpy.data.materials.new(key)
        mat.diffuse_color = linear(high)
        mat.use_nodes = True
        graph = mat.node_tree
        p = graph.nodes.get("Principled BSDF")
        p.inputs["Roughness"].default_value = roughness
        p.inputs["Subsurface Weight"].default_value = sss
        p.inputs["Subsurface Radius"].default_value = (.11,.052,.03)
        p.inputs["Specular IOR Level"].default_value = .31
        p.inputs["Coat Weight"].default_value = .14 if key not in ("dark", "skin", "bone") else .04
        p.inputs["Coat Roughness"].default_value = .29
        p.inputs["Emission Color"].default_value = linear(high)
        p.inputs["Emission Strength"].default_value = glow
        tex = graph.nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = 3.0 if key != "membrane" else 5.0
        tex.inputs["Detail"].default_value = 2.8
        tex.inputs["Roughness"].default_value = .65
        ramp = graph.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = .18
        ramp.color_ramp.elements[0].color = linear(low)
        ramp.color_ramp.elements[1].position = .80
        ramp.color_ramp.elements[1].color = linear(high)
        graph.links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
        graph.links.new(ramp.outputs["Color"], p.inputs["Base Color"])
        grain = graph.nodes.new("ShaderNodeTexNoise")
        grain.inputs["Scale"].default_value = 53 if key in ("shell", "ridge") else 27
        grain.inputs["Detail"].default_value = 2
        bump = graph.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = .13
        bump.inputs["Distance"].default_value = .012
        graph.links.new(grain.outputs["Fac"], bump.inputs["Height"])
        graph.links.new(bump.outputs["Normal"], p.inputs["Normal"])
        result[key] = mat
    return result

class Anatomy:
    def __init__(self, palette):
        self.palette = palette
        self.parts = []

    def finish(self, obj, material):
        obj.data.materials.append(self.palette[material])
        for f in obj.data.polygons:
            f.use_smooth = True
        self.parts.append(obj)
        return obj

    def mesh(self, name, vertices, faces, material):
        data = bpy.data.meshes.new(name)
        data.from_pydata(vertices, [], faces)
        data.update()
        obj = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(obj)
        return self.finish(obj, material)

    def ell(self, name, center, radii, mat, rotation=(0, 0, 0)):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=14, radius=1, location=center)
        obj = bpy.context.object
        obj.name = name
        obj.scale = radii
        obj.rotation_euler = rotation
        return self.finish(obj, mat)

    def plate(self, name, center, radii, mat="shell", rotation=(0, 0, 0)):
        # An overlapping carapace with a narrow trailing tip, ridged crown and rolled lip.
        verts = []
        faces = []
        rings, sides = 16, 24
        for i in range(rings + 1):
            t = i / rings
            x = -math.cos(math.pi*t)
            r = max(.003, math.sin(math.pi*t))
            for j in range(sides):
                a = TAU*j/sides
                y = r*math.cos(a)*(.72+.33*t)
                h = math.sin(a)
                crown = max(0, h)
                z = r*(.38*min(0, h) + crown*(.73+.23*crown**9))
                z += .065*x + .065*r*math.cos(3*a)*crown
                verts.append((radii[0]*x,radii[1]*y,radii[2]*z))
        for i in range(rings):
            for j in range(sides):
                n = (j+1)%sides
                faces.append((i*sides+j,i*sides+n,(i+1)*sides+n,(i+1)*sides+j))
        obj = self.mesh(name, verts, faces, mat)
        obj.location = center
        obj.rotation_euler = rotation
        return obj

    def tube(self, name, points, radii, mat, flat=1):
        # Catmull-Rom center line, transported ring frames and tapered radii.
        points = [V(p) for p in points]
        path = []
        widths = []
        for i in range(len(points)-1):
            p,q = points[i:i+2]
            prev = points[max(0,i-1)]
            after = points[min(len(points)-1,i+2)]
            for ii in range(5):
                t = ii/5
                path.append(.5*(2*p+(-prev+q)*t+(2*prev-5*p+4*q-after)*t*t+(-prev+3*p-3*q+after)*t**3))
                widths.append(max(.001, radii[i]*(1-t)+radii[i+1]*t))
        path.append(points[-1]); widths.append(max(.001,radii[-1]))
        vertices, faces = [], []
        last_side = None
        sides = 12
        for i, (c, r) in enumerate(zip(path, widths)):
            tangent = (path[min(i+1,len(path)-1)]-path[max(0,i-1)]).normalized()
            if last_side is None:
                seed = V((0,1,0)) if abs(tangent.y)<.88 else V((0,0,1))
            else:
                seed = last_side
            side = (seed - tangent*seed.dot(tangent)).normalized()
            outward = tangent.cross(side)
            last_side = side
            for j in range(sides):
                a = TAU*j/sides
                vertices.append(c+r*(math.cos(a)*flat*side + math.sin(a)*outward))
            if i:
                for j in range(sides):
                    k = (j+1)%sides
                    faces.append(((i-1)*sides+j,(i-1)*sides+k,i*sides+k,i*sides+j))
        faces += [tuple(reversed(range(sides))), tuple((len(path)-1)*sides+j for j in range(sides))]
        return self.mesh(name, vertices, faces, mat)

    def membrane(self, name, boundary, root, mat="membrane", lift=.08):
        outline = [V(v) for v in boundary]
        root = V(root)
        vertices = [root]
        faces = []
        n = len(outline)
        # The cambered skin sags between wing fingers and scalloped outer edges.
        for i in range(1,6):
            t = i/5
            for j,v in enumerate(outline):
                p = root.lerp(v,t)
                p.z += lift*math.sin(t*math.pi)*(1+.20*math.sin(j*1.8))
                vertices.append(p)
        for j in range(n-1):
            faces.append((0,1+j,2+j))
            for i in range(1,5):
                a=1+(i-1)*n+j
                faces.append((a,a+n,a+n+1,a+1))
        return self.mesh(name,vertices,faces,mat)

    def fang(self, name, points, thick, mat="bone", flat=.70):
        self.tube(name, points, [thick*(1-i/(len(points)-1))**.74 for i in range(len(points))], mat,flat)

    def leg(self, name, start, knee, hock, toe, thick):
        a,b,c,d = (V(p) for p in (start,knee,hock,toe))
        self.tube(name+" coxa",[a,a.lerp(b,.44),b], [thick*.89,thick*1.18,thick*.59],"skin")
        self.tube(name+" tibial plate",[b,b.lerp(c,.34),c], [thick*.89,thick*.77,thick*.32],"shell",.83)
        self.ell(name+" condyle",b,(thick*.72,thick*.74,thick*.67),"ridge")
        self.fang(name+" tarsus",[c,c.lerp(d,.48)+V((0,0,-thick*.23)),d],thick*.38)

def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (bpy.data.meshes,bpy.data.curves,bpy.data.materials,bpy.data.cameras,bpy.data.lights):
        for block in list(collection):
            if block.users == 0:
                collection.remove(block)

def lamp(name, pos, energy, color, size):
    data = bpy.data.lights.new(name,"AREA")
    data.energy, data.color, data.shape, data.size = energy, color, "DISK", size
    obj=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(obj)
    obj.location=pos
    obj.rotation_euler=(-V(pos)).to_track_quat("-Z","Y").to_euler()

def render(unit):
    clear()
    scene=bpy.context.scene
    a=Anatomy(materials());UNITS[unit](a)
    bpy.context.view_layer.update()
    cam_data=bpy.data.cameras.new("Recruit portrait")
    cam=bpy.data.objects.new("Recruit portrait",cam_data);bpy.context.collection.objects.link(cam)
    view = {"mutalisk":(4.7,-3.75,5.9), "brood_lord":(4.9,-2.95,5.1),
            "ultralisk":(4.5,-4.4,3.45), "roach":(3.8,-5.5,4.2),
            "hydralisk":(4.15,-4.9,2.9), "piercer":(3.5,-5.4,4.0)}
    direction=V(view.get(unit,(3.5,-5.8,3.1))).normalized()
    cam.rotation_euler=(-direction).to_track_quat("-Z","Y").to_euler()
    orientation=cam.rotation_euler.to_quaternion()
    right,up=orientation@V((1,0,0)),orientation@V((0,1,0))
    coords=[part.matrix_world@v.co for part in a.parts for v in part.data.vertices]
    xs=[v.dot(right) for v in coords];ys=[v.dot(up) for v in coords]
    target=right*((max(xs)+min(xs))*.5)+up*((max(ys)+min(ys))*.5)
    cam.location=target+direction*10;cam_data.type="ORTHO"
    cam_data.ortho_scale=max(max(xs)-min(xs),max(ys)-min(ys))*1.093
    scene.camera=cam
    lamp("Broad warm key",(2.2,-3.8,6.3),570,(1,.86,.76),3.1)
    lamp("Pearl bounce",(4,-4,.8),86,(.64,.78,1),2.4)
    lamp("Amethyst rim",(-3,2,4.2),490,(.55,.59,1),2.4)
    lamp("Carapace edge",(1,3,2.0),355,(1,.54,.32),2.2)
    scene.world.color=(.065,.060,.095)
    scene.render.engine="CYCLES";scene.cycles.samples=56
    scene.cycles.use_denoising=False;scene.cycles.max_bounces=3
    scene.render.resolution_x=256;scene.render.resolution_y=256;scene.render.resolution_percentage=100
    scene.render.film_transparent=True
    scene.render.image_settings.file_format="PNG";scene.render.image_settings.color_mode="RGBA"
    scene.view_settings.view_transform="AgX"
    scene.render.filepath=str(OUTPUT/(unit+".png"))
    bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    OUTPUT.mkdir(parents=True,exist_ok=True)
    names=sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else list(UNITS)
    for unit in names:
        render(unit)
