extends Node3D
## Analytic destruction of the active pose. The actor supplies elapsed time, including pause.

const WRECK_DURATION := 2.90
const FADE_START := 2.23
const CORE_FLASH := 0.11
const ARM_RELEASE := 0.18
const POD_RELEASE := 0.24
const BODY_RELEASE := 0.31

enum Effect { FLASH, SOOT, SPARK, SHADOW }

class Piece:
	var pivot: Node3D
	var meshes: Array[MeshInstance3D] = []
	var bounds: AABB
	var release: float
	var flight: float
	var rollout: float
	var hop: float
	var roll: float
	var yaw: float
	var axis: Vector3
	var start: Vector3
	var landing: Vector3
	var rest: Vector3
	var scorched := false
	var settled := false

	func rotation_at(progress: float) -> Basis:
		return Basis(Vector3.UP, yaw * progress) * Basis(axis, roll * progress)

class Burst:
	var kind: Effect
	var origin: Vector3
	var drift: Vector3
	var birth: float
	var life: float
	var diameter: float
	var angle: float
	var paint: Color

static var _metal_shader: Shader
static var _burst_paint: ShaderMaterial
static var _burst_quad: QuadMesh
static var _contact_points: Dictionary = {}

var _parts: Array[Piece] = []
var _bursts: Array[Burst] = []
var _paint_cache: Dictionary = {}
var _batch: MultiMesh
var _floor := 0.0
var _forward := Vector3.RIGHT
var _side := Vector3.BACK
var _started := false
var _last_age := -1.0

func begin(model_root: Node3D, roles: Dictionary, ground_height: float) -> void:
	if _started:
		return
	_started = true
	_floor = ground_height
	var to_wreck := global_transform.affine_inverse()
	var forward := (to_wreck * model_root.global_transform).basis.x
	var flat_forward := Vector3(forward.x, 0, forward.z)
	if flat_forward.length_squared() > 0.000001:
		_forward = flat_forward.normalized()
		_side = _forward.cross(Vector3.UP)

	# Group both visible geometry and related fasteners about a common pivot.
	# Reparent the original renderers so the dying rig never overlaps an intact copy.
	var groups: Dictionary = {}
	var full_bounds := AABB()
	var first := true
	for key in roles:
		var mesh_node := key as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null or not mesh_node.is_visible_in_tree():
			continue
		var role := String(roles[key])
		var bounds := (to_wreck * mesh_node.global_transform) * mesh_node.get_aabb()
		if not groups.has(role):
			var group := Piece.new()
			group.bounds = bounds
			groups[role] = group
		var target: Piece = groups[role]
		target.bounds = target.bounds.merge(bounds)
		target.meshes.append(mesh_node)
		full_bounds = bounds if first else full_bounds.merge(bounds)
		first = false

	var center := full_bounds.get_center()
	if groups.has("Trunk"):
		center = groups["Trunk"].bounds.get_center()
	elif groups.has("Chest"):
		center = groups["Chest"].bounds.get_center()
	_emit_core(center)
	# Iterate the groups in name order so the timing and effects are repeatable.
	var ordered := groups.keys()
	ordered.sort()
	for role in ordered:
		var part: Piece = groups[role]
		_attach_piece(part, role, center)

	model_root.hide()
	_prepare_effects()
	seek(0.0)

func seek(age: float) -> void:
	if not _started or age == _last_age:
		return
	_last_age = age
	visible = age < WRECK_DURATION
	if not visible:
		return
	var fade := 1.0 - smoothstep(FADE_START, WRECK_DURATION, age)
	for part in _parts:
		_place_piece(part, age)
	if age >= FADE_START:
		for paint in _paint_cache.values():
			paint.set_shader_parameter("coverage", fade)
	_place_effects(age, fade)

