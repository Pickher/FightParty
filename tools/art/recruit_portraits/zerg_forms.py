"""Anatomy for the eleven recruitable Swarm organisms. +X faces the target."""
from math import cos, sin, pi
from mathutils import Vector as V

SIDES=(-1,1)

def head(a, origin, size, jaw=.65):
    x,y,z=origin
    def pt(i,j,k): return (x+size*i,y+size*j,z+size*k)
    a.ell("cranial muscle",pt(0,0,0),(size*.52,size*.37,size*.32),"skin",(0,.20,0))
    a.plate("crown and beak",pt(.035,0,.14),(size*.52,size*.43,size*.30),"ridge",(0,.26,0))
    a.ell("open gape",pt(.39,0,-.12),(size*.23,size*.28,size*.18),"dark",(0,.28,0))
    for s in SIDES:
        a.plate("cheek flange",pt(-.07,s*.32,.05),(size*.39,size*.17,size*.23),"shell",(-s*.45,.13,s*.14))
        for i in range(3):
            a.ell("ocular socket",pt(.30-i*.13,s*(.342+i*.019),.145-i*.034),
                  (size*(.136-i*.02),size*.079,size*(.095-i*.013)),"dark",(0,-.36,s*.14))
            a.ell("compound eye facet",pt(.315-i*.13,s*(.388+i*.019),.15-i*.034),
                  (size*(.104-i*.017),size*.053,size*(.070-i*.009)),"amber",(0,-.36,s*.14))
        a.tube("mandible", [pt(.09,s*.26,-.14),pt(.29,s*.37,-.24),
               pt(.52,s*.31,-.27),pt(.52+jaw*.19,s*.18,-.18)], [size*.095,size*.13,size*.079,.001],"bone",.68)
        for i in range(3):
            a.fang("saw tooth",[pt(.30+i*.078,s*(.235-i*.020),-.095),pt(.32+i*.079,s*(.225-i*.022),-.20-i*.016)],size*.029)
        a.fang("occipital spur",[pt(-.19,s*.28,.21),pt(-.41,s*.34,.30),pt(-.64,s*.32,.16)],size*.095,"shell")
    return pt

def scutes(a, centers, size=.32):
    for i,(x,w,z) in enumerate(centers):
        a.plate("dorsal shield",(x,0,z),(size,w,.26+size*.20),"ridge" if i%3==1 else "shell",(0,-.11,0))
        for s in SIDES:
            a.plate("flank pleuron",(x-.045,s*w*.65,z-.09),
                    (size*.94,w*.55,.18),"shell",(s*.61,-.17,-s*.07))

def talons(a, roots, radius=.15):
    for s in SIDES:
        for i,(x,y,z,kx,ky,kz,tx,ty) in enumerate(roots):
            h=(tx,s*ty,.17)
            a.leg("walking limb",(x,s*y,z),(kx,s*ky,kz),h,(tx+.16,s*(ty+.05),.052),radius*(1-i*.055))

