extends Node3D
## Ground vehicle presentation. Actor X/Z is map X/Y; one local unit is one hull length.
const ORIGINAL_MODEL := "res://assets/models/hellbat/hellbat.glb"
const HULL_TURN_RATE := 3.50
const TURRET_TURN_RATE := 7.50
const WRECK_DURATION := 1.48
const FLAME_AFTERGLOW := 0.11
const WHEEL_RADII := [0.107, 0.107, 0.134, 0.134]
const WHEEL_NAMES := ["WheelFrontLeft", "WheelFrontRight", "WheelRearLeft", "WheelRearRight"]
# Asset-local coordinates measured at the barrel outlet and the rear fuel compartment.
const BARREL_TIP := Vector3(0.056, 0.583, 0.0)
const TANK_CAP := Vector3(-0.26, 0.39, 0.15)

static var original_paint: Material
static var burnt_paint: Material
static var plume_shader: Shader
static var jet_mesh: ArrayMesh
static var puff_mesh: QuadMesh
static var puff_paints: Dictionary = {}
var heading := 0.0
var turret_heading := 0.0
var wheel_phase := 0.0
var shot_age := 999.0
var wreck_age := -1.0
var drive_speed := 0.0
var shot_length := 0.0
var shot_duration := 0.33
var shot_serial := 0
var length_factor := 1.0
var turn_lean := 0.0
var driving := Node3D.new()
var suspension := Node3D.new()
var centered := Node3D.new()
var model_root: Node3D
var wheels: Array[Node3D] = []
var turret: Node3D
var socket := Node3D.new()
var tank_socket := Node3D.new()
var meshes: Array[MeshInstance3D] = []
var flame: MeshInstance3D
var fire_material: ShaderMaterial
var rupture: Array[MeshInstance3D] = []
var plumes: Array[MeshInstance3D] = []
var embers: Array[MeshInstance3D] = []
var darkened := false

func setup(model: PackedScene, bounds: AABB, initial_heading: float) -> void:
	heading = initial_heading
	turret_heading = initial_heading
	length_factor = 1.0 / maxf(maxf(bounds.size.x, bounds.size.z), 0.001)
	add_child(driving)
	driving.add_child(suspension)
	suspension.add_child(centered)
	centered.scale = Vector3.ONE * length_factor
	centered.position = -bounds.get_center() * length_factor
	model_root = model.instantiate() as Node3D
	centered.add_child(model_root)
	_load_paints()
	for child in model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		meshes.append(mesh_node)
		mesh_node.material_override = original_paint
	turret = model_root.find_child("Turret", true, false) as Node3D
	for node_name in WHEEL_NAMES:
		wheels.append(model_root.find_child(node_name, true, false) as Node3D)
	if turret != null:
		turret.add_child(socket)
		socket.position = turret.to_local(model_root.to_global(BARREL_TIP))
	else:
		model_root.add_child(socket)
		socket.position = BARREL_TIP
	model_root.add_child(tank_socket)
	tank_socket.position = TANK_CAP
	_update_vehicle()

static func _load_paints() -> void:
	if original_paint != null:
		return
	var source := load(ORIGINAL_MODEL) as PackedScene
	if source == null:
		return
	var probe := source.instantiate()
	var parts := probe.find_children("*", "MeshInstance3D", true, false)
	if probe is MeshInstance3D:
		parts.push_front(probe)
	for part in parts:
		if part.mesh != null and part.mesh.get_surface_count() > 0:
			original_paint = part.get_active_material(0)
			if original_paint != null:
				break
	probe.free()
	if original_paint is StandardMaterial3D:
		var soot := original_paint.duplicate() as StandardMaterial3D
		soot.albedo_color = Color(0.30, 0.255, 0.22)
		soot.roughness = 0.94
		soot.metallic = 0.25
		burnt_paint = soot
	else:
		burnt_paint = original_paint

func muzzle_world() -> Vector3:
	return socket.global_position

