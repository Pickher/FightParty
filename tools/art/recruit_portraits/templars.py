"""Sculpted Protoss character busts for FightParty's recruitment cards.

The eye sockets, cranial ridges, armatures, raised filigree and layered castings
are modeled relief, so the same three-quarter light works across all four.
"""
import math

import bpy
import bmesh
from mathutils import Vector

from studio import M, mat, ell


def mesh(name, vertices, faces, materials, indices=None, smoothing=1):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    for material in materials:
        data.materials.append(material)
    if indices:
        for face, index in zip(data.polygons, indices):
            face.material_index = index
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    for face in data.polygons:
        face.use_smooth = True
    ob = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(ob)
    if smoothing:
        modifier = ob.modifiers.new("Sculpted curvature", 'SUBSURF')
        modifier.levels = smoothing
        modifier.render_levels = smoothing
    return ob


def rings(name, rows, materials, material_bands=None, smoothing=1):
    n = len(rows[0])
    verts = [tuple(p) for row in rows for p in row]
    faces = [tuple(reversed(range(n)))]
    indices = [0]
    for k in range(len(rows) - 1):
        for i in range(n):
            j = (i + 1) % n
            faces.append((k*n+i, k*n+j, (k+1)*n+j, (k+1)*n+i))
            indices.append(material_bands[k] if material_bands else 0)
    faces.append(tuple(range((len(rows)-1)*n, len(rows)*n)))
    indices.append(material_bands[-1] if material_bands else 0)
    return mesh(name, verts, faces, materials, indices, smoothing)


def shell(name, contour, crown, enamel, edging=None, smoothing=1):
    """Dished panel with return flange, gold lip, and convex central casting."""
    border = [Vector(p) for p in contour]
    center = sum(border, Vector()) / len(border)
    relief = Vector(crown) - center
    # Paired vertices on either side of each outline corner keep the chamfer
    # locally rounded without melting the entire casting into an oval.
    if smoothing:
        original = border
        border = []
        for i,p in enumerate(original):
            border.extend((p.lerp(original[i-1],.18),p.lerp(original[(i+1)%len(original)],.18)))
    rows = []
    for radius, depth in ((.92,-.35),(1.,-.10),(1.,.04),(.972,.15),
                          (.92,.25),(.884,.27),(.87,.20),(.846,.27),
                          (.67,.55),(.43,.75),(.20,.91),(.055,.99)):
        rows.append([center + (p-center)*radius + relief*depth for p in border])
    return rings(name, rows, [M["recess"], edging or M["gold"], enamel],
                 [0,0,1,1,1,0,1,2,2,2,2], smoothing)


def sweep(name, controls, material, sides=10, plane=(0, 1, 0), smoothing=2):
    """Elliptical sections following an artist-drawn centre line."""
    points = [Vector(p[:3]) for p in controls]
    rows = []
    for i, p in enumerate(points):
        axis = (points[min(i+1,len(points)-1)] - points[max(0,i-1)]).normalized()
        cross = axis.cross(Vector(plane))
        if cross.length < .1:
            cross = axis.cross(Vector((1,0,0)))
        cross.normalize()
        depth = axis.cross(cross).normalized()
        a, b = controls[i][3:]
        rows.append([p + a*math.cos(j*math.tau/sides)*cross
                       + b*math.sin(j*math.tau/sides)*depth for j in range(sides)])
    return rings(name,rows,[material],smoothing=smoothing)


def sectioned(name, sections, material, n=18, smoothing=2, flutes=0):
    rows = []
    for x,y,z,w,d in sections:
        row = []
        for i in range(n):
            theta = i*math.tau/n
            modulation = 1 + flutes*math.cos(7*theta)
            row.append((x+w*math.cos(theta)*modulation, y+d*math.sin(theta)*modulation,z))
        rows.append(row)
    return rings(name,rows,[material],smoothing=smoothing)


def side(points, sign):
    return [(sign*p[0], *p[1:]) for p in points]


def custom(name, color, metal=0, rough=.40, glow=0):
    return mat(name,color,metal,rough,glow)


