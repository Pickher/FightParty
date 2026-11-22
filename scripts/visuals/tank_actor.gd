extends Node3D
## +X is forward, +Y is up, +Z is map south. One actor unit is one mobile footprint.
const RIG_PATH := "res://assets/models/mortar/mortar_rig.glb"
const Section = preload("res://scripts/visuals/tank_section.gd")
const Treads = preload("res://scripts/visuals/tank_treads.gd")
const Wreck = preload("res://scripts/visuals/tank_wreck.gd")
const MuzzleShader = preload("res://scripts/visuals/tank_muzzle.gdshader")
const JOINTS := ["Hull", "TrackFrontP", "TrackFrontN", "TrackRearP", "TrackRearN",
		"ArmP", "ArmN", "FootP", "FootN", "Turret", "Mount", "BarrelP", "BarrelN", "CenterBarrel"]
const DEPLOY_TIME := 1.50
const PACK_TIME := 1.00
const HULL_SLEW := 2.75
const TURRET_SLEW := 4.40
const MOBILE := "mobile_cannon"
const SIEGE := "siege_cannon"

var presentation := Node3D.new()
var facing := Node3D.new()
var centered := Node3D.new()
var model_root: Node3D
var sections: Array[Section] = []
var joints: Dictionary = {}
var hull: Node3D
var turret: Node3D
var mount: Node3D
var barrels: Array[Node3D] = []
var mobile_muzzles: Array[Node3D] = []
var siege_muzzle: Node3D
var tracks: Array[Node3D] = []
var feet: Array[Node3D] = []
var tread_banks: Array[Treads] = []
var track_distance := PackedFloat64Array([0.0, 0.0])
var heading := 0.0
var turret_heading := 0.0
var deployment_progress := 0.0
var ground_height := 0.0
var length_factor := 1.0
var muzzle_index := 0
var flash: MeshInstance3D
var shot_age := 99.0
var wreck: Wreck
var wreck_age := -1.0
var _ready_rig := false
var _wanted := 0.0
var _speed := 0.0
var _lean := 0.0
var _serial := 0
var _arm_shots := 0
var _shot_mode := MOBILE
var _target_offset := Vector2.INF
var _hold := 0.0
var _flash_paint: ShaderMaterial
static var _flash_mesh: ArrayMesh
static var _mobile_bounds_cache: Dictionary = {}

