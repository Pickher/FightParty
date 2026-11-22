extends Node3D
## Articulated ground armor. Actor +X/+Z map to battlefield X/Y, one actor unit per footprint.

const Wreck = preload("res://scripts/visuals/marauder_wreck.gd")
const SIDES := ["P", "N"]
const BODY_TURN_RATE := 4.2
const AIM_TURN_RATE := 7.4
const STRIDE := 0.69
const STANCE := 0.57
const TURN_CYCLE_ANGLE := 1.32
const RECOIL_TIME := 0.19
const FLASH_TIME := 0.115
const AIM_HOLD := 0.23

static var _flash_mesh: ArrayMesh
var heading := 0.0
var aim := 0.0
var walk_phase := 0.0
var stride_weight := 0.0
var ground_height := 0.0
var last_arm := 0
var wreck: Node3D
var wreck_age := -1.0

var presentation := Node3D.new()
var facing := Node3D.new()
var model_root: Node3D
var pelvis: Node3D
var trunk: Node3D
var helmet: Node3D
var reactor: Node3D
var reactor_socket: Node3D
var hips: Array[Node3D] = []
var knees: Array[Node3D] = []
var feet: Array[Node3D] = []
var shoulders: Array[Node3D] = []
var launchers: Array[Node3D] = []
var muzzles: Array[Node3D] = []
var flashes: Array[MeshInstance3D] = [null, null]
var rest: Dictionary = {}

var _model_diameter := 1.0
var _model_center := Vector3.ZERO
var _next_arm := 0
var _ready_to_pose := false
var _aim_weight := 0.0
var _target_hold := 0.0
var _target := Vector2.INF
var _shot_age := PackedFloat32Array([9.0, 9.0])
var _turn_phase := 0.0
var _turn_weight := 0.0
var _turn_direction := 1.0

func setup(model: PackedScene, bounds: AABB, initial_heading: float) -> bool:
	if model == null:
		return false
	heading = initial_heading
	aim = heading
	_model_diameter = maxf(0.001, maxf(bounds.size.x, bounds.size.z))
	_model_center = bounds.get_center()
	ground_height = -0.5 * bounds.size.y / _model_diameter

	add_child(presentation)
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		# Project height north in the overhead battlefield without tilting grounded soles.
		var top := smoothstep(0.86, 0.99, camera.global_basis.z.normalized().dot(Vector3.UP))
		var height_projection := 0.61 * top
		presentation.basis = Basis(Vector3.RIGHT, Vector3(0, 1, -height_projection), Vector3.BACK)
		presentation.position.z = ground_height * height_projection * 0.45
	presentation.add_child(facing)
	var centered := Node3D.new()
	facing.add_child(centered)
	centered.scale = Vector3.ONE / _model_diameter
	centered.position = -_model_center / _model_diameter
	model_root = model.instantiate() as Node3D
	if model_root == null:
		return false
	centered.add_child(model_root)

	pelvis = _joint("Pelvis")
	trunk = _joint("Trunk")
	helmet = _joint("Helmet")
	reactor = _joint("Reactor")
	reactor_socket = _joint("ReactorCore")
	for side in SIDES:
		hips.append(_joint("Hip" + side))
		knees.append(_joint("Knee" + side))
		feet.append(_joint("Ankle" + side))
		shoulders.append(_joint("Shoulder" + side))
		launchers.append(_joint("Launcher" + side))
		muzzles.append(_joint("ArmMuzzle" + side))
	if pelvis == null or trunk == null:
		hide()
		return false
	for group in [hips, knees, feet, shoulders, launchers, muzzles]:
		if group.has(null):
			hide()
			return false
	_ready_to_pose = true
	_pose()
	return true

func _joint(node_name: String) -> Node3D:
	var joint := model_root.find_child(node_name, true, false) as Node3D
	if joint != null:
		rest[joint] = joint.transform
	return joint

