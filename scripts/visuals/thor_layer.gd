extends RefCounted
## Presentation state for visible walkers in the shared battle viewport.
const Actor = preload("res://scripts/visuals/thor_actor.gd")
const MODEL_PATH := "res://assets/models/thor/thor_rig.glb"
const MAX_LIVE := 16
const MAX_WRECKS := 6
const MODES := ["high_impact", "javelin", "hammer"]
const JAVELIN_VISUAL_SPEED := 1.5
# Two 32px spark radii, the longest ray (1.05), and its anti-aliased tip.
const IMPACT_MARGIN_PX := 70.0
const IMPACT_DURATION := 0.24
# Authored in polar order: angle, relative travel, and streak length or puff size.
const IMPACT_SPARKS := [
	Vector3(0.03, 1.00, 0.38), Vector3(0.43, 0.63, 0.12), Vector3(1.18, 0.84, 0.24),
	Vector3(1.91, 0.98, 0.31), Vector3(2.16, 0.72, 0.14), Vector3(3.05, 0.87, 0.27),
	Vector3(3.92, 0.58, 0.15), Vector3(4.35, 0.94, 0.36), Vector3(5.52, 0.83, 0.19),
]
const IMPACT_PUFFS := [
	Vector3(0.22, 0.54, 0.89), Vector3(0.79, 0.39, 1.08), Vector3(2.54, 0.57, 0.83),
	Vector3(3.05, 0.41, 1.24), Vector3(4.87, 0.49, 0.96),
]
var model: PackedScene
var scene: Node3D
var bounds: AABB
var entries: Dictionary = {}
var switches: Dictionary = {}
var launch_offsets: Dictionary = {}
var javelins: Dictionary = {}
var _native_shots: Dictionary = {}
var _native_tick := -1
var _presented_at := -INF
static var _glow: GradientTexture2D

func configure(shared_world: Node3D, resource: PackedScene, model_bounds: AABB) -> void:
	scene = shared_world
	model = resource
	bounds = model_bounds

func reset() -> void:
	for id in entries.keys():
		_remove(id)
	switches.clear()
	launch_offsets.clear()
	javelins.clear()
	_native_shots.clear()
	_native_tick = -1
	_presented_at = -INF

func _remove(id: int) -> void:
	var actor: Node3D = entries[id].actor
	actor.hide()
	actor.queue_free()
	entries.erase(id)

func has_model(id: int) -> bool:
	return entries.has(id) and not entries[id].dead

func _diameter(sim) -> float:
	var size: Array = sim.catalog.thor.size
	return maxf(float(size[0]), float(size[1]))

func _air_mode(unit: Dictionary, config: Dictionary) -> String:
	var order: Array = config.get("mode_ids", MODES)
	var index := int(unit.get("air_weapon_index", config.get("default_index", 0)))
	return "javelin" if index >= 0 and index < order.size() and order[index] == "javelin" else "high_impact"

func _create(id: int, unit: Dictionary, pos: Vector2, config: Dictionary) -> Dictionary:
	var motion: Vector2 = unit.pos - unit.get("prev", unit.pos)
	var heading := motion.angle() if motion.length_squared() > 0.000001 else (0.0 if unit.team == 0 else PI)
	var actor = Actor.new()
	scene.add_child(actor)
	actor.setup(model, bounds, heading, _air_mode(unit, config))
	var entry := {"actor":actor, "pos":pos, "team":unit.team, "heading":heading,
		"aim":NAN, "aim_until":-1.0, "dead":false, "death_at":-1.0}
	entries[id] = entry
	return entry

func _place(entry: Dictionary, view, diameter: float) -> void:
	var screen: Vector2 = view.point(entry.pos)
	entry.actor.position = Vector3(screen.x, -100.0, screen.y)
	entry.actor.scale = Vector3.ONE * view.pixels(diameter)

func _sample(start: float, end: float, remaining: float, duration: float) -> float:
	return lerpf(start, end, 1.0 - clampf(remaining / maxf(1.0, duration), 0.0, 1.0))

