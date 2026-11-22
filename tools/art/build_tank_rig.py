"""Build a single mechanically articulated tank from the mobile and siege uploads.

Python 3, NumPy and SciPy. The two originals have different tessellations and
opposite forward axes. Rig space is +X forward, +Y up, +Z toward the P side.
Every physical part is rigid and remains on the chassis in both poses.
"""
from pathlib import Path

import numpy as np
from scipy.spatial import ConvexHull


from hellbat_mech_joints import split_joint
from rigid_glb import Rig, load_surface, matrix, orient_axis
from tank_paint import FRAME, MARK, MATERIALS, SAND, SKIRT, STEEL, painted_surface

DIRECTORY = Path(__file__).resolve().parents[2] / "assets/models/mortar"
ROOT = "MortarRig"
UP = np.array([0., 1., 0.])
X = np.array([1., 0., 0.])
Z = np.array([0., 0., 1.])


def subset(source, islands):
    triangles, ids = source
    choose = np.isin(ids, islands)
    return triangles[choose], ids[choose]


def join(*groups):
    return tuple(np.concatenate(parts) for parts in zip(*groups))


def cut(group, axis, station):
    return split_joint(*group, np.array(axis) * station, axis)


def source_groups():
    mobile = load_surface(DIRECTORY / "mortar.glb", 74)
    siege = load_surface(DIRECTORY / "mortar_siege.glb", 27)
    # Rotate both normals and positions; IDs continue to refer to the source GLB.
    siege[0][:, :, [0, 2, 3, 5]] *= -1.
    m, s = {}, {}
    shell = subset(mobile, [0])
    for side, suffix in [(1, "P"), (-1, "N")]:
        # Only the travelling model's front bogies are fused to its body. Cut
        # behind their armour and to the inside of their rubber, then cap both
        # newly exposed interfaces. The independent rear bogies come from siege.
        outboard, shell = cut(shell, side * Z, .0973)
        front, _ = cut(outboard, X, .0917)
        ribs = range(65, 74) if side == 1 else range(56, 65)
        m["TrackFront" + suffix] = join(front, subset(mobile, ribs))
        m["Arm" + suffix] = subset(mobile, [32, 42] if side == 1 else [31, 41])
        s["TrackRear" + suffix] = subset(siege, [24, 25] if side == 1 else [23, 26])
        s["Arm" + suffix] = subset(siege, [11, 13, 15, 17] if side == 1 else [12, 14, 16, 18])
        s["Foot" + suffix] = subset(siege, [9, 19] if side == 1 else [10, 20])
        s["Barrel" + suffix] = subset(siege, [0, 4] if side == 1 else [1, 5])
    m["Turret"] = subset(mobile, [33, 35, 36, 37, 38, 39, 40, 46, 47, 48, 49])
    m["Mount"] = subset(mobile, [44])
    # The mobile twin muzzles flank the travel jacket on the same welded island.
    m["BarrelP"], gun = cut(subset(mobile, [50]), Z, .0425)
    m["BarrelN"], m["CenterBarrel"] = cut(gun, -Z, .0445)
    _, s["Hull"] = cut(subset(siege, [7]), UP, .3521)
    s["CenterBarrel"] = subset(siege, [6, 8])
    return m, s


def local(points, frame):
    return (points - frame[:3, 3]) @ frame[:3, :3]


def perimeter(points, stations):
    lengths = np.linalg.norm(np.roll(points, -1, axis=0) - points, axis=1)
    edges = np.r_[0, lengths.cumsum()]
    at = np.arange(stations) * edges[-1] / stations
    i = np.searchsorted(edges[1:], at)
    u = ((at-edges[i]) / lengths[i])[:,None]
    return points[i] + u * (points[(i+1)%len(points)] - points[i])


def track_path(bank, frame, name, form):
    points = local(bank[0][:,:,:3], frame).reshape(-1, 3)
    if form == "mobile":
        side = 1 if name.endswith("P") else -1
        # Measured around the tyre, behind the original overhanging nose guard.
        outline = [[.441,.047],[.285,.034],[.132,.046],[.100,.071],[.099,.17],
                   [.133,.255],[.194,.270],[.309,.229],[.407,.180],[.478,.147],
                   [.493,.110],[.480,.070]]
        width = .106
        world = np.column_stack((outline, np.full(len(outline),side*.154)))
        return perimeter(local(world, frame),16), width

    # The two siege-source rear bogies have different native splay angles. Their longitudinal section
    # gives the rubber's true sloping bottom and nose; tuck the return under
    # the painted upper guard while preserving the original ground contact.
    zlo, zhi = np.percentile(points[:,2], [5,95])
    center_z = (zlo+zhi)*.5
    width = (zhi-zlo)*.73
    sel = np.abs(points[:,2]-center_z) < (zhi-zlo)*.47
    xy = points[sel, :2]
    hull = xy[ConvexHull(xy).vertices]
    samples = []
    for fraction in [.935,.70,.40,.16,.055,.018,.065,.17,.42,.68,.86,.965,.986]:
        x = np.min(xy[:,0]) + fraction * np.ptp(xy[:,0])
        cuts = []
        for a,b in zip(hull,np.roll(hull,-1,axis=0)):
            if (a[0]-x)*(b[0]-x) < 0:
                cuts.append(a[1] + (x-a[0])*(b[1]-a[1])/(b[0]-a[0]))
        lo, hi = min(cuts),max(cuts)
        i = len(samples)
        blend = 0.0 if i < 5 else .32 if i in (5,12) else .72
        samples.append([x,lo+(hi-lo)*blend,center_z])
    return perimeter(np.asarray(samples),16), width


