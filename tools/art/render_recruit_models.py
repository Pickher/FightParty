"""Render the static recruitment portraits from the game's authored models.

Blender 4.3+ with Pillow: blender -b -t 3 -P tools/art/render_recruit_models.py
Append -- and one or more unit IDs to render a subset.
"""
import math
import sys
import tempfile
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/art"))
sys.path.insert(0, str(ROOT / "tools/art/recruit_portraits"))
import protoss_finishes

OUTPUT = ROOT / "assets/ui/recruits"
MODELS = ROOT / "assets/models"
PROTOSS_DISPLAY_MODELS = {"sentry", "disruptor"}
PORTRAIT_ROLL = {"carrier": 30.0, "sentry": -25.5}
# Camera positions in Blender Z-up space. The GLB models face +X.
VIEWS = {
    "rifle": (ROOT / "assets/units/rifle/source/special_ops.blend", (-.88, -1.0, .40)),
    "hellbat": (MODELS / "hellbat/hellbat.glb", (.9, -1.05, .85)),
    "hellbat_mech": (MODELS / "hellbat_mech/hellbat_mech_rig.glb", (1.0, -.68, .46)),
    "marauder": (MODELS / "marauder/marauder_rig.glb", (1.0, -.55, .33)),
    "medivac": (MODELS / "medivac/medivac.glb", (.79, -.97, 1.02)),
    "mortar": (MODELS / "mortar/mortar_rig.glb", (.83, -1.0, .87)),
    "viking_assault": (MODELS / "viking/viking_assault_rig.glb", (1.0, -.70, .43)),
    "thor": (MODELS / "thor/thor_rig.glb", (1.0, -.55, .39)),
    "battlecruiser": (MODELS / "battlecruiser/battlecruiser.glb", (.76, -1.0, .94)),
}


def model_scene(unit, source):
    if source.suffix == ".blend":
        bpy.ops.wm.open_mainfile(filepath=str(source))
        scene = bpy.context.scene
        scene.frame_set(1)
        # A waist-up portrait leaves the amber visor, pauldrons and carbine large
        # enough to retain their individual silhouettes in the 52-pixel slot.
        for side in ("Hip L", "Hip R"):
            for obj in scene.objects[side].children_recursive:
                obj.hide_render = True
        anchor = scene.objects["Ground anchor"]
        anchor.animation_data_clear()
        anchor.rotation_euler.z = 0
        for obj in list(scene.objects):
            if obj.type in {"LIGHT", "CAMERA"}:
                bpy.data.objects.remove(obj, do_unlink=True)
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(source))
        scene = bpy.context.scene
    if unit in protoss_finishes.MODEL_UNITS and source.stem == unit:
        protoss_finishes.apply_finish(unit, source, scene)
    if unit == "marauder":
        # Use the in-game aiming axes to present the forearm launchers and their bores.
        for side in ("P", "N"):
            mount = scene.objects["Shoulder" + side]
            bore = scene.objects["ArmMuzzle" + side].matrix_world.to_quaternion() @ Vector((1, 0, 0))
            pitch = Quaternion((0, -1, 0), -math.asin(bore.z) * .82)
            pitched = pitch @ bore
            yaw = Quaternion((0, 0, 1), -math.atan2(pitched.y, pitched.x) * .70)
            origin = mount.matrix_world.translation.copy()
            turn = (yaw @ pitch).to_matrix().to_4x4()
            mount.matrix_world = Matrix.Translation(origin) @ turn @ Matrix.Translation(-origin) @ mount.matrix_world
        bpy.context.view_layer.update()
    if unit == "thor":
        # Rack sockets and receiver blend shapes are the same ones as the deployed AA pose.
        for tube in ("InnerP", "InnerN", "OuterP", "OuterN"):
            joint = scene.objects["Cannon" + tube]
            joint.matrix_world = scene.objects["Deploy" + tube].matrix_world.copy()
            mesh = scene.objects["Cannon" + tube + "Mesh"].data
            mesh.shape_keys.key_blocks["StowShroud"].value = 0.0
        bpy.context.view_layer.update()
    if unit == "mortar":
        # Seat the actual hinged parts in the braced artillery pose.
        targets = {obj.name.removeprefix("Deploy"): obj.matrix_world.copy()
                   for obj in scene.objects if obj.name.startswith("Deploy")}
        def seat(parent):
            if parent.name in targets:
                parent.matrix_world = targets[parent.name]
                bpy.context.view_layer.update()
            for child in parent.children:
                seat(child)
        for obj in scene.objects:
            if obj.parent is None:
                seat(obj)
    bpy.context.view_layer.update()
    return scene


