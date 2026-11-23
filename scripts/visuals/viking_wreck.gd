extends "res://scripts/visuals/thor_wreck.gd"
## Original rigid parts leave the pose they had on the frame of death.
## Ground and air share one debris solver; height and forward momentum vary continuously.
var airborne := 0.0
var _center := Vector3.ZERO
var _vent := Vector3.ZERO

func begin(model_root: Node3D, roles: Dictionary, ground_height: float) -> void:
	if _started:
		return
	airborne = clampf(airborne, 0.0, 1.0)
	# Measure the first rupture at the engine itself, even while its mounting is folding.
	var bounds := AABB()
	var found := false
	var world_to_local := global_transform.affine_inverse()
	for renderer in roles:
		if str(roles[renderer]) != "EngineP" or not renderer.is_visible_in_tree():
			continue
		var box: AABB = (world_to_local * renderer.global_transform) * renderer.get_aabb()
		bounds = bounds.merge(box) if found else box
		found = true
	if found:
		_vent = bounds.get_center()
	else:
		_vent = to_local(model_root.global_position)
	super.begin(model_root, roles, ground_height)
	# Airborne fragments can carry their ground shadows beyond two footprints.
	_batch.custom_aabb = _batch.custom_aabb.grow(0.8)

func _emit_core(center: Vector3) -> void:
	_center = center
	_add_burst(Effect.FLASH, _vent, -_forward * 0.065, 0.0, 0.15, 0.49, 0.46, Color("d7f5ff"))
	var breach := _vent + Vector3.UP * 0.10 + _side * 0.07
	var crown := center + Vector3.UP * 0.15
	_add_burst(Effect.FLASH, breach, _side * 0.13, 0.07, 0.29, 0.78, -0.57, Color("ff9237"))
	_add_burst(Effect.FLASH, crown + _forward * 0.056, _forward * 0.10, 0.175, 0.27, 0.68, 1.16, Color("ffa444"))
	for i in 7:
		var angle := 2.40 * i
		var drift := (_forward * cos(angle) + _side * sin(angle)) * (0.31 + 0.038 * i)
		_add_burst(Effect.SPARK, breach.lerp(crown, i / 8.0), drift, 0.07 + 0.012 * i, 0.37,
				0.092, atan2(drift.x, drift.z), Color("ffc47a"))
	for i in 3:
		var drift := -_forward * (0.14 + 0.064 * i) + _side * (0.065 * cos(i * 2.0))
		_add_burst(Effect.SOOT, breach, drift, 0.08 + 0.09 * i, 0.77 + 0.12 * i,
				0.38 + 0.073 * i, i * 0.91, Color("48464ecc"))

func _attach_piece(part: Piece, role: String, core: Vector3) -> void:
	# Each mesh keeps its world transform when transferred to its fragment pivot.
	part.pivot = Node3D.new()
	part.pivot.name = role + "Fragment"
	add_child(part.pivot)
	part.start = part.bounds.get_center()
	part.pivot.position = part.start
	for renderer in part.meshes:
		renderer.reparent(part.pivot, true)
	_parts.append(part)

	var radial := part.start - core
	var side := -1.0 if radial.dot(_side) < 0.0 else 1.0
	var reach := clampf(absf(radial.dot(_side)) * 1.4, 0.12, 0.68)
	var forward := clampf(radial.dot(_forward) * 1.4, -0.46, 0.55)
	var toss := 0.13
	var release := 0.21
	var roll := 2.45
	if role.begins_with("Wing"):
		reach = 0.77
		forward = -0.14
		release = 0.14
		toss = 0.21
		roll = 3.45
	elif role.begins_with("Engine"):
		reach = 0.43
		forward = -0.44
		release = 0.105 if role == "EngineP" else 0.19
		toss = 0.23
		roll = 3.16
	elif role.begins_with("Gun") or role.begins_with("Shoulder"):
		forward = 0.49 if role.begins_with("Gun") else -0.09
		reach = 0.53
		toss = 0.17
	elif role.begins_with("Ankle") or role.begins_with("Foot"):
		forward = 0.34
		reach = 0.28
		release = 0.32
		toss = 0.048
		roll = 1.35
	elif role == "Trunk" or role == "Pelvis":
		forward = 0.24 if role == "Trunk" else -0.23
		reach = 0.09
		release = 0.265
		toss = 0.076
		roll = 1.53
	part.release = release + (0.025 if side < 0.0 else 0.0)
	# Light wing panels carry further sideways; the falling fuselage retains its heading.
	var shift := _forward * (forward + 0.85 * airborne) + _side * side * reach
	part.axis = Vector3.UP.cross(_forward * forward + _side * side * reach).normalized()
	part.yaw = side * lerpf(0.67, 1.14, airborne)
	part.roll = roll + 0.82 * airborne
	part.landing = part.start + shift * (0.78 + 0.10 * airborne)
	part.rest = part.start + shift
	var landing_floor := _floor - _low_vertex(part, part.rotation_at(0.8))
	part.landing.y = landing_floor
	part.rest.y = _floor - _low_vertex(part, part.rotation_at(1.0))
	var drop := maxf(0.0, part.start.y + _locked_shift(part.release).y - landing_floor)
	part.flight = 0.32 + toss + airborne * (0.10 + 0.38 * sqrt(drop))
	part.rollout = 0.35 + 0.19 * airborne
	# The linear descent plus this arc gives a nearly level initial velocity and
	# an accelerating fall from the current height, even halfway through takeoff.
	part.hop = toss + drop * 0.25 * airborne
	if role == "EngineP":
		_engine_trail(part)
	elif role == "Trunk":
		_ground_contact(part)

