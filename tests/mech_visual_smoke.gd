## Drives the presentation actors with snapshots; no battle simulation is constructed.
extends SceneTree

const SharedView = preload("res://scripts/visuals/medivac_3d.gd")
const HellionLayer = preload("res://scripts/visuals/hellion_layer.gd")
const Hellbat = preload("res://scripts/visuals/hellbat_actor.gd")
const MECH_RIG := "res://assets/models/hellbat_mech/hellbat_mech_rig.glb"
const CAR_RIG := "res://assets/models/hellbat/hellion_rig.glb"

class FixtureGame:
	extends RefCounted
	var started := true
	var paused := false
	var backgrounded := false
	var help_open := false
	var setup_open := false
	var economy_open := false
	var formation_panel := {"opened": false}
	var medivac_visual
	var accumulator := 0.025
	var fog := true
	var window := Rect2(0, 0, 40, 24)
	var sim := {"tick": 20, "finished": false, "rules": {"tick_rate": 20}, "units": [],
		"by_id": {}, "active_beams": [], "projectiles": [], "catalog": {}}

	func _hidden_team(team: int) -> bool:
		return fog and team == 1

	func _camera_rect() -> Rect2:
		return window

class FixtureView:
	extends RefCounted

	func viewport_size() -> Vector2:
		return Vector2(800, 480)

	func point(pos: Vector2) -> Vector2:
		return pos * 20.0

	func pixels(distance: float) -> float:
		return distance * 20.0

var host = SharedView.new()
var game := FixtureGame.new()
var view := FixtureView.new()
var failures := 0
var shooter := {"id": 7, "kind": "marauder", "team": 0, "hp": 125,
	"prev": Vector2(12, 8), "pos": Vector2(12, 8)}
var enemy := {"id": 8, "kind": "marauder", "team": 1, "hp": 125,
	"prev": Vector2(17, 8), "pos": Vector2(17, 8)}
var aircraft := {"id": 9, "kind": "viking", "team": 1, "hp": 135,
	"prev": Vector2(16, 9), "pos": Vector2(16, 9)}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func frame() -> void:
	game.sim.tick += 1
	host.sync(view, 0.05)

func check_gait(actor, label: String) -> void:
	# Move the normal actor root by the same footprint distance that its legs receive.
	var start: Transform3D = actor.global_transform
	var stride := 0.021
	var standing_streak := [0, 0]
	var longest_stance := [0, 0]
	var height_gap := 0.0
	var lead := {}
	for i in 85:
		var old := [actor.feet[0].global_position, actor.feet[1].global_position]
		var travel: Vector3 = start.basis.x * stride
		actor.global_position += travel
		actor.advance(0.025, 0.0, stride)
		if i < 16:
			continue
		var left: Vector3 = actor.to_local(actor.feet[0].global_position)
		var right: Vector3 = actor.to_local(actor.feet[1].global_position)
		if absf(left.x - right.x) > .035:
			lead[signf(left.x - right.x)] = true
		height_gap = maxf(height_gap, absf(left.y - right.y))
		for foot in 2:
			var moved := absf((Vector3(actor.feet[foot].global_position) - Vector3(old[foot])).dot(travel.normalized()))
			standing_streak[foot] = standing_streak[foot] + 1 if moved < travel.length() * .29 else 0
			longest_stance[foot] = maxi(longest_stance[foot], standing_streak[foot])
	check(lead.size() == 2 and height_gap > .035, label + " should lift and pass alternating feet")
	check(longest_stance.min() >= 3, label + " should plant each foot while its body advances")
	for i in 12:
		actor.advance(.04, 0.0, 0.0)
	var initial: float = actor.heading
	var turn_heading := 2.6
	var standing := [actor.to_local(actor.feet[0].global_position).y, actor.to_local(actor.feet[1].global_position).y]
	var lifted := [false, false]
	actor.advance(.04, turn_heading, 0.0)
	check(actor.heading > initial + .01 and actor.heading < turn_heading, label + " should turn through intermediate headings")
	for i in 30:
		actor.advance(.04, turn_heading, 0.0)
		for side in 2:
			lifted[side] = lifted[side] or actor.to_local(actor.feet[side].global_position).y > standing[side] + .025
	check(lifted[0] and lifted[1], label + " should lift both feet during its stationary turn")
	check(absf(angle_difference(actor.heading, turn_heading)) < .03, label + " should finish its turn")
	actor.global_transform = start

