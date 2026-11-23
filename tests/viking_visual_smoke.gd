## Exercises the rig and shared battlefield presentation with synthetic snapshots.
## No battle simulation is constructed. Run after importing the Viking rig:
## godot --headless -s tests/viking_visual_smoke.gd
extends SceneTree

const Fixture = preload("res://tests/mech_visual_smoke.gd")
const SharedView = preload("res://scripts/visuals/medivac_3d.gd")
const Viking = preload("res://scripts/visuals/viking_actor.gd")
const MissileFX = preload("res://scripts/visuals/viking_ordnance.gd")
const DT := 0.05
const VISIBLE := Rect2(0, 0, 40, 24)
const MISSILE := "anti_air_missile"
const CANNON := "gatling_cannon"
const ASSAULT := "viking_assault"

var host = SharedView.new()
var game := Fixture.FixtureGame.new()
var view := Fixture.FixtureView.new()
var fighter := {"id": 21, "team": 0, "kind": "viking", "hp": 180,
	"pos": Vector2(12, 8), "prev": Vector2(12, 8)}
var target := {"id": 50, "team": 1, "kind": "mutalisk", "hp": 100,
	"pos": Vector2(18, 8), "prev": Vector2(18, 8)}
var failures := 0
var next_projectile := 100


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)


func frames(count: int = 1) -> void:
	for i in count:
		game.sim.tick += 1
		host.sync(view, DT)


func render_time() -> float:
	return float(game.sim.tick - 1) * DT + game.accumulator


func deliver(event: Dictionary, before: Dictionary, layer = null) -> bool:
	host.events([event], before)
	var presentation = host.vikings if layer == null else layer
	return presentation.event(event, before, game, host.clock)


func spawn(layer = null) -> bool:
	game.sim.units = [fighter, target]
	game.sim.by_id = {fighter.id: fighter, target.id: target}
	host.sync(view, DT)
	if not host.has_model(fighter.id):
		check(false, "The shared viewport should instantiate the imported Viking rig")
		return false
	var presentation = host.vikings if layer == null else layer
	var actor: Node3D = presentation.entries[fighter.id].actor
	check(actor.get_viewport() == host.viewport, "The Viking should share the battlefield viewport")
	check(Vector2(actor.position.x, actor.position.z).distance_to(view.point(fighter.pos)) < 2.0,
		"The stationary Viking should be centered on its snapshot's map location")
	return true


func check_gait(actor) -> void:
	var neutral: Vector3 = actor.model_root.to_local(actor.feet[0].global_position) 		- actor.model_root.to_local(actor.feet[1].global_position)
	var fronts := {}
	var lifts := {}
	for i in 92:
		actor.position.x += 0.026
		actor.advance(0.025, 0.0, 0.026)
		var separation: Vector3 = actor.model_root.to_local(actor.feet[0].global_position) 			- actor.model_root.to_local(actor.feet[1].global_position) - neutral
		if absf(separation.x) > 0.035:
			fronts[signf(separation.x)] = true
		if absf(separation.y) > 0.028:
			lifts[signf(separation.y)] = true
	check(fronts.size() == 2 and lifts.size() == 2,
		"Both feet should take turns passing and rising in the assault gait")
	for i in 20:
		actor.advance(0.04, 0.0, 0.0)
	var standing: Transform3D = actor.feet[0].transform
	var sole_p: Vector3 = actor.model_root.to_local(actor.soles[0].global_position)
	var sole_n: Vector3 = actor.model_root.to_local(actor.soles[1].global_position)
	check(absf(sole_p.y - sole_n.y) < 0.04, "Both soles should reach the same ground height when idle")
	actor.advance(0.10, 0.0, 0.0)
	check(standing.is_equal_approx(actor.feet[0].transform), "Idle legs should settle after walking")


# Compare geometry in rig space so battlefield scale, yaw and hover do not skew dimensions.
func visible_bounds(actor, part: Node3D) -> AABB:
	var bounds := AABB()
	var to_model: Transform3D = actor.model_root.global_transform.affine_inverse()
	for mesh in live_parts(part, true):
		var box: AABB = (to_model * mesh.global_transform) * mesh.get_aabb()
		bounds = box if not bounds.has_volume() else bounds.merge(box)
	return bounds