def face(origin, size, skin, ridge, eye, framed=True, long=1.):
    """A single tapered mouthless cranium, inset luminous eyes and paired malar keels."""
    ox,oy,oz=origin
    def p(x,y,z):
        return (ox+x*size,oy+y*size,oz+z*size)
    def sp(points,s=1):
        return [(*p(s*x,y,z),w*size,d*size) for x,y,z,w,d in points]
    def orb(name, c, radii, material):
        return ell(name,p(*c),tuple(v*size for v in radii),material)
    profile = [(-.43,-.14,.042,.055),(-.38,-.13,.14,.15),(-.22,-.06,.245,.238),
               (-.045,-.01,.32,.265),(.14,.005,.353,.293),(.34,.037,.328,.304),
               (.50,.084,.26,.25),(.62,.123,.14,.16),(.67,.13,.045,.048)]
    sectioned("Cranium", [(*p(0,y,z*long),w*size,d*size) for z,y,w,d in profile],skin)
    for s in (-1,1):
        socket=[(.035,-.301,.112,.007,.007),(.081,-.297,.132,.049,.031),
                (.170,-.276,.155,.067,.029),(.243,-.233,.182,.061,.030),
                (.297,-.182,.209,.026,.016),(.316,-.153,.211,.005,.005)]
        sweep("Orbital recess",sp(socket,s),M["recess"])
        iris=[(.059,-.317,.12,.003,.004),(.111,-.322,.14,.026,.012),
              (.178,-.300,.157,.032,.012),(.239,-.264,.184,.024,.012),
              (.290,-.212,.202,.003,.002)]
        sweep("Bioluminescent eye",sp(iris,s),eye)
        # Raised brows and two converging cheeks shape the characteristic long face.
        sweep("Supraorbital ridge",sp([(.014,-.260,.24,.016,.015),
              (.082,-.292,.240,.051,.045),(.181,-.248,.260,.069,.048),
              (.297,-.134,.268,.064,.054),(.324,-.025,.218,.021,.028)],s),ridge)
        sweep("Malar ridge",sp([(.305,-.103,.125,.022,.030),(.26,-.200,.034,.056,.046),
              (.184,-.261,-.073,.048,.049),(.102,-.277,-.198,.038,.038),
              (.052,-.204,-.335,.006,.011)],s),ridge)
        sweep("Lower jaw",sp([(.292,-.040,.053,.02,.022),(.25,-.093,-.106,.053,.053),
              (.175,-.135,-.260,.04,.049),(.073,-.165,-.365,.008,.015)],s),skin)
        if framed:
            sweep("Temple inlay",sp([(.300,-.087,.225,.008,.012),(.336,.010,.261,.034,.030),
                  (.306,.083,.423,.026,.032),(.223,.130,.553,.008,.014)],s),M["gold"])
    sweep("Central nasal keel",sp([(0,-.265,.367,.022,.029),(0,-.291,.25,.063,.042),
          (0,-.303,.122,.049,.049),(0,-.296,.004,.032,.045),(0,-.274,-.093,.018,.013)]),ridge)
    return p


def collar_gem(c,w):
    x,y,z=c
    diamond=[(x,y,z+w*1.4),(x+w,y,z),(x,y,z-w*1.4),(x-w,y,z)]
    shell("Inset chrysalis",diamond,(x,y-w*.57,z),M["teal"],M["bronze"],0)
    shell("Core light",[(x+(a-x)*.52,b-w*.24,z+(d-z)*.52) for a,b,d in diamond],
          (x,y-w*.68,z),M["plasma"],M["teal"],0)


def pauldron(s, broad=1., high=0., enamel=None):
    xy=[(.33,-.17,1.20),(.46,-.09,1.41+high),(.75,.07,1.51+high),
        (.96,.14,1.39+high),(1.09,.04,1.18),(.986,-.19,.96),(.70,-.36,.994),
        (.48,-.39,1.065)]
    pts=side([(x*broad,y,z) for x,y,z in xy],s)
    shell("Layered shoulder carapace",pts,(s*.76*broad,-.48,1.30+high),enamel or M["gold"],M["bronze"])
    p=[(.52,-.364,1.10),(.72,-.415,1.07),(.96,-.23,1.066),(.93,-.22,.973),(.718,-.35,.920),(.53,-.37,.981)]
    shell("Shoulder under-lamella",side([(x*broad,y,z) for x,y,z in p],s),(s*.755*broad,-.400,1.016),M["gold_dark"],M["bronze"])


