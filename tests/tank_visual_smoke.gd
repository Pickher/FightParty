## Real battlefield rendering with synthetic snapshots and weapon events only.
extends SceneTree

const Fixture = preload("res://tests/mech_visual_smoke.gd")
const SharedView = preload("res://scripts/visuals/medivac_3d.gd")
const DT := 0.05
const VISIBLE_RECT := Rect2(0, 0, 40, 24)

var host = SharedView.new()
var game := Fixture.FixtureGame.new()
var view := Fixture.FixtureView.new()
var tank := {"id": 24, "kind": "mortar", "team": 0, "hp": 175,
	"prev": Vector2(10, 8), "pos": Vector2(10, 8), "siege_state": "mobile", "siege_until_tick": 0}
var target := {"id": 93, "team": 1, "kind": "rifle", "hp": 45, "pos": Vector2.ZERO, "prev": Vector2.ZERO}
var actor
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func frames(count: int = 1) -> void:
	for i in count:
		game.sim.tick += 1
		host.sync(view, DT)

func transition(state: String, duration: float) -> void:
	var before: Dictionary = host.before_tick()
	game.sim.tick += 1
	tank.siege_state = state
	tank.siege_until_tick = game.sim.tick + roundi(duration / DT)
	host.events([], before)
	host.sync(view, DT)

func check_tracks_and_aim() -> void:
	var left: float = actor.track_distance[0]
	var right: float = actor.track_distance[1]
	for i in 8:
		tank.prev = tank.pos
		tank.pos += Vector2(0.1, 0)
		frames()
	check(actor.track_distance[0] > left and actor.track_distance[1] > right,
		"Both tracks should move forward with the actual travel")
	var center: Vector2 = view.point(tank.prev.lerp(tank.pos, game.accumulator / DT))
	check(Vector2(actor.position.x, actor.position.z).is_equal_approx(center), "Tank should use the interpolated map position")
	tank.prev = tank.pos
	frames(4)
	left = actor.track_distance[0]
	right = actor.track_distance[1]
	frames(4)
	check(is_equal_approx(left, actor.track_distance[0]) and is_equal_approx(right, actor.track_distance[1]),
		"A parked tank should stop both tracks")

	# Targeting to the flank should traverse the turret without dragging the hull.
	var parked: float = actor.heading
	target.pos = tank.pos + Vector2(0, 5)
	target.prev = target.pos
	game.sim.by_id[target.id] = target
	game.fog = false
	tank.locked_target_id = target.id
	frames(25)
	check(absf(angle_difference(actor.turret_heading, PI * 0.5)) < 0.15 and is_equal_approx(actor.heading, parked),
		"The turret should aim across the stationary hull")
	target.pos = tank.pos + Vector2.RIGHT * 5.0
	target.prev = target.pos
	frames(25)

func mesh_poses() -> Dictionary:
	var poses := {}
	for item in actor.find_children("*", "MeshInstance3D", true, false):
		if item.mesh != null and item.is_visible_in_tree():
			poses[item] = item.global_transform
	return poses

func support_poses() -> Dictionary:
	var poses := {}
	for label in ["TrackFrontP", "TrackFrontN", "FootP", "FootN"]:
		var joint := actor.find_child(label, true, false) as Node3D
		if joint != null:
			for mesh in joint.find_children("*", "MeshInstance3D", true, false):
				if mesh.mesh != null and mesh.is_visible_in_tree():
					poses[joint] = joint.global_transform
					break
	return poses