func check_wreck(actor, sockets: Array, label: String) -> void:
	var wreck = actor.wreck
	if wreck == null:
		check(false, label + " should start the rupture")
		return
	var captured := false
	for burst in wreck._bursts:
		if burst.birth > .03:
			continue
		for socket in sockets:
			if wreck.to_global(burst.origin).distance_to(socket) < actor.global_basis.x.length() * .18:
				captured = true
	check(captured, label + " ignition should originate at its reactor or fuel tank")
	check(wreck._parts.size() >= 5 and not actor.model_root.is_visible_in_tree(), label + " should detach the original body and limbs")
	var initial := {}
	for piece in wreck._parts:
		initial[piece.pivot] = piece.pivot.transform
	for i in 15:
		actor.advance(.04, actor.heading, 0.0)
	var moving := 0
	for piece in wreck._parts:
		if piece.pivot.visible and not piece.pivot.transform.is_equal_approx(initial[piece.pivot]):
			moving += 1
	check(moving >= 4, label + " should throw several visible fragments")
	for i in 90:
		actor.advance(.04, actor.heading, 0.0)
	check(actor.is_finished() and not wreck.visible, label + " should finish and clear its wreck")

func check_mech_attack(actor) -> void:
	var start: Array[Vector3] = []
	for i in 2:
		start.append(actor.model_root.to_local(actor.shields[i].to_global(actor.shield_centers[i])))
	actor.fire(1.8, 1.05, actor.heading)
	var deployed := [false, false]
	var previous := Vector3.ZERO
	var swept := 0.0
	var burning := 0
	var detached := false
	for i in 30:
		actor.advance(.028, actor.heading, 0.0)
		for j in 2:
			var center: Vector3 = actor.model_root.to_local(actor.shields[j].to_global(actor.shield_centers[j]))
			deployed[j] = deployed[j] or (center.x > start[j].x + .06 and absf(center.z) < absf(start[j].z) - .04)
		if not is_instance_valid(actor.flame) or not actor.flame.is_visible_in_tree():
			continue
		burning += 1
		detached = detached or actor.flame.global_position.distance_to(actor.muzzle_world()) > .012
		var axis: Vector3 = actor.muzzle.global_basis.x.normalized()
		if not previous.is_zero_approx():
			swept += previous.angle_to(axis)
		previous = axis
	check(deployed.all(func(v): return v) and burning >= 5, "Hellbat should bring up both shields and sustain its flame")
	check(not detached and swept > .12, "The jet should remain attached while the actual Hellbat nozzle sweeps")

