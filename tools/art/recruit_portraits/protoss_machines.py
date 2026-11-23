"""Original hard-surface mechanical Protoss miniatures for the recruit catalog."""
import math
from mathutils import Vector
from studio import M,mat,mesh,ell,loft,beam,tube,box

gold, edge, bronze, dark, ivory, azure, light, white = (M[k] for k in ('gold','gold_dark','bronze','recess','ivory','teal','plasma','pale'))
night=mat('Stalker indigo lacquer','464368',.73,.29)
silver=mat('Protoss pale titanium','b9b2a3',.76,.3)
navy=mat('Prismatic inlay','153354',.54,.22)
amber=mat('Thermal-lance amber','ffb142',.25,.22,1.3)


def swept(name,path,armor=gold,trim=edge):
    """Cast a fluted plate along its ridgeline. Path sections give xyz, width and depth."""
    profile=[(1,0),(.82,.49),(.40,.88),(.07,1.0),(0,1.1),(-.07,1.),(-.40,.88),(-.82,.49),
             (-1,0),(-.85,-.48),(-.35,-.76),(0,-.77),(.35,-.76),(.85,-.48)]
    pts=[Vector(p[:3]) for p in path]
    verts=[]; faces=[]; tags=[]
    for i,p in enumerate(pts):
        axis=(pts[min(i+1,len(pts)-1)]-pts[max(i-1,0)]).normalized()
        across=axis.cross(Vector((0,0,1)))
        if across.length<.05:across=Vector((1,0,0))
        else:across.normalize()
        up=across.cross(axis).normalized()
        for a,b in profile:
            verts.append(p+across*a*path[i][3]+up*b*path[i][4])
    n=len(profile)
    for i in range(len(path)-1):
        for j in range(n):
            a=i*n+j;b=i*n+(j+1)%n
            faces.append((a,b,b+n,a+n)); tags.append(1 if j>=8 else 0)
    faces+=[tuple(range(n)),tuple(range((len(path)-1)*n,len(path)*n))]
    tags+=[1,1]
    ob=mesh(name,verts,faces,armor)
    ob.data.materials.append(trim)
    for f,j in zip(ob.data.polygons,tags):f.material_index=j
    mod=ob.modifiers.new('Cast ridges','SUBSURF');mod.levels=2
    return ob


def diamond(name,center,size,gem=light):
    x,y,z=center; rx,ry,rz=size
    verts=[(x,y,z+rz),(x,y,z-rz)]
    for i in range(8):
        a=i*math.pi/4
        verts.append((x+rx*math.cos(a),y+ry*math.sin(a),z))
    return mesh(name,verts,[f for j in range(8) for f in [(0,2+j,2+(j+1)%8),(1,2+(j+1)%8,2+j)]],gem,False)


def bearing(name,p,size,side):
    x,y,z=p
    a=(x-side*size*.6,y,z);b=(x+side*size*.58,y,z)
    beam(name+' socket',a,b,size,size*.92,dark,24)
    a=b;b=(x+side*size*.72,y,z)
    beam(name+' rim',a,b,size*.89,size*.84,edge,24)
    a=b;b=(x+side*size*.78,y,z)
    beam(name+' iris',a,b,size*.63,size*.53,azure,20)
    beam(name+' pilot',b,(x+side*size*.81,y,z),size*.19,size*.16,light,16)


def claw_leg(side,hip,knee,ankle,toe,width,armor=gold):
    # Armoured upper actuator and recurved lower talon overlap the articulated hubs.
    def V(p):return Vector((side*p[0],p[1],p[2]))
    a,b,c,d=map(V,(hip,knee,ankle,toe))
    swept('Coxa',[(*a,.045,.060),(*a.lerp(b,.30),width*.84,width*.55),
                  (*a.lerp(b,.73),width,width*.78),(*b,width*.66,width*.53)],armor)
    bearing('Knee',b,width*.61,side)
    swept('Tibial blade',[(*b,width*.48,width*.53),(*b.lerp(c,.22),width*.90,width*.65),
                           (*b.lerp(c,.63),width*.51,width*.49),(*c,width*.20,width*.25),
                           (*d,.012,.015)],armor)
    tube('Ankle piston',[a.lerp(b,.19)+Vector((0,.04,-.055)),b+Vector((0,.075,-.085)),
                         b.lerp(c,.36)+Vector((0,.06,-.052))],width*.12,silver)


