"""Articulate and paint the uploaded Marauder. Run with Python 3, NumPy and SciPy."""

from pathlib import Path

import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial import Delaunay

from rigid_glb import Rig, face_normals, load_surface, matrix, orient_axis

ASSETS = Path(__file__).resolve().parents[2] / "assets/models/marauder"
PLATE, DARK_PLATE, JOINT, STEEL, VISOR, STRIPE, CORE = range(7)


def finish(name, rgb, metal, rough, glow=(0, 0, 0)):
    return {
        "name": name,
        "pbrMetallicRoughness": {
            "baseColorFactor": [*rgb, 1],
            "metallicFactor": metal,
            "roughnessFactor": rough,
        },
        "emissiveFactor": glow,
    }


# Linear glTF factors. Narrow warm ID bands distinguish the armored grenade trooper
# from the blue-grey Thor; the amber faceplate and cyan reactor are separate optics.
MATERIALS = [
    finish("Oxide red ceramic", (0.26, 0.052, 0.042), 0.35, 0.42),
    finish("Oxblood trim", (0.107, 0.037, 0.039), 0.44, 0.46),
    finish("Graphite flex seals", (0.037, 0.049, 0.060), 0.34, 0.58),
    finish("Brushed steel", (0.26, 0.31, 0.33), 0.66, 0.40),
    finish("Amber faceplate", (0.89, 0.37, 0.063), 0.28, 0.20, (0.47, 0.12, 0.008)),
    finish("Sand unit markings", (0.59, 0.45, 0.259), 0.25, 0.48),
    finish("Reactor sight glass", (0.10, 0.44, 0.55), 0.22, 0.24, (0.035, 0.50, 0.73)),
]

# World-space joints measured on the asymmetric source. P is on +Z, forward is +X.
LEGS = {
    "P": ((0.025, 0.48, 0.110), (0.072, 0.310, 0.170), (0.015, 0.101, 0.220)),
    "N": ((0.035, 0.49, -0.090), (0.084, 0.320, -0.110), (-0.005, 0.112, -0.147)),
}
ARMS = {
    "P": ((-0.040, 0.689, 0.222), (-0.045, 0.594, 0.324), (0.022, 0.282, 0.397), (0.170, -0.759, 0.628)),
    "N": ((0.029, 0.683, -0.245), (0.035, 0.596, -0.304), (0.200, 0.287, -0.340), (0.597, -0.703, -0.385)),
}
CAP = -1
ID_BAND, SOLE, BORE, LIP, SIGHT = -2, -3, -4, -5, -6