def pin(x, z, height_radius, finishes, sides=12):
    """Stack turned vertical rings; the rim, fastener and bright shoulder share one mesh."""
    rows, colors = [], []
    circle = np.arange(sides) * (2*np.pi/sides)
    rings = [np.column_stack([x + radius*np.cos(circle), np.full(sides, h), z + radius*np.sin(circle)])
             for h, radius in height_radius]
    for k, (bottom, top) in enumerate(zip(rings, rings[1:])):
        for j in range(sides):
            next_j = (j + 1) % sides
            rows.extend([[bottom[j], top[j], top[next_j]], [bottom[j], top[next_j], bottom[next_j]]])
            colors.extend([finishes[k], finishes[k]])
    # Winding is counter-clockwise viewed from outside in the glTF basis.
    for ring, end, color in [(rings[0], -1, finishes[0]), (rings[-1], 1, finishes[-1])]:
        center = ring.mean(0)
        for j in range(sides):
            a, b = ring[j], ring[(j+1)%sides]
            rows.append([center, a, b] if end < 0 else [center, b, a])
            colors.append(color)
    return machined(rows, colors)


def machined(rows, colors):
    xyz = np.asarray(rows, dtype=float)
    n = np.cross(xyz[:,1]-xyz[:,0], xyz[:,2]-xyz[:,0])
    n /= np.maximum(np.linalg.norm(n,axis=1)[:,None], 1e-12)
    return np.concatenate((xyz, np.broadcast_to(n[:,None,:], xyz.shape)), axis=2), np.asarray(colors)


def link_plate(root, axle):
    """Dog-bone swing arm and bevels milled into its lower and upper edges."""
    vec = axle-root
    along = vec/np.linalg.norm(vec)
    across = np.cross(along, UP)
    # Along/across outline starts at root's trailing side.
    length = np.linalg.norm(vec)
    outline = np.array([[-.021,-.023],[.009,-.026],[length-.005,-.018],[length+.016,-.012],
                        [length+.020,.011],[length-.005,.020],[.009,.026],[-.021,.023]])
    center = np.array([length*.5,0.])
    slices = []
    for y, inset in [(-.014, .91), (-.009, 1.), (.009, 1.), (.014, .91)]:
        points = center + (outline-center)*inset
        slices.append(root + points[:,0,None]*along + points[:,1,None]*across + UP*y)
    rows, colors = [], []
    for k,(a,b) in enumerate(zip(slices,slices[1:])):
        for j in range(len(a)):
            n = (j+1)%len(a)
            rows.extend([[a[j],b[j],b[n]],[a[j],b[n],a[n]]])
            colors.extend([STEEL if k != 1 else FRAME]*2)
    for ring, upper in [(slices[0],False),(slices[-1],True)]:
        for j in range(len(ring)):
            a,b = ring[j],ring[(j+1)%len(ring)]
            rows.append([ring.mean(0),b,a] if upper else [ring.mean(0),a,b])
            colors.append(SKIRT if upper else FRAME)
    return machined(rows,colors)


HULL_BIND = matrix([-.030,.237,0.])
# Register the actual common turret bearing with both uploaded turret heights.
HULL_DEPLOY = matrix([-.006,.162,.0047])
HULL_SHIFT = HULL_DEPLOY[:3,3] - HULL_BIND[:3,3]


