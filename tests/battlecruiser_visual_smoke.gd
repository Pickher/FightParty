## Optional presentation-only smoke. Supplies positions and events directly; no match is created.
## After editor import, run: godot --headless -s tests/battlecruiser_visual_smoke.gd
extends SceneTree

const AircraftLayer = preload("res://scripts/visuals/medivac_3d.gd")
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
	var sim := {
		"tick": 20, "rules": {"tick_rate": 20}, "units": [], "active_beams": [],
		"by_id": {}, "catalog": {"battlecruiser": {"size": [2.5, 2.5],
			"skills": {"yamato": {"channel_seconds": 2.0}}}},
	}
	func _hidden_team(team: int) -> bool:
		return team == 1
	func _camera_rect() -> Rect2:
		return Rect2(0, 0, 100, 50)

class FixtureView:
	extends RefCounted
	func viewport_size() -> Vector2:
		return Vector2(800, 400)
	func point(position: Vector2) -> Vector2:
		return position * 8.0
	func pixels(length: float) -> float:
		return length * 8.0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr(message)

func run() -> void:
	var game := FixtureGame.new()
	var view := FixtureView.new()
	var layer := AircraftLayer.new()
	layer.game = game
	root.add_child(layer)
	var ship := {"id": 1, "kind": "battlecruiser", "team": 0, "weapon_index": 0,
		"prev": Vector2(20, 20), "pos": Vector2(21, 20)}
	var target := {"id": 2, "kind": "battlecruiser", "team": 1, "weapon_index": 0,
		"prev": Vector2(20, 30), "pos": Vector2(20, 30)}
	game.sim.units = [ship, target]
	game.sim.by_id = {1: ship, 2: target}
	layer.sync(view, 0.016)
	if not layer.has_model(1):
		printerr("Ship not instanced. Import the GLB before running the visual smoke.")
		quit(1)
		return
	var fleet = layer.battlecruisers
	var actor = fleet.entries[1].actor
	check(actor.get_viewport() == layer.viewport, "Ship should use the common aircraft viewport")
	check(not layer.has_model(2), "Hidden enemy acquired a visible hull")
	check(is_equal_approx(actor.position.x, 164.0), "Ship should be drawn halfway between the two ticks")

	# A right-angle course change should bank and rotate over multiple presentation frames.
	ship.prev = ship.pos
	ship.pos += Vector2.DOWN
	var initial_heading: float = actor.heading
	layer.sync(view, 0.025)
	var turn := absf(angle_difference(initial_heading, actor.heading))
	check(turn > 0.001 and turn < PI / 2.0 and absf(actor.bank) > 0.001, "Course change should turn and bank gradually")
	game.paused = true
	var frozen_heading: float = actor.heading
	var frozen_clock: float = layer.clock
	layer.sync(view, 0.09)
	check(is_equal_approx(actor.heading, frozen_heading) and is_equal_approx(layer.clock, frozen_clock), "Pause should freeze mid-turn")
	game.paused = false

	# These dictionaries match the launch and release events emitted by the game.
	var before: Dictionary = layer.before_tick()
	var laser := {"type": "attack", "kind": "battlecruiser", "source_id": 1, "team": 0,
		"from": ship.pos, "to": target.pos, "mode": "ats_laser", "projectile": true, "time": 0.95}
	fleet.event(laser, before, game, layer.clock)
	check(fleet.owns_projectile({"kind": "battlecruiser", "source_id": ship.id, "launch_time": 0.95}), "Animated laser should own its matching projectile")
	check(actor.flash != null and actor.flash.visible, "Laser should flash from an ordinary battery")
	var battery: int = actor.active_battery
	fleet.event(laser, before, game, layer.clock)
	check(actor.active_battery != battery, "Successive ground shots should alternate batteries")
	laser.mode = "ata_laser"
	fleet.event(laser, before, game, layer.clock)
	check(actor.active_battery >= 2, "Air shots should use an upper battery")
	ship.yamato_target = target.id
	ship.yamato_fire_tick = game.sim.tick + 20
	layer.sync(view, 0.016)
	check(actor.charge > 0.0, "Channel progress should reach the charge effect")
	ship.erase("yamato_target")
	ship.erase("yamato_fire_tick")
	layer.sync(view, 0.016)
	check(actor.charge < 0 and actor.discharge_age >= actor.DISCHARGE_DURATION, "Cancelled charge fired a shot or kept glowing")

	ship.yamato_target = target.id
	ship.yamato_fire_tick = game.sim.tick
	before = layer.before_tick()
	ship.erase("yamato_target")
	ship.erase("yamato_fire_tick")
	var release := {"type": "yamato", "kind": "battlecruiser", "team": 0, "from": ship.pos, "to": target.pos}
	fleet.event(release, before, game, layer.clock)
	check(actor.discharge_age < actor.DISCHARGE_DURATION, "Yamato release should trigger recoil and discharge")
	check(fleet.traces.size() > 0 and fleet.traces.back().kind == "yamato", "Yamato release should create a cannon beam")
	if not fleet.traces.is_empty():
		var trace: Dictionary = fleet.traces.back()
		var socket: Vector2 = actor.muzzle_screen_offset(true) * float(game.sim.catalog.battlecruiser.size[0])
		check(Vector2(trace.offset).is_equal_approx(socket) and socket.length() > 0.001, "Beam should start at the transformed main cannon socket")
		check(Vector2(trace.to).is_equal_approx(target.pos), "Beam should use the actual release target")
	check(not actor.muzzle_screen_offset(true).is_equal_approx(actor.muzzle_screen_offset(false)), "Main cannon and laser should have distinct origins")

	before = layer.before_tick()
	game.sim.units = []
	game.sim.by_id.clear()
	fleet.event({"type": "death", "id": 1, "team": 0, "pos": ship.pos}, before, game, layer.clock)
	layer.sync(view, 0.05)
	check(actor.wreck_age > 0.0 and not layer.has_model(1), "Death should retain an animated wreck and retire the live ship")
	for i in range(5):
		layer.sync(view, 0.1)
	check(not actor.skin.visible and actor.fracture_parts.size() == 3, "Destroyed hull should separate into bow, middle and stern")
	for part in actor.fracture_parts:
		check(part.visible and part.get_child_count() > 0, "Each wreck section should contain visible hull geometry")
	for i in range(27):
		layer.sync(view, 0.1)
	check(fleet.entries.is_empty(), "Expired wreck is still present")
	layer.reset()
	check(fleet.traces.is_empty() and layer.clock == 0.0, "Reset should clear trails and animation time")
	if failures == 0:
		print("Battlecruiser visual smoke passed")
	layer.free()
	quit(1 if failures else 0)
