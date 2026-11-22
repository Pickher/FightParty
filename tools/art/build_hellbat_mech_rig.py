"""Articulate the supplied solid Hellbat and register its folding joints to the Hellion.

Run from any directory with Python 3, NumPy and SciPy. The two source assets stay
in their original +X-forward, +Y-up coordinate systems. Fold markers describe
absolute target poses, relative to the standing rig root.
"""
from pathlib import Path
import json
import struct

import numpy as np
from scipy.spatial.transform import Rotation

from hellbat_mech_joints import split_joint
from hellbat_mech_paint import FRAME, MATERIALS, assign_paint
from rigid_glb import Rig, face_normals, load_surface, matrix, orient_axis


MODELS = Path(__file__).resolve().parents[2] / "assets/models"
MECH = MODELS / "hellbat_mech"
CAR = MODELS / "hellbat/hellion_rig.glb"
ROOT = "HellbatRig"

# Surface stations measured on the final ring and the back of the barrel.
TIP = np.array([.050, .790, -.017])
BORE = np.array([1., -.105, -.177])
CAR_TIP = np.array([.056, .583, 0.])
CAR_BORE = np.array([1., -.052, -.012])
# Match the maximum horizontal diameter, preserving both real ground planes.
CAR_SCALE = .99951172 / .98086548


def unit(vector):
    return np.asarray(vector, dtype=float) / np.linalg.norm(vector)


def basis_from_axes(longitudinal, normal):
    x = unit(longitudinal)
    z = unit(normal - x * np.dot(x, normal))
    return np.column_stack((x, np.cross(z, x), z))


def registered_frame(joint, reference, target, basis):
    """The chosen point on the source casting lands exactly on its vehicle mate."""
    return matrix(np.asarray(target) - basis @ (np.asarray(reference) - joint), basis)


def car_nodes():
    raw = CAR.read_bytes()
    length = struct.unpack_from("<I", raw, 12)[0]
    doc = json.loads(raw[20:20 + length])
    return {n["name"]: CAR_SCALE * np.array(n["translation"])
            for n in doc["nodes"] if "translation" in n}


