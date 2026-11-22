## Exercises the game viewport with synthetic unit snapshots and launch events.
## After resource import: godot --headless --path . --script tests/thor_visual_smoke.gd
extends SceneTree

const Aircraft = preload("res://scripts/visuals/medivac_3d.gd")

## Observe the same per-frame flight and impact drawing decisions as the battle canvas.
class RecordedFleet:
	extends "res://scripts/visuals/thor_layer.gd"
	var rockets := {}
	var impacts := {}
	func sample(view, game, now: float) -> void:
		rockets.clear()
		impacts.clear()
		draw_ordnance(null, view, game, now)
	func _draw_rocket(_canvas: CanvasItem, _view, flight: Dictionary, _goal: Vector2, t: float, tip: Vector2, _duration: float) -> void:
		rockets[flight.strike] = {"progress": t, "pos": tip}
	func _draw_impact(_canvas: CanvasItem, _view, hit: Dictionary, strike: int, age: float) -> void:
		impacts[strike] = {"pos": hit.to, "age": age}

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
	var hide_enemy := true
	var camera_rect := Rect2(0, 0, 32, 20)
	var sim := {"tick": 20, "rules": {"tick_rate": 20}, "units": [], "by_id": {},
		"active_beams": [], "projectiles": [], "catalog": {}}
	func _hidden_team(team: int) -> bool:
		return hide_enemy and team == 1
	func _camera_rect() -> Rect2:
		return camera_rect

class FixtureView:
	extends RefCounted
	func viewport_size() -> Vector2:
		return Vector2(640, 400)
	func pixels(length: float) -> float:
		return length * 20.0
	func point(pos: Vector2) -> Vector2:
		return pos * 20.0

var failures := 0
var game := FixtureGame.new()
var view := FixtureView.new()
var host = Aircraft.new()
var fleet
var unit := {"id": 11, "kind": "thor", "team": 0, "hp": 400, "weapon_index": 2,
	"air_weapon_index": 0, "switch_until_tick": 0, "prev": Vector2(8.8, 8), "pos": Vector2(9, 8)}
var opponent := {"id": 21, "kind": "thor", "team": 1, "hp": 400, "weapon_index": 1,
	"air_weapon_index": 1, "switch_until_tick": 0, "prev": Vector2(20, 8), "pos": Vector2(20, 8)}
var air_target := {"id": 31, "kind": "viking", "team": 1, "hp": 135, "prev": Vector2(22, 8), "pos": Vector2(22, 8)}
var actor
var next_projectile_id := 1000

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func step(frames: int = 1) -> void:
	for i in frames:
		game.sim.tick += 1
		host.sync(view, 0.05)

func present_at(time: float, delta: float) -> void:
	var rate := float(game.sim.rules.tick_rate)
	var frame := time * rate
	game.sim.tick = floori(frame) + 1
	game.accumulator = (frame - floorf(frame)) / rate
	host.sync(view, delta)
	fleet.sample(view, game, fleet.render_time(game.sim, game.accumulator * rate))

func event(data: Dictionary) -> void:
	fleet.event(data, host.before_tick(), game, host.clock)

func cannon_poses() -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for cannon in actor.cannons:
		poses.append(cannon.transform)
	return poses

func switch_to(index: int) -> void:
	var before: Dictionary = host.before_tick()
	unit.air_weapon_index = index
	unit.weapon_index = index
	unit.switch_until_tick = game.sim.tick + 10
	fleet.event({"type": "weapon_switch", "id": unit.id, "weapon": "javelin" if index == 1 else "high_impact"}, before, game, host.clock)

