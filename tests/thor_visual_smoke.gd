## Exercises the game viewport with synthetic unit snapshots and launch events.
## After resource import: godot --headless --path . --script tests/thor_visual_smoke.gd
extends SceneTree

const Aircraft = preload("res://scripts/visuals/medivac_3d.gd")

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
var actor

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

func check_salvo(mode: String, strikes: int) -> void:
	var launchers: Array = actor.arms if mode == "hammer" else actor.cannons
	var sockets: Array = actor.arm_sockets if mode == "hammer" else actor.cannon_sockets
	var offsets: Array[Vector2] = []
	var physical_sides: Array[float] = []
	for i in strikes:
		step(8)
		var weapon: Node3D = launchers[i]
		var at_rest := weapon.position
		var other: Node3D = launchers[i ^ 1]
		var opposite := other.position
		var launch_time: float = float(game.sim.tick) / 20.0
		var shot := {"id": 1000 + int(game.sim.tick), "kind": "thor", "source_id": unit.id, "team": unit.team, "launch_time": launch_time,
			"impact_time": launch_time + 0.4, "strike": i, "origin": unit.pos, "pos": unit.pos,
			"goal": opponent.pos, "target_id": opponent.id, "weapon": {"id": mode}}
		game.sim.projectiles = [shot]
		var shot_snapshot := shot.duplicate(true)
		event({"type": "attack", "kind": "thor", "source_id": unit.id, "team": unit.team,
			"from": unit.pos, "to": opponent.pos, "mode": mode, "strike": i, "time": launch_time, "projectile": true})
		var muzzle: Node3D = sockets[i]
		var marker := Vector2(muzzle.global_position.x, muzzle.global_position.z)
		var origin: Vector2 = (marker - view.point(unit.pos)) / view.pixels(1.0)
		var actual: Vector2 = fleet.projectile_offset(shot, launch_time)
		offsets.append(actual)
		physical_sides.append(actor.trunk.to_local(muzzle.global_position).z)
		check(actual.distance_to(origin) < 0.025, "Launch should inherit the rendered muzzle origin for %s strike %d" % [mode, i])
		check(Vector2(fleet.projectile_offset(shot, launch_time + 0.2)).is_equal_approx(actual * 0.5)
			and Vector2(fleet.projectile_offset(shot, launch_time + 0.4)).is_zero_approx(),
			"Projectile correction should converge to the native impact point")
		var flash = actor.flashes[i if mode == "hammer" else i + 2]
		check(is_instance_valid(flash) and flash.is_visible_in_tree(), "A launch event should illuminate the selected socket")
		if is_instance_valid(flash):
			check(flash.global_position.distance_to(muzzle.global_position) < 0.01, "Flash should originate at the physical muzzle")
		host.sync(view, 0.025)
		check(weapon.position.distance_to(at_rest) > 0.005 and other.position.is_equal_approx(opposite),
			"Only the selected weapon should slide back on its mount")
		check(shot_snapshot == shot, "Corrections should leave the authoritative projectile untouched")
	for i in range(1, strikes):
		check(physical_sides[i-1] * physical_sides[i] < 0.0 and offsets[i-1].distance_to(offsets[i]) > 0.08,
			"Consecutive %s shots should alternate physical sides and projected origins" % mode)
	game.sim.projectiles.clear()
	step(8)

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
	game.sim.units = [unit, opponent]
	game.sim.by_id = {11: unit, 21: opponent}
	host.game = game
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
	check_salvo("hammer", 2)
	check_salvo("high_impact", 2)
	switch_to(1)
	step(12)
	check_salvo("javelin", 4)
	check_walk()
	opponent.air_weapon_index = 0
	check_deaths()
	host.reset()
	check(fleet.entries.is_empty() and is_zero_approx(host.clock), "Scene reset should release actors and presentation time")
	host.free()
	if failures == 0:
		print("Thor visual smoke passed")
	quit(1 if failures else 0)