func _attach_piece(part: Piece, role: String, core: Vector3) -> void:
	part.pivot = Node3D.new()
	part.pivot.name = StringName(role + "Fragment")
	add_child(part.pivot)
	part.start = part.bounds.get_center()
	part.pivot.position = part.start
	for mesh_node in part.meshes:
		mesh_node.reparent(part.pivot, true)

	var radial := part.start - core
	radial.y = 0.0
	var side := 1.0 if radial.dot(_side) >= 0.0 else -1.0
	var direction := (radial + _side * side * 0.05).normalized()
	var spread := 0.30
	var arm := role.begins_with("Shoulder") or role.begins_with("Arm")
	var pod := role.begins_with("Cannon") or role.begins_with("Pod")
	var leg := role.begins_with("Hip") or role.begins_with("Knee") or role.begins_with("Ankle")
	if arm:
		part.release = ARM_RELEASE + (0.045 if side < 0.0 else 0.0)
		part.flight = 0.48
		part.rollout = 0.48
		part.hop = 0.13
		part.roll = 2.73
		part.yaw = -side * 0.46
		direction = (_side * side + _forward * 0.25).normalized()
		spread = 0.54
	elif pod:
		var outer := role.contains("Outer")
		part.release = POD_RELEASE + (0.045 if side < 0.0 else 0.0) + (0.035 if outer else 0.0)
		part.flight = 0.48 if outer else 0.42
		part.rollout = 0.35
		part.hop = 0.22 if outer else 0.17
		part.roll = 3.75 if outer else 2.87
		part.yaw = side * (0.72 if outer else -0.43)
		direction = (_side * side * (1.0 if outer else 0.45) - _forward * (0.62 if outer else 1.0)).normalized()
		spread = 0.58 if outer else 0.48
	elif leg:
		var upper := role.begins_with("Hip")
		var foot := role.begins_with("Ankle")
		part.release = BODY_RELEASE + (0.015 if upper else 0.055 if foot else 0.035)
		part.flight = 0.33 if upper else 0.27
		part.rollout = 0.42
		part.hop = 0.062 if upper else 0.045
		part.roll = 1.89 if upper else 1.42 if foot else 2.07
		part.yaw = side * 0.34
		direction = (_side * side * (0.80 if foot else 1.0) + _forward * (0.27 if upper else 0.73 if foot else -0.27)).normalized()
		spread = 0.28 if upper else 0.38 if foot else 0.34
	else:
		var trunk := role == "Trunk" or role == "Chest"
		part.release = BODY_RELEASE + (0.035 if trunk else 0.015)
		part.flight = 0.40 if trunk else 0.34
		part.rollout = 0.45
		part.hop = 0.035 if trunk else 0.075
		part.roll = 1.42 if trunk else 2.0
		part.yaw = 0.23 if trunk else -0.55
		direction = (-_forward + _side * (0.31 if trunk else -0.52)).normalized()
		spread = 0.21 if trunk else 0.30

	part.axis = Vector3.UP.cross(direction).normalized()
	part.landing = part.start + direction * spread * 0.79
	part.rest = part.start + direction * spread
	part.landing.y = _floor - _low_vertex(part, part.rotation_at(0.80))
	part.rest.y = _floor - _low_vertex(part, part.rotation_at(1.0))
	_parts.append(part)

	if arm or pod:
		var diameter := 0.41 if arm else 0.28
		_add_burst(Effect.FLASH, part.start, direction * 0.11, part.release - 0.034, 0.29, diameter, 0.71 * side, Color("ff9b37"))
		_add_burst(Effect.SPARK, part.start, direction * 0.51, part.release, 0.31, 0.075, atan2(direction.x, direction.z), Color("ffb55a"))

static func _vertices(mesh: Mesh) -> PackedVector3Array:
	# Packed scenes share the same fixed rig meshes across all actors and deaths.
	if not _contact_points.has(mesh):
		var points := PackedVector3Array()
		for index in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(index)
			if not arrays.is_empty() and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
				points.append_array(arrays[Mesh.ARRAY_VERTEX])
		_contact_points[mesh] = points
	return _contact_points[mesh]

func _low_vertex(part: Piece, orientation: Basis) -> float:
	# Use the real hull rather than rotating oversized bounds, which would leave
	# the broad weapon boxes hovering after their first impact or final settlement.
	var lowest := INF
	var up := orientation.transposed().y
	for node in part.meshes:
		var transform := node.transform
		var local_up := transform.basis.transposed() * up
		var offset := up.dot(transform.origin)
		var vertices := _vertices(node.mesh)
		if vertices.is_empty():
			var local_bounds := node.get_aabb()
			var corner := local_up.dot(local_bounds.get_center()) - local_up.abs().dot(local_bounds.size * 0.5)
			lowest = minf(lowest, corner + offset)
			continue
		for vertex in vertices:
			lowest = minf(lowest, local_up.dot(vertex) + offset)
	return 0.0 if is_inf(lowest) else lowest

func _locked_shift(age: float) -> Vector3:
	var strike := sin(age * 59.0) * smoothstep(0.01, 0.035, age)
	var jolt := _side * strike * 0.014 + _forward * strike * 0.009
	return jolt - Vector3.UP * smoothstep(0.09, BODY_RELEASE, age) * 0.035

