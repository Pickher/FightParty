"""Four original Terran recruiting miniatures without corresponding unit models."""
import math
from mathutils import Vector
from studio import mat, ell, beam, loft, tube, box, plate, mesh
from protoss_machines import swept, panel

steel=mat('Human brushed steel','8093a8',.77,.33)
dark=mat('Human gunmetal','2f3c47',.68,.32)
rubber=mat('Human carbon pads','18262b',.2,.61)
blue=mat('Naval slate enamel','506c89',.59,.33)
white=mat('Hull markings','ced6cd',.42,.39)
red=mat('Viking oxblood','aa3f38',.54,.32)
amber=mat('Hazard yellow','e6a942',.45,.37)
glass=mat('Polarized flight glass','255c72',.72,.16)
glow=mat('Cockpit ice','81d7ee',.34,.20,.48)
lime=mat('Ghost vision phosphor','93f79e',.22,.15,1.4)
optic=mat('Mine ready sensor','ff6047',.27,.19,1.2)
cloak=mat('Recon weave','435c65',.09,.76)


def barrel(name,a,b,r,metal=dark):
    a,b=Vector(a),Vector(b);axis=(b-a).normalized()
    beam(name,a,b,r,r*.91,metal,16)
    beam(name+' lip',b-axis*.045,b,r*1.09,r*1.04,steel,16)
    beam(name+' dark aperture',b,b+axis*.006,r*.74,r*.70,rubber,16)