func measure_rig(actor) -> Dictionary:
	var meshes := {}
	var to_model: Transform3D = actor.model_root.global_transform.affine_inverse()
	for mesh in live_parts(actor.model_root, true):
		var local: Transform3D = to_model * mesh.global_transform
		# The Gram matrix preserves the lengths and included angles of the part's axes.
		meshes[mesh] = {"resource": mesh.mesh, "metric": local.basis.transposed() * local.basis}
	return meshes


func same_rigid_parts(reference: Dictionary, measured: Dictionary) -> bool:
	if reference.size() != measured.size():
		return false
	for mesh in reference:
		if not measured.has(mesh) or measured[mesh].resource != reference[mesh].resource:
			return false
		var metric: Basis = measured[mesh].metric
		if mesh.get_blend_shape_count() != 0 or not metric.is_equal_approx(reference[mesh].metric):
			return false
	return true


func check_flight_shape(actor, ground: AABB, ground_wingspan: float, ground_foot: Vector3) -> void:
	var flying := visible_bounds(actor, actor.model_root)
	var nose := visible_bounds(actor, actor.joints.NoseTip)
	var wing_p := visible_bounds(actor, actor.joints.WingTipP)
	var wing_n := visible_bounds(actor, actor.joints.WingTipN)
	var wingspan := wing_p.end.z - wing_n.position.z
	check(ground.size.y - flying.size.y > .05 and flying.size.z - ground.size.z > .05,
		"The deployed fighter should be visibly flatter and wider than the ground mech")
	check(wingspan > ground_wingspan + .07 and wing_p.end.z > 0.0 and wing_n.position.z < 0.0,
		"The airframe should present two laterally extended physical wing tips")
	var foot_p: Vector3 = actor.model_root.to_local(actor.soles[0].global_position)
	var foot_n: Vector3 = actor.model_root.to_local(actor.soles[1].global_position)
	check(minf(foot_p.y, foot_n.y) > ground_foot.y + .10
			and maxf(absf(foot_p.z), absf(foot_n.z)) < wingspan * .35,
		"Both feet should retract beneath the fuselage and inside the wing span")
	var body: Vector3 = actor.model_root.to_local(actor.joints.Trunk.global_position)
	check(nose.has_volume() and nose.end.x > body.x + .09
			and nose.end.x > maxf(foot_p.x, foot_n.x),
		"The physical nose should project in front of the fuselage and the folded feet")


func check_preview_form(actor) -> void:
	actor.set_flight_progress(0.0)
	var open_foot: Vector3 = actor.model_root.to_local(actor.soles[0].global_position)
	var ground := visible_bounds(actor, actor.model_root)
	var ground_wingspan := visible_bounds(actor, actor.joints.WingTipP).end.z - visible_bounds(actor, actor.joints.WingTipN).position.z
	var assembled := measure_rig(actor)
	actor.set_flight_mode(true)
	for i in 13:
		actor.advance(0.04, 0.0, 0.0)
	var partial: float = actor.flight_progress
	var foot_mid: Transform3D = actor.feet[0].global_transform
	check(partial > 0.05 and partial < 0.9, "Takeoff should pass through an articulated middle pose")
	check(same_rigid_parts(assembled, measure_rig(actor)), "Mid-flight should retain the same rigid mesh parts and proportions")
	actor.set_flight_mode(false)
	check(is_equal_approx(partial, actor.flight_progress) and foot_mid.is_equal_approx(actor.feet[0].global_transform),
		"Reversing direction should begin from the current visible pose")
	actor.advance(0.04, 0.0, 0.0)
	check(actor.flight_progress < partial and actor.flight_progress > 0.0, "Interrupted takeoff should start to reverse continuously")
	for i in 40:
		actor.advance(0.04, 0.0, 0.0)
	check(is_zero_approx(actor.flight_progress), "Landing should finish on the assault endpoint")

	actor.set_flight_mode(true)
	for i in 45:
		actor.advance(0.04, 0.0, 0.0)
	check(is_equal_approx(actor.flight_progress, 1.0), "Takeoff should finish in the fighter endpoint")
	check(same_rigid_parts(assembled, measure_rig(actor)), "Flight should remain the same rigid model as the assault mech")
	check_flight_shape(actor, ground, ground_wingspan, open_foot)
	actor.set_flight_mode(false)
	for i in 35:
		actor.advance(0.04, 0.0, 0.0)
	check(is_zero_approx(actor.flight_progress) and open_foot.distance_to(actor.model_root.to_local(actor.soles[0].global_position)) < 0.02,
		"A full air-ground cycle should return the actual foot to its original stance")


