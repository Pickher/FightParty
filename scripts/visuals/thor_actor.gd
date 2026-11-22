extends Node3D
## Presentation poses in +X forward, +Y up, +Z right. One actor unit spans the rig footprint.
const Wreck = preload("res://scripts/visuals/thor_wreck.gd")
const SWITCH_TIME := 0.5
const STRIDE := 0.53
const STANCE := 0.58
const BODY_TURN := 3.1
const AIM_TURN := 6.2
enum Shot { HAMMER, HIGH_IMPACT, JAVELIN }
const SHOT_LIFE := [0.13, 0.15, 0.115]
const ARM_RECOIL_TIME := 0.21
const SHOULDER_RECOIL_TIME := 0.17
const SIDE_NAMES := ["P", "N"]
const CANNON_NAMES := ["InnerP", "InnerN", "OuterP", "OuterN"]

var presentation := Node3D.new()
var facing := Node3D.new()
var centered := Node3D.new()
var model_root: Node3D
var pelvis: Node3D
var trunk: Node3D
var hips: Array[Node3D] = []
var knees: Array[Node3D] = []
var feet: Array[Node3D] = []
var arms: Array[Node3D] = []
var cannons: Array[Node3D] = []
var shrouds: Array[MeshInstance3D] = []
var arm_sockets: Array[Node3D] = []
var cannon_sockets: Array[Node3D] = []
var deployed: Array[Transform3D] = []
var rest: Dictionary = {}
var heading := 0.0
var aim := 0.0
var aim_weight := 0.0
var walk_phase := 0.0
var stride_weight := 0.0
var transform_progress := 0.0
var target_progress := 0.0
var ground_height := 0.0
var length_factor := 1.0
var fire_age := PackedFloat32Array([9, 9, 9, 9, 9, 9])
var fire_kind := PackedInt32Array([0, 0, 0, 0, 0, 0])
var close_target := Vector2.INF
var target_hold := 0.0
var flashes: Array[Node3D] = [null, null, null, null, null, null]
var wreck: Node3D
var wreck_age := -1.0
static var shot_meshes: Dictionary = {}

func setup(model: PackedScene, bounds: AABB, initial_heading: float, initial_air_mode: String = "high_impact") -> void:
	heading = initial_heading
	aim = heading
	length_factor = 1.0 / maxf(0.001, maxf(bounds.size.x, bounds.size.z))
	ground_height = -0.5 * bounds.size.y * length_factor
	add_child(presentation)
	# The battle camera looks vertically down. Show elevation towards screen north
	# while keeping the grounded soles, collision anchor and floor height coherent.
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var overhead := smoothstep(0.86, 0.99, camera.global_transform.basis.z.normalized().dot(Vector3.UP))
		var foreshortening := 0.56 * overhead
		presentation.basis = Basis(Vector3.RIGHT, Vector3(0, 1, -foreshortening), Vector3.BACK)
		presentation.position.z = ground_height * foreshortening * 0.45
	presentation.add_child(facing)
	facing.add_child(centered)
	centered.scale = Vector3.ONE * length_factor
	centered.position = -bounds.get_center() * length_factor
	model_root = model.instantiate() as Node3D
	centered.add_child(model_root)
	pelvis = _joint("Pelvis")
	trunk = _joint("Trunk")
	for side in SIDE_NAMES:
		hips.append(_joint("Hip" + side))
		knees.append(_joint("Knee" + side))
		feet.append(_joint("Ankle" + side))
		arms.append(_joint("Shoulder" + side))
		arm_sockets.append(_joint("ArmMuzzle" + side))
	for part in CANNON_NAMES:
		var cannon := _joint("Cannon" + part)
		cannons.append(cannon)
		var shroud := cannon.find_child("Cannon" + part + "Mesh", true, false) as MeshInstance3D
		shrouds.append(shroud if shroud != null and shroud.get_blend_shape_count() > 0 else null)
		cannon_sockets.append(_joint("Muzzle" + part))
		deployed.append(_joint("Deploy" + part).transform)
	target_progress = 1.0 if initial_air_mode == "javelin" else 0.0
	transform_progress = target_progress
	_pose()

