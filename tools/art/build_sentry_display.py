"""Rebuild the coloured, +X-forward Sentry display from all 42 uploaded castings.

Run with: blender -b --python-exit-code 1 -P tools/art/build_sentry_display.py
"""

import io
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.spatial.transform import Rotation

ART = Path(__file__).resolve().parent
sys.path[:0] = [str(ART), str(ART / "recruit_portraits")]
from rigid_glb import Rig, load_surface
from protoss_cores import paint
from protoss_finishes import PALETTE

MODEL = ART.parents[1] / "assets/models/sentry"


def display_pose(triangles, islands):
    posed = triangles.copy()
    globe = triangles[islands == 1, :, :3].reshape(-1, 3)
    tail = (globe.min(axis=0) + globe.max(axis=0)) / 2

    def seat(parts, pivot, translation, tilt):
        selected = np.isin(islands, parts)
        turn = Rotation.from_euler("z", tilt, degrees=True).as_matrix()
        posed[selected, :, :3] = (triangles[selected, :, :3] - pivot) @ turn.T + pivot + translation
        posed[selected, :, 3:] = triangles[selected, :, 3:] @ turn.T

    # The aft counterweight, outer globe and inner core remain concentric.
    aft = np.array([-.145, .143, 0.])
    seat((0, 1, 8), tail, aft, -5)
    # Lay the original dorsal bridge along the line between the elevated aft
    # cradle and the lowered prow. Each fin and every inset moves as a solid.
    seat((4, 5, 9), [.10, .56, 0.], [-.055, .035, 0.], -17)
    seat((2, 3, 12, 13, 14, 15, 16, 17), [0., .42, 0.], [-.067, .057, 0.], -12)
    seat((6, 7, 10, 11), [0., .31, 0.], [-.024, .019, 0.], -13)
    seat((18, 19, 20, 21), [.19, .29, 0.], [.039, -.016, 0.], -9)
    forward = (22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33,
               34, 35, 36, 37, 38, 39, 40, 41)
    seat(forward, [.22, .38, 0.], [.103, -.028, 0.], -14)
    aperture = posed[islands == 41, :, :3].reshape(-1, 3)
    nose = aperture[aperture[:, 0].argmax()].copy()

    # Centre the occupied horizontal footprint so a shared battle pivot can
    # steer this mesh without making the recruitment pose orbit its actor.
    vertices = posed[:, :, :3].reshape(-1, 3)
    low, high = vertices.min(axis=0), vertices.max(axis=0)
    origin = (low + high) / 2
    origin[1] = low[1]
    posed[:, :, :3] -= origin
    return posed, tail + aft - origin, nose - origin


def core_braces(tail):
    """A matched pair of low, tapered spars from the aft cradle to the forward hull."""
    # glTF offsets from the centre of the rear globe, followed by half-width
    # and half-height. Both rails enter solid castings under their end caps.
    stations = np.array([
        [.070, -.145, .108, .018, .015], [.136, -.160, .119, .021, .016],
        [.215, -.159, .130, .020, .015], [.345, -.132, .128, .027, .017],
        [.440, -.126, .116, .030, .019], [.505, -.140, .089, .032, .020],
        [.539, -.153, .080, .025, .015],
    ])
    surfaces = []
    finishes = []
    # Flat shoulders and a shallow outer chine continue the existing gold vanes.
    profile = ((0, 1), (.67, .9), (1, .20), (.8, -.70),
               (0, -1), (-.8, -.70), (-1, .20), (-.67, .90))
    for side in (-1, 1):
        path = stations[:, :3].copy()
        path[:, 2] *= side
        path += tail
        forwards = np.gradient(path, axis=0)
        forwards /= np.linalg.norm(forwards, axis=1, keepdims=True)
        across = np.cross(forwards, [0., 1., 0.])
        across /= np.linalg.norm(across, axis=1, keepdims=True)
        vertical = np.cross(across, forwards)
        rings = np.stack([path + a * stations[:, 3:4] * across + b * stations[:, 4:5] * vertical
                          for a, b in profile], axis=1)
        for k in range(len(path) - 1):
            for j in range(len(profile)):
                next_j = (j + 1) % len(profile)
                quad = rings[[k, k, k + 1, k + 1], [j, next_j, next_j, j]]
                xyz = quad[[0, 1, 2, 0, 2, 3]].reshape(2, 3, 3)
                normal = np.cross(xyz[:, 1] - xyz[:, 0], xyz[:, 2] - xyz[:, 0])
                normal /= np.linalg.norm(normal, axis=1, keepdims=True)
                surfaces.extend(np.concatenate((xyz, np.broadcast_to(normal[:, None], xyz.shape)), axis=-1))
                finish = ("gold", "bronze", "navy", "gunmetal", "gunmetal", "navy", "bronze", "gold")[j]
                finishes.extend((finish, finish))
    return np.array(surfaces), np.array(finishes)


