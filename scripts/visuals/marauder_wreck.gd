extends "res://scripts/visuals/thor_wreck.gd"
## Reuse pose-preserving rigid pieces and floor contact, with a shorter rear-led rupture.

var _reactor_origin := Vector3.INF

func begin_at_reactor(model_root: Node3D, roles: Dictionary, ground_level: float, reactor_world: Vector3) -> void:
	if reactor_world.is_finite():
		_reactor_origin = to_local(reactor_world)
	begin(model_root, roles, ground_level)

func _locked_shift(age: float) -> Vector3:
	# The first rear pressure wave kicks the intact body forward before it opens up.
	var push := smoothstep(0.10, 0.20, age) * 0.069
	return super._locked_shift(age) + _forward * push

func _attach_piece(part: Piece, role: String, core: Vector3) -> void:
	part.pivot = Node3D.new()
	part.pivot.name = StringName(role + "Fragment")
	add_child(part.pivot)
	part.start = part.bounds.get_center()
	part.pivot.position = part.start
	for mesh_node in part.meshes:
		mesh_node.reparent(part.pivot, true)

	# A rear reactor, two lateral weapon groups, a forward boot pair and the
	# heavy torso all settle apart. Keep destination spacing consistent even
	# when the live pose is twisted, mid-stride or recoiling at destruction.
	var side := -1.0 if role.ends_with("N") else 1.0
	var stagger := 0.026 if side < 0.0 else 0.0
	var destination := Vector2(0.24, -0.19)
	part.release = 0.32
	part.flight = 0.38
	part.rollout = 0.45
	part.hop = 0.079
	part.roll = 2.42
	part.yaw = 0.58
	if role == "Reactor":
		destination = Vector2(-0.98, -0.11)
		part.release = 0.166
		part.flight = 0.49
		part.rollout = 0.58
		part.hop = 0.25
		part.roll = 4.12
		part.yaw = -0.81
	elif role.begins_with("Launcher") or role.begins_with("Shoulder"):
		var launcher := role.begins_with("Launcher")
		if launcher:
			destination = Vector2(-0.11 + side * 0.27, 0.99 * side)
		else:
			destination = Vector2(-0.37 + side * 0.24, 0.76 * side)
		part.release = (0.214 if launcher else 0.239) + stagger
		part.flight = 0.44 if launcher else 0.49
		part.rollout = 0.58 if launcher else 0.39
		part.hop = 0.20 if launcher else 0.15
		part.roll = 4.45 if launcher else 2.53
		part.yaw = side * (0.92 if launcher else 0.46)
	elif role.begins_with("Ankle"):
		destination = Vector2(0.91 + 0.15 * side, 0.40 * side)
		part.release = 0.29 + stagger
		part.flight = 0.38
		part.rollout = 0.49
		part.hop = 0.114
		part.roll = 3.06
		part.yaw = -side * 0.52
	elif role.begins_with("Knee") or role.begins_with("Hip"):
		var shin := role.begins_with("Knee")
		destination = Vector2(0.62 if shin else 0.39, (0.58 if shin else 0.43) * side)
		part.release = (0.31 if shin else 0.335) + stagger
		part.flight = 0.34 if shin else 0.39
		part.hop = 0.086 if shin else 0.074
		part.roll = 2.65 if shin else 1.87
		part.yaw = side * 0.63
	elif role == "Helmet":
		destination = Vector2(0.10, 0.57)
		part.release = 0.276
		part.flight = 0.43
		part.hop = 0.23
		part.roll = 3.59
		part.yaw = -0.69
	elif role == "Trunk":
		destination = Vector2(-0.08, 0.06)
		part.release = 0.32
		part.flight = 0.39
		part.rollout = 0.48
		part.hop = 0.047
		part.roll = 1.70
		part.yaw = -0.26

	part.rest = core + _forward * destination.x + _side * destination.y
	part.landing = part.start.lerp(part.rest, 0.75)
	var heading := part.rest - part.start
	heading.y = 0.0
	if heading.length_squared() < 0.000001:
		heading = _forward
	part.axis = Vector3.UP.cross(heading).normalized()
	part.landing.y = _floor - _low_vertex(part, part.rotation_at(0.80))
	part.rest.y = _floor - _low_vertex(part, part.rotation_at(1.0))
	_parts.append(part)

	if role.begins_with("Launcher"):
		var spark := heading.normalized() * 0.39
		_add_burst(Effect.FLASH, part.start + Vector3.UP * 0.05, spark * 0.25,
			part.release - 0.018, 0.21, 0.28, side * 0.61, Color("ffaf53"))
		_add_burst(Effect.SPARK, part.start, spark, part.release, 0.28, 0.074,
			atan2(spark.x, spark.z), Color("ffd16d"))

func _emit_core(center: Vector3) -> void:
	var socket := _reactor_origin if _reactor_origin.is_finite() else center - _forward * 0.23 + Vector3.UP * 0.10
	var fire_center := socket - _forward * 0.046 + Vector3.UP * 0.13
	# A small electrical flare at the reactor precedes the two hot ruptures.
	_add_burst(Effect.FLASH, socket, -_forward * 0.046, 0.0, 0.13, 0.33, 0.23, Color("7dd9ff"))
	_add_burst(Effect.FLASH, fire_center, -_forward * 0.10, 0.11, 0.24, 0.69, -0.32, Color("ff9a36"))
	_add_burst(Effect.FLASH, fire_center.lerp(center, 0.47) + Vector3.UP * 0.11,
		_forward * 0.08, 0.24, 0.32, 0.99, 0.54, Color("ff7c30"))
	for i in 8:
		var angle := 2.399963 * float(i)
		var radial := Vector3(sin(angle), 0, cos(angle))
		var drift := radial * (0.25 + 0.037 * i) - _forward * 0.22
		_add_burst(Effect.SPARK, fire_center, drift, 0.13 + 0.013 * i, 0.38, 0.092, angle, Color("ffb265"))
	for i in 4:
		var drift := -_forward * (0.23 + 0.06 * i) + _side * sin(i * 2.4) * 0.21
		_add_burst(Effect.SOOT, fire_center + Vector3.UP * (0.04 * i), drift, 0.18 + 0.09 * i,
			0.94 + 0.14 * i, 0.55 + 0.075 * i, 0.41 * i, Color("544d49bb"))
