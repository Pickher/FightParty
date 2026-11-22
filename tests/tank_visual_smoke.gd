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
	for item in actor.model_root.find_children("*", "MeshInstance3D", true, false):
		if item.mesh != null and item.is_visible_in_tree():
			poses[item] = item.global_transform
	return poses

# Observe the parts in model space so the battle camera's oblique projection
# and the unit's screen scale are not mistaken for deformation.
func rigid_mesh_state() -> Dictionary:
	var state := {}
	var world_to_model: Transform3D = actor.model_root.global_transform.affine_inverse()
	for part in actor.model_root.find_children("*", "MeshInstance3D", true, false):
		if not part.is_visible_in_tree() or part.mesh == null:
			continue
		var paint: Array[Material] = []
		for i in part.mesh.get_surface_count():
			paint.append(part.get_active_material(i))
		var pose: Transform3D = world_to_model * part.global_transform
		state[part] = {"mesh": part.mesh, "paint": paint, "pose": pose}
	return state

func remains_solid(initial: Dictionary, current: Dictionary) -> bool:
	if initial.size() != current.size():
		return false
	for part in initial:
		if not current.has(part) or part.get_blend_shape_count() > 0:
			return false
		var old: Dictionary = initial[part]
		var now: Dictionary = current[part]
		if now.mesh != old.mesh or now.paint != old.paint:
			return false
		var a: Basis = old.pose.basis
		var b: Basis = now.pose.basis
		# The Gram matrix preserves lengths and angles across every rigid rotation.
		if not (a.transposed() * a).is_equal_approx(b.transposed() * b):
			return false
	return true

func retraces_joints(outgoing: Dictionary, incoming: Dictionary) -> bool:
	for part in outgoing:
		if not incoming.has(part):
			return false
		var a: Transform3D = outgoing[part].pose
		var b: Transform3D = incoming[part].pose
		var separation := a.origin.distance_to(b.origin)
		var yaw := a.basis.orthonormalized().get_rotation_quaternion().angle_to(b.basis.orthonormalized().get_rotation_quaternion())
		if separation > 0.005 or yaw > 0.025:
			return false
	return true

# Identify the physical tips in each rigid bank's own lengthwise coordinate.
# Their signed hull-space Z positions then measure distance from the centerline.
func track_end_widths(track: Node3D, front: bool, side_sign: float) -> Vector2:
	var path := track.find_children(String(track.name) + "Path??", "Node3D", false, false)
	if path.is_empty():
		return Vector2.INF
	var inner: Node3D = path.front()
	var outer: Node3D = inner
	var outward := 1.0 if front else -1.0
	for point: Node3D in path:
		if point.position.x * outward < inner.position.x * outward:
			inner = point
		if point.position.x * outward > outer.position.x * outward:
			outer = point
	return Vector2(actor.hull.to_local(inner.global_position).z, actor.hull.to_local(outer.global_position).z) * side_sign

func mechanism_positions() -> Dictionary:
	var motion := {}
	for side in ["P", "N"]:
		var sign_side := 1.0 if side == "P" else -1.0
		for end in ["Front", "Rear"]:
			var track: Node3D = actor.joints["Track" + end + side]
			var axis: Vector3 = actor.hull.global_basis.inverse() * track.global_basis.x
			motion["Track" + end + side] = atan2(axis.z, axis.x) * sign_side * (1.0 if end == "Front" else -1.0)
			motion["Tips" + end + side] = track_end_widths(track, end == "Front", sign_side)
		var slide: Node3D = actor.joints["Slide" + side]
		motion["Slide" + side] = actor.hull.to_local(slide.global_position).z * sign_side
		var pad := actor.model_root.find_child("Contact" + side, true, false) as Node3D
		motion["Foot" + side] = actor.presentation.to_local(pad.global_position).y - actor.ground_height
		motion["Sole" + side] = lowest_pad_vertex(actor.joints["Foot" + side]) - actor.ground_height
		var cover: Node3D = actor.joints["Cover" + side]
		motion["Cover" + side] = atan2(cover.basis.y.z, cover.basis.y.y)
		for part in ["Rail", "Barrel"]:
			var joint: Node3D = actor.joints[part + side]
			motion[part + side] = actor.mount.to_local(joint.global_position).x
		var front: Node3D = actor.joints["BayFront" + side]
		var rear: Node3D = actor.joints["BayRear" + side]
		motion["Doors" + side] = actor.hull.to_local(front.global_position).x - actor.hull.to_local(rear.global_position).x
	var receiver: Node3D = actor.joints.CenterBarrel
	motion["Receiver"] = actor.mount.to_local(receiver.global_position).x
	motion["Tube"] = receiver.to_local(actor.siege_muzzle.global_position).x
	var mount_axis: Vector3 = actor.turret.global_basis.inverse() * actor.mount.global_basis.x
	motion["Elevation"] = atan2(mount_axis.y, Vector2(mount_axis.x, mount_axis.z).length())
	return motion