func check_ground_cannons(actor) -> void:
	var seen := {}
	for heading in [-0.34, 0.45]:
		var aim := Vector2.from_angle(heading) * 5.0
		actor.fire_at(CANNON, aim)
		var side: int = actor.muzzle_index
		seen[side] = true
		var visible_burst := false
		for i in 8:
			actor.advance(0.02, heading, 0.0, heading)
			var flash: MeshInstance3D = actor.flashes[side]
			visible_burst = visible_burst or (is_instance_valid(flash) and flash.is_visible_in_tree())
		var bore: Vector3 = actor.muzzle_direction_world(CANNON, side)
		var direction := Vector2(bore.x, bore.z).normalized()
		check(visible_burst and direction.dot(aim.normalized()) > 0.92,
			"The selected assault cannon should visibly fire along its own aimed bore")
		for i in 26:
			actor.advance(0.02, heading, 0.0, heading)
		var flash: MeshInstance3D = actor.flashes[side]
		check(not is_instance_valid(flash) or not flash.is_visible_in_tree(), "An assault-cannon burst should expire")
	check(seen.size() == 2, "Successive assault-cannon bursts should use both physical ports")


func check_preview() -> void:
	var actor = Viking.new()
	host.scene.add_child(actor)
	if not actor.setup(host.vikings.model, host.vikings.bounds, 0.0, 0.0):
		check(false, "The imported single rig should also initialize in assault mode")
		actor.free()
		return
	check_gait(actor)
	check_preview_form(actor)
	check_ground_cannons(actor)
	actor.destroy()
	check(is_instance_valid(actor.wreck) and not actor.model_root.is_visible_in_tree(),
		"Assault destruction should replace the intact rig with a wreck")
	for i in 60:
		actor.advance(0.08, actor.heading, 0.0)
	check(actor.is_finished(), "Assault debris should expire")
	actor.free()