def cuirass(width=1., pearl=False):
    sectioned("Indigo muscle armour",[(0,.06,.06,.35*width,.26),(0,.04,.22,.44*width,.32),
          (0,.02,.55,.56*width,.37),(0,.04,.94,.77*width,.36),(0,.06,1.15,.71*width,.29),
          (0,.07,1.31,.25*width,.20)],M["indigo"])
    for s in (-1,1):
        shape=[(.04,-.29,1.23),(.30,-.27,1.28),(.62,-.18,1.24),(.75,-.12,1.09),
               (.58,-.27,.88),(.167,-.37,.65),(.032,-.38,.81)]
        shell("Pectoral shield",side([(x*width,y,z) for x,y,z in shape],s),
              (s*.32*width,-.53,1.065),M["ivory"] if pearl else M["gold"])
        for i in range(2):
            z=.67-.21*i
            lam=[(.015,-.34,z+.123),(.34,-.34,z+.186),(.51,-.18,z+.22),
                 (.49,-.22,z+.021),(.095,-.34,z-.196),(.023,-.36,z-.11)]
            shell("Abdominal lamella",side([(x*width,y,d) for x,y,d in lam],s),
                  (s*.22*width,-.424,z+.014),M["gold_dark"] if i else M["gold"],M["bronze"])
    collar_gem((0,-.40,.99),.066)
    sectioned("Neck seal",[(0,.03,1.14,.21,.23),(0,.01,1.30,.252,.222),
               (0,.00,1.46,.184,.167),(0,.025,1.56,.166,.16)],M["recess"])


def vanguard():
    skin=custom("Warrior hide","647989",.14,.39)
    ridge=custom("Warrior cranial plate","849399",.20,.34)
    cuirass()
    for s in (-1,1):
        pauldron(s)
        sweep("Armoured sinew",side([(.57,.02,1.09,.18,.17),(.81,.012,.96,.219,.189),
              (.89,-.016,.79,.175,.16),(.88,-.11,.64,.133,.13)],s),M["indigo"])
        sweep("Gauntlet inner sleeve",side([(.88,-.022,.65,.14,.15),(.86,-.22,.61,.175,.17),
              (.80,-.42,.67,.175,.16),(.74,-.57,.78,.14,.12)],s),M["alloy"])
        br=[(.94,-.15,.81),(.99,-.27,.76),(.92,-.55,.87),(.86,-.66,.90),
            (.69,-.63,.69),(.70,-.46,.54),(.79,-.25,.51)]
        shell("Psi bracer",side(br,s),(s*.89,-.48,.73),M["gold"])
        # Flexible glove with separate overlapping knuckle plates.
        ell("Closed warrior glove",(s*.744,-.61,.74),(.139,.125,.142),M["indigo"])
        for i in range(3):
            x=.659+i*.072
            sweep("Gold knuckle",side([(x,-.622,.795,.042,.034),
                  (x+.012,-.691,.801,.046,.036),(x+.019,-.718,.747,.044,.031),
                  (x+.016,-.703,.685,.031,.026)],s),M["gold"],8)
        # A steel outer-face bail curves across the emitter instead of
        # leaving the travelling end of the plate smooth.
        sweep("Emitter feed",side([(.998,-.254,.751,.018,.018),(.959,-.369,.799,.026,.020),
              (.890,-.543,.852,.025,.020),(.825,-.588,.851,.012,.010)],s),M["alloy"],8)
        # Wrist emitters have solid nacre flanks and a narrow hot edge.
        k = 1.0 if s>0 else .92
        outline=[(.71,-.60,.83),(.80,-.63,.79),(.974,-.65,1.065),
                 (1.15,-.66,1.86*k),(.91,-.635,1.29),(.785,-.595,1.025)]
        shell("Psi wrist blade",side(outline,s),(s*.91,-.682,1.14),M["plasma"],M["teal"],0)
        sweep("Blade current",side([(.789,-.663,.857,.021,.015),(.946,-.686,1.152,.026,.013),
                                    (1.145,-.672,1.85*k,.002,.002)],s),M["pale"],6,smoothing=1)
    face((0,-.01,1.60),1.0,skin,ridge,M["plasma"])
    for s in (-1,1):
        crown=[(.05,-.14,1.96),(.105,-.205,1.99),(.245,-.169,2.076),
               (.31,-.005,2.264),(.196,.162,2.368),(.095,.286,2.444),
               (.135,.038,2.185),(.052,-.089,2.075)]
        shell("Flared diadem",side(crown,s),(s*.20,-.259,2.112),M["gold"],M["bronze"])
        for i in range(3):
            x=.17+i*.07
            sweep("Nerve cord",side([(x,.155,1.969,.082,.075),
                  (x+.145,.257,1.80,.075,.068),(x+.17,.310,1.56,.060,.061),
                  (x+.22,.298,1.40,.044,.045),(x+.19,.278,1.22+i*.045,.015,.018)],s),M["indigo"])
    collar_gem((0,-.253,1.977),.048)
    for s in (-1,1):
        p=[(.15,-.268,1.994),(.216,-.229,2.031),(.262,-.16,2.176),(.299,-.10,2.27),
           (.197,-.085,2.213),(.13,-.145,2.08)]
        shell("Helm cheek ridge",side(p,s),(s*.226,-.261,2.116),M["ivory"])
    shell("Cranial key",[(0,-.284,2.160),(.068,-.289,2.080),(.047,-.278,2.020),
                         (0,-.280,1.985),(-.051,-.278,2.02),(-.067,-.289,2.08)],
          (0,-.338,2.076),M["gold_dark"])
    for s in (-1,1):
        sweep("Breastplate pinstripe",side([(.087,-.403,1.105,.009,.007),(.19,-.481,1.096,.013,.009),
              (.33,-.513,1.102,.012,.009),(.48,-.422,1.136,.008,.006)],s),M["ivory"],8)



