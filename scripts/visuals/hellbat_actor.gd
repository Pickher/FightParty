extends Node3D
## +X is forward; distances are expressed in actor footprint lengths.
const Assembly = preload("res://scripts/visuals/hellbat_vehicle_assembly.gd")
const Hellion = preload("res://scripts/visuals/hellion_actor.gd")
const FuelWreck = preload("res://scripts/visuals/hellbat_wreck.gd")
const FlameShader = preload("res://scripts/visuals/hellbat_flame.gdshader")
const RIG_PATH := "res://assets/models/hellbat_mech/hellbat_mech_rig.glb"
const TRANSFORM_DURATION := 1.45
const STRIDE := 0.45
const STANCE := 0.59
const AFTERBURN := 0.19
const DRIVE_TURN := 3.8
const SIDES := ["P", "N"]

var presentation := Node3D.new()
var facing := Node3D.new()
var centered := Node3D.new()
var model_root: Node3D
var pelvis: Node3D
var trunk: Node3D
var turret: Node3D
var muzzle: Node3D
var hips: Array[Node3D] = []
var knees: Array[Node3D] = []
var feet: Array[Node3D] = []
var shoulders: Array[Node3D] = []
var shields: Array[Node3D] = []
var tanks: Array[Node3D] = []
var shield_centers: Array[Vector3] = []
var joints: Array[Node3D] = []
var skins: Array[MeshInstance3D] = []
var rest: Dictionary = {}
var bind: Dictionary = {}
var folded: Dictionary = {}
var assembly: Assembly
var vehicle: Hellion
var vehicle_progress := 0.0
var _wanted_form := 0.0
var heading := 0.0
var aim := 0.0
var walk_phase := 0.0
var walk_weight := 0.0
var _step_direction := Vector2(1, 0)
var _overhead := 0.0
var length_factor := 1.0
var ground_height := 0.0
var guard := 0.0
var fire_age := 99.0
var fire_duration := 0.0
var shot_heading := 0.0
var shot_reach := 0.0
var _serial := 0
var flame: MeshInstance3D
var _flame_paint: ShaderMaterial
static var _ribbon: ArrayMesh
var wreck: FuelWreck
var wreck_age := -1.0

func setup(model: PackedScene, bounds: AABB, initial_heading: float) -> void:
	heading = initial_heading
	aim = heading
	length_factor = 1.0 / maxf(.001, maxf(bounds.size.x, bounds.size.z))
	ground_height = -0.5 * bounds.size.y * length_factor
	add_child(presentation)
	presentation.add_child(facing)
	facing.add_child(centered)
	centered.scale = Vector3.ONE * length_factor
	centered.position = -bounds.get_center() * length_factor
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_overhead = .48 * smoothstep(.86, .99, camera.global_basis.z.normalized().dot(Vector3.UP))
	model_root = model.instantiate()
	centered.add_child(model_root)
	pelvis = _joint("Pelvis")
	trunk = _joint("Trunk")
	for side in SIDES:
		hips.append(_joint("Hip" + side))
		knees.append(_joint("Knee" + side))
		feet.append(_joint("Ankle" + side))
		shoulders.append(_joint("Shoulder" + side))
		var shield := _joint("Shield" + side)
		shields.append(shield)
		var shell := skins.back() as MeshInstance3D
		shield_centers.append(shield.to_local(shell.to_global(shell.get_aabb().get_center())))
		tanks.append(_joint("Tank" + side))
	turret = _joint("Turret")
	muzzle = model_root.find_child("Muzzle", true, false)
	_pose()

func _joint(key: String) -> Node3D:
	var node := model_root.find_child(key, true, false) as Node3D
	joints.append(node)
	rest[node] = node.transform
	bind[node] = model_root.global_transform.affine_inverse() * node.global_transform
	var marker := model_root.find_child("Fold" + key, true, false) as Node3D
	folded[node] = model_root.global_transform.affine_inverse() * marker.global_transform
	skins.append(node.find_child(key + "Mesh", false, false) as MeshInstance3D)
	return node

func set_vehicle_form(as_vehicle: bool) -> void:
	if wreck_age < 0.0:
		_wanted_form = 1.0 if as_vehicle else 0.0
		if not is_equal_approx(_wanted_form, vehicle_progress):
			_end_spray()