func advance(delta: float, desired_heading: float, distance: float, aim_heading: float = NAN) -> void:
	var dt := maxf(delta, 0.0)
	if dt == 0.0 or not _ready_to_pose:
		return
	if wreck != null:
		wreck_age += dt
		wreck.seek(wreck_age)
		return
	var moving := absf(distance) > 0.00001
	var desired_aim := desired_heading if is_nan(aim_heading) else aim_heading
	var aim_weight := 1.0 if not is_nan(aim_heading) or _target_hold > 0.0 else 0.0
	var hull_goal := desired_heading
	if not moving and not is_nan(aim_heading) and absf(angle_difference(desired_heading, aim_heading)) > 0.75:
		hull_goal = aim_heading
	if not moving and stride_weight == 0.0 and _turn_weight == 0.0 and _target_hold == 0.0 and _aim_weight == aim_weight and _shot_age[0] >= RECOIL_TIME and _shot_age[1] >= RECOIL_TIME:
		if absf(angle_difference(heading, hull_goal)) < 0.00001 and absf(angle_difference(aim, desired_aim)) < 0.00001:
			return
	var previous_heading := heading
	heading = rotate_toward(heading, hull_goal, BODY_TURN_RATE * dt)
	var angular_step := angle_difference(previous_heading, heading)
	var pivoting := not moving and absf(angular_step) > 0.00001
	if pivoting:
		var direction := signf(angular_step)
		if _turn_weight == 0.0 or direction != _turn_direction:
			# Lift the outside boot first. The inside boot supports the initial turn.
			_turn_phase = 0.0 if direction > 0.0 else 0.5
		_turn_direction = direction
		_turn_phase = fposmod(_turn_phase + absf(angular_step) / TURN_CYCLE_ANGLE, 1.0)
	_turn_weight = move_toward(_turn_weight, 1.0 if pivoting else 0.0, dt * (11.0 if pivoting else 6.0))
	stride_weight = move_toward(stride_weight, 1.0 if moving else 0.0, dt * (8.5 if moving else 5.1))
	walk_phase = fposmod(walk_phase + distance / STRIDE, 1.0)
	_target_hold = maxf(0.0, _target_hold - dt)
	_aim_weight = move_toward(_aim_weight, aim_weight, dt * 6.5)
	if _target_hold == 0.0:
		_target = Vector2.INF
		aim = rotate_toward(aim, desired_aim if not is_nan(aim_heading) else heading, AIM_TURN_RATE * dt)
	for i in _shot_age.size():
		_shot_age[i] += dt
	_pose()
	_update_flashes()

func _recoil(index: int) -> float:
	var elapsed := float(_shot_age[index])
	if elapsed >= RECOIL_TIME:
		return 0.0
	return (0.61 + 0.39 * smoothstep(0.0, 0.027, elapsed)) * (1.0 - smoothstep(0.027, RECOIL_TIME, elapsed))

func _pose() -> void:
	facing.rotation.y = -heading
	var phase := walk_phase * TAU
	var pivot_phase := _turn_phase * TAU
	var kick := maxf(_recoil(0), _recoil(1))
	var stride_sink := (0.061 + 0.014 * cos(phase * 2.0)) * stride_weight
	var pivot_sink := (0.026 + 0.010 * cos(pivot_phase * 2.0)) * _turn_weight
	var sink := _model_diameter * (stride_sink + pivot_sink + 0.011 * kick)
	var sway := _model_diameter * (0.022 * sin(phase) * stride_weight + 0.026 * sin(pivot_phase) * _turn_weight)
	var pelvis_pose: Transform3D = rest[pelvis]
	pelvis.position = pelvis_pose.origin + Vector3(0, -sink, sway)
	for i in 2:
		_pose_leg(i, fposmod(walk_phase + 0.5 * i, 1.0), sink, sway)

	var torso_twist := clampf(angle_difference(heading, aim), -1.19, 1.19)
	var walk_twist := 0.080 * sin(phase) * stride_weight * (1.0 - 0.84 * _aim_weight)
	var trunk_pose: Transform3D = rest[trunk]
	trunk.basis = trunk_pose.basis * Basis(Vector3.UP, -torso_twist + walk_twist) * Basis(Vector3.RIGHT, -0.092 * sin(phase) * stride_weight) * Basis(Vector3.BACK, -0.054 * stride_weight + 0.046 * kick)
	var actor_from_trunk := global_transform.affine_inverse() * trunk.global_transform
	for i in 2:
		_pose_arm(i, phase, actor_from_trunk)