def agent():
    loft('Upper body',[(0,.02,.04,.28,.17),(0,.03,.21,.37,.22),(0,.015,.63,.48,.265),
              (0,.02,.93,.49,.22),(0,.02,1.07,.25,.16)],rubber,14,2,'Z')
    for s in [-1,1]:
        swept('Pectoral laminate',[(s*.10,-.14,1.12,.015,.025),(s*.28,-.22,.96,.18,.10),
                                  (s*.27,-.22,.76,.20,.10),(s*.15,-.21,.54,.095,.045)],blue,dark)
        loft('Pauldrons',[(s*.486,.009,.667,.12,.135),(s*.514,.012,.735,.19,.182),
              (s*.515,.007,.813,.198,.207),(s*.490,-.005,.936,.205,.196),
              (s*.450,-.012,.99,.149,.127)],blue,10,1,'Z')
        loft('Shoulder band',[(s*.501,-.006,.727,.160,.166),(s*.514,-.006,.757,.195,.192),
                              (s*.514,-.006,.789,.198,.202)],dark,10,1,'Z')
        tube('Plate boundary',[(s*.406,-.178,.861),(s*.507,-.197,.837),
                               (s*.622,-.17,.84),(s*.676,-.112,.864)],.015,steel)
        ell('Upper sleeve',(s*.517,-.011,.645),(.186,.182,.24),cloak,rot=(0,s*.18,0))
        box('Shoulder badge',(s*.495,-.113,.861),(.238,.167,.187),blue,.06,rot=(.15,s*.20,s*.25))
        beam('Forearm',(s*.544,-.008,.526),(s*.418,-.291,.473),.156,.124,dark)
        tube('Torso ranures',[(s*.07,-.213,.48),(s*.19,-.22,.46),(s*.31,-.154,.51)],.027,steel)
    # Interlocking vest panels follow the rib cage beneath the forward gun.
    for s in (-1,1):
        plate('Chest ballistic plate',[(s*.032,-.276,.983),(s*.252,-.250,1.023),
              (s*.405,-.198,.90),(s*.328,-.262,.744),(s*.079,-.291,.713)],.067,blue,.032)
        plate('Inset pectoral scale',[(s*.081,-.310,.934),(s*.247,-.289,.95),
              (s*.326,-.275,.891),(s*.266,-.303,.833),(s*.082,-.322,.846)],.026,dark,.012)
        for i in range(3):
            z=.735-i*.091
            plate('Segmented belly plate',[(s*.045,-.249,z),(s*.25,-.244,z+.022),
                  (s*.303,-.217,z-.041),(s*.130,-.27,z-.079),(s*.038,-.270,z-.057)],.043,blue,.014)
        plate('Armoured shoulder cap',[(s*.384,-.161,.984),(s*.531,-.153,.991),
              (s*.627,-.112,.911),(s*.657,-.110,.784),(s*.551,-.184,.779),
              (s*.441,-.198,.861)],.062,steel,.032)
        plate('Shoulder cloth marking',[(s*.497,-.195,.926),(s*.545,-.187,.928),
              (s*.605,-.152,.868),(s*.573,-.176,.85)],.017,blue,.01)
    tube('Throat comms',[(-.12,-.22,1.22),(-.17,-.257,1.11),(-.11,-.285,1.03)],.023,steel)
    loft('Neck gaiter',[(0,0,.94,.21,.17),(0,-.018,1.175,.238,.185),(0,0,1.26,.185,.18)],cloak,16,2,'Z')
    loft('Sniper cowl',[(0,.024,1.10,.133,.143),(0,.034,1.22,.255,.244),(0,.034,1.49,.288,.288),
                         (0,.045,1.65,.270,.255),(0,.07,1.76,.186,.193),(0,.086,1.79,.06,.067)],cloak,20,2,'Z')
    ell('Face mask',(0,-.169,1.432),(.223,.146,.228),dark)
    swept('Brow guard',[(0,-.329,1.507,.039,.020),(0,-.263,1.588,.22,.075),
                         (0,-.105,1.693,.23,.08),(0,.055,1.74,.16,.085)],blue,dark)
    # The rigid split rebreather and brow leave a single narrow targeting visor.
    mask=loft('Lower mask armour',[(0,-.252,1.243,.058,.039),(0,-.254,1.307,.122,.064),
                (0,-.252,1.394,.177,.065),(0,-.249,1.428,.171,.042)],blue,10,1,'Z')
    for s in [-1,1]:
        panel(mask,[(s*.026,1.290),(s*.084,1.307),(s*.126,1.387),(s*.040,1.376)],dark,steel,True)
        plate('Reinforced brow',[(s*.006,-.359,1.507),(s*.030,-.352,1.558),(s*.172,-.319,1.551),
                                 (s*.195,-.298,1.521),(s*.071,-.355,1.502)],.023,blue,.01)
        ell('Orbit socket',(s*.088,-.283,1.487),(.099,.056,.073),rubber,rot=(0,s*.18,0))
        ell('Ghost night sight',(s*.09,-.334,1.492),(.063,.032,.026),lime,rot=(0,s*.18,0))
        swept('Respirator cheek',[(s*.035,-.299,1.318,.03,.018),(s*.124,-.281,1.379,.063,.044),
                                 (s*.183,-.216,1.459,.065,.052)],steel)
        for k in range(3):
            tube('Mask vent',[(s*.037,-.311,1.353-k*.026),(s*.085,-.297,1.362-k*.025)],.009,rubber)
    ell('Rangefinder',(0,-.287,1.583),(.039,.035,.032),glass)
    for s in [-1,1]:
        plate('Stealth helmet frame',[(s*.153,-.257,1.555),(s*.222,-.201,1.536),
              (s*.223,-.199,1.391),(s*.143,-.260,1.320),(s*.122,-.276,1.353),
              (s*.168,-.265,1.427)],.025,blue,.014)
        tube('Hood edge stitching',[(s*.198,-.194,1.622),(s*.247,-.160,1.522),
                                  (s*.240,-.147,1.40),(s*.224,-.122,1.33)],.011,steel)
    box('Earpiece bracket',(.245,-.052,1.45),(.044,.133,.131),dark,.017)
    box('Comms inset',(.269,-.063,1.446),(.010,.097,.075),steel,.009)
    beam('Sight rangefinder',(.195,-.168,1.51),(.195,-.31,1.51),.040,.037,blue,10)
    beam('Sight lamp',(.195,-.311,1.51),(.195,-.319,1.51),.028,.025,glass,10)
    box('Lower harness',(0,-.171,.261),(.61,.115,.108),blue,.018)
    for s in [-1,1]:
        box('Field pouch',(s*.200,-.226,.304),(.148,.095,.18),dark,.025)
        box('Pouch closure',(s*.2,-.267,.329),(.137,.047,.067),blue,.014)
    box('Belt clasp',(0,-.238,.26),(.097,.044,.080),steel,.011)

    for s in [-1,1]:
        swept('Cowl fold',[(s*.10,.117,1.71,.02,.026),(s*.23,.136,1.39,.065,.077),
                          (s*.24,.172,1.16,.094,.07),(s*.39,.201,.92,.17,.085),
                          (s*.50,.18,.63,.11,.05)],cloak,dark)

    a=Vector((-.64,-.348,.50)); b=Vector((1.06,-.53,.92)); axis=(b-a).normalized()
    def p(t):return a.lerp(b,t)
    receiver=box('Marksman action',p(.48),(.163,.174,.57),dark,.04)
    receiver.rotation_euler=axis.to_track_quat('Z','Y').to_euler()
    butt=box('Adjustable stock',p(.17),(.137,.19,.40),blue,.051)
    butt.rotation_euler=receiver.rotation_euler
    barrel('Rifle barrel',p(.59),b,.056)
    barrel('Suppressor',p(.82),b+axis*.075,.082)
    barrel('Combat optic',p(.42)+Vector((0,.039,.126)),p(.64)+Vector((0,.039,.126)),.06,blue)
    for t in [.40,.48,.59,.67]:
        pos=p(t)
        beam('Breech ring',pos-axis*.014,pos+axis*.014,.087,.087,steel,10)
    for t in [.74,.79,.86,.95]:
        ax=p(t); beam('Fore-end guards',ax-axis*.018,ax+axis*.018,.087,.082,blue,8)
    for s in [-1,1]:
        box('Armour fastening',(s*.36,-.185,.825),(.059,.032,.105),steel,.009,rot=(0,s*.35,0))
        for z in [.606,.645,.688]:
            box('Carrier webbing',(s*.236,-.266,z),(.108,.025,.027),dark,.007,rot=(0,s*.17,0))
    for t in [.29,.64]:
        grip=p(t)
        elbow=Vector((-.50 if t<.4 else .51,-.08,.428 if t<.4 else .468))
        beam('Guarded forearm',elbow,grip+Vector((0,.035,-.042)),.117,.069,blue,10)
        pos=grip+Vector((-.015,-.083,-.037))
        ell('Armored glove',pos,(.085,.063,.079),rubber)
        for k in range(3):
            ell('Knuckle guard',pos+Vector((.012*k,-.054,.022*k-.016)),(.033,.029,.038),steel)