func set_vehicle_progress(progress: float) -> void:
	if wreck_age >= 0.0:
		return
	_wanted_form = clampf(progress, 0.0, 1.0)
	if not is_equal_approx(_wanted_form, vehicle_progress):
		_end_spray()
	vehicle_progress = _wanted_form
	_pose()
	_update_flame()

func is_vehicle() -> bool:
	return vehicle_progress >= 1.0

func _end_spray() -> void:
	fire_age = fire_duration + AFTERBURN
	if flame != null:
		flame.hide()
	if vehicle != null and vehicle.flame != null:
		vehicle.shot_age = vehicle.shot_duration + Hellion.FLAME_AFTERGLOW
		vehicle.flame.hide()

func advance(delta: float, desired_heading: float, distance: float, aim_heading: float = NAN) -> void:
	var dt := maxf(0.0, delta)
	if dt <= 0.0:
		return
	if wreck_age >= 0.0:
		wreck_age += dt
		if wreck != null:
			wreck.seek(wreck_age)
		elif vehicle != null:
			vehicle.advance(dt, 0.0, 0.0)
		return
	var desired_aim := desired_heading if is_nan(aim_heading) else aim_heading
	if not is_vehicle() and vehicle_progress == _wanted_form and walk_weight == 0.0 and guard == 0.0 and fire_age >= fire_duration + AFTERBURN:
		if absf(distance) < 0.00001 and absf(angle_difference(heading, desired_heading)) < 0.00001 and absf(angle_difference(aim, desired_aim)) < 0.00001:
			return
	var previous := heading
	heading = rotate_toward(heading, desired_heading, dt * DRIVE_TURN)
	var turn := angle_difference(previous, heading)
	var pivot_distance := absf(turn) * .18
	var travel := absf(distance) + pivot_distance
	var moving := travel > 0.00001
	if moving:
		_step_direction = Vector2(distance / travel, turn * .18 / travel)
		walk_phase = fposmod(walk_phase + travel / STRIDE, 1.0)
	walk_weight = move_toward(walk_weight, 1.0 if moving else 0.0, dt * 7.0)
	fire_age += dt
	var firing := fire_age < fire_duration + AFTERBURN and vehicle_progress < 0.15
	if firing:
		desired_aim = shot_heading
	elif is_nan(aim_heading):
		desired_aim = heading
	var slew := 2.9 if not firing and is_nan(aim_heading) else 5.3
	aim = rotate_toward(aim, desired_aim, dt * slew)
	guard = move_toward(guard, 1.0 if fire_age < fire_duration and firing else 0.0, dt * (10.5 if firing else 5.4))
	var prior := vehicle_progress
	vehicle_progress = move_toward(vehicle_progress, _wanted_form, dt / TRANSFORM_DURATION)
	if is_vehicle() and prior >= 1.0:
		facing.rotation.y = -heading
	else:
		_pose()
	if is_vehicle():
		vehicle.advance(dt, 0.0, distance, angle_difference(heading, aim))
	_update_flame()

func _pose() -> void:
	var p := vehicle_progress
	var shear := _overhead * (1.0 - smoothstep(.28,1.0,p))
	presentation.basis = Basis(Vector3.RIGHT, Vector3(0,1,-shear), Vector3.BACK)
	presentation.position.z = ground_height * shear * .45
	facing.rotation.y = -heading
	if p > 0.0 and assembly == null:
		assembly = Assembly.new()
		assembly.setup(centered)
		vehicle = assembly.car
	if assembly != null:
		assembly.set_progress(p)
	model_root.visible = p < 1.0
	if p >= 1.0:
		return
	for i in joints.size():
		joints[i].transform = rest[joints[i]]
		if skins[i] != null:
			skins[i].show()
			skins[i].scale = Vector3.ONE
	var stride := walk_weight * (1.0 - smoothstep(0.0,.43,p))
	var cycle := TAU * walk_phase
	var protect := guard * (1.0-smoothstep(.03,.23,p))
	var sink := (.020 + .010*cos(2.0*cycle)) * stride + .022*protect
	var sway := .016*sin(cycle)*stride
	pelvis.position += Vector3(0,-sink,sway)
	for i in 2:
		_leg(i, fposmod(walk_phase + 0.5 * i,1.0), stride,sink,sway)
	var aim_offset := angle_difference(heading,aim)
	trunk.rotation = Vector3(-.075*sin(cycle)*stride, -aim_offset*.74 + .045*sin(cycle)*stride, -.055*protect)
	for i in 2:
		_guard_arm(i, stride, cycle, protect)
	var elapsed := minf(fire_age, fire_duration)
	var sweep := .52 * sin(elapsed * 8.4) * smoothstep(0,.09,elapsed) * protect
	var nozzle_axis := muzzle.transform.basis.x.normalized()
	turret.rotation.y = -aim_offset*.26 - sweep + atan2(nozzle_axis.z,nozzle_axis.x) * protect
	if p > 0.0:
		_fold_joints(p)