func check_walk() -> void:
	var center: Vector2 = view.point(unit.prev.lerp(unit.pos, 0.5))
	check(Vector2(actor.position.x, actor.position.z).is_equal_approx(center), "Walker should use the interpolated game position")
	var start_phase: float = actor.walk_phase
	var direction_changes: Dictionary = {}
	var min_lift := INF
	var max_lift := -INF
	for i in 80:
		unit.prev = unit.pos
		unit.pos += Vector2(0.07, 0)
		step()
		# Compare the two physical feet in body space to exclude model translation.
		var a: Vector3 = actor.to_local(actor.feet[0].global_position)
		var b: Vector3 = actor.to_local(actor.feet[1].global_position)
		min_lift = minf(min_lift, a.y - b.y)
		max_lift = maxf(max_lift, a.y - b.y)
		if absf(a.x - b.x) > 0.015:
			direction_changes[signf(a.x - b.x)] = true
	check(not is_equal_approx(start_phase, actor.walk_phase) and direction_changes.size() == 2,
		"Left and right feet should take turns leading across a full stride")
	check(max_lift - min_lift > 0.05, "The stepping foot should lift above the planted foot")
	var moving_phase: float = actor.walk_phase
	game.paused = true
	host.sync(view, 0.1)
	check(is_equal_approx(moving_phase, actor.walk_phase), "Pausing should hold the current stride")
	game.paused = false
	unit.prev = unit.pos
	step(16)
	var stopped: float = actor.walk_phase
	step(6)
	check(is_equal_approx(actor.walk_phase, stopped), "Idle feet should stop advancing the walk cycle")

func check_switches() -> void:
	game.accumulator = 0.0
	var stowed := cannon_poses()
	var mesh_ids: Array[int] = []
	for cannon in actor.cannons:
		var meshes: Array[Node] = cannon.find_children("*", "MeshInstance3D", true, false)
		if cannon is MeshInstance3D:
			meshes.append(cannon)
		check(meshes.any(func(mesh): return mesh.mesh != null), "Every moving roof barrel should carry rendered geometry")
		mesh_ids.append(cannon.get_instance_id())
	switch_to(1)
	step(4)
	var outgoing := cannon_poses()
	check(actor.transform_progress > 0.0 and actor.transform_progress < 1.0, "Deploying the launchers should take several frames")
	var frozen: float = actor.transform_progress
	game.paused = true
	host.sync(view, 0.1)
	check(is_equal_approx(actor.transform_progress, frozen) and cannon_poses() == outgoing, "Pause should freeze all four moving barrels")
	game.paused = false
	step(8)
	var deployed := cannon_poses()
	check(is_equal_approx(actor.transform_progress, 1.0), "Javelin should reach the deployed endpoint")
	for i in 4:
		check(actor.cannons[i].get_instance_id() == mesh_ids[i], "A switch should move the same mounted cannon")
		var marker_name := str(actor.cannons[i].name).replace("Cannon", "Deploy")
		var target: Node3D = actor.find_child(marker_name, true, false)
		check(target != null, "Expected an authored end pose for " + str(actor.cannons[i].name))
		if target != null:
			check(actor.cannons[i].global_transform.is_equal_approx(target.global_transform), "Deployed barrel should match its authored rocket pose")
		check(not outgoing[i].basis.is_equal_approx(stowed[i].basis) and not outgoing[i].basis.is_equal_approx(deployed[i].basis),
			"Each barrel should rotate through an intermediate pose on deployment")
	unit.weapon_index = 2
	step(4)
	check(cannon_poses() == deployed, "Ground targeting should preserve the selected anti-air form")
	switch_to(0)
	step(5)
	var folding := cannon_poses()
	for i in 4:
		check(not folding[i].basis.is_equal_approx(deployed[i].basis) and not folding[i].basis.is_equal_approx(stowed[i].basis),
			"Every barrel should fold back through intermediate angles")
	# Cull in mid-switch. A returning actor should reflect the clock immediately.
	game.camera_rect = Rect2(100, 100, 32, 20)
	step()
	check(not fleet.has_model(unit.id), "Offscreen walker should be released")
	game.camera_rect = Rect2(0, 0, 32, 20)
	step()
	actor = fleet.entries[unit.id].actor
	check(actor.transform_progress > 0.0 and actor.transform_progress < 0.6, "Reentering mid-switch should restore the remaining fraction")
	step(5)
	check(is_zero_approx(actor.transform_progress), "High impact mode should finish folding on schedule")
	for i in 4:
		check(actor.cannons[i].transform.is_equal_approx(stowed[i]), "Folded barrel should return to its original transform")
	switch_to(1)
	step(4)
	var interrupted: float = actor.transform_progress
	switch_to(0)
	check(is_equal_approx(actor.transform_progress, interrupted), "Reversing an unfinished switch should preserve its current pose")
	step(2)
	check(actor.transform_progress < interrupted, "Barrels should start folding from the interrupted angle")
	step(10)