def geometry_points(scene):
    graph = bpy.context.evaluated_depsgraph_get()
    arrays = []
    for obj in scene.objects:
        if obj.hide_render or obj.type not in {"MESH", "CURVE"}:
            continue
        evaluated = obj.evaluated_get(graph)
        mesh = evaluated.to_mesh()
        xyz = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
        mesh.vertices.foreach_get("co", xyz)
        transform = np.array(evaluated.matrix_world)
        arrays.append(xyz.reshape(-1, 3) @ transform[:3, :3].T + transform[:3, 3])
        evaluated.to_mesh_clear()
    return np.concatenate(arrays)


def softbox(scene, name, center, offset, diameter, power, color, span):
    data = bpy.data.lights.new(name, "AREA")
    data.shape = "DISK"
    data.size = diameter * span
    data.energy = power * span * span
    data.color = color
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = center + offset * span
    light.rotation_euler = (-offset).to_track_quat("-Z", "Y").to_euler()


def render(unit, temp, output=OUTPUT):
    protoss = unit in protoss_finishes.MODEL_UNITS
    if protoss:
        stem = unit + "_display" if unit in PROTOSS_DISPLAY_MODELS else unit
        source = MODELS / unit / f"{stem}.glb"
        camera_offset = protoss_finishes.view(unit)
    else:
        source, camera_offset = VIEWS[unit]
    scene = model_scene(unit, source)
    points = geometry_points(scene)
    span = float(np.ptp(points, axis=0).max())
    front = Vector(camera_offset).normalized()
    rotation = (-front).to_track_quat("-Z", "Y")
    if unit in PORTRAIT_ROLL:
        rotation = rotation @ Quaternion((0, 0, 1), math.radians(PORTRAIT_ROLL[unit]))
    right = rotation @ Vector((1, 0, 0))
    up = rotation @ Vector((0, 1, 0))

    # Frame the transformed vertices on the sensor, including rifle accessories,
    # rather than the bounding boxes of the rig's empty animation markers.
    def extent(direction):
        projected = points @ np.array(direction)
        return (projected.min() + projected.max()) * .5, np.ptp(projected)
    cx, width = extent(right)
    cy, height = extent(up)
    cz, _ = extent(front)
    center = right * cx + up * cy + front * cz
    data = bpy.data.cameras.new("Recruit camera")
    data.type = "ORTHO"
    data.ortho_scale = max(width, height) / .90
    if unit == "sentry":
        # Balance the trailing fins on the left with the prow on the right.
        data.shift_x = -.033
    camera = bpy.data.objects.new("Recruit camera", data)
    scene.collection.objects.link(camera)
    camera.rotation_euler = rotation.to_euler()
    camera.location = center + front * span * 5.0
    scene.camera = camera

    # Broader light and less frontal fill keep the raised ornament readable
    # across adjoining gold and ivory plates.
    if protoss:
        key_size, key, fill, warm, cool = 1.86, 138, 43, 80, 53
        warm_tint, cool_tint = (.97, .86, .68), (.61, .81, 1.)
    else:
        key_size, key, fill, warm, cool = 1.55, 170, 89, 145, 98
        warm_tint, cool_tint = (1., .68, .39), (.66, .59, 1.)
    softbox(scene, "Cool upper key", center, front*1.65 - right*1.0 + up*1.8,
            key_size, key, (.78, .89, 1.0), span)
    softbox(scene, "Face fill", center, front*1.75 + right*1.5 + up*.20,
            1.70, fill, (.96, .88, .83), span)
    softbox(scene, "Amber edge", center, -front*.88 + right*1.18 + up*1.20,
            .95, warm, warm_tint, span)
    softbox(scene, "Violet edge", center, -front*.68 - right*1.60 + up*.45,
            1.1, cool, cool_tint, span)
    scene.world = bpy.data.worlds.new("Recruit studio")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes["Background"]
    background.inputs["Color"].default_value = (.66, .74, .88, 1)
    background.inputs["Strength"].default_value = .33

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 40
    scene.cycles.seed = 7
    scene.cycles.use_denoising = False
    scene.render.resolution_x = scene.render.resolution_y = 448
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = .68 if unit == "battlecruiser" else 0
    if unit in PROTOSS_DISPLAY_MODELS:
        # Preserve the saturated core colours in the two baked display models.
        scene.view_settings.view_transform = "Khronos PBR Neutral"
        scene.view_settings.look = "None"
        scene.view_settings.exposure = -.48
    scene.render.filepath = str(temp)
    bpy.ops.render.render(write_still=True)
    with Image.open(temp) as image:
        image.resize((256, 256), Image.Resampling.LANCZOS).save(output / f"{unit}.png",
                                                                optimize=True)


if __name__ == "__main__":
    units = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [*VIEWS, *protoss_finishes.MODEL_UNITS]
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temp_dir:
        for unit_id in units:
            render(unit_id, Path(temp_dir) / "portrait.png")