def pod(name,x,y,z,r,proj=light):
    ell(name+' bezel',(x,y,z),(r,r*.46,r*.9),bronze)
    ell(name+' lens',(x,y-r*.17,z+r*.05),(r*.72,r*.38,r*.66),proj)


def _stalker_body():
    for side in (-1,1):
        claw_leg(side,(.34,-.13,.78),(.91,-.47,.98),(.84,-.95,.14),(1.06,-1.11,.055),.17,night)
        claw_leg(side,(.34,.26,.76),(.90,.69,1.0),(1.07,.91,.18),(1.23,1.01,.05),.17,night)
    swept('Ventral frame',[(0,-.84,.82,.03,.04),(0,-.50,.84,.38,.19),(0,.1,.89,.55,.28),(0,.83,.9,.06,.06)],dark,navy)
    swept('Helmet ridge',[(0,-.91,1.00,.016,.02),(0,-.58,1.14,.36,.24),(0,-.04,1.22,.48,.24),
                          (0,.41,1.22,.42,.20),(0,.75,1.08,.07,.08)],night,bronze)
    for s in (-1,1):
        swept('Sickle mandible',[(s*.13,-.94,.83,.025,.025),(s*.32,-.62,.96,.14,.12),
              (s*.45,-.17,1.14,.18,.15),(s*.46,.40,1.06,.13,.12),(s*.33,.66,1.02,.05,.07)],gold)
        tube('Canted optic',[(s*.13,-.785,1.041),(s*.24,-.694,1.098),(s*.34,-.537,1.117)],.038,light)
        swept('Disruptor spines',[(s*.46,-.39,1.03,.045,.045),(s*.55,-.05,1.12,.10,.10),
              (s*.58,.48,1.29,.12,.13),(s*.53,.84,1.48,.014,.024)],night,gold)
    diamond('Crown glyph',(0,-.43,1.40),(.08,.14,.035),azure)


def _immortal_body():
    for s in (-1,1):
        claw_leg(s,(.39,-.24,.71),(.83,-.39,.69),(.72,-.77,.13),(.91,-.94,.07),.24)
        claw_leg(s,(.38,.29,.71),(.85,.52,.72),(.85,.82,.12),(1.04,.96,.07),.24)
    ell('Reactor underframe',(0,.04,.74),(.64,.76,.40),dark)
    swept('Sarcofagus shield',[(0,-.80,.87,.08,.08),(0,-.62,1.02,.46,.29),(0,-.16,1.15,.57,.36),
                               (0,.42,1.13,.52,.31),(0,.73,1.0,.13,.10)],gold)
    swept('Ivory brow',[(0,-.72,1.10,.06,.04),(0,-.42,1.34,.31,.14),(0,.02,1.45,.34,.12),(0,.49,1.32,.14,.07)],ivory,gold)
    pod('Command optic',0,-.70,1.07,.146)
    for s in (-1,1):
        x=s*.77
        bearing('Weapon shoulder',(s*.52,.02,1.05),.255,s)
        swept('Particle housing',[(x,-.92,1.02,.17,.16),(x,-.69,1.06,.23,.23),(x,-.10,1.10,.26,.24),
                                   (x,.38,1.12,.23,.20),(x,.56,1.08,.11,.11)],gold)
        beam('Particle bore',(x,-.69,1.03),(x,-1.09,1.03),.153,.137,dark,16)
        beam('Port ring',(x,-1.04,1.03),(x,-1.105,1.03),.145,.142,silver,16)
        beam('Port glass',(x,-1.106,1.03),(x,-1.111,1.03),.102,.091,azure,16)
        pod('Cannon focal bead',x,-1.112,1.03,.042)
        for y in [-.39,-.24,-.09]:
            tube('Breech vents',[(x+s*.10,y,1.282),(x+s*.19,y,1.243),(x+s*.222,y+.02,1.19)],.018,navy)


