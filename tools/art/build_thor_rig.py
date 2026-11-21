"""Build the rigid Thor rig from its two uploaded, untextured GLBs (Python 3, NumPy, SciPy)."""
import json
import struct
import zlib
from pathlib import Path

import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial import Delaunay
from scipy.spatial.transform import Rotation

from thor_paint import GUN, MATERIALS, assign_paint

ASSETS = Path(__file__).resolve().parents[2] / "assets/models/thor"
IDENTITY = np.eye(3)


def labels(points, edges):
    adjacency = coo_matrix((np.ones(len(edges), np.uint8), edges.T), shape=(len(points),) * 2)
    return connected_components(adjacency, directed=False)[1]


def load(name, expected_islands):
    data = (ASSETS / name).read_bytes()
    length = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + length])
    blob = data[28 + length:]
    primitive = doc["meshes"][0]["primitives"][0]

    def read(index):
        acc = doc["accessors"][index]
        view = doc["bufferViews"][acc["bufferView"]]
        dtype = {5123: "<u2", 5125: "<u4", 5126: "<f4"}[acc["componentType"]]
        width = {"SCALAR": 1, "VEC3": 3}[acc["type"]]
        return np.frombuffer(blob, dtype, acc["count"] * width,
                             view.get("byteOffset", 0) + acc.get("byteOffset", 0)).reshape(-1, width)

    vertices = np.column_stack([read(primitive["attributes"][attr]) for attr in ("POSITION", "NORMAL")])
    indices = read(primitive["indices"]).reshape(-1, 3)
    geo, index = np.unique(vertices[:, :3], axis=0, return_inverse=True)
    welded = index[indices]
    edges = np.column_stack([welded.ravel(), welded[:, [1, 2, 0]].ravel()])
    island = labels(geo, edges)[welded[:, 0]]
    if len(np.unique(island)) != expected_islands:
        raise ValueError(f"{name} topology changed; remap the moving parts")
    return vertices[indices].astype(float), island


def face_normals(triangles):
    n = np.cross(triangles[:, 1, :3] - triangles[:, 0, :3], triangles[:, 2, :3] - triangles[:, 0, :3])
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-14)


def below_plane(triangle, height):
    points, edge = [], []
    for i, b in enumerate(triangle):
        a = triangle[i - 1]
        if (a[1] < height) != (b[1] < height):
            p = a + (b - a) * ((height - a[1]) / (b[1] - a[1]))
            points.append(p)
            edge.append(p[:3])
        if b[1] <= height:
            points.append(b)
    return [np.array([points[0], points[j], points[j + 1]]) for j in range(1, len(points) - 1)], edge


def open_outer_sockets(shell):
    """Cut only the stalks of the outer guns fused to the ordinary torso.

    Above the seat plane, each entire cannon is an isolated connected region.
    Flood in that half-space so identically high cockpit/shoulder armor survives.
    Close the fixed seats using the actual section contours.
    """
    height = .625
    points, ids = np.unique(shell[:, :, :3].reshape(-1, 3), axis=0, return_inverse=True)
    ids = ids.reshape(-1, 3)
    edges = np.column_stack([ids.ravel(), ids[:, [1, 2, 0]].ravel()])
    above = points[:, 1] > height
    group = labels(points, edges[above[edges].all(1)])
    stalks = np.unique(group[(points[:, 1] > .8) & (np.abs(points[:, 2]) > .18)])
    assert len(stalks) == 2
    cut = np.isin(group[ids], stalks).any(1)
    retained = list(shell[~cut])
    boundaries = {-1: [], 1: []}
    for tri in shell[cut]:
        lower, edge = below_plane(tri, height)
        retained.extend(lower)
        if len(edge) == 2:
            boundaries[1 if edge[0][2] > 0 else -1].append(edge)
    cap = []
    for edges in boundaries.values():
        lines = np.array(edges)[:, :, [0, 2]]
        coords = np.unique(np.round(lines.reshape(-1, 2), 9), axis=0)
        for simplex in Delaunay(coords).simplices:
            tri = coords[simplex]
            x, z = tri.mean(0)
            a, b = lines[:, 0], lines[:, 1]
            crosses = (a[:, 1] > z) != (b[:, 1] > z)
            a, b = a[crosses], b[crosses]
            crossings = a[:, 0] + (z - a[:, 1]) * (b[:, 0] - a[:, 0]) / (b[:, 1] - a[:, 1])
            if np.count_nonzero(crossings > x) % 2:
                face = np.array([[xx, height, zz, 0, 1, 0] for xx, zz in tri])
                if face_normals(face[None])[0, 1] < 0:
                    face = face[::-1]
                cap.append(face)
    return np.array(retained), np.array(cap)


