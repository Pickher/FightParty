"""Rigid sliding bay doors and folding jacks for the two uploaded tank bodies.

The deployed source supplies a real casting, wrist and ground shoe on each side.
They close like a folding ruler inside the travel hull, behind the split side armor.
Coordinates use +X forward and +Y up.
"""
import numpy as np
from scipy.spatial.transform import Rotation

from build_marauder_rig import mark
from hellbat_mech_joints import split_joint
from rigid_glb import face_normals, matrix
from tank_paint import FRAME, SAND, STEEL, painted_surface


def _roll(degrees):
    return Rotation.from_euler("x", degrees, degrees=True).as_matrix()


def _sleeve(start, end, radius, swatches, sides=12):
    """Turn a chamfered solid along a rail or hinge, with distinct rim, shaft and end caps."""
    start, end = np.asarray(start), np.asarray(end)
    axis = end - start
    axis = axis / np.linalg.norm(axis)
    cross = np.cross(axis, [0, 1, 0])
    cross /= np.linalg.norm(cross)
    up = np.cross(axis, cross)
    angles = np.arange(sides) * (2.0 * np.pi / sides)
    radial = np.cos(angles)[:, None] * cross + np.sin(angles)[:, None] * up
    rings = [start + ratio * (end - start) + radial * radius * thickness
             for ratio, thickness in [(0, .78), (.06, 1.), (.94, 1.), (1., .78)]]
    triangles, colors = [], []
    for k in range(3):
        for i in range(sides):
            j = (i + 1) % sides
            a, b, c, d = rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]
            triangles.extend([[a, b, c], [a, c, d]])
            colors.extend([swatches[k], swatches[k]])
    for i in range(sides):
        j = (i + 1) % sides
        triangles.extend([[start, rings[0][j], rings[0][i]], [end, rings[-1][i], rings[-1][j]]])
        colors.extend([swatches[0], swatches[-1]])
    xyz = np.asarray(triangles)
    normals = np.cross(xyz[:, 1] - xyz[:, 0], xyz[:, 2] - xyz[:, 0])
    normals /= np.linalg.norm(normals, axis=1)[:, None]
    return np.concatenate([xyz, np.broadcast_to(normals[:, None], xyz.shape)], axis=2), np.array(colors)


def _together(*parts):
    return tuple(np.concatenate(arrays) for arrays in zip(*parts))


def _islands(group, selection):
    tri, labels = group
    mask = np.isin(labels, selection)
    return tri[mask], labels[mask]


def _shoe(group, side):
    """Pick out the contact strips on the original shoe, visible while the jack unrolls."""
    tri, colors = painted_surface("Foot", group[0], "siege", group[1])
    material = np.broadcast_to(colors[:, None, None], (*tri.shape[:2], 1))
    face = np.concatenate((tri, material), axis=2)
    for station in (.306, .350, .394, .438):
        for half in (-1, 1):
            # Mirrored shallow V's follow the two tines across the forked shoe.
            axis = np.array([half * .24, 0., side])
            choose = (face[:, :, 1].mean(1) < .031) & (face_normals(face)[:, 1] < -.48)
            planes = [([half, 0., 0.], half * .003), (axis, station), (-axis, -station - .012)]
            face = mark(face, choose, planes, FRAME)
            choose = (face[:, 0, 6] == FRAME) & (face_normals(face)[:, 1] < -.62)
            face = mark(face, choose, [(axis, station + .007), (-axis, -station - .011),
                                      ([half, 0., 0.], .035)], STEEL)
    return face[:, :, :6], face[:, 0, 6].astype(np.uint8)


def outrigger_parts(mobile, siege, add, socket):
    for side, suffix in [(1, "P"), (-1, "N")]:
        # The travel upload has a continuous, bevelled side cover and a latch on
        # top. Its two leaves separate along the chassis to uncover the jack bay.
        source = mobile["Arm" + suffix]
        front, rear = split_joint(*source, [-.066, 0., 0.], [1., 0., 0.])
        for name, group, direction in [("BayFront", front, 1), ("BayRear", rear, -1)]:
            pivot = np.array([-.066 + direction * .094, .318, side * .263])
            stowed = matrix(pivot)
            opened = matrix(pivot + [direction * .112, -.020, -side * .086], _roll(-side * 13))
            add(name + suffix, "Hull", "mobile", group, stowed, stowed, opened)

        # S, E and A are the actual shoulder, elbow and ankle axes of the
        # deployed casting. An elbow folds back on the shoulder when it is stowed.
        center = .0047
        shoulder = np.array([.003, .258, center + side * .164])
        elbow = np.array([.003, .153, center + side * .273])
        ankle = np.array([.003, .066, center + side * .317])
        out = np.array([-.062, 0., side * .038])
        stored = np.array([-.066, .310, side * .111])
        upper_roll = _roll(side * 59)
        wrist_roll = _roll(-side * 73)
        stored_elbow = stored + upper_roll @ (elbow - shoulder)
        stored_ankle = stored_elbow + wrist_roll @ (ankle - elbow)

        root = "Slide" + suffix
        # Sliding stock and hinge pin come out of the hull together. In battery
        # the inboard ends still overlap the hull, so the arm always has a bearing.
        rails = []
        for dx in (-.039, .039):
            tip = shoulder + [dx, .000, side * .004]
            rails.append(_sleeve(tip - [0., 0., side * .104], tip, .020, (FRAME, STEEL, FRAME)))
        rails.append(_sleeve(shoulder - [.069, 0., 0.], shoulder + [.069, 0., 0.],
                            .033, (SAND, FRAME, SAND)))
        add(root, "Hull", "painted", _together(*rails), matrix(shoulder),
            matrix(stored), matrix(shoulder + out))

        arm = siege["Arm" + suffix]
        case_ids, wrist_ids = ([13, 17], [11, 15]) if side == 1 else ([14, 18], [12, 16])
        case = _islands(arm, case_ids)
        add("Arm" + suffix, root, "siege", case, matrix(shoulder),
            matrix(stored, upper_roll), matrix(shoulder + out))

        tri, ids = _islands(arm, wrist_ids)
        wrist = painted_surface("Ram", tri, "siege", ids)
        elbow_pin = _sleeve(elbow - [.068, 0., 0.], elbow + [.068, 0., 0.], .023, (STEEL, FRAME, STEEL))
        add("Ram" + suffix, "Arm" + suffix, "painted", _together(wrist, elbow_pin), matrix(elbow),
            matrix(stored_elbow, wrist_roll), matrix(elbow + out))

        foot = "Foot" + suffix
        add(foot, "Ram" + suffix, "painted", _shoe(siege[foot], side), matrix(ankle),
            matrix(stored_ankle, _roll(-side * 85)), matrix(ankle + out))
        toe = np.array([.003, 0., center + side * .402])
        socket("Contact" + suffix, foot, matrix(toe - ankle))
