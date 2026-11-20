## Standalone presentation fixture. No simulation or battle scene is constructed.
extends SceneTree

const Aircraft = preload("res://scripts/visuals/medivac_3d.gd")
const Fleet = preload("res://scripts/visuals/hellion_layer.gd")
var failures := 0

class FixtureGame:
	extends RefCounted
	var started := true
	var paused := false
	var backgrounded := false
	var help_open := false
	var economy_open := false
	var setup_open := false
	var formation_panel := {"opened": false}
	var accumulator := 0.025
	var hidden := true
	var camera_rect := Rect2(0, 0, 100, 50)
	var sim := {
		"tick": 20, "rules": {"tick_rate": 20}, "units": [], "by_id": {},
		"active_beams": [], "attack_waves": [],
		"catalog": {"hellbat": {"size": [1.2, 1.2], "layer": "ground", "attack_modes": [
			{"id": "flame_jet", "delivery": {"length": 5, "speed": 15.0}}
		]}}
	}
	func _hidden_team(team: int) -> bool:
		return hidden and team == 1
	func _camera_rect() -> Rect2:
		return camera_rect

class FixtureView:
	extends RefCounted
	func viewport_size() -> Vector2:
		return Vector2(800, 400)
	func point(p: Vector2) -> Vector2:
		return p * 8.0
	func pixels(length: float) -> float:
		return length * 8.0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func has_flame(actor) -> bool:
	return is_instance_valid(actor.flame) and actor.flame.visible

func nozzle_bearing(actor) -> float:
	var axis: Vector3 = actor.turret.global_basis.x
	return Vector2(axis.x, axis.z).angle()

func bearing_to_target(actor, view, target: Vector2) -> float:
	var nozzle: Vector3 = actor.muzzle_world()
	return (view.point(target) - Vector2(nozzle.x, nozzle.z)).angle()

func sync_layer(layer, fleet, view, dt: float) -> void:
	layer.sync(view, dt)
	fleet.sync_shared(view, layer, dt)

