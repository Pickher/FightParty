"""Build articulated game meshes with one embedded palette atlas per GLB. Typical input is an untextured Tripo GLB."""
import json
import struct
import zlib
from pathlib import Path

import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial.transform import Rotation

IDENTITY = np.eye(3)


def labels(points, edges):
    adjacency = coo_matrix((np.ones(len(edges), np.uint8), edges.T), shape=(len(points),) * 2)
    return connected_components(adjacency, directed=False)[1]


def load_surface(path, expected_islands):
    data = Path(path).read_bytes()
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
        raise ValueError(f"{path} topology changed; remap the moving parts")
    return vertices[indices].astype(float), island


def face_normals(triangles):
    n = np.cross(triangles[:, 1, :3] - triangles[:, 0, :3], triangles[:, 2, :3] - triangles[:, 0, :3])
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-14)


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
    """8x8 solid swatches; the nearest-filtered center of each stays exact."""
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
    def __init__(self, materials, name):
        self.materials = materials
        self.name = name
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
        # A calibrated UV per panel compresses the physical finishes into one
        # draw per moving part, including emission and independent metal/roughness.
        uv = np.broadcast_to(((paint[:, None, None] + .5) / len(self.materials)), (len(paint), 3, 1))
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
        factors = [mat["pbrMetallicRoughness"] for mat in self.materials]
        palettes = [
            (self.name + "Paint", srgb([p["baseColorFactor"][:3] for p in factors])),
            (self.name + "Finish", [[1, p["roughnessFactor"], p["metallicFactor"]] for p in factors]),
            (self.name + "Lamps", srgb([mat.get("emissiveFactor", [0, 0, 0]) for mat in self.materials])),
        ]
        images = [{"name": name, "mimeType": "image/png", "bufferView": self.view(palette_png(colors))}
                  for name, colors in palettes]
        material = {"name": self.name + "PanelFinishes", "pbrMetallicRoughness": {
            "baseColorTexture": {"index": 0}, "metallicRoughnessTexture": {"index": 1}},
            "emissiveTexture": {"index": 2}, "emissiveFactor": [1, 1, 1]}
        doc = {"asset": {"version": "2.0", "generator": f"FightParty {self.name} rigid rig"},
               "scene": 0, "scenes": [{"name": self.name + "Rig", "nodes": [0]}],
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