def widow_mine():
    ochre=mat('Mine industrial bronze','b88d53',.66,.35)
    for s in [-1,1]:
        for front in [-1,1]:
            a=Vector((s*.36,front*.23,.48));b=Vector((s*.70,front*.47,.53));c=Vector((s*.82,front*.65,.09))
            beam('Walking spindle',a,b,.116,.105,steel,18)
            ell('Rotating gear',b,(.113,.127,.124),rubber)
            swept('Burrowing claw',[(*b,.11,.085),(*b.lerp(c,.32),.14,.12),(*b.lerp(c,.83),.067,.058),
                                   (s*.94,front*.72,.045,.015,.015)],ochre,dark)
            beam('Leg bolt',b-Vector((s*.10,0,0)),b+Vector((s*.115,0,0)),.060,.055,steel,10)
    loft('Armored drum',[(0,0,.27,.36,.31),(0,0,.32,.50,.43),(0,0,.54,.60,.51),
                         (0,.015,.75,.52,.45),(0,.05,.79,.38,.35)],dark,14,1,'Z')
    for s in [-1,1]:
        swept('Articulated carapace',[(s*.19,-.48,.55,.033,.063),(s*.36,-.30,.66,.14,.15),
                                    (s*.44,.01,.69,.15,.17),(s*.38,.30,.65,.16,.16),(s*.27,.47,.54,.06,.055)],ochre)
        for y in [-.21,-.05,.13]:
            tube('Hazard chevron',[(s*.50,y,.71),(s*.46,y-.043,.78),(s*.39,y-.07,.82)],.023,rubber)
    # The compact missile is visibly cradled inside the two upturned shell doors.
    a=Vector((-.04,.03,.53));b=Vector((.095,-.085,1.18));ax=(b-a).normalized()
    beam('Warhead silo',a,b,.19,.15,white,20)
    beam('Missile band',b-ax*.12,b-ax*.06,.17,.16,amber,20)
    beam('Red nose cone',b-ax*.035,b+ax*.21,.16,.015,red,20)
    for s in [-1,1]:
        plate('Open silo cover',[(s*.16,-.22,.69),(s*.19,.31,.70),(s*.32,.26,1.01),(s*.29,-.15,1.04)],.065,dark,.029)
    for s in [-1,1]:
        plate('Lower mine skirt',[(s*.45,-.33,.486),(s*.48,-.21,.385),(s*.56,.09,.404),(s*.56,.16,.52)],.053,blue,.019)
        beam('Hip piston flex',(s*.45,-.18,.41),(s*.66,-.38,.47),.052,.046,steel,14)
        box('Silo latch',(s*.26,-.16,.81),(.073,.12,.042),amber,.016,rot=(0,s*.31,0))
    box('Sensor bar',(0,-.467,.58),(.35,.105,.13),steel,.04)
    for x in [-.094,.0,.094]:
        ell('Armed sensor',(x,-.521,.586),(.037,.022,.036),optic)