def adept():
    skin=custom("Adept skin","687185",.14,.41)
    ridge=custom("Adept cheek ridges","9892A0",.17,.36)
    pearl=custom("Adept nacre","D1D6DB",.54,.24)
    violet=custom("Adept silk","34304B",.23,.39)
    cuirass(.78,True)
    # A curved asymmetric lance, shaped to leave the face readable behind it.
    for s in (-1,1):
        feather=[(.28,-.156,1.225),(.38,-.083,1.43),(.62,.030,1.508),
                 (.91,.23,1.57),(.84,.060,1.293),(.70,-.091,1.111),(.43,-.295,1.095)]
        shell("Adept winged spaulder",side(feather,s),(s*.602,-.295,1.364),pearl,M["gold"])
        sweep("Flexible upper arm",side([(.47,.03,1.158,.132,.129),(.66,.02,1.002,.149,.137),
                                      (.698,-.035,.808,.129,.111),(.71,-.067,.65,.099,.09)],s),violet)
        br=[(.63,-.082,.822),(.74,-.11,.825),(.844,-.281,.713),(.79,-.449,.603),
            (.62,-.443,.572),(.61,-.268,.62)]
        shell("Wrist resonator",side(br,s),(s*.745,-.338,.740),pearl)
        for i in range(3):
            finger=[(.67+i*.037,-.393,.674,.036,.033),(.68+i*.038,-.475,.65,.035,.031),
                    (.69+i*.03,-.496,.568+i*.014,.021,.02)]
            sweep("Armoured fingers",side(finger,s),M["gold_dark"],sides=8)
    face((0,-.055,1.622),.89,skin,ridge,M["plasma"],framed=False,long=1.07)
    # Swept back crest and articulated auricular tiles distinguish the Adept's helm.
    for s in (-1,1):
        plate=[(.038,-.200,1.828),(.145,-.220,1.902),(.265,-.15,1.894),(.367,-.030,1.935),
               (.33,.174,2.08),(.18,.37,2.205),(.099,.61,2.207),
               (.130,.272,2.026),(.205,.18,1.894),(.264,.11,1.695),(.20,-.079,1.734)]
        shell("Swept back crown",side(plate,s),(s*.26,-.208,1.995),pearl,M["gold"])
        sweep("Crown filigree",side([(.132,-.239,1.923,.014,.010),(.279,-.230,1.978,.022,.014),
          (.301,-.154,2.038,.017,.014),(.193,.226,2.142,.006,.009)],s),M["gold"],8)
        for i in range(3):
            sweep("Adept head tendril",side([(.16+i*.054,.150,1.891,.050,.051),
                  (.299+i*.049,.310,1.713,.057,.050),(.292+i*.070,.399,1.505,.047,.046),
                  (.245+i*.056,.417,1.309,.040,.041),(.346+i*.063,.413,1.157+i*.047,.012,.018)],s),
                  M["indigo"],9)
        collar=[(.033,-.320,1.15),(.118,-.263,1.321),(.307,-.154,1.391),
                (.352,-.180,1.212),(.206,-.363,.978)]
        shell("Gorget",side(collar,s),(s*.191,-.391,1.22),M["gold"])
    # The open glaive carries its blue edge on two hooked vanes of different lengths.
    ell("Glaive focus mounting",(.747,-.502,.710),(.124,.107,.142),M["bronze"])
    ell("Glaive focus",(.745,-.60,.73),(.077,.042,.089),M["plasma"])
    for flip in (-1,1):
        cx,cy,cz=.745,-.527,.73
        # Outer arm is deliberately long and curves back over the focus.
        if flip==1:
            points=[(.027,0,.001,.078,.052),(.183,-.012,.018,.103,.055),
                (.325,-.022,.182,.104,.055),(.378,-.019,.367,.074,.042),
                (.341,-.015,.547,.048,.025),(.260,-.011,.709,.007,.006)]
        else:
            points=[(-.014,0,-.008,.071,.040),(-.101,.002,-.118,.082,.048),
                (-.077,-.002,-.277,.078,.040),(.039,-.008,-.391,.056,.031),
                (.178,-.005,-.471,.007,.006)]
        sweep("Glaive casting",[(cx+x,cy+y,cz+z,w,d) for x,y,z,w,d in points],M["gold"],12)
        sweep("Glaive wave edge",[(cx+x+.015*flip,cy+y-.036,cz+z,max(.004,w*.40),max(.003,d*.34))
                                   for x,y,z,w,d in points],M["plasma"],8)
    collar_gem((0,-.259,1.946),.042)
    # Sweep the casque back into a fin above the face. Distinct in the small card.
    sweep("Adept sagittal crest",[(0,-.221,1.913,.042,.029),(0,-.208,2.037,.078,.075),
          (0,-.056,2.168,.075,.123),(0,.194,2.245,.052,.129),
          (0,.424,2.250,.037,.078),(0,.636,2.202,.008,.015)],M["teal"])
    for s in (-1,1):
        sweep("Circlet tendril",side([(.055,-.251,1.974,.017,.012),(.089,-.215,2.103,.020,.014),
              (.107,-.09,2.159,.018,.013),(.106,.111,2.224,.007,.006)],s),M["gold"],8)