# Compare mechanical events by their measured halfway points, independent of easing.
func halfway(path: Array[Dictionary], part: String) -> int:
	var first: float = path.front()[part]
	var delta: float = path.back()[part] - first
	if absf(delta) > 0.001:
		for i in path.size():
			if (float(path[i][part]) - first) / delta >= 0.5:
				return i
	return -1

func travel_at(path: Array[Dictionary], part: String, phase: float) -> float:
	var at := roundi(phase * float(path.size() - 1))
	var start: float = path.front()[part]
	var end: float = path.back()[part]
	return inverse_lerp(start, end, float(path[at][part]))

func check_mechanisms(path: Array[Dictionary]) -> void:
	var first: Dictionary = path.front()
	var last: Dictionary = path.back()
	check((last.CoverP - first.CoverP) * (last.CoverN - first.CoverN) < 0.0,
		"The two covers should hinge away from the bore on opposite sides")
	var receiver_frame := halfway(path, "Receiver")
	check(last.Elevation - first.Elevation > 0.12 and last.Receiver > first.Receiver + 0.04
			and last.Tube > first.Tube + 0.02 and halfway(path, "Tube") > receiver_frame,
		"The gun should elevate and the tube should telescope forward within the deployed receiver")
	check(travel_at(path, "Elevation", 0.55) < 0.04 and travel_at(path, "Receiver", 0.60) < 0.03
			and travel_at(path, "Tube", 0.85) < 0.80 and travel_at(path, "Tube", 0.95) > 0.97,
		"The planted chassis should hold while the mount elevates and the siege tube finishes its late extension")
	for side in ["P", "N"]:
		for end in ["Front", "Rear"]:
			var name: String = "Track" + end + side
			check(last[name] - first[name] > 0.18 and travel_at(path, name, 0.20) < 0.07
					and travel_at(path, name, 0.50) > 0.97, name + " should swing out between the bay opening and pad contact")
			var tips: String = "Tips" + end + side
			var parked: Vector2 = first[tips]
			var braced: Vector2 = last[tips]
			check(braced.x >= 0.0 and braced.x < parked.x - 0.02 and braced.y > parked.y + 0.10,
				name + " should pull its inner tread tip toward the hull centerline while its outer tip swings away")
		var slide: String = "Slide" + side
		var foot: String = "Foot" + side
		var doors: String = "Doors" + side
		var door_frame := halfway(path, doors)
		var slide_frame := halfway(path, slide)
		var grounded_frame := halfway(path, foot)
		check(last[doors] > first[doors] + 0.02 and last[slide] > first[slide] + 0.025,
			"Both bay doors should slide apart and expose their outrigger")
		check(travel_at(path, doors, 0.25) > 0.80 and travel_at(path, slide, 0.25) > 0.50
				and door_frame >= 0 and slide_frame > door_frame and grounded_frame > slide_frame
				and first[foot] > last[foot] + 0.02 and absf(last[foot]) < 0.025,
			"The carriage should extend through its open doors before the stabilizer pad lowers to ground")
		var sole: String = "Sole" + side
		var above_ground := true
		var holds_ground := true
		for i in path.size():
			above_ground = above_ground and float(path[i][sole]) >= -0.001
			if float(i) / (path.size() - 1) >= 0.57:
				holds_ground = holds_ground and absf(float(path[i][sole])) < 0.002
		check(above_ground and holds_ground and path[roundi(0.50 * (path.size() - 1))][sole] > 0.003,
			"The actual shoe should clear the ground on approach, plant near 55%, then remain planted through gun deployment")
		var shell: String = "Barrel" + side
		var rail: String = "Rail" + side
		var cover: String = "Cover" + side
		check(first[shell] - last[shell] > 0.02 and absf(last[cover] - first[cover]) > 0.20
				and travel_at(path, cover, 0.40) < 0.015 and travel_at(path, cover, 0.60) > 0.50,
			"The mobile barrel should retract and its rigid cover should hinge open")
		var rail_frame := halfway(path, rail)
		check(last[rail] > first[rail] + 0.02
				and halfway(path, cover) < rail_frame and halfway(path, shell) < rail_frame and receiver_frame > halfway(path, cover),
			"The rails and siege bore should advance after the mobile shrouds clear their path")