func launch_and_hit() -> int:
	var actor = host.vikings.entries[fighter.id].actor
	fighter.attack_target_id = target.id
	var weapon: Dictionary = game.sim.catalog.viking.attack_modes[0]
	var now := render_time()
	var reach: float = fighter.pos.distance_to(target.pos)
	var projectile := {"kind": fighter.kind, "source_id": fighter.id, "team": fighter.team, "id": next_projectile,
		"origin": fighter.pos, "pos": fighter.pos, "goal": target.pos, "target_id": target.id,
		"weapon": weapon.duplicate(true), "impact_skills": {}, "damage_multiplier": 1.0, "strike": 0,
		"launch_time": now, "impact_time": now + reach / float(weapon.delivery.speed)}
	next_projectile += 1
	game.sim.projectiles = [projectile]
	var attack := {"type": "attack", "kind": fighter.kind, "source_id": fighter.id, "team": fighter.team,
		"from": projectile.origin, "to": projectile.goal, "strike": 0, "splash": weapon.splash,
		"mode": weapon.id, "projectile": true, "time": now}
	var key := [fighter.id, 0, now]
	var before: Dictionary = host.before_tick()
	var original: Dictionary = projectile.duplicate(true)
	check(deliver(attack, before), "The 3D Viking should claim its real single-strike missile event")
	check(deliver(attack, before) and host.vikings.shots.size() == 1,
		"Redelivering an attack should preserve only one visual missile")
	host.sync(view, .015)
	if not host.vikings.shots.has(key):
		check(false, "The native projectile should have a matching visual flight")
		return -1
	var shot: Dictionary = host.vikings.shots[key]
	if not shot.released:
		frames()
	var side: int = shot.side
	var muzzle: Vector3 = actor.muzzle_world(MISSILE, side)
	check(shot.released and host.vikings.owns_projectile(projectile),
		"The rendered missile should release and suppress the generic projectile dot")
	check(projectile == original, "The renderer should leave the native projectile data untouched")
	check(view.point(shot.origin).distance_to(Vector2(muzzle.x, muzzle.z)) < 2.0,
		"The missile origin should be the selected physical rail on the rendered fighter")
	var origin: Vector2 = shot.origin
	var launch_axis: Vector2 = shot.direction
	var bore: Vector3 = actor.muzzle_direction_world(MISSILE, side)
	var beginning := MissileFX.flight_position(origin, projectile.goal, launch_axis, 0.01)
	check(origin.direction_to(beginning).dot(Vector2(bore.x, bore.z).normalized()) > 0.995,
		"The missile's first motion should follow the real rail even while the wing turns")
	check(not shot.hit, "Launching should leave the missile in flight")
	var flash: MeshInstance3D = actor.flashes[side]
	var other: MeshInstance3D = actor.flashes[1 - side]
	check(is_instance_valid(flash) and flash.is_visible_in_tree() and flash.global_position.distance_to(muzzle) < 0.3
			and (not is_instance_valid(other) or not other.is_visible_in_tree()),
		"Only the firing rail should flash at its actual socket")

	# The tracking service updates this same native dictionary during flight.
	target.prev = target.pos
	target.pos += Vector2(0.0, 0.8)
	projectile.goal = target.pos
	var expected: Vector2 = projectile.goal
	var midpoint := MissileFX.flight_position(origin, expected, launch_axis, 0.5)
	var approach := MissileFX.flight_position(origin, expected, launch_axis, 0.9)
	var arrival := MissileFX.flight_position(origin, expected, launch_axis, 1.0)
	check(approach.distance_to(expected) < midpoint.distance_to(expected) and arrival.is_equal_approx(expected),
		"The rendered missile should guide toward the moving native target after clearing the rail")
	while render_time() + DT < float(projectile.impact_time):
		frames()
	game.sim.projectiles.clear()
	var hit := {"type": "attack_hit", "id": target.id, "kind": fighter.kind, "mode": weapon.id,
		"team": fighter.team, "strike": 0, "time": projectile.impact_time, "amount": weapon.damage}
	deliver(hit, host.before_tick())
	check(shot.hit and Vector2(shot.hit_pos).is_equal_approx(expected),
		"The rendered impact should use the confirmed moving target's native contact point")
	frames(10)
	check(not host.vikings.owns_projectile(projectile), "The finished missile and contact should leave the draw layer")
	return side


func expected_takeoff() -> float:
	var elapsed := render_time() - float(fighter.born) * DT
	return clampf((elapsed - float(host.vikings.GROUND_LEAD)) / float(host.vikings.TAKEOFF_TIME), 0.0, 1.0)


func check_birth() -> void:
	var actor = host.vikings.entries[fighter.id].actor
	check(is_zero_approx(actor.flight_progress), "A just-born Viking should start in its assault silhouette")
	var phase: float = actor.walk_phase
	for i in 5:
		fighter.prev = fighter.pos
		fighter.pos += Vector2.RIGHT * 0.09
		frames()
	fighter.prev = fighter.pos
	check(is_zero_approx(actor.flight_progress) and not is_equal_approx(actor.walk_phase, phase),
		"A new fighter should walk during its grounded startup beat")
	frames(7)
	var progress: float = actor.flight_progress
	check(progress > 0.1 and progress < 0.6 and is_equal_approx(progress, expected_takeoff()),
		"Takeoff should derive its actual phase from the birth tick and interpolation")
	game.paused = true
	var hold: Transform3D = actor.feet[0].global_transform
	var clock: float = host.clock
	host.sync(view, 0.10)
	check(is_equal_approx(actor.flight_progress, progress) and is_equal_approx(clock, host.clock)
			and hold.is_equal_approx(actor.feet[0].global_transform), "Pause should freeze the takeoff and the feet")
	game.paused = false

	game.window = Rect2(90, 90, 40, 24)
	frames(3)
	check(not host.has_model(fighter.id) and not actor.is_visible_in_tree(), "Offscreen fighters should release their live renderers")
	game.window = VISIBLE
	frames()
	if not host.has_model(fighter.id):
		check(false, "A returning fighter should regain a viewport actor")
		return
	actor = host.vikings.entries[fighter.id].actor
	check(actor.flight_progress > progress and actor.flight_progress < 1.0 and is_equal_approx(actor.flight_progress, expected_takeoff()),
		"Reentry should recover the current takeoff phase without restarting")
	check(launch_and_hit() >= 0, "The real AA missile must still be visible during the birth presentation")
	frames(12)
	var flying = host.vikings.entries[fighter.id].actor
	check(is_equal_approx(flying.flight_progress, 1.0), "The takeoff should settle at the flight endpoint")
	game.window = Rect2(90, 90, 40, 24)
	frames()
	game.window = VISIBLE
	frames()
	check(host.has_model(fighter.id) and is_equal_approx(host.vikings.entries[fighter.id].actor.flight_progress, 1.0),
		"A completed takeoff should stay complete after leaving and reentering the camera")


