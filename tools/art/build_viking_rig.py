"""Bind the uploaded Viking assault mech and its articulated fighter pose.

Run with Python 3, NumPy and SciPy. +X is forward, +Y up, +Z is the P side.
Air<Joint> markers store absolute target frames in the same model space as the
standing castings. The moving pieces, material assignments and UVs persist in both forms.
"""
from pathlib import Path

import numpy as np
from scipy.spatial.transform import Rotation

from hellbat_mech_joints import split_joint
from rigid_glb import Rig, load_surface, matrix, orient_axis
from viking_panels import (BLUE, FRAME, GLASS, HOT, MATERIALS, RED, SHADOW, SOLE,
                          STEEL, WHITE, join, loft, paint, sliding_cheeks, swept_panel, unit)

DIR = Path(__file__).resolve().parents[2] / "assets/models/viking"
ROOT = "VikingRig"
Y = np.array([0.,1.,0.])
Z = np.array([0.,0.,1.])
X = np.array([1.,0.,0.])


def align(direction, reference, target, target_reference):
    """Map two vectors, preserving a right-handed, unit-scale frame."""
    def axes(v, ref):
        v = unit(v)
        w = unit(np.cross(v,ref))
        return np.column_stack((v,np.cross(w,v),w))
    return axes(target,target_reference) @ axes(direction,reference).T


def rotate(group, frame):
    tri, ids = group
    copy = tri.copy()
    copy[:,:,:3] = tri[:,:,:3] @ frame[:3,:3].T + frame[:3,3]
    copy[:,:,3:] = tri[:,:,3:] @ frame[:3,:3].T
    return copy, ids


def rot(axis, degrees):
    return Rotation.from_euler(axis, degrees, degrees=True).as_matrix()


