"""Build the rigid Thor rig from its two uploaded, untextured GLBs (Python 3, NumPy, SciPy)."""
from pathlib import Path

import numpy as np
from scipy.spatial import Delaunay

from rigid_glb import Rig, labels, load_surface, face_normals, matrix, orient_axis
from thor_paint import GUN, MATERIALS, assign_paint

ASSETS = Path(__file__).resolve().parents[2] / "assets/models/thor"


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


def colors(part, tris, islands):
    return assign_paint(part, tris[:, :, :3].mean(1), face_normals(tris), islands)


def build():
    ordinary, ids = load_surface(ASSETS / "thor.glb", 41)
    artillery, alt_ids = load_surface(ASSETS / "thor_rocket.glb", 29)
    rig = Rig(MATERIALS, "Thor")
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