def zergling(a):
    # Raked dorsal sickles, long balance tail and distinctly sprung rear hocks.
    a.ell("forward-leaning thorax",(.13,0,.63),(.78,.25,.27),"skin",(0,.17,0))
    a.ell("sprinter pelvis",(-.63,0,.74),(.41,.24,.23),"dark")
    scutes(a,[(.24,.27,.78),(-.01,.28,.83),(-.28,.25,.86),(-.52,.23,.86)],.31)
    a.tube("balance whip",[(-.75,0,.75),(-1.12,.03,.79),(-1.47,.10,.86),(-1.83,.18,.99),(-2.06,.29,1.18)],[.17,.13,.081,.045,.002],"shell")
    a.tube("lunging neck",[(.56,0,.61),(.79,0,.53),(1.01,0,.51)],[.23,.20,.15],"skin")
    head(a,(1.00,0,.49),.58,.93)
    for s in SIDES:
        a.leg("running forefoot",(.42,s*.18,.58),(.65,s*.39,.61),(.86,s*.39,.21),(1.10,s*.41,.04),.096)
        a.ell("jumping hip",(-.59,s*.19,.62),(.39,.17,.25),"shell",(0,-.52,s*.16))
        a.leg("coiled hind hock",(-.65,s*.22,.69),(-.32,s*.43,.55),(-1.03,s*.54,.31),(-.78,s*.58,.075),.14)
        a.tube("dorsal scythe humerus",[(.27,s*.18,.78),(.01,s*.38,.95),(-.20,s*.55,1.17)],[.12,.09,.080],"ridge")
        a.tube("dorsal scythe blade",[(-.20,s*.55,1.17),(.08,s*.63,1.40),(.40,s*.65,1.42),(.85,s*.60,1.20),(1.08,s*.57,1.02)],[.069,.156,.110,.060,.001],"bone",.44)
        wingroot=(-.30,s*.13,.83)
        fingers=[(-.40,s*.42,1.43),(-.78,s*.50,1.68),(-.90,s*.46,1.36),(-1.15,s*.50,1.35),(-.99,s*.35,1.13),(-1.13,s*.34,1.04),(-.82,s*.20,.88)]
        a.membrane("sprint winglet",fingers,wingroot,"rust",.025)
        for j in [1,3,5]:
            a.tube("winglet rib",[wingroot,((-.3+fingers[j][0])*.5,s*.36,(.83+fingers[j][2])*.5+.04),fingers[j]],[.05,.030,.002],"ridge")

def baneling(a):
    a.ell("inflated venom abdomen",(-.25,0,.76),(.91,.71,.73),"acid")
    a.ell("chitinous underside",(.11,0,.52),(.82,.58,.28),"dark")
    # Exposed cellular lobes form the majority of the silhouette.
    for s in SIDES:
        for x,y,z,r in [(-.63,.28,1.08,.39),(-.30,.53,.91,.38),(.01,.49,1.05,.33),(-.75,.51,.70,.29)]:
            a.ell("blister",(x,s*y,z),(r*.91,r*.78,r),"acid")
        for cx,cy,cz,rr in [(-.69,.37,1.10,.40),(-.29,.55,.92,.396),(.01,.49,1.065,.34)]:
            line=[]
            for angle in [-.10,.24,.61,.99,1.31,1.67,2.06]:
                line.append((cx+.052*sin(2*angle),s*(cy+rr*.81*sin(angle)),cz+rr*cos(angle)))
            a.tube("blister venule",line,[.006,.008,.014,.017,.014,.010,.003],"rust")
            a.ell("venom pore",(cx+.08,s*(cy+rr*.68),cz+rr*.53),(.039,.036,.033),"dark")
        a.tube("venom vein",[(-.95,s*.36,.79),(-.67,s*.64,.69),(-.34,s*.71,.74),(-.01,s*.62,.66),(.31,s*.48,.55)],
               [.02,.051,.044,.040,.023],"skin")
        a.plate("carapace clasp",(.19,s*.49,.70),(.55,.22,.25),"shell",(s*.74,.46,0))
        for x in (-.62,-.22,.14):
            a.fang("blister scute",[(x,s*.40,1.12),(x-.14,s*.45,1.30),(x-.23,s*.46,1.35)],.074,"ridge")
    scutes(a,[(.38,.53,.84),(.18,.45,1.02)],.34)
    head(a,(.69,0,.49),.65,.4)
    talons(a,[(.33,.37,.49,.67,.63,.39,.68,.67),(-.25,.42,.44,-.35,.71,.43,-.53,.79)],.104)

