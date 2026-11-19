"""Split the uploaded one-piece Hellion into six rigid parts in its original coordinates.

Run with Python 3 and NumPy. The original GLB stays authoritative for PBR materials.
Render code shares that material between all parts; the derivative has no images.
"""
import json
import math
import struct
from pathlib import Path

import numpy as np

MODEL_DIR = Path(__file__).resolve().parents[2] / "assets/models/hellbat"
SOURCE = MODEL_DIR / "hellbat.glb"
TARGET = MODEL_DIR / "hellion_rig.glb"
PIVOTS = {
    "Body": (0, 0, 0),
    "Turret": (-0.296, 0.479, 0),
    "WheelFrontLeft": (0.383, 0.106, -0.193),
    "WheelFrontRight": (0.383, 0.106, 0.193),
    "WheelRearLeft": (-0.325, 0.172, -0.241),
    "WheelRearRight": (-0.325, 0.172, 0.241),
}


def load_surface():
    raw = SOURCE.read_bytes()
    json_length = struct.unpack_from("<I", raw, 12)[0]
    doc = json.loads(raw[20:20 + json_length])
    binary = raw[28 + json_length:]
    surface = doc["meshes"][0]["primitives"][0]

    def array(accessor_id):
        accessor = doc["accessors"][accessor_id]
        view = doc["bufferViews"][accessor["bufferView"]]
        dtype = {5125: "<u4", 5126: "<f4"}[accessor["componentType"]]
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[accessor["type"]]
        offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        return np.frombuffer(binary, dtype, accessor["count"] * width, offset).reshape(-1, width)

    vertices = np.hstack([array(surface["attributes"][key])
                          for key in ("POSITION", "NORMAL", "TEXCOORD_0")]).astype(float)
    triangles = array(surface["indices"]).reshape(-1, 3)
    return vertices[triangles]


def cut(polygon, normal, offset):
    """Split a convex polygon, interpolating the source UVs and shading at the seam."""
    distances = polygon[:, :3] @ normal - offset
    if distances.min() >= 0:
        return polygon, None
    if distances.max() <= 0:
        return None, polygon
    inside, outside = [], []
    for i, b in enumerate(polygon):
        a = polygon[i - 1]
        da, db = distances[i - 1], distances[i]
        if da * db < 0:
            shared = a + (b - a) * (da / (da - db))
            inside.append(shared)
            outside.append(shared)
        if db >= 0:
            inside.append(b)
        if db <= 0:
            outside.append(b)
    return np.array(inside), np.array(outside)


def separate(polygons, planes, selector):
    inside, outside = [], []
    for polygon in polygons:
        if not selector(polygon[:, :3]):
            outside.append(polygon)
            continue
        for normal, offset in planes:
            polygon, remainder = cut(polygon, normal, offset)
            if remainder is not None:
                outside.append(remainder)
            if polygon is None:
                break
        if polygon is not None:
            inside.append(polygon)
    return inside, outside


def cut_parts(surface):
    turret, body = separate(surface, [(np.array([0, 1, 0]), 0.479)], lambda _: True)
    parts = {"Turret": turret}
    for name, (cx, cy, cz) in PIVOTS.items():
        if not name.startswith("Wheel"):
            continue
        is_front = name.startswith("WheelFront")
        radius = 0.113 if is_front else 0.145
        inset = 0.116 if is_front else 0.125
        side = 1 if cz > 0 else -1
        # The suspension leans out at the bottom. Clip the bonded axle inboard of
        # the tread, retaining fenders/fuel tanks on the nonrotating chassis.
        planes = [(np.array([0, 0.12, side]), inset + 0.12 * cy)]
        for angle in np.linspace(0, math.tau, 20, endpoint=False):
            inward = np.array([-math.cos(angle), -math.sin(angle), 0])
            planes.append((inward, inward[0] * cx + inward[1] * cy - radius))

        def nearby(xyz):
            return (xyz[:, 0].max() >= cx - radius and xyz[:, 0].min() <= cx + radius
                    and xyz[:, 1].max() >= cy - radius and xyz[:, 1].min() <= cy + radius
                    and (side * xyz[:, 2]).max() > inset - 0.03)
        parts[name], body = separate(body, planes, nearby)
    parts["Body"] = body
    return parts