func setup(model: PackedScene, bounds: AABB, initial_heading: float, initial_deployment: float = 0.0) -> bool:
	if model == null:
		return false
	model_root = model.instantiate() as Node3D
	if model_root == null:
		return false
	add_child(presentation)
	presentation.add_child(facing)
	facing.add_child(centered)
	centered.add_child(model_root)
	var root_inverse := model_root.global_transform.affine_inverse()
	var ends: Dictionary = {}
	for key in JOINTS:
		var joint := model_root.find_child(key, true, false) as Node3D
		var marker := model_root.find_child("Deploy" + key, true, false) as Node3D
		if joint == null or marker == null:
			return false
		var parent := joint.get_parent()
		var parent_deployed: Transform3D = ends.get(parent, Transform3D.IDENTITY)
		ends[joint] = root_inverse * marker.global_transform
		var rail := Vector3.RIGHT if not key.begins_with("Foot") else Vector3.UP
		var piece := Section.new()
		if not piece.setup(joint, parent_deployed.affine_inverse() * ends[joint], rail):
			return false
		sections.append(piece)
		joints[key] = joint
	hull = joints.Hull
	turret = joints.Turret
	mount = joints.Mount
	for side in ["P", "N"]:
		var port := model_root.find_child("MobileMuzzle" + side, true, false) as Node3D
		if port == null:
			return false
		mobile_muzzles.append(port)
		barrels.append(joints["Barrel" + side])
		feet.append(joints["Foot" + side])
	siege_muzzle = model_root.find_child("SiegeMuzzle", true, false)
	if siege_muzzle == null:
		return false
	if not _mobile_bounds_cache.has(model):
		# Imported Mesh AABBs can include the alternate shape. Measure unposed mobile
		# vertices once so the zero floor and 1.6-cell footprint remain exact in both forms.
		var mobile_box := AABB()
		var measured := false
		for section in sections:
			var native := section.mobile_mesh
			if native == null:
				continue
			var space := root_inverse * native.global_transform
			for surface in native.mesh.get_surface_count():
				var vertices: PackedVector3Array = native.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for point in vertices:
					var local := space * point
					mobile_box = mobile_box.expand(local) if measured else AABB(local, Vector3.ZERO)
					measured = true
		_mobile_bounds_cache[model] = mobile_box if measured else bounds
	var mobile_bounds: AABB = _mobile_bounds_cache[model]
	length_factor = 1.0 / maxf(0.001, maxf(mobile_bounds.size.x, mobile_bounds.size.z))
	ground_height = -mobile_bounds.size.y * 0.5 * length_factor
	centered.scale = Vector3.ONE * length_factor
	centered.position = -mobile_bounds.get_center() * length_factor
	for name_key in ["TrackFrontP", "TrackFrontN", "TrackRearP", "TrackRearN"]:
		var bank: Node3D = joints[name_key]
		var tread := Treads.new()
		if not tread.setup(bank):
			tread.renderer.free()
			return false
		tracks.append(bank)
		tread_banks.append(tread)
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var shear := 0.46 * smoothstep(0.87, 0.998, camera.global_basis.z.normalized().dot(Vector3.UP))
		presentation.basis = Basis(Vector3.RIGHT, Vector3(0, 1, -shear), Vector3.BACK)
		presentation.position.z = ground_height * shear * 0.44
	heading = initial_heading
	turret_heading = heading
	deployment_progress = clampf(initial_deployment, 0, 1)
	_wanted = deployment_progress
	_ready_rig = true
	_pose()
	return true

func set_deployed(deployed: bool) -> void:
	if wreck == null:
		_wanted = 1.0 if deployed else 0.0

func set_deployment_progress(value: float) -> void:
	if not _ready_rig or wreck != null:
		return
	_wanted = clampf(value, 0.0, 1.0)
	if not is_equal_approx(deployment_progress, _wanted):
		deployment_progress = _wanted
		_pose()
		_update_flash()

func advance(delta: float, desired_heading: float, distance: float, aim_heading: float = NAN) -> void:
	var dt := maxf(delta, 0.0)
	if not _ready_rig or dt <= 0.0:
		return
	if wreck != null:
		wreck_age += dt
		wreck.seek(wreck_age)
		if wreck_age >= Wreck.FADE_START:
			var coverage := 1.0 - smoothstep(Wreck.FADE_START, Wreck.WRECK_DURATION, wreck_age)
			for bank in tread_banks:
				bank.material.set_shader_parameter("coverage", coverage)
		return
	var desired_aim := turret_heading if is_nan(aim_heading) else aim_heading
	var movable := 1.0 - smoothstep(0.06, 0.48, deployment_progress)
	if distance == 0.0 and deployment_progress == _wanted and _hold <= 0.0 and shot_age > 0.40 and _speed == 0.0 and _lean == 0.0:
		if (movable == 0.0 or absf(angle_difference(heading, desired_heading)) < 0.00001) and absf(angle_difference(turret_heading, desired_aim)) < 0.00001:
			return
	var previous := heading
	heading = rotate_toward(heading, desired_heading, dt * HULL_SLEW * movable)
	var yaw := angle_difference(previous, heading)
	var roll_distance := distance * movable
	var track_radius := absf(tracks[0].position.z) * length_factor
	track_distance[0] += roll_distance - yaw * track_radius
	track_distance[1] += roll_distance + yaw * track_radius
	_speed = move_toward(_speed, minf(1.0, absf(roll_distance) / dt), dt * 7.5)
	_lean = move_toward(_lean, clampf(-yaw / dt * 0.027, -0.055, 0.055), dt * 0.68)
	shot_age += dt
	_hold = maxf(0.0, _hold - dt)
	if _hold <= 0.0:
		_target_offset = Vector2.INF
		turret_heading = rotate_toward(turret_heading, desired_aim, dt * TURRET_SLEW)
	var duration := DEPLOY_TIME if _wanted > deployment_progress else PACK_TIME
	deployment_progress = move_toward(deployment_progress, _wanted, dt / duration)
	_pose()
	_update_flash()