func launch(mode: String, strike: int, target: Dictionary, shooter: Dictionary, at: float = NAN) -> Dictionary:
	var weapon: Dictionary
	for config in game.sim.catalog.thor.attack_modes:
		if config.id == mode:
			weapon = config
			break
	var time := float(game.sim.tick) / float(game.sim.rules.tick_rate) if is_nan(at) else at
	var duration: float = shooter.pos.distance_to(target.pos) / float(weapon.delivery.speed) if weapon.delivery.flight == "distance" else weapon.delivery.seconds
	var shot := {"id": next_projectile_id, "kind": "thor", "source_id": shooter.id, "team": shooter.team, "launch_time": time,
		"impact_time": time + duration, "strike": strike, "origin": shooter.pos, "pos": shooter.pos,
		"goal": target.pos, "target_id": target.id, "weapon": weapon}
	next_projectile_id += 1
	game.sim.projectiles.append(shot)
	var original := shot.duplicate(true)
	event({"type": "attack", "kind": "thor", "source_id": shooter.id, "team": shooter.team, "from": shooter.pos,
		"to": target.pos, "mode": mode, "strike": strike, "splash": weapon.splash, "time": time, "projectile": true})
	check(shot == original, "A presentation launch should leave the native projectile untouched")
	return shot

func check_arm_salvo(mode: String) -> void:
	var mounts: Array = actor.arms + actor.cannons
	var sockets: Array = actor.arm_sockets + actor.cannon_sockets
	var expected_form: float = actor.transform_progress
	var offsets: Array[Vector2] = []
	var physical_sides: Array[float] = []
	for i in 2:
		game.sim.projectiles.clear()
		step(8)
		var slot := i
		var rest: Array[Vector3] = []
		for mount in mounts:
			rest.append(mount.position)
		var shot := launch(mode, i, opponent if mode == "hammer" else air_target, unit)
		var muzzle: Node3D = sockets[slot]
		var marker := Vector2(muzzle.global_position.x, muzzle.global_position.z)
		var origin: Vector2 = (marker - view.point(unit.pos)) / view.pixels(1.0)
		var actual: Vector2 = fleet.projectile_offset(shot, shot.launch_time)
		check(Vector2(fleet.projectile_offset(shot, (shot.launch_time + shot.impact_time) * 0.5)).is_equal_approx(actual * 0.5)
			and Vector2(fleet.projectile_offset(shot, shot.impact_time)).is_zero_approx(),
			"Arm projectile correction should converge to the native impact point")
		check(not fleet.owns_javelin(shot), "Arm shots should retain their native projectile drawing")
		offsets.append(actual)
		physical_sides.append(actor.trunk.to_local(muzzle.global_position).z)
		check(actual.distance_to(origin) < 0.025, "Launch should inherit the rendered muzzle origin for %s strike %d" % [mode, i])
		var flash = actor.flashes[slot]
		check(is_instance_valid(flash) and flash.is_visible_in_tree(), "A launch event should illuminate the selected socket")
		host.sync(view, 0.025)
		if is_instance_valid(flash):
			check(flash.global_position.distance_to(muzzle.global_position) < 0.01,
				"Flash should stay on the physical nozzle while the projectile travels")
		for j in mounts.size():
			if j == slot:
				check(mounts[j].position.distance_to(rest[j]) > 0.005, "The firing weapon should recoil")
			else:
				check(mounts[j].position.is_equal_approx(rest[j]), "An inactive arm or shoulder tube recoiled during " + mode)
				var unused = actor.flashes[j]
				check(not is_instance_valid(unused) or not unused.is_visible_in_tree(), "An inactive arm or shoulder tube flashed during " + mode)
		check(is_equal_approx(expected_form, actor.transform_progress), "Firing should preserve the active Thor form")
	check(physical_sides[0] * physical_sides[1] < 0.0 and offsets[0].distance_to(offsets[1]) > 0.08,
		"Consecutive %s shots should alternate physical sides and projected origins" % mode)
	game.sim.projectiles.clear()
	step(8)