func _joint(node_name: String) -> Node3D:
	var node := model_root.find_child(node_name, true, false) as Node3D
	rest[node] = node.transform
	return node

func set_air_mode(mode: String) -> void:
	if wreck == null and mode in ["javelin", "high_impact"]:
		target_progress = 1.0 if mode == "javelin" else 0.0

func set_air_progress(value: float, target_mode: String) -> void:
	if wreck != null:
		return
	set_air_mode(target_mode)
	var desired := clampf(value, 0.0, 1.0)
	if not is_equal_approx(transform_progress, desired):
		transform_progress = desired
		_pose()
		_update_flashes()

func advance(delta: float, desired_heading: float, distance: float, aim_heading: float = NAN) -> void:
	var dt := maxf(delta, 0.0)
	if dt == 0.0:
		return
	if wreck != null:
		wreck_age += dt
		wreck.seek(wreck_age)
		return
	var travelling := absf(distance) > 0.00001
	var desired_aim := desired_heading if is_nan(aim_heading) else aim_heading
	var resting_aim := 0.0 if is_nan(aim_heading) else 1.0
	# A stationary, fully settled machine holds its pose without evaluating rig IK.
	if not travelling and stride_weight == 0.0 and target_hold == 0.0 and transform_progress == target_progress and aim_weight == resting_aim:
		if absf(angle_difference(heading, desired_heading)) < 0.00001 and absf(angle_difference(aim, desired_aim)) < 0.00001:
			return
	heading = rotate_toward(heading, desired_heading, BODY_TURN * dt)
	stride_weight = move_toward(stride_weight, 1.0 if travelling else 0.0, dt * (7.5 if travelling else 5.0))
	walk_phase = fposmod(walk_phase + distance / STRIDE, 1.0)
	transform_progress = move_toward(transform_progress, target_progress, dt / SWITCH_TIME)
	target_hold = maxf(0.0, target_hold - dt)
	if target_hold <= 0.0:
		close_target = Vector2.INF
	aim_weight = move_toward(aim_weight, 1.0 if target_hold > 0.0 or not is_nan(aim_heading) else 0.0, dt * 6.0)
	if target_hold <= 0.0:
		aim = rotate_toward(aim, heading if is_nan(aim_heading) else aim_heading, AIM_TURN * dt)
	for i in fire_age.size():
		fire_age[i] += dt
	_pose()
	_update_flashes()

func _recoil(index: int) -> float:
	var age := float(fire_age[index])
	var recovery := ARM_RECOIL_TIME if index < 2 else SHOULDER_RECOIL_TIME
	if age >= recovery:
		return 0.0
	return (0.73 + 0.27 * smoothstep(0, 0.024, age)) * (1.0 - smoothstep(0.024, recovery, age))

