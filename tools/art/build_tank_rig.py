"""Build the two-pose Siege Tank from the actual mobile and deployed uploads.

Python 3, NumPy and SciPy. The two originals have different tessellations and
opposite forward axes. Rig space is +X forward, +Y up, +Z toward the P side.
"""
from pathlib import Path

import numpy as np
from scipy.spatial import ConvexHull, cKDTree
from scipy.spatial.transform import Rotation

from hellbat_mech_joints import split_joint
from rigid_glb import Rig, load_surface, matrix, orient_axis
from tank_paint import MATERIALS, painted_surface

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
    body = []
    for side, suffix in [(1, "P"), (-1, "N")]:
        # The source's four tracks are cast into its hull. Open the side seam
        # inboard of the tread, and the two concealed transitions at the deck.
        outboard, shell = cut(shell, side * Z, .0973)
        front, other = cut(outboard, X, .0917)
        rear, center = cut(other, -X, .2021)
        body.append(center)
        nose_ribs = range(65, 74) if side == 1 else range(56, 65)
        tail_ribs = [3, 4, 7, 8, 16, 17, 19, 23, 24, 25, 26, 28] if side == 1 else [
            1, 2, 5, 6, 12, 13, 14, 15, 18, 20, 21, 22, 27]
        m["TrackFront" + suffix] = join(front, subset(mobile, nose_ribs))
        m["TrackRear" + suffix] = join(rear, subset(mobile, tail_ribs))
        # Large travelling shoes nest below the hard-sided upper jack. Both
        # are genuine islands in the original; the deployed scan adds its rams.
        m["Arm" + suffix] = subset(mobile, [32, 42] if side == 1 else [31, 41])
        m["Foot" + suffix] = subset(mobile, [30] if side == 1 else [29])
        s["TrackFront" + suffix] = subset(siege, [2] if side == 1 else [3])
        s["TrackRear" + suffix] = subset(siege, [24, 25] if side == 1 else [23, 26])
        s["Arm" + suffix] = subset(siege, [11, 13, 15, 17] if side == 1 else [12, 14, 16, 18])
        s["Foot" + suffix] = subset(siege, [9, 19] if side == 1 else [10, 20])
        s["Barrel" + suffix] = subset(siege, [0, 4] if side == 1 else [1, 5])
    m["Hull"] = join(shell, *body, subset(mobile, [9, 10, 11, 34, 43, 45, 51, 52, 53, 54, 55]))
    m["Turret"] = subset(mobile, [33, 35, 36, 37, 38, 39, 40, 46, 47, 48, 49])
    m["Mount"] = subset(mobile, [44])
    # Isolate the two optical-square muzzles from the connecting middle sleeve.
    m["BarrelP"], gun = cut(subset(mobile, [50]), Z, .0425)
    m["BarrelN"], m["CenterBarrel"] = cut(gun, -Z, .0445)
    turret, s["Hull"] = cut(subset(siege, [7]), UP, .3521)
    s["Turret"] = turret
    s["Mount"] = subset(siege, [21, 22])
    s["CenterBarrel"] = subset(siege, [6, 8])
    for source, pieces in [(mobile, m), (siege, s)]:
        # Every original island must appear on the assembled vehicle.
        assert set(np.unique(source[1])) == set(np.unique(np.concatenate([g[1] for g in pieces.values()]))) - {-1}
    return m, s