func _air_progress(id: int, unit: Dictionary, mode: String, at_tick: float, duration: float) -> float:
	var end := 1.0 if mode == "javelin" else 0.0
	var until := int(unit.get("switch_until_tick", 0))
	var start := 1.0 - end
	if switches.has(id) and switches[id].mode == mode and switches[id].until == until:
		start = switches[id].start
	return _sample(start, end, until - at_tick, duration)

func _aim(entry: Dictionary, unit: Dictionary, game, alpha: float) -> void:
	var firing: bool = unit.get("attack_phase", "") in ["windup", "firing", "backswing"]
	var ids := [unit.get("attack_target_id", 0) if firing else 0,
		unit.get("locked_target_id", 0), unit.get("engage_id", 0)]
	for id in ids:
		var target_pos: Vector2
		if int(id) < 0 and firing:
			target_pos = game.sim.base_pos(1 - int(unit.team))
		else:
			var target = game.sim.by_id.get(id)
			if target == null or target.team == unit.team or target.get("hp", 1.0) <= 0.0 or game._hidden_team(int(target.team)):
				continue
			target_pos = target.prev.lerp(target.pos, alpha)
		var direction: Vector2 = target_pos - entry.pos
		if direction.length_squared() > 0.000001:
			entry.aim = direction.angle()
		return
	entry.aim = NAN

func sync(game, view, dt: float, clock: float, alpha: float) -> void:
	if model == null or not game.sim.catalog.has("thor"):
		return
	var diameter := _diameter(game.sim)
	var config: Dictionary = game.sim.catalog.thor.skills.weapon_switch
	var duration := ceili(float(config.switch_seconds) * float(game.sim.rules.tick_rate))
	var at_tick := float(game.sim.tick) + alpha
	var area: Rect2 = game._camera_rect().grow(diameter * 2.0)
	var retained: Dictionary = {}
	for unit in game.sim.units:
		if unit.kind != "thor" or game._hidden_team(int(unit.team)):
			continue
		var pos: Vector2 = unit.prev.lerp(unit.pos, alpha)
		if retained.size() >= MAX_LIVE or not area.has_point(pos):
			continue
		retained[unit.id] = true
		if not entries.has(unit.id):
			_create(unit.id, unit, pos, config)
		var entry: Dictionary = entries[unit.id]
		var motion: Vector2 = unit.pos - unit.prev
		var distance: float = Vector2(entry.pos).distance_to(pos) / diameter
		if motion.length_squared() > 0.000001:
			entry.heading = motion.angle()
			if motion.dot(Vector2.from_angle(entry.actor.heading)) < 0:
				distance = -distance
		entry.pos = pos
		if clock >= entry.aim_until:
			_aim(entry, unit, game, alpha)
		_place(entry, view, diameter)
		entry.actor.advance(dt, entry.heading, distance if dt > 0 else 0.0, entry.aim)
		var mode := _air_mode(unit, config)
		entry.actor.set_air_progress(_air_progress(unit.id, unit, mode, at_tick, duration), mode)

	for id in entries.keys():
		var entry: Dictionary = entries[id]
		if game._hidden_team(int(entry.team)) or not area.has_point(entry.pos):
			_remove(id)
		elif entry.dead:
			_place(entry, view, diameter)
			entry.actor.advance(dt, entry.heading, 0.0)
			if entry.actor.is_finished():
				_remove(id)
		elif not retained.has(id):
			_remove(id)
	for id in switches.keys():
		if at_tick >= switches[id].until or game._hidden_team(int(switches[id].team)):
			switches.erase(id)
	if not launch_offsets.is_empty():
		var live: Dictionary = {}
		for projectile in game.sim.projectiles:
			if projectile.kind == "thor" and not game._hidden_team(int(projectile.team)):
				var key := _projectile_key(projectile)
				if launch_offsets.has(key):
					live[key] = launch_offsets[key]
		launch_offsets = live
	var now := render_time(game.sim, alpha)
	# A finishing hit may occur between the last two simulation samples. Let its
	# confirmed contact finish under the result panel, using the pause-aware delta.
	if game.sim.get("finished") == true:
		now = maxf(now, _presented_at + dt)
	_presented_at = now
	var due: Array[Array] = []
	for key in javelins.keys():
		var flight: Dictionary = javelins[key]
		var retention := IMPACT_DURATION if not flight.hit.is_empty() else 1.0 / float(game.sim.rules.tick_rate)
		if now >= float(flight.impact_time) + retention or game._hidden_team(int(flight.team)):
			javelins.erase(key)
		elif not flight.released and now >= flight.release_time:
			due.append(key)
	# Several frames may elapse in one update. A closer target can schedule a
	# later native shot first; sample recoil and aim in visible release order.
	if due.size() > 1:
		due.sort_custom(_releases_first)
	for key in due:
		_release_javelin(javelins[key], key, game.sim, diameter, alpha, now)
	if _native_tick != game.sim.tick:
		_native_shots.clear()