func _phase(key: String) -> float:
	var p := deployment_progress
	if key.begins_with("Track"):
		return smoothstep(0.02 if key.contains("Rear") else 0.07, 0.73, p)
	if key.begins_with("Arm"):
		return smoothstep(0.08, 0.72, p)
	if key.begins_with("Foot"):
		return smoothstep(0.22, 0.82, p)
	if key == "Hull":
		return smoothstep(0.04, 0.83, p)
	if key == "Turret":
		return smoothstep(0.17, 0.91, p)
	return smoothstep(0.23, 0.99, p)

func _pose() -> void:
	facing.rotation.y = -heading
	var track_id := 0
	for piece in sections:
		var key := String(piece.joint.name)
		var t := _phase(key)
		var pose := piece.at_rest.interpolate_with(piece.deployed, t)
		var arc := sin(PI * t)
		if key.begins_with("Track"):
			pose.origin.y += 0.017 * arc
			var bank := tread_banks[track_id]
			bank.material.set_shader_parameter("deployment", t)
			bank.material.set_shader_parameter("distance_traveled", track_distance[track_id % 2] / length_factor)
			track_id += 1
		elif key.begins_with("Arm"):
			pose.origin.z += (0.035 if key.ends_with("P") else -0.035) * arc
		elif key == "Mount":
			pose.origin.y += 0.039 * arc
		piece.joint.transform = pose
		piece.skin(t)
	var braced := smoothstep(0.06, 0.65, deployment_progress)
	var vibration := sin((track_distance[0] + track_distance[1]) * 60.0) * _speed * (1.0 - braced)
	var rocking := 0.007 * vibration
	hull.position.y += 0.004 * vibration
	hull.basis = Basis(Vector3.RIGHT, _lean * (1.0 - braced)) * Basis(Vector3.BACK, rocking) * hull.basis
	var siege_shot := _shot_mode == SIEGE
	var loss := 0.34 if siege_shot else 0.23
	var kick := (0.76 + 0.24 * smoothstep(0, 0.026, shot_age)) * (1.0 - smoothstep(0.027, loss, shot_age))
	if kick > 0.0:
		var gun: Node3D = joints.CenterBarrel if siege_shot else barrels[muzzle_index]
		var bore := siege_muzzle if siege_shot else mobile_muzzles[muzzle_index]
		var gun_axis := gun.global_basis.inverse() * bore.global_basis.x
		gun.position -= gun.basis * gun_axis.normalized() * kick * (0.113 if siege_shot else 0.058)
		mount.position.x -= kick * (0.020 if siege_shot else 0.008)
		turret.position.y -= 0.010 * kick
	_aim_turret()

func _aim_turret() -> void:
	var desired_yaw := -angle_difference(heading, turret_heading)
	var rest_basis := turret.basis
	var current_mode := _shot_mode if _hold > 0.0 else (SIEGE if deployment_progress >= 0.5 else MOBILE)
	var port := _muzzle(current_mode)
	var parent := turret.get_parent_node_3d()
	var parent_to_actor := global_transform.affine_inverse() * parent.global_transform
	var ray := parent.global_basis.inverse() * port.global_basis.x
	var offset := parent.to_local(port.global_position) - turret.position
	var target := _target_offset if _target_offset.is_finite() else Vector2.from_angle(turret_heading) * 1000.0
	# Solve rotation about the turret ring against the screen-projected line of this bore,
	# including the mobile barrels' side offset and the elevated siege gun.
	for pass_index in 4:
		var step := Basis(Vector3.UP, desired_yaw)
		var axis := step * ray
		var lever := step * offset
		var tip := parent_to_actor * (turret.position + lever)
		var direction := parent_to_actor.basis * axis
		var from_muzzle := target - Vector2(tip.x, tip.z)
		var line := Vector2(direction.x, direction.z)
		var cross := line.cross(from_muzzle)
		if absf(cross) < 0.00001:
			break
		var da := parent_to_actor.basis * Vector3.UP.cross(axis)
		var dp := parent_to_actor.basis * Vector3.UP.cross(lever)
		var derivative := Vector2(da.x, da.z).cross(from_muzzle) - line.cross(Vector2(dp.x, dp.z))
		if absf(derivative) < 0.0001:
			break
		desired_yaw -= clampf(cross / derivative, -0.48, 0.48)
	turret.basis = Basis(Vector3.UP, desired_yaw) * rest_basis