func muzzle_screen_offset() -> Vector2:
	var local := to_local(muzzle_world())
	return Vector2(local.x, local.z)

func aim_nozzle(launch_heading: float) -> Vector2:
	turret_heading = launch_heading
	_update_vehicle()
	return muzzle_screen_offset()

func advance(delta: float, desired_heading: float, move_distance: float, aim_heading: float = NAN, target_offset: Vector2 = Vector2.INF) -> void:
	var dt := maxf(0.0, delta)
	if wreck_age >= 0.0:
		wreck_age += dt
		_update_wreck()
		return
	if dt > 0.0:
		var previous := heading
		heading = rotate_toward(heading, desired_heading, dt * HULL_TURN_RATE)
		var turning := angle_difference(previous, heading)
		turn_lean = lerpf(turn_lean, clampf(-turning / dt * 0.027, -0.10, 0.10), 1.0 - exp(-dt * 9.0))
		drive_speed = lerpf(drive_speed, absf(move_distance) / dt, 1.0 - exp(-dt * 12.0))
		wheel_phase = wrapf(wheel_phase - move_distance / (float(WHEEL_RADII[0]) * length_factor), -PI, PI)
		for i in wheels.size():
			var wheel := wheels[i]
			if wheel == null:
				continue
			# The inside and outside tyres cover different distances during a turn.
			var travel := move_distance - turning * wheel.position.z * length_factor
			wheel.rotation.z = wrapf(wheel.rotation.z - travel / (float(WHEEL_RADII[i]) * length_factor), -PI, PI)
		shot_age += dt
	_update_vehicle(dt, aim_heading, target_offset)
	_update_flame()

func _update_vehicle(dt := 0.0, aim_heading := NAN, target_offset := Vector2.INF) -> void:
	driving.rotation.y = -heading
	var engine := minf(drive_speed * 0.35, 1.0)
	suspension.position.y = engine * sin(wheel_phase * 2.0) * 0.006
	suspension.rotation = Vector3(0.11 + turn_lean, 0.0, -0.085 + engine * sin(wheel_phase * 2.0) * 0.011)
	if turret != null:
		if target_offset.is_finite():
			# The gun rotates about a rear-mounted axis. Use the point on that axis at
			# nozzle height so body lean and a close target both affect the bearing.
			var pivot := to_local(turret.to_global(Vector3.UP * socket.position.y))
			var towards := target_offset - Vector2(pivot.x, pivot.z)
			if towards.length_squared() > 0.000001:
				aim_heading = towards.angle()
		if dt > 0.0 and not is_nan(aim_heading):
			turret_heading = rotate_toward(turret_heading, aim_heading, dt * TURRET_TURN_RATE)
		# Solve azimuth in the tilted hull's local plane so its projection stays on target.
		var flat := Vector2(cos(turret_heading - heading), sin(turret_heading - heading))
		var axis := suspension.transform.basis
		var local_x := flat.x * axis.z.z - flat.y * axis.z.x
		var local_z := flat.y * axis.x.x - flat.x * axis.x.z
		turret.rotation.y = -atan2(local_z, local_x)

func fire(reach: float, duration: float) -> void:
	if wreck_age >= 0.0:
		return
	shot_length = maxf(0.03, reach)
	shot_duration = maxf(duration, 0.04)
	shot_age = 0.0
	shot_serial += 1
	if flame == null:
		_prepare_flame()
	_update_flame()

func _prepare_flame() -> void:
	if jet_mesh == null:
		jet_mesh = ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		# A single ribbon rolls about the gun axis to face the camera. Crossing translucent
		# cards leave a stippled seam in the hottest part of the jet on Compatibility.
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
			Vector3(0,0,-0.5), Vector3(1,0,-0.5), Vector3(1,0,0.5), Vector3(0,0,0.5)
		])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3])
		jet_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		plume_shader = Shader.new()
		plume_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float flow;
