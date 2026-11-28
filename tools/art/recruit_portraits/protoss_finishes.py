"""Recruit-only finishes on the uploaded GLBs. Source coordinates use glTF Y-up."""
from importlib import import_module

_MODELS = {
    "carrier": ("protoss_hulls", 39),
    "stalker": ("protoss_hulls", 18),
    "sentry": ("protoss_cores", 42),
    "disruptor": ("protoss_cores", 16),
    "colossus": ("protoss_walkers", 44),
    "immortal": ("protoss_walkers", 26),
}
MODEL_UNITS = tuple(_MODELS)

# Polished armour, dark joints, coloured insets and luminous optics.
# Display hex, metalness, roughness and emission strength.
PALETTE = {
    "gold": ("D6A14E", .73, .385, 0),
    "champagne": ("F6D68C", .64, .375, 0),
    "bronze": ("996336", .72, .445, 0),
    "ivory": ("F4E7CC", .48, .395, 0),
    "gunmetal": ("434A56", .65, .465, 0),
    "steel": ("8898AD", .67, .415, 0),
    "silver": ("BBC9E3", .68, .355, 0),
    "navy": ("27355A", .48, .435, 0),
    "cobalt": ("4566A8", .55, .375, 0),
    "violet": ("847FBD", .57, .385, 0),
    "blue": ("327BEA", .32, .325, .55),
    "cyan": ("5AD6FC", .24, .295, .76),
    "amber": ("FF9D38", .23, .315, .79),
    "white_glow": ("D3F6FF", .16, .325, .66),
    "psi_core": ("4196EE", .20, .345, .47),
    "plasma_core": ("FF9D38", .24, .365, .42),
}

CORE_COLORS = {
    "psi_core": ("1A417F", "3168C5", "47A5E7", "BAF0FF", "508DD4", "529FDF"),
    "plasma_core": ("723421", "B15124", "E78434", "FFDA87", "C1652E", "ED933F"),
}


def view(unit):
    return import_module(_MODELS[unit][0]).VIEWS[unit]


def linear_rgba(hex_color):
    rgb = [int(hex_color[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in rgb) + (1.,)


def material(name):
    import bpy
    hex_color, metallic, roughness, glow = PALETTE[name]
    linear = linear_rgba(hex_color)
    mat = bpy.data.materials.new("Recruit " + name)
    mat.diffuse_color = linear
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    for socket, value in (("Base Color", linear), ("Metallic", metallic), ("Roughness", roughness),
                          ("Emission Color", linear), ("Emission Strength", glow)):
        shader.inputs[socket].default_value = value
    if name in CORE_COLORS:
        # Broad currents and a narrow luminous band on the actual core. The
        # Generated coordinates remain continuous across its unwrapped surface.
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 3.8
        noise.inputs["Detail"].default_value = 2.2
        noise.inputs["Distortion"].default_value = 1.6
        ramp = nodes.new("ShaderNodeValToRGB")
        stops = ramp.color_ramp.elements
        stops.remove(stops[1])
        for index, (position, color) in enumerate(zip((.18, .39, .49, .54, .598, .81), CORE_COLORS[name])):
            stop = stops.new(position) if index else stops[0]
            stop.position = position
            stop.color = linear_rgba(color)
        links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        for socket in ("Base Color", "Emission Color"):
            links.new(ramp.outputs["Color"], shader.inputs[socket])
    return mat


def apply_finish(unit, source, scene):
    import numpy as np
    from scipy.spatial import cKDTree
    from rigid_glb import load_surface

    style, expected_islands = _MODELS[unit]
    triangles, islands = load_surface(source, expected_islands)
    finish = np.asarray(import_module(style).paint(unit, triangles, islands))
    if finish.shape != islands.shape:
        raise ValueError(f"Missing face assignments for {unit}")
    # Import can reorder vertices and faces. Match face centres back to the
    # original rather than depending on Blender's polygon indices.
    obj, = (obj for obj in scene.objects if obj.type == 'MESH')
    mesh = obj.data
    centers = np.empty((len(mesh.polygons), 3), dtype=np.float32)
    mesh.polygons.foreach_get("center", centers.ravel())
    transform = np.asarray(obj.matrix_world)
    world = centers @ transform[:3, :3].T + transform[:3, 3]
    gltf = np.column_stack((world[:, 0], world[:, 2], -world[:, 1]))
    distance, nearest = cKDTree(triangles[:, :, :3].mean(axis=1)).query(gltf)
    # Blender can discard duplicate source triangles while importing.
    if distance.max() > .00001:
        raise ValueError(f"The imported {unit} no longer matches the painted surface")
    names, indices = np.unique(finish[nearest], return_inverse=True)
    mesh.materials.clear()
    for name in names:
        mesh.materials.append(material(str(name)))
    mesh.polygons.foreach_set("material_index", indices.astype(np.int32))
    mesh.update()