func _engine_trail(part: Piece) -> void:
	for i in 3:
		var t := 0.22 + 0.22 * i
		var p := (part.start + _locked_shift(part.release)).lerp(part.landing, t)
		p.y += 4.0 * part.hop * t * (1.0 - t)
		var birth := part.release + t * part.flight
		_add_burst(Effect.SOOT, p, -_forward * (0.07 + 0.08 * airborne), birth,
				0.61, 0.25 + 0.05 * i, i * 1.23, Color("48444ba8"))
		if i < 2:
			_add_burst(Effect.SPARK, p, -_forward * 0.21 + _side * 0.09, birth,
					0.22, 0.065, atan2(-_forward.x, -_forward.z), Color("ffc76b"))

func _ground_contact(part: Piece) -> void:
	var contact := Vector3(part.landing.x, _floor + 0.015, part.landing.z)
	var at := part.release + part.flight
	_add_burst(Effect.FLASH, contact, Vector3.ZERO, at, 0.15, 0.34 + 0.34 * airborne, 0.18, Color("ffb675"))
	for i in 6:
		var angle := i * TAU / 6.0
		var ray := _forward * cos(angle) + _side * sin(angle)
		var drift := ray * (0.23 + 0.15 * airborne)
		_add_burst(Effect.SOOT, contact + ray * 0.042, drift, at + 0.014 * (i % 3), 0.49,
				0.25 + 0.12 * airborne, angle, Color("9b816baf"))
		if i % 2 == 0:
			_add_burst(Effect.SPARK, contact, drift * 1.27, at, 0.24, 0.078,
					atan2(drift.x, drift.z), Color("ffb968"))

func _locked_shift(age: float) -> Vector3:
	var ground := super._locked_shift(age)
	var coast := _forward * age * 0.65 + Vector3.DOWN * age * age * 1.32
	return ground.lerp(coast, airborne)

func _place_piece(part: Piece, age: float) -> void:
	super._place_piece(part, age)
	if airborne <= 0.0 or age >= part.release + part.flight:
		return
	# The airframe banks as one around the damaged engine. A detached part
	# inherits that attitude and pivots around its own center for the tumble.
	var t := clampf((age - part.release) / part.flight, 0.0, 1.0)
	var tilt := smoothstep(0.0, 0.31, minf(age, part.release)) * airborne
	var bank := Basis(_forward, 0.52 * tilt) * Basis(_side, -0.26 * tilt)
	var lever := part.start - _center
	part.pivot.position += (bank * lever - lever) * (1.0 - t)
	var tumble := part.rotation_at(0.80 * t)
	part.pivot.basis = bank.slerp(Basis.IDENTITY, t) * tumble