def _colossus_body():
    for s in (-1,1):
        claw_leg(s,(.32,-.10,1.30),(.97,-.42,1.62),(.91,-.67,.34),(1.04,-.90,.035),.135,ivory)
        claw_leg(s,(.37,.27,1.31),(.96,.71,1.57),(1.07,.93,.32),(1.22,1.09,.035),.13,gold)
        tube('High suspension spine',[(s*.52,.21,1.40),(s*.70,.29,1.47),(s*.85,.49,1.55)],.04,bronze)
    swept('Elevated saddle',[(0,-.45,1.49,.055,.07),(0,-.05,1.52,.47,.18),
                             (0,.38,1.47,.51,.23),(0,.86,1.35,.08,.09)],gold)
    swept('Dorsal spine',[(0,-.16,1.80,.09,.06),(0,.02,1.78,.26,.17),(0,.40,1.70,.22,.20),(0,.83,1.84,.025,.04)],ivory)
    swept('Long neck',[(0,-.88,1.55,.10,.10),(0,-.48,1.64,.18,.15),(0,-.11,1.54,.12,.13)],bronze,dark)
    for s in (-1,1):
        swept('Thermal brow',[(s*.08,-1.08,1.49,.02,.035),(s*.23,-.84,1.62,.16,.09),
                              (s*.45,-.60,1.68,.22,.13),(s*.63,-.38,1.68,.19,.12),(s*.78,-.16,1.79,.025,.04)],gold)
        pod('Thermal aperture',s*.42,-.727,1.58,.09,amber)
        tube('Board illumination',[(s*.22,-.83,1.68),(s*.40,-.62,1.78),(s*.57,-.46,1.77)],.016,ivory)
    diamond('Sensor',(0,-.87,1.66),(.115,.135,.079),light)


def _sentry_body():
    ell('Inner sphere',(0,.04,.85),(.42,.43,.43),azure)
    ell('Front lens bezel',(0,-.28,.84),(.32,.17,.33),dark)
    ell('Core lens',(0,-.38,.84),(.23,.15,.24),light)
    for s in (-1,1):
        swept('Cradle horn',[(s*.13,-.46,.51,.025,.024),(s*.42,-.31,.58,.14,.13),
                             (s*.62,.04,.85,.20,.14),(s*.52,.29,1.11,.15,.13),
                             (s*.30,.32,1.36,.085,.12),(s*.18,.25,1.48,.012,.02)],gold)
        swept('Counterweight',[(s*.14,-.37,.53,.055,.035),(s*.28,-.04,.49,.15,.13),
                               (s*.36,.35,.48,.19,.14),(s*.35,.67,.31,.051,.045)],ivory)
        tube('Inner energy conduit',[(s*.27,-.40,.58),(s*.46,-.29,.74),(s*.53,.015,.93)],.029,light)
    swept('Antenna housing',[(0,.09,1.01,.18,.08),(0,.34,1.10,.19,.12),(0,.66,1.32,.055,.07),
                             (0,.71,1.47,.012,.017)],ivory,gold)
    diamond('Levitation crystal',(0,.02,.32),(.12,.15,.23),light)


def _disruptor_body():
    # Exposed resonator in a massive toroidal cradle, with six separately layered vanes.
    ell('Energy resonator',(0,0,.65),(.48,.49,.47),light)
    for i in range(6):
        a=2*math.pi*i/6 + math.pi/9
        path=[]
        for r,twist,z,w,h in [(.35,-.26,.48,.08,.065),(.64,-.05,.44,.215,.13),
                              (.86,.12,.54,.24,.20),(.86,.34,.71,.18,.15),(.69,.43,.90,.045,.055)]:
            x,y=r*math.cos(a+twist),r*math.sin(a+twist)
            path.append((x,y,z,w,h))
        swept('Rotary induction vane',path,ivory if i%3==1 else gold)
        ax,ay=.68*math.cos(a),.68*math.sin(a)
        ell('Exciter',(ax,ay,.548),(.103,.103,.105),azure)
    for dz,rr in [(.22,.49),(.80,.49)]:
        for k in range(3):
            points=[]
            for i in range(8):
                a=(k*2.094 + .17 + 1.68*i/7)
                points.append((rr*math.cos(a),rr*math.sin(a),dz+.025*math.cos(2*a)))
            tube('Induction collar',points,.044,dark)
    diamond('Polar crystal',(0,.005,.99),(.18,.19,.25),ivory)


