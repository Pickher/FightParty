"""Rigid machined backing plates and road-wheel hubs for the tank's exposed bogie sides."""
import numpy as np

from tank_paint import FRAME, SKIRT, STEEL, TREAD


def _cross(a, b):
    return a[:, 0]*b[:, 1] - a[:, 1]*b[:, 0]


class SidePlate:
    def __init__(self, local_triangles, outward, source_frame):
        self.local = local_triangles
        self.sign = outward
        self.source = source_frame
        a, b, c = (self.local[:, j, :2] for j in range(3))
        self.a = a
        self.ab = b - a
        self.ac = c - a
        denominator = _cross(self.ab, self.ac)
        self.faces = np.abs(denominator) > 1e-9
        self.det = np.where(self.faces, denominator, 1.)
        self.faces_out, self.colors = [], []

    def depth(self, x, y):
        delta = [x, y] - self.a
        u = _cross(delta, self.ac) / self.det
        v = _cross(self.ab, delta) / self.det
        hit = self.faces & (u >= -1e-8) & (v >= -1e-8) & (u+v <= 1.+1e-8)
        if not hit.any():
            return None
        z = self.local[hit, :, 2]
        depth = z[:, 0] + u[hit]*(z[:, 1]-z[:, 0]) + v[hit]*(z[:, 2]-z[:, 0])
        return np.max(self.sign * depth)

    def face(self, vertices, color):
        # Input loops run positively around the visible XY face.
        tri = np.array(vertices)
        tri[:, 2] *= self.sign
        if self.sign < 0:
            tri = tri[::-1]
        self.faces_out.append(tri)
        self.colors.append(color)

    def quad(self, a, b, c, d, color):
        self.face([a,b,c], color)
        self.face([a,c,d], color)

    def wheel(self, center, radius, relief):
        x, y = center
        depth = self.depth(x,y)
        if depth is None:
            return
        segments = 14
        angles = np.arange(segments)*(2*np.pi/segments)
        # A steel rim, indented dark web and hex fastener remain distinct in raking light.
        profile = [(.96,-.005,TREAD),(1.,.002,TREAD),(.94,.005,FRAME),(.81,.0055,STEEL),
                   (.75,.002,TREAD),(.42,.002,FRAME),(.32,.006,SKIRT),(.22,.008,STEEL)]
        rings = []
        for radial, offset, _ in profile:
            rings.append(np.column_stack((x + radius*radial*np.cos(angles),
                                          y + radius*radial*np.sin(angles),
                                          np.full(segments,depth+offset*relief))))
        for j,(outer,inner) in enumerate(zip(rings,rings[1:])):
            for i in range(segments):
                k = (i+1)%segments
                self.quad(outer[i],outer[k],inner[k],inner[i],profile[j][2])
        for i in range(segments):
            self.face([[x,y,depth+.009*relief],rings[-1][i],rings[-1][(i+1)%segments]], STEEL)

        for i in range(6):
            angle = np.pi/12 + i*np.pi/3
            radial = np.array([np.cos(angle),np.sin(angle)])
            along = radius*radial
            across = radius*.056*np.array([-radial[1],radial[0]])
            a = center+.41*along
            b = center+.72*along
            base = depth+.0022*relief
            crown = base+.0037*relief
            # Six wedge ribs make a cast web inside the rim. The actual recess is
            # cut by the raised annuli, and remains visible between the spokes.
            self.quad([*(a-across),base],[*(b-across),base],[*b,crown],[*a,crown], FRAME)
            self.quad([*a,crown],[*b,crown],[*(b+across),base],[*(a+across),base], SKIRT)

    def rib(self, a, b, thickness):
        a, b = np.asarray(a), np.asarray(b)
        start, stop = self.depth(*a), self.depth(*b)
        if start is None or stop is None:
            return
        delta = b-a
        normal = thickness * np.array([-delta[1],delta[0]])/np.linalg.norm(delta)
        rings = [np.array([[*(p-normal),z],[*(p-.56*normal),z+.005],
                           [*(p+.56*normal),z+.005],[*(p+normal),z]])
                 for p,z in ((a,start+.0004),(b,stop+.0004))]
        bottom,top = rings
        for j, color in enumerate([STEEL,SKIRT,FRAME]):
            self.quad(bottom[j],top[j],top[j+1],bottom[j+1],color)

    def finish(self):
        pts = np.asarray(self.faces_out)
        pts = pts @ self.source[:3,:3].T + self.source[:3,3]
        n = np.cross(pts[:,1]-pts[:,0],pts[:,2]-pts[:,0])
        n /= np.maximum(np.linalg.norm(n,axis=1,keepdims=True),1e-14)
        return np.concatenate((pts,np.broadcast_to(n[:,None,:],pts.shape)),axis=2), np.asarray(self.colors)


def bogie_detail(group, source, name):
    """Machine each side on the actual skin depth without a second material or draw."""
    points = (group[0][:,:,:3]-source[:3,3]) @ source[:3,:3]
    side = 1 if name.endswith("P") else -1
    front = name.startswith("TrackFront")
    # Coordinates are transverse to the real road-wheel axes in native bogie space.
    stations = ([(.032,-.044,.037),(.111,-.086,.040),(.196,-.069,.046),(.264,-.081,.036)]
                if front else [(-.267,-.066,.040),(-.186,-.057,.050),(-.092,-.065,.049)])
    result = []
    for inside in (True,False):
        plate = SidePlate(points, -side if inside else side, source)
        for x,y,r in stations:
            # The original exterior already models part of the wheel web; on
            # those faces add only its smaller hub/axle, preserving the tire.
            plate.wheel(np.array([x,y]), r*(1.0 if inside else .69), 1.0 if inside else .8)
        if inside and front:
            plate.rib([.023,.040],[.210,.009],.006)
            plate.rib([.210,.009],[.279,-.009],.006)
        if inside and not front:
            plate.rib([-.232,.021],[-.124,.048],.005)
        result.append(plate.finish())
    return tuple(np.concatenate(values) for values in zip(*result))