func _place_piece(part: Piece, age: float) -> void:
	if part.settled:
		return
	var elapsed := age - part.release
	if elapsed < 0.0:
		part.pivot.position = part.start + _locked_shift(age)
		return
	if not part.scorched:
		_scorch(part)
	var start := part.start + _locked_shift(part.release)
	var flight := clampf(elapsed / part.flight, 0.0, 1.0)
	var position := start.lerp(part.landing, flight)
	var roll := 0.80 * flight
	if flight < 1.0:
		position.y += 4.0 * part.hop * flight * (1.0 - flight)
	else:
		var settling := clampf((elapsed - part.flight) / part.rollout, 0.0, 1.0)
		part.settled = settling >= 1.0
		var ease_out := 1.0 - pow(1.0 - settling, 2.0)
		var rebound := clampf(settling / 0.60, 0.0, 1.0)
		position = part.landing.lerp(part.rest, ease_out)
		position.y += 0.12 * part.hop * 4.0 * rebound * (1.0 - rebound)
		roll += 0.20 * ease_out
	part.pivot.transform = Transform3D(part.rotation_at(roll), position)

func _scorch(part: Piece) -> void:
	part.scorched = true
	for node in part.meshes:
		var active: Array[Material] = []
		for surface in node.mesh.get_surface_count():
			active.append(node.get_active_material(surface))
		node.material_override = null
		for surface in active.size():
			if not _paint_cache.has(active[surface]):
				_paint_cache[active[surface]] = _wreck_paint(active[surface] as StandardMaterial3D)
			node.set_surface_override_material(surface, _paint_cache[active[surface]])

static func _wreck_paint(source: StandardMaterial3D) -> ShaderMaterial:
	if _metal_shader == null:
		_metal_shader = Shader.new()
		_metal_shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D color_map : source_color, hint_default_white, filter_linear_mipmap;
uniform vec4 paint : source_color = vec4(0.52, 0.48, 0.45, 1.0);
uniform float metal = 0.35;
uniform float coverage = 1.0;
void fragment() {
	vec2 pixel = floor(FRAGCOORD.xy);
	float threshold = fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
	if (coverage <= threshold) { discard; }
	float soot = 0.87 + 0.13 * sin(dot(VERTEX, vec3(29.0, 17.0, 15.0)));
	ALBEDO = texture(color_map, UV).rgb * paint.rgb * soot;
	ROUGHNESS = 0.91;
	METALLIC = metal;
}
"""
	var paint := ShaderMaterial.new()
	paint.shader = _metal_shader
	if source != null:
		paint.set_shader_parameter("paint", source.albedo_color * Color(0.72, 0.65, 0.60))
		paint.set_shader_parameter("color_map", source.albedo_texture)
		paint.set_shader_parameter("metal", source.metallic * 0.65)
	return paint

func _emit_core(center: Vector3) -> void:
	var origin := center + Vector3.UP * 0.16
	_add_burst(Effect.FLASH, origin, Vector3.ZERO, 0.0, 0.14, 0.61, 0.41, Color("70ccff"))
	_add_burst(Effect.FLASH, origin + Vector3.UP * 0.015, -_forward * 0.06, CORE_FLASH, 0.32, 0.84, -0.28, Color("ff962e"))
	_add_burst(Effect.FLASH, origin - _forward * 0.12, _side * 0.08, BODY_RELEASE, 0.32, 0.68, 0.24, Color("f26c28"))
	for i in 7:
		var angle := 2.399963 * float(i)
		var drift := Vector3(sin(angle), 0, cos(angle)) * (0.35 + 0.037 * i)
		_add_burst(Effect.SPARK, origin, drift, CORE_FLASH + 0.013 * i, 0.42, 0.094, angle, Color("ffb462"))
	for i in 4:
		var drift := -_forward * (0.24 + 0.045 * i) + _side * sin(i * 2.65) * 0.20
		_add_burst(Effect.SOOT, origin + Vector3.UP * (0.02 * i), drift, 0.22 + 0.09 * i, 1.22 + 0.10 * i, 0.67 + 0.035 * i, 0.43 * i, Color("574c44a3"))

func _add_burst(kind: Effect, origin: Vector3, drift: Vector3, birth: float, life: float, diameter: float, angle: float, paint: Color) -> void:
	var burst := Burst.new()
	burst.kind = kind
	burst.origin = origin
	burst.drift = drift
	burst.birth = birth
	burst.life = life
	burst.diameter = diameter
	burst.angle = angle
	burst.paint = paint
	_bursts.append(burst)

func _prepare_effects() -> void:
	if _burst_quad == null:
		_burst_quad = QuadMesh.new()
		_burst_quad.size = Vector2.ONE
		_burst_paint = ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
varying vec4 tint;
varying float kind;
void vertex() {
	tint = COLOR;
	kind = INSTANCE_CUSTOM.x;
}
void fragment() {
	vec2 point = UV * 2.0 - 1.0;
	vec2 edge = abs(point);
	float r = length(point);
	float opacity;
	vec3 paint = tint.rgb;
	if (kind < 0.15) {
		float star = max(exp(-edge.x * 15.0), exp(-edge.y * 15.0));
		opacity = max(1.0 - smoothstep(0.15, 0.94, r), star * (1.0 - smoothstep(0.25, 0.98, r)));
		paint = mix(tint.rgb, vec3(1.0, 0.95, 0.80), 1.0 - smoothstep(0.05, 0.58, r));
	} else if (kind < 0.48) {
		float ripples = sin(point.x * 17.0 + point.y * 6.0) * sin(point.y * 13.0 - point.x * 7.0);
		opacity = (1.0 - smoothstep(0.09, 0.96, r + 0.105 * ripples)) * (0.72 + 0.19 * ripples);
	} else if (kind < 0.80) {
		opacity = (1.0 - smoothstep(0.08, 0.66, edge.x)) * smoothstep(-0.80, 0.51, point.y) * (1.0 - smoothstep(0.61, 0.96, point.y));
		paint = mix(tint.rgb, vec3(1.0, 0.92, 0.70), 0.7 * smoothstep(0.15, 0.8, point.y));
	} else {
		opacity = 1.0 - smoothstep(0.12, 1.0, r);
	}
	ALBEDO = paint;
	ALPHA = opacity * tint.a;
}
"""
		_burst_paint.shader = shader
	_batch = MultiMesh.new()
	_batch.transform_format = MultiMesh.TRANSFORM_3D
	_batch.use_colors = true
	_batch.use_custom_data = true
	_batch.mesh = _burst_quad
	_batch.instance_count = _parts.size() + _bursts.size()
	_batch.custom_aabb = AABB(Vector3(-1.6, -1.0, -1.6), Vector3(3.2, 2.6, 3.2))
	for i in _parts.size():
		_batch.set_instance_custom_data(i, Color(1.0, 0, 0))
	for i in _bursts.size():
		_batch.set_instance_custom_data(_parts.size() + i, Color(float(_bursts[i].kind) / 3.0, 0, 0))
	var rendered := MultiMeshInstance3D.new()
	rendered.multimesh = _batch
	rendered.material_override = _burst_paint
	rendered.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rendered)