def drape(name,origin,width,height,material,points,depth=.12):
    ox,oy,oz=origin
    rows=[]
    for t in (0,.02,.14,.35,.61,.86,.98,1):
        line=[]
        for j in range(13):
            u=j/12
            x=(u-.5)*width
            folds=math.cos(u*math.pi*6+.65*t)*depth*math.sin(math.pi*u)
            z=oz + height*t + points(u)*(1-t)
            y=oy+folds*(1-.46*t)+.16*(1-t)**2+.045*abs(2*u-1)
            line.append((ox+x*(1-.30*t),y,z))
        rows.append(line)
    verts=[p for row in rows for p in row]
    faces=[(j*13+i,j*13+i+1,(j+1)*13+i+1,(j+1)*13+i)
           for j in range(len(rows)-1) for i in range(12)]
    ob=mesh(name,verts,faces,[material],smoothing=2)
    solid=ob.modifiers.new("Woven hem",'SOLIDIFY')
    solid.thickness=.018
    return ob


def high_templar():
    skin=custom("Elder skin","715F81",.05,.46)
    ridge=custom("Elder aspect","A191AC",.16,.34)
    cloth=custom("Temple mantle","263A62",.21,.46)
    weft=custom("Temple tabard","586A8A",.16,.41)
    sectioned("Robed torso",[(0,.03,.05,.45,.27),(0,.035,.21,.50,.33),
          (0,.05,.55,.53,.38),(0,.045,.92,.56,.33),(0,.10,1.17,.50,.26),
          (0,.10,1.28,.23,.19)],cloth,24,2,.060)
    drape("Split deep-blue stole",(0,-.24,.025),1.05,1.07,cloth,lambda u:.12*abs(2*u-1),.095)
    drape("Pale central tabard",(0,-.322,.075),.31,1.05,weft,lambda u:.10*abs(2*u-1),.022)
    for s in (-1,1):
        # The shawl's edge sweeps upward around the neck instead of a warrior's dome.
        wide=[(.04,-.205,1.35),(.26,.025,1.46),(.53,.20,1.52),(.85,.31,1.54),
              (1.02,.150,1.35),(.94,-.016,1.172),(.66,-.160,1.021),
              (.33,-.317,.79),(.091,-.323,.653)]
        shell("Brocade mantle",side(wide,s),(s*.48,-.277,1.214),cloth,M["gold"])
        scarf=[(.04,-.225,1.365),(.27,-.019,1.503),(.68,.15,1.565),
               (.82,.26,1.629),(.75,.074,1.385),(.525,-.110,1.269),(.249,-.295,1.098),(.095,-.344,.945)]
        shell("High priest's gorget",side(scarf,s),(s*.41,-.26,1.352),M["ivory"],M["gold"])
        for i in range(2):
            sweep("Gilded vestment seam",side([(.09+i*.035,-.352,1.03,.018,.013),
                (.187+i*.049,-.350,.88,.023,.013),(.286+i*.065,-.368,.68,.022,.012),
                (.270+i*.076,-.350,.42,.018,.010),(.338+i*.063,-.273,.18,.009,.007)],s),M["gold"],8)
        sweep("Sleeved arms",side([(.61,.095,1.22,.15,.15),(.78,.00,1.024,.224,.202),
              (.794,-.035,.807,.239,.215),(.72,-.14,.587,.170,.159)],s),cloth)
    face((0,-.012,1.586),.93,skin,ridge,M["plasma"],framed=False,long=1.03)
    for s in (-1,1):
        tiara=[(.074,-.196,1.877),(.194,-.165,1.938),(.292,-.127,2.103),
               (.341,-.032,2.291),(.397,.069,2.504),(.47,.128,2.585),
               (.43,.231,2.322),(.39,.24,2.061),(.334,.144,1.875),
               (.283,.11,1.65),(.205,-.041,1.604),(.227,-.07,1.807)]
        shell("Temple crown antler",side(tiara,s),(s*.326,-.241,2.052),M["gold"],M["bronze"])
        sweep("Coronet recess",side([(.273,-.245,1.889,.025,.021),
             (.325,-.252,2.061,.034,.020),(.349,-.196,2.193,.018,.014),
             (.397,-.093,2.39,.006,.008)],s),M["teal"])
        for i in range(3):
            sweep("Long nerve plait",side([(.20+.026*i,.153,1.91,.055,.051),
               (.33+.036*i,.123,1.647,.059,.051),(.25+.050*i,-.05,1.442,.047,.044),
               (.22+.043*i,-.122,1.279,.039,.037),(.13+.031*i,-.21,1.142,.011,.012)],s),ridge,9)
    # Folded hood has depth behind the jaw and a textile lining visible on both sides.
    for s in (-1,1):
        hood=[(.052,.007,2.196),(.18,.064,2.252),(.315,.139,2.170),
              (.399,.218,1.960),(.421,.191,1.486),(.504,.224,1.26),
              (.249,-.068,1.332),(.205,-.053,1.61),(.278,-.031,1.890),
              (.20,-.126,2.055),(.086,-.133,2.123)]
        shell("Navy cowl",side(hood,s),(s*.35,-.111,1.906),cloth,M["gold_dark"])
    # The off hand is held against the sash in a composed counter-gesture.
    sweep("Tucked left forearm",[(-.73,-.045,.69,.137,.118),(-.744,-.198,.651,.137,.119),
          (-.637,-.304,.661,.120,.111),(-.527,-.366,.727,.085,.085)],weft)
    ell("Left hand",(-.474,-.379,.731),(.106,.074,.078),skin)
    for i in range(3):
        sweep("Left folded finger",[(-.501,-.408,.746-i*.023,.030,.024),
              (-.430,-.434,.777-i*.028,.032,.022),(-.368,-.424,.770-i*.032,.013,.011)],ridge,8)
    collar_gem((0,-.349,.954),.079)
    # An upturned three-fingered hand gathers the storm near the camera.
    sweep("Forearm",[(.735,-.031,.70,.110,.102),(.81,-.209,.68,.129,.117),
          (.89,-.367,.811,.103,.096),(.915,-.432,.877,.081,.080)],M["bronze"])
    ell("Palm",(.905,-.451,.904),(.139,.136,.089),skin)
    for i,(dx,dy,dz) in enumerate([(.110,.025,.13),(.103,-.05,.161),(.040,-.111,.104),(-.117,.002,.092)]):
        sweep("Summoning fingers",[(.903+dx*.52,-.46+dy*.45,.902,.038,.032),
              (.906+dx,-.46+dy,.926,.041,.033),(.896+dx*1.24,-.46+dy*1.22,.95+dz*.42,.032,.028),
              (.884+dx*1.29,-.46+dy*1.18,.941+dz,.011,.011)],ridge,8)
    ell("Condensed storm",(.90,-.455,1.151),(.106,.106,.107),M["plasma"])
    aurora=custom("Storm filaments","82C8FF",.11,.27,2.2)
    for s in (-1,1):
        sweep("Lightning coil",[(.90+s*.058,-.433,1.131,.012,.012),
              (.90+s*.162,-.445,1.112,.016,.012),(.90+s*.077,-.447,1.198,.015,.012),
              (.90+s*.166,-.433,1.193,.013,.010),(.90+s*.061,-.43,1.327,.005,.004)],aurora,6,smoothing=0)