func run() -> void:
	var game := FixtureGame.new()
	var view := FixtureView.new()
	var layer := Aircraft.new()
	layer.game = game
	root.add_child(layer)
	var fleet := Fleet.new()
	fleet.initialize(layer)
	var car := {"id": 1, "kind": "hellbat", "team": 0, "pos": Vector2(20, 20),
		"prev": Vector2(19.9, 20), "locked_target_id": 2, "engage_id": 2, "born": 0}
	var enemy := {"id": 2, "kind": "hellbat", "team": 1, "pos": Vector2(16, 20),
		"prev": Vector2(16, 20), "locked_target_id": 0, "engage_id": 0, "born": 0}
	game.sim.units = [car, enemy]
	var flank := {"id": 3, "kind": "dummy", "team": 1, "prev": Vector2(21, 25), "pos": Vector2(21, 25)}
	game.sim.by_id = {1: car, 2: enemy, 3: flank}
	sync_layer(layer, fleet, view, 0.05)
	if not fleet.has_model(1):
		printerr("Hellion not instanced. Import the articulated model before running the smoke.")
		quit(1)
		return
	var actor = fleet.entries[1].actor
	check(not fleet.has_model(2), "Unrevealed enemy should retain the hidden-unit representation")
	check(actor.get_viewport() == layer.viewport and layer.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"Visible vehicle should wake the shared world when no aircraft are present")
	game.hidden = false
	if not is_instance_valid(actor.turret) or actor.wheels.size() != 4 or actor.wheels.has(null):
		printerr("Expected the uploaded hull rig to contain the gun turret and four articulated wheels")
		quit(1)
		return
	var wheels_at_spawn: float = actor.wheel_phase
	var front_wheel_at_spawn: float = actor.wheels[0].rotation.z
	# Chassis travels east while the target remains due west. Wind the presentation clock
	# forward, supplying fresh positions so each visual update includes real translation.
	for step in range(20):
		car.prev = car.pos
		car.pos += Vector2(0.06, 0)
		sync_layer(layer, fleet, view, 0.08)
	check(not is_equal_approx(actor.wheel_phase, wheels_at_spawn) and not is_equal_approx(actor.wheels[0].rotation.z, front_wheel_at_spawn), "Wheels should roll while travelling")
	check(absf(angle_difference(actor.heading, 0.0)) < 0.08, "Movement should keep the chassis heading east")
	check(absf(angle_difference(actor.turret_heading, PI)) < 0.12, "Roof turret should aim backward independently of the chassis")
	check(absf(angle_difference(nozzle_bearing(actor), PI)) < 0.12,
		"Rendered gun should point backward in world space")
	check(not has_flame(actor), "Tracking a target must not start a flame")
	car.prev = car.pos
	car.pos += Vector2(0.0, 0.08)
	var previous_heading: float = actor.heading
	sync_layer(layer, fleet, view, 0.05)
	var turn := absf(angle_difference(previous_heading, actor.heading))
	check(turn > 0.001 and turn < PI / 2.0, "Chassis should steer into the bend over time")
	check(absf(angle_difference(nozzle_bearing(actor), bearing_to_target(actor, view, enemy.pos))) < 0.02,
		"Cornering should keep the rendered nozzle pointed at the tracked enemy")
	var previous_wheel: float = actor.wheel_phase
	var previous_turret: float = actor.turret_heading
	previous_heading = actor.heading
	game.paused = true
	sync_layer(layer, fleet, view, 0.1)
	check(is_equal_approx(actor.heading, previous_heading) and is_equal_approx(actor.wheel_phase, previous_wheel)
		and is_equal_approx(actor.turret_heading, previous_turret), "Pause should freeze the chassis, wheels and turret")
	game.paused = false
	car.prev = car.pos
	sync_layer(layer, fleet, view, 0.05)
	previous_wheel = actor.wheel_phase
	sync_layer(layer, fleet, view, 0.05)
	check(is_equal_approx(actor.wheel_phase, previous_wheel), "Wheels should stop spinning when parked")

	# A nearby firing target supersedes the old lock as the chassis finishes turning.
	car.attack_phase = "firing"
	car.attack_target_id = flank.id
	flank.pos = car.pos + Vector2(0.7, 0.12)
	flank.prev = flank.pos
	for step in range(22):
		sync_layer(layer, fleet, view, 0.08)
	check(absf(angle_difference(actor.heading, PI / 2.0)) < 0.02,
		"Chassis should have completed its turn before checking the close target")
	var target_bearing := bearing_to_target(actor, view, flank.pos)
	check(absf(angle_difference((flank.pos - car.pos).angle(), target_bearing)) > 0.15,
		"The near target should distinguish an offset roof gun from chassis-center aim")
	check(absf(angle_difference(nozzle_bearing(actor), target_bearing)) < 0.005,
		"The actual barrel ray should point at the close target from its muzzle")
	check(not has_flame(actor), "Entering the firing phase alone must not create a flame")
	previous_turret = actor.turret_heading
	game.hidden = true
	sync_layer(layer, fleet, view, 0.08)
	check(is_equal_approx(previous_turret, actor.turret_heading), "Losing sight should hold the gun's last world bearing")
	game.hidden = false
	car.erase("attack_phase")
	car.erase("attack_target_id")
	for step in range(22):
		sync_layer(layer, fleet, view, 0.08)
	# Feed the real presentation shape of a flame segment and then its continuation.
	var previous: Array = fleet.before_step(game.sim)
	game.sim.tick += 1
	game.sim.attack_waves = [{"source_id": car.id, "kind": "hellbat", "team": 0,
		"source": car.pos, "origin": car.pos, "direction": Vector2.LEFT, "distance": 0.75,
		"strike": 0, "born": game.sim.tick, "effect": "flame", "length": 5.0, "speed": 15.0}]
	var segment := {"type": "line_attack", "kind": "hellbat", "effect": "flame", "team": 0,
		"source": car.pos, "from": car.pos, "to": car.pos + Vector2.LEFT * 0.75,
		"half_width": 0.3}
	var owned: Dictionary = fleet.observe_step(game, previous, [segment])
	check(owned.get(0) == car.id, "Flame should be claimed by the emitting car")
	sync_layer(layer, fleet, view, 0.01)
	check(has_flame(actor), "The actual flame event should ignite the muzzle")
	check(actor.flame.global_position.distance_to(actor.muzzle_world()) < 0.001,
		"Visible jet should start at the transformed barrel socket")
	var first_shot_age: float = actor.shot_age
	game.sim.attack_waves[0].distance = 1.5
	segment.from = segment.to
	segment.to = car.pos + Vector2.LEFT * 1.5
	fleet.observe_step(game, previous, [segment])
	check(is_equal_approx(actor.shot_age, first_shot_age), "A travelling segment must not restart the same flame")
	game.sim.attack_waves.clear()
	# Camera culling and fog must also dispose of previously visible instances.
	game.hidden = false
	sync_layer(layer, fleet, view, 0.05)
	check(fleet.has_model(2), "Revealing the opponent should create its actor")
	game.hidden = true
	game.camera_rect = Rect2(300, 300, 100, 50)
	sync_layer(layer, fleet, view, 0.05)
	check(not fleet.has_model(1) and not fleet.has_model(2), "Offscreen and hidden actors should be released")
	game.camera_rect = Rect2(0, 0, 100, 50)
	sync_layer(layer, fleet, view, 0.05)
	actor = fleet.entries[1].actor
	previous = fleet.before_step(game.sim)
	game.sim.units = []
	game.sim.by_id.clear()
	fleet.observe_step(game, previous, [{"type": "death", "id": 1, "team": 0, "pos": car.pos}])
	sync_layer(layer, fleet, view, 0.05)
	check(not fleet.has_model(1) and actor.wreck_age > 0.0, "Death should start a finite vehicle wreck")
	check(not has_flame(actor), "Destroyed vehicles should stop firing")
	check_wreck_sequence(actor, game, layer, fleet, view)
	fleet.reset()
	layer.reset()
	check(layer.clock == 0.0 and fleet.entries.is_empty(), "Reset should clear visual time and IDs")
	layer.free()
	if failures == 0:
		print("Hellion visual smoke passed")
	quit(1 if failures else 0)

