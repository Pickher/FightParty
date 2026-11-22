"""Bisect a rigid mech shell and close both new joint faces in its source coordinates."""
import numpy as np
from scipy.spatial import Delaunay


def _cross(a, b):
    return a[..., 0] * b[..., 1] - a[..., 1] * b[..., 0]


def _segment_crosses(a, b, c, d):
    u = b - a
    v = d - c
    return ((_cross(u, c - a) * _cross(u, d - a) < -1e-23) &
            (_cross(v, a - c) * _cross(v, b - c) < -1e-23))


def _cap_faces(points, segments):
    """Restore constrained edges before filtering nested contours by the even/odd rule."""
    faces = Delaunay(points).simplices.copy()
    for a, b in segments:
        previous = set()
        for _ in range(len(faces)):
            edges = {}
            for face_index, (u, v, w) in enumerate(faces):
                for left, right, other in ((u, v, w), (v, w, u), (w, u, v)):
                    edges.setdefault(tuple(sorted((left, right))), []).append((face_index, other))
            if tuple(sorted((a, b))) in edges:
                break
            candidates = []
            for (c, d), sides in edges.items():
                if len(sides) != 2 or (c, d) in previous:
                    continue
                if not _segment_crosses(*points[[a, b, c, d]]):
                    continue
                (i, h), (j, k) = sides
                if _segment_crosses(*points[[c, d, h, k]]):
                    candidates.append((int(_segment_crosses(*points[[a, b, h, k]])), c, d, h, k, i, j))
            if not candidates:
                break
            _, c, d, h, k, i, j = min(candidates)
            faces[i], faces[j] = [h, k, c], [k, h, d]
            previous.add((c, d))
    centers = points[faces].mean(axis=1)
    inside = np.zeros(len(faces), dtype=bool)
    for a, b in points[segments]:
        crossing = (a[1] > centers[:, 1]) != (b[1] > centers[:, 1])
        if np.any(crossing):
            x = a[0] + (centers[crossing, 1] - a[1]) * (b[0] - a[0]) / (b[1] - a[1])
            inside[crossing] ^= centers[crossing, 0] < x
    return faces[inside]


def split_joint(triangles, tags, point, normal):
    """Return the positive and negative triangle soups and their signed integer island IDs.

    Input vertices contain position and normal. Original panel IDs stay on the exterior;
    both new faces receive -1, allowing the rig to paint them as recessed metal.
    """
    triangles = np.asarray(triangles, dtype=float).reshape(-1, 3, 6)
    tags = np.asarray(tags, dtype=np.int32)
    point = np.asarray(point, dtype=float)
    axis = np.asarray(normal, dtype=float)
    axis = axis / np.linalg.norm(axis)
    distance = (triangles[:, :, :3] - point) @ axis
    distance[np.abs(distance) < 1e-10] = 0
    positive = np.all(distance >= 0, axis=1)
    negative = ~positive & np.all(distance <= 0, axis=1)
    soups = [list(triangles[positive]), list(triangles[negative])]
    labels = [list(tags[positive]), list(tags[negative])]
    for face_index in np.flatnonzero(~(positive | negative)):
        tri, dist = triangles[face_index], distance[face_index]
        vertex_lists = [[], []]
        for i, b in enumerate(tri):
            a, da, db = tri[i - 1], dist[i - 1], dist[i]
            if da * db < 0:
                cut = a + (b - a) * (da / (da - db))
                cut[3:] /= max(np.linalg.norm(cut[3:]), 1e-12)
                for polygon in vertex_lists:
                    polygon.append(cut)
            if db >= 0:
                vertex_lists[0].append(b)
            if db <= 0:
                vertex_lists[1].append(b)
        for side, polygon in enumerate(vertex_lists):
            for i in range(1, len(polygon) - 1):
                soups[side].append(np.array([polygon[0], polygon[i], polygon[i + 1]]))
                labels[side].append(tags[face_index])

    sides = [np.asarray(soup, dtype=float).reshape(-1, 3, 6) for soup in soups]
    # Edges present only once on each side form the new seam. Intersecting both
    # sets prevents an existing hole or a coplanar panel from receiving a plug.
    cuts = []
    for soup in sides:
        verts = soup[:, :, :3]
        edges = np.stack((verts, verts[:, (1, 2, 0)]), axis=2).reshape(-1, 2, 3)
        edges = edges[np.all(np.abs((edges - point) @ axis) < 1e-8, axis=1)]
        boundary = set()
        for line in np.round(edges, 8):
            a, b = sorted(map(tuple, line))
            if a != b:
                boundary.symmetric_difference_update([(a, b)])
        cuts.append(boundary)
    boundary = sorted(cuts[0] & cuts[1])
    if len(boundary) >= 3:
        coords, inverse = np.unique(np.asarray(boundary).reshape(-1, 3), axis=0, return_inverse=True)
        tangent = np.cross(axis, np.eye(3)[np.argmin(np.abs(axis))])
        tangent /= np.linalg.norm(tangent)
        frame = np.column_stack([tangent, np.cross(axis, tangent)])
        uv = (coords - point) @ frame
        if np.linalg.matrix_rank(uv - uv.mean(0)) == 2:
            indices = _cap_faces(uv, inverse.reshape(-1, 2))
            for side, outward in enumerate((-axis, axis)):
                face = coords[indices].copy()
                winding = np.cross(face[:, 1] - face[:, 0], face[:, 2] - face[:, 0]) @ outward
                face[winding < 0] = face[winding < 0][:, ::-1]
                caps = np.concatenate([face, np.broadcast_to(outward, face.shape)], axis=2)
                sides[side] = np.concatenate([sides[side], caps])
                labels[side].extend([-1] * len(caps))
    return tuple((soup, np.asarray(ids, dtype=np.int32)) for soup, ids in zip(sides, labels))
