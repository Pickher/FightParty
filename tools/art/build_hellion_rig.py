"""Split the uploaded one-piece Hellion into six rigid parts in its original coordinates.

Run with Python 3, NumPy and Pillow. The original GLB stays authoritative for PBR materials.
Render code shares that material between all parts; the wreck adds a small, original scorched-metal tile for the torn inner structure.
"""
from collections import defaultdict
import io
import json
import math
import struct
from pathlib import Path

import numpy as np

MODEL_DIR = Path(__file__).resolve().parents[2] / "assets/models/hellbat"
SOURCE = MODEL_DIR / "hellbat.glb"
TARGET = MODEL_DIR / "hellion_rig.glb"
WRECK = MODEL_DIR / "hellion_wreck.glb"
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


def cut_at_distances(polygon, distances):
    """Split a convex polygon, interpolating the source UVs and shading at the seam."""
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
            polygon, remainder = cut_at_distances(polygon, polygon[:, :3] @ normal - offset)
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


def write_glb(target, groups, materials=None, interior_image=None):
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

    for name, pivot, surfaces in groups:
        primitives = []
        for tris, material in surfaces:
            records = np.vstack(tris).astype("<f4")
            if material is not None:
                # glTF generates flat normals for the untextured, torn inner metal.
                records = records[:, [0, 1, 2, 6, 7]]
            vertices, indices = np.unique(records, axis=0, return_inverse=True)
            vertices[:, :3] -= np.asarray(pivot)
            attributes = {"POSITION": store(vertices[:, :3], 34962, "VEC3", 5126)}
            if material is None:
                normals = vertices[:, 3:6]
                normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-10)
                attributes["NORMAL"] = store(normals, 34962, "VEC3", 5126)
                attributes["TEXCOORD_0"] = store(vertices[:, 6:8], 34962, "VEC2", 5126)
            else:
                attributes["TEXCOORD_0"] = store(vertices[:, 3:5], 34962, "VEC2", 5126)
            index = store(indices.reshape(-1).astype("<u2"), 34963, "SCALAR", 5123)
            primitive = {"attributes": attributes, "indices": index}
            if material is not None:
                primitive["material"] = material
            primitives.append(primitive)
        nodes.append({"name": name, "mesh": len(meshes), "translation": pivot})
        meshes.append({"name": name, "primitives": primitives})
        print(f"{name}: {sum(len(tris) for tris, _ in surfaces)} triangles at {pivot}")
    while len(binary) % 4:
        binary.append(0)
    if interior_image is not None:
        views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(interior_image)})
        binary.extend(interior_image)
        binary.extend(b"\0" * (-len(binary) % 4))
    doc = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}],
           "nodes": nodes, "meshes": meshes, "accessors": accessors, "bufferViews": views,
           "buffers": [{"byteLength": len(binary)}]}
    if materials:
        doc["materials"] = materials
    if interior_image is not None:
        doc["textures"] = [{"source": 0}]
        doc["images"] = [{"name": "torn_gunmetal", "mimeType": "image/png", "bufferView": len(views) - 1}]
    metadata = json.dumps(doc, separators=(",", ":")).encode()
    metadata += b" " * (-len(metadata) % 4)
    target.write_bytes(struct.pack("<4sIII4s", b"glTF", 2, 28 + len(metadata) + len(binary),
                                   len(metadata), b"JSON") + metadata
                       + struct.pack("<I4s", len(binary), b"BIN\0") + binary)


# Keep the outer paint and UV islands from the live rig. Each fracture snakes
# across a different panel junction; rear tanks stay with the engine, the gold
# canopy with the cabin and the front suspension with the cowling.
WRECK_PIVOTS = {
    "NoseChunk": (0.278, 0.185, 0.0),
    "CockpitChunk": (0.023, 0.243, 0.0),
    "EngineChunk": (-0.260, 0.228, 0.0),
}


def fracture(triangles, station, lean, skew):
    """Open the fracture along authored triangle edges, retaining the original UVs."""
    front, back = [], []
    edge_sides = {}
    segments = []
    for triangle in triangles:
        x, y, z = triangle[:, :3].mean(axis=0)
        tear = station + lean * (y - .24) + skew * z + .013 * math.sin(34 * z + 11 * y)
        forward = x >= tear
        (front if forward else back).append(triangle)
        for i, a in enumerate(triangle):
            b = triangle[(i + 1) % 3]
            edge = tuple(sorted((tuple(a[:3].round(6)), tuple(b[:3].round(6)))))
            previous = edge_sides.pop(edge, None)
            if previous is None:
                edge_sides[edge] = forward
            elif previous != forward:
                segments.append((a, b))
    return front, back, segments