def build():
    source, ids = load_surface(DIR/"viking_assault.glb", expected_islands=41)
    rig = Rig(MATERIALS, "Viking")
    rig.node(ROOT, None, np.eye(4))
    targets, used = {}, set()

    def islands(*numbers):
        assert not used.intersection(numbers)
        used.update(numbers)
        selected = np.isin(ids,numbers)
        return source[selected], ids[selected]

    def part(name, parent, p, target, geometry, basis=np.eye(3)):
        bind = matrix(p, basis)
        rig.node(name, parent, bind)
        rig.mesh(name, *geometry, bind)
        targets[name] = target

    def socket(name, parent, pos, axis=X):
        rig.node(name,parent,matrix(pos,orient_axis(unit(axis))))

    pelvis = np.array([-.082,.421,0.])
    trunk = np.array([-.10,.60,0.])
    fuselage = matrix([.01,.34,0.],rot('z',38))
    part("Pelvis",ROOT,pelvis,matrix([-.10,.245,0.]),paint("Pelvis",islands(15)))
    tail, body = split_joint(*islands(0),[-.282,.55,0],[-.82,-.55,0])
    tail_p, tail_n = split_joint(*tail,[0,0,0],Z)
    nose_axis = unit([.8,-.60,0.])
    nose, central = split_joint(*body,[.082,.630,0.],nose_axis)
    nose_p = np.array([.082,.630,0.])
    nose_air = matrix(fuselage[:3,3] + fuselage[:3,:3] @ (nose_p-trunk) + [.092,0,0],fuselage[:3,:3])
    # Sliding frames stay overlapped when the nose separates from the cockpit sill.
    frame_rails = [loft(nose_p + [0,0,s*.078],nose_axis,
                        [(-.15,.028,.028,FRAME),(-.02,.032,.032,STEEL),(.17,.025,.025,FRAME)],8)
                   for s in (1,-1)]
    part("Trunk","Pelvis",trunk,fuselage,join(paint("Trunk",central),sliding_cheeks(nose,nose_p,nose_axis),*frame_rails))
    part("Nose","Trunk",nose_p,nose_air,paint("Nose",nose))
    tip_p = np.array([-.075,.685,0.])
    prow = loft(tip_p,nose_axis,[(-.022,.052,.102,FRAME),(.02,.064,.122,SHADOW),
                 (.085,.069,.136,BLUE),(.191,.057,.117,BLUE),(.238,.046,.097,SHADOW),
                 (.269,.035,.058,RED),(.281,.033,.053,WHITE),(.292,.031,.051,RED),
                 (.355,.022,.035,SHADOW),(.421,.006,.010,STEEL)],8)
    tip_air = matrix(nose_air[:3,3] + nose_air[:3,:3] @ (tip_p-nose_p) + [.362,0,0],nose_air[:3,:3])
    part("NoseTip","Nose",tip_p,tip_air,prow)

    for sign, suffix, tail_half in [(1,"P",tail_p),(-1,"N",tail_n)]:
        pos = sign == 1
        def side(name): return name+suffix
        hip = np.array([-.102,.570,.136] if pos else [-.176,.560,-.142])
        knee = np.array([-.067,.416,.145] if pos else [-.142,.413,-.138])
        ankle = np.array([.095,.220,.177] if pos else [-.154,.179,-.226])
        leg_upper, leg_lower = split_joint(*islands(8 if pos else 1),knee,[.04,1,0])
        hip_air = np.array([-.075,.355,sign*.113])
        upper_dir = unit([-.96,-.06,sign*.055])
        knee_air = hip_air + upper_dir*np.linalg.norm(knee-hip)
        lower_dir = unit([-.93,.195,-sign*.045])
        ankle_air = knee_air + lower_dir*np.linalg.norm(ankle-knee)
        part(side("Hip"),"Pelvis",hip,matrix(hip_air,align(knee-hip,Z,upper_dir,Z)),paint("Hip",leg_upper))
        lower_extra = islands(17,18,20,22) if pos else islands(7,11,12,16,19)
        part(side("Knee"),side("Hip"),knee,matrix(knee_air,align(ankle-knee,Z,lower_dir,Z)),
             paint("Knee",join(leg_lower,lower_extra)))
        foot = islands(21 if pos else 2)
        toe = np.array([.246,-.090,sign*.155] if pos else [.182,-.13,sign*.208])
        foot_air = matrix(ankle_air,align(toe,Y,[.94,-.07,-sign*.15],Y))
        part(side("Ankle"),side("Knee"),ankle,foot_air,paint("Ankle",foot))
        verts = np.unique(foot[0][:,:,:3].reshape(-1,3),axis=0)
        floor = verts[:,1].min()
        sole = verts[verts[:,1]<floor+.013].mean(0)
        sole[1] = floor
        socket(side("Sole"),side("Ankle"),sole)

        shoulder_p = np.array([-.127,.657 if pos else .631,sign*.272])
        pod, carrier = split_joint(*islands(4 if pos else 3),[-.123,.632 if pos else .605,sign*.31],
                                   [-.17,1,0])
        shoulder_air = matrix([-.225,.390,sign*.300],rot('x',sign*72) @ rot('z',8))
        hinges = islands(9,13) if pos else islands(10,14)
        part(side("Shoulder"),"Trunk",shoulder_p,shoulder_air,paint("Shoulder",join(carrier,hinges)))
        gun_p = np.array([.078,.545 if pos else .521,sign*.332])
        tube_ids = [27,29,31,32,35,37,38] if pos else [28,30,33,34,36,39,40]
        cluster = islands(*tube_ids)
        centerlines, ports, tails = [], [], []
        for tag in tube_ids:
            verts = np.unique(cluster[0][cluster[1] == tag,:,:3].reshape(-1,3),axis=0)
            axis = np.linalg.svd(verts - verts.mean(0), full_matrices=False)[2][0]
            if axis[0] < 0:
                axis = -axis
            along = verts @ axis
            centerlines.append(axis)
            ports.append(verts[along > along.max()-.004].mean(0))
            tails.append(verts[along < along.min()+.004].mean(0))
        gun_axis = unit(np.mean(centerlines, axis=0))
        gun_air = matrix([-.144,.347,sign*.345],rot('x',sign*72) @ align(gun_axis,Y,X,Y))
        fixed = islands(23,25) if pos else islands(24,26)
        part(side("Gun"),side("Shoulder"),gun_p,gun_air,paint("Gun",fixed))
        rotor_p = np.mean(tails,axis=0)
        rotor_basis = orient_axis(gun_axis)
        drum = loft(rotor_p,gun_axis,[(-.012,.055,.055,FRAME),(.011,.055,.055,STEEL),
                                     (.015,.054,.054,SHADOW)],16)
        lips = [loft(port,axis,[(-.004,.011,.011,FRAME),(.002,.012,.012,STEEL),
                     (.005,.012,.012,STEEL),(.005,.008,.008,SOLE),(.002,.007,.007,SOLE)],10)
                for port, axis in zip(ports,centerlines)]
        rotor_air = gun_air @ np.linalg.inv(matrix(gun_p)) @ matrix(rotor_p,rotor_basis)
        part(side("Rotor"),side("Gun"),rotor_p,rotor_air,join(paint("Gun",cluster),drum,*lips),rotor_basis)
        station = np.max((np.array(ports) - rotor_p) @ gun_axis) + .005
        socket(side("Muzzle"),side("Rotor"),rotor_p + station*gun_axis,gun_axis)

        engine_p = np.array([-.147,.691 if pos else .663,sign*.312])
        exit_axis = unit([-1,.105,0])
        nozzle_p = np.array([-.245,.740 if pos else .713,sign*.33])
        exhaust = loft(nozzle_p,exit_axis,[(-.052,.064,.068,FRAME),(-.018,.069,.075,SHADOW),
                      (.004,.066,.074,STEEL),(.031,.058,.069,FRAME),(.050,.064,.071,STEEL),
                      (.054,.062,.069,STEEL),(.054,.048,.056,FRAME),(.032,.045,.051,SHADOW),
                      (.018,.034,.040,HOT),(.018,.026,.029,HOT)],14)
        engine_air = matrix([-.350,.401,sign*.260],align(exit_axis,Y,-X,Y))
        part(side("Engine"),"Trunk",engine_p,engine_air,join(paint("Engine",pod),exhaust))
        socket(side("Exhaust"),side("Engine"),nozzle_p+.054*exit_axis,exit_axis)

        tail_pivot = np.array([-.301,.566,sign*.125])
        tail_air = matrix([-.329,.437,sign*.164],align([-.077,-.218,sign*.015],Z,
                                  [-.815,.515,sign*.233],Z))
        part(side("Tail"),"Trunk",tail_pivot,tail_air,paint("Tail",tail_half))

        wing_p = np.array([-.156,.599 if pos else .570,sign*(.421 if pos else .430)])
        wing_air_p = np.array([.125,.404,sign*.220])
        outward = unit([-.545,.025,sign*.837])
        wing_basis = align([-.026,-.282,sign*.065],X,outward,X)
        wing_frame = matrix(wing_air_p,wing_basis)
        air_to_rest = matrix(wing_p) @ np.linalg.inv(wing_frame)
        def rest(p):
            return (air_to_rest @ np.r_[p,1])[:3]
        # The compact missile rail is bolted to the underside of the existing wing.
        # Its mouth and the live launch marker share a physical lip.
        hardpoint = wing_air_p + .205*outward + [-.004,-.031,0]
        rail = loft(hardpoint,X,[(-.10,.028,.033,SHADOW),(-.082,.037,.038,BLUE),
                    (.045,.035,.036,SHADOW),(.082,.027,.029,STEEL),(.084,.020,.021,FRAME),
                    (.063,.016,.018,SOLE)],8)
        wing = islands(6 if pos else 5)
        part(side("Wing"),"Trunk",wing_p,wing_frame,join(paint("Wing"+suffix,wing),rotate(rail,air_to_rest)))
        socket(side("Missile"),side("Wing"),rest(hardpoint + [.084,0,0]),wing_basis.T @ X)
        # Main wing panels are stowed vertically, one over the other behind the
        # shoulder housing. They fan out longitudinally to make a continuous
        # swept wing; the original wing shield locks under its leading spar.
        stations = [(.145,.269,-.345),(.25,.186,-.372),(.394,.050,-.410),
                    (.48,-.047,-.430),(.592,-.156,-.438),(.622,-.190,-.427)]
        inner = [(z,front,.49*front+.51*back) for z,front,back in stations]
        flap = [(z,.49*front+.51*back-.0015,back) for z,front,back in stations]
        for key, spread, name, bind_anchor, finish in [
                ("WingGlove",inner,"Trunk",[-.117,.402,sign*.148],"glove"),
                ("WingFlap",flap,side("WingGlove"),[-.151,.423,sign*.175],"flap")]:
            z0,front,back = spread[0]
            attach = np.array([.50*(front+back),.423,sign*z0])
            # Sweep diagonally up the back when stowed. The two folding leaves
            # retain different hinge depths and cannot z-fight when nested.
            stow = align([-.445,0,sign*.455],X,[-.237,.551,sign*.031],X)
            bind_anchor = np.array(bind_anchor)
            to_bind = matrix(bind_anchor,stow) @ np.linalg.inv(matrix(attach))
            panel = rotate(swept_panel(spread,sign,finish),to_bind)
            part(side(key),name,bind_anchor,matrix(attach,stow.T),panel)

        # The outer delta tapers to a swept red wingtip. It retracts behind the
        # upload's hinged shield, rather than scaling the polygon to disappear.
        tip_outline = [(.560,-.135,-.419),(.652,-.22,-.475),(.747,-.318,-.502),
                       (.773,-.344,-.510),(.849,-.437,-.519),(.866,-.473,-.508)]
        tip_root = np.array([-.21,.437,sign*.560])
        anchor = np.array([-.135,.394 if pos else .367,sign*.379])
        stow = align([-.36,0,sign*.37],X,[-.057,.321,-sign*.028],X)
        to_bind = matrix(anchor,stow) @ np.linalg.inv(matrix(tip_root))
        leaf = rotate(swept_panel(tip_outline,sign,"tip"),to_bind)
        part(side("WingTip"),side("Wing"),anchor,matrix(tip_root,stow.T),leaf)

    assert used == set(np.unique(ids)), "Each original component must stay on the vehicle"
    for name, target in targets.items():
        rig.node("Air"+name,ROOT,target)
    rig.write(DIR/"viking_rig.glb")


if __name__ == "__main__":
    build()