def shell_pauldron(shell):
    """The N shoulder touches the torso at a vertex only. Recover its complete plate by shared edges."""
    _, ids = np.unique(shell[:, :, :3].reshape(-1, 3), axis=0, return_inverse=True)
    faces = ids.reshape(-1, 3)
    edges = np.sort(np.stack([faces, faces[:, [1, 2, 0]]], axis=-1), axis=-1).reshape(-1, 2)
    _, edge_id, count = np.unique(edges, axis=0, return_inverse=True, return_counts=True)
    order = np.argsort(edge_id, kind="stable")
    first = np.r_[0, np.cumsum(count)[:-1]][count == 2]
    links = (order[first] // 3, order[first + 1] // 3)
    graph = coo_matrix((np.ones(len(first)), links), shape=(len(faces),) * 2)
    group = connected_components(graph, directed=False)[1]
    pauldron = np.flatnonzero(np.bincount(group) == 2282)
    if len(pauldron) != 1:
        raise ValueError("Cannot recognize the original N shoulder shell")
    return group == pauldron[0]


def reduce_surface(tris, cell=0.016):
    """Cluster vertices in orthographic sub-pixel cells, retaining independent source islands and their normals."""
    p = tris.reshape(-1, 7)
    xyz, ids = np.unique(np.column_stack([p[:, :3], p[:, 6]]), axis=0, return_inverse=True)
    keys = np.column_stack([np.floor(xyz[:, :3] / cell + 0.5), xyz[:, 3]])
    _, clusters, counts = np.unique(keys, axis=0, return_inverse=True, return_counts=True)
    mean = np.column_stack([np.bincount(clusters, weights=v) / counts for v in xyz[:, :3].T])
    # Keep one original surface sample per cell rather than moving outer armor inwards.
    error = np.sum((xyz[:, :3] - mean[clusters]) ** 2, axis=1)
    nearest = np.lexsort((error, clusters))
    pos = xyz[nearest[np.r_[0, np.cumsum(counts)[:-1]]], :3]
    result = tris.copy()
    result[:, :, :3] = pos[clusters[ids]].reshape(-1, 3, 3)
    cross = np.cross(result[:, 1, :3] - result[:, 0, :3], result[:, 2, :3] - result[:, 0, :3])
    return result[np.linalg.norm(cross, axis=1) > 1.0e-11]


def wafer(edges, normal):
    """Close a joint using its real cross-section, retaining separate contours and holes."""
    if not edges:
        return np.empty((0, 3, 7))
    lines = np.array(edges)
    basis = orient_axis(normal if abs(normal[1]) < 0.98 else [1, 0, 0])
    u = np.cross(normal, basis[:, 1] if abs(normal[1]) < 0.98 else basis[:, 0])
    u /= np.linalg.norm(u)
    v = np.cross(normal, u)
    coords, inv = np.unique(np.round(lines.reshape(-1, 3), 8), axis=0, return_inverse=True)
    if len(coords) < 3:
        return np.empty((0, 3, 7))
    uv = coords @ np.array([u, v]).T
    pieces = Delaunay(uv).simplices
    middle = uv[pieces].mean(1)
    a, b = uv[inv.reshape(-1, 2)].transpose(1, 0, 2)
    odd = np.zeros(len(pieces), dtype=bool)
    for left, right in zip(a, b):
        if abs(right[1] - left[1]) > 1.0e-12:
            crossing = (right[1] > middle[:, 1]) != (left[1] > middle[:, 1])
            odd ^= crossing & (
                left[0] + (middle[:, 1] - left[1]) * (right[0] - left[0]) / (right[1] - left[1])
                > middle[:, 0]
            )
    corners = coords[pieces[odd]]
    out = np.empty((len(corners), 3, 7))
    out[:, :, :3] = corners
    out[:, :, 3:6] = normal
    out[:, :, 6] = CAP
    return out


def divide(tris, direction, offset, close=True):
    """Split on a joint plane, interpolating original normals. Return positive then negative side."""
    normal = np.array(direction, dtype=float)
    d = tris[:, :, :3] @ normal - offset
    norm = normal / np.linalg.norm(normal)
    pos, neg = [tris[(d >= 0).all(1)]], [tris[(d <= 0).all(1)]]
    edges = []
    cross = (d.max(1) > 0) & (d.min(1) < 0)
    for tri, dist in zip(tris[cross], d[cross]):
        sides = [[], []]
        edge = []
        for i, b in enumerate(tri):
            a = tri[i - 1]
            da, db = dist[i - 1], dist[i]
            if da * db < 0:
                p = a + (b - a) * (da / (da - db))
                edge.append(p[:3])
                sides[0].append(p)
                sides[1].append(p)
            elif db == 0:
                edge.append(b[:3])
            if db >= 0:
                sides[0].append(b)
            if db <= 0:
                sides[1].append(b)
        if len(edge) == 2:
            edges.append(edge)
        for polygon, dest in zip(sides, (pos, neg)):
            dest.append(
                np.array([[polygon[0], polygon[i], polygon[i + 1]] for i in range(1, len(polygon) - 1)])
            )
    if close:
        cap = wafer(edges, norm)
        neg.append(cap)
        back = cap[:, ::-1].copy()
        back[:, :, 3:6] *= -1
        pos.append(back)
    return np.concatenate(pos), np.concatenate(neg)


def mark(mesh, mask, planes, paint_id):
    # Cut the color boundary into the source faces rather than making its edge
    # follow the arbitrary triangles of the scanned model.
    outside = [mesh[~mask]]
    inside = mesh[mask]
    for normal, offset in planes:
        inside, trimmed = divide(inside, normal, offset, close=False)
        outside.append(trimmed)
    inside[:, :, 6] = paint_id
    return np.concatenate(outside + [inside])


def muzzle_collar(port, direction):
    # A short machined collar fits over the existing round wrist face. The black
    # chamber is recessed behind its steel lip and the marker sits on that lip.
    basis = orient_axis(direction)
    rows = []
    angles = np.arange(20) * 2 * np.pi / 20
    radial = np.column_stack([np.zeros(len(angles)), np.cos(angles), np.sin(angles)]) @ basis.T
    rings = [
        (-0.012, 0.040),
        (0.009, 0.048),
        (0.026, 0.047),
        (0.031, 0.043),
        (0.031, 0.030),
        (0.015, 0.027),
        (0.015, 0),
    ]
    for i, ((x, r), (xx, rr)) in enumerate(zip(rings, rings[1:])):
        a = port + basis[:, 0] * x + radial * r
        b = port + basis[:, 0] * xx + radial * rr
        for k in range(len(radial)):
            j = (k + 1) % len(radial)
            for tri in [(a[k], a[j], b[k]), (a[j], b[j], b[k])]:
                tri = np.array(tri)
                cross = np.cross(tri[1] - tri[0], tri[2] - tri[0])
                if np.linalg.norm(cross) < 1e-11:
                    continue
                row = np.empty((3, 7))
                row[:, :3] = tri
                row[:, 3:6] = cross / np.linalg.norm(cross)
                row[:, 6] = LIP if 1 <= i <= 3 else BORE
                rows.append(row)
    return np.array(rows)


def paint(part, tri):
    x, y, z = tri[:, :, :3].mean(1).T
    nx, ny, nz = face_normals(tri).T
    island = tri[:, 0, 6].astype(int)
    color = np.full(len(tri), PLATE)
    if part.startswith("Hip") or part == "Pelvis":
        color[:] = JOINT
        color[(ny > 0.35) & (x > 0.02)] = DARK_PLATE
        color[np.isin(island, [31, 37])] = DARK_PLATE
    elif part.startswith("Knee") or part.startswith("Ankle"):
        color[:] = DARK_PLATE
        color[(x > 0.008) & (y > 0.05)] = PLATE
        color[ny < -0.55] = JOINT
        color[np.isin(island, [14, 15, 16, 17, 18, 19, 20, 21, 22])] = STEEL
    elif part.startswith("Shoulder"):
        color[:] = JOINT
        cover = np.isin(island, [13, 50])
        color[cover] = PLATE
        color[cover & (ny < -0.16)] = DARK_PLATE
        color[cover & (ny < -0.63)] = STEEL
    elif part.startswith("Launcher"):
        color[:] = DARK_PLATE
        color[(np.abs(z + 0.01) > 0.36) & (y > 0.36)] = PLATE
        color[(ny < -0.42) | (y < 0.36)] = JOINT
        color[(y > 0.408) & (y < 0.429) & (np.abs(z) > 0.36)] = STEEL
        color[np.isin(island, [23, 24, 26, 27, 28, 29, 33, 35, 38, 41, 42, 43, 44, 45])] = STEEL
    elif part == "Reactor":
        color[:] = DARK_PLATE
        color[(ny < -0.20) | np.isin(island, [3, 9, 10])] = JOINT
        color[np.isin(island, [2, 4, 6, 8, 11])] = STEEL
        color[(island == 1) & (nx < -0.45)] = CORE
    elif part == "Helmet":
        color[:] = DARK_PLATE
        color[island == 30] = JOINT
        color[(island == 25) | ((island != 30) & (ny > 0.75))] = STEEL
    else:
        color[(ny < -0.33) | (x < -0.05)] = DARK_PLATE
        color[(np.abs(z) < 0.092) & (x > 0.18) & (y < 0.65)] = JOINT
        color[np.isin(island, [34, 36, 39, 40, 46, 47, 48, 49])] = STEEL
    color[np.isin(island, [CAP, SOLE, BORE])] = JOINT
    color[island == LIP] = STEEL
    color[island == ID_BAND] = STRIPE
    color[island == SIGHT] = VISOR
    return color


def build():
    tris, ids = load_surface(ASSETS / "marauder.glb", 50)
    source = np.flatnonzero(ids == 0)
    ids[source[shell_pauldron(tris[source])]] = 50
    data = reduce_surface(
        np.concatenate([tris, np.broadcast_to(ids[:, None, None], (len(ids), 3, 1))], axis=2)
    )
    ids = data[:, 0, 6].astype(int)
    pieces = {}

    def take(*numbers):
        return data[np.isin(ids, numbers)]

    def add(name, *arrays):
        pieces[name] = np.concatenate(arrays)

    rig = Rig(MATERIALS, "Marauder")

    def joint(name, parent, point, normal=None):
        rig.node(name, parent, matrix(point, orient_axis(normal)) if normal is not None else matrix(point))

    joint("Marauder", None, (0, 0, 0))
    joint("Pelvis", "Marauder", (0.035, 0.465, 0.015))
    joint("Trunk", "Pelvis", (0.0, 0.546, 0.0))
    joint("Reactor", "Trunk", (-0.142, 0.69, -0.02))
    joint("ReactorCore", "Reactor", (-0.303, 0.660, -0.023), (-1, 0, 0))
    joint("Helmet", "Trunk", (0.080, 0.739, -0.013))
    pelvis, legs = divide(take(12), (0, 1, 0), 0.466)
    legp, legn = divide(legs, (0, 0, 1), 0.020)
    add("Pelvis", pelvis, take(31, 32, 37))
    shell = take(0)
    for side, sign, leg in [("P", 1, legp), ("N", -1, legn)]:
        hip, knee, ankle = LEGS[side]
        shoulder, elbow, port, axis = ARMS[side]
        for name, parent, point in [
            ("Hip", "Pelvis", hip),
            ("Knee", "Hip" + side, knee),
            ("Ankle", "Knee" + side, ankle),
            ("Shoulder", "Trunk", shoulder),
            ("Launcher", "Shoulder" + side, elbow),
        ]:
            joint(name + side, parent, point)
        joint("ArmMuzzle" + side, "Launcher" + side, np.array(port) + orient_axis(axis)[:, 0] * 0.031, axis)
        thigh, boot = divide(leg, (-0.16, 1, 0), knee[1] - 0.16 * knee[0])
        shin, foot = divide(boot, (-0.18, 1, 0), ankle[1] - 0.18 * ankle[0])
        foot = mark(foot, foot[:, 0, 6] != CAP, [((0.03, -1, 0), -0.049 if sign > 0 else -0.067)], SOLE)
        add("Hip" + side, thigh)
        add("Knee" + side, shin, take(*([16, 18, 19, 20, 22] if sign > 0 else [14, 15, 17, 21])))
        add("Ankle" + side, foot)
        # The uploaded guns and hose roots are fused. Cut inboard of the forearm along its collar.
        outer, shell = divide(shell, (-0.06, -0.18, sign), 0.192 - 0.18 * 0.60)
        upper, launcher = divide(outer, (-0.13, 1, 0.04 * sign), 0.622)
        pauldron = take(13 if sign > 0 else 50)
        stripe = np.array([0.12, -0.018, sign])
        pauldron = mark(
            pauldron,
            np.ones(len(pauldron), bool),
            [(stripe, 0.244 - sign * 0.012), (-stripe, -0.268 + sign * 0.012), ((0, 1, 0), 0.699)],
            ID_BAND,
        )
        add("Shoulder" + side, upper, pauldron, take(5 if sign > 0 else 7))
        add(
            "Launcher" + side,
            launcher,
            muzzle_collar(port, axis),
            take(*([23, 24, 26, 27, 28, 29] if sign > 0 else [33, 35, 38, 41, 42, 43, 44, 45])),
        )
    back, chest = divide(shell, (-1, 0.02, 0), 0.134 + 0.02 * 0.70)
    add("Reactor", back, take(1, 2, 3, 4, 6, 8, 9, 10, 11))
    crest, body = divide(chest, (0, 1, 0), 0.837)
    visor = take(30)
    visor = mark(
        visor,
        np.ones(len(visor), bool),
        [((1, 0, 0), 0.168), ((0, 1, 0.20), 0.731), ((0, 1, -0.20), 0.735), ((0, -1, 0), -0.792)],
        SIGHT,
    )
    add("Helmet", crest, take(25), visor)
    add("Trunk", body, take(34, 36, 39, 40, 46, 47, 48, 49))
    for name, mesh in pieces.items():
        rig.mesh(name, mesh[:, :, :6], paint(name, mesh), rig.frames[name])
    rig.write(ASSETS / "marauder_rig.glb")
    print(
        "Marauder:",
        len(tris),
        "source triangles;",
        sum(len(t) for t in pieces.values()),
        "triangles with closed mounts;",
        len(pieces),
        "rigid mesh sections",
    )
    return pieces


if __name__ == "__main__":
    build()
