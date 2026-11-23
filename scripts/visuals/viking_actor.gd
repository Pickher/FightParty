extends Node3D
## One articulated Viking: +X forward, +Y up, +Z starboard in the rig.
const RIG_PATH := "res://assets/models/viking/viking_rig.glb"
const AIR := "anti_air_missile"
const GROUND := "gatling_cannon"
const LAUNCH_TIME := 1.20
const LAND_TIME := 1.25
const FLIGHT_LIFT := .43
const Stride = preload("res://scripts/visuals/viking_stride.gd")
const Effects = preload("res://scripts/visuals/viking_effects.gd")
const Wreck = preload("res://scripts/visuals/viking_wreck.gd")

var presentation := Node3D.new()
var facing := Node3D.new()
var motion := Node3D.new()
var centered := Node3D.new()
var model_root: Node3D
var joints: Dictionary = {}
var hips: Array[Node3D] = []
var knees: Array[Node3D] = []
var feet: Array[Node3D] = []
var soles: Array[Node3D] = []
var shoulders: Array[Node3D] = []
var guns: Array[Node3D] = []
var rotors: Array[Node3D] = []
var wings: Array[Node3D] = []
var muzzles: Array[Node3D] = []
var rails: Array[Node3D] = []
var _exhausts: Array[Node3D] = []
var pelvis: Node3D
var trunk: Node3D
var heading := 0.0
var flight_progress := 0.0
var flight_target := 0.0
var walk_phase: float:
	get: return _stride.phase
var flashes: Array[MeshInstance3D]:
	get: return _effects.flashes
var muzzle_index := 0
var ground_height := 0.0
var wreck: Wreck
var wreck_age := -1.0

var _stride := Stride.new()
var _effects := Effects.new()
var _nodes: Array[Node3D] = []
var _rest: Array[Transform3D] = []
var _flown: Array[Transform3D] = []
var _timing: Array[Vector4] = []
var _air_rotors: Array[Basis] = []
var _applied_spin := PackedFloat64Array([0.,0.])
var _at_air_endpoint := false
var _diameter := 1.
var _overhead := 0.
var _bank := 0.
var _speed := 0.
var _aim := 0.
var _target := Vector2.INF
var _aim_hold := 0.
var _cursor := {AIR:0, GROUND:0}
var _valid := false

func setup(model: PackedScene, bounds: AABB, initial_heading: float, initial_flight: float = 0.) -> bool:
	if model == null:
		return false
	model_root = model.instantiate() as Node3D
	if model_root == null:
		return false
	add_child(presentation)
	presentation.add_child(facing)
	facing.add_child(motion)
	motion.add_child(centered)
	centered.add_child(model_root)
	_diameter = maxf(.001,maxf(bounds.size.x,bounds.size.z))
	centered.scale = Vector3.ONE / _diameter
	centered.position = -bounds.get_center() / _diameter
	ground_height = -.5*bounds.size.y/_diameter
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_overhead = smoothstep(.86,.995,camera.global_basis.z.normalized().dot(Vector3.UP))
	var targets: Dictionary = {}
	for node in model_root.find_children("Air*","Node3D",true,false):
		targets[String(node.name).trim_prefix("Air")] = model_root.global_transform.affine_inverse() * (node as Node3D).global_transform
	for joint in model_root.find_children("*","Node3D",true,false):
		var key := String(joint.name)
		if not targets.has(key):
			continue
		var node := joint as Node3D
		var parent := node.get_parent_node_3d()
		var parent_frame: Transform3D = targets.get(String(parent.name), model_root.global_transform.affine_inverse()*parent.global_transform)
		joints[key] = node
		_nodes.append(node)
		_rest.append(node.transform)
		_flown.append(parent_frame.affine_inverse() * (targets[key] as Transform3D))
		_timing.append(_window(key))
	pelvis = joints.get("Pelvis")
	trunk = joints.get("Trunk")
	for side in ["P","N"]:
		hips.append(joints.get("Hip"+side))
		knees.append(joints.get("Knee"+side))
		feet.append(joints.get("Ankle"+side))
		shoulders.append(joints.get("Shoulder"+side))
		guns.append(joints.get("Gun"+side))
		rotors.append(joints.get("Rotor"+side))
		wings.append(joints.get("Wing"+side))
		muzzles.append(model_root.find_child("Muzzle"+side,true,false))
		rails.append(model_root.find_child("Missile"+side,true,false))
		soles.append(model_root.find_child("Sole"+side,true,false))
		_exhausts.append(model_root.find_child("Exhaust"+side,true,false))
	if pelvis == null or trunk == null:
		return false
	for group in [hips,knees,feet,shoulders,guns,rotors,wings,muzzles,rails,soles,_exhausts]:
		if group.has(null):
			return false
	for rotor in rotors:
		_air_rotors.append(_flown[_nodes.find(rotor)].basis)
	heading = initial_heading
	_aim = heading
	flight_progress = clampf(initial_flight,0.,1.)
	flight_target = flight_progress
	_stride.setup(knees,feet,soles,model_root,bounds,_diameter,heading)
	_valid = true
	_pose()
	return true

