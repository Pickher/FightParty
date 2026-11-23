"""Physical finishes and inset hardware for the two poses of the Viking airframe."""
import numpy as np

from build_marauder_rig import mark
from hellbat_mech_paint import _material
from rigid_glb import face_normals, orient_axis

BLUE, SHADOW, RED, FRAME, STEEL, SOLE, TEAL, GLASS, WHITE, HOT = range(10)
MATERIALS = [
    _material("Slate flight armor", (108, 133, 151), .49, .43),
    _material("Deep blue plating", (63, 84, 103), .47, .46),
    _material("Oxide red squadron paint", (160, 76, 63), .35, .41),
    _material("Gunmetal recess", (47, 56, 66), .58, .54),
    _material("Machined steel", (148, 160, 169), .69, .39),
    _material("Carbon", (34, 39, 46), .13, .75),
    _material("Blue-green canopy", (54, 141, 153), .42, .23, (.012, .040, .049)),
    _material("Smoked glass", (27, 67, 83), .49, .27),
    _material("Warm recognition stripe", (215, 211, 188), .27, .43),
    _material("Turbine throat", (95, 184, 228), .28, .32, (.04, .26, .44)),
]


def join(*groups):
    return tuple(np.concatenate(items) for items in zip(*groups))


def unit(v):
    vec = np.asarray(v, dtype=float)
    return vec / np.linalg.norm(vec)


def paint(part, group):
    tri, ids = group
    x, y, z = tri[:, :, :3].mean(1).T
    nx, ny, nz = face_normals(tri).T
    side = np.abs(z)
    colors = np.full(len(tri), BLUE, dtype=int)
    if part == "Pelvis" or part.startswith("Hip"):
        colors[:] = FRAME
    elif part.startswith("Knee"):
        colors[:] = SHADOW
        colors[np.isin(ids, (7, 20))] = BLUE
        colors[np.isin(ids, (22, 16))] = STEEL
        colors[np.isin(ids, (11, 12, 17, 18, 19))] = FRAME
    elif part.startswith("Ankle"):
        colors[:] = SHADOW
    elif part.startswith("Engine"):
        colors[:] = RED
    elif part.startswith("Shoulder"):
        colors[:] = SHADOW
        colors[np.isin(ids, (9, 10, 13, 14))] = STEEL
    elif part.startswith("Gun"):
        colors[:] = STEEL
        colors[np.isin(ids, (25, 26))] = SHADOW
    elif part.startswith("Tail"):
        colors[:] = RED
    colors[ids == -1] = FRAME
    surface = np.concatenate([tri, np.broadcast_to(colors[:, None, None], (len(tri), 3, 1))], axis=2)
    if part == "Trunk" or part == "Nose":
        # A smoke-glass windshield, separate from the armored spine. Clip the
        # shape, its frame and center mullion into the uploaded cockpit surface.
        panes = [((1,.42,0), .365), ((-1,-.42,0),-.552),
                 ((-.25,1,0), .613), ((.25,-1,0),-.873),
                 ((0,.08,1),-.042), ((0,.08,-1),-.042)]
        surface = mark(surface, ids != -1, panes, FRAME)
        inset = [(a, v+.012) for a,v in panes]
        for sign in [1,-1]:
            surface = mark(surface, surface[:,0,6]==FRAME,
                           inset+[((0,0,sign),.006)], GLASS)
            surface = mark(surface, surface[:,0,6]==GLASS,
                           [((1,.39,sign*.33),.358),((-1,-.39,-sign*.33),-.39),
                            ((0,0,sign),.018)], TEAL)
        for sign in [1,-1]:
            surface = mark(surface, surface[:,0,6]==BLUE,
                           [((0,0,sign),.126), ((.63,1,0),.64)], SHADOW)
            surface = mark(surface, surface[:,0,6]==SHADOW,
                           [((1,.34,0),.27), ((-1,-.34,0),-.329)], RED)
    elif part.startswith("Engine"):
        surface = mark(surface, ids!=-1, [((-1,.08,0),.209)], SHADOW)
        surface = mark(surface, surface[:,0,6]==RED, [((1,.28,0),.09),((-1,-.28,0),-.103)], WHITE)
    elif part.startswith("Knee"):
        surface = mark(surface, np.isin(ids,(1,8)), [((0,1,0),.264),((0,-1,0),-.343)], RED)
    elif part.startswith("Wing"):
        surface = mark(surface, ids != -1, [((-.19, 1, 0), .405 if part.endswith("P") else .379),
                                           ((.19, -1, 0), -.428 if part.endswith("P") else -.402)], WHITE)
    return surface[:, :, :6], surface[:, 0, 6].astype(int)