def torn_steel(segments, outward):
    """Build recessed, folded metal from each continuous rim independently."""
    positions, neighbors = {}, defaultdict(set)
    for a, b in segments:
        qa, qb = (tuple(v[:3].round(6)) for v in (a, b))
        if qa == qb:
            continue
        positions[qa], positions[qb] = a, b
        neighbors[qa].add(qb)
        neighbors[qb].add(qa)
    surface = []
    for start in neighbors:
        if not neighbors[start]:
            continue
        stack, edges, rim = [start], [], set()
        while stack:
            node = stack.pop()
            rim.add(node)
            for other in sorted(neighbors[node]):
                edges.append((positions[node], positions[other]))
                neighbors[other].discard(node)
                stack.append(other)
            neighbors[node].clear()
        center = np.mean([positions[k] for k in sorted(rim)], axis=0)
        radius = np.max([np.linalg.norm(positions[k][:3] - center[:3]) for k in rim])
        recess = min(.017, .20 * radius)
        center[0] -= outward * recess
        for a, b in edges:
            tri = np.array([a, b, center])
            normal = np.cross(tri[1, :3] - tri[0, :3], tri[2, :3] - tri[0, :3])
            if np.linalg.norm(normal) < 1e-12:
                continue
            if normal[0] * outward < 0:
                tri = tri[[0, 2, 1]]
            surface.append(tri)
    return surface


def coarse_socket_caps(triangles):
    """Weld only the synthetic wheel-well/collar infill. Exterior paint stays exact."""
    if not triangles:
        return []
    positions = np.stack(triangles)[:, :, :3].reshape(-1, 3)
    keys, inverse = np.unique(np.round(positions / .065), axis=0, return_inverse=True)
    merged = np.zeros_like(keys)
    np.add.at(merged, inverse, positions)
    merged /= np.bincount(inverse)[:, None]
    index = inverse.reshape(-1, 3)
    output = []
    seen = set()
    for i, row in enumerate(index):
        signature = tuple(sorted(row))
        if len(set(signature)) != 3 or signature in seen:
            continue
        seen.add(signature)
        tri = triangles[i].copy()
        tri[:, :3] = merged[row]
        output.append(tri)
    return output


def section_ribs(station, slope, outward):
    """A pair of bent hat-section frame rails stands proud of each recessed cavity."""
    ribs = []
    for sign in (-1, 1):
        ring = []
        for y, lateral in ((.145, .078), (.210, .056), (.286, .101)):
            z = sign * lateral
            x = station + slope * (y - .24) + (.14 if station > 0 else -.16) * z
            # Flange / crushed crown / flange, clipped back from the painted skin.
            ring.append([np.array([x + outward * protrusion, y, z + dz, 0., 0., 0., 0., 0.])
                         for dz, protrusion in ((-.010, -.005), (-.003, .009), (.011, .001))])
        for lo, hi in zip(ring, ring[1:]):
            for i in (0, 1):
                ribs.extend(np.array(t) for t in ((lo[i], hi[i], hi[i+1]), (lo[i], hi[i+1], lo[i+1])))
    return ribs


def inner_plate_uv(triangles, cut_face=False, rib=False):
    """Project inner faces in local metres, independent of the painted UV islands."""
    for tri in triangles:
        p = tri[:, :3]
        normal = np.cross(p[1] - p[0], p[2] - p[0])
        axis = 0 if cut_face else np.argmax(abs(normal))
        plane = ((2, 1), (0, 2), (0, 1))[axis]
        tri[:, 6:8] = p[:, plane] / .39 + np.array([.51, .32])
        if rib:
            # Small dedicated strip of clean exposed steel at the atlas edge.
            tri[:, 6] = .960 + .012 * np.sin(tri[:, 6])
    return triangles