func _pose_leg(index: int, cycle: float, sink: float, sway: float) -> void:
	var offset: float
	var lift := 0.0
	var toe := 0.0
	if cycle < STANCE:
		# Backward travel is the distance that the hull moved under this planted sole.
		offset = STRIDE * (STANCE * 0.5 - cycle)
	else:
		var swing := (cycle - STANCE) / (1.0 - STANCE)
		offset = STRIDE * STANCE * (smoothstep(0.0, 1.0, swing) - 0.5)
		lift = 0.102 * pow(maxf(0.0, sin(swing * PI)), 1.43)
		toe = 0.18 * sin(swing * TAU)
	var hip_pose: Transform3D = rest[hips[index]]
	var knee_pose: Transform3D = rest[knees[index]]
	var foot_pose: Transform3D = rest[feet[index]]
	var neutral := knee_pose.origin + foot_pose.origin
	var turn_cycle := fposmod(_turn_phase + index * 0.5, 1.0)
	var pivot_turn := 0.0
	var pivot_lift := 0.0
	if _turn_weight > 0.0:
		if turn_cycle < STANCE:
			pivot_turn = TURN_CYCLE_ANGLE * (STANCE * 0.5 - turn_cycle)
		else:
			var swing := (turn_cycle - STANCE) / (1.0 - STANCE)
			pivot_turn = TURN_CYCLE_ANGLE * STANCE * (smoothstep(0.0, 1.0, swing) - 0.5)
			pivot_lift = 0.070 * pow(maxf(0.0, sin(swing * PI)), 1.27)
		pivot_turn *= _turn_weight * _turn_direction
		pivot_lift *= _turn_weight
	var pelvis_pose: Transform3D = rest[pelvis]
	var boot := pelvis_pose.origin + hip_pose.origin + neutral - _model_center
	var boot_plane := Vector2(boot.x, boot.z)
	# Subtract the hull's yaw while this boot is planted, then lift it around the arc.
	var pivot_offset := boot_plane.rotated(pivot_turn) - boot_plane
	var upper := Vector2(knee_pose.origin.x, knee_pose.origin.y)
	var lower := Vector2(foot_pose.origin.x, foot_pose.origin.y)
	if minf(upper.length_squared(), lower.length_squared()) < 0.000001:
		return
	var height := neutral.y + (lift * stride_weight + pivot_lift) * _model_diameter + sink
	var lateral := neutral.z + pivot_offset.y - sway
	var goal_yz := Vector2(height, lateral)
	# The authored leg has sideways offsets. Work in the sagittal plane first, then
	# roll the whole chain so its toe meets the exact requested lateral position.
	var sagittal_y := -sqrt(maxf(0.00001, goal_yz.length_squared() - neutral.z * neutral.z))
	var target := Vector2(neutral.x + offset * stride_weight * _model_diameter + pivot_offset.x, sagittal_y)
	var upper_length := upper.length()
	var lower_length := lower.length()
	var reach := clampf(target.length(), absf(upper_length - lower_length) + 0.00001, upper_length + lower_length - 0.00001)
	var rest_bend := upper.angle_to(lower)
	# Preserve the rig's forward knee. Signed bend allows different authored rest stances.
	var bend := acos(clampf((reach * reach - upper.length_squared() - lower.length_squared()) / (2.0 * upper_length * lower_length), -1.0, 1.0))
	if rest_bend <= 0.0:
		bend = -bend
	var hip_pitch := target.angle() - atan2(lower_length * sin(bend), upper_length + lower_length * cos(bend)) - upper.angle()
	var knee_pitch := bend - rest_bend
	var hip_roll := Vector2(sagittal_y, neutral.z).angle_to(goal_yz)
	var roll := Basis(Vector3.RIGHT, hip_roll)
	hips[index].basis = hip_pose.basis * roll * Basis(Vector3.BACK, hip_pitch)
	knees[index].basis = knee_pose.basis * Basis(Vector3.BACK, knee_pitch)
	var shin_basis := hips[index].basis * knees[index].basis
	feet[index].basis = shin_basis.inverse() * Basis(Vector3.UP, -pivot_turn) * foot_pose.basis * Basis(Vector3.BACK, toe * stride_weight)