func _pose() -> void:
	facing.rotation.y = -heading
	var phase := walk_phase * TAU
	var blend := smoothstep(0.0, 1.0, transform_progress)
	var brace := maxf(_recoil(0), _recoil(1))
	var compression := 0.032 * stride_weight + 0.049 * blend + 0.010 * brace
	var sink := compression + 0.012 * cos(2.0 * phase) * stride_weight
	var sway := 0.018 * sin(phase) * stride_weight
	var pelvis_rest: Transform3D = rest[pelvis]
	pelvis.position = pelvis_rest.origin + Vector3(0, -sink, sway)
	for i in 2:
		_place_leg(i, fposmod(walk_phase + 0.5 * i, 1.0), sink, sway)
	var turn := angle_difference(heading, aim)
	var torso_twist := 0.052 * sin(phase) * stride_weight * (1.0 - aim_weight)
	trunk.rotation = Vector3(-0.077 * sin(phase) * stride_weight, -turn + torso_twist,
			-0.038 * blend - 0.026 * cos(2.0 * phase) * stride_weight + 0.057 * brace)
	var trunk_to_actor := global_transform.affine_inverse() * trunk.global_transform if aim_weight > 0.0 else Transform3D.IDENTITY
	for i in 2:
		_place_arm(i, blend, phase, trunk_to_actor)
	for i in cannons.size():
		var initial: Transform3D = rest[cannons[i]]
		var end := deployed[i]
		# Outer rails lift slightly ahead of the inner pair, clearing the shoulder aperture.
		var delay := 0.075 if i < 2 else 0.0
		var travel := smoothstep(delay, delay + 0.925, transform_progress)
		var pose := initial.interpolate_with(end, travel)
		var clearance := sin(PI * travel)
		pose.origin += Vector3(-0.018, 0.072, 0.035 * (1 if i % 2 == 0 else -1)) * clearance
		var tube_axis: Vector3 = (rest[cannon_sockets[i]] as Transform3D).basis.x.normalized()
		pose.origin -= pose.basis * tube_axis * _recoil(2 + i) * 0.023
		cannons[i].transform = pose
		var shroud := shrouds[i]
		if shroud != null and not is_equal_approx(shroud.get_blend_shape_value(0), 1.0 - travel):
			shroud.set_blend_shape_value(0, 1.0 - travel)

func _place_leg(index: int, p: float, sink: float, sway: float) -> void:
	# In stance the foot travels backward by exactly the actor's forward distance.
	# During swing the same sole lifts, passes the opposite foot, and plants level.
	var step_length := STRIDE / length_factor
	var offset_x: float
	var lift := 0.0
	var toe := 0.0
	if p < STANCE:
		offset_x = step_length * (0.5 * STANCE - p)
	else:
		var swing := (p - STANCE) / (1.0 - STANCE)
		var travel := smoothstep(0.0, 1.0, swing)
		offset_x = step_length * STANCE * (travel - 0.5)
		lift = 0.084 * pow(sin(PI * swing), 1.25)
		toe = -0.20 * sin(TAU * swing)
	var upper: Vector3 = (rest[knees[index]] as Transform3D).origin
	var lower: Vector3 = (rest[feet[index]] as Transform3D).origin
	var u := Vector2(upper.x, upper.y)
	var l := Vector2(lower.x, lower.y)
	var foot := u + l + Vector2(offset_x * stride_weight, lift * stride_weight + sink)
	var d := clampf(foot.length(), absf(u.length() - l.length()) + 0.0001, u.length() + l.length() - 0.0001)
	var bend := acos(clampf((d*d - u.length_squared() - l.length_squared()) / (2.0 * u.length() * l.length()), -1.0, 1.0))
	var hip_pitch := foot.angle() - atan2(l.length() * sin(bend), u.length() + l.length() * cos(bend)) - u.angle()
	var knee_pitch := bend - u.angle_to(l)
	var hip_roll := -sway / minf(-0.10, foot.y)
	hips[index].basis = Basis(Vector3.RIGHT, hip_roll) * Basis(Vector3.BACK, hip_pitch)
	knees[index].rotation.z = knee_pitch
	feet[index].basis = Basis(Vector3.BACK, -(knee_pitch + hip_pitch)) * Basis(Vector3.RIGHT, -hip_roll) * Basis(Vector3.BACK, toe * stride_weight)