def roach(a):
    a.ell("low ribbed body",(-.06,0,.43),(.95,.59,.30),"dark")
    for i,(x,w,h) in enumerate([(.42,.62,.66),(.11,.81,.76),(-.26,.82,.77),(-.61,.71,.68),(-.83,.52,.56)]):
        a.plate("thick overlapping beetle shell",(x,0,h),(.48,w,.30),"obsidian",(0,-.14,0))
        for s in SIDES:
            a.plate("swept elytron",(x-.09,s*w*.63,h-.10),(.43,w*.47,.21),"obsidian",(s*.62,-.21,-s*.14))
            a.tube("chitin growth ridge",[(x+.23,s*.11,h+.22),(x+.17,s*w*.44,h+.19),(x+.02,s*w*.72,h+.06),(x-.16,s*w*.84,h-.03)],[.012,.023,.021,.003],"ridge")
    a.ell("short prognathous skull",(.86,0,.39),(.37,.37,.21),"skin")
    a.plate("low head shield",(.86,0,.49),(.40,.43,.19),"obsidian",(0,.20,0))
    for s in SIDES:
        a.ell("spitter gland",(.80,s*.343,.392),(.15,.084,.073),"aqua",(0,.14,0))
        a.ell("acid eye",(1.022,s*.267,.489),(.067,.046,.052),"amber")
        a.tube("cleft jaw",[(.89,s*.26,.34),(1.06,s*.29,.30),(1.18,s*.23,.30),(1.23,s*.17,.35)],[.084,.082,.054,.002],"bone",.66)
        for i,(x,z) in enumerate([(-.04,.80),(-.38,.76),(-.66,.68)]):
            a.fang("low elytral point",[(x,s*.51,z),(x-.22,s*.68,z+.17),(x-.50,s*.74,z+.21)],.10-i*.012,"bone")
    talons(a,[(.48,.43,.43,.75,.76,.46,.89,1.00),(.01,.44,.43,.04,.93,.49,-.18,1.11),
               (-.39,.42,.43,-.68,.81,.42,-.96,1.00)],.133)
    a.tube("abdomen point",[(-.72,0,.43),(-1.09,0,.39),(-1.31,.02,.41)],[.21,.13,.015],"obsidian")

def hydralisk(a):
    a.tube("continuous spine and coiled tail",[(-1.33,-.83,.36),(-1.26,-.65,.24),(-1.02,-.43,.24),(-.71,-.52,.22),
           (-.36,-.42,.15),(.00,-.15,.24),(.13,.01,.50),(.01,0,.83),(-.12,0,1.16),(-.09,0,1.48),(.16,0,1.72)],
           [.006,.098,.15,.20,.27,.33,.30,.27,.28,.33,.24],"skin")
    for x,y,z,sz,turn in [(-1.10,-.48,.28,.15,-.8),(-.81,-.49,.29,.19,-.36),(-.50,-.47,.29,.23,.18),(-.21,-.33,.32,.25,.53),(.03,-.11,.43,.24,1.01)]:
        a.plate("imbricated tail shield",(x,y,z),(sz*.91,sz*.96,sz*.68),"shell",(0,-.11,turn))
    for i in range(6):
        z=.47+i*.164
        for sign in SIDES:
            a.tube("ventral rib",[(.06,sign*.24,z+.085),(.20,sign*.20,z+.11),(.26,sign*.14,z+.066),(.30,sign*.025,z)],
                   [.063,.059,.043,.016],"bone" if i in (2,4) else "ridge")
    for sign in SIDES:
        root=(.22,sign*.12,1.55)
        ends=[(.25,sign*.38,1.75),(-.04,sign*.55,1.92),(-.45,sign*.58,2.06),(-.38,sign*.48,1.79),(-.62,sign*.56,1.80),
              (-.42,sign*.39,1.60),(-.57,sign*.39,1.53),(-.25,sign*.24,1.38)]
        a.membrane("cervical hood",ends,root,"obsidian",.08)
        for j in [2,4,6]:
            e=V(ends[j]);r=V(root)
            a.tube("hood rib",[r,r.lerp(e,.50)+V((0,0,.10)),e],[.077,.048,.003],"ridge")
        a.plate("hood collar",(-.02,sign*.23,1.58),(.38,.26,.25),"shell",(sign*.77,-.35,-sign*.28))
        a.tube("hook forearm",[(-.06,sign*.23,1.32),(-.13,sign*.52,1.12),(.02,sign*.77,.97),(.25,sign*.87,1.09)],[.13,.12,.081,.083],"dark")
        a.tube("raptorial sickle",[(.24,sign*.86,1.08),(.38,sign*.98,1.16),(.59,sign*1.06,1.05),(.76,sign*1.06,.75),(.73,sign*.98,.56)],
               [.08,.131,.097,.045,.002],"bone",.52)
    head(a,(.34,0,1.81),.76,1.0)
    for i in range(4):
        a.fang("vertebral thorn",[(-.29,0,.72+i*.19),(-.49,0,.88+i*.21),(-.59,0,1.00+i*.21)],.070+i*.012,"ridge")