func check_fog() -> void:
	fighter.team = 1
	target.team = 0
	var old = host.vikings.entries[fighter.id].actor
	game.fog = true
	frames()
	check(not host.has_model(fighter.id) and not old.is_visible_in_tree(), "Fog should remove the enemy's live fighter")
	var event := {"type": "attack", "kind": fighter.kind, "mode": MISSILE, "source_id": fighter.id,
		"team": fighter.team, "from": fighter.pos, "to": target.pos, "time": render_time(),
		"strike": 0, "splash": 0.0, "projectile": true}
	check(not deliver(event, host.before_tick()) and host.vikings.shots.is_empty(), "A hidden enemy must not expose a missile or muzzle flare")
	game.fog = false
	frames()
	check(host.has_model(fighter.id), "A revealed enemy should return to the shared viewport")
	fighter.team = 0
	target.team = 1


func live_parts(parent: Node, authored_only: bool = false) -> Dictionary:
	var parts := {}
	for mesh in parent.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh != null and mesh.is_visible_in_tree() and (not authored_only or mesh.owner != null):
			parts[mesh] = mesh.global_transform
	return parts


func check_wreck(label: String, layer = null) -> void:
	var presentation = host.vikings if layer == null else layer
	# Death arrives at the end of the snapshot; capture the render pose at that same time.
	var accumulator := game.accumulator
	game.accumulator = DT
	host.sync(view, 0.0)
	var actor = presentation.entries[fighter.id].actor
	var intact := live_parts(actor.model_root, true)
	var before: Dictionary = host.before_tick()
	var dead := {"type": "death", "id": fighter.id, "pos": fighter.pos, "team": fighter.team}
	game.sim.units = [target]
	game.sim.by_id.erase(fighter.id)
	deliver(dead, before, presentation)
	var wreck = actor.wreck
	game.accumulator = accumulator
	if not is_instance_valid(wreck):
		check(false, label + " death should create its posed wreck")
		return
	if fighter.kind == ASSAULT:
		check(is_zero_approx(wreck.airborne), "A native assault death should stay at ground height")
	deliver(dead, before, presentation)
	check(not host.has_model(fighter.id) and actor.wreck == wreck and presentation.entries.size() == 1,
		label + " death should retire the live model and create only one wreck")
	var pieces := live_parts(wreck)
	var preserved := 0
	for part in intact:
		if pieces.has(part) and Transform3D(pieces[part]).is_equal_approx(intact[part]):
			preserved += 1
	check(intact.size() >= 5 and preserved == intact.size() and not actor.model_root.is_visible_in_tree(),
		label + " wreck should capture the actual rigid parts at their latest pose")
	var age: float = actor.wreck_age
	game.paused = true
	host.sync(view, 0.1)
	check(is_equal_approx(actor.wreck_age, age), label + " wreck should freeze when paused")
	game.paused = false
	frames(13)
	var moved := 0
	for mesh in pieces:
		if is_instance_valid(mesh) and mesh.is_visible_in_tree() and not mesh.global_transform.is_equal_approx(pieces[mesh]):
			moved += 1
	check(moved >= 4, label + " should separate and move multiple visible pieces")
	frames(100)
	check(presentation.entries.is_empty() and actor.is_queued_for_deletion(),
		label + " wreck should be freed when its fragments finish fading")