def _void_ray_body():
    # Three long different-height prongs shelter the focusing crystal in their gap.
    swept('Prismatic keel',[(0,-1.40,.53,.015,.025),(0,-.96,.52,.09,.085),(0,-.48,.55,.16,.11),
                            (0,.12,.66,.30,.24),(0,.73,.73,.25,.23),(0,1.13,.74,.035,.035)],gold)
    for s in (-1,1):
        swept('Field prong',[(s*.36,-1.34,.85,.018,.021),(s*.40,-.97,.85,.07,.10),(s*.45,-.51,.84,.105,.12),
                            (s*.41,.02,.82,.14,.13),(s*.35,.56,.76,.20,.16),(s*.65,.96,.77,.065,.08)],ivory)
        tube('Prong conductor',[(s*.348,-1.18,.84),(s*.376,-.74,.86),(s*.37,-.19,.88)],.024,light)
        swept('Swept field generator',[(s*.23,-.28,.69,.10,.08),(s*.47,.07,.68,.19,.11),
                                       (s*.73,.46,.63,.22,.14),(s*.85,.96,.61,.16,.13),
                                       (s*.77,1.25,.66,.045,.05)],gold)
        swept('Engine vent',[(s*.72,.44,.73,.06,.04),(s*.83,.78,.76,.09,.06),(s*.79,1.09,.72,.07,.05)],navy)
        for y in [.39,.56,.72]:
            tube('Light channels',[(s*.30,y,.84),(s*.51,y+.10,.83),(s*.64,y+.22,.76)],.015,azure)
    diamond('Void prism',(0,-.76,.73),(.17,.51,.18),light)
    swept('Elevated bridge',[(0,-.24,.79,.04,.04),(0,.19,.96,.16,.14),(0,.64,1.07,.14,.16),
                             (0,1.01,1.17,.012,.035)],gold)


def _carrier_body():
    swept('Underbelly',[(0,-1.52,.38,.045,.027),(0,-1.06,.43,.37,.13),(0,-.53,.42,.61,.23),
                        (0,.35,.45,.71,.26),(0,1.03,.54,.42,.17),(0,1.39,.55,.09,.08)],edge,dark)
    swept('Mothership hull',[(0,-1.55,.55,.025,.025),(0,-1.04,.64,.36,.17),(0,-.47,.64,.52,.24),
                             (0,.37,.71,.58,.31),(0,.91,.76,.39,.27),(0,1.33,.76,.055,.065)],ivory,gold)
    swept('Dorsal fin',[(0,-.96,.76,.025,.017),(0,-.49,.83,.075,.045),(0,.15,.98,.15,.085),
                       (0,.61,1.10,.13,.16),(0,.84,1.25,.024,.044)],gold)
    for s in (-1,1):
        swept('Flight deck rim',[(s*.28,-1.12,.43,.025,.035),(s*.53,-.67,.48,.10,.065),
                                (s*.75,-.08,.47,.15,.125),(s*.76,.52,.46,.18,.17),
                                (s*.54,1.04,.54,.16,.14),(s*.47,1.31,.57,.045,.04)],gold)
        tube('Hangar shadow',[(s*.50,-.64,.50),(s*.64,-.22,.58),(s*.68,.22,.61),(s*.63,.61,.62)],.076,navy)
        for y in [-.48,-.21,.06,.33,.56]:
            x=.57+.10*(1-abs(y)*1.6)
            tube('Launch bay ribs',[(s*(x-.023),y-.03,.68),(s*(x+.061),y+.01,.59),(s*(x+.082),y+.011,.53)],.026,ivory)
            ell('Bay emitter',(s*(x+.065),y+.085,.573),(.032,.054,.026),light)
        tube('Deck seam',[(s*.10,-1.17,.65),(s*.26,-.74,.77),(s*.35,-.21,.84),(s*.39,.19,.91),(s*.26,.79,.97)],.018,edge)
    diamond('Bridge light',(0,-.025,.985),(.079,.13,.045),azure)