func check_transform(actor) -> void:
	var reference = load(CAR_RIG).instantiate()
	var shield := actor.shields[0] as Node3D
	var initial := actor.to_local(shield.global_position) as Vector3
	actor.set_vehicle_form(true)
	var samples := 0
	var last_progress := 0.0
	var travel := 0.0
	var wheel_path := 0.0
	var max_wheel_step := 0.0
	var last_wheel := Vector3.INF
	for i in 100:
		actor.advance(.022, actor.heading, 0.0)
		var progress: float = actor.vehicle_progress
		check(progress + .0001 >= last_progress, "Vehicle transition should advance monotonically")
		if progress > .08 and progress < .88:
			samples += 1
			travel = maxf(travel, initial.distance_to(actor.to_local(shield.global_position)))
		if actor.vehicle != null and actor.vehicle.wheels[0].is_visible_in_tree():
			var point: Vector3 = actor.to_local(actor.vehicle.wheels[0].global_position)
			if last_wheel.is_finite():
				var distance := last_wheel.distance_to(point)
				max_wheel_step = maxf(max_wheel_step, distance)
				wheel_path += distance
			last_wheel = point
		last_progress = progress
		if progress >= .9999:
			break
	check(samples >= 6 and travel > .06 and last_progress >= .9999, "The Hellbat's own armor should articulate through intermediate vehicle poses")
	check(wheel_path > .12 and max_wheel_step < .09, "The same original front wheel should deploy continuously before reaching its axle")
	if actor.vehicle == null or actor.vehicle.wheels.size() != 4:
		check(false, "The vehicle endpoint should contain the game's four-wheel Hellion")
		reference.free()
		return
	var vehicle = actor.vehicle
	check(vehicle.model_root.is_visible_in_tree() and not actor.model_root.is_visible_in_tree(), "Only the real Hellion hull should remain at the vehicle endpoint")
	for wheel in vehicle.wheels:
		var original := reference.find_child(wheel.name, true, false) as MeshInstance3D
		check(original != null and original.mesh == wheel.mesh and wheel.is_visible_in_tree(), "A transformed wheel should reuse its original vehicle mesh")
	var phase: float = vehicle.wheels[0].rotation.z
	actor.advance(.06, actor.heading, .075)
	check(not is_equal_approx(phase, vehicle.wheels[0].rotation.z), "Hellion wheels should roll when the transformed vehicle moves")
	actor.set_vehicle_form(false)
	for i in 100:
		actor.advance(.025, actor.heading, 0.0)
	check(actor.vehicle_progress < .001 and actor.model_root.is_visible_in_tree(), "Reverse transformation should recover the standing mech")
	reference.free()

func observe_grenade(source: Dictionary, target: Dictionary, serial: int) -> Dictionary:
	var weapon: Dictionary = game.sim.catalog.marauder.attack_modes[0]
	var time := (float(game.sim.tick) - .5) / 20.0
	var due: float = time + source.pos.distance_to(target.pos) / float(weapon.delivery.speed)
	var native := {"id": serial, "source_id": source.id, "kind": source.kind, "team": source.team, "weapon": weapon,
		"origin": source.pos, "pos": source.pos, "goal": target.pos, "target_id": target.id, "strike": 0,
		"launch_time": time, "impact_time": due}
	var launch := {"type": "attack", "kind": source.kind, "source_id": source.id, "team": source.team,
		"from": source.pos, "to": target.pos, "strike": 0, "mode": weapon.id,
		"projectile": true, "splash": weapon.splash, "time": time}
	game.sim.projectiles.append(native)
	return {"native": native, "launch": launch, "key": [source.id, 0, time]}

