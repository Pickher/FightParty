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
	check(actor.rupture.size() > 0 and actor.rupture[0].visible, "Fuel tank should rupture on destruction")
	if not actor.rupture.is_empty():
		var tank_position: Vector3 = actor.to_local(actor.tank_socket.global_position)
		check(actor.rupture[0].position.distance_to(tank_position) < 0.35 and actor.rupture[0].scale.x <= 0.5,
			"Fuel flash should stay local to the tank and smaller than the hull")
	for step in range(4):
		sync_layer(layer, fleet, view, 0.1)
	check(actor.darkened and not actor.rupture.is_empty() and not actor.rupture[0].visible, "Fuel flash should clear and expose the scorched chassis")
	for step in range(36):
		sync_layer(layer, fleet, view, 0.1)
	check(fleet.entries.is_empty(), "Fuel-tank explosion and wreck must expire")
	fleet.reset()
	layer.reset()
	check(layer.clock == 0.0 and fleet.entries.is_empty(), "Reset should clear visual time and IDs")
	layer.free()
	if failures == 0:
		print("Hellion visual smoke passed")
	quit(1 if failures else 0)
