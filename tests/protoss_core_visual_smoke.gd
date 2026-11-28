## Exercises the shared battlefield models with fixed presentation snapshots.
## After Godot imports the display rigs: godot --headless -s tests/protoss_core_visual_smoke.gd
extends SceneTree

const SharedView = preload("res://scripts/visuals/medivac_3d.gd")
const DT := 0.05
const SOLAR_IDLE := "SolarIdle"

class FixtureGame:
	var started := true
	var paused := false
	var backgrounded := false
	var help_open := false
	var economy_open := false
	var setup_open := false
	var fog := false
	var window := Rect2(0, 0, 40, 24)
	var accumulator := 0.025
	var sim := {"tick": 20, "finished": false, "rules": {"tick_rate": 20}, "units": [],
		"catalog": {}, "by_id": {}, "active_beams": [], "projectiles": [], "skill_areas": []}

	func _hidden_team(team: int) -> bool:
		return fog and team == 1

	func _camera_rect() -> Rect2:
		return window


class FixtureView:
	func viewport_size() -> Vector2:
		return Vector2(800, 480)

	func point(pos: Vector2) -> Vector2:
		return pos * 20.0

	func pixels(distance: float) -> float:
		return distance * 20.0


var host = SharedView.new()
var game := FixtureGame.new()
var view := FixtureView.new()
var sentry := {"id": 51, "kind": "sentry", "team": 0, "hp": 40,
	"prev": Vector2(11.9, 8), "pos": Vector2(12, 8)}
var disruptor := {"id": 52, "kind": "disruptor", "team": 1, "hp": 100,
	"prev": Vector2(18, 8), "pos": Vector2(18, 8)}
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> bool:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
	return ok


func sync_step(delta: float) -> void:
	game.accumulator += delta
	if game.accumulator >= DT:
		game.sim.tick += 1
		game.accumulator -= DT
	host.sync(view, delta)


func sync_span(seconds: float) -> void:
	var samples := ceili(seconds / DT)
	for step in samples:
		sync_step(seconds / float(samples))


func check_facing(entry: Dictionary) -> void:
	var model: Node3D = entry.model
	var tail := model.find_child("TailOrb", true, false) as Node3D
	var nose := model.find_child("NoseTip", true, false) as Node3D
	if not check(tail != null and nose != null, "The display rig should identify the physical tail sphere and the nose"):
		return
	var first: Vector3 = nose.global_position - tail.global_position
	check(first.x > 0.0 and Vector2(first.x, first.z).normalized().dot(Vector2.RIGHT) > 0.96,
		"The hardware nose should start in front of its trailing sphere")
	for step in 29:
		sentry.prev = sentry.pos
		sentry.pos += Vector2.DOWN * 0.06
		sync_step(DT)
	var forward: Vector3 = nose.global_position - tail.global_position
	check(Vector2(forward.x, forward.z).normalized().dot(Vector2.DOWN) > 0.96,
		"The actual nose and tail should turn to match the map movement")
	sentry.prev = sentry.pos
	var snapshot := sentry.duplicate(true)
	game.sim.active_beams = [{"kind":"sentry", "source_id":sentry.id, "target_id":disruptor.id,
		"from":sentry.pos, "to":disruptor.pos}]
	sync_span(0.65)
	forward = nose.global_position - tail.global_position
	var aim := Vector2(sentry.pos).direction_to(disruptor.pos)
	check(Vector2(forward.x, forward.z).normalized().dot(aim) > 0.96,
		"A stationary sentry's actual nose should follow its native beam target")
	game.sim.active_beams.clear()
	check(sentry == snapshot, "The presentation must leave the simulation snapshot unchanged")