func fractional_frame(delta: float) -> void:
	game.accumulator += delta
	if game.accumulator >= DT:
		game.accumulator -= DT
		game.sim.tick += 1
	host.sync(view, delta)


func check_native_walk(actor) -> void:
	var neutral: Vector3 = actor.model_root.to_local(actor.feet[0].global_position) 		- actor.model_root.to_local(actor.feet[1].global_position)
	var lead := {}
	var both_grounded := true
	for i in 48:
		fighter.prev = fighter.pos
		fighter.pos += Vector2.RIGHT * 0.077
		frames()
		var separation: Vector3 = actor.model_root.to_local(actor.feet[0].global_position) 			- actor.model_root.to_local(actor.feet[1].global_position) - neutral
		if absf(separation.x) > 0.035:
			lead[signf(separation.x)] = true
		both_grounded = both_grounded and is_zero_approx(actor.flight_progress)
	check(lead.size() == 2, "Native snapshot movement should pass the mech's feet in turn")
	check(both_grounded and render_time() - float(fighter.born) * DT > 1.5,
		"Even an old ground assault should keep its terrestrial pose")
	fighter.prev = fighter.pos
	frames(12)


func check_rotor(actor, side: int, before_rotor: Array[Basis], receivers: Array[Basis]) -> void:
	var previous: Basis = before_rotor[side]
	var initial_rate := 0.0
	var powered_rate := 0.0
	var eased := false
	var coasted := false
	var has_flash := false
	var fixed_housings := true
	var standby := true
	var pulse_count := 0
	var lit := false
	var settled := 0.0
	for i in 75:
		fractional_frame(.01)
		var current: Basis = actor.rotors[side].basis
		var delta := previous.orthonormalized().get_rotation_quaternion().angle_to(current.orthonormalized().get_rotation_quaternion())
		var flash: MeshInstance3D = actor.flashes[side]
		var shining := is_instance_valid(flash) and flash.is_visible_in_tree()
		if shining and not lit:
			pulse_count += 1
		if shining:
			if not has_flash:
				initial_rate = delta
			has_flash = true
			powered_rate = maxf(powered_rate, delta)
		elif has_flash and delta > 0.004:
			coasted = true
			eased = eased or delta < powered_rate * 0.75
		lit = shining
		fixed_housings = fixed_housings and actor.guns[side].basis.is_equal_approx(receivers[side])
		standby = standby and actor.rotors[1 - side].basis.is_equal_approx(before_rotor[1 - side])
		previous = current
		settled = delta
	check(has_flash and pulse_count == 1, "A single native gatling strike should trigger one muzzle pulse")
	check(powered_rate > initial_rate + .015 and coasted and eased and settled < .001,
		"The firing cluster should accelerate, coast after the flash, decelerate, then stop")
	check(standby and fixed_housings, "The other barrel cluster and firing gun's housing should keep their roll")


func ground_shot(actor, base: bool) -> int:
	var layer = host.assault_vikings
	var weapon: Dictionary = game.sim.catalog[ASSAULT].attack_modes[0]
	var aim := Vector2(4.0, 1.15 if base else -1.15)
	var goal := Vector2(fighter.pos) + aim
	target.prev = goal
	target.pos = goal if base else goal + Vector2(0, 0.25)
	var hit_at: Vector2 = goal if base else target.prev.lerp(target.pos, game.accumulator / DT)
	fighter.attack_target_id = -2 if base else target.id
	var initial: Array[Basis] = [actor.rotors[0].basis, actor.rotors[1].basis]
	var housings: Array[Basis] = [actor.guns[0].basis, actor.guns[1].basis]
	var now := render_time()
	var attack := {"type": "attack", "kind": fighter.kind, "source_id": fighter.id, "team": fighter.team,
		"from": fighter.pos, "to": hit_at, "strike": 0, "splash": 0.0, "mode": weapon.id,
		"projectile": false, "time": now}
	var before: Dictionary = host.before_tick()
	var key := [fighter.id, 0, now]
	check(deliver(attack, before, layer) and deliver(attack.duplicate(), before, layer),
		"The live assault renderer should own the instant native gatling event")
	if not layer.shots.has(key):
		check(false, "The native strike should allocate a single presentation record")
		return -1
	var shot: Dictionary = layer.shots[key]
	if not base:
		var hit := {"type": "attack_hit", "id": target.id, "kind": fighter.kind, "mode": weapon.id,
			"team": fighter.team, "strike": 0, "amount": weapon.damage, "time": now}
		deliver(hit, before, layer)
		deliver(hit.duplicate(), before, layer)
	fractional_frame(.01)
	var side: int = shot.side
	check(layer.shots.size() == 1 and shot.released and shot.hit and is_equal_approx(shot.launch_time, shot.impact_time),
		"The native instant attack should release and contact once without delayed flight")
	check(Vector2(shot.hit_pos).is_equal_approx(hit_at),
		"The instant contact should use the native " + ("base coordinates" if base else "victim position at the hit time"))
	var bore: Vector3 = actor.muzzle_world(CANNON, side)
	check(view.point(shot.origin).distance_to(Vector2(bore.x, bore.z)) < 2.0 and game.sim.projectiles.is_empty(),
		"The ground attack should use its physical cannon and leave native ordnance untouched")
	check_rotor(actor, side, initial, housings)
	check(layer.shots.is_empty(), "An instant gatling flash and contact should expire")
	return side