func event(data: Dictionary, before: Dictionary, game, clock: float) -> void:
	if model == null or not game.sim.catalog.has("thor"):
		return
	var kind := str(data.type)
	if kind not in ["attack", "weapon_switch", "death"]:
		return
	if kind == "attack" and (data.get("kind") != "thor" or data.get("mode") not in MODES):
		return
	if kind == "attack" and owns_javelin_launch(data):
		return
	var id := int(data.get("source_id", -1) if kind == "attack" else data.get("id", -1))
	var unit: Dictionary = game.sim.by_id.get(id, before.get(id, {}))
	if unit.get("kind") != "thor" or game._hidden_team(int(unit.team)):
		return
	var config: Dictionary = game.sim.catalog.thor.skills.weapon_switch
	if kind == "weapon_switch":
		var mode := str(data.weapon)
		if mode not in ["high_impact", "javelin"]:
			return
		var old: Dictionary = before.get(id, {})
		var duration := ceili(float(config.switch_seconds) * float(game.sim.rules.tick_rate))
		var start := 1.0 if mode == "high_impact" else 0.0
		if not old.is_empty():
			start = _air_progress(id, old, _air_mode(old, config), float(game.sim.tick), duration)
		switches[id] = {"mode":mode, "start":start, "team":unit.team,
			"until":unit.get("switch_until_tick", game.sim.tick + duration)}
		if has_model(id):
			entries[id].actor.set_air_progress(start, mode)
		return

	var diameter := _diameter(game.sim)
	var pos: Vector2 = data.from if kind == "attack" else data.pos
	if not game._camera_rect().grow(diameter * 2.0).has_point(pos):
		_register_icon_shot(data, game.sim)
		return
	if not entries.has(id):
		var count := 0
		for entry in entries.values():
			if not entry.dead:
				count += 1
		if count >= MAX_LIVE:
			_register_icon_shot(data, game.sim)
			return
		_create(id, unit, pos, config)
	var entry: Dictionary = entries[id]
	if entry.dead:
		return
	if kind == "death":
		_destroy(entry, pos, clock)
		switches.erase(id)
		return

	var mode := str(data.mode)
	var strike := int(data.get("strike", 0))
	var target_offset: Vector2 = (data.to - pos) / diameter
	if target_offset.length_squared() > 0.000001:
		entry.aim = target_offset.angle()
	entry.aim_until = clock + 0.15
	if mode != "hammer":
		entry.actor.set_air_progress(1.0 if mode == "javelin" else 0.0, mode)
	# Javelin waits for its shorter visible flight window. The arm guns fire on
	# their native strike events and keep their original timing.
	if mode != "javelin" or not data.has("time"):
		entry.actor.fire_at(mode, strike, target_offset)
	if data.has("time") and (data.get("projectile", false) or mode == "javelin"):
		var key := [id, strike, float(data.time)]
		var offset: Vector2 = entry.actor.muzzle_screen_offset(mode, strike) * diameter
		if data.get("projectile", false):
			launch_offsets[key] = offset
		if mode == "javelin":
			_register_javelin(key, data, pos + offset, entry.actor.javelin_launch_direction(strike), game.sim)