def ravager(a):
    a.ell("high ribcage",(-.18,0,1.00),(.79,.55,.69),"rust",(0,-.22,0))
    a.ell("throat",(.30,0,.92),(.47,.36,.38),"skin",(0,.22,0))
    head(a,(.66,0,.77),.63,.68)
    for s in SIDES:
        for x,z,r in [(-.56,1.23,.34),(-.16,1.47,.39),(.19,1.30,.32)]:
            a.ell("glowing yellow-orange bile sac",(x,s*.34,z),(r*1.13,r*.83,r*1.20),"sac",(0,-.29,0))
            a.tube("laced sac wall",[(x+.20,s*.42,z-.22),(x+.09,s*.56,z-.03),(x-.06,s*.58,z+.17),(x-.23,s*.57,z+.25)],[.06,.07,.047,.009],"rust")
        for i,(x,z) in enumerate([(-.55,1.33),(-.20,1.65),(.14,1.48)]):
            a.fang("lateral crown spine",[(x,s*.48,z),(x-.12,s*.59,z+.31),(x-.31,s*.61,z+.45)],.11,"ridge")
        a.plate("high shoulder frame",(.27,s*.37,.99),(.45,.19,.31),"rust",(s*.74,.37,0))
        a.leg("long front brace",(.33,s*.38,.98),(.71,s*.75,1.00),(.84,s*.89,.20),(1.06,s*.89,.048),.15)
    talons(a,[(-.02,.43,.93,-.22,.82,1.01,-.42,.92),(-.42,.38,.77,-.83,.69,.94,-1.07,.81)],.166)
    for i,(x,z) in enumerate([(-.48,1.60),(-.14,1.86),(.17,1.65)]):
        a.tube("open dorsal mortar",[(x+.06,0,z-.28),(x-.045,0,z-.04),(x-.17,0,z+.24)],[.14,.17,.15-i*.009],"rust")
        a.ell("blackened throat",(x-.161,0,z+.24),(.127,.134,.060),"dark",(0,-.42,0))
        a.ell("hot mortar core",(x-.156,0,z+.257),(.082,.089,.045),"amber",(0,-.42,0))

def piercer(a):
    a.ell("deflated burrowing abdomen",(-.11,0,.52),(.91,.56,.31),"skin")
    scutes(a,[(.38,.46,.68),(.12,.59,.74),(-.18,.60,.73),(-.52,.51,.64)],.34)
    head(a,(.55,0,.46),.69,.55)
    for s in SIDES:
        for x,kx,ky,tx,ty,z in [(.47,.93,.76,1.12,1.00,.82),(.03,.10,1.09,-.03,1.35,.92),(-.39,-.80,.91,-1.09,1.18,.78)]:
            a.leg("stilt limb",(x,s*.38,.58),(kx,s*ky,z),(tx,s*ty,.16),(tx+.05,s*(ty+.14),.015),.119)
            a.fang("tibial thorn",[(kx,s*ky,z),(kx-.055,s*(ky+.09),z+.17),(kx-.12,s*(ky+.11),z+.27)],.074,"ridge")
        for i,(x,z,dx) in enumerate([(.28,.72,-.04),(-.02,.82,-.16),(-.36,.74,-.29),(-.60,.62,-.34)]):
            side=s*(.19 if i<3 else .14)
            a.tube("impaler quill root",[(x,side,z),(x+dx*.31,side+s*.02,z+.21),(x+dx*.56,side+s*.06,z+.41)],
                   [.108,.075,.051],"ridge",.84)
            a.fang("impaler barb",[(x+dx*.56,side+s*.06,z+.40),(x+dx*.83,side+s*.09,z+.63),(x+dx,side+s*.12,z+.74-i*.045)],.063,"bone",.76)
        a.ell("sensory pits",(.52,s*.35,.60),(.105,.055,.052),"aqua")
    a.tube("spinal keel",[(-.79,0,.51),(-1.03,0,.47),(-1.14,.02,.53)],[.17,.081,.006],"shell")