def panel(host,outline,top,edge_material=bronze,front=False):
    """Conform an inlaid, bevelled armour panel to an existing compound curved plate."""
    import bpy
    from mathutils.bvhtree import BVHTree
    deps=bpy.context.evaluated_depsgraph_get()
    tree=BVHTree.FromObject(host,deps)
    points=[Vector(p) for p in outline]
    center=sum(points,Vector((0.,0.)))/len(points)
    contour=[]
    for i,p in enumerate(points):
        q=points[(i+1)%len(points)]
        for j in range(3):contour.append(p.lerp(q,j/3))
    world=host.matrix_world
    inverse=world.inverted()
    direction=Vector((0,1,0) if front else (0,0,-1))
    def hit(p,height):
        for j in range(7):
            pos=center.lerp(p,.93**j)
            origin=Vector((pos.x,-8.,pos.y) if front else (pos.x,pos.y,8.))
            local,normal,_,_=tree.ray_cast(inverse @ origin,(inverse.to_3x3() @ direction).normalized())
            if local is not None:
                return world @ local + (world.to_3x3().inverted().transposed() @ normal).normalized()*height
        return None
    middle=hit(center,.008)
    if middle is None:return None
    verts=[middle];faces=[];tags=[]
    for k,(u,h) in enumerate([(.34,.009),(.70,.009),(.90,.010),(.95,.007),(1.,.003)]):
        for xy in contour:
            p=hit(center.lerp(xy,u),h)
            if p is None:return None
            verts.append(p)
        n=len(contour);start=1+k*n
        for i in range(n):
            a=start+i;b=start+(i+1)%n
            if k==0:faces.append((0,a,b))
            else:faces.append((a-n,a,b,b-n))
            tags.append(0 if k<3 else 1)
    ob=mesh('Inset armour panel',verts,faces,top)
    ob.data.materials.append(edge_material)
    for f,k in zip(ob.data.polygons,tags):f.material_index=k
    return ob



def _host(name):
    import bpy
    return bpy.data.objects[name]


def stalker():
    _stalker_body()
    for s in [-1,1]:
        panel(_host('Helmet ridge'),[(s*.044,-.55),(s*.20,-.51),(s*.35,-.18),(s*.28,.08),(s*.105,.00)],night,silver)
        panel(_host('Helmet ridge'),[(s*.10,.07),(s*.29,.15),(s*.32,.33),(s*.16,.48)],navy,edge)
        x=s*.47
        for y in [-.25,-.09,.07]:
            tube('Blink cooling fins',[(x,y,1.13),(x+s*.07,y+.05,1.17),(x+s*.065,y+.12,1.18)],.017,silver)
        tube('Spine light',[(s*.42,.33,1.18),(s*.52,.52,1.32),(s*.52,.65,1.37)],.019,azure)
    diamond('Tracking optic',(0,-.80,1.025),(.060,.045,.043),white)


def immortal():
    _immortal_body()
    for s in [-1,1]:
        for y in [-.38,-.04,.22]:
            panel(_host('Ivory brow'),[(s*.035,y-.15),(s*.21,y-.07),(s*.246,y+.075),(s*.077,y+.092)],ivory,edge)
        for z,xx in [(1.05,.64),(1.15,.66)]:
            tube('Gun trunnion rim',[(s*xx,-.44,z),(s*(xx+.05),-.23,z+.09),(s*(xx+.05),.18,z+.087)],.028,silver)
        barrel=_host('Particle housing' if s<0 else 'Particle housing.001')
        for y in [-.63,-.37,-.13,.13]:
            panel(barrel,[(s*.70,y-.075),(s*.84,y-.06),(s*.90,y+.06),(s*.80,y+.09),(s*.70,y+.045)],edge,ivory)
        ell('Forward shield port',(s*.31,-.62,1.04),(.068,.04,.093),dark)
        ell('Shield lamp',(s*.31,-.65,1.05),(.026,.016,.068),light)
    pod('Heavy forward emitter',0,-.766,1.024,.112)


def colossus():
    _colossus_body()
    for s in [-1,1]:
        swept('Lance bridge',[(s*.18,-.85,1.64,.02,.03),(s*.35,-.56,1.77,.156,.075),
                             (s*.46,-.12,1.79,.16,.093),(s*.38,.18,1.74,.06,.05)],ivory)
        barrel=_host('Lance bridge' if s<0 else 'Lance bridge.001')
        panel(barrel,[(s*.28,-.61),(s*.42,-.53),(s*.45,-.32),(s*.35,-.34)],gold,bronze)
        tube('Thermal projector brace',[(s*.50,-.43,1.60),(s*.57,-.64,1.58),(s*.60,-.74,1.58)],.046,dark)
        pod('Projector face',s*.60,-.745,1.59,.078,amber)
        for leg in [(.79,-.32,1.53),(.83,.60,1.51)]:
            ell('Long leg locking pin',(s*leg[0],leg[1],leg[2]),(.07,.066,.055),bronze)