func check_grenades(layer, actor) -> void:
	shooter.locked_target_id = aircraft.id
	check(is_nan(layer._aim(shooter, game, shooter.pos, .5)), "A ground-only launcher should ignore aircraft aim locks")
	shooter.attack_target_id = enemy.id
	shooter.locked_target_id = enemy.id
	var sides: Array[int] = []
	for i in 2:
		var sample := observe_grenade(shooter, enemy, 100 + i)
		var before: Dictionary = host.before_tick()
		var native_copy: Dictionary = sample.native.duplicate(true)
		var owned: bool = layer.event(sample.launch, before, game, host.clock)
		layer.event(sample.launch, before, game, host.clock)
		host.sync(view, .025)
		if not owned or not layer.shots.has(sample.key):
			check(false, "A real ground grenade launch should replace the generic effect")
			return
		var shot: Dictionary = layer.shots[sample.key]
		sides.append(shot.side)
		var muzzle: Node3D = actor.muzzles[shot.side]
		var flash = actor.flashes[shot.side]
		var active: Node3D = actor.launchers[shot.side]
		var idle: Node3D = actor.launchers[1 - shot.side]
		check(active.position.distance_to(actor.rest[active].origin) > .018 and idle.position.is_equal_approx(actor.rest[idle].origin),
			"Only the firing arm should recoil")
		var world_port := Vector2(muzzle.global_position.x, muzzle.global_position.z)
		check(shot.released and world_port.distance_to(view.point(shot.origin)) < .25,
			"The launched grenade should leave the recoiling physical arm")
		check(is_instance_valid(flash) and flash.is_visible_in_tree() and flash.global_position.distance_to(muzzle.global_position) < .02,
			"The selected arm's flare should start at its physical muzzle")
		check(layer.shots.size() == 1 and layer.owns_projectile(sample.native) and native_copy == sample.native,
			"A repeated event should own a single flight and leave the native projectile untouched")
		game.sim.tick = ceili(sample.native.impact_time * 20.0)
		game.sim.projectiles.clear()
		layer.event({"type": "attack_hit", "kind": "marauder", "mode": sample.launch.mode, "id": enemy.id,
			"team": shooter.team, "strike": 0, "amount": 13, "time": sample.native.impact_time}, before, game, host.clock)
		check(shot.hit and Vector2(shot.hit_pos).distance_to(enemy.pos) < .01, "The grenade should use the real ground contact")
		for tick in 30:
			frame()
	check(sides.size() == 2 and sides[0] != sides[1],
		"Consecutive one-hit volleys both use native strike zero and should alternate arms")
	var previous_window := game.window
	game.window = Rect2(25, 13, 12, 10)
	frame()
	var offscreen := observe_grenade(shooter, enemy, 140)
	var fallback: bool = layer.event(offscreen.launch, host.before_tick(), game, host.clock)
	host.sync(view, .025)
	check(fallback and not host.has_model(shooter.id) and layer.shots.has(offscreen.key)
		and Vector2(layer.shots[offscreen.key].origin).is_equal_approx(shooter.pos),
		"A known offscreen shooter should launch from its map center when its physical muzzle is culled")
	game.sim.projectiles.clear()
	game.window = previous_window
	game.fog = true
	frame()
	var hidden := observe_grenade(enemy, shooter, 150)
	check(not layer.event(hidden.launch, host.before_tick(), game, host.clock)
		and not layer.owns_projectile(hidden.native) and not host.has_model(enemy.id),
		"Unrevealed Marauders should retain neutral projectile and unit rendering")
	game.sim.projectiles.clear()
	game.fog = false