def frames():
    bind, deploy, parents = {}, {}, {}

    def add(name, parent, mobile, siege, mobile_forward=X, siege_forward=X):
        parents[name] = parent
        bind[name] = matrix(mobile, orient_axis(mobile_forward.copy()))
        deploy[name] = matrix(siege, orient_axis(siege_forward.copy()))

    add("Hull", ROOT, [-.03, .237, 0], [-.038, .203, .0046])
    add("Turret", "Hull", [-.074, .429, -.0008], [-.05, .3521, .0047])
    mobile_bore = np.array([1., -.069, 0.])
    siege_bore = np.array([1., .420, 0.])
    add("Mount", "Turret", [.0295, .486, -.0008], [.108, .401, .0047],
        mobile_bore, siege_bore)
    for side, suffix in [(1, "P"), (-1, "N")]:
        z = lambda distance: .0047 + side * distance
        add("Barrel" + suffix, "Mount", [.060, .502, -.001 + side * .088],
            [.147, .432, z(.110)], mobile_bore, siege_bore)
        add("TrackFront" + suffix, "Hull", [.134, .228, side * .108],
            [.167, .222, z(.103)], X, np.array([.802, 0., side * .597]))
        add("TrackRear" + suffix, "Hull", [-.234, .282, side * .107],
            [-.210, .208, z(.098)], X, np.array([.761, 0., -side * .649]))
        add("Arm" + suffix, "Hull", [-.066, .390, side * .253],
            [.001, .278, z(.228)], X, np.array([1., 0., 0.]))
        # Mobile shoe's long axis is X; in battery the real outer plate is laid
        # flat under the ram. Its local Z axis rolls into +Y as it unfolds.
        add("Foot" + suffix, "Arm" + suffix, [-.079, .196, side * .176],
            [.003, .071, z(.321)])
        deploy["Foot" + suffix][:3, :3] = Rotation.from_rotvec(-side * 1.13 * X).as_matrix()
        deploy["Arm" + suffix][:3, :3] = Rotation.from_rotvec(side * -.64 * X).as_matrix()
    add("CenterBarrel", "Mount", [.060, .506, -.001], [.146, .437, .0047],
        mobile_bore, siege_bore)
    return parents, bind, deploy


def local(points, frame):
    return (points - frame[:3, 3]) @ frame[:3, :3]