def sentry():
    _sentry_body()
    import bpy
    # An angular crystal and refracting bands replace a simple, featureless lens.
    for name in ['Front lens bezel','Core lens','Inner sphere']:
        bpy.data.objects.remove(_host(name),do_unlink=True)
    diamond('Faceted levitation core',(0,-.055,.87),(.32,.30,.48),azure)
    diamond('Bright core shard',(.02,-.225,.86),(.149,.153,.32),light)
    for s in [-1,1]:
        swept('Front energy claw',[(s*.10,-.43,.44,.025,.035),(s*.28,-.39,.55,.075,.066),
                                 (s*.44,-.29,.83,.067,.077),(s*.39,-.22,1.01,.025,.035)],ivory,gold)
        tube('Oscillator',[(s*.30,-.22,.94),(s*.30,-.13,1.12),(s*.18,-.04,1.26)],.017,light)
        for n in [0,1]:
            x=s*(.41+n*.049)
            ell('Claw register',(x,-.258+n*.10,.66+n*.08),(.036,.035,.044),bronze)


def disruptor():
    _disruptor_body()
    import bpy
    _host('Energy resonator').scale=(.51,.51,.39)
    # Deep equatorial race and repeating heavy capacitors distinguish its disc from the sentry.
    bpy.ops.mesh.primitive_torus_add(major_segments=48,minor_segments=12,location=(0,0,.592),major_radius=.553,minor_radius=.084)
    ob=bpy.context.object;ob.name='Equatorial gap';ob.data.materials.append(dark)
    for i in range(6):
        a=i*math.pi/3+math.pi/9
        def at(r,t,z):return (r*math.cos(a+t),r*math.sin(a+t),z)
        swept('Capacitor finger',[(*at(.79,.14,.49),.12,.065),(*at(.815,.14,.29),.13,.089),
                                 (*at(.65,.28,.20),.077,.062),(*at(.55,.37,.17),.025,.045)],edge,dark)
        tube('Armature strap',[at(.88,.03,.51),at(.955,.17,.62),at(.92,.31,.71)],.047,dark)
        tube('Indicator tick',[at(.916,.14,.64),at(.932,.19,.66)],.023,azure)
    diamond('Disruption emitter',(0,-.03,.997),(.135,.13,.10),light)


def void_ray():
    _void_ray_body()
    for s in [-1,1]:
        for j,y in enumerate([-.62,-.27,.05]):
            h=_host('Field prong' if s<0 else 'Field prong.001')
            panel(h,[(s*.392,y-.115),(s*.47,y-.096),(s*.493,y+.03),(s*.40,y+.09)],gold,bronze)
        h=_host('Swept field generator' if s<0 else 'Swept field generator.001')
        panel(h,[(s*.48,.10),(s*.63,.18),(s*.79,.56),(s*.70,.55)],ivory,edge)
        for k in range(3):
            y=.45+k*.148
            tube('Generator heat sink',[(s*.705,y,.754),(s*.783,y+.04,.775),(s*.832,y+.103,.726)],.023,dark)


def carrier():
    _carrier_body()
    h=_host('Mothership hull')
    for s in [-1,1]:
        for y,w in [(-.71,.31),(-.30,.45),(.12,.46),(.54,.35)]:
            panel(h,[(s*.048,y-.15),(s*w*.81,y-.17),(s*w,y+.02),(s*w*.78,y+.15),
                     (s*.09,y+.17)],ivory,bronze)
        swept('Launch gallery',[(s*.50,-.77,.55,.036,.035),(s*.56,-.50,.60,.074,.069),
                                (s*.74,-.06,.64,.075,.072),(s*.73,.38,.64,.080,.073),
                                (s*.65,.69,.65,.031,.035)],navy,dark)
        for y in [-.44,-.20,.04,.28,.48]:
            x=.605+.116*(1-abs(y)*1.7)
            tube('Carrier bay lamps',[(s*(x+.018),y,.665),(s*(x+.035),y+.072,.676)],.026,light)
        pod('Fleet navigation lamp',s*.53,-.67,.54,.060)
    for y in [-.16,.06,.28]:
        tube('Dorsal buttress',[(-.11,y,.954),(0,y+.085,1.045),(.11,y,.954)],.031,gold)


BUILDERS={'stalker':stalker,'immortal':immortal,'colossus':colossus,'sentry':sentry,
          'disruptor':disruptor,'void_ray':void_ray,'carrier':carrier}