def orb_texture(triangles, islands, size=(256, 128)):
    """Bake the existing portrait's generated-coordinate shader into a portable globe map."""
    import bpy
    from tempfile import TemporaryDirectory
    from protoss_finishes import material

    bpy.ops.wm.read_factory_settings(use_empty=True)
    # An equirectangular sampling plane supplies the original body's Generated
    # coordinates to the same shader that was used on the uploaded unit.
    def blender_xyz(xyz):
        return np.stack((xyz[..., 0], -xyz[..., 2], xyz[..., 1]), axis=-1)

    sphere = triangles[islands == 1, :, :3].reshape(-1, 3)
    low, high = sphere.min(0), sphere.max(0)
    bounds = blender_xyz(triangles[:, :, :3].reshape(-1, 3))
    nu, nv = 96, 48
    u, v = np.meshgrid(np.linspace(0, 1, nu + 1), np.linspace(0, 1, nv + 1))
    theta, phi = 2 * np.pi * u, np.pi * (v - .5)
    directions = np.stack((np.cos(phi) * np.cos(theta), np.sin(phi),
                           np.cos(phi) * np.sin(theta)), axis=-1)
    surface = blender_xyz((low + high) / 2 + directions * (high - low) / 2)
    coords = ((surface - bounds.min(0)) / np.ptp(bounds, axis=0)).reshape(-1, 3)

    uv = np.column_stack((u.ravel(), v.ravel())).astype(np.float32)
    vertices = np.column_stack((uv, np.zeros(len(uv))))
    start = np.arange(nu + 1)[None, :nu] + (nu + 1) * np.arange(nv)[:, None]
    faces = np.stack((start, start + 1, start + nu + 2, start + nu + 1), axis=-1)
    mesh = bpy.data.meshes.new("CoreBakePlane")
    mesh.from_pydata(vertices.tolist(), [], faces.reshape(-1, 4).tolist())
    obj = bpy.data.objects.new("CoreBakePlane", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    mesh.uv_layers.new().data.foreach_set("uv", uv[faces.ravel()].ravel())
    field = mesh.color_attributes.new(name="SourcePosition", type="FLOAT_COLOR", domain="POINT")
    field.data.foreach_set("color", np.column_stack((coords, np.ones(len(coords)))).ravel())

    mat = material("psi_core")
    mesh.materials.append(mat)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    position = nodes.new("ShaderNodeVertexColor")
    position.layer_name = field.name
    noise = next(node for node in nodes if node.type == "TEX_NOISE")
    links.new(position.outputs["Color"], noise.inputs["Vector"])
    ramp = next(node for node in nodes if node.type == "VALTORGB")
    emission = nodes.new("ShaderNodeEmission")
    links.new(ramp.outputs["Color"], emission.inputs["Color"])
    output = next(node for node in nodes if node.type == "OUTPUT_MATERIAL")
    links.new(emission.outputs[0], output.inputs["Surface"])
    target = nodes.new("ShaderNodeTexImage")
    texture = bpy.data.images.new("AftCoreCurrents", width=size[0], height=size[1], alpha=False)
    target.image, nodes.active = texture, target
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    bpy.ops.object.bake(type="EMIT", margin=2)
    with TemporaryDirectory() as temp:
        texture.filepath_raw = str(Path(temp) / "currents.png")
        texture.file_format = "PNG"
        texture.save()
        return Image.open(texture.filepath_raw).convert("RGB")


def atlas(triangles, islands, finish, brace_finish):
    """One draw per actor; all surfaces share embedded base, PBR and emission maps."""
    globe = orb_texture(triangles, islands)
    w, h = globe.size
    # Half a circumference repeats the prime meridian for polar triangles across U=1.
    margin, solids_width = w // 2, 32
    width = w + margin + solids_width
    finish = np.concatenate((finish, brace_finish))
    names = sorted(set(finish) - {"psi_core"})
    base = Image.new("RGB", (width, h))
    base.paste(globe)
    base.paste(globe.crop((0, 0, margin, h)), (w, 0))
    pbr = Image.new("RGB", base.size)
    emission = Image.new("RGB", base.size)

    def emitted(rgb, strength):
        linear = np.where(rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055) ** 2.4)
        linear *= strength
        display = np.where(linear < .0031308, linear * 12.92, 1.055 * linear ** (1 / 2.4) - .055)
        return np.rint(255 * display).astype(np.uint8)

    _, metal, rough, glow = PALETTE["psi_core"]
    pbr.paste((255, round(255 * rough), round(255 * metal)), (0, 0, w + margin, h))
    core = np.asarray(base.crop((0, 0, w + margin, h)), dtype=float) / 255
    emission.paste(Image.fromarray(emitted(core, glow)))

    uv = np.empty((len(finish), 3, 2))
    for index, name in enumerate(names):
        color, metal, rough, glow = PALETTE[name]
        rgb = tuple(bytes.fromhex(color))
        top, bottom = round(index * h / len(names)), round((index + 1) * h / len(names))
        rect = (w + margin, top, width, bottom)
        base.paste(rgb, rect)
        pbr.paste((255, round(255 * rough), round(255 * metal)), rect)
        emission.paste(tuple(emitted(np.array(rgb) / 255, glow)), rect)
        uv[finish == name] = ((width - solids_width / 2) / width, (top + bottom) / (2 * h))

    sphere = triangles[islands == 1, :, :3]
    low, high = sphere.min(axis=(0, 1)), sphere.max(axis=(0, 1))
    direction = (sphere - (low + high) / 2) / ((high - low) / 2)
    direction /= np.linalg.norm(direction, axis=2, keepdims=True)
    longitude = np.arctan2(direction[:, :, 2], direction[:, :, 0]) / (2 * np.pi) % 1
    seam = np.ptp(longitude, axis=1) > .5
    longitude += seam[:, None] & (longitude < .5)
    uv[np.flatnonzero(islands == 1)] = np.stack((longitude * w / width,
                                  .5 - np.arcsin(direction[:, :, 1].clip(-1, 1)) / np.pi), axis=-1)
    return uv, (base, pbr, emission)