static func _window(key: String) -> Vector4:
	# Local rotations and sliding carriages have separate time intervals. All
	# phases are functions of one reversible clock, including landing mid-launch.
	if key.begins_with("Ankle"):
		return Vector4(.16,.58,.20,.62)
	if key.begins_with("Knee"):
		return Vector4(.19,.64,.26,.66)
	if key.begins_with("Hip"):
		return Vector4(.26,.73,.24,.69)
	if key.begins_with("Gun"):
		return Vector4(.20,.62,.19,.64)
	if key.begins_with("Shoulder"):
		return Vector4(.14,.61,.23,.66)
	if key.begins_with("WingGlove"):
		return Vector4(.16,.64,.20,.66)
	if key.begins_with("WingFlap"):
		return Vector4(.32,.74,.36,.78)
	if key.begins_with("WingTip"):
		return Vector4(.42,.92,.45,.93)
	if key.begins_with("Wing"):
		return Vector4(.20,.72,.29,.75)
	if key.begins_with("Engine"):
		return Vector4(.24,.79,.39,.83)
	if key.begins_with("Nose"):
		return Vector4(.33,.84,.37,.92)
	return Vector4(.18,.77,.20,.77)

func set_flight_mode(wants_flight: bool) -> void:
	if wreck == null:
		flight_target = 1. if wants_flight else 0.

func set_flight_progress(value: float) -> void:
	if not _valid or wreck != null:
		return
	flight_target = clampf(value, 0., 1.)
	if flight_progress != flight_target:
		flight_progress = flight_target
		_pose()

func advance(delta: float, desired_heading: float, distance: float, aim_heading: float = NAN) -> void:
	var dt := maxf(delta,0.)
	if not _valid or dt <= 0.:
		return
	if wreck != null:
		wreck_age += dt
		wreck.seek(wreck_age)
		return
	var before := heading
	heading = rotate_toward(heading, desired_heading, dt*lerpf(3.65,2.45,flight_progress))
	var turn := angle_difference(before,heading)
	var new_bank := clampf(turn/dt*.20,-.30,.30)*flight_progress
	var next_bank := move_toward(_bank,new_bank,dt*1.85)
	var next_speed := move_toward(_speed,minf(absf(distance)/dt,1.),dt*5.)
	var next_flight := move_toward(flight_progress,flight_target,dt/(LAUNCH_TIME if flight_target>flight_progress else LAND_TIME))
	var desired_aim := heading if is_nan(aim_heading) else aim_heading
	if flight_progress == next_flight and turn == 0. and absf(distance) < .000001 and _stride.weight == 0. and _bank == next_bank and _speed == next_speed and _effects.cold() and _aim_hold == 0. and is_zero_approx(angle_difference(_aim,desired_aim)):
		return
	flight_progress = next_flight
	_bank = next_bank
	_speed = next_speed
	if flight_progress < 1. or _stride.weight > 0.:
		_stride.advance(dt,before,heading,distance,1.-smoothstep(.10,.40,flight_progress))
	_effects.advance(dt)
	_aim_hold = maxf(0.,_aim_hold-dt)
	if _aim_hold <= 0.:
		_target = Vector2.INF
		_aim = rotate_toward(_aim,desired_aim,dt*4.7)
	_pose()

func _pose() -> void:
	var p := flight_progress
	var release := 1.-smoothstep(.10,.40,p)
	var shear := _overhead * lerpf(.48,.20,smoothstep(.08,.94,p))
	presentation.basis = Basis(Vector3.RIGHT,Vector3(0,1,-shear),Vector3.BACK)
	presentation.position.z = ground_height*shear*.45
	facing.rotation.y = -heading
	motion.position.y = FLIGHT_LIFT * smoothstep(.055,.665,p)
	var takeoff_pitch := .095*sin(PI*smoothstep(.06,.88,p))
	motion.basis = Basis(Vector3.RIGHT,_bank)*Basis(Vector3.BACK,takeoff_pitch-.037*_speed*p)
	# Flight attitude and thrust are carried by the outer nodes. All local
	# attachment frames can stay seated until a landing or a rotor spin.
	if p == 1.:
		if not _at_air_endpoint:
			for i in _nodes.size():
				_nodes[i].transform = _flown[i]
	elif p == 0.:
		for i in _nodes.size():
			_nodes[i].transform = _rest[i]
	else:
		for i in _nodes.size():
			var timing := _timing[i]
			var rest := _rest[i]
			var flown := _flown[i]
			_nodes[i].transform = Transform3D(rest.basis.slerp(flown.basis,smoothstep(timing.x,timing.y,p)),
				rest.origin.lerp(flown.origin,smoothstep(timing.z,timing.w,p)))
	if release > .0:
		_stride.pose(pelvis,hips,knees,feet,release)
		# The waist takes the wide traverse while the planted legs finish
		# turning. Each shoulder converges its own barrel on the contact.
		var twist := clampf(.82*angle_difference(heading,_aim),-2.57,2.57)
		var step := sin(TAU*walk_phase)*_stride.weight
		trunk.basis = trunk.basis * Basis(Vector3.UP,(-twist+.038*step)*release) * Basis(Vector3.RIGHT,-.063*step*release)
		for side in 2:
			_ground_arm(side,step,release)
	for side in rotors.size():
		var spin := _effects.rotor_angles[side]
		if p == 1. and _at_air_endpoint and spin == _applied_spin[side]:
			continue
		var seat := _air_rotors[side] if p == 1. else rotors[side].basis
		rotors[side].basis = seat * Basis(Vector3.RIGHT,spin)
		_applied_spin[side] = spin
	_at_air_endpoint = p == 1.
	_effects.sync_exhausts(_exhausts,smoothstep(.06,.54,p)*(.41+.38*_speed+.68*sin(PI*p)),_diameter)
	_effects.sync_flashes(muzzles,rails,_diameter)