func _leg(i: int, t: float, weight: float, sink: float, sway: float) -> void:
	var side := 1.0 if i == 0 else -1.0
	var step_length := STRIDE / length_factor * (_step_direction.x - side * _step_direction.y)
	var offset := step_length * (.5*STANCE - t)
	var lift := 0.0
	var toe := 0.0
	if t >= STANCE:
		var swing := (t-STANCE)/(1.0-STANCE)
		offset = step_length * STANCE * (smoothstep(0,1,swing)-.5)
		lift = .08 * pow(sin(PI*swing),1.22)
		toe = -.20 * sin(TAU*swing)
	var upper: Vector3 = (rest[knees[i]] as Transform3D).origin
	var lower: Vector3 = (rest[feet[i]] as Transform3D).origin
	var u := Vector2(upper.x,upper.y)
	var l := Vector2(lower.x,lower.y)
	var target := u+l+Vector2(weight*offset,weight*lift+sink)
	var distance := clampf(target.length(),absf(u.length()-l.length())+.0001,u.length()+l.length()-.0001)
	var bind_bend := u.angle_to(l)
	var bend := signf(bind_bend) * acos(clampf((distance*distance-u.length_squared()-l.length_squared())/(2*u.length()*l.length()),-1.0,1.0))
	var hip_pitch := target.angle()-atan2(l.length()*sin(bend),u.length()+l.length()*cos(bend))-u.angle()
	var knee_pitch := bend-bind_bend
	var hip_roll := -sway/minf(-.08,target.y)
	hips[i].basis = Basis(Vector3.RIGHT,hip_roll)*Basis(Vector3.BACK,hip_pitch)
	knees[i].rotation.z = knee_pitch
	feet[i].basis = Basis(Vector3.BACK,-hip_pitch-knee_pitch)*Basis(Vector3.RIGHT,-hip_roll)*Basis(Vector3.BACK,toe*weight)

func _guard_arm(i: int, stride: float, cycle: float, protect: float) -> void:
	var side := 1.0 if i == 0 else -1.0
	var shoulder := shoulders[i]
	shoulder.rotation = Vector3(0,side*1.04*protect,.13*protect+.12*sin(cycle+i*PI)*stride*(1.0-protect))
	if protect <= 0.0:
		return
	# Rotate the broad side plates across the chest. Solve against their geometry
	# centers so the unequal left/right shield shapes meet at the front.
	var orientation := Basis(Vector3.RIGHT, side * .39) * Basis(Vector3.UP, side * 1.21) * Basis(Vector3.BACK, .07)
	var guard_center := Vector3(.282 + .017 * i, .465, side * .114)
	var guard_pose := Transform3D(orientation, guard_center - orientation * shield_centers[i])
	var local_guard := shoulder.global_transform.affine_inverse() * trunk.global_transform * (bind[trunk] as Transform3D).affine_inverse() * guard_pose
	shields[i].transform = (rest[shields[i]] as Transform3D).interpolate_with(local_guard,protect)

func _fold_joints(progress: float) -> void:
	var raw_to_world := model_root.global_transform
	var to_raw := raw_to_world.affine_inverse()
	var source: Array[Transform3D] = []
	for joint in joints:
		source.append(to_raw * joint.global_transform)
	for i in joints.size():
		var joint := joints[i]
		var joint_name := String(joint.name)
		var arm := joint_name.begins_with("Shield") or joint_name.begins_with("Shoulder")
		var foot := joint_name.begins_with("Ankle")
		var tank := joint_name.begins_with("Tank")
		var gun := joint == turret
		var w := smoothstep(.03 if arm or foot else .09, .86 if tank or foot else .95, progress)
		var pose := source[i].interpolate_with(folded[joint], w)
		var arc := sin(PI*w)
		pose.origin.y += (.075 if arm else .038 if tank or gun else -.025) * arc
		if arm or tank:
			pose.origin.z += signf(source[i].origin.z)*.085*arc
		joint.global_transform = raw_to_world * pose
		var skin := skins[i]
		if skin == null:
			continue
		# The old outer plate turns edge-on and slides under the new fender. Each
		# group retracts on its own rail, while the real vehicle parts swing over it.
		var tuck := smoothstep(.54 if arm or gun else .42,.96 if arm or gun else .88,progress)
		skin.scale = Vector3.ONE.lerp(Vector3(.13,.18,.15) if not arm else Vector3(.36,.15,.12),tuck)
		skin.visible = tuck < 0.999