func _pose_arm(index: int, phase: float, actor_from_trunk: Transform3D) -> void:
	var shoulder_pose: Transform3D = rest[shoulders[index]]
	var launcher_pose: Transform3D = rest[launchers[index]]
	var muzzle_pose: Transform3D = rest[muzzles[index]]
	var axis := muzzle_pose.basis.x.normalized()
	var kick := _recoil(index)
	# The gun slides back along its own bore; the other carrier and gun remain untouched.
	launchers[index].position = launcher_pose.origin - launcher_pose.basis * axis * (0.092 * kick * _model_diameter)
	var swing := 0.135 * sin(phase + PI * index) * stride_weight * (1.0 - _aim_weight)
	var launcher_from_shoulder := launchers[index].transform * muzzle_pose
	var local_ray := shoulder_pose.basis * launcher_from_shoulder.basis.x.normalized()
	var slope := atan2(local_ray.y, Vector2(local_ray.x, local_ray.z).length())
	var pitch := Basis(Vector3.BACK, swing - slope * _aim_weight + 0.073 * kick)
	var orientation := pitch * shoulder_pose.basis
	var yaw := 0.0
	if _aim_weight > 0.0:
		var target := _target if _target.is_finite() else Vector2.from_angle(aim) * 100.0
		yaw = _barrel_yaw(actor_from_trunk, shoulder_pose.origin, orientation * launcher_from_shoulder.origin,
			orientation * launcher_from_shoulder.basis.x, target) * _aim_weight
	shoulders[index].basis = Basis(Vector3.UP, yaw) * orientation

static func _barrel_yaw(actor_from_trunk: Transform3D, mount: Vector3, port: Vector3, ray: Vector3, target: Vector2) -> float:
	var yaw := 0.0
	for i in 3:
		var turn := Basis(Vector3.UP, yaw)
		var offset := turn * port
		var axis := turn * ray
		var muzzle := actor_from_trunk * (mount + offset)
		var direction := actor_from_trunk.basis * axis
		var line := Vector2(direction.x, direction.z)
		var to_target := target - Vector2(muzzle.x, muzzle.z)
		var error := line.cross(to_target)
		if absf(error) < 0.00001:
			break
		var d_axis := actor_from_trunk.basis * Vector3.UP.cross(axis)
		var d_offset := actor_from_trunk.basis * Vector3.UP.cross(offset)
		var derivative := Vector2(d_axis.x, d_axis.z).cross(to_target) - line.cross(Vector2(d_offset.x, d_offset.z))
		if absf(derivative) < 0.0001:
			break
		yaw = clampf(yaw - error / derivative, -1.06, 1.06)
	return yaw

func _selected_arm(side: int) -> int:
	return last_arm if side < 0 else side % 2

func muzzle_world(side: int = -1) -> Vector3:
	return muzzles[_selected_arm(side)].global_position if _ready_to_pose else global_position

func muzzle_direction_world(side: int = -1) -> Vector3:
	return muzzles[_selected_arm(side)].global_basis.x.normalized() if _ready_to_pose else global_basis.x.normalized()

func muzzle_screen_offset(side: int = -1) -> Vector2:
	var location := to_local(muzzle_world(side))
	return Vector2(location.x, location.z)