def point_on_candidates(points, triangles):
    """Closest point on each of the K candidate triangles, including skinny bevels."""
    p = points[:, None, :]
    a, b, c = (triangles[:, :, i] for i in range(3))
    ab, ac = b - a, c - a
    signed = np.cross(ab, ac)
    norm2 = (signed * signed).sum(2, keepdims=True)
    projected = p - signed * ((p-a)*signed).sum(2, keepdims=True) / np.maximum(norm2, 1e-20)
    inside = norm2[:, :, 0] > 1e-20
    edges = [(a,b), (b,c), (c,a)]
    alternatives = [projected]
    for start, end in edges:
        along = end - start
        inside &= (np.cross(along, projected - start) * signed).sum(2) >= -1e-12
        ratio = ((p - start) * along).sum(2, keepdims=True) / np.maximum((along * along).sum(2, keepdims=True), 1e-20)
        alternatives.append(start + np.clip(ratio, 0, 1) * along)
    choices = np.stack(alternatives, axis=2)
    distances = ((choices - p[:, :, None])**2).sum(3)
    distances[:, :, 0] = np.where(inside, distances[:, :, 0], np.inf)
    take = distances.reshape(len(points), -1).argmin(1)
    return choices[np.arange(len(points)), take // 4, take % 4]


def transition_delta(current, other):
    """Transport both triangulations to a common mid-sized shell in joint space.

    Normalizing each hard part around its own envelope prevents a long sleeve or
    folded foot from snapping to an unrelated neighbouring part. A nearest actual
    face (not its triangle center) retains edges and broad armour plates.
    """
    p, index = np.unique(current.reshape(-1, 3), axis=0, return_inverse=True)
    q = other.reshape(-1, 3)
    low, high = p.min(0), p.max(0)
    low2, high2 = q.min(0), q.max(0)
    center, center2 = (low + high) * .5, (low2 + high2) * .5
    extent, extent2 = np.maximum(high-low, 1e-5), np.maximum(high2-low2, 1e-5)
    query = (p-center)/extent
    target = (other-center2)/extent2
    # A centroid tree plus incident-face candidates at the closest vertex also
    # finds large flat plates whose centers lie well away from an edge detail.
    tree = cKDTree(target.mean(1))
    corner_tree = cKDTree(target.reshape(-1, 3))
    hits = []
    for batch in np.array_split(query, max(1, (len(query)+799)//800)):
        faces = tree.query(batch, k=min(12,len(target)))[1]
        corners = corner_tree.query(batch, k=min(12,3*len(target)))[1] // 3
        pick = np.column_stack((faces, corners))
        hits.append(point_on_candidates(batch, target[pick]))
    matched = np.concatenate(hits)
    middle = (query + matched) * .25 * (extent+extent2) + (center+center2) * .5
    return (middle-p)[index].reshape(current.shape)


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
        front = name.startswith("TrackFront")
        side = 1 if name.endswith("P") else -1
        # Key stations on the outer rubber, below the overhanging fender. The
        # source's rear bogie rests higher than its nose; preserve this profile.
        outline = ([[.441,.047],[.285,.034],[.132,.046],[.100,.071],[.099,.17],
                    [.133,.255],[.194,.270],[.309,.229],[.407,.180],[.478,.147],
                    [.493,.110],[.480,.070]] if front else
                   [[-.255,.160],[-.362,.161],[-.452,.165],[-.482,.19],
                    [-.493,.227],[-.471,.281],[-.405,.323],[-.323,.350],
                    [-.275,.354],[-.221,.319],[-.214,.254],[-.224,.201]])
        width = .106 if front else .104
        midz = side * (.154 if front else .136)
        world = np.column_stack((outline, np.full(len(outline), midz)))
        return perimeter(local(world, frame),16), width

    # Deployed bogies have unique splay angles. Their longitudinal section
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


def build():
    mobile, siege = source_groups()
    parents, bind, deploy = frames()
    rig = Rig(MATERIALS, "Mortar")
    rig.node(ROOT, None, np.eye(4))
    for name, parent in parents.items():
        rig.node(name, parent, bind[name])
        forms = []
        for form, groups, frame in [("mobile", mobile, bind), ("siege", siege, deploy)]:
            tri, tags = groups[name]
            tri, colors = painted_surface(name, tri, form, tags)
            forms.append((tri, colors, frame[name], local(tri[:,:,:3], frame[name])))
        for i, (tri, colors, frame, positions) in enumerate(forms):
            suffix = "Mobile" if i == 0 else "Siege"
            alias = name + suffix
            # Bind both skins directly to the same rotating physical joint.
            rig.index[alias], rig.frames[alias] = rig.index[name], bind[name]
            delta = transition_delta(positions, forms[1-i][3])
            rig.mesh(alias, tri, colors, frame, delta)
            mesh = rig.meshes[-1]
            mesh["weights"] = [0.]
            mesh["extras"]["targetNames"] = ["ChangeShell"]
        rig.node("Deploy" + name, ROOT, deploy[name])
        if name.startswith("Track"):
            for prefix, groups, frame in [("", mobile, bind), ("Siege", siege, deploy)]:
                path, width = track_path(groups[name], frame[name], name, "mobile" if not prefix else "siege")
                for i, p in enumerate(path):
                    rig.node(name + prefix + "Path%02d" % i, name, bind[name] @ matrix(p))
                rig.node(name + prefix + "TrackWidth", name, bind[name] @ matrix([0.,0.,width]))
    for side, suffix in [(1,"P"),(-1,"N")]:
        name = "Barrel" + suffix
        muzzle = matrix([.416,.476,side*.092-.001], bind[name][:3,:3])
        rig.node("MobileMuzzle"+suffix, name, muzzle)
        foot = "Foot"+suffix
        contact = matrix([.003,0.0,side*.405+.0047])
        rig.node("Contact"+suffix, foot, bind[foot] @ np.linalg.inv(deploy[foot]) @ contact)
    # The open siege rails flank a single bore. Keep a second mark at the
    # energized rail exit, allowing effects to travel through the visible gap.
    name = "CenterBarrel"
    for marker, pos in [("SiegeBreech",[.364,.506,.0047]),("SiegeMuzzle",[.492,.560,.0047])]:
        socket = matrix(pos, deploy[name][:3,:3])
        rig.node(marker,name,bind[name] @ np.linalg.inv(deploy[name]) @ socket)
    rig.write(DIRECTORY / "mortar_rig.glb")


if __name__ == "__main__":
    build()