func check_rigid_cycle() -> void:
	for side in ["P", "N"]:
		for prefix in ["TrackFront", "TrackRear", "Slide", "BayFront", "BayRear", "Cover", "Barrel", "Rail"]:
			if not actor.joints.has(prefix + side):
				check(false, "Expected rigid mechanical joint " + prefix + side)
				return
	var skill: Dictionary = game.sim.catalog.mortar.skills.deployment
	var samples := 30
	var states: Array[Dictionary] = [rigid_mesh_state()]
	var motion: Array[Dictionary] = [mechanism_positions()]
	var solid := not states[0].is_empty()
	actor.set_deployed(true)
	for i in samples:
		actor.advance(float(skill.deploy_seconds) / samples, actor.heading, 0.0, actor.turret_heading)
		var current := rigid_mesh_state()
		solid = solid and remains_solid(states[0], current)
		states.append(current)
		motion.append(mechanism_positions())
	check_mechanisms(motion)
	check(is_equal_approx(actor.deployment_progress, 1.0), "Timed deployment should reach the siege pose")
	actor.set_deployed(false)
	var reversed := true
	for i in samples:
		actor.advance(float(skill.pack_seconds) / samples, actor.heading, 0.0, actor.turret_heading)
		var current := rigid_mesh_state()
		solid = solid and remains_solid(states[0], current)
		reversed = reversed and retraces_joints(states[samples - i - 1], current)
	check(solid, "Deployment and packing must retain the same visible rigid geometry and surfaces")
	check(reversed and is_zero_approx(actor.deployment_progress), "Packing should reverse the physical joint sequence to its mobile pose")

func lowest_pad_vertex(foot: Node3D) -> float:
	var lowest := INF
	var world_to_facing: Transform3D = actor.facing.global_transform.affine_inverse()
	for shoe in foot.find_children("*", "MeshInstance3D", true, false):
		if not shoe.is_visible_in_tree() or shoe.mesh == null:
			continue
		var space: Transform3D = world_to_facing * shoe.global_transform
		for surface in shoe.mesh.get_surface_count():
			var vertices: PackedVector3Array = shoe.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				lowest = minf(lowest, (space * vertex).y)
	return lowest

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
	transition("deploying", deploy_seconds)
	var duration := roundi(deploy_seconds / DT)
	frames(duration)
	tank.siege_state = "deployed"
	frames()
	check(is_equal_approx(actor.deployment_progress, 1.0), "Complete deployment should reach the siege endpoint")
	for sign_name in ["P", "N"]:
		var pad: Node3D = actor.model_root.find_child("Contact" + sign_name, true, false)
		var pad_height: float = actor.presentation.to_local(pad.global_position).y
		var sole := lowest_pad_vertex(actor.joints["Foot" + sign_name])
		check(absf(pad_height - actor.ground_height) < 0.025 and absf(sole - actor.ground_height) < 0.025,
			"The physical underside of each load-bearing shoe should reach the ground plane")

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
	check(fragments.size() == live.size() and fragments.size() >= 5, state + " death should preserve every visible rigid part in the wreck")
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
		check_rigid_cycle()
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
		tank.id += 1
		if spawn():
			var skill: Dictionary = game.sim.catalog.mortar.skills.deployment
			transition("deploying", skill.deploy_seconds)
			frames(roundi(skill.deploy_seconds / DT * 0.7))
			transition("packing", skill.pack_seconds)
			frames(2)
			check(actor.deployment_progress > 0.1 and actor.deployment_progress < 0.9, "The interrupted tank should retain its articulated pose before destruction")
			check_wreck("mid-packing")
		check(host.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "An empty battlefield should release the shared render target")
	host.reset()
	host.free()
	if failures == 0:
		print("Tank presentation smoke passed")
	quit(1 if failures else 0)