func muzzle_heading(side: int = -1) -> Vector2:
	var axis := global_basis.inverse() * muzzle_direction_world(side)
	return Vector2(axis.x, axis.z).normalized()

func fire_at(target_offset: Vector2, shot_age: float = 0.0, side: int = -1) -> bool:
	if wreck != null or not _ready_to_pose:
		return false
	last_arm = _next_arm if side < 0 else side % 2
	_next_arm = 1 - last_arm
	if target_offset.is_finite() and target_offset.length_squared() > 0.000001:
		aim = target_offset.angle()
		_target = target_offset
		# A shot from behind would require the launchers to pass through the torso.
		if absf(angle_difference(heading, aim)) > 1.86:
			heading = aim
	_aim_weight = 1.0
	var elapsed := maxf(0.0, shot_age)
	_target_hold = maxf(0.0, AIM_HOLD - elapsed)
	_shot_age[last_arm] = elapsed
	if elapsed < FLASH_TIME and flashes[last_arm] == null:
		var node := MeshInstance3D.new()
		node.mesh = _make_flash()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		flashes[last_arm] = node
	_pose()
	_update_flashes()
	return true

static func _make_flash() -> ArrayMesh:
	if _flash_mesh != null:
		return _flash_mesh
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	paint.vertex_color_use_as_albedo = true
	builder.set_material(paint)
	var profiles := [
		[0.002, 0.029, Color("ffb45b")],
		[0.041, 0.061, Color("fff6c7")],
		[0.088, 0.040, Color("ffe29e")],
		[0.137, 0.005, Color("ff963e")],
	]
	for section in range(profiles.size() - 1):
		var from: Array = profiles[section]
		var to: Array = profiles[section + 1]
		for i in 7:
			var a := i * TAU / 7.0
			var b := (i + 1) * TAU / 7.0
			var va := Vector3(0, cos(a), sin(a))
			var vb := Vector3(0, cos(b), sin(b))
			var from_a := Vector3.RIGHT * float(from[0]) + va * float(from[1])
			var from_b := Vector3.RIGHT * float(from[0]) + vb * float(from[1])
			var to_a := Vector3.RIGHT * float(to[0]) + va * float(to[1])
			var to_b := Vector3.RIGHT * float(to[0]) + vb * float(to[1])
			for vertex in [from_a, from_b, to_a, to_a, from_b, to_b]:
				builder.set_color(from[2] if vertex.x < float(to[0]) else to[2])
				builder.add_vertex(vertex)
	_flash_mesh = builder.commit()
	return _flash_mesh

func _update_flashes() -> void:
	for i in flashes.size():
		var node := flashes[i]
		if node == null:
			continue
		var progress := float(_shot_age[i]) / FLASH_TIME
		node.visible = progress < 1.0
		if node.visible:
			var fade := 1.0 - smoothstep(0.20, 1.0, progress)
			var length := maxf(0.004, fade * (0.8 + progress * 0.40) * _model_diameter)
			var radius := maxf(0.004, fade * (0.74 + progress * 0.30) * _model_diameter)
			node.global_transform = muzzles[i].global_transform.scaled_local(Vector3(length, radius, radius))

func destroy() -> void:
	if wreck != null or not _ready_to_pose:
		return
	for flash in flashes:
		if flash != null:
			flash.hide()
	var reactor_position := Vector3.INF
	if reactor_socket != null:
		reactor_position = reactor_socket.global_position
	elif reactor != null:
		reactor_position = reactor.global_position
	wreck = Wreck.new()
	presentation.add_child(wreck)
	var roles: Dictionary = {}
	for part in model_root.find_children("*", "MeshInstance3D", true, false):
		var ancestor: Node = part
		while ancestor != null and not rest.has(ancestor):
			ancestor = ancestor.get_parent()
		roles[part] = str(ancestor.name) if ancestor != null else "Trunk"
	wreck.begin_at_reactor(model_root, roles, ground_height, reactor_position)
	wreck_age = 0.0

func is_finished() -> bool:
	return wreck_age >= Wreck.WRECK_DURATION