func muzzle_world(_side: int = 0) -> Vector3:
	return vehicle.muzzle_world() if is_vehicle() and vehicle != null else muzzle.global_position

func fire(reach: float, duration: float, shot_angle: float) -> void:
	if wreck_age >= 0.0:
		return
	aim = shot_angle
	if is_vehicle():
		vehicle.aim_nozzle(angle_difference(heading, shot_angle))
		vehicle.fire(reach, duration)
		return
	if vehicle_progress > .15:
		return
	shot_heading = shot_angle
	fire_age = 0.0
	fire_duration = maxf(.12,duration)
	shot_reach = maxf(.10,reach)
	_serial += 1
	if flame == null:
		_create_flame()
	flame.custom_aabb = AABB(Vector3(-shot_reach,-1,-shot_reach),Vector3(2*shot_reach,2,2*shot_reach))
	_flame_paint.set_shader_parameter("firing_time",fire_duration)
	_flame_paint.set_shader_parameter("reach",shot_reach)
	_flame_paint.set_shader_parameter("shot_seed",float(_serial)*.39)
	_pose()
	_update_flame()

func _create_flame() -> void:
	if _ribbon == null:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 24:
			var u0 := float(i)/24.0
			var u1 := float(i+1)/24.0
			for uv in [Vector2(u0,0),Vector2(u0,1),Vector2(u1,1),Vector2(u0,0),Vector2(u1,1),Vector2(u1,0)]:
				tool.set_uv(uv)
				tool.add_vertex(Vector3(uv.x,0.0,uv.y-.5))
		_ribbon = tool.commit()
	flame = MeshInstance3D.new()
	flame.mesh = _ribbon
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame_paint = ShaderMaterial.new()
	_flame_paint.shader = FlameShader
	flame.material_override = _flame_paint
	presentation.add_child(flame)

func _update_flame() -> void:
	if flame == null:
		return
	flame.visible = wreck_age < 0.0 and fire_age < fire_duration + AFTERBURN and vehicle_progress < .15
	if not flame.visible:
		return
	flame.position = presentation.to_local(muzzle.global_position)
	flame.rotation.y = -shot_heading
	var local_axis := flame.global_basis.inverse() * muzzle.global_basis.x
	_flame_paint.set_shader_parameter("elapsed",fire_age)
	_flame_paint.set_shader_parameter("nozzle_angle",atan2(local_axis.z,local_axis.x))
	_flame_paint.set_shader_parameter("nozzle_pitch",atan2(local_axis.y,Vector2(local_axis.x,local_axis.z).length()))

func destroy() -> void:
	if wreck_age >= 0.0:
		return
	wreck_age = 0.0
	if flame != null:
		flame.hide()
	if is_vehicle():
		vehicle.destroy()
		return
	wreck = FuelWreck.new()
	presentation.add_child(wreck)
	for tank in tanks:
		wreck.fuel_origins.append(wreck.to_local(tank.global_position))
	var roles: Dictionary = {}
	for i in joints.size():
		if skins[i] == null:
			continue
		var role := String(joints[i].name)
		if role.begins_with("Shield"):
			role = "Arm" + role
		elif role.begins_with("Tank"):
			role = "Pod" + role
		roles[skins[i]] = role
	if vehicle != null and vehicle.visible:
		for panel in assembly.panels:
			roles[panel] = "Car" + String(panel.name)
	wreck.begin(facing,roles,ground_height)

func is_finished() -> bool:
	if wreck_age < 0.0:
		return false
	return wreck_age >= FuelWreck.WRECK_DURATION if wreck != null else vehicle.is_finished()