func _place_effects(age: float, fade: float) -> void:
	for i in _parts.size():
		var part := _parts[i]
		var center := part.pivot.position
		var lift := clampf(center.y - _floor, 0.0, 0.62)
		var diameter := clampf(maxf(part.bounds.size.x, part.bounds.size.z) * 1.25, 0.11, 0.47)
		var ground := Vector3(center.x, _floor + 0.012, center.z) + _side * lift * 0.22 - _forward * lift * 0.19
		var paint := Color(0.025, 0.021, 0.019, fade * (0.36 - 0.2 * lift))
		_set_card(i, ground, diameter * (1.0 + 0.58 * lift), diameter * 0.74, 0, paint)

	for i in _bursts.size():
		var burst := _bursts[i]
		var progress := (age - burst.birth) / burst.life
		var index := i + _parts.size()
		if progress < 0.0 or progress >= 1.0:
			_batch.set_instance_color(index, Color.TRANSPARENT)
			continue
		var center := burst.origin + burst.drift * progress
		var spread := burst.diameter
		var paint := burst.paint
		var length_scale := 1.0
		match burst.kind:
			Effect.FLASH:
				center.y += 0.15 * progress
				spread *= lerpf(0.24, 1.0, smoothstep(0.0, 0.30, progress))
				paint.a *= 1.0 - smoothstep(0.16, 1.0, progress)
			Effect.SOOT:
				center.y += 0.37 * progress
				spread *= lerpf(0.23, 1.0, pow(progress, 0.63))
				paint.a *= smoothstep(0.0, 0.17, progress) * (1.0 - smoothstep(0.38, 1.0, progress))
			Effect.SPARK:
				center.y += 0.26 * sin(progress * PI)
				spread *= lerpf(0.45, 0.18, progress)
				length_scale = 6.0
				paint.a *= 1.0 - smoothstep(0.33, 1.0, progress)
		_set_card(index, center, spread, spread * length_scale, burst.angle, paint)

func _set_card(index: int, center: Vector3, width: float, length: float, angle: float, paint: Color) -> void:
	var basis := Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, -PI / 2.0)
	_batch.set_instance_transform(index, Transform3D(basis.scaled_local(Vector3(width, length, 1.0)), center))
	_batch.set_instance_color(index, paint)