def triangles_of(polygons):
    return [np.array([poly[0], poly[i], poly[i + 1]])
            for poly in polygons for i in range(1, len(poly) - 1)
            if np.linalg.norm(np.cross(poly[i][:3] - poly[0][:3], poly[i + 1][:3] - poly[0][:3])) > 1e-12]


def close_open_edges(triangles, part):
    # Cap only freshly opened boundaries. Source UV seams duplicate vertices, so
    # compare geometric edges after rounding. Axle/collar faces use the adjacent
    # edge's source UVs and face normals to cover gaps when the pieces articulate.
    edges = {}
    def key(v):
        return tuple(np.round(v[:3], 6))
    for tri in triangles:
        for i in range(3):
            a, b = tri[i], tri[(i + 1) % 3]
            edge = tuple(sorted([key(a), key(b)]))
            if edge in edges:
                del edges[edge]
            else:
                edges[edge] = (a, b)
    for a, b in edges.values():
        midpoint = (a + b) * .5
        if part == "Body":
            # Exterior gaps in the chassis line up with the same articulated pieces.
            nearest = min((tag for tag in PIVOTS if tag != "Body"),
                          key=lambda tag: np.linalg.norm(midpoint[:3] - PIVOTS[tag]))
        else:
            nearest = part
        pivot = np.array(PIVOTS[nearest])
        if nearest.startswith("Wheel"):
            pivot[2] = math.copysign(.125 if "Rear" in nearest else .116, pivot[2])
        tip = midpoint.copy()
        tip[:3] = pivot
        cap = np.array([b, a, tip])
        normal = np.cross(cap[1, :3] - cap[0, :3], cap[2, :3] - cap[0, :3])
        length = np.linalg.norm(normal)
        if length > 1e-10:
            cap[:, 3:6] = normal / length
            triangles.append(cap)


def save(parts):
    binary = bytearray()
    views, accessors, meshes, nodes = [], [], [], []

    def store(array, target, shape, component):
        while len(binary) % 4:
            binary.append(0)
        data = np.ascontiguousarray(array).tobytes()
        views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(data), "target": target})
        binary.extend(data)
        accessor = {"bufferView": len(views) - 1, "componentType": component,
                    "count": len(array), "type": shape}
        if shape == "VEC3":
            accessor.update(min=array.min(axis=0).tolist(), max=array.max(axis=0).tolist())
        accessors.append(accessor)
        return len(accessors) - 1

    for name, pivot in PIVOTS.items():
        tris = triangles_of(parts[name])
        close_open_edges(tris, name)
        vertices, indices = np.unique(np.vstack(tris).astype("<f4"), axis=0, return_inverse=True)
        vertices[:, :3] -= np.asarray(pivot)
        normals = vertices[:, 3:6]
        normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-10)
        attributes = {key: store(vertices[:, s], 34962, shape, 5126)
                      for key, s, shape in [("POSITION", slice(0, 3), "VEC3"),
                                            ("NORMAL", slice(3, 6), "VEC3"),
                                            ("TEXCOORD_0", slice(6, 8), "VEC2")]}
        index = store(indices.reshape(-1).astype("<u2"), 34963, "SCALAR", 5123)
        nodes.append({"name": name, "mesh": len(meshes), "translation": pivot})
        meshes.append({"name": name, "primitives": [{"attributes": attributes, "indices": index}]})
        print(f"{name}: {len(tris)} triangles at {pivot}")
    while len(binary) % 4:
        binary.append(0)
    doc = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}],
           "nodes": nodes, "meshes": meshes, "accessors": accessors, "bufferViews": views,
           "buffers": [{"byteLength": len(binary)}]}
    metadata = json.dumps(doc, separators=(",", ":")).encode()
    metadata += b" " * (-len(metadata) % 4)
    TARGET.write_bytes(struct.pack("<4sIII4s", b"glTF", 2, 28 + len(metadata) + len(binary),
                                   len(metadata), b"JSON") + metadata
                       + struct.pack("<I4s", len(binary), b"BIN\0") + binary)


if __name__ == "__main__":
    save(cut_parts(load_surface()))