def tunneler(a):
    a.ell("brood vault",(-.24,0,.72),(.98,.72,.62),"skin",(0,-.12,0))
    scutes(a,[(.54,.55,.80),(.29,.60,.96),(-.77,.46,.89)],.33)
    head(a,(.78,0,.52),.65,.52)
    # Seed-like paired hatching pits sit on top of a single armored dome.
    for x,y,z,r in [(-.76,0,1.20,.24),(-.44,-.30,1.27,.23),(-.43,.30,1.27,.23),(-.10,0,1.40,.23),
                       (-.01,-.44,1.21,.19),(-.01,.44,1.21,.19),(.21,-.19,1.26,.17),(.21,.19,1.26,.17)]:
        a.ell("hatch base",(x,y,z),(r*1.02,r*.91,r*.47),"obsidian",(0,-.16,0))
        a.ell("brood well",(x,y,z+r*.40),(r*.73,r*.61,r*.12),"dark",(0,-.13,0))
        a.ell("hatching pupa",(x+.016,y,z+r*.50),(r*.46,r*.37,r*.27),"sac",(0,-.10,0))
        ring=[(x+r*.78*cos(j*pi/8),y+r*.66*sin(j*pi/8),z+r*(.47+.12*cos(j*pi/8))) for j in range(17)]
        a.tube("raised segmented hatch rim",ring,[r*(.13+.024*sin(j*pi/2)) for j in range(17)],"bone")
    for s in SIDES:
        for i,x in enumerate([-.74,-.42,-.11,.18]):
            a.plate("pleural rim",(x,s*(.46+.06*sin(i)),.84),(.29,.25,.27),"shell",(s*.76,-.17,0))
            a.fang("ridge point",[(x,s*.53,.96),(x-.17,s*.60,1.10),(x-.28,s*.61,1.13)],.075,"bone")
        a.ell("thoracic spiracle",(.42,s*.43,.76),(.14,.06,.09),"acid")
        a.leg("digging forearm",(.47,s*.32,.65),(.73,s*.70,.74),(.77,s*.82,.18),(1.08,s*.84,.035),.16)
        a.tube("shovel edge",[(.77,s*.82,.18),(.90,s*.84,.22),(1.08,s*.86,.18),(1.17,s*.80,.10)],[.08,.11,.072,.003],"bone",.61)
    talons(a,[(-.03,.47,.56,-.02,.77,.60,-.22,.86),(-.47,.43,.53,-.76,.74,.57,-.97,.79)],.127)

def infestor(a):
    # Long, low, translucent gut with scute collars and small limbs toward the head.
    for i in range(7):
        t=i/6
        x=.62-i*.31
        w=(.39+.20*sin(pi*t))*(1-.44*t*t)
        z=.41+.105*sin(pi*t)
        a.ell("gastric segment",(x,.08*sin(t*2.9),z),(max(.21,.37-.07*t),w,w*.92),"skin",(0,.06,0))
        a.plate("abdominal collar",(x-.105,.08*sin(t*2.9),z+.13),(.23,w*1.16,w*.75),"ridge",(0,-.11,0))
        for s in SIDES:
            a.ell("subdermal gland",(x+.06,s*w*.79+.08*sin(t*2.9),z+.08),(.18*(1-.22*t),.12,.15*(1-.18*t)),"acid")
            a.tube("flank seam",[(x+.10,s*w*.67,z-.05),(x-.04,s*w*.93,z-.08),(x-.14,s*w*.74,z-.19)],[.046,.045,.014],"dark")
    a.plate("cephalic hood",(.79,0,.56),(.47,.42,.43),"shell",(0,.08,0))
    head(a,(1.04,0,.43),.55,.35)
    for s in SIDES:
        for i,x in enumerate([.70,.43,.20,-.04]):
            a.leg("belly leg",(x,s*.28,.37),(x+.05,s*(.53+i*.022),.38),(x+.16,s*(.67+i*.01),.08),(x+.24,s*.71,.04),.070)
        for i in range(2):
            a.tube("feeler",[(1.16,s*.20,.36),(1.35,s*(.24+i*.11),.29),(1.44,s*(.31+i*.14),.14),(1.65-i*.12,s*(.38+i*.14),.20)],[.057,.040,.025,.003],"skin")
        for i in range(3):
            x=-.06-i*.38
            a.ell("dorsal bulla",(x,s*.24,.91-i*.035),(.19,.16,.18),"acid")
    a.tube("tail seam",[(-1.26,.03,.38),(-1.51,.07,.33),(-1.67,.13,.22),(-1.83,.22,.27)],[.27,.18,.075,.005],"skin")