def archon_skin():
    energy=custom("Ionised mantle","438DCF",.24,.27,.36)
    nodes=energy.node_tree.nodes
    shader=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
    links=energy.node_tree.links
    noise=nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value=3.7
    noise.inputs['Detail'].default_value=3.0
    noise.inputs['Distortion'].default_value=1.2
    ramp=nodes.new('ShaderNodeValToRGB')
    stops=[(.23,(.016,.021,.102,1)),(.40,(.041,.090,.41,1)),
           (.526,(.048,.255,.61,1)),(.61,(.060,.59,.79,1)),
           (.692,(.29,.83,1.0,1)),(.785,(.73,.94,1.,1))]
    ramp.color_ramp.interpolation='EASE'
    for i,(pos,col) in enumerate(stops):
        e=ramp.color_ramp.elements[0] if i==0 else ramp.color_ramp.elements[-1] if i==len(stops)-1 else ramp.color_ramp.elements.new(pos)
        e.position=pos
        e.color=col
    links.new(noise.outputs['Fac'],ramp.inputs['Fac'])
    links.new(ramp.outputs['Color'],shader.inputs['Base Color'])
    if 'Emission Color' in shader.inputs:
        links.new(ramp.outputs['Color'],shader.inputs['Emission Color'])
    return energy