func _projectile_key(projectile: Dictionary) -> Array:
	return [int(projectile.get("source_id", -1)), int(projectile.get("strike", -1)), float(projectile.get("launch_time", -1))]

# Project the real trajectory from the muzzle, converging on its tracked impact.
func projectile_offset(projectile: Dictionary, now: float) -> Vector2:
	if launch_offsets.is_empty():
		return Vector2.ZERO
	var key := _projectile_key(projectile)
	if not launch_offsets.has(key):
		return Vector2.ZERO
	var offset: Vector2 = launch_offsets[key]
	var duration := float(projectile.impact_time) - float(projectile.launch_time)
	var remaining := clampf((float(projectile.impact_time) - now) / maxf(0.000001, duration), 0.0, 1.0)
	return offset * remaining

func render_time(sim, alpha: float) -> float:
	# Opening some UI panels resets the interpolation accumulator in the same tick.
	var sample := (float(sim.tick) - 1.0 + clampf(alpha, 0.0, 1.0)) / float(sim.rules.tick_rate)
	return maxf(sample, _presented_at)

func _register_icon_shot(data: Dictionary, sim) -> void:
	if data.type == "attack" and data.mode == "javelin" and data.has("time"):
		var key := [int(data.source_id), int(data.strike), float(data.time)]
		var axis: Vector2 = data.to - data.from
		_register_javelin(key, data, data.from, axis.normalized(), sim)

func _register_javelin(key: Array, data: Dictionary, origin: Vector2, axis: Vector2, sim) -> void:
	if _native_tick != sim.tick:
		_native_tick = sim.tick
		_native_shots.clear()
		for projectile in sim.projectiles:
			if projectile.kind == "thor" and projectile.weapon.id == "javelin":
				_native_shots[_projectile_key(projectile)] = projectile
	var native: Dictionary = _native_shots.get(key, {})
	var due := float(data.time)
	if not native.is_empty():
		due = float(native.impact_time)
	else:
		# A short flight can be launched and resolved within one simulation step.
		# Its launch event and the configured travel time survive that step.
		for weapon in sim.catalog.thor.get("attack_modes", []):
			if weapon.id == "javelin":
				var length: float = data.from.distance_to(data.to)
				due += length / maxf(0.001, float(weapon.delivery.speed))
				break
	var launch_time := float(data.time)
	var visible_duration := maxf(0.0, due - launch_time) / JAVELIN_VISUAL_SPEED
	javelins[key] = {"team":int(data.team), "strike":int(data.strike), "origin":origin,
		"launch_direction":axis, "goal":data.to, "native":native, "launch_time":launch_time,
		"release_time":due - visible_duration, "released":false, "impact_time":due, "hit":{}}

func _releases_first(a: Array, b: Array) -> bool:
	var left: Dictionary = javelins[a]
	var right: Dictionary = javelins[b]
	if left.release_time != right.release_time:
		return left.release_time < right.release_time
	return left.launch_time < right.launch_time if left.launch_time != right.launch_time else left.strike < right.strike

func _release_javelin(flight: Dictionary, key: Array, sim, diameter: float, alpha: float, now: float) -> void:
	flight.released = true
	var id := int(key[0])
	if not has_model(id):
		# A culled live walker fires from its tactical icon. An already destroyed
		# launcher leaves the recorded muzzle in world space for this real shot.
		var source = sim.by_id.get(id)
		if source != null and source.get("hp", 1.0) > 0.0 and not entries.get(id, {}).get("dead", false):
			flight.origin = Vector2(source.prev).lerp(source.pos, alpha)
		return
	var entry: Dictionary = entries[id]
	var goal := _display_goal(flight, sim, now)
	var elapsed := maxf(0.0, now - float(flight.release_time))
	entry.actor.fire_at("javelin", flight.strike, (goal - Vector2(entry.pos)) / diameter, elapsed)
	var offset: Vector2 = entry.actor.muzzle_screen_offset("javelin", flight.strike) * diameter
	flight.origin = Vector2(entry.pos) + offset
	flight.launch_direction = entry.actor.javelin_launch_direction(flight.strike)
	if launch_offsets.has(key):
		launch_offsets[key] = offset