def engine_case(x):
    # The Viking's paired armoured nacelles have deep box inlets and segmented shoulders.
    rings=[(-.879,.151,.086,.42),(-.846,.181,.12,.427),(-.60,.206,.144,.445),
           (-.28,.214,.158,.45),(.50,.203,.143,.458),(.825,.15,.123,.439)]
    profile=[(-.72,-1),(.72,-1),(1,-.58),(1,.55),(.64,1),(-.64,1),(-1,.55),(-1,-.58)]
    verts=[(x+a*w,y,z+b*h) for y,w,h,z in rings for a,b in profile]
    faces=[tuple(range(8))];tags=[0]
    for i in range(len(rings)-1):
        for j in range(8):
            a=i*8+j;b=i*8+(j+1)%8;faces.append((a,b,b+8,a+8))
            tags.append(1 if j in (2,3,5) and i in (2,3) else 0)
    faces.append(tuple(range(len(verts)-8,len(verts))));tags.append(0)
    shell=mesh('Viking split engine plating',verts,faces,blue,False)
    shell.data.materials.append(red)
    for f,k in zip(shell.data.polygons,tags):f.material_index=k
    from studio import rounded
    rounded(shell,.020)
    for i,y in enumerate([-.56,-.22,.12,.45]):
        panel(shell,[(x-.10,y-.091),(x+.092,y-.091),(x+.126,y+.06),(x+.074,y+.089),(x-.094,y+.08)],
              red if i in (0,1) else blue,dark)
    box('Air intake',(x,-.885,.430),(.277,.035,.120),rubber,.019)
    for dx in [-.093,-.03,.034,.096]:
        box('Intake guides',(x+dx,-.912,.426),(.021,.066,.100),steel,.008)
    for j in range(2):
        beam('Thrust drum',(x+.075*(j*2-1),.70,.44),(x+.075*(j*2-1),.99,.43),.105,.080,dark,12)
    return shell


def wing(name,plan,z,thickness,color,bevel=.025):
    return plate(name,[(x,y,z+(0.04 if y>0 else 0)) for x,y in plan],thickness,color,bevel)


def canopy(y,z,sx,sy,sz):
    ell('Canopy rim',(0,y,z),(sx*1.11,sy*1.06,sz*.89),steel)
    ell('Flight canopy',(0,y-.017,z+.035),(sx,sy,sz),glass)
    for s in [-1,1]:
        tube('Windshield frame',[(s*sx*.22,y-sy*.94,z+.076),(s*sx*.72,y-sy*.44,z+sz*.72),
                                 (s*sx*.83,y+sy*.30,z+sz*.63)],.019,steel)


def viking():
    swept('Viking fuselage',[(0,-1.28,.37,.077,.034),(0,-1.02,.43,.20,.12),
                             (0,-.56,.47,.31,.20),(0,-.15,.48,.34,.24),
                             (0,.62,.44,.26,.21),(0,1.01,.43,.14,.13)],blue,dark)
    canopy(-.52,.614,.205,.41,.16)
    for s in [-1,1]:
        plan=[(s*.20,-.44),(s*.46,-.31),(s*1.13,.32),(s*1.18,.63),
              (s*.79,.49),(s*.55,.52),(s*.31,.72)]
        wing('Armored swept wing',plan,.424,.09,red)
        wing('Wing stripe',[(s*.70,.04),(s*.77,.09),(s*.98,.47),(s*.88,.43)],.486,.018,white,.009)
        engine_case(s*.487)
        wing('Forward canard',[(s*.53,-.58),(s*.775,-.53),(s*.877,-.30),(s*.716,-.35),(s*.543,-.37)],.454,.057,blue,.019)
        box('Canard insignia',(s*.74,-.453,.495),(.094,.048,.015),white,.005)
        box('Obsidian inlet',(s*.47,-.692,.463),(.275,.18,.162),dark,.04)
        barrel('Wingtip cannon',(s*.94,.33,.33),(s*.94,-.48,.32),.061)
        for j in range(3):
            box('Engine radiator',(s*.483,-.02+.115*j,.611),(.208,.047,.026),rubber,.008)
        plate('Canted tail',[(s*.40,.53,.48),(s*.53,1.01,.48),(s*.66,1.11,.89),(s*.62,.89,.89)],.047,blue,.020)
        barrel('Nacelle chin gun',(s*.493,-.63,.337),(s*.493,-1.022,.32),.060)
        for j in range(2):
            box('Wing linkage',(s*.66,.26+.16*j,.49),(.106,.067,.064),steel,.016,rot=(0,0,-s*.31))
    box('Dorsal brake',(0,.55,.641),(.27,.42,.058),dark,.035)


