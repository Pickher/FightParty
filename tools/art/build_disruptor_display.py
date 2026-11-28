"""Rebuild the Disruptor's +X-forward display GLB with Python, NumPy, SciPy and Pillow."""
import io
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import map_coordinates
from scipy.spatial import cKDTree
from scipy.spatial.transform import Rotation

from recruit_portraits.protoss_cores import paint
from rigid_glb import Rig, load_surface

DIRECTORY = Path(__file__).resolve().parents[2] / "assets/models/disruptor"
CENTER = np.array([-.004, .332, -.012])
SHIELD_RADIUS = .202
SUN_RADIUS = .119
PERIOD = 2.4
TAU = 2 * np.pi


def normalized(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)


def sphere(longitudes, latitudes, radius):
    lon, lat = np.meshgrid(np.linspace(0, TAU, longitudes + 1), np.linspace(0, np.pi, latitudes + 1))
    normal = np.stack((np.cos(lon) * np.sin(lat), np.cos(lat), np.sin(lon) * np.sin(lat)), axis=-1)
    uv = np.stack((lon / TAU, lat / np.pi), axis=-1)
    i = np.arange(latitudes)[:, None] * (longitudes + 1) + np.arange(longitudes)
    cells = np.stack((i, i + 1, i + longitudes + 1, i + 1, i + longitudes + 2, i + longitudes + 1), -1)
    indices = cells.reshape(-1, 3)
    # Degenerate rows at the poles have no area.
    pos = normal.reshape(-1, 3)
    faces = pos[indices]
    area = np.linalg.norm(np.cross(faces[:, 1] - faces[:, 0], faces[:, 2] - faces[:, 0]), axis=1)
    return pos * radius, pos, uv.reshape(-1, 2), indices[area > 1e-7]


def photosphere():
    """Bake an equirectangular emission map from a seamless 3D convection field."""
    width, height = 512, 256
    lon, lat = np.meshgrid((np.arange(width) + .5) * TAU / width,
                           (np.arange(height) + .5) * np.pi / height)
    p = np.stack((np.sin(lat) * np.cos(lon), np.cos(lat), np.sin(lat) * np.sin(lon)), -1)
    rng = np.random.default_rng(2719)
    grid = rng.uniform(-1, 1, (32, 32, 32))

    def field(v, frequency, offset):
        return map_coordinates(grid, np.moveaxis(v * frequency + offset, -1, 0),
                               order=1, mode="grid-wrap")

    warp = np.stack([field(p, 2.7, shift) for shift in (2.4, 11.2, 23.8)], -1)
    domain = normalized(p + .19 * warp)
    seeds = normalized(rng.normal(size=(116, 3)))
    dist, _ = cKDTree(seeds).query(domain.reshape(-1, 3), k=2)
    borders = (dist[:, 1] - dist[:, 0]).reshape(height, width)
    granules = .30 * field(domain, 8, 3.7) + .12 * field(p, 22, 5.8)
    curls = np.sin(9 * domain[..., 0] + 5 * domain[..., 1] + 6 * field(domain, 2.2, 4.2))
    value = granules + .45 * np.exp(-borders / .040) + .27 * np.exp(-(curls / .25)**2) + .23 * field(p, 2.6, 14.3)
    # Preserve deep orange convection pockets even under the game's bright
    # environment light. Only the hottest few percent of the filaments go white.
    colors = [(108, 19, 2), (163, 31, 1), (219, 58, 1), (249, 101, 3),
              (255, 166, 14), (255, 224, 74), (255, 243, 167), (255, 250, 204)]
    stops = list(zip(np.quantile(value, (0, .11, .29, .47, .68, .86, .965, 1)), colors))
    return color_ramp(value, stops)


def color_ramp(values, stops):
    t, colors = zip(*stops)
    return np.uint8(np.rint(np.stack([np.interp(values, t, ch) for ch in zip(*colors)], -1)))