func check_solar_loop(entry: Dictionary) -> void:
	# A native charging area drives aim without constructing any combat logic.
	var goal: Vector2 = disruptor.pos + Vector2.DOWN * 2.0
	game.sim.skill_areas = [{"kind":"disruptor", "source_id":disruptor.id,
		"origin":disruptor.pos, "pos":goal}]
	sync_span(0.65)
	var facing: Node3D = entry.facing
	var nose_axis := facing.global_basis.x
	check(Vector2(nose_axis.x, nose_axis.z).normalized().dot(Vector2.DOWN) > 0.96,
		"A stationary disruptor should face its native nova target")
	game.sim.skill_areas.clear()
	var player: AnimationPlayer = entry.player
	if not check(is_instance_valid(player) and player.has_animation(SOLAR_IDLE),
			"The imported disruptor rig should provide its SolarIdle clip"):
		return
	var clip := player.get_animation(SOLAR_IDLE)
	if not check(clip.length > 0.5 and clip.loop_mode == Animation.LOOP_LINEAR, "SolarIdle must have an imported looping clip"):
		return
	var model: Node3D = entry.model
	var material_count := 0
	var parts: Dictionary = {}
	for name in ["SolarCore", "Shield", "HeatFilamentsA", "HeatFilamentsB"]:
		var part := model.find_child(name, true, false) as Node3D
		if not check(part != null and part.is_visible_in_tree(), "The actual disruptor rig should render " + name):
			return
		parts[name] = part
	for part in model.find_children("*", "MeshInstance3D", true, false):
		if part.mesh != null and part.mesh.get_surface_count() > 0 and part.get_active_material(0) != null:
			material_count += 1
	check(material_count >= 4, "The rendered hull and solar effect should include their material resources")
	var core: Node3D = parts.SolarCore
	var shield: Node3D = parts.Shield
	var heat_a: Node3D = parts.HeatFilamentsA
	var heat_b: Node3D = parts.HeatFilamentsB
	var start_time := player.current_animation_position
	var start_core := core.transform
	var start_shield := shield.transform
	var start_a := heat_a.transform
	var start_b := heat_b.transform
	sync_span(float(clip.length) * 0.25)
	check(not core.transform.is_equal_approx(start_core), "The production clock should rotate the solar core")
	check(not heat_a.transform.is_equal_approx(start_a) and not heat_b.transform.is_equal_approx(start_b),
		"Both independent heat filament groups should animate")
	check(shield.transform.is_equal_approx(start_shield), "The outer shield should not rotate with the solar core")

	game.paused = true
	var held_time := player.current_animation_position
	var held_core := core.transform
	var held_filaments := heat_a.transform
	host.sync(view, 0.1)
	# Also allow the engine frames to run so an unmanaged player cannot appear paused accidentally.
	await create_timer(0.08).timeout
	host.sync(view, 0.1)
	check(is_equal_approx(player.current_animation_position, held_time) and core.transform.is_equal_approx(held_core)
			and heat_a.transform.is_equal_approx(held_filaments), "Pause should freeze the native animation time and visible geometry")
	game.paused = false
	sync_span(float(clip.length) * 0.75)
	var wrap_error := absf(wrapf(player.current_animation_position - start_time, -clip.length * 0.5, clip.length * 0.5))
	var core_turn := start_core.basis.orthonormalized().get_rotation_quaternion().angle_to(core.basis.orthonormalized().get_rotation_quaternion())
	check(wrap_error < 0.02 and core_turn < 0.04, "After a full period the production layer should return to the same solar phase")


func check_visibility() -> void:
	var old_sentry: Node3D = host.protoss.entries[sentry.id].root
	var old_disruptor: Node3D = host.protoss.entries[disruptor.id].root
	var camera := game.window
	game.window = Rect2(100, 100, 40, 24)
	sync_step(DT)
	check(host.protoss.entries.is_empty() and old_sentry.is_queued_for_deletion() and old_disruptor.is_queued_for_deletion()
			and not old_sentry.is_visible_in_tree() and not old_disruptor.is_visible_in_tree(),
		"Offscreen models should be hidden immediately and queued for release")
	check(host.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "An empty shared viewport should stop rendering")
	game.window = camera
	sync_step(DT)
	if not check(host.has_model(sentry.id) and host.has_model(disruptor.id), "Both renderers should return on reentry"):
		return
	check(host.protoss.entries[sentry.id].root != old_sentry and host.protoss.entries[disruptor.id].root != old_disruptor,
		"No offscreen renderer should be resurrected alongside the new instance")
	var enemy: Node3D = host.protoss.entries[disruptor.id].root
	game.fog = true
	sync_step(DT)
	check(host.has_model(sentry.id) and not host.has_model(disruptor.id) and not enemy.is_visible_in_tree()
			and enemy.is_queued_for_deletion(), "Fog should retire the enemy model and its solar effect while keeping friendly models")
	game.sim.units.clear()
	game.sim.by_id.clear()
	sync_step(DT)
	check(host.protoss.entries.is_empty(), "A removed unit should release its active entry")


func run() -> void:
	game.sim.catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/units.json")).units
	game.sim.units = [sentry, disruptor]
	game.sim.by_id = {sentry.id: sentry, disruptor.id: disruptor}
	host.game = game
	root.add_child(host)
	host.sync(view, 0.0)
	if check(host.has_model(sentry.id) and host.has_model(disruptor.id), "Imported display rigs should enter through the shared battlefield viewport"):
		var scout: Dictionary = host.protoss.entries[sentry.id]
		var solar: Dictionary = host.protoss.entries[disruptor.id]
		check(scout.root.get_viewport() == host.viewport and solar.root.get_viewport() == host.viewport,
			"Both units should reuse the existing 3D battlefield viewport")
		check_facing(scout)
		await check_solar_loop(solar)
		check_visibility()
	host.reset()
	host.free()
	if failures == 0:
		print("Protoss core presentation smoke passed")
	quit(0 if failures == 0 else 1)