func _ground_arm(side: int, step: float, release: float) -> void:
	var kick := _effects.recoil(side)
	var shoulder := shoulders[side]
	var gun := guns[side]
	var socket := muzzles[side]
	var bias := -1.0 if side == 0 else 1.0
	var aiming := 1.0 if _aim_hold > 0. else smoothstep(.04,.40,absf(angle_difference(_aim,heading)))
	var ray := shoulder.to_local(socket.to_global(Vector3.RIGHT))-shoulder.to_local(socket.global_position)
	var pitch := -.13*step*bias*(1.-aiming) - atan2(ray.y,Vector2(ray.x,ray.z).length())*aiming + kick*.031
	shoulder.basis = Basis(Vector3.BACK,pitch*release) * shoulder.basis
	if aiming > 0.:
		var target := _target if _target.is_finite() else Vector2.from_angle(_aim)*100.
		var mount := shoulder.get_parent_node_3d()
		var tip := mount.to_local(socket.global_position)
		var axis := mount.to_local(socket.to_global(Vector3.RIGHT))-tip
		var bore := Vector2(axis.x,axis.z).normalized()
		var target_height := to_local(socket.global_position).y
		var contact := mount.to_local(to_global(Vector3(target.x,target_height,target.y)))-shoulder.position
		var line := Vector2(contact.x,contact.z)
		var arm := tip-shoulder.position
		# The bore is offset from the shoulder's swivel axis. Solve the
		# angle against that offset, including a target beside the mech.
		var lateral := bore.cross(Vector2(arm.x,arm.z))
		var turn := bore.angle_to(line)-asin(clampf(lateral/maxf(.00001,line.length()),-1.,1.))
		shoulder.basis = Basis(Vector3.UP,-clampf(wrapf(turn,-PI,PI),-1.22,1.22)*release*aiming) * shoulder.basis
	if kick > 0.:
		var bore_axis := (gun.global_basis.inverse()*socket.global_basis.x).normalized()
		gun.position -= gun.basis*bore_axis*.062*_diameter*kick*release

func _socket(mode: String, side: int) -> Node3D:
	var index := muzzle_index if side < 0 else clampi(side,0,1)
	var airborne := mode == AIR if not mode.is_empty() else flight_progress >= .5
	return rails[index] if airborne else muzzles[index]

func muzzle_world(mode: String = "", side: int = -1) -> Vector3:
	return _socket(mode,side).global_position

func muzzle_direction_world(mode: String = "", side: int = -1) -> Vector3:
	return _socket(mode,side).global_basis.x.normalized()

func muzzle_screen_offset(mode: String = "", side: int = -1) -> Vector2:
	var point := to_local(muzzle_world(mode,side))
	return Vector2(point.x,point.z)

func fire(mode: String, shot_heading: float) -> void:
	_fire(mode,shot_heading,Vector2.INF,0.,-1)

func fire_at(mode: String, target_offset: Vector2, elapsed: float = 0., side: int = -1) -> void:
	_fire(mode,target_offset.angle(),target_offset,elapsed,side)

func _fire(mode: String, angle: float, target: Vector2, elapsed: float, side: int) -> void:
	if not _valid or wreck != null or mode not in [GROUND,AIR]:
		return
	muzzle_index = int(_cursor[mode]) if side < 0 else clampi(side,0,1)
	_cursor[mode] = 1-muzzle_index
	var hold := .19-elapsed
	if mode == GROUND and hold > 0.:
		_aim = angle
		_target = target
		_aim_hold = hold
	_effects.start(self,muzzle_index,mode,elapsed)
	_pose()

func destroy() -> void:
	if not _valid or wreck != null:
		return
	_effects.stop()
	var roles: Dictionary = {}
	for part in model_root.find_children("*","MeshInstance3D",true,false):
		if not part.visible:
			continue
		var owner_joint: Node3D = (part as MeshInstance3D).get_parent_node_3d()
		while owner_joint != null and not joints.has(String(owner_joint.name)):
			owner_joint = owner_joint.get_parent_node_3d()
		if owner_joint != null:
			roles[part] = String(owner_joint.name)
	wreck = Wreck.new()
	presentation.add_child(wreck)
	wreck.airborne = flight_progress
	wreck_age = 0.
	wreck.begin(model_root,roles,ground_height)

func is_finished() -> bool:
	return wreck_age >= Wreck.WRECK_DURATION