func check_rocket_cadence() -> void:
	var flights: Array[Dictionary] = []
	var flashes_at: Array[float] = []
	var origins: Array[Vector2] = []
	var early_flash := false
	var wrong_flight_frame := false
	var wrong_impact_frame := false
	var max_progress_error := 0.0
	var base := float(game.sim.tick) / float(game.sim.rules.tick_rate)
	var launch_gap := 0.125 # Four strikes across the configured 0.5-second volley.
	var sample := 0.005
	var landed := 0
	var contacts := 0
	for frame in 220:
		var now := base + frame * sample
		if flights.size() < 4 and now + 0.000001 >= base + launch_gap * flights.size():
			var index := flights.size()
			var shot := launch("javelin", index, air_target, unit, base + launch_gap * index)
			var flight: Dictionary = fleet.javelins[[shot.source_id, index, shot.launch_time]]
			var original_duration: float = shot.impact_time - shot.launch_time
			check(is_equal_approx(flight.impact_time, shot.impact_time) and is_equal_approx(
				flight.impact_time - flight.release_time, original_duration / 1.5),
				"Each Javelin should travel for two thirds of its native duration and reach the original impact time")
			check(fleet.owns_javelin(shot), "Native rocket dots must remain suppressed while the shot waits to leave its tube")
			flights.append(flight)
		# Simulation contact is known at the end of its tick, while the camera is
		# still rendering the interval leading up to that contact.
		var render_tick := floori(now * game.sim.rules.tick_rate) + 1
		while contacts < flights.size():
			var due: float = flights[contacts].impact_time
			var impact_tick := ceili(due * game.sim.rules.tick_rate)
			if impact_tick > render_tick:
				break
			game.sim.tick = impact_tick
			var hit := {"type": "area_impact", "kind": "thor", "team": unit.team, "radius": 1.2, "from": air_target.pos, "to": air_target.pos}
			check(fleet.accept_javelin_impact(hit, game), "The shortened flight must preserve its exact native contact")
			contacts += 1
		present_at(now, sample)
		for i in flights.size():
			var f := flights[i]
			var flash = actor.flashes[i + 2]
			var lit: bool = is_instance_valid(flash) and flash.is_visible_in_tree()
			if now < f.release_time - 0.000001:
				early_flash = early_flash or lit or f.released
				wrong_flight_frame = wrong_flight_frame or fleet.rockets.has(i)
			elif now < f.impact_time - 0.000001:
				if flashes_at.size() == i:
					var socket: Node3D = actor.cannon_sockets[i]
					var center := Vector2(socket.global_position.x, socket.global_position.z) / view.pixels(1.0)
					check(f.released and lit and flash.global_position.distance_to(socket.global_position) < 0.01,
						"First airborne frame must illuminate the matching physical tube")
					check(center.distance_to(f.origin) < 0.025, "Rocket must leave the transformed socket at visual release")
					check(actor.cannons[i].position.distance_to(actor.deployed[i].origin) > 0.005, "The selected shoulder tube should recoil at release")
					origins.append(center)
					flashes_at.append(now)
				if fleet.rockets.has(i):
					var expected: float = (now - f.release_time) / (f.impact_time - f.release_time)
					max_progress_error = maxf(max_progress_error, absf(fleet.rockets[i].progress - expected))
				else:
					wrong_flight_frame = true
			elif landed == i:
				check(not fleet.rockets.has(i) and fleet.impacts.has(i), "Impact should replace its own airborne rocket on the contact frame")
				landed += 1
			elif now - f.impact_time > 0.241:
				wrong_impact_frame = wrong_impact_frame or fleet.impacts.has(i) or fleet.javelins.has([unit.id, i, f.launch_time])
			elif now - f.impact_time > 0.06 and now - f.impact_time < 0.10:
				wrong_impact_frame = wrong_impact_frame or not fleet.impacts.has(i)
		if landed == 4 and fleet.javelins.is_empty():
			break
	check(not early_flash and not wrong_flight_frame and max_progress_error < 0.001,
		"Physical flashes and shortened draw windows should follow the 1.5x timeline")
	check(not wrong_impact_frame, "Contact smoke and sparks should be present at 80 ms and released by 240 ms")
	check(flashes_at.size() == 4 and landed == 4, "All four tubes must launch and arrive")
	for i in range(1, flashes_at.size()):
		check(absf(flashes_at[i] - flashes_at[i-1] - launch_gap) < sample * 1.1 and origins[i].distance_to(origins[i-1]) > 0.08,
			"Successive physical tubes should preserve the salvo's 125 ms spacing")
	check(fleet.javelins.is_empty() and fleet.impacts.is_empty(), "Last impact should expire without leaving flight records or drawing smoke")
	game.sim.projectiles.clear()
	game.accumulator = 0.0
	step()

