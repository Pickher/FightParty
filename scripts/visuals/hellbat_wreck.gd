extends "res://scripts/visuals/thor_wreck.gd"
## Tank ignition and shell breakup reuse the articulated debris renderer and contact solver.
var fuel_origins: Array[Vector3] = []

func _emit_core(center: Vector3) -> void:
	var ignition := fuel_origins[0] if not fuel_origins.is_empty() else center
	var second := fuel_origins[1] if fuel_origins.size() > 1 else center
	_add_burst(Effect.FLASH, ignition, _side * .07, 0, .15, .45, .37, Color("ffda64"))
	_add_burst(Effect.FLASH, ignition, _side * .16 + Vector3.UP * .11, .09, .29, .92, .83, Color("ff852b"))
	_add_burst(Effect.FLASH, second, -_side * .16 + Vector3.UP * .10, .16, .26, .77, 1.42, Color("ff9b39"))
	for i in 9:
		var angle := 2.4 * i
		var drift := (_forward * cos(angle) + _side * sin(angle)) * (.39 + .031 * i) + Vector3.UP * .14
		_add_burst(Effect.SPARK, ignition if i % 2 == 0 else second, drift, .12 + .009 * i, .38, .079, angle, Color("ffb155"))
	for i in 4:
		var drift := -_forward * (.10 + .047 * i) + _side * sin(i * 2.1) * .20 + Vector3.UP * .23
		_add_burst(Effect.SOOT, ignition.lerp(second, i / 3.0), drift, .20 + .07 * i, .94 + .04 * i, .36 + i * .047, .67 * i, Color("615043b8"))

func _attach_piece(part: Piece, role: String, core: Vector3) -> void:
	super._attach_piece(part, role, core)
	var thrust := 1.38 if role.begins_with("Pod") or role.begins_with("Arm") else 1.18
	part.rest.x = lerpf(part.start.x, part.rest.x, thrust)
	part.rest.z = lerpf(part.start.z, part.rest.z, thrust)
	part.landing.x = lerpf(part.start.x, part.landing.x, thrust)
	part.landing.z = lerpf(part.start.z, part.landing.z, thrust)
	part.hop *= 1.37