def mutalisk(a):
    a.ell("flight thorax",(0,0,1.0),(.59,.30,.31),"skin",(0,.14,0))
    a.plate("shoulder plate",(-.12,0,1.11),(.55,.34,.29),"shell",(0,-.12,0))
    a.tube("serpentine flight tail",[(-.23,0,.97),(-.59,.08,.87),(-.93,.25,.75),(-1.19,.53,.62),(-1.41,.76,.70),(-1.51,.99,.94)],
           [.27,.23,.16,.13,.084,.005],"skin")
    for i in range(4):
        a.plate("tail scale",(-.46-i*.22,.042+i*i*.043,1.03-i*.092),(.22-i*.019,.22-i*.029,.17-i*.024),"ridge",(0,-.35,0))
    a.tube("neck",[(.17,0,.93),(.43,0,1.00),(.62,0,1.13)],[.26,.22,.16],"skin")
    head(a,(.72,0,1.12),.62,.85)
    for s in SIDES:
        shoulder=(.04,s*.18,1.07)
        wrist=(.15,s*.87,1.55)
        fingers=[(.37,s*1.78,1.60),(-.37,s*1.79,1.68),(-1.05,s*1.34,1.68),(-1.18,s*.77,1.49),(-.69,s*.28,1.13)]
        outlines=[wrist,fingers[0],(-.015,s*1.47,1.62),fingers[1],(-.50,s*1.23,1.60),fingers[2],(-.67,s*.93,1.46),fingers[3],(-.64,s*.50,1.35),fingers[4]]
        a.membrane("scalloped flight membrane",outlines,shoulder,"wing",.16)
        a.tube("wing arm",[shoulder,(-.11,s*.53,1.24),wrist],[.17,.102,.074],"shell")
        for i,tip in enumerate(fingers[:-1]):
            start=V(wrist);end=V(tip)
            mid=start.lerp(end,.53)+V((.028,0,.054))
            a.tube("finger spar",[start,mid,end],[.052 if i==0 else .034,.031 if i==0 else .019,.005],"ridge")
        a.fang("carpal talon",[wrist,(.25,s*.92,1.65),(.37,s*.96,1.66)],.056,"bone")
        a.tube("wing muscle",[shoulder,(-.14,s*.38,1.08),(-.37,s*.47,.99)],[.14,.097,.023],"skin")
        a.fang("hooked hind claw",[(-.17,s*.17,.84),(-.08,s*.33,.72),(-.19,s*.39,.64)],.09,"bone")
    a.fang("tail stinger",[(-1.31,.66,.68),(-1.49,.77,.68),(-1.68,.89,.57)],.092,"bone")
    for i in range(3):
        a.fang("flight crest",[(.62-i*.18,0,1.25-i*.02),(.44-i*.23,0,1.46-i*.04),(.34-i*.24,0,1.43-i*.04)],.065,"ridge")