func check_javelin_flight() -> void:
	step(20)
	var shot := launch("javelin", 0, air_target, unit)
	var flight: Dictionary = fleet.javelins.get([shot.source_id, shot.strike, shot.launch_time], {})
	if flight.is_empty():
		check(false, "Expected a managed Javelin flight")
		return
	var old_goal: Vector2 = air_target.pos
	var start: Vector2 = fleet.javelin_position(flight, old_goal, 0.0)
	var first: Vector2 = fleet.javelin_position(flight, old_goal, 0.008)
	var bore: Vector3 = actor.cannon_sockets[0].global_basis.x
	check(start.direction_to(first).dot(Vector2(bore.x, bore.z).normalized()) > 0.95,
		"Missile should leave in the physical tube's direction before homing")
	check(flight.hit.is_empty(), "Launch should not create a contact explosion")
	# Keep the target in view while the launcher leaves the camera.
	game.camera_rect = Rect2(20, 0, 12, 20)
	step()
	check(not fleet.has_model(unit.id) and fleet.owns_javelin(shot), "Missile flight should survive culling its launcher")
	game.camera_rect = Rect2(0, 0, 32, 20)
	game.paused = true
	var frozen: float = fleet.render_time(game.sim, 0.0)
	host.sync(view, 0.1)
	check(is_equal_approx(frozen, fleet.render_time(game.sim, 0.0)) and fleet.owns_javelin(shot) and flight.hit.is_empty(),
		"Pause should retain the flight without advancing its clock or igniting its target")
	game.paused = false
	# Supply the authoritative tracking samples for a fighter crossing the original line.
	for i in 3:
		air_target.prev = air_target.pos
		air_target.pos += Vector2(0.0, 0.55)
		shot.goal = air_target.pos
		shot.pos = shot.origin.lerp(shot.goal, (float(game.sim.tick + 1) / 20.0 - shot.launch_time) / (shot.impact_time - shot.launch_time))
		step()
	var halfway: Vector2 = fleet._display_goal(flight, game.sim, fleet.render_time(game.sim, 0.5))
	check(halfway.is_equal_approx(air_target.prev.lerp(air_target.pos, 0.5)), "Tracking should interpolate the actual aircraft between tick samples")
	var tracked: Vector2 = fleet._display_goal(flight, game.sim, fleet.render_time(game.sim, 1.0))
	var incoming: Vector2 = fleet.javelin_position(flight, tracked, 0.82)
	check(incoming.distance_to(fleet.javelin_position(flight, old_goal, 0.82)) > 0.5,
		"The airborne missile should bend toward the fighter's updated location")
	check(Vector2(fleet.javelin_position(flight, shot.goal, 1.0)).is_equal_approx(air_target.pos), "Missile should reach the updated goal")
	var impact := {"type": "area_impact", "kind": "thor", "team": unit.team, "radius": shot.weapon.splash,
		"from": shot.goal, "to": shot.goal}
	game.sim.tick = ceili(shot.impact_time * 20.0)
	game.sim.projectiles.clear()
	check(flight.hit.is_empty(), "Reaching the scheduled arrival time alone must not create a blast")
	var unrelated := impact.duplicate()
	unrelated.from = old_goal + Vector2.RIGHT * 3.0
	unrelated.to = unrelated.from
	check(not fleet.accept_javelin_impact(unrelated, game) and flight.hit.is_empty(),
		"An unrelated area strike should keep its own effect and must not detonate this missile")
	check(fleet.accept_javelin_impact(impact, game), "The native contact event should transfer impact drawing to the missile")
	check(not flight.hit.is_empty() and Vector2(flight.hit.to).is_equal_approx(air_target.pos),
		"The blast should originate at the actual tracked contact")
	var hit_record: Dictionary = flight.hit.duplicate(true)
	check(fleet.accept_javelin_impact(impact, game) and flight.hit == hit_record and fleet.javelins.size() == 1,
		"Repeated observation should suppress a duplicate generic ring and preserve the first explosion")
	game.paused = true
	for i in 8:
		host.sync(view, 0.1)
	check(fleet.javelins.size() == 1 and flight.hit == hit_record, "Contact should remain frozen throughout a pause")
	game.paused = false
	step(20)
	check(fleet.javelins.is_empty(), "Finished contact should be released")
	var friendly_air := {"id": 32, "kind": "viking", "team": 0, "hp": 135, "prev": unit.pos, "pos": unit.pos}
	game.sim.by_id[friendly_air.id] = friendly_air
	var hidden_shot := launch("javelin", 1, friendly_air, opponent)
	check(fleet.owns_javelin(hidden_shot), "A visible opposing launcher should own its missile")
	game.hide_enemy = true
	step()
	check(not fleet.owns_javelin(hidden_shot) and fleet.javelins.is_empty(), "Fog should release the opposing shooter's private visual")
	game.sim.projectiles.clear()
	game.hide_enemy = false
	var pending := launch("javelin", 1, air_target, unit)
	host.reset()
	check(not fleet.owns_javelin(pending) and fleet.javelins.is_empty(), "Reset should clear pending flight and impact ownership")
	game.sim.projectiles.clear()
	step()
	actor = fleet.entries[unit.id].actor