func _muzzle(mode: String) -> Node3D:
	return siege_muzzle if mode == SIEGE or (mode.is_empty() and deployment_progress >= 0.5) else mobile_muzzles[muzzle_index]

func muzzle_world(mode: String = "") -> Vector3:
	return _muzzle(mode).global_position

func muzzle_direction_world(mode: String = "") -> Vector3:
	return _muzzle(mode).global_basis.x.normalized()

func muzzle_screen_offset(mode: String = "") -> Vector2:
	var local := to_local(muzzle_world(mode))
	return Vector2(local.x, local.z)

func fire_at(mode: String, target_offset: Vector2) -> void:
	_fire(mode, target_offset.angle(), target_offset)

func fire(mode: String, shot_heading: float) -> void:
	_fire(mode, shot_heading, Vector2.INF)

func _fire(mode: String, shot_heading: float, offset: Vector2) -> void:
	if not _ready_rig or wreck != null or mode not in [MOBILE, SIEGE]:
		return
	if mode == MOBILE:
		muzzle_index = _arm_shots % 2
		_arm_shots += 1
	_shot_mode = mode
	shot_age = 0.0
	_serial += 1
	_hold = 0.34 if mode == SIEGE else 0.23
	turret_heading = shot_heading
	_target_offset = offset
	_pose()
	if flash == null:
		_prepare_flash()
	_flash_paint.set_shader_parameter("siege", float(mode == SIEGE))
	_flash_paint.set_shader_parameter("seed", float(_serial) * 0.67)
	_update_flash()

func _prepare_flash() -> void:
	if _flash_mesh == null:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for lobe in 3:
			for uv in [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(1, 0)]:
				tool.set_color(Color(lobe * 0.5, 0, 0))
				tool.set_uv(uv)
				tool.add_vertex(Vector3(uv.x, 0, uv.y - 0.5))
		_flash_mesh = tool.commit()
	flash = MeshInstance3D.new()
	flash.mesh = _flash_mesh
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_paint = ShaderMaterial.new()
	_flash_paint.shader = MuzzleShader
	flash.material_override = _flash_paint
	add_child(flash)

func _update_flash() -> void:
	if flash == null:
		return
	flash.visible = wreck == null and shot_age < (0.38 if _shot_mode == SIEGE else 0.25)
	if flash.visible:
		flash.global_transform = _muzzle(_shot_mode).global_transform
		_flash_paint.set_shader_parameter("age", shot_age)

func destroy() -> void:
	if not _ready_rig or wreck != null:
		return
	wreck_age = 0.0
	wreck = Wreck.new()
	presentation.add_child(wreck)
	if flash != null:
		flash.hide()
	wreck.vent = wreck.to_local(model_root.to_global(Vector3(-0.26, 0.25, 0)))
	var roles: Dictionary = {}
	var bank_meshes: Array[MeshInstance3D] = []
	for section in sections:
		for shell in [section.mobile_mesh, section.siege_mesh]:
			if shell != null and shell.visible:
				roles[shell] = String(section.joint.name)
		if String(section.joint.name).begins_with("Track"):
			bank_meshes.append(section.mobile_mesh if section.mobile_mesh.visible else section.siege_mesh)
	wreck.begin(facing, roles, ground_height)
	# Keep the actual tread shoes on their departing bank, at the locked wheel phase.
	for i in bank_meshes.size():
		tread_banks[i].renderer.reparent(bank_meshes[i].get_parent(), true)

func is_finished() -> bool:
	return wreck_age >= Wreck.WRECK_DURATION
