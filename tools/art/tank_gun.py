"""Rigid turret, split travel jacket and telescoping siege gun for the Siege Tank."""
import math

import numpy as np
from scipy.spatial.transform import Rotation

from hellbat_mech_joints import split_joint
from rigid_glb import matrix, orient_axis
from tank_paint import FRAME, SKIRT, STEEL, TREAD, painted_surface


MOBILE_AXIS = orient_axis(np.array([1.0, -.069, 0.0]))
SIEGE_AXIS = orient_axis(np.array([1.0, .420, 0.0]))


def _frame_on_axis(basis, along, height, lateral):
    return matrix(basis @ np.array([along, height, lateral]), basis)


def _ring_barrel():
    """A stepped jacket and a deep open bore. All stations are machined into one rigid tube."""
    sections = 12
    profile = [
        # (distance along bore, radius, material up to the next station)
        (0.0, .0320, FRAME), (.027, .0320, STEEL), (.030, .0292, STEEL),
        (.075, .0292, FRAME), (.080, .0250, FRAME), (.129, .0250, STEEL),
        (.132, .0232, STEEL), (.164, .0232, FRAME), (.171, .0302, FRAME),
        (.204, .0302, STEEL), (.209, .0270, STEEL), (.209, .0179, TREAD),
        (.174, .0179, TREAD), (.174, .0011, TREAD),
    ]
    rings = []
    for x, radius, _ in profile:
        angle = (np.arange(sections) + .5) * (2 * math.pi / sections)
        rings.append(np.column_stack((np.full(sections, x), radius * np.cos(angle), radius * np.sin(angle))))
    triangles, colors = [], []
    for i, (back, front) in enumerate(zip(rings, rings[1:])):
        for j in range(sections):
            k = (j + 1) % sections
            for corners in [(back[j], back[k], front[k]), (back[j], front[k], front[j])]:
                vertices = np.asarray(corners)
                normal = np.cross(vertices[1] - vertices[0], vertices[2] - vertices[0])
                normal /= np.linalg.norm(normal)
                triangles.append(np.column_stack((vertices, np.tile(normal, (3, 1)))))
                colors.append(profile[i][2])
    return (np.asarray(triangles), np.asarray(colors)), profile[-4][0]


def _hatch_surface(name, group, side):
    """Mill both exposed faces below the original closed jacket envelope."""
    tri, colors = painted_surface(name, group[0], "mobile", group[1])
    # Bore coordinates make the hat-section stiffeners follow the jacket slope.
    model = tri[:, :, :3] @ MOBILE_AXIS
    pieces, finishes = [], []

    def face(vertices, color, outward=None):
        points = np.asarray(vertices) @ MOBILE_AXIS.T
        normal = np.cross(points[1] - points[0], points[2] - points[0])
        if outward is not None and np.dot(normal, MOBILE_AXIS @ outward) < 0:
            points = points[[0, 2, 1]]
            normal *= -1.
        length = np.linalg.norm(normal)
        if length > 1e-12:
            pieces.append(np.column_stack((points, np.tile(normal / length, (3, 1)))))
            finishes.append(color)

    cap = np.zeros(len(tri), bool)
    for z, outward in [(-.0011, -side), ((.0425 if side == 1 else -.0445), side)]:
        selected = np.max(np.abs(model[:, :, 2] - z), axis=1) < 1e-6
        cap |= selected
        surface = model[selected]
        center = (surface.max(axis=(0, 1)) + surface.min(axis=(0, 1))) * .5

        def inset(point):
            return center + (point-center) * [ .987, .85, 1.0] - [0., 0., outward*.006]

        # A narrow bevel follows the actual scan silhouette, including the
        # change of section at the nose, and connects to the recessed backing.
        edges = {}
        for corners in surface:
            face(inset(corners), FRAME, np.array([0., 0., outward]))
            for i in range(3):
                a, b = corners[i], corners[(i+1) % 3]
                key = tuple(sorted((tuple(a.round(7)), tuple(b.round(7)))))
                if key in edges:
                    del edges[key]
                else:
                    edges[key] = (a, b)
        for a, b in edges.values():
            inner_a, inner_b = inset(a), inset(b)
            normal = np.array([0., 0., outward])
            face([a, b, inner_b], STEEL, normal)
            face([a, inner_b, inner_a], STEEL, normal)

        # Three stamped ribs stand proud of the dark bed, yet remain below
        # its lip so the two rigid leaves can close flush for travel.
        for u in [.186, .253, .323]:
            nearby = surface[np.max(surface[:, :, 0], axis=1) > u-.012]
            nearby = nearby[np.min(nearby[:, :, 0], axis=1) < u+.012]
            lo = max(.457, nearby[:, :, 1].min()) + .010
            hi = min(.540, nearby[:, :, 1].max()) - .010
            outline = np.array([[u-.009, lo], [u+.002, lo], [u+.016, hi-.004],
                                [u+.013, hi], [u+.002, hi], [u-.012, lo+.004]])
            c = outline.mean(axis=0)
            foot = np.column_stack((outline, np.full(6, z - outward*.0062)))
            top = np.column_stack((c + (outline-c)*[.82,.94], np.full(6, z - outward*.0007)))
            for i in range(6):
                j = (i+1) % 6
                face([foot[i], foot[j], top[j]], SKIRT, np.array([0.,0.,outward]))
                face([foot[i], top[j], top[i]], SKIRT, np.array([0.,0.,outward]))
            for i in range(1,5):
                face([top[0],top[i],top[i+1]], STEEL, np.array([0.,0.,outward]))

    return np.concatenate((tri[~cap], pieces)), np.r_[colors[~cap], finishes]