func check_deferred_flashes() -> void:
	var before: Vector2 = unit.pos
	var shot := launch("javelin", 2, air_target, unit)
	var flight: Dictionary = fleet.javelins[[shot.source_id, 2, shot.launch_time]]
	var planned: Vector2 = flight.origin
	unit.pos += Vector2(0.65, 0.0)
	unit.prev = unit.pos
	present_at(flight.release_time + 0.037, 0.09)
	check(flight.origin.x > planned.x + 0.4 and absf(actor.fire_age[4] - 0.037) < 0.004,
		"A delayed frame should sample the moving launcher and advance its flare to the correct age")
	game.paused = true
	var age: float = actor.fire_age[4]
	for i in 4:
		host.sync(view, 0.08)
	check(is_equal_approx(actor.fire_age[4], age), "A pause should freeze the deferred muzzle flash")
	game.paused = false
	unit.pos = before
	unit.prev = before
	game.sim.projectiles.clear()
	step(16)
	var missed := launch("javelin", 3, air_target, unit)
	var late: Dictionary = fleet.javelins[[missed.source_id, 3, missed.launch_time]]
	present_at(late.release_time + 0.14, 0.1)
	var flash = actor.flashes[5]
	check(fleet.rockets.has(3) and (not is_instance_valid(flash) or not flash.is_visible_in_tree()),
		"Catching up during flight must not replay an expired launcher flash")
	game.sim.projectiles.clear()
	step(16)
	var old_target: Vector2 = air_target.pos
	air_target.prev = unit.pos + Vector2(0.3, 0.0)
	air_target.pos = air_target.prev
	var short_shot := launch("javelin", 0, air_target, unit)
	var short: Dictionary = fleet.javelins[[short_shot.source_id, 0, short_shot.launch_time]]
	check(absf(short.impact_time - short.release_time - 0.008) < 0.0001, "A native 12 ms shot should display 8 ms of travel")
	present_at((short.release_time + short.impact_time) * 0.5, 0.005)
	check(fleet.rockets.has(0) and absf(fleet.rockets[0].progress - 0.5) < 0.001,
		"A sub-tick flight should still draw a distinct midpoint at high frame rate")
	air_target.prev = old_target
	air_target.pos = old_target
	game.sim.projectiles.clear()
	game.accumulator = 0.0
	step(8)