def ultralisk(a):
    a.ell("armored torso",(-.12,0,.98),(1.06,.60,.68),"skin",(0,-.06,0))
    scutes(a,[(.35,.69,1.26),(.03,.70,1.36),(-.32,.63,1.28),(-.65,.50,1.12)],.44)
    head(a,(.71,0,.81),.90,1.02)
    for s in SIDES:
        for x,y,z,kx,ky,kz,tx,ty in [(.42,.38,.91,.46,.60,.64,.56,.68),(-.35,.43,.85,-.64,.64,.72,-.71,.72)]:
            a.leg("armored pillar",(x,s*y,z),(kx,s*ky,kz),(tx,s*ty,.20),(tx+.25,s*(ty+.02),.048),.239)
            a.plate("leg shield",(kx,s*(ky+.035),kz+.04),(.32,.18,.24),"shell",(s*.94,-.21,0))
        root=(.38,s*.44,.91)
        a.tube("tusk socket",[root,(.45,s*.70,.72),(.54,s*.88,.60)],[.23,.20,.145],"ridge")
        a.tube("kaiser blade",[(.52,s*.85,.61),(.75,s*1.05,.55),(1.14,s*1.14,.67),(1.47,s*1.10,.96),(1.60,s*.96,1.27)],
               [.13,.162,.142,.085,.003],"bone",.60)
        a.fang("inner mandible",[(.68,s*.30,.66),(.85,s*.49,.49),(1.13,s*.55,.52),(1.34,s*.49,.70)],.116,"bone",.62)
        a.fang("shoulder tusk",[(.08,s*.43,1.45),(-.03,s*.55,1.67),(-.22,s*.60,1.74)],.12,"bone")
    a.tube("armored tail",[(-.82,0,.91),(-1.22,.07,.81),(-1.45,.10,.66)],[.265,.155,.019],"shell")

def brood_lord(a):
    # Broad, solid dorsal mantle in contrast with the folding wings of a Mutalisk.
    a.ell("floating nursery",(-.13,0,1.11),(1.01,.59,.38),"skin")
    a.plate("central dorsal keel",(-.04,0,1.22),(1.06,.63,.36),"shell",(0,.025,0))
    for s in SIDES:
        root=(.10,s*.26,1.23)
        edge=[(.78,s*.41,1.19),(.45,s*.89,1.09),(.12,s*1.29,1.16),(-.24,s*1.83,1.28),(-.48,s*1.48,1.12),
              (-.77,s*1.24,1.06),(-.99,s*1.07,1.19),(-.93,s*.84,1.03),(-1.13,s*.63,1.05),(-.90,s*.42,1.10)]
        a.membrane("thick serrated mantle",edge,root,"shell",.15)
        for i,(x,y,z,angle) in enumerate([(.02,.53,1.26,-.18),(-.12,.79,1.24,-.38),(-.18,1.05,1.21,-.52),(-.25,1.29,1.23,-.64)]):
            a.plate("mantle finger",(x,s*y,z),(.54-i*.064,.25-i*.021,.142-i*.016),"ridge" if i%2==0 else "shell",(s*.13,-.09,s*angle))
        a.tube("wing spar",[(.58,s*.37,1.18),(.32,s*.82,1.14),(.02,s*1.30,1.21),(-.24,s*1.83,1.28)],[.125,.109,.068,.005],"ridge")
        for i,(x,y,z) in enumerate([(.21,.42,.91),(-.12,.56,.89),(-.43,.52,.90),(-.63,.36,.94)]):
            a.ell("brood cargo",(x,s*y,z-.11),(.21,.158,.25),"sac",(0,-.29,0))
            a.tube("brood clamp",[(x-.18,s*y,z+.09),(x-.16,s*(y+.1),z-.07),(x-.02,s*(y+.14),z-.22)], [.063,.039,.012],"shell")
        a.fang("nose mandible",[(.59,s*.30,1.12),(.85,s*.45,1.13),(1.19,s*.49,1.03),(1.29,s*.40,.91)],.114,"bone",.70)
        a.tube("ventral tendon",[(-.50,s*.20,.92),(-.76,s*.34,.76),(-.87,s*.38,.48),(-.98,s*.30,.30)],
               [.115,.086,.047,.003],"skin")
    for i in range(5):
        x=.45-i*.29
        a.plate("spinal scute",(x,0,1.39),(.26,.28,.15),"ridge",(0,-.17,0))
        if i>0: a.fang("mantle crest",[(x,0,1.46),(x-.14,0,1.64),(x-.27,0,1.69)],.075,"bone")
    head(a,(.77,0,1.10),.59,.83)

UNITS={fn.__name__:fn for fn in (
    zergling,baneling,roach,hydralisk,ravager,piercer,tunneler,mutalisk,infestor,ultralisk,brood_lord
)}