def surfaces(faces, colors):
    triangles = np.asarray(faces, dtype=float)
    normals = face_normals(triangles)
    return np.concatenate((triangles, np.broadcast_to(normals[:, None, :], triangles.shape)), axis=2), np.asarray(colors)


def loft(center, axis, profile, sides=12):
    """Closed, concentric rings. Radius may be elliptical for a nested canopy spine."""
    frame = orient_axis(unit(axis))
    theta = (np.arange(sides) + .5) * (2*np.pi/sides)
    rings = []
    for s, height, width, _ in profile:
        rings.append(center + frame[:, 0]*s + np.outer(np.cos(theta), frame[:, 1])*height +
                     np.outer(np.sin(theta), frame[:, 2])*width)
    faces, colors = [], []
    for k, (a, b) in enumerate(zip(rings, rings[1:])):
        for i in range(sides):
            j = (i+1) % sides
            faces.extend(((a[i], a[j], b[j]), (a[i], b[j], b[i])))
            colors.extend((profile[k][3], profile[k][3]))
    for ring, swatch, reverse in [(rings[0], profile[0][3], True), (rings[-1], profile[-1][3], False)]:
        for i in range(1, sides-1):
            a,b=ring[i],ring[i+1]
            faces.append((ring[0], b, a) if reverse else (ring[0], a, b))
            colors.append(swatch)
    return surfaces(faces, colors)


def swept_panel(stations, side, panel):
    """Airfoil sections with a cambered leading edge and a thin shadowed trailing edge.

    Stations are (span, front X, back X) in level aircraft space. Each half folds
    on its own root under the shoulder armor; together they make the full delta.
    """
    faces, colors, rings = [], [], []
    sections = [(0,.0), (.10,.010), (.70,.014), (1,.0), (.75,-.009), (.12,-.010)]
    for span, nose, tail in stations:
        rings.append(np.array([[nose+(tail-nose)*t,.423+.026*(span-.145)+h,side*span]
                               for t,h in sections]))
    for k,(a,b) in enumerate(zip(rings,rings[1:])):
        for i in range(len(sections)):
            j=(i+1)%len(sections)
            coat = STEEL if i == 0 else BLUE if i<3 else SHADOW
            if panel == "flap" and i == 2:
                coat = FRAME
            if panel == "glove" and k==2 and i in (1,2):
                coat = SHADOW
            if panel == "tip" and i<3:
                coat = RED if k>=3 else WHITE if k==2 else coat
            faces.extend(((a[i],a[j],b[j]), (a[i],b[j],b[i])))
            colors.extend((coat,coat))
    for ring, root_face in ((rings[0],True),(rings[-1],False)):
        for i in range(1,len(sections)-1):
            faces.append((ring[0],ring[i+1],ring[i]) if root_face else (ring[0],ring[i],ring[i+1]))
            colors.append(FRAME)
    tri,cols = surfaces(faces,colors)
    if side < 0:
        tri = tri[:,::-1].copy()
        tri[:,:,3:] *= -1
    return tri,cols


def sliding_cheeks(cap, center, axis):
    """Fit the hidden telescoping sleeve to the exact perimeter of the nose cut."""
    cut = cap[0][cap[1] == -1,:,:3]
    cut = cut[np.abs((cut - center) @ axis).max(1) < .00001]
    points, index = np.unique(np.round(cut,7).reshape(-1,3),axis=0,return_inverse=True)
    f = index.reshape(-1,3)
    edges = np.sort(np.column_stack((f.ravel(),f[:,[1,2,0]].ravel())),axis=1)
    edges, counts = np.unique(edges,axis=0,return_counts=True)
    faces, colors = [], []
    for i,j in edges[counts==1]:
        a,b=points[[i,j]]
        for lo,hi,scale0,scale1,color in [(-.025,.01,.94,.96,SHADOW),
                (.01,.055,.96,.96,BLUE),(.055,.061,.96,.96,STEEL),
                (.061,.09,.96,.93,BLUE),(.09,.118,.93,.88,FRAME)]:
            v=np.array([center+(a-center)*scale0+axis*lo,center+(b-center)*scale0+axis*lo,
                        center+(b-center)*scale1+axis*hi,center+(a-center)*scale1+axis*hi])
            normal=np.cross(v[1]-v[0],v[2]-v[0])
            radial=v.mean(0)-center;radial-=axis*(radial@axis)
            if normal@radial<0:v=v[::-1]
            faces.extend((v[[0,1,2]],v[[0,2,3]]));colors.extend([color,color])
    return surfaces(faces,colors)