def fan(x,y,z,r):
    bpy=__import__('bpy')
    for rad,minor,h,m in [(r,.082,z,blue),(r*.83,.046,z-.017,steel),(r,.047,z+.054,white)]:
        bpy.ops.mesh.primitive_torus_add(major_segments=48,minor_segments=12,location=(x,y,h),major_radius=rad,minor_radius=minor)
        ob=bpy.context.object;ob.name='Ducted lift rotor';ob.data.materials.append(m)
        for p in ob.data.polygons:p.use_smooth=True
    beam('Turbofan bed',(x,y,z-.10),(x,y,z-.085),r*.81,r*.81,rubber,36)
    for i in range(10):
        a=i*math.pi/5
        def fanpoint(radius,theta,h):return (x+radius*math.cos(theta),y+radius*math.sin(theta),h)
        pts=[fanpoint(r*.17,a,z+.04),fanpoint(r*.72,a+.14,z+.011),fanpoint(r*.83,a+.55,z-.008),fanpoint(r*.32,a+.54,z+.012)]
        plate('Fan blade',pts,.018,steel,.008)
    ell('Rotor hub',(x,y,z+.033),(r*.23,r*.23,.093),blue)
    ell('Hub lamp',(x,y,z+.102),(r*.09,r*.09,.028),glow)


def liberator():
    swept('Liberator body',[(0,-1.16,.49,.15,.11),(0,-.97,.52,.29,.18),(0,-.53,.57,.39,.23),
                            (0,.17,.61,.39,.25),(0,.78,.55,.29,.21),(0,1.06,.51,.14,.11)],blue,dark)
    canopy(-.65,.70,.253,.30,.137)
    for s in [-1,1]:
        wing('Transverse lift spar',[(s*.19,-.31),(s*.77,-.39),(s*.90,-.14),(s*.80,.43),(s*.37,.58)],.54,.14,blue)
        fan(s*.90,.13,.64,.410)
        box('Fan support',(s*.60,.12,.51),(.48,.33,.22),dark,.06)
        swept('Fan housing jaw',[(s*.93,-.48,.57,.05,.06),(s*1.16,-.27,.56,.11,.105),
                                 (s*1.28,.13,.57,.105,.11),(s*1.18,.50,.58,.10,.085),(s*.98,.63,.58,.055,.045)],blue)
        # Three divided cowl covers protect each horizontal lift fan.
        for n in [-1,0,1]:
            angle=-math.pi/2+n*.52
            def polar(rad,t,h):return (s*(.90+rad*math.cos(angle+t)),.13+rad*math.sin(angle+t),h)
            plate('Front turbine cowl',[polar(.37,-.19,.672),polar(.49,-.19,.627),polar(.50,.20,.629),
                  polar(.37,.20,.668)],.059,blue,.018)
        for j in [0,1,2]:
            xx=s*(.87+.047*j)
            beam('Missile ports',(xx,-.34,.552),(xx,-.422,.54),.033,.031,dark,10)
        plate('Rear elevator',[(s*.25,.62,.57),(s*.60,.78,.73),(s*.71,1.04,.76),(s*.37,.94,.60)],.059,blue,.024)
        barrel('Siege projector',(s*.25,-.63,.42),(s*.25,-1.23,.36),.085)
        box('Rear radiator',(s*.16,.62,.751),(.16,.30,.071),dark,.041)
        for y in [.56,.65,.74]:
            box('Exhaust edging',(s*.16,y,.79),(.134,.022,.013),steel,.006)
    upper=__import__('bpy').data.objects['Liberator body']
    for s in (-1,1):
        panel(upper,[(s*.043,-.12),(s*.227,-.20),(s*.30,-.02),(s*.235,.22),(s*.086,.19)],blue,dark)
        panel(upper,[(s*.078,.28),(s*.240,.25),(s*.245,.48),(s*.138,.56)],steel,dark)
    wing('Recognition flash',[(-.14,-.16),(.13,-.16),(.13,-.09),(-.14,-.09)],.829,.013,white,.008)


BUILDERS={'agent':agent,'widow_mine':widow_mine,'viking':viking,'liberator':liberator}