func check_deployment() -> void:
	var data: Dictionary = game.sim.catalog.mortar.skills.deployment
	var deploy_seconds: float = data.deploy_seconds
	var pack_seconds: float = data.pack_seconds
	transition("deploying", deploy_seconds)
	frames(10)
	var interrupted: float = actor.deployment_progress
	check(interrupted > 0.20 and interrupted < 0.5, "Deployment should reach an intermediate pose on the skill clock")
	game.paused = true
	host.sync(view, 0.1)
	check(is_equal_approx(actor.deployment_progress, interrupted), "Pause must hold the deployment pose")
	game.paused = false
	transition("packing", pack_seconds)
	frames()
	var first: float = actor.deployment_progress
	check(first <= interrupted + 0.035 and first >= interrupted - 0.075,
		"An interrupted deployment should pack from the current pose, without jumping to fully deployed")
	frames(4)
	check(actor.deployment_progress < first, "Packing should begin folding the partially extended armor")
	game.window = Rect2(80, 80, 40, 24)
	frames()
	check(not host.has_model(tank.id), "An offscreen tank should release its renderer")
	game.window = VISIBLE_RECT
	frames()
	if not host.has_model(tank.id):
		check(false, "The tank should regain a renderer when it returns to view")
		return
	actor = host.tanks.entries[tank.id].actor
	check(actor.deployment_progress <= first and actor.deployment_progress > 0.0, "Reentry should recover the interrupted packing pose")
	frames(roundi(pack_seconds / DT))
	tank.siege_state = "mobile"
	frames()
	check(is_zero_approx(actor.deployment_progress), "Packing should finish at the mobile endpoint")
	var mobile := support_poses()
	transition("deploying", deploy_seconds)
	var duration := roundi(deploy_seconds / DT)
	frames(floori(duration * 0.5))
	var middle := support_poses()
	frames(duration - floori(duration * 0.5))
	tank.siege_state = "deployed"
	frames()
	check(is_equal_approx(actor.deployment_progress, 1.0), "Complete deployment should reach the siege endpoint")
	var deployed := support_poses()
	var articulated := 0
	for part in mobile:
		if middle.has(part) and deployed.has(part) and not mobile[part].is_equal_approx(middle[part]) and not middle[part].is_equal_approx(deployed[part]):
			articulated += 1
	for sign_name in ["P", "N"]:
		var pad: Node3D = actor.model_root.find_child("Contact" + sign_name, true, false)
		var pad_height: float = actor.presentation.to_local(pad.global_position).y
		check(absf(pad_height - actor.ground_height) < 0.025, "A deployed stabilizer pad should reach the ground plane")
	check(articulated == 4, "Both real front track banks and both stabilizer feet should articulate through deployment")

func shoot(mode: String) -> void:
	var catalog: Dictionary = game.sim.catalog.mortar
	var siege: bool = mode == catalog.skills.deployment.mode_id
	var weapon: Dictionary = catalog.attack_modes[1 if siege else 0]
	var time := (float(game.sim.tick) - 1.0 + game.accumulator / DT) * DT
	var goal: Vector2 = tank.pos + Vector2.RIGHT * 5.0
	var launch := {"type": "attack", "kind": tank.kind, "mode": mode, "from": tank.pos,
		"to": goal, "team": tank.team, "source_id": tank.id, "projectile": false,
		"time": time, "strike": 0, "splash": weapon.splash}
	var before: Dictionary = host.before_tick()
	var rest: Dictionary = {}
	for barrel in [actor.barrels[0], actor.barrels[1], actor.joints.CenterBarrel]:
		rest[barrel] = barrel.position
	var effect_copy := launch.duplicate(true)
	if not host.tanks.event(launch, before, game, host.clock) or host.tanks.shots.is_empty():
		check(false, mode + " should own the actual launch on the battlefield")
		return
	var shot: Dictionary = host.tanks.shots.back()
	var firing_barrel: Node3D = actor.joints.CenterBarrel if siege else actor.barrels[actor.muzzle_index]
	var muzzle: Vector3 = actor.muzzle_world(mode)
	var ray: Vector3 = actor.muzzle_direction_world(mode)
	var axis := Vector2(ray.x, ray.z).normalized()
	check(axis.dot(view.point(shot.origin).direction_to(view.point(goal))) > 0.995, "The visible bore should point at the actual target")
	check(view.point(shot.origin).distance_to(Vector2(muzzle.x, muzzle.z)) < 0.15,
		mode + " effects must start at the projected animated bore")
	check(not shot.hit, "Contact should wait for a native hit or area event")
	host.tanks.event(launch, before, game, host.clock)
	check(host.tanks.shots.size() == 1, "Redelivery should not create a second recoil or muzzle burst")
	if siege:
		var contact := {"type": "area_impact", "kind": tank.kind, "team": tank.team,
			"from": goal, "to": goal, "radius": weapon.splash}
		check(host.tanks.event(contact, before, game, host.clock), "The siege burst should claim its actual area contact")
	else:
		var hit := {"type": "attack_hit", "kind": tank.kind, "mode": mode, "team": tank.team,
			"id": target.id, "strike": 0, "amount": weapon.damage, "time": time}
		host.tanks.event(hit, before, game, host.clock)
	check(shot.hit and shot.goal == goal and shot.at == host.clock, "A zero-flight cannon should contact the actual goal on the firing frame")
	var max_recoil := 0.0
	var flashed := false
	for i in 5:
		host.sync(view, 0.01)
		flashed = flashed or (is_instance_valid(actor.flash) and actor.flash.is_visible_in_tree())
		max_recoil = maxf(max_recoil, Vector3(rest[firing_barrel]).distance_to(firing_barrel.position))
		for barrel in rest:
			if barrel != firing_barrel:
				check(barrel.position.is_equal_approx(rest[barrel]), "Only the active barrel should recoil in its mount")
		game.accumulator += 0.01
		if game.accumulator >= DT:
			game.sim.tick += 1
			game.accumulator -= DT
	check(flashed and max_recoil > 0.005, mode + " should recoil and flash at its own physical barrel")
	check(launch == effect_copy and game.sim.projectiles.is_empty(), "Cannon presentation should preserve the native instantaneous shot")
	frames(15)
	check(firing_barrel.position.is_equal_approx(rest[firing_barrel]) and (not is_instance_valid(actor.flash) or not actor.flash.is_visible_in_tree()),
		mode + " should return its barrel to rest and extinguish the muzzle flash")