def orient_axis(direction):
    x = np.asarray(direction, dtype=float)
    x /= np.linalg.norm(x)
    z = np.cross(x, [0, 1, 0])
    z /= np.linalg.norm(z)
    return np.column_stack((x, np.cross(z, x), z))


def matrix(origin, basis=IDENTITY):
    out = np.eye(4)
    out[:3, :3], out[:3, 3] = basis, origin
    return out


def palette_png(colors):
    """Six 8x8 solid swatches; the nearest-filtered center of each stays exact."""
    rgb = np.repeat(np.uint8(np.round(np.clip(colors, 0, 1) * 255)), 8, axis=0).tobytes()
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))
    header = struct.pack(">IIBBBBB", 8 * len(colors), 8, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress((b"\0" + rgb) * 8, 9)) + chunk(b"IEND", b""))


def srgb(values):
    linear = np.array(values)
    return np.where(linear < .0031308, 12.92 * linear, 1.055 * linear ** (1 / 2.4) - .055)


class Rig:
    def __init__(self):
        self.blob = bytearray()
        self.views, self.accessors, self.meshes, self.nodes = [], [], [], []
        self.index, self.frames = {}, {}

    def node(self, name, parent, frame):
        local = frame if not parent else np.linalg.inv(self.frames[parent]) @ frame
        value = {"name": name, "translation": local[:3, 3].round(8).tolist()}
        if not np.allclose(local[:3, :3], IDENTITY):
            value["rotation"] = Rotation.from_matrix(local[:3, :3]).as_quat().round(9).tolist()
        index = len(self.nodes)
        self.index[name], self.frames[name] = index, frame
        if parent:
            self.nodes[self.index[parent]].setdefault("children", []).append(index)
        self.nodes.append(value)
        return index

    def view(self, raw, target=None):
        self.blob.extend(bytes(-len(self.blob) % 4))
        item = {"buffer": 0, "byteOffset": len(self.blob), "byteLength": len(raw)}
        if target:
            item["target"] = target
        self.blob.extend(raw)
        self.views.append(item)
        return len(self.views) - 1

    def accessor(self, xyz, width, component, target, bounds=False):
        view = self.view(np.ascontiguousarray(xyz).tobytes(), target)
        acc = {"bufferView": view, "componentType": component, "count": len(xyz), "type": width}
        if bounds:
            acc.update(min=xyz.min(0).tolist(), max=xyz.max(0).tolist())
        self.accessors.append(acc)
        return len(self.accessors) - 1

    def mesh(self, part, triangles, paint, source_frame, stow_delta=None):
        # Geometry can be bound in the deployed frame while the node starts folded.
        local = np.asarray(triangles).copy()
        local[:, :, :3] = (local[:, :, :3] - source_frame[:3, 3]) @ source_frame[:3, :3]
        local[:, :, 3:] = local[:, :, 3:] @ source_frame[:3, :3]
        norm = local[:, :, 3:]
        norm /= np.maximum(np.linalg.norm(norm, axis=2, keepdims=True), 1e-14)
        # A calibrated UV per panel compresses six physical finishes into one
        # draw per moving part, including emission and independent metal/roughness.
        uv = np.broadcast_to(((paint[:, None, None] + .5) / len(MATERIALS)), (len(paint), 3, 1))
        channels = np.concatenate([local, uv], axis=2)
        if stow_delta is not None:
            channels = np.concatenate([channels, stow_delta], axis=2)
        verts, idx = np.unique(channels.reshape(-1, channels.shape[2]).astype("<f4"), axis=0, return_inverse=True)
        assert len(verts) < 65536
        uv = np.column_stack([verts[:, 6], np.full(len(verts), .5, dtype="<f4")])
        attr = {"POSITION": self.accessor(verts[:, :3], "VEC3", 5126, 34962, True),
                "NORMAL": self.accessor(verts[:, 3:6], "VEC3", 5126, 34962),
                "TEXCOORD_0": self.accessor(uv, "VEC2", 5126, 34962)}
        primitive = {"attributes": attr, "material": 0,
                     "indices": self.accessor(idx.ravel().astype("<u2"), "SCALAR", 5123, 34963)}
        mesh = {"name": part, "primitives": [primitive]}
        if stow_delta is not None:
            target = self.accessor(verts[:, 7:], "VEC3", 5126, 34962, True)
            primitive["targets"] = [{"POSITION": target}]
            mesh["weights"] = [1.0]
            mesh["extras"] = {"targetNames": ["StowShroud"]}
        node = self.node(part + "Mesh", part, self.frames[part])
        self.nodes[node]["mesh"] = len(self.meshes)
        self.meshes.append(mesh)

    def write(self, path):
        factors = [mat["pbrMetallicRoughness"] for mat in MATERIALS]
        palettes = [
            ("ThorPaint", srgb([p["baseColorFactor"][:3] for p in factors])),
            ("ThorFinish", [[1, p["roughnessFactor"], p["metallicFactor"]] for p in factors]),
            ("ThorLamps", srgb([mat.get("emissiveFactor", [0, 0, 0]) for mat in MATERIALS])),
        ]
        images = [{"name": name, "mimeType": "image/png", "bufferView": self.view(palette_png(colors))}
                  for name, colors in palettes]
        material = {"name": "ThorPanelFinishes", "pbrMetallicRoughness": {
            "baseColorTexture": {"index": 0}, "metallicRoughnessTexture": {"index": 1}},
            "emissiveTexture": {"index": 2}, "emissiveFactor": [1, 1, 1]}
        doc = {"asset": {"version": "2.0", "generator": "FightParty Thor rigid rig"},
               "scene": 0, "scenes": [{"name": "ThorRig", "nodes": [0]}],
               "nodes": self.nodes, "meshes": self.meshes, "materials": [material], "images": images,
               "textures": [{"source": i, "sampler": 0} for i in range(len(images))],
               "samplers": [{"magFilter": 9728, "minFilter": 9728, "wrapS": 33071, "wrapT": 33071}],
               "buffers": [{"byteLength": len(self.blob)}],
               "bufferViews": self.views, "accessors": self.accessors}
        js = json.dumps(doc, ensure_ascii=True, separators=(",", ":")).encode()
        js += b" " * (-len(js) % 4)
        self.blob.extend(bytes(-len(self.blob) % 4))
        size = 28 + len(js) + len(self.blob)
        path.write_bytes(struct.pack("<4sII", b"glTF", 2, size) + struct.pack("<I4s", len(js), b"JSON") + js
                         + struct.pack("<I4s", len(self.blob), b"BIN\0") + self.blob)