func _place_arm(index: int, blend: float, phase: float, trunk_to_actor: Transform3D) -> void:
	var arm := arms[index]
	var port: Transform3D = rest[arm_sockets[index]]
	var start: Transform3D = rest[arm]
	var kick := _recoil(index)
	var swing := 0.095 * sin(phase + PI * index) * stride_weight * (1.0 - 0.7 * aim_weight)
	var axis := port.basis.x.normalized()
	var elevation := atan2(axis.y, Vector2(axis.x, axis.z).length())
	var aim_elevation := 0.04
	if fire_kind[index] == Shot.HIGH_IMPACT:
		aim_elevation += 0.21 * (1.0 - smoothstep(0.075, 0.21, fire_age[index]))
	var tilt := lerpf(-0.30 * blend + swing, aim_elevation - elevation, aim_weight) + 0.11 * kick
	var pitch := Basis(Vector3.BACK, tilt)
	var carrier := start.origin + Vector3(0.012 * blend, -0.043 * blend, 0.0)
	var yaw := 0.0
	if aim_weight > 0.0:
		var target := close_target if close_target.is_finite() else Vector2.from_angle(aim) * 1000.0
		yaw = _barrel_yaw(trunk_to_actor, carrier, pitch * (port.origin - axis * 0.098 * kick), pitch * axis, target) * aim_weight
	arm.basis = Basis(Vector3.UP, yaw) * pitch
	arm.position = carrier - (arm.basis * axis) * 0.098 * kick

static func _barrel_yaw(trunk_to_actor: Transform3D, carrier: Vector3, port: Vector3, ray: Vector3, target: Vector2) -> float:
	# Converge the actual muzzle line on the projected target. Correct for the
	# two unequal shoulder offsets, the shoulder pitch, and the top-down projection.
	var yaw := 0.0
	for pass_index in 3:
		var step := Basis(Vector3.UP, yaw)
		var offset := step * port
		var axis := step * ray
		var muzzle := trunk_to_actor * (carrier + offset)
		var direction := trunk_to_actor.basis * axis
		var line := Vector2(direction.x, direction.z)
		var towards := target - Vector2(muzzle.x, muzzle.z)
		var error := line.cross(towards)
		if absf(error) < 0.00001:
			break
		var d_axis := trunk_to_actor.basis * Vector3.UP.cross(axis)
		var d_offset := trunk_to_actor.basis * Vector3.UP.cross(offset)
		var slope := Vector2(d_axis.x, d_axis.z).cross(towards) - line.cross(Vector2(d_offset.x, d_offset.z))
		if absf(slope) < 0.0001:
			break
		yaw = clampf(yaw - error / slope, -1.08, 1.08)
	return yaw

func _slot(mode: String, strike: int) -> int:
	return 2 + posmod(strike, 4) if mode == "javelin" else posmod(strike, 2)

func _socket(index: int) -> Node3D:
	return arm_sockets[index] if index < 2 else cannon_sockets[index - 2]

func muzzle_world(mode: String, strike: int) -> Vector3:
	return _socket(_slot(mode, strike)).global_position

func muzzle_screen_offset(mode: String, strike: int) -> Vector2:
	var point := to_local(muzzle_world(mode, strike))
	return Vector2(point.x, point.z)

func javelin_launch_direction(strike: int) -> Vector2:
	var muzzle := _socket(_slot("javelin", strike))
	var axis := global_basis.inverse() * muzzle.global_basis.x
	return Vector2(axis.x, axis.z).normalized()

func fire_at(mode: String, strike: int, target_offset: Vector2, elapsed: float = 0.0) -> void:
	if wreck != null:
		return
	_fire(mode, strike, target_offset.angle(), target_offset, elapsed)

func fire(mode: String, strike: int, shot_heading: float) -> void:
	_fire(mode, strike, shot_heading, Vector2.INF)

func _fire(mode: String, strike: int, shot_heading: float, target: Vector2, elapsed: float = 0.0) -> void:
	if wreck != null or mode not in ["hammer", "high_impact", "javelin"]:
		return
	var index := _slot(mode, strike)
	if elapsed >= (ARM_RECOIL_TIME if index < 2 else SHOULDER_RECOIL_TIME):
		return
	close_target = target
	aim = shot_heading
	aim_weight = 1.0
	target_hold = 0.22 - elapsed
	fire_age[index] = elapsed
	fire_kind[index] = Shot.JAVELIN if mode == "javelin" else (Shot.HIGH_IMPACT if mode == "high_impact" else Shot.HAMMER)
	if flashes[index] == null:
		var flash := MeshInstance3D.new()
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flash)
		flashes[index] = flash
	(flashes[index] as MeshInstance3D).mesh = _shot_mesh(fire_kind[index])
	_pose()
	_update_flashes()