def write_display(path, posed, uv, images, tail, nose):
    rig = Rig([], "SentryDisplay")
    channels = np.concatenate((posed, uv), axis=-1).astype("<f4")
    vertex, inverse = np.unique(channels.reshape(-1, 8), axis=0, return_inverse=True)
    assert len(vertex) < 65536
    attributes = {
        "POSITION": rig.accessor(vertex[:, :3], "VEC3", 5126, 34962, True),
        "NORMAL": rig.accessor(vertex[:, 3:6], "VEC3", 5126, 34962),
        "TEXCOORD_0": rig.accessor(vertex[:, 6:], "VEC2", 5126, 34962),
    }
    indices = rig.accessor(inverse.ravel().astype("<u2"), "SCALAR", 5123, 34963)
    descriptors = []
    for name, image in zip(("SentryArmourAndCore", "SentryMetalFinish", "SentryCoreEmission"), images):
        encoded = io.BytesIO()
        image.save(encoded, format="PNG")
        descriptors.append({"name": name, "mimeType": "image/png", "bufferView": rig.view(encoded.getvalue())})
    doc = {"asset": {"version": "2.0", "generator": "FightParty Sentry display builder"},
           "scene": 0, "scenes": [{"nodes": [0]}],
           "nodes": [{"name": "SentryDisplay", "mesh": 0, "children": [1, 2]},
                     {"name": "TailOrb", "translation": tail.tolist()},
                     {"name": "NoseTip", "translation": nose.tolist()}],
           "meshes": [{"name": "SentryCastings", "primitives":
                        [{"attributes": attributes, "indices": indices, "material": 0}]}],
           "materials": [{"name": "SentryArmourAndAftCore", "pbrMetallicRoughness": {
               "baseColorTexture": {"index": 0}, "metallicRoughnessTexture": {"index": 1}},
               "emissiveTexture": {"index": 2}, "emissiveFactor": [1, 1, 1]}],
           "textures": [{"source": i, "sampler": 0} for i in range(3)],
           "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}],
           "images": descriptors, "bufferViews": rig.views, "accessors": rig.accessors,
           "buffers": [{"byteLength": len(rig.blob)}]}
    header = json.dumps(doc, separators=(",", ":")).encode()
    header += b" " * (-len(header) % 4)
    rig.blob.extend(bytes(-len(rig.blob) % 4))
    path.write_bytes(struct.pack("<4sII", b"glTF", 2, 28 + len(header) + len(rig.blob))
                     + struct.pack("<I4s", len(header), b"JSON") + header
                     + struct.pack("<I4s", len(rig.blob), b"BIN\0") + rig.blob)


if __name__ == "__main__":
    triangles, parts = load_surface(MODEL / "sentry.glb", 42)
    posed, tail, nose = display_pose(triangles, parts)
    braces, brace_finish = core_braces(tail)
    posed = np.concatenate((posed, braces))
    uv, images = atlas(triangles, parts, paint("sentry", triangles, parts), brace_finish)
    write_display(MODEL / "sentry_display.glb", posed, uv, images, tail, nose)