def gun_parts(mobile, siege, add, socket):
    """Register each native casting once. Target transforms are world-space rigid frames."""
    ring = matrix([-.074, .429, -.0008])
    deployed_ring = matrix([-.050, .3521, .0047])
    add("Turret", "Hull", "mobile", mobile["Turret"], ring, ring, deployed_ring)

    trunnion = matrix([.0295, .486, -.0008], MOBILE_AXIS)
    up_trunnion = matrix([.057, .383, .0047], SIEGE_AXIS)
    # Keep the short rear bridge tied to the pitch bearing. The two real
    # opening leaves begin at the forward edge of this rigid receiver hood.
    nose, hood = split_joint(*mobile["CenterBarrel"], MOBILE_AXIS[:, 0] * .150, MOBILE_AXIS[:, 0])
    station = hood[0][:, :, :3] @ MOBILE_AXIS[:, 0]
    front_cap = np.max(np.abs(station - .150), axis=1) < 1e-7
    housing = tuple(np.concatenate([a, b[~front_cap]]) for a,b in zip(mobile["Mount"], hood))
    add("Mount", "Turret", "mobile", housing, trunnion, trunnion, up_trunnion)

    # The standing scan's middle slab becomes the two leaves of a longitudinal
    # breech cover. They remain attached to the same square-muzzled side castings.
    doors = split_joint(*nose, [0., 0., -.0011], [0., 0., 1.])
    for side, suffix, leaf in [(1, "P", doors[0]), (-1, "N", doors[1])]:
        barrel = matrix([.073, .501, -.001 + side * .086], MOBILE_AXIS)
        seated = np.linalg.solve(trunnion, barrel)
        # The two breech carriages withdraw on short parallel rails and move
        # apart sufficient to clear the single, larger central siege projectile.
        seated[:3, 3] += [-.090, 0., side * .040]
        deployed = up_trunnion @ seated
        name = "Barrel" + suffix
        add(name, "Mount", "mobile", mobile[name], barrel, barrel, deployed)
        port = matrix([.416, .472, -.001 + side * .081], MOBILE_AXIS)
        socket("MobileMuzzle" + suffix, name, np.linalg.solve(barrel, port))

        hinge = _frame_on_axis(MOBILE_AXIS, .044, .540, -.001 + side * .043)
        open_hinge = deployed @ np.linalg.solve(barrel, hinge)
        open_hinge[:3, :3] = open_hinge[:3, :3] @ Rotation.from_rotvec([side * 2.13, 0., 0.]).as_matrix()
        hatch = _hatch_surface("Cover" + suffix, leaf, side)
        add("Cover" + suffix, name, "painted", hatch, hinge, hinge, open_hinge)

        # The deployed upload contains distinct guide blades and lower castings.
        # Fit its actual distal blade into the travel jacket as a sideways slide.
        # Its longer mobile housing serves as the rear guide in both positions.
        rail, tags = siege[name]
        island = 0 if side > 0 else 1
        source_blade = tags == island
        rail_socket = _frame_on_axis(SIEGE_AXIS, .474, .351, .0047 + side * .102)
        tip, _ = split_joint(rail[source_blade], tags[source_blade], rail_socket[:3, 3], SIEGE_AXIS[:, 0])
        stowed = _frame_on_axis(MOBILE_AXIS, .104, .498, -.001 + side * .052)
        stowed[:3, :3] = MOBILE_AXIS @ Rotation.from_rotvec([side * 1.27, 0., 0.]).as_matrix()
        add("Rail" + suffix, "Mount", "siege", tip, rail_socket, stowed, rail_socket)

    # The siege upload includes the short, thick receiver and its dorsal key.
    # It travels out of the turret under the open doors; the last telescoping
    # section runs through that receiver, inside the two elevated guide blades.
    receiver = _frame_on_axis(SIEGE_AXIS, .313, .341, .0047)
    stored_receiver = _frame_on_axis(MOBILE_AXIS, -.132, .494, -.001)
    add("CenterBarrel", "Mount", "siege", siege["CenterBarrel"], receiver, stored_receiver, receiver)
    breech_socket = matrix([.364, .508, .0047], SIEGE_AXIS)
    socket("SiegeBreech", "CenterBarrel", np.linalg.solve(receiver, breech_socket))

    tube_group, length = _ring_barrel()
    tube_end = np.array([.506, .560, .0047])
    tube = matrix(tube_end - length * SIEGE_AXIS[:, 0], SIEGE_AXIS)
    # Mesh coordinates are local lathe coordinates; it keeps the same aperture,
    # collars and wall thickness while sinking into or extending from its breech.
    stored_tube = stored_receiver @ np.linalg.solve(receiver, tube)
    stored_tube[:3, 3] -= .083 * MOBILE_AXIS[:, 0]
    add("Tube", "CenterBarrel", "painted", tube_group, np.eye(4), stored_tube, tube)
    socket("SiegeMuzzle", "Tube", matrix([length, 0., 0.]))