static func _shot_mesh(kind: int) -> ArrayMesh:
	if shot_meshes.has(kind):
		return shot_meshes[kind]
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	builder.set_material(material)
	if kind == Shot.JAVELIN:
		# Only ignition gas stays on the tube. The tracked missile owns its body and exhaust.
		_ring(builder, -0.005, 0.022, Color("fffce1"), 0.023, 0.041, Color("fff2b8"))
		_ring(builder, 0.023, 0.041, Color("fff2b8"), 0.061, 0.033, Color("ffb453"))
		_ring(builder, 0.061, 0.033, Color("ffb453"), 0.107, 0.0, Color("ee692b"))
	else:
		var large := 1.16 if kind == Shot.HIGH_IMPACT else 1.0
		var cold := Color("aee8ff") if kind == Shot.HIGH_IMPACT else Color("ffe7a0")
		var edge := Color("659cc1") if kind == Shot.HIGH_IMPACT else Color("f89c38")
		_ring(builder, -0.017, 0.023 * large, cold, 0.040, 0.047 * large, Color("ffffe6"))
		_ring(builder, 0.040, 0.047 * large, Color("ffffe6"), 0.092 * large, 0.033 * large, cold)
		_ring(builder, 0.092 * large, 0.033 * large, cold, 0.20 * large, 0.0, edge)
	shot_meshes[kind] = builder.commit()
	return shot_meshes[kind]

static func _ring(builder: SurfaceTool, x0: float, r0: float, color0: Color, x1: float, r1: float, color1: Color) -> void:
	for i in 8:
		var a := i * TAU / 8.0
		var b := (i + 1) * TAU / 8.0
		var va := Vector3(0.0, cos(a), sin(a))
		var vb := Vector3(0.0, cos(b), sin(b))
		var left_a := Vector3.RIGHT * x0 + va * r0
		var left_b := Vector3.RIGHT * x0 + vb * r0
		var right_a := Vector3.RIGHT * x1 + va * r1
		var right_b := Vector3.RIGHT * x1 + vb * r1
		for v in [left_a, left_b, right_a, right_a, left_b, right_b]:
			builder.set_color(color0 if is_equal_approx(v.x, x0) else color1)
			builder.add_vertex(v)

func _update_flashes() -> void:
	for i in flashes.size():
		var node := flashes[i]
		if node == null:
			continue
		var kind := int(fire_kind[i])
		var t := float(fire_age[i]) / float(SHOT_LIFE[kind])
		node.visible = t < 1.0
		if not node.visible:
			continue
		var socket := _socket(i)
		var reach := 1.0 - smoothstep(0.27, 1.0, t)
		var expansion := 1.0 + 0.28 * t
		var shape := Vector3(maxf(0.02, reach * expansion), maxf(0.02, reach), maxf(0.02, reach))
		node.global_transform = socket.global_transform.scaled_local(shape)

func destroy() -> void:
	if wreck != null:
		return
	for flash in flashes:
		if flash != null:
			flash.hide()
	wreck = Wreck.new()
	presentation.add_child(wreck)
	var roles: Dictionary = {}
	for part in model_root.find_children("*", "MeshInstance3D", true, false):
		var ancestor: Node = part
		while ancestor != null and not rest.has(ancestor):
			ancestor = ancestor.get_parent()
		roles[part] = str(ancestor.name) if ancestor != null else "Trunk"
	wreck.begin(model_root, roles, ground_height)
	wreck_age = 0.0
	wreck.seek(wreck_age)

func is_finished() -> bool:
	return wreck_age >= Wreck.WRECK_DURATION