# Advance the real visual layer, bounded to its normal update timestep.
func advance_wreck_to(age: float, actor, layer, fleet, view) -> void:
	for step in range(ceili(maxf(0, age - actor.wreck_age) / 0.04) + 1):
		if actor.wreck_age >= age - 0.0001:
			return
		sync_layer(layer, fleet, view, minf(0.04, age - actor.wreck_age))

func fragment_poses(parts: Array) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for part in parts:
		poses.append(part.mesh.transform)
	return poses

func check_wreck_sequence(actor, game, layer, fleet, view) -> void:
	var original_body: Node3D = actor.model_root.find_child("Body", true, false)
	if original_body == null:
		check(false, "Expected the original Body mesh on the articulated vehicle")
		return
	check(original_body.is_visible_in_tree(), "Fuel ignition should briefly retain the original chassis")
	check(not actor.rupture.is_empty() and actor.rupture[0].visible, "The fuel compartment should flash before the chassis breaks")
	if not actor.rupture.is_empty():
		var tank: Vector3 = actor.to_local(actor.tank_socket.global_position)
		check(actor.rupture[0].position.distance_to(tank) < 0.35, "Ignition should originate at the fuel compartment")
	var original_parts: Array = actor.wheels.duplicate()
	original_parts.append(actor.turret)
	advance_wreck_to(actor.BREAK_TIME - 0.01, actor, layer, fleet, view)
	check(original_body.is_visible_in_tree(), "Chassis should survive the initial ignition delay")
	advance_wreck_to(actor.BREAK_TIME + 0.03, actor, layer, fleet, view)
	check(not original_body.is_visible_in_tree(), "An intact chassis must not remain after breakup")
	var parts: Array = actor.wreck_parts
	if parts.size() < 8:
		check(false, "Expected four detached wheels, the gun and at least three textured chassis fragments")
		return
	var pieces: Array[MeshInstance3D] = []
	var body_meshes: Array[Mesh] = []
	for part in parts:
		pieces.append(part.mesh)
		check(part.mesh.is_visible_in_tree() and part.mesh.mesh != null, "Each debris piece should have visible geometry")
		if not original_parts.has(part.mesh) and part.mesh.mesh != null and part.mesh.mesh.get_surface_count() > 0:
			if not body_meshes.has(part.mesh.mesh):
				body_meshes.append(part.mesh.mesh)
	for old_part in original_parts:
		check(pieces.has(old_part), "The detached wheel or turret should use its original mesh")
	check(body_meshes.size() >= 3, "Body should fragment into at least three different mesh sections")
	var initial := fragment_poses(parts)
	var scene_children: int = actor.find_children("*", "", true, false).size()
	var wreck_age: float = actor.wreck_age
	game.paused = true
	sync_layer(layer, fleet, view, 0.1)
	check(is_equal_approx(actor.wreck_age, wreck_age) and fragment_poses(parts) == initial, "Pause should freeze the debris in midair")
	game.paused = false

	# Observe independent trajectories through the camera's ground plane. A real bounce
	# descends then rises again before settling. This also catches frozen debris.
	var seen_descent: Dictionary = {}
	var observed_bounce := false
	var previous := initial
	var ascending_at_launch := false
	var distinct_directions: Dictionary = {}
	for sample in range(80):
		if actor.wreck_age >= 1.55:
			break
		sync_layer(layer, fleet, view, 0.02)
		var current := fragment_poses(parts)
		for index in parts.size():
			var motion: Vector3 = current[index].origin - previous[index].origin
			if motion.y < -0.001:
				seen_descent[index] = true
			elif motion.y > 0.001:
				ascending_at_launch = true
				if seen_descent.has(index):
					observed_bounce = true
		previous = current
	var grounded := fragment_poses(parts)
	for index in parts.size():
		var offset: Vector3 = grounded[index].origin - initial[index].origin
		var offset_on_ground := Vector2(offset.x, offset.z)
		check(offset_on_ground.length() > 0.035, "Each piece should travel across the ground")
		distinct_directions[roundi(offset_on_ground.angle() * 8.0)] = true
		check(not grounded[index].basis.is_equal_approx(initial[index].basis), "Detached pieces should spin")
	check(ascending_at_launch and observed_bounce, "Ejected debris should arc, land, and rebound")
	check(distinct_directions.size() >= 4, "Debris should scatter on several distinct paths")
	check(actor.find_children("*", "", true, false).size() <= scene_children, "Stepping debris should not keep allocating extra scene nodes")
	advance_wreck_to(actor.FADE_START - 0.05, actor, layer, fleet, view)
	var held := fragment_poses(parts)
	for index in parts.size():
		check(held[index].is_equal_approx(grounded[index]), "Settled pieces should rest in place before the fade")
	check(is_equal_approx(actor.wreck_opacity, 1.0), "Settled wreckage should remain fully visible until the fade")
	advance_wreck_to(lerpf(actor.FADE_START, actor.WRECK_DURATION, 0.50), actor, layer, fleet, view)
	check(actor.wreck_opacity > 0.0 and actor.wreck_opacity < 1.0, "The settled wreck should fade before it is released")
	var remaining: float = actor.WRECK_DURATION - actor.wreck_age
	for step in range(ceili(remaining / 0.05) + 2):
		sync_layer(layer, fleet, view, 0.05)
	check(fleet.entries.is_empty() and actor.is_queued_for_deletion(), "All debris must be removed together when the wreck expires")