def track_parts(mobile, siege):
    """Two pins and a constant-length swing arm per pod, with the deck's true sag.

    Each fixed inner bearing is on the perpendicular bisector of the open/closed
    pod pin. Both suspension positions thus fit the same metal link, and the pod
    only needs to turn about the second physical pin as its toe swings outward.
    """
    tracks, collars = [], []
    for side, suffix in [(1,"P"),(-1,"N")]:
        for front, label in [(True,"Front"),(False,"Rear")]:
            name = "Track"+label+suffix
            if front:
                # The detailed nose track and the overhanging fender stay bolted.
                group = mobile[name]
                source = matrix([.130,.223,side*.154])
                bind = matrix([.130,.195,side*.154])
                target = matrix([.104,.198,.0047+side*.104],
                                orient_axis(np.array([.7314,0.,side*.6820])))
                form = "mobile"
            else:
                # The siege upload has a complete rear bogie down to the idler.
                # Use the same pod when parallel in road gear and splayed in siege.
                group = siege[name]
                source = matrix([-.207,.202,.0047+side*.106],
                                orient_axis(np.array([.761,0.,-side*.649])))
                bind = matrix([-.171,.193,side*.151])
                target = matrix([-.132,.202,.0047+side*.113],
                                orient_axis(np.array([.7193,0.,-side*.6947])))
                form = "siege"
            p = bind[:3,3].copy()
            q = target[:3,3].copy() - HULL_SHIFT
            # The suspension plunger compensates for the hull dropping on its jacks.
            q[1] = p[1]
            chord = q - p
            perpendicular = np.cross(chord, UP)
            perpendicular /= np.linalg.norm(perpendicular)
            if side*perpendicular[2] > 0:
                perpendicular = -perpendicular
            r = .091
            bearing = (p+q)*.5 + np.sqrt(r*r - np.linalg.norm(chord)**2*.25)*perpendicular
            end_bearing = bearing + HULL_SHIFT
            end_bearing[1] = target[1,3]
            crank_bind = matrix(bearing, orient_axis(p-bearing))
            crank_end = matrix(end_bearing, orient_axis(target[:3,3]-end_bearing))
            crank = "Crank"+label+suffix
            steel = join(link_plate(bearing,p),
                         pin(bearing[0],bearing[2],[(p[1]-.021,.028),(p[1]-.016,.032),
                             (p[1]+.019,.032),(p[1]+.025,.025),(p[1]+.117,.020)],
                             [STEEL,SKIRT,STEEL,STEEL]),
                         pin(p[0],p[2],[(p[1]-.022,.021),(p[1]-.018,.025),
                             (p[1]+.017,.025),(p[1]+.023,.019),(p[1]+.026,.013)],
                             [STEEL,FRAME,STEEL,MARK]))
            tracks.append((crank, "Hull", "painted", steel, crank_bind, crank_bind, crank_end))
            tracks.append((name, crank, form, group, source, bind, target))
            # Permanently fixed receiver collar around the plunger: all collars
            # share the draw with the original hull. The mobile/deployed link's
            # vertical travel occurs inside the collar.
            bx, _, bz = end_bearing
            collars.append(pin(bx,bz,[(.212,.030),(.216,.035),(.246,.035),
                                      (.252,.030),(.287,.029),(.291,.025)],
                               [STEEL,FRAME,STEEL,SKIRT,STEEL]))
    return tracks, collars


class Assembly:
    def __init__(self):
        self.rig = Rig(MATERIALS, "Mortar")
        self.rig.node(ROOT, None, np.eye(4))

    def part(self, name, parent, form, group, source_frame, bind_frame, deployed_frame):
        for frame in (source_frame, bind_frame, deployed_frame):
            assert np.allclose(frame[:3,:3].T @ frame[:3,:3], np.eye(3), atol=1e-6)
            assert np.isclose(np.linalg.det(frame[:3,:3]), 1.)
        assert len(group[0]) and name not in self.rig.index, name
        self.rig.node(name, parent, bind_frame)
        geometry = group if form == "painted" else painted_surface(name, group[0], form, group[1])
        self.rig.mesh(name, *geometry, source_frame)
        self.rig.node("Deploy"+name, ROOT, deployed_frame)

    def socket(self, name, parent, parent_local):
        self.rig.node(name, parent, self.rig.frames[parent] @ parent_local)


def build():
    from tank_bogies import bogie_detail
    from tank_gun import gun_parts
    from tank_outriggers import outrigger_parts
    mobile, siege = source_groups()
    tracks, collars = track_parts(mobile,siege)
    assembler = Assembly()
    source_hull = siege["Hull"]
    hull_paint = painted_surface("Hull", source_hull[0], "siege", source_hull[1])
    assembler.part("Hull", ROOT, "painted", join(hull_paint,*collars),
                   HULL_DEPLOY, HULL_BIND, HULL_DEPLOY)
    for name, parent, form, group, source, bind, target in tracks:
        if name.startswith("Track"):
            original = painted_surface(name, group[0], form, group[1])
            assembled = join(original, bogie_detail(group,source,name))
            assembler.part(name, parent, "painted", assembled, source, bind, target)
            loop, width = track_path(group,source,name,form)
            for i, p in enumerate(loop):
                assembler.socket(name+"Path%02d"%i, name, matrix(p))
            assembler.socket(name+"TrackWidth", name, matrix([0.,0.,width]))
        else:
            assembler.part(name, parent, form, group, source, bind, target)
    outrigger_parts(mobile, siege, assembler.part, assembler.socket)
    gun_parts(mobile, siege, assembler.part, assembler.socket)
    assembler.rig.write(DIRECTORY/"mortar_rig.glb")


if __name__ == "__main__":
    build()
