"""Finish assignments for the original sentry and disruptor recruitment meshes."""
import numpy as np
from scipy.spatial import cKDTree


# Blender camera directions. Look down the sentry's rails from the nose and
# through the open side of the disruptor's containment frame.
VIEWS = {
    "sentry": (.805, -.484, .342),
    "disruptor": (.74, .62, .28),
}


def shield_relief(triangles):
    """Measure the cast grooves on one detached shield in local tangent space."""
    centers = triangles[:, :, :3].mean(axis=1)
    normals = triangles[:, :, 3:].mean(axis=1)
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-10)
    distances, nearby = cKDTree(centers).query(centers, k=110)
    alignment = np.einsum("ijk,ik->ij", normals[nearby], normals)
    weights = np.exp(-(distances / .039) ** 2) * np.clip(alignment, 0, 1)
    surface = np.einsum("ij,ijk->ik", weights, centers[nearby]) / weights.sum(axis=1, keepdims=True)
    relief = np.einsum("ij,ij->i", centers - surface, normals)
    return np.median(relief[nearby[:, :7]], axis=1)


def paint(unit, tri, islands):
    finish = np.full(len(tri), "gold", dtype="<U12")
    if unit == "sentry":
        # The two concentric spheres are exported separately from all five
        # tiers of floating claws, so the entire outer globe can be polished.
        surfaces = {
            "cyan": (8, 35, 36, 41),
            "champagne": (2, 3, 22, 23, 32, 34),
            "bronze": (4, 5, 10, 11, 18, 19, 27, 28),
            "navy": (12, 13, 25, 31, 33),
            "cobalt": (24,),
            "gold": (0, 6, 7, 9, 20, 21, 29, 30),
            "psi_core": (1,),
            "blue": (14, 15, 16, 17, 26, 37),
            "silver": (38, 39, 40),
        }
    elif unit == "disruptor":
        # Four detached, opposing shields surround a gimballed central lens.
        # The two bands beside the coil are the left/right edges of that cage.
        surfaces = {
            "bronze": (1, 2, 4, 14),
            "gold": (0, 15),
            "plasma_core": (5, 7),
            "amber": (9, 10, 11),
            "gunmetal": (3, 6, 8, 12, 13),
        }
    else:
        raise ValueError(f"Unsupported core unit {unit!r}")
    for material, ids in surfaces.items():
        finish[np.isin(islands, ids)] = material
    if unit == "disruptor":
        # A dark inner liner separates the two amber discs from the crown.
        finish[(islands == 3) & (tri[:, :, 1].mean(axis=1) > .48)] = "bronze"
        # The emblems are embossed into the original mesh. Pick up the crests
        # of the low bronze shields and the recesses in the tall gold vanes.
        for shield in (0, 1, 2, 15):
            faces = np.flatnonzero(islands == shield)
            relief = shield_relief(tri[faces])
            if shield in (1, 2):
                finish[faces[relief > .0044]] = "gold"
                finish[faces[relief < -.0054]] = "gunmetal"
            else:
                finish[faces[relief < -.0035]] = "bronze"
    return finish