def tube(path, widths, brightness, sides=6):
    tangent = normalized(np.gradient(path, axis=0))
    # Carry a cross-section along the curve without spinning at vertical tangents.
    normal = np.empty_like(path)
    normal[0] = normalized(np.cross(tangent[0], np.eye(3)[np.argmin(abs(tangent[0]))]))
    for i in range(1, len(path)):
        normal[i] = normalized(normal[i - 1] - np.dot(normal[i - 1], tangent[i]) * tangent[i])
    angle = np.arange(sides) * TAU / sides
    cross = normal[:, None] * np.cos(angle)[None, :, None]
    cross += np.cross(tangent, normal)[:, None] * np.sin(angle)[None, :, None]
    verts = path[:, None] + widths[:, None, None] * cross
    # The outer edge cools before the hottest part along the axis of a filament.
    u = np.clip(brightness[:, None] + .085 * np.cos(angle), .01, .99)
    uv = np.stack((u, np.full_like(u, .5)), -1)
    i = np.arange(len(path) - 1)[:, None] * sides + np.arange(sides)
    j = (i // sides) * sides + (i + 1) % sides
    faces = np.stack((i, j, i + sides, j, j + sides, i + sides), -1)
    return verts.reshape(-1, 3), cross.reshape(-1, 3), uv.reshape(-1, 2), faces.reshape(-1, 3)


def combine(parts):
    vertices, normals, uv, faces = [], [], [], []
    offset = 0
    for v, n, tex, triangles in parts:
        vertices.append(v)
        normals.append(n)
        uv.append(tex)
        faces.append(triangles + offset)
        offset += len(v)
    return tuple(np.concatenate(group) for group in (vertices, normals, uv, faces))


# glTF-space directions to the transfer slots around the four original floating vanes.
STREAMS = np.array([[.79, .26, -.56], [-.79, .39, -.42], [.26, -.31, -.91],
                    [-.62, -.33, .72], [.73, .49, .48], [.19, .81, .56]])


def stream(index, phase):
    axis = normalized(STREAMS[index])
    side = normalized(np.cross([0, 1, 0], axis))
    up = np.cross(axis, side)
    bend = (1 if index % 2 else -1) * (.41 * (1 - phase) + .41 * np.sin(TAU * (phase * .80 + .10)))
    lift = .13 * np.sin(TAU * (phase * .85 + index * .21))
    direction = normalized(axis + bend[..., None] * side + lift[..., None] * up)
    return direction * (SUN_RADIUS * .97 + (.16 if index % 3 else .174) * phase)[..., None]


class Display(Rig):
    def __init__(self):
        super().__init__([], "Disruptor")
        self.nodes = [{"name": "DisruptorDisplay", "children": []}]
        self.images, self.textures, self.channels, self.tracks = [], [], [], []
        self.times = self.accessor(np.linspace(0, PERIOD, 49, dtype="<f4"), "SCALAR", 5126, None)
        self.accessors[-1].update(min=[0.0], max=[PERIOD])

    def texture(self, name, rgb):
        image = io.BytesIO()
        Image.fromarray(rgb).save(image, format="PNG", optimize=True)
        self.images.append({"name": name, "mimeType": "image/png", "bufferView": self.view(image.getvalue())})
        self.textures.append({"source": len(self.images) - 1, "sampler": 0})
        return len(self.textures) - 1

    def add(self, name, material, geometry, parent=0, center=None):
        v, n, uv, faces = geometry
        attrs = {"POSITION": self.accessor(v.astype("<f4"), "VEC3", 5126, 34962, True),
                 "NORMAL": self.accessor(n.astype("<f4"), "VEC3", 5126, 34962)}
        attrs["TEXCOORD_0"] = self.accessor(uv.astype("<f4"), "VEC2", 5126, 34962)
        indices = self.accessor(faces.astype("<u2").ravel(), "SCALAR", 5123, 34963)
        prim = {"attributes": attrs, "indices": indices, "material": material, "mode": 4}
        self.meshes.append({"name": name, "primitives": [prim]})
        node = {"name": name, "mesh": len(self.meshes) - 1}
        if center is not None:
            node["translation"] = list(center)
        self.nodes.append(node)
        self.nodes[parent].setdefault("children", []).append(len(self.nodes) - 1)
        return len(self.nodes) - 1

    def animate(self, node, path, values):
        values = np.asarray(values, dtype="<f4")
        # q and -q denote the same orientation. Preserve the hemisphere of each
        # successive key so a full turn takes the short arc through each quarter.
        if path != "rotation":
            values[-1] = values[0]
        accessor = self.accessor(values, "VEC4" if path == "rotation" else "VEC3", 5126, None)
        self.nodes[node][path] = values[0].tolist()
        self.channels.append({"sampler": len(self.tracks), "target": {"node": node, "path": path}})
        self.tracks.append({"input": self.times, "output": accessor, "interpolation": "LINEAR"})

    def save(self, path):
        doc = {"asset": {"version": "2.0", "generator": "FightParty Disruptor display"},
               "scene": 0, "scenes": [{"name": "DisruptorDisplay", "nodes": [0]}], "nodes": self.nodes,
               "meshes": self.meshes, "materials": self.materials, "images": self.images, "textures": self.textures,
               "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 33071}],
               "extensionsUsed": ["KHR_materials_emissive_strength"],
               # Godot strips its -loop import hint and exposes the looping clip as SolarIdle.
               "animations": [{"name": "SolarIdle-loop", "samplers": self.tracks, "channels": self.channels}],
               "bufferViews": self.views, "accessors": self.accessors, "buffers": [{"byteLength": len(self.blob)}]}
        data = json.dumps(doc, separators=(",", ":")).encode("utf8")
        data += b" " * (-len(data) % 4)
        self.blob.extend(b"\0" * (-len(self.blob) % 4))
        path.write_bytes(struct.pack("<4sII", b"glTF", 2, 28 + len(data) + len(self.blob))
                         + struct.pack("<I4s", len(data), b"JSON") + data
                         + struct.pack("<I4s", len(self.blob), b"BIN\0") + self.blob)


def radiant(name, image=None, strength=1., color=(1., 1., 1.), diffuse=1.):
    pbr = {"metallicFactor": 0., "roughnessFactor": .82, "baseColorFactor": [*[c * diffuse for c in color], 1.]}
    m = {"name": name, "pbrMetallicRoughness": pbr, "emissiveFactor": list(color),
         "extensions": {"KHR_materials_emissive_strength": {"emissiveStrength": strength}}}
    if image is not None:
        pbr["baseColorTexture"] = {"index": image}
        m["emissiveTexture"] = {"index": image}
    return m


def build():
    display = Display()
    fire_texture = display.texture("Solar granulation", photosphere())
    spectrum = color_ramp(np.linspace(0, 1, 64)[None, :],
                          [(0, (145, 27, 4)), (.27, (233, 57, 4)), (.52, (255, 112, 10)),
                           (.77, (255, 188, 51)), (1, (255, 246, 180))])
    flow_texture = display.texture("Coronal temperature", spectrum)
    swatches = np.uint8([(213, 168, 90), (146, 96, 53), (67, 75, 88), (235, 196, 119)])
    atlas = np.repeat(np.repeat(swatches[None, :, :], 8, axis=0), 8, axis=1)
    alloy_texture = display.texture("Cast alloys", atlas)
    display.materials = [
        {"name": "Suspended antique gold casting", "pbrMetallicRoughness": {
            "baseColorTexture": {"index": alloy_texture}, "metallicFactor": .61, "roughnessFactor": .42}},
        radiant("Photosphere", fire_texture, .99, (1., .89, .55), .42),
        {"name": "Shield | single front surface", "alphaMode": "BLEND", "doubleSided": False,
         "pbrMetallicRoughness": {"baseColorFactor": [.14, .47, .56, .085], "metallicFactor": .16, "roughnessFactor": .27}},
        radiant("Shield boundary", strength=.48, color=(.29, .69, .73)),
        radiant("Coronal stream", flow_texture, .77, (1., .77, .31), .46),
        radiant("Moving heat front", strength=1.1, color=(1., .49, .07), diffuse=.4),
    ]
    # Keep the four original floating castings down to their surface normals
    # and ornament. Sample finishes through an sRGB palette so Godot
    # Compatibility and Blender apply the same colour conversion.
    tri, islands = load_surface(DIRECTORY / "disruptor.glb", 16)
    keep = np.isin(islands, (0, 1, 2, 15))
    finish = paint("disruptor", tri, islands)[keep]
    color_ids = {"gold": 0, "bronze": 1, "gunmetal": 2}
    u = (np.array([color_ids[name] for name in finish]) + .5) / len(swatches)
    uv = np.stack((u, np.full_like(u, .5)), axis=1)
    rows = np.concatenate((tri[keep], np.repeat(uv[:, None, :], 3, axis=1)), -1)
    vertices, indices = np.unique(rows.reshape(-1, 8).astype("f4"), axis=0, return_inverse=True)
    frame = [(vertices[:, :3], vertices[:, 3:6], vertices[:, 6:8], indices.reshape(-1, 3))]
    # The source's thick gimbals crossed the external front window and
    # obscured the sun. Rebuild them as open, bevelled bronze arms on the same
    # two mounting planes, with raised gold edges following the back of the dome.
    for side in (-1, 1):
        t = np.linspace(0, 1, 46)
        angle = .86 + .21 * side + (TAU - 2.00) * t
        curve = np.column_stack((side * (.115 + .012 * np.sin(angle)),
                                 .318 + .177 * np.sin(angle), -.009 - .184 * np.cos(angle)))
        radius = .0023 + .0105 * np.sin(np.pi * t)**.44
        for slot, offset, width in [(1, 0, 1.), (3, .008, .34)]:
            v, n, _, f = tube(curve + [side * offset, 0, 0], radius * width, t, 7)
            frame.append((v, n, np.tile([(slot + .5) / len(swatches), .5], (len(v), 1)), f))
    display.add("FloatingArmour", 0, combine(frame))
    sun = display.add("SolarCore", 1, sphere(40, 24, SUN_RADIUS), center=CENTER)
    display.add("Shield", 2, sphere(40, 20, SHIELD_RADIUS), center=CENTER)

    # Sparse meniscus marks give the clear, single-layer shield a contour even
    # in unlit renderers without requiring a second overlapping alpha surface.
    arcs = []
    for normal, arcspec in [((.35, 1, .25), [(.18, 1.68), (2.43, 4.47), (5.0, 5.72)]),
                            ((.76, .28, -.66), [(.62, 1.72), (2.4, 3.12), (4.52, 5.98)])]:
        axis = normalized(np.array(normal))
        x = normalized(np.cross(axis, [0, 1, 0]))
        y = np.cross(axis, x)
        for lo, hi in arcspec:
            t = np.linspace(0, 1, 20)
            a = lo + (hi - lo) * t
            path = (np.cos(a)[:, None] * x + np.sin(a)[:, None] * y) * (SHIELD_RADIUS + .0009)
            arcs.append(tube(path, .00025 + .0019 * np.sin(np.pi * t)**.42, np.ones_like(t) * .7, 5))
    display.add("ShieldMeniscus", 3, combine(arcs), center=CENTER)

    time = np.linspace(0, 1, 49)
    spin = Rotation.from_rotvec(TAU * time[:, None] * normalized(np.array([.15, 1., -.2]))).as_quat()
    display.animate(sun, "rotation", spin)
    groups = []
    for group in range(2):
        paths = []
        for idx in range(group, len(STREAMS), 2):
            t = np.linspace(0, 1, 31)
            path = stream(idx, t)
            # Only two broad plumes leave the shell. Shorter secondary
            # tendrils follow them instead of radiating as a regular starburst.
            size = (1.7, 1.03, .81, .58, 1.21, .64)[idx]
            width = size * (.004 + .0075 * np.sin(np.pi * t)**.72) * (1 - .97 * t**1.45)
            paths.append(tube(path, width, .78 - .65 * t + .085 * np.sin(TAU * t + idx)))
            # A standing prominence curls back into a different point on the
            # photosphere. The larger loops keep a hot orange arch at UI scale.
            axis = normalized(STREAMS[idx])
            tangent = normalized(np.cross(axis, [.31, 1., .07]))
            foot = normalized(axis + (.95 * t[:, None] - .475) * tangent)
            height = (.072, .049, .032, .057, .067, .040)[idx]
            arch = np.sin(np.pi * t)
            curve = foot * (SUN_RADIUS + height * arch**.82)[:, None]
            paths.append(tube(curve, .002 + size * .0070 * arch**.7, .37 + .22 * arch))
            if idx in (0, 3, 4):
                # Adjacent cooler threads make irregular loops and open gaps,
                # as in a solar prominence, instead of a circular fire outline.
                curl = normalized(foot + (.095 * arch)[:, None] * np.cross(axis, tangent))
                edge = curl * (SUN_RADIUS + (.011 + height) * arch**.86)[:, None]
                paths.append(tube(edge, .0006 + .0026 * arch, .63 - .17 * arch))
        node = display.add("HeatFilaments" + "AB"[group], 4, combine(paths), center=CENTER)
        groups.append(node)
        phase = TAU * time + group * 1.7
        scale = np.stack([1 + .032 * np.sin(phase), 1 + .045 * np.sin(phase + .7), 1 + .027 * np.sin(phase + 1.2)], 1)
        display.animate(node, "scale", scale)
    # Heat packets travel outward on three different continuously fed streams.
    # The tail collapses before its path resets inside the sun. At least two
    # streams remain active while a third packet is restarting.
    for idx, shift in [(0, 0.), (1, 1 / 3), (4, 2 / 3)]:
        progress = np.mod(time + shift, 1.)
        pulse = display.add("HeatPacket" + str(idx), 5, sphere(8, 6, .0082), parent=groups[idx % 2])
        display.animate(pulse, "translation", stream(idx, progress))
        taper = np.clip(np.minimum(progress / .115, (1 - progress) / .14), 0, 1)
        # A subpixel ember keeps Godot’s imported basis invertible at reset.
        scale = .004 + .996 * taper * taper * (3 - 2 * taper)
        display.animate(pulse, "scale", np.repeat(scale[:, None], 3, axis=1))
    display.save(DIRECTORY / "disruptor_display.glb")


if __name__ == "__main__":
    build()