def assemble():
    source, islands = load_surface(MECH / "hellbat_mech.glb", expected_islands=27)
    vehicle = car_nodes()
    rig = Rig(MATERIALS, "Hellbat")
    rig.node(ROOT, None, np.eye(4))
    targets = {}

    def faces(*numbers):
        selected = np.isin(islands, numbers)
        return source[selected], islands[selected]

    def join(*groups):
        return tuple(np.concatenate(items) for items in zip(*groups))

    def joint(name, parent, pivot, surface, folded):
        frame = matrix(pivot)
        rig.node(name, parent, frame)
        tri, tags = surface
        finish = assign_paint(name, tri[:, :, :3].mean(1), face_normals(tri), tags)
        finish[tags == -1] = FRAME
        rig.mesh(name, tri, finish, frame)
        targets[name] = folded

    # The hips, waist and wheel boots were exported as continuous castings.
    # Separate them through physical joint collars and fill the exposed metal.
    torso, pelvis = split_joint(*faces(4), [0, .3508, 0], [.08, 1., 0.])
    pelvis_pivot = np.array([0., .337, 0.])
    trunk_pivot = np.array([-.017, .379, .003])
    joint("Pelvis", ROOT, pelvis_pivot, join(pelvis, faces(6)),
          matrix([-.065, .159, 0.], Rotation.from_euler("z", -14, degrees=True).as_matrix()))
    # The visor folds into the driver's canopy; the rear hose stays attached to the shell.
    trunk_fold = registered_frame(trunk_pivot, [.105, .617, -.004],
                                  [.085, .355, 0.], Rotation.from_euler("z", -18, degrees=True).as_matrix())
    joint("Trunk", "Pelvis", trunk_pivot, join(torso, faces(0, 5, 13, 23, 24)), trunk_fold)

    for side, suffix in [(1, "P"), (-1, "N")]:
        positive = side == 1
        leg_id, brace_id = (12, 18) if positive else (15, 16)
        # The outer wheel and forward sole are a single boot. An oblique cut
        # behind the wheel guard retains the tire outline through ankle rotation.
        upper, lower = split_joint(*faces(leg_id), [.091, .252, 0], [.38, 1., 0.])
        shin, boot = split_joint(*lower, [.070, .173, 0], [.44, 1., 0.])
        hip = np.array([.009 if positive else .021, .347, side * .103])
        knee = np.array([.101 if positive else .113, .248, side * .140])
        ankle = np.array([.009, .078, .233] if positive else [.045, .078, -.226])
        front_wheel = vehicle["WheelFrontRight" if positive else "WheelFrontLeft"]
        rear_wheel = vehicle["WheelRearRight" if positive else "WheelRearLeft"]
        # The wheel boot travels forward onto the real front hub; the folded
        # thigh and shin form a horizontal trailing link under its fender.
        joint("Hip" + suffix, "Pelvis", hip, upper,
              matrix([.075, .204, side * .123], Rotation.from_euler("z", 35, degrees=True).as_matrix()))
        joint("Knee" + suffix, "Hip" + suffix, knee, join(shin, faces(brace_id)),
              matrix([.237, .195, side * .145], Rotation.from_euler("z", 90, degrees=True).as_matrix()))
        # The scan's two hubs are cambered and individually posed. Straighten
        # both actual wheel axes, then tuck their toes up under the front cowl.
        wheel_axis = [-.088, .212, .939] if positive else [-.200, .152, -.922]
        axle_basis = basis_from_axes([0., 0., side], np.array([0., 1., 0.]))
        wheel_basis = axle_basis @ basis_from_axes(wheel_axis, np.array([0., 1., 0.])).T
        toe_up = Rotation.from_euler("z", 82, degrees=True).as_matrix()
        toe_hardware = (11, 14) if positive else (19, 20)
        joint("Ankle" + suffix, "Knee" + suffix, ankle,
              join(boot, faces(*toe_hardware)), matrix(front_wheel, toe_up @ wheel_basis))

        shoulder = np.array([.002, .552, side * .127])
        elbow = np.array([.113 if positive else .093, .459, side * .237])
        arm_ids = (22, 26, 10, 7) if positive else (17, 25, 21, 3)
        # The shell's broad outward panel becomes a front fender. The two
        # differently angled plates need separate longitudinal and normal axes.
        if positive:
            center, long_axis, normal = [.134, .455, .329], [.605,.562,-.564], [.472,.318,.822]
            drum_center, drum_axis = [-.095,.559,.255], [-.420,.534,.733]
        else:
            center, long_axis, normal = [.153,.439,-.339], [.393,.709,.585], [.694,.188,-.695]
            drum_center, drum_axis = [-.136,.562,-.230], [-.528,.498,-.688]
        new_shield = basis_from_axes([1., -.15, 0.], np.array([0., .79, side * .614]))
        shield_basis = new_shield @ basis_from_axes(long_axis, np.asarray(normal)).T
        shield_fold = registered_frame(elbow, center, [.142, .285, side * .183], shield_basis)
        joint("Shoulder" + suffix, "Trunk", shoulder, faces(arm_ids[0]),
              matrix([-.017,.28,side*.142], Rotation.from_euler("z", 55, degrees=True).as_matrix()))
        joint("Shield" + suffix, "Shoulder" + suffix, elbow, faces(*arm_ids[1:3]), shield_fold)

        # Cylindrical fuel jackets nest on the measured rear wheel axles.
        drum_basis = axle_basis @ basis_from_axes(drum_axis, np.array([0., 1., 0.])).T
        joint("Tank" + suffix, "Trunk", drum_center, faces(arm_ids[3]), matrix(rear_wheel, drum_basis))

    burner = np.array([-.169, .683, .021])
    align_barrel = orient_axis(CAR_BORE.copy()) @ orient_axis(BORE.copy()).T
    turret_fold = registered_frame(burner, TIP, CAR_SCALE * CAR_TIP, align_barrel)
    joint("Turret", "Trunk", burner, faces(1, 2, 8, 9), turret_fold)
    rig.node("Muzzle", "Turret", matrix(TIP, orient_axis(BORE.copy())))
    targets["Muzzle"] = matrix(CAR_SCALE * CAR_TIP, orient_axis(CAR_BORE.copy()))
    for name, frame in targets.items():
        rig.node("Fold" + name, ROOT, frame)
    rig.write(MECH / "hellbat_mech_rig.glb")


if __name__ == "__main__":
    assemble()
