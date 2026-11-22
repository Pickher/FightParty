extends "res://scripts/visuals/thor_wreck.gd"
## A ruptured rear engine vents first. The magazine throws the turret from its ring.
var vent := Vector3.ZERO

func _emit_core(center: Vector3) -> void:
	_add_burst(Effect.FLASH, vent, -_forward * 0.055, 0.0, 0.14, 0.32, 0.31, Color("ffd478"))
	_add_burst(Effect.FLASH, vent, -_forward * 0.11 + Vector3.UP * 0.09, 0.09, 0.26, 0.60, -0.68, Color("ff892e"))
	_add_burst(Effect.FLASH, center + Vector3.UP * 0.06, Vector3.UP * 0.19, 0.174, 0.33, 0.88, 1.13, Color("ffc05b"))
	for i in 9:
		var angle := 2.40 * i
		var drift := _forward * cos(angle) + _side * sin(angle)
		_add_burst(Effect.SPARK, vent.lerp(center, i / 8.0), drift * (0.31 + 0.032 * i),
				0.09 + i * 0.014, 0.41, 0.085, angle, Color("ffc478"))
	for i in 4:
		var drift := -_forward * (0.11 + 0.051 * i) + _side * sin(i * 2.5) * 0.16 + Vector3.UP * 0.19
		_add_burst(Effect.SOOT, vent.lerp(center, i / 3.0), drift, 0.19 + 0.085 * i,
				0.93 + 0.07 * i, 0.52 + i * 0.045, 0.39 * i, Color("59534cb8"))

func _attach_piece(part: Piece, role: String, core: Vector3) -> void:
	super._attach_piece(part, role, core)
	var side := -1.0 if role.ends_with("N") else 1.0
	var forward_sign := -1.0 if role.contains("Rear") else 1.0
	var offset := Vector2(-0.24, -0.18)
	part.release = 0.30
	part.flight = 0.40
	part.rollout = 0.57
	part.hop = 0.075
	part.roll = 1.36
	part.yaw = 0.46
	if role == "Turret" or role == "Mount":
		var tower := role == "Turret"
		offset = Vector2(-0.14, 0.67) if tower else Vector2(0.25, 0.41)
		part.release = 0.175 if tower else 0.203
		part.flight = 0.70 if tower else 0.52
		part.hop = 0.47 if tower else 0.32
		part.roll = 3.94 if tower else 2.65
		part.yaw = -1.38 if tower else 0.82
	elif role.contains("Barrel"):
		offset = Vector2(0.68, -0.39) if role == "CenterBarrel" else Vector2(0.61, 0.47 * side)
		part.release = 0.195
		part.flight = 0.59
		part.hop = 0.29
		part.roll = 3.78
		part.yaw = -0.99 * side
	elif role.begins_with("Track"):
		offset = Vector2(forward_sign * 0.36, side * (0.54 if forward_sign > 0 else 0.39))
		part.release = 0.245 if forward_sign < 0 else 0.315
		part.flight = 0.43
		part.rollout = 0.57
		part.hop = 0.17
		part.roll = 2.42 * side
		part.yaw = forward_sign * side * 0.82
	elif role.begins_with("Foot") or role.begins_with("Arm"):
		offset = Vector2(-0.51 if role.begins_with("Foot") else -0.31, side * 0.47)
		part.release = 0.35
		part.roll = 3.21
		part.hop = 0.12
	var shift := _forward * offset.x + _side * offset.y
	part.axis = Vector3.UP.cross(shift).normalized()
	part.landing = part.start + shift * 0.76
	part.rest = part.start + shift
	part.landing.y = _floor - _low_vertex(part, part.rotation_at(0.8))
	part.rest.y = _floor - _low_vertex(part, part.rotation_at(1.0))
