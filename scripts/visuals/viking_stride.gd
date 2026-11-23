extends RefCounted
## Contact points live in a virtual heading/travel plane. The layer and the
## stationary art preview can therefore drive the same stride with signed distance.
const LENGTH := 0.46
const STANCE := 0.58
const TURN_RADIUS := 0.235

var phase := 0.0
var weight := 0.0
var home: Array[Vector2] = []
var floor_height: float
var diameter: float
var crouch: float
var root := Vector2.ZERO
var anchors: Array[Vector2] = []
var anchor_yaw := PackedFloat32Array([0.0, 0.0])
var offsets: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var lift := PackedFloat32Array([0.0, 0.0])
var toe := PackedFloat32Array([0.0, 0.0])
var foot_yaw := PackedFloat32Array([0.0, 0.0])
var knee_frames: Array[Transform3D] = []
var ankle_frames: Array[Transform3D] = []
var sole_delta: Array[Vector3] = []
var bind_sole: Array[Vector3] = []
var _fore_aft := PackedFloat32Array([0.,0.])

func setup(knees: Array[Node3D], ankles: Array[Node3D], soles: Array[Node3D], model: Node3D, bounds: AABB, body_diameter: float, heading: float) -> void:
	diameter = body_diameter
	floor_height = bounds.position.y
	crouch = .042 * diameter
	for i in 2:
		knee_frames.append(knees[i].transform)
		ankle_frames.append(ankles[i].transform)
		sole_delta.append(ankles[i].to_local(soles[i].global_position))
		var point := model.to_local(soles[i].global_position)
		bind_sole.append(point)
		crouch = maxf(crouch, point.y-floor_height+.016*diameter)
		var offset := point - bounds.get_center()
		home.append(Vector2(offset.x, offset.z) / diameter)
		anchors.append(home[i].rotated(heading))
		anchor_yaw[i] = heading
	# The scan catches one foot reaching well ahead of the other. Bring the
	# neutral supports closer to the hips to leave extension for both strides.
	for i in 2:
		var upper := knee_frames[i].origin
		var lower := ankle_frames[i].origin
		var neutral_reach := .20*(upper.length()+lower.length())
		_fore_aft[i] = neutral_reach-upper.x-lower.x
		home[i].x += _fore_aft[i]/diameter
		anchors[i] = home[i].rotated(heading)

func advance(dt: float, heading_before: float, heading: float, distance: float, ground: float) -> void:
	var yaw := angle_difference(heading_before,heading)
	var travel := absf(distance) + absf(yaw)*TURN_RADIUS
	var moving := travel > .00001 and ground > .001
	root += Vector2.from_angle(heading_before + yaw*.5) * distance
	var old_phase := phase
	if moving:
		phase = fposmod(phase + travel/LENGTH, 1.0)
	weight = move_toward(weight, 1.0 if moving else 0.0, dt * (8.0 if moving else 6.0))
	for i in 2:
		var t := fposmod(phase + .5*i, 1.0)
		var last := fposmod(old_phase + .5*i, 1.0)
		if weight <= .00001 or ground <= .001:
			anchors[i] = root + home[i].rotated(heading)
			anchor_yaw[i] = heading
			offsets[i] = Vector2.ZERO
			lift[i] = 0.0
			toe[i] = 0.0
			foot_yaw[i] = 0.0
			continue
		# Predict the middle of the next contact, including the foot's arc
		# around the vertical axis during an in-place turn.
		var ahead := .5*STANCE*LENGTH/maxf(.00001,travel)
		var next_heading := heading + clampf(yaw*ahead,-.62,.62)
		var target := root + home[i].rotated(next_heading) + Vector2.from_angle(heading)*distance*ahead
		if moving and (t < last or travel >= LENGTH):
			anchors[i] = target
			anchor_yaw[i] = next_heading
		var swing := clampf((t-STANCE)/(1.0-STANCE),0.0,1.0)
		var ease := smoothstep(0.0,1.0,swing)
		var contact := anchors[i].lerp(target,ease)
		offsets[i] = (contact-root).rotated(-heading)-home[i]
		lift[i] = .083 * pow(maxf(0.0,sin(PI*swing)),1.35)
		toe[i] = -.17*sin(TAU*swing)
		foot_yaw[i] = angle_difference(heading,lerp_angle(anchor_yaw[i],next_heading,ease))
	# Localize accumulated travel so very long preview loops retain precision.
	if root.length_squared() > 256.0:
		for i in anchors.size():
			anchors[i] -= root
		root = Vector2.ZERO

func pose(pelvis: Node3D, hips: Array[Node3D], knees: Array[Node3D], feet: Array[Node3D], influence: float) -> void:
	if influence <= .00001:
		return
	var moving := weight*influence
	var drop := crouch*influence + diameter*moving*(.009-.008*cos(TAU*phase*2.0))
	var sway := diameter*moving*.017*sin(TAU*phase)
	pelvis.position += Vector3(0,-drop,sway)
	for i in 2:
		var upper := knee_frames[i].origin
		var lower := ankle_frames[i].origin
		var sole_rotation := Basis(Vector3.UP,-foot_yaw[i]*moving) * Basis(Vector3.BACK,toe[i]*moving)
		var contact_shift := Vector3(offsets[i].x, lift[i], offsets[i].y)*diameter*moving
		contact_shift.x += _fore_aft[i]*influence
		contact_shift.y -= (bind_sole[i].y-floor_height)*influence
		var goal := upper+lower + contact_shift + sole_delta[i] - sole_rotation*sole_delta[i]
		goal += Vector3(0,drop,-sway)
		var u := Vector2(upper.x,upper.y)
		var l := Vector2(lower.x,lower.y)
		var yz := Vector2(goal.y,goal.z)
		var neutral_z := upper.z+lower.z
		var sagittal := Vector2(goal.x, -sqrt(maxf(.000001,yz.length_squared()-neutral_z*neutral_z)))
		var a := u.length()
		var b := l.length()
		var reach := clampf(sagittal.length(),absf(a-b)+.00001,a+b-.00001)
		var rest_bend := u.angle_to(l)
		var bend := signf(rest_bend)*acos(clampf((reach*reach-a*a-b*b)/(2.0*a*b),-1.0,1.0))
		var pitch := sagittal.angle() - atan2(b*sin(bend),a+b*cos(bend)) - u.angle()
		var roll := Vector2(sagittal.y,neutral_z).angle_to(yz)
		var hip := Basis(Vector3.RIGHT,roll)*Basis(Vector3.BACK,pitch)
		var knee := Basis(Vector3.BACK,bend-rest_bend)
		# Blend the ground offsets on the authored local frames as the feet
		# leave the ground and the knee/ankle hinges seat in the fuselage.
		var correction := influence
		hips[i].basis = hips[i].basis * Basis.IDENTITY.slerp(hip,correction)
		knees[i].basis = knees[i].basis * Basis.IDENTITY.slerp(knee,correction)
		feet[i].basis = feet[i].basis * Basis.IDENTITY.slerp((hip*knee).inverse()*sole_rotation,correction)