func check_visibility() -> void:
	game.fog = true
	tank.team = 1
	frames()
	check(not host.has_model(tank.id), "Fog should release a previously visible tank immediately")
	var event := {"type": "attack", "kind": "mortar", "source_id": tank.id, "mode": "mobile_cannon",
		"strike": 0, "team": 1, "from": tank.pos, "to": target.pos, "splash": 0.0,
		"projectile": false, "time": game.sim.tick * DT}
	check(not host.tanks.event(event, host.before_tick(), game, host.clock),
		"A hidden cannon must not be exposed by a tank muzzle flash")
	tank.team = 0
	frames()
	check(host.has_model(tank.id), "A revealed tank should return to the shared viewport")

func check_wreck(state: String) -> void:
	# Capture real renderers before the unit disappears, including its currently folded supports.
	var live := mesh_poses()
	var snapshot: Dictionary = host.before_tick()
	var death := {"type": "death", "id": tank.id, "pos": tank.pos, "team": tank.team}
	game.sim.units.clear()
	game.sim.by_id.clear()
	host.tanks.event(death, snapshot, game, host.clock)
	var wreck = actor.wreck
	if not is_instance_valid(wreck):
		check(false, state + " death should start a tank wreck")
		return
	check(not host.has_model(tank.id), "A dying tank should give up its live renderer")
	var fragments := {}
	for part in live:
		if wreck.is_ancestor_of(part):
			fragments[part] = live[part]
			check(part.global_transform.is_equal_approx(live[part]), state + " death should start from the current part pose")
	check(fragments.size() >= 5, state + " death should release multiple original tank parts")
	frames(12)
	var scattered := 0
	for part in fragments:
		if part.is_visible_in_tree() and not part.global_transform.is_equal_approx(fragments[part]):
			scattered += 1
	check(scattered >= 4, state + " should scatter the actual wheels, armor and weapon")
	var age: float = actor.wreck_age
	game.paused = true
	host.sync(view, 0.1)
	check(is_equal_approx(actor.wreck_age, age), "Pause should freeze the wreck")
	game.paused = false
	frames(100)
	check(host.tanks.entries.is_empty() and actor.is_queued_for_deletion(), state + " wreck should be released after it fades")

func spawn() -> bool:
	game.sim.units = [tank]
	game.sim.by_id = {tank.id: tank}
	host.sync(view, DT)
	if not host.has_model(tank.id):
		check(false, "Expected the uploaded tank rig in the shared battlefield viewport")
		return false
	actor = host.tanks.entries[tank.id].actor
	return true

func run() -> void:
	game.sim.catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/units.json")).units
	host.game = game
	game.medivac_visual = host
	root.add_child(host)
	if spawn():
		check(actor.get_viewport() == host.viewport, "A tank should use the shared battlefield viewport")
		check_tracks_and_aim()
		shoot("mobile_cannon")
		var first: int = actor.muzzle_index
		shoot("mobile_cannon")
		check(first != actor.muzzle_index, "Consecutive mobile cannon strikes should use alternating barrels")
		check_deployment()
		shoot("siege_cannon")
		check_wreck("deployed")
		tank.siege_state = "mobile"
		tank.siege_until_tick = 0
		tank.id += 1
		if spawn():
			check_visibility()
			actor = host.tanks.entries[tank.id].actor
			check_wreck("mobile")
		check(host.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "An empty battlefield should release the shared render target")
	host.reset()
	host.free()
	if failures == 0:
		print("Tank presentation smoke passed")
	quit(1 if failures else 0)