uniform float front;
uniform float tail;
uniform float energy;
float hash(vec2 p) {
	vec3 v = fract(vec3(p.xyx) * 0.1031);
	v += dot(v, v.yzx + 33.33);
	return fract((v.x + v.y) * v.z);
}
float noise2(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.0),f.x),f.y);
}
void vertex() {
	vec3 eye_local = inverse(mat3(MODEL_MATRIX)) * INV_VIEW_MATRIX[2].xyz;
	vec2 span = vec2(-eye_local.z, eye_local.y);
	if (dot(span,span) < 0.000001) { span = vec2(0.0,1.0); }
	VERTEX.yz = normalize(span) * VERTEX.z;
}
void fragment() {
	float u = UV.x, v = UV.y * 2.0 - 1.0;
	vec2 advect = vec2(u*6.0-flow*8.0,v*2.4);
	float billow = noise2(advect)*0.58 + noise2(advect*2.07+5.4)*0.28 + noise2(advect*4.13+1.6)*0.14;
	float braid = (sin(u*20.0-flow*14.0)*0.08 + sin(u*11.0-flow*9.0)*0.08) * u;
	float spread = (0.055 + pow(u,0.73) * (0.52+0.49*billow)) * (1.0-smoothstep(front-0.10,front+0.07,u)*0.68);
	float charge = spread-abs(v-braid) + (billow-0.5)*0.42*u;
	float edge = smoothstep(-0.07,0.05,charge);
	float tip = 1.0-smoothstep(front-0.08,front+0.015,u+(0.5-billow)*0.10*u);
	float back = smoothstep(tail-0.06,tail+0.012,u);
	float hot = clamp(charge/max(spread,0.04)+0.95*(billow-0.55)-u*0.42,0.0,1.0);
	vec3 color = mix(vec3(0.79,0.12,0.018),vec3(1.0,0.47,0.035),smoothstep(0.04,0.45,hot));
	color = mix(color,vec3(1.0,0.94,0.61),smoothstep(0.46,0.89,hot));
	color = mix(color,vec3(0.61,0.82,1.0),0.85*(1.0-smoothstep(0.012,0.10,u))*hot);
	ALBEDO = color;
	ALPHA = edge * tip * back * energy * (0.76+hot*0.24);
}
"""
	fire_material = ShaderMaterial.new()
	fire_material.shader = plume_shader
	flame = MeshInstance3D.new()
	flame.mesh = jet_mesh
	flame.material_override = fire_material
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)

func _update_flame() -> void:
	if flame == null:
		return
	flame.visible = wreck_age < 0.0 and shot_age < shot_duration + FLAME_AFTERGLOW
	if not flame.visible:
		return
	flame.position = to_local(muzzle_world())
	flame.rotation.y = -turret_heading
	var width := clampf(shot_length * 0.23, 0.24, 0.98)
	flame.scale = Vector3(shot_length, width, width)
	fire_material.set_shader_parameter("flow", shot_age + 0.53 * shot_serial)
	fire_material.set_shader_parameter("front", minf(1.0, 0.035 + shot_age / shot_duration))
	fire_material.set_shader_parameter("tail", clampf((shot_age - shot_duration + 0.015) / FLAME_AFTERGLOW, 0.0, 1.0))
	fire_material.set_shader_parameter("energy", 1.0 - 0.65 * smoothstep(shot_duration, shot_duration + FLAME_AFTERGLOW, shot_age))

func destroy() -> void:
	if wreck_age >= 0.0:
		return
	wreck_age = 0.0
	if flame != null:
		flame.hide()
	# Flames vent from the fuel compartment. The chassis and tyres stay on the ground.
	for i in 2:
		rupture.append(_puff("flare"))
	for i in 3:
		plumes.append(_puff("soot"))
	for i in 5:
		embers.append(_puff("cinder"))
	_update_wreck()

func is_finished() -> bool:
	return wreck_age >= WRECK_DURATION

func _update_wreck() -> void:
	var t := wreck_age
	var shock := sin(clampf((t - 0.075) / 0.36, 0.0, 1.0) * PI) * exp(-maxf(0.0, t - 0.075) * 3.5)
	suspension.position = Vector3(-0.015 * shock, 0.042 * shock - smoothstep(0.38, 0.68, t) * 0.018, 0.0)
	suspension.rotation.x = 0.11 + turn_lean - shock * 0.21 - smoothstep(0.36, 0.67, t) * 0.045
	suspension.rotation.z = -0.085 + shock * 0.17
	if not darkened and t >= 0.19:
		for mesh in meshes:
			mesh.material_override = burnt_paint
		darkened = true
	var tank := to_local(tank_socket.global_position)
	var along := Vector3(cos(heading), 0, sin(heading))
	var side := Vector3(-sin(heading), 0, cos(heading))
	for i in rupture.size():
		var local_time := t - 0.085 * i
		var raw := clampf(local_time / (0.23 + 0.08 * i), 0.0, 1.0)
		var node := rupture[i]
		node.visible = local_time >= 0.0 and raw < 1.0
		if node.visible:
			node.position = tank - along * 0.045 * i + Vector3.UP * (0.07 + raw * 0.14) + side * (i * 0.07)
			var diameter := (0.12 + 0.28 * sin(raw * PI)) * (1.0 - smoothstep(0.62, 1.0, raw))
			node.scale = Vector3.ONE * maxf(0.002, diameter)
	for i in plumes.size():
		var born := 0.11 + i * 0.11
		var p := clampf((t - born) / (0.76 + i * 0.10), 0.0, 1.0)
		var plume := plumes[i]
		plume.visible = p > 0.0 and p < 1.0
		if plume.visible:
			plume.position = tank - along * (0.04 * i + 0.15 * p) + side * (0.052 * sin(i * 3.1 + p * 4.0)) + Vector3.UP * (0.14 + 0.31 * p)
			var diameter := (0.10 + 0.24 * sin(p * PI * 0.64)) * (1.0 - smoothstep(0.72, 1.0, p))
			plume.scale = Vector3.ONE * maxf(0.002, diameter)
	for i in embers.size():
		var e := clampf((t - 0.068 - 0.019 * i) / 0.32, 0.0, 1.0)
		var ember := embers[i]
		ember.visible = e > 0.0 and e < 1.0
		if ember.visible:
			var angle := 2.4 * i + 0.31
			ember.position = tank + (along * cos(angle) + side * sin(angle)) * (0.12 + 0.19 * e) + Vector3.UP * (0.11 + 0.19 * sin(e * PI))
			ember.scale = Vector3.ONE * (0.047 * (1.0 - e))

func _puff(kind: String) -> MeshInstance3D:
	if puff_mesh == null:
		puff_mesh = QuadMesh.new()
		puff_mesh.size = Vector2.ONE
	if not puff_paints.has(kind):
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.28, 0.62, 1.0])
		match kind:
			"flare":
				gradient.colors = PackedColorArray([Color("fff7c9"), Color("ffd46a"), Color("ff671cba"), Color("a5250600")])
			"soot":
				gradient.colors = PackedColorArray([Color("4a3e3ace"), Color("574a41bd"), Color("574f4b93"), Color("71675f00")])
			"cinder":
				gradient.colors = PackedColorArray([Color("ffedbd"), Color("ffc86c"), Color("f88340cc"), Color("bf351400")])
		var texture := GradientTexture2D.new()
		texture.width = 32
		texture.height = 32
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1, 0.5)
		texture.gradient = gradient
		var paint := StandardMaterial3D.new()
		paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		paint.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		paint.billboard_keep_scale = true
		paint.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if kind == "soot" else BaseMaterial3D.BLEND_MODE_ADD
		paint.albedo_texture = texture
		puff_paints[kind] = paint
	var node := MeshInstance3D.new()
	node.mesh = puff_mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.material_override = puff_paints[kind]
	add_child(node)
	return node
