"""Panel finishes for the two untextured tank uploads. Both sets of coordinates use +X forward."""
import numpy as np

from build_marauder_rig import divide
from rigid_glb import face_normals


SAND, SKIRT, FRAME, TREAD, STEEL, MARK, OPTIC = range(7)


def _finish(name, linear_rgb, metallic, roughness, glow=None):
    material = {"name": name, "pbrMetallicRoughness": {
        "baseColorFactor": [*linear_rgb, 1.0], "metallicFactor": metallic, "roughnessFactor": roughness}}
    if glow is not None:
        material["emissiveFactor"] = glow
    return material


MATERIALS = [
    _finish("Desert ochre enamel", (.39, .245, .116), .31, .49),
    _finish("Brown olive armor skirt", (.165, .137, .085), .35, .54),
    _finish("Blued steel frame", (.072, .096, .106), .52, .49),
    _finish("Graphite track pads", (.033, .043, .048), .18, .72),
    _finish("Worn machined steel", (.29, .335, .34), .66, .4),
    _finish("Linen recognition band", (.69, .64, .46), .23, .49),
    _finish("Turquoise sight glass", (.042, .38, .43), .24, .23, (.015, .26, .31)),
]


def paint(part, centroid, normal, form, islands):
    """Return one atlas index per triangle. Island IDs are those of each uploaded mesh."""
    x, y, z = centroid.T
    nx, ny, nz = normal.T
    side = np.abs(z)
    color = np.full(len(islands), FRAME, dtype=np.uint8)
    if form == "mobile":
        # The hull and all four track guards came welded together. The side profile
        # follows the real belt as it rises at the back and descends around the nose.
        hull = islands == 0
        belt_top = np.interp(x, [-.5, -.35, -.21, .08, .25, .41, .5],
                             [.25, .32, .33, .26, .23, .18, .12])
        color[hull & (y < belt_top) & (side > .10)] = TREAD
        color[hull & (y > belt_top)] = SKIRT
        guard = hull & (y > belt_top + .023) & (ny > .25)
        color[guard] = SAND
        color[guard & (x > .18) & (side < .075)] = FRAME
        # Thin cast-in grilles, wheel hubs, tucked-in support feet and the turret ring.
        color[np.isin(islands, [29, 30])] = SKIRT
        color[np.isin(islands, [29, 30]) & (y < .054)] = TREAD
        color[np.isin(islands, [31, 32])] = SKIRT
        color[np.isin(islands, [31, 32]) & (ny > .48)] = SAND
        color[np.isin(islands, [27, 28, 41, 42, 44])] = STEEL
        color[np.isin(islands, [34, 43, 45, 52, 53])] = FRAME
        color[(islands >= 56) & (islands <= 73)] = STEEL
        turret = islands == 33
        color[turret] = SKIRT
        color[turret & (y > .475)] = SAND
        color[turret & (y > .551) & (side < .072)] = FRAME
        color[np.isin(islands, [46, 47])] = STEEL
        color[np.isin(islands, [48, 49])] = OPTIC
        barrel = islands == 50
        color[barrel & (x < .179)] = SAND
        color[barrel & (x > .232) & (x < .288)] = STEEL
        color[barrel & (x > .326) & (nx < .65)] = SKIRT
        color[barrel & (x > .40) & (nx > .75)] = TREAD
        color[barrel & (x < .221) & (side < .041) & (ny > .34)] = SAND
        color[islands == 51] = SKIRT
        color[(islands == 51) & (ny > .38)] = SAND
        color[guard & (x > .26) & (x < .288) & (side > .115)] = MARK
    elif form == "siege":
        # In the deployed upload each splayed tread includes its sloping fender.
        # Its local profile is easier to recognize in height than in global X/Z.
        tracks = np.isin(islands, [2, 3, 23, 24])
        rear = np.isin(islands, [23, 24])
        belt_top = np.where(rear, .225, .203) - .40 * np.maximum(side - .19, 0)
        color[tracks] = TREAD
        color[tracks & (y > belt_top)] = SKIRT
        guard = tracks & (y > belt_top + .018) & (ny > .30)
        color[guard] = SAND
        color[guard & (x > .26) & (x < .288)] = MARK
        hull = islands == 7
        color[hull & (y > .176)] = SKIRT
        color[hull & (y > .267) & (ny > .32)] = SAND
        color[hull & (y > .344)] = SAND
        color[hull & (y > .447) & (side < .065)] = FRAME
        # These pairs are the shoe, upper link, ram and pins of each side jack.
        color[np.isin(islands, [9, 10])] = SKIRT
        color[np.isin(islands, [9, 10]) & (ny > .36)] = SAND
        color[np.isin(islands, [9, 10]) & (y < .027)] = TREAD
        color[np.isin(islands, [11, 12, 15, 16, 19, 20, 25, 26])] = STEEL
        color[np.isin(islands, [13, 14])] = SKIRT
        color[np.isin(islands, [17, 18])] = SAND
        cheeks = np.isin(islands, [21, 22])
        color[cheeks] = SAND
        color[cheeks & (ny < .0)] = SKIRT
        color[cheeks & (x > .003) & (nx > .75) & (y > .406) & (y < .43)] = OPTIC
        rails = np.isin(islands, [0, 1])
        color[rails & (x < .27)] = SAND
        color[rails & (x > .317) & (x < .355)] = STEEL
        color[rails & (x > .418) & (nx < .65)] = SKIRT
        color[rails & (x > .462) & (nx > .75)] = TREAD
        color[np.isin(islands, [4, 5])] = STEEL
        color[islands == 6] = SKIRT
        color[(islands == 6) & (ny > .34)] = SAND
    else:
        raise ValueError(f"Unknown tank source form {form!r}")
    # Builder-generated interior faces retain a dark metal finish when pieces detach.
    color[islands < 0] = FRAME
    return color


def painted_surface(part, triangles, form, islands):
    """Split long source triangles at paint edges, preserving surface shape and interpolated normals."""
    ids = np.broadcast_to(islands[:, None, None], (*triangles.shape[:2], 1))
    surface = np.concatenate((triangles, ids), axis=2)
    if form == "mobile":
        # Some scan faces run all the way along a barrel or track guard. Sampling
        # those faces once would turn the straight collars and stripes into triangles.
        edges = [([50], 0, [.179, .221, .232, .288, .326, .40]),
                 ([0], 0, [.26, .288]), ([33], 1, [.475, .551])]
    else:
        edges = [([0, 1], 0, [.27, .317, .355, .418, .462]),
                 ([2, 3], 0, [.26, .288]), ([21, 22], 1, [.406, .43]),
                 ([7], 1, [.176, .267, .344, .447])]
    for selection, axis, planes in edges:
        selected = np.isin(surface[:, 0, 6], selection)
        if not selected.any():
            continue
        strip = surface[selected]
        for offset in planes:
            coordinates = strip[:, :, axis]
            crossing = (coordinates.min(1) < offset) & (coordinates.max(1) > offset)
            if crossing.any():
                front, back = divide(strip[crossing], np.eye(3)[axis], offset, close=False)
                strip = np.concatenate((strip[~crossing], front, back))
        surface = np.concatenate((surface[~selected], strip))
    geo = surface[:, :, :6]
    colors = paint(part, geo[:, :, :3].mean(1), face_normals(geo), form, surface[:, 0, 6])
    return geo, colors