def colors(part, tris, islands):
    return assign_paint(part, tris[:, :, :3].mean(1), face_normals(tris), islands)


def build():
    ordinary, ids = load("thor.glb", 41)
    artillery, alt_ids = load("thor_rocket.glb", 29)
    rig = Rig()
    rig.node("Thor", None, matrix([0, 0, 0]))
    rig.node("Pelvis", "Thor", matrix([-.020, .380, 0]))
    rig.node("Trunk", "Pelvis", matrix([-.070, .481, 0]))
    regions = {"Pelvis": [17], "Trunk": [9, 10, 24, 25, 26, 29]}
    trunk, caps = open_outer_sockets(ordinary[ids == 0])
    for suffix, sign in [("P", 1), ("N", -1)]:
        p = sign == 1
        for key, parent, pos, parts in [
            ("Hip", "Pelvis", (-.071, .387, .120), [19, 14, 15, 23] if p else [18, 13, 16, 22]),
            ("Knee", "Hip" + suffix, (-.111, .236, .138),
             [5, 8, 12, 27, 31, 35, 38, 39] if p else [6, 7, 11, 28, 30, 34, 36, 37, 40]),
            ("Ankle", "Knee" + suffix, (.087, .067, .183), [32] if p else [33]),
            ("Shoulder", "Trunk", (-.080, .646, .285), [20] if p else [21]),
        ]:
            name = key + suffix
            rig.node(name, parent, matrix([pos[0], pos[1], sign * pos[2]]))
            regions[name] = parts
        arm_basis = orient_axis([.837, .484, sign * .253])
        for key, pos in [("ArmMuzzle", (.278, .629, .418)), ("ArmMuzzleLower", (.315, .554, .439))]:
            rig.node(key + suffix, "Shoulder" + suffix, matrix([pos[0], pos[1], sign * pos[2]], arm_basis))

    # Keep the two source pairs of support clevises underneath the four
    # raised trunnions. Both imported poses share the same stationary chassis.
    register = np.array([0, .075, 0])
    clevis = artillery[np.isin(alt_ids, [0, 1, 13, 14])].copy()
    clevis[:, :, :3] += register
    for name, group in regions.items():
        choose = np.isin(ids, group)
        triangles = ordinary[choose]
        paint = colors(name, triangles, ids[choose])
        if name == "Trunk":
            paint = np.r_[paint, colors(name, trunk, np.zeros(len(trunk), int)), np.full(len(caps) + len(clevis), GUN)]
            triangles = np.concatenate([triangles, trunk, caps, clevis])
        rig.mesh(name, triangles, paint, rig.frames[name])

    # Each uploaded deployed tube retains its receiver, muzzle and associated
    # shield. Register the braced second pose against the standing torso. Use
    # the true breech trunnion in that pose, then place the folded muzzles at
    # the measured four ordinary-model exit ports.
    for suffix, sign in [("P", 1), ("N", -1)]:
        p = sign == 1
        for kind in ["Inner", "Outer"]:
            inner = kind == "Inner"
            if inner:
                barrel, cover = (5, 3) if p else (6, 4)
                pivot = np.array([-.187, .715, .148 if p else -.151])
                muzzle = np.array([.263, .826, .125 if p else -.139])
                closed_tip = np.array([-.157, .916, .125 if p else -.135])
                closed_dir = [.185, .982, -.018 * sign]
            else:
                barrel, cover = (11, 10) if p else (12, 9)
                pivot = np.array([-.151, .648, .258 if p else -.261])
                muzzle = np.array([.333, .780, .227 if p else -.231])
                closed_tip = np.array([-.150, .849, .226 if p else -.225])
                closed_dir = [.197, .979, -.037 * sign]
            axis = orient_axis(muzzle - pivot)
            folded_axis = orient_axis(closed_dir)
            port = axis.T @ (muzzle - pivot)
            folded_pivot = closed_tip - folded_axis @ port
            name = kind + suffix
            bind = matrix(pivot, axis)
            opened = matrix(pivot + register, axis)
            folded = matrix(folded_pivot, folded_axis)
            rig.node("Cannon" + name, "Trunk", folded)
            rig.node("Deploy" + name, "Trunk", opened)
            rig.node("Muzzle" + name, "Cannon" + name, matrix(closed_tip, folded_axis))
            use = np.isin(alt_ids, [barrel, cover])
            tris = artillery[use]
            paint = colors("Cannon" + name, tris, alt_ids[use])
            # Compress the long sleeve between the receiver and first forward
            # collar while folding. The distal bore, sight and muzzle sockets
            # stay in register. The outer covers nest against the rear armor.
            axial = (tris[:, :, :3] - pivot) @ axis[:, 0]
            retract = .093 if inner else .118
            along = np.clip((.30 - axial) / .20, 0, 1)
            stow = np.zeros(tris[:, :, :3].shape)
            stow[:, :, 0] = along * retract
            shield = alt_ids[use] == cover
            stow[shield, :, 0] = retract
            stow[shield, :, 1] = -.054 if inner else -.083
            rig.mesh("Cannon" + name, tris, paint, bind, stow)
    rig.write(ASSETS / "thor_rig.glb")


if __name__ == "__main__":
    build()
