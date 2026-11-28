"""Recruit finishes for the two original four-legged walker meshes."""

import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components


# Both weapons face glTF +X. These Blender camera directions expose the
# apertures and leave negative space between the four feet.
VIEWS = {
    "colossus": (1.0, -.40, .39),
    "immortal": (1.0, -.53, .57),
}


def _panel_centres(tri, crease):
    """Give every face the centre of its own crease-bounded machined panel."""
    xyz = tri[:, :, :3]
    _, welded = np.unique(xyz.reshape(-1, 3), axis=0, return_inverse=True)
    welded = welded.reshape(-1, 3)
    edges = np.stack((welded, np.roll(welded, -1, axis=1)), axis=-1)
    edges = np.sort(edges.reshape(-1, 2), axis=1)
    order = np.lexsort((edges[:, 1], edges[:, 0]))
    sorted_edges = edges[order]
    shared = np.flatnonzero((sorted_edges[:-1] == sorted_edges[1:]).all(axis=1))
    face_a = order[shared] // 3
    face_b = order[shared + 1] // 3

    normals = np.cross(xyz[:, 1] - xyz[:, 0], xyz[:, 2] - xyz[:, 0])
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-12)
    smooth = (normals[face_a] * normals[face_b]).sum(axis=1) > np.cos(np.radians(crease))
    graph = coo_matrix((np.ones(smooth.sum()), (face_a[smooth], face_b[smooth])),
                       shape=(len(tri), len(tri)))
    _, panels = connected_components(graph, directed=False)
    counts = np.bincount(panels)
    means = np.column_stack([np.bincount(panels, weights=axis) / counts
                             for axis in xyz.mean(axis=1).T])
    return means[panels]


def _immortal(finish, islands, panel):
    x, y, z = panel.T
    lateral = np.abs(z + .011)
    shins = np.isin(islands, (0, 1, 22, 23))
    toes = np.isin(islands, (2, 3, 24, 25))
    struts = np.isin(islands, (7, 8, 20, 21))
    finish[shins] = "champagne"
    finish[shins & (y < .25)] = "bronze"
    finish[toes] = "steel"
    finish[struts] = "gunmetal"
    finish[struts & (y > .38)] = "bronze"
    finish[np.isin(islands, (12, 13, 18, 19))] = "cobalt"
    finish[islands == 14] = "gunmetal"
    finish[islands == 15] = "cobalt"

    belly = islands == 11
    finish[belly] = "gold"
    finish[belly & (y > .401)] = "gunmetal"
    finish[belly & (np.abs(x - .13) < .01) & (np.abs(y - .336) < .01)] = "cyan"
    head = islands == 4
    finish[head] = "champagne"
    finish[head & (y < .57)] = "gunmetal"
    # The original casting has an oval panel on either cheek and three
    # distinct glass, bezel and keel surfaces along the forward ridge.
    finish[head & (lateral > .126)] = "cobalt"
    front = head & (x > -.018) & (lateral < .016)
    finish[front & (y > .65) & (y < .76)] = "bronze"
    finish[front & (y > .76) & (y < .86)] = "blue"
    finish[front & (y > .86) & (y < .893)] = "cyan"

    finish[np.isin(islands, (5, 6))] = "bronze"
    covers = np.isin(islands, (9, 10))
    finish[covers] = "gold"
    finish[covers & (lateral < .19)] = "gunmetal"

    # Each original gun has two nested elliptical apertures on different X
    # stations. Keep the rims and the fitted ends as separate materials.
    guns = np.isin(islands, (16, 17))
    finish[guns] = "steel"
    finish[guns & (x < .05)] = "gunmetal"
    for height, ring, face in ((.683, .263, .280), (.785, .230, .247)):
        muzzle = guns & (np.abs(y - height) < .036)
        finish[muzzle & (x > ring)] = "navy"
        finish[muzzle & (x > face)] = "blue"


def _colossus(finish, islands, panel):
    x, y, z = panel.T
    blades = np.isin(islands, (1, 3, 32, 33))
    finish[blades] = "champagne"
    finish[blades & (y < .20)] = "gold"
    finish[np.isin(islands, (6, 7, 34, 35))] = "cobalt"
    links = np.isin(islands, (13, 15, 28, 29))
    finish[links] = "steel"
    finish[links & (y > .38)] = "bronze"
    finish[np.isin(islands, (19, 20, 26, 27))] = "gunmetal"
    finish[np.isin(islands, (14, 18))] = "navy"
    finish[islands == 21] = "cobalt"

    # A raised sapphire lens and its bezel already exist on the shell's brow.
    shell = islands == 0
    finish[shell] = "champagne"
    finish[shell & (x > .05) & (y < .77)] = "bronze"
    bezel = shell & (x > -.036) & (x < .08) & (y > .80) & (y < .92)
    finish[bezel] = "cobalt"
    finish[bezel & (np.abs(z + .005) < .01)] = "blue"
    finish[bezel & (y > .87) & (np.abs(z + .005) < .01)] = "cyan"
    finish[np.isin(islands, (2, 4, 5))] = "bronze"
    finish[np.isin(islands, (8, 24, 30))] = "gunmetal"
    finish[np.isin(islands, (9, 10))] = "gold"
    finish[np.isin(islands, (16, 17, 25))] = "cobalt"
    finish[np.isin(islands, (11, 12, 22, 23))] = "steel"
    emitter = islands == 31
    finish[emitter] = "navy"
    finish[emitter & (x < .206)] = "gold"
    finish[emitter & (x > .215) & (y > .62)] = "blue"
    finish[np.isin(islands, (36, 37, 38, 39))] = "cyan"
    finish[np.isin(islands, (40, 41))] = "champagne"
    finish[np.isin(islands, (42, 43))] = "silver"


def paint(unit, tri, islands):
    finish = np.full(len(tri), "gold", dtype="<U12")
    if unit == "immortal":
        _immortal(finish, islands, _panel_centres(tri, 45))
    elif unit == "colossus":
        _colossus(finish, islands, _panel_centres(tri, 55))
    else:
        raise ValueError(f"Unsupported walker {unit!r}")
    return finish