def interior_plate():
    """Small authored cross-section tile: black cavities, crimped radiator and conduits."""
    from PIL import Image, ImageDraw

    scale = 2
    img = Image.new("RGB", (128 * scale, 128 * scale), (52, 61, 64))
    draw = ImageDraw.Draw(img)
    def line(points, color, width=1):
        draw.line([(round(x * scale), round(y * scale)) for x, y in points],
                  fill=color, width=width * scale)
    def rect(bounds, color):
        draw.rectangle([v*scale for v in bounds], fill=color)
    def polygon(points, color):
        draw.polygon([(x*scale, y*scale) for x,y in points], fill=color)

    # Pressed, bevelled bulkhead with an open bay exposing longitudinal rails.
    polygon([(5,10),(49,8),(53,14),(50,57),(9,60),(3,52)],(100,109,111))
    polygon([(6,13),(48,11),(50,16),(47,54),(10,56),(6,50)],(18,24,28))
    for y in range(18,52,8):
        line([(10,y+2),(44,y)],(43,51,56),3)
        line([(10,y),(44,y-2)],(85,94,95))
    rect((62,7,118,50),(14,19,22))
    for x in range(66,115,8):
        line([(x,11),(x+1,43)],(73,78,80),3)
        line([(x,12),(x+1,40)],(124,123,111))
    # Folded transverse beam. Its chipped leading edge stays light against a dark bay.
    line([(-4,78),(31,67),(64,71),(100,58),(130,60)],(14,20,24),11)
    line([(-4,75),(31,64),(64,68),(100,55),(130,57)],(84,93,98),8)
    line([(-4,71),(31,60),(64,64),(100,51),(130,53)],(150,153,146),2)
    # Two severed coolant conduits with retaining clamps and dark hollow ends.
    for shift,shade,shine in [(0,(56,68,72),(114,129,128)),(8,(87,66,55),(135,108,84))]:
        points=[(10,114+shift),(27,99+shift),(69,98+shift),(84,82+shift)]
        line(points,(19,25,28),8);line(points,shade,5)
        line([(x-1,y-1) for x,y in points],shine)
    for x in (35,58):
        line([(x,95),(x+1,108)],(128,134,130),3)
    for x,y in [(7,7),(54,56),(119,9),(106,62),(57,83),(95,115),(18,81)]:
        rect((x,y,x+2,y+2),(27,29,30));rect((x,y,x+1,y+1),(150,150,136))
    rect((119,0,127,127),(125,133,135))
    line([(120,0),(120,128)],(167,166,154))
    buf = io.BytesIO()
    img.resize((128,128),Image.Resampling.LANCZOS).save(buf,format="PNG")
    return buf.getvalue()


def wreck_groups(body, painted_count):
    exterior_ids = {id(tri) for tri in body[:painted_count]}
    nose, behind, front_rim = fracture(body, .150, .32, .14)
    cockpit, engine, rear_rim = fracture(behind, -.138, .15, -.16)
    shells = [nose, cockpit, engine]
    caps = [torn_steel(front_rim, -1), torn_steel(front_rim, 1) + torn_steel(rear_rim, -1),
            torn_steel(rear_rim, 1)]
    ribs = [section_ribs(.150, .32, -1), section_ribs(.150, .32, 1) + section_ribs(-.138, .15, -1),
            section_ribs(-.138, .15, 1)]
    for (name, pivot), shell, cap, supports in zip(WRECK_PIVOTS.items(), shells, caps, ribs):
        exterior = [tri for tri in shell if id(tri) in exterior_ids]
        hidden = [tri for tri in shell if id(tri) not in exterior_ids]
        inside = inner_plate_uv(cap, cut_face=True) + inner_plate_uv(coarse_socket_caps(hidden))
        inside += inner_plate_uv(supports, cut_face=True, rib=True)
        yield name, pivot, [(exterior, None), (inside, 0)]


def build():
    parts = cut_parts(load_surface())
    groups = []
    for name, pivot in PIVOTS.items():
        triangles = triangles_of(parts[name])
        if name == "Body":
            painted_count = len(triangles)
        close_open_edges(triangles, name)
        groups.append((name, pivot, [(triangles, None)]))
    write_glb(TARGET, groups)
    body = groups[0][2][0][0]
    steel = {"name": "Scorched torn metal", "doubleSided": True, "pbrMetallicRoughness": {
        "baseColorTexture": {"index": 0}, "metallicFactor": .36, "roughnessFactor": .82}}
    write_glb(WRECK, wreck_groups(body, painted_count), [steel], interior_plate())


if __name__ == "__main__":
    build()