func check_overlapping_launches() -> void:
	# A flyer directly above a Thor gives zero native travel time. Both the launch
	# and area contact arrive in the same tick, with no projectile in the final list.
	var saved: Vector2 = air_target.pos
	air_target.pos = unit.pos
	air_target.prev = unit.pos
	var time := (float(game.sim.tick) - 0.3) / float(game.sim.rules.tick_rate)
	for strike in 2:
		var data := {"type": "attack", "kind": "thor", "source_id": unit.id, "team": unit.team, "from": unit.pos,
			"to": air_target.pos, "mode": "javelin", "strike": strike, "time": time, "splash": 1.2, "projectile": false}
		event(data)
		check(fleet.owns_javelin_launch(data), "Coincident launch must suppress its generic attack trace")
	var first := {"type": "area_impact", "kind": "thor", "team": unit.team, "from": air_target.pos, "to": air_target.pos, "radius": 1.2}
	var second := first.duplicate()
	check(fleet.accept_javelin_impact(first, game) and fleet.accept_javelin_impact(first, game)
		and fleet.accept_javelin_impact(second, game), "Two simultaneous rockets should each claim their own contact once")
	var landed: Array = fleet.javelins.values()
	check(landed.size() == 2 and not landed[0].hit.is_empty() and not landed[1].hit.is_empty()
		and not is_same(landed[0].hit, landed[1].hit), "Distinct rockets hitting the same point should each explode")
	fleet.sample(view, game, time + 0.001)
	check(fleet.rockets.is_empty() and fleet.impacts.size() == 2, "Coincident arrivals should draw one contact each and zero frames of flight")
	air_target.prev = saved
	air_target.pos = saved
	step(10)
	check(fleet.javelins.is_empty(), "Same-tick effects should expire normally")

func visible_cannon_meshes(mech) -> Dictionary:
	var poses := {}
	for cannon in mech.cannons:
		var meshes: Array[Node] = cannon.find_children("*", "MeshInstance3D", true, false)
		if cannon is MeshInstance3D:
			meshes.append(cannon)
		for mesh in meshes:
			if mesh.is_visible_in_tree() and mesh.mesh != null:
				poses[mesh] = mesh.global_transform
	return poses