def archon():
    ether=archon_skin()
    bright=custom("Archon arc","82DFFF",.15,.25,1.20)
    frost=custom("Luminous psionic flesh","89BFDB",.20,.30,.26)
    amethyst=custom("Night field","485599",.20,.34,.18)
    sectioned("Vortex torso",[(.03,.122,-.07,.07,.088),(0,.135,.05,.20,.20),
          (-.038,.136,.256,.293,.264),(-.030,.091,.53,.43,.31),
          (.0,.059,.79,.61,.362),(0,.049,1.10,.84,.42),
          (0,.08,1.34,.81,.38),(0,.114,1.493,.42,.29),
          (.0,.083,1.59,.23,.19)],ether,24)
    # Paired diamond pectoral plates float over a brilliant stellar body.
    for s in (-1,1):
        p=[(.034,-.30,1.405),(.38,-.248,1.504),(.665,-.111,1.445),
           (.771,-.143,1.284),(.607,-.288,1.111),(.26,-.421,1.015),(.048,-.379,1.047)]
        shell("Luminous pectorals",side(p,s),(s*.369,-.488,1.29),ether,amethyst)
        sweep("Blue arc deltoid",side([(.557,.07,1.296,.196,.213),(.794,.073,1.365,.311,.257),
              (.937,.048,1.29,.30,.26),(.985,.032,1.157,.25,.234),
              (.957,.044,1.037,.177,.186)],s),ether,16)
        for i in range(2):
            swept=[(.55,.114,1.349+i*.055),(.67,.131,1.529+i*.035),
                (.86,.243,1.655+i*.025),(1.11,.293,1.733-i*.112),
                (1.016,.058,1.459-i*.108),(.885,-.105,1.344-i*.07),(.693,-.175,1.29-i*.04)]
            shell("Corona shoulder armour",side(swept,s),(s*.84,-.170,1.502-i*.08),
                  M["gold"] if i else M["ivory"],M["bronze"])
        sweep("Spectral arm",side([(.85,.045,1.224,.182,.18),(.998,.056,1.127,.211,.207),
              (1.04,.089,.939,.205,.186),(.989,.097,.798,.147,.142)],s),ether,14)
        sweep("Spectral forearm",side([(.978,.088,.847,.145,.122),(1.049,-.046,.805,.200,.163),
              (1.097,-.26,.875,.158,.12),(1.061,-.335,.992,.093,.095)],s),ether)
        hoop=[(.945,-.238,.742),(1.125,-.215,.803),(1.19,-.225,.936),
              (1.166,-.308,1.033),(1.01,-.381,1.032),(.976,-.359,.947)]
        shell("Psionic manacle",side(hoop,s),(s*1.101,-.409,.928),M["gold"])
        ell("Light hand",(s*1.055,-.359,1.056),(.132,.117,.129),frost)
        for i,(dx,dy) in enumerate([(.103,-.017),(.05,-.087),(-.024,-.099),(-.102,-.004)]):
            sweep("Ionised finger",side([(1.054+dx*.60,-.359+dy*.60,1.054,.044,.042),
                  (1.054+dx,-.365+dy,1.118,.042,.039),
                  (1.056+dx*1.28,-.38+dy,1.165+.016*i,.032,.029),
                  (1.046+dx*1.24,-.383+dy,1.203+.021*i,.010,.009)],s),frost,8)
        sweep("Lower vortex filament",side([(.035,.100,.012,.015,.013),(.222,.100,.176,.047,.035),
              (.312,-.044,.347,.053,.041),(.39,-.145,.531,.043,.032),
              (.276,-.248,.701,.018,.016)],s),amethyst)
        collar=[(.042,-.321,1.45),(.313,-.183,1.54),(.494,.021,1.509),
                (.390,-.162,1.364),(.178,-.381,1.234),(.063,-.427,1.12)]
        shell("Archon collar",side(collar,s),(s*.260,-.365,1.419),M["gold"])
    collar_gem((0,-.426,1.155),.086)
    face((0,-.009,1.708),1.02,frost,frost,M["pale"],framed=False,long=.95)
    # An irregular, oblique plasma torus gives the Archon a continuous energy
    # silhouette resembling an enveloping field seen edge-on.
    for j in range(2):
        points=[]
        for i in range(23):
            a=math.radians(7+i*8.4+j*174)
            size=.014+.022*math.sin(i*math.pi/22)
            points.append((1.19*math.cos(a),.159+.24*math.cos(a)+.068*math.sin(3*a+j),
                          1.35+1.05*math.sin(a)+.054*math.sin(4*a),size,size*.62))
        sweep("Ion field arc",points,bright if j==0 else ether,8)
    # A swept corona and asymmetrical filaments frame the head without filling
    # the background with a stock halo.
    for s in (-1,1):
        sweep("Ionic crown",side([(.175,.08,1.99,.124,.10),(.219,.151,2.149,.135,.092),
              (.306,.105,2.265,.105,.076),(.329,.103,2.397,.068,.049),
              (.251,.148,2.58-.065*s,.014,.010)],s),ether,11)
        arc=[(.82,.186,1.40,.023,.022),(1.061,.236,1.477,.021,.020),
             (1.14,.230,1.679,.023,.018),(1.21,.217,1.632,.020,.016),
             (1.087,.191,1.87,.017,.014),(.965,.167,1.919,.008,.009)]
        if s<0:
            arc=[(x*.94,y+.03,z+.16,w,d) for x,y,z,w,d in arc]
        sweep("Electrical discharge",side(arc,s),bright,6,smoothing=0)
    sweep("Apex discharge",[(0,.089,2.100,.120,.10),(-.061,.13,2.238,.115,.10),
           (-.044,.190,2.388,.085,.062),(.061,.192,2.483,.045,.043),
           (.084,.182,2.623,.015,.014)],ether)


BUILDERS={"vanguard":vanguard, "adept":adept, "high_templar":high_templar, "archon":archon}