func check_native_assault() -> void:
	var layer = host.assault_vikings
	fighter.id += 1
	fighter.kind = ASSAULT
	fighter.hp = 220
	fighter.born = game.sim.tick
	fighter.pos = Vector2(12, 8)
	fighter.prev = fighter.pos
	target.kind = "rifle"
	if not spawn(layer):
		return
	var actor = layer.entries[fighter.id].actor
	check(is_zero_approx(actor.flight_progress), "A newly spawned assault uses the terrestrial stance")
	check_native_walk(actor)
	if actor.rotors.has(null):
		check(false, "Each cannon must have an independent physical rotor")
		return
	var first := ground_shot(actor, false)
	var second := ground_shot(actor, true)
	check(first >= 0 and second >= 0 and first != second, "Real consecutive gatling strikes should alternate barrel clusters")

	game.window = Rect2(90, 90, 40, 24)
	frames()
	check(not host.has_model(fighter.id) and not actor.is_visible_in_tree() and layer.entries.is_empty(),
		"An offscreen assault should drop its renderer without leaving a ghost")
	game.window = VISIBLE
	frames()
	if not host.has_model(fighter.id):
		check(false, "The camera should regain the assault renderer")
		return
	check(is_zero_approx(layer.entries[fighter.id].actor.flight_progress),
		"After camera reentry the ground variant should still have both feet deployed")
	check_wreck("Native assault Viking", layer)


func run() -> void:
	game.sim.catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/units.json")).units
	game.fog = false
	game.medivac_visual = host
	host.game = game
	root.add_child(host)
	if spawn():
		check_preview()
		check(is_equal_approx(float(host.vikings.entries[fighter.id].actor.flight_progress), 1.0),
			"A snapshot without birth metadata should start in full flight")
		var first := launch_and_hit()
		var second := launch_and_hit()
		check(first >= 0 and second >= 0 and first != second, "Consecutive AA launches should use opposite rails")
		check_fog()
		if host.has_model(fighter.id):
			check_wreck("Airborne Viking")
		fighter.id += 1
		fighter.born = game.sim.tick
		if spawn():
			check_birth()
		host.reset()
		fighter.id += 1
		fighter.born = game.sim.tick
		if spawn():
			frames(15)
			var progress: float = host.vikings.entries[fighter.id].actor.flight_progress
			check(progress > 0.1 and progress < 0.85, "The final wreck fixture should be halfway through launch")
			check_wreck("Taking-off Viking")
		check(game.sim.catalog.has(ASSAULT), "The native assault catalog entry must be available")
		if game.sim.catalog.has(ASSAULT):
			check_native_assault()
		check(host.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
			"An empty shared scene should stop rendering the viewport")
	host.reset()
	check(host.vikings.entries.is_empty() and host.vikings.shots.is_empty()
			and host.assault_vikings.entries.is_empty() and host.assault_vikings.shots.is_empty(),
		"Reset should clear both forms' models and ordnance")
	host.free()
	if failures == 0:
		print("Viking presentation smoke passed")
	quit(1 if failures else 0)