func javelin_progress(flight: Dictionary, now: float) -> float:
	var duration := float(flight.impact_time) - float(flight.release_time)
	if duration <= 0.0:
		return 1.0 if now >= flight.impact_time else 0.0
	return clampf((now - float(flight.release_time)) / duration, 0.0, 1.0)

func owns_javelin(projectile: Dictionary) -> bool:
	return projectile.get("weapon", {}).get("id") == "javelin" and javelins.has(_projectile_key(projectile))

func owns_javelin_launch(data: Dictionary) -> bool:
	return data.get("kind") == "thor" and data.get("mode") == "javelin" and javelins.has([
		int(data.get("source_id", -1)), int(data.get("strike", -1)), float(data.get("time", -1))])

func accept_javelin_impact(data: Dictionary, game) -> bool:
	if data.type != "area_impact" or data.get("kind") != "thor" or game._hidden_team(int(data.team)):
		return false
	var tick_end := float(game.sim.tick) / float(game.sim.rules.tick_rate)
	var tick_start := tick_end - 1.0 / float(game.sim.rules.tick_rate)
	var best: Dictionary = {}
	var best_error := INF
	for flight in javelins.values():
		if is_same(flight.hit, data):
			return true
		if flight.team != data.team or not flight.hit.is_empty() or flight.impact_time > tick_end + 0.000001 or flight.impact_time < tick_start - 0.000001:
			continue
		var native: Dictionary = flight.native
		var goal: Vector2 = native.get("goal", flight.goal)
		var error := goal.distance_squared_to(data.to)
		# The simulator updates this same projectile dictionary just before
		# removing it. Overlapping contacts retain its native time / ID order.
		if not native.is_empty() and not goal.is_equal_approx(data.to):
			continue
		if native.is_empty() and error > pow(float(data.radius), 2):
			continue
		if error < best_error or (error == best_error and _lands_first(flight, best)):
			best_error = error
			best = flight
	if best.is_empty():
		return false
	best.hit = data
	return true

func _lands_first(flight: Dictionary, other: Dictionary) -> bool:
	if other.is_empty() or flight.impact_time != other.impact_time:
		return other.is_empty() or flight.impact_time < other.impact_time
	return int(flight.native.get("id", 2147483647)) < int(other.native.get("id", 2147483647))

func javelin_position(flight: Dictionary, goal: Vector2, progress: float) -> Vector2:
	var start: Vector2 = flight.origin
	var delta := goal - start
	var length := delta.length()
	var axis := delta.normalized()
	var launch: Vector2 = flight.launch_direction
	if launch.is_zero_approx():
		launch = axis
	# Leave the physical bore tangent first, then bank onto the tracked aircraft.
	# The raised approach projects slightly north in the battlefield's overhead view.
	var first := start + launch * minf(length * 0.40, 2.0)
	var last := goal - axis * minf(length * 0.22, 1.7) + Vector2.UP * minf(length * 0.17, 1.0)
	return start.bezier_interpolate(first, last, goal, clampf(progress, 0.0, 1.0))

func _display_goal(flight: Dictionary, sim, now: float) -> Vector2:
	var native: Dictionary = flight.native
	var hit: Dictionary = flight.hit
	var goal: Vector2 = native.get("goal", flight.goal) if hit.is_empty() else hit.to
	if not hit.is_empty() and now >= flight.impact_time:
		return goal
	var target = sim.by_id.get(native.get("target_id", 0))
	if target == null:
		return goal
	var tick_start := (float(sim.tick) - 1.0) / float(sim.rules.tick_rate)
	var duration := 1.0 / float(sim.rules.tick_rate)
	if not hit.is_empty():
		duration = maxf(0.000001, float(flight.impact_time) - tick_start)
	return Vector2(target.prev).lerp(goal, clampf((now - tick_start) / duration, 0.0, 1.0))