func check_battle_morph() -> void:
	var layer = host.hellbat_mechs
	var travel := HellionLayer.new()
	travel.initialize(host)
	game.medivac_visual = host
	var unit := {"id":21, "kind":"hellbat", "team":0, "prev":Vector2(5,5), "pos":Vector2(5,5)}
	game.sim.units = [unit]
	game.sim.by_id = {21:unit}
	game.sim.tick = 100
	host.sync(view, 0.05)
	travel.sync_shared(view, host, 0.05)
	check(travel.has_model(21) and not layer.has_model(21), "A travelling Hellion uses the vehicle rig")
	unit.morph_start_tick = 100
	unit.morph_end_tick = 140
	game.sim.tick = 101
	game.accumulator = 0.0
	host.sync(view, 0.05)
	travel.sync_shared(view, host, 0.05)
	if not layer.has_model(21):
		check(false, "The transforming vehicle should be owned by the articulated rig")
		return
	var actor = layer.entries[21].actor
	check(is_equal_approx(actor.vehicle_progress, 1.0) and not travel.has_model(21),
		"At contact exactly one finished vehicle hull should be visible for this ID")
	game.sim.tick = 121
	host.sync(view, 0.05)
	check(is_equal_approx(actor.vehicle_progress, 0.5), "Half of the gameplay interval should unfold half the rig")
	game.window = Rect2(25,13,12,10)
	host.sync(view, 0.0)
	check(not layer.has_model(21), "The transforming rig should be culled outside the camera")
	game.window = Rect2(0,0,40,24)
	host.sync(view, 0.0)
	actor = layer.entries[21].actor
	check(is_equal_approx(actor.vehicle_progress, 0.5), "Reentering the view must recover the current pose")
	unit.kind = "hellbat_mech"
	unit.erase("morph_start_tick")
	unit.erase("morph_end_tick")
	game.sim.tick = 140
	host.sync(view, 0.05)
	check(actor == layer.entries[21].actor and is_zero_approx(actor.vehicle_progress),
		"The same combat actor should stand on its feet as the gameplay form changes")
	var config: Dictionary = game.sim.catalog.hellbat_mech
	var delivery: Dictionary = config.attack_modes[0].delivery
	var origin: Vector2 = unit.pos + Vector2.RIGHT * float(config.collision_radius)
	var endpoint := origin + Vector2.RIGHT * float(delivery.length)
	var diameter := float(layer.entries[21].diameter)
	var port := actor.to_local(actor.muzzle_world())
	var expected_reach := maxf(0.1, (endpoint.x - unit.pos.x) / diameter - port.x)
	host.events([{"type":"cone_attack","kind":"hellbat_mech","source_id":21,"team":0,
		"from":origin,"to":endpoint,"angle_degrees":float(delivery.angle_degrees),"time":7.0}],{})
	check(is_equal_approx(actor.shot_reach, expected_reach), "The Hellbat flame uses the configured gameplay endpoint")
	check(actor.flame != null and actor.flame.is_visible_in_tree(), "The actual cone event should fire the rig nozzle")
	host.events([{"type":"death","id":21,"team":0,"pos":unit.pos}],{})
	check(not host.has_model(21) and actor.wreck != null, "The combat actor should break from its final pose")
	travel.reset()

func run() -> void:
	game.sim.catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/units.json")).units
	game.sim.units = [shooter, enemy, aircraft]
	game.sim.by_id = {7: shooter, 8: enemy, 9: aircraft}
	host.game = game
	root.add_child(host)
	host.sync(view, .025)
	if not host.has_model(shooter.id) or not ResourceLoader.exists(MECH_RIG):
		printerr("Import the Marauder and Hellbat articulated meshes before running the presentation smoke.")
		host.free()
		quit(1)
		return
	var layer = host.marauders
	var marauder = layer.entries[shooter.id].actor
	check(not host.has_model(enemy.id) and marauder.get_viewport() == host.viewport,
		"Only revealed Marauders should occupy the shared model viewport")
	check_gait(marauder, "Marauder")
	game.fog = false
	frame()
	check_grenades(layer, marauder)
	marauder = layer.entries[shooter.id].actor
	var captured := host.before_tick()
	var reactor := [marauder.reactor_socket.global_position]
	game.sim.units.erase(shooter)
	game.sim.by_id.erase(shooter.id)
	layer.event({"type": "death", "id": shooter.id, "team": shooter.team, "pos": shooter.pos}, captured, game, host.clock)
	check(not layer.has_model(shooter.id), "A destroyed Marauder must leave live model ownership")
	check_wreck(marauder, reactor, "Marauder")

	var mech = Hellbat.new()
	host.scene.add_child(mech)
	var rig := load(MECH_RIG) as PackedScene
	mech.setup(rig, host._model_bounds(rig), 0.0)
	if mech.feet.size() != 2 or mech.feet.has(null) or mech.muzzle == null:
		check(false, "The Hellbat rig should expose its feet, tanks, shields and nozzle")
	else:
		check_gait(mech, "Hellbat")
		check_mech_attack(mech)
		check_transform(mech)
		var tanks := [mech.tanks[0].global_position, mech.tanks[1].global_position]
		mech.destroy()
		check_wreck(mech, tanks, "Hellbat")
	check_battle_morph()
	host.reset()
	host.free()
	if failures == 0:
		print("Marauder and Hellbat presentation smoke passed")
	quit(1 if failures else 0)