func check_deaths() -> void:
	game.hide_enemy = false
	step()
	check(fleet.has_model(opponent.id), "A revealed opponent should acquire its model")
	var folded = fleet.entries[opponent.id].actor
	check(is_zero_approx(folded.transform_progress), "Newly visible actor should start in its current high-impact pose")
	var deployed = actor
	check(is_equal_approx(deployed.transform_progress, 1.0), "Second dying actor should begin in Javelin mode")
	var meshes := visible_cannon_meshes(folded)
	meshes.merge(visible_cannon_meshes(deployed))
	var before: Dictionary = host.before_tick()
	game.sim.units.clear()
	game.sim.by_id.clear()
	for mech in [unit, opponent]:
		fleet.event({"type": "death", "id": mech.id, "team": mech.team, "pos": mech.pos}, before, game, host.clock)
	check(meshes.size() >= 8, "Both forms should contribute all four real barrel meshes to the wrecks")
	for mesh in meshes:
		check((folded.wreck.is_ancestor_of(mesh) or deployed.wreck.is_ancestor_of(mesh)) and mesh.global_transform.is_equal_approx(meshes[mesh]),
			"Destruction should carry the mesh's current folded or deployed pose into its wreck")
	step(1)
	check(not fleet.has_model(unit.id) and not fleet.has_model(opponent.id), "Death should retire both live actors")
	check(deployed.wreck_age > 0.0 and folded.wreck_age > 0.0, "Both air-weapon configurations should enter destruction")
	var wreck_age: float = deployed.wreck_age
	game.paused = true
	host.sync(view, 0.1)
	check(is_equal_approx(deployed.wreck_age, wreck_age) and is_equal_approx(folded.wreck_age, wreck_age),
		"Pausing should freeze both destruction sequences")
	game.paused = false
	step(10)
	check(not deployed.is_finished() and not folded.is_finished(), "Heavy wrecks should persist beyond the first explosion")
	for mesh in meshes:
		check(not mesh.global_transform.is_equal_approx(meshes[mesh]), "The original shoulder guns should separate during destruction")
	step(80)
	check(fleet.entries.is_empty() and deployed.is_queued_for_deletion() and folded.is_queued_for_deletion(),
		"After a finite destruction animation the viewport should release both wrecks")
	check(host.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "A completely empty viewport should sleep")

func run() -> void:
	game.sim.catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/units.json")).units
	game.sim.units = [unit, opponent, air_target]
	game.sim.by_id = {11: unit, 21: opponent, 31: air_target}
	host.game = game
	host.thors = RecordedFleet.new()
	root.add_child(host)
	host.sync(view, 0.025)
	fleet = host.thors
	if not fleet.has_model(unit.id):
		printerr("Thor rig unavailable in the shared viewport; import the GLB before this fixture")
		host.free()
		quit(1)
		return
	actor = fleet.entries[unit.id].actor
	check(actor.get_viewport() == host.viewport and host.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"A lone Thor should wake the same orthographic viewport used by aircraft")
	check(not fleet.has_model(opponent.id), "Unrevealed enemies should remain hidden")
	if actor.feet.size() != 2 or actor.cannons.size() != 4 or actor.cannon_sockets.size() != 4 or actor.arm_sockets.size() != 2:
		printerr("Expected two articulated feet, two arm sockets and four articulated launchers")
		host.free()
		quit(1)
		return
	check_walk()
	check_switches()
	game.hide_enemy = false
	check_arm_salvo("hammer")
	check_arm_salvo("high_impact")
	switch_to(1)
	step(12)
	check_arm_salvo("hammer")
	check_rocket_cadence()
	check_javelin_flight()
	check_deferred_flashes()
	check_overlapping_launches()
	check_walk()
	opponent.air_weapon_index = 0
	check_deaths()
	host.reset()
	check(fleet.entries.is_empty() and is_zero_approx(host.clock), "Scene reset should release actors and presentation time")
	host.free()
	if failures == 0:
		print("Thor visual smoke passed")
	quit(1 if failures else 0)