func draw_ordnance(canvas: CanvasItem, view, game, now: float) -> void:
	if javelins.is_empty():
		return
	var area: Rect2 = game._camera_rect().grow(1.5)
	var impact_area := Rect2(Vector2.ZERO, view.viewport_size()).grow(IMPACT_MARGIN_PX)
	for flight in javelins.values():
		if game._hidden_team(int(flight.team)):
			continue
		if now >= flight.impact_time:
			var hit: Dictionary = flight.hit
			var age := now - float(flight.impact_time)
			if not hit.is_empty() and age < IMPACT_DURATION and impact_area.has_point(view.point(hit.to)):
				_draw_impact(canvas, view, hit, int(flight.strike), age)
			continue
		if not flight.released or now < flight.release_time:
			continue
		var duration := float(flight.impact_time) - float(flight.release_time)
		var t := javelin_progress(flight, now)
		var goal := _display_goal(flight, game.sim, now)
		var tip := javelin_position(flight, goal, t)
		if area.has_point(tip):
			_draw_rocket(canvas, view, flight, goal, t, tip, duration)

func _draw_rocket(canvas: CanvasItem, view, flight: Dictionary, goal: Vector2, t: float, world_tip: Vector2, duration: float) -> void:
	var tip: Vector2 = view.point(world_tip)
	var near := javelin_position(flight, goal, t + 0.005) - javelin_position(flight, goal, t - 0.005)
	var axis := near.normalized()
	if axis.is_zero_approx():
		axis = Vector2.RIGHT
	var body := clampf(view.pixels(0.34), 3.6, 12.0)
	# The tip starts at the socket. Reveal only the length which has cleared the bore.
	var bore: Vector2 = view.point(flight.origin)
	var travel := tip.distance_to(bore)
	if travel < body + 14.0:
		travel = 0.0
		for i in range(1, 5):
			var along: Vector2 = view.point(javelin_position(flight, goal, t * i / 4.0))
			travel += bore.distance_to(along)
			bore = along
	if travel < 0.6:
		return
	var exposed := minf(body, travel)
	var shoulder := tip - axis * minf(exposed, body * 0.39)
	var nozzle := tip - axis * exposed
	var span := axis.orthogonal() * maxf(1.0, body * 0.20)
	if exposed < body * 0.4:
		var nose_span := span * (exposed / (body * 0.4))
		canvas.draw_colored_polygon(PackedVector2Array([tip, nozzle+nose_span, nozzle-nose_span]), Color("fbfeff"))
		return
	var clearance := travel - body
	if clearance > 0.65:
		# The motor and its smoke appear once the back of the missile is in free flight.
		var trail_time := minf(t, 0.068 / duration)
		var previous: Vector2 = view.point(javelin_position(flight, goal, t - trail_time))
		for i in range(1, 6):
			var u := float(i) / 5.0
			var p: Vector2 = view.point(javelin_position(flight, goal, t - trail_time * (1.0 - u)))
			canvas.draw_line(previous, p, Color(0.82,0.79,0.69,0.16+0.32*u), maxf(1.1, body * (0.16 + 0.12*u)), true)
			previous = p
		var flicker := 0.85 + 0.15 * sin(t * duration * 59.0 + int(flight.strike))
		var tail := nozzle - axis * minf(clearance, clampf(view.pixels(0.38), 4, 13) * flicker)
		canvas.draw_colored_polygon(PackedVector2Array([nozzle+span, tail, nozzle-span]), Color("ff7524"))
		canvas.draw_line(nozzle, nozzle.lerp(tail, 0.62), Color("ffe6a5"), maxf(1.1, body * 0.22), true)
	canvas.draw_colored_polygon(PackedVector2Array([tip, shoulder+span, nozzle+span*0.75,
		nozzle-span*0.75, shoulder-span]), Color("a3bac3"))
	canvas.draw_line(shoulder, tip, Color("fbfeff"), maxf(1.0, body * 0.25), true)

func _draw_impact(canvas: CanvasItem, view, hit: Dictionary, strike: int, age: float) -> void:
	if _glow == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
		gradient.colors = PackedColorArray([Color.WHITE, Color(1,1,1,0.82), Color(1,1,1,0.27), Color(1,1,1,0)])
		_glow = GradientTexture2D.new()
		_glow.gradient = gradient
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1, 0.5)
	var t := clampf(age / IMPACT_DURATION, 0.0, 1.0)
	var center: Vector2 = view.point(hit.to)
	var size := clampf(view.pixels(float(hit.radius) * 0.72), 5.0, 32.0)
	var spread := size * 2.0
	var travel := sqrt(t)
	var fade := 1.0 - smoothstep(0.20, 1.0, t)
	var smoke := smoothstep(0.0, 0.18, t) * fade
	# Small banks of soot spread around the flash so the target remains visible through the center.
	for cloud: Vector3 in IMPACT_PUFFS:
		var axis := Vector2.from_angle(cloud.x + strike * 0.71)
		var puff := center + axis * spread * (0.10 + cloud.y * travel)
		var radius := maxf(1.7, spread * (0.075 + 0.14 * travel) * cloud.z)
		var extent := Vector2(radius, radius * 0.88)
		canvas.draw_texture_rect(_glow, Rect2(puff - extent, extent * 2.0), false, Color(0.34, 0.36, 0.38, 0.85 * smoke))
		var rim := puff - extent * 0.23 + axis.orthogonal() * radius * 0.34
		extent *= 0.80
		canvas.draw_texture_rect(_glow, Rect2(rim - extent, extent * 2.0), false, Color(0.70, 0.68, 0.64, 0.67 * smoke))

	var flash := 1.0 - smoothstep(0.07, 0.67, t)
	var halo := Vector2.ONE * size * (0.42 + 0.46 * sin(PI * travel))
	canvas.draw_texture_rect(_glow, Rect2(center - halo, halo * 2.0), false, Color(1.0, 0.39, 0.10, 0.90 * flash))
	var core := halo * 0.53
	canvas.draw_texture_rect(_glow, Rect2(center - core, core * 2.0), false, Color(1.0, 0.96, 0.76, flash))
	for i in IMPACT_SPARKS.size():
		var spark: Vector3 = IMPACT_SPARKS[i]
		var axis := Vector2.from_angle(spark.x + strike * 0.72)
		var ray := axis * spread * spark.y
		var progress := 0.12 + 0.93 * travel
		var tip := center + ray * progress
		var tail := center + ray * maxf(0.02, progress - spark.z * (1.0 - t))
		var width := maxf(1.0, size * (0.03 + 0.10 * spark.z))
		canvas.draw_line(tail, tip, Color(1.0, 0.49, 0.13, fade), width, true)
		canvas.draw_circle(tip, maxf(0.65, width * 0.60), Color(1.0, 0.94, 0.68, fade), true, -1.0, true)
		if i == 0 or i == 7:
			var chip := center + ray * progress * 0.70 + axis.orthogonal() * spread * 0.075 * travel
			canvas.draw_circle(chip, maxf(0.65, width * 0.48), Color(1.0, 0.72, 0.32, fade), true, -1.0, true)

func _destroy(entry: Dictionary, pos: Vector2, clock: float) -> void:
	var count := 0
	var oldest := -1
	for id in entries:
		if entries[id].dead:
			count += 1
			if oldest < 0 or entries[id].death_at < entries[oldest].death_at:
				oldest = id
	if count >= MAX_WRECKS:
		_remove(oldest)
	entry.dead = true
	entry.death_at = clock
	entry.pos = pos
	entry.actor.destroy()
