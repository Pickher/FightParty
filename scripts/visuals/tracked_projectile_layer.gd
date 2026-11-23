extends RefCounted
## Presentation for a real single-strike tracking projectile and the actor that fired it.
const MAX_LIVE := 24
const MAX_WRECKS := 8
var _kind: String
var _mode: String
var _target_layer: String
var _wreck_margin: float
var _turn_to_target_at_rest := false
var _actor_script: GDScript
var _ordnance: GDScript
var model: PackedScene
var scene: Node3D
var bounds: AABB
var entries: Dictionary = {}
var next_sides: Dictionary = {}
var _last_headings: Dictionary = {}
var shots: Dictionary = {}
var _contacts: Dictionary = {}
var _native: Dictionary = {}
var _indexed_tick := -1
var _presented_at := -INF

func _init(kind: String, mode: String, target_layer: String, actor_script: GDScript, ordnance: GDScript, wreck_margin: float = 2.0) -> void:
	_kind = kind
	_mode = mode
	_target_layer = target_layer
	_wreck_margin = wreck_margin
	_actor_script = actor_script
	_ordnance = ordnance

# Units with a timed entry animation can sample it at simulation time, even on reentry.
func _sample_form(_entry: Dictionary, _unit: Dictionary, _sim, _time: float) -> void:
	pass

func _socket(_actor: Node3D, _side: int) -> Transform2D:
	return Transform2D.IDENTITY

func _fire_actor(_actor: Node3D, _offset: Vector2, _age: float, _side: int) -> void:
	pass

func _draw_contact(canvas: CanvasItem, view, pos: Vector2, age: float, side: int) -> void:
	_ordnance.draw_impact(canvas, view, pos, age, side)

func configure(shared: Node3D, resource: PackedScene, model_bounds: AABB) -> void:
	scene = shared
	model = resource
	bounds = model_bounds

func reset() -> void:
	for id in entries.keys():
		_remove(id)
	next_sides.clear()
	_last_headings.clear()
	shots.clear()
	_contacts.clear()
	_native.clear()
	_indexed_tick = -1
	_presented_at = -INF

func _remove(id: int) -> void:
	var actor: Node3D = entries[id].actor
	actor.hide()
	actor.queue_free()
	entries.erase(id)

func has_model(id: int) -> bool:
	return entries.has(id) and not entries[id].dead

func _diameter(sim) -> float:
	var size: Array = sim.catalog[_kind].size
	return maxf(float(size[0]), float(size[1]))

func _create(id: int, source: Dictionary, pos: Vector2) -> bool:
	var motion: Vector2 = source.pos - source.get("prev", source.pos)
	var heading: float = motion.angle() if motion.length_squared() > 0.000001 else _last_headings.get(id, 0.0 if source.team == 0 else PI)
	var actor = _actor_script.new()
	scene.add_child(actor)
	if not actor.setup(model, bounds, heading):
		actor.hide()
		actor.queue_free()
		model = null
		return false
	entries[id] = {"actor":actor, "team":source.team, "pos":pos, "heading":heading, "height":-100.0, "dead":false, "death_at":0.0}
	return true

func _place(entry: Dictionary, view, diameter: float) -> void:
	var screen: Vector2 = view.point(entry.pos)
	entry.actor.position = Vector3(screen.x, entry.height, screen.y)
	entry.actor.scale = Vector3.ONE * view.pixels(diameter)

func _aim(unit: Dictionary, game, pos: Vector2, alpha: float) -> float:
	var firing: bool = unit.get("attack_phase", "") in ["windup", "firing", "backswing"]
	var ids := [unit.get("attack_target_id", 0) if firing else 0, unit.get("locked_target_id", 0), unit.get("engage_id", 0)]
	for id in ids:
		var goal: Vector2
		if int(id) < 0 and firing and _target_layer == "ground":
			goal = game.sim.base_pos(1 - int(unit.team))
		else:
			var target = game.sim.by_id.get(id)
			if target == null or target.team == unit.team or target.get("hp", 1.0) <= 0 or game._hidden_team(int(target.team)):
				continue
			if game.sim.catalog.get(target.kind, {}).get("layer", "ground") != _target_layer:
				continue
			goal = target.prev.lerp(target.pos, alpha)
		if goal.distance_squared_to(pos) > 0.000001:
			return pos.direction_to(goal).angle()
	return NAN

func render_time(sim, alpha: float) -> float:
	return maxf(_presented_at, (float(sim.tick) - 1.0 + clampf(alpha, 0.0, 1.0)) / float(sim.rules.tick_rate))

func sync(game, view, dt: float, _clock: float, alpha: float) -> void:
	if model == null or not game.sim.catalog.has(_kind):
		return
	var now := render_time(game.sim, alpha)
	var diameter := _diameter(game.sim)
	var camera_rect: Rect2 = game._camera_rect()
	var area := camera_rect.grow(diameter * 2.0)
	var wreck_area := camera_rect.grow(diameter * _wreck_margin)
	var retained: Dictionary = {}
	for unit in game.sim.units:
		if unit.kind != _kind or game._hidden_team(int(unit.team)):
			continue
		var motion: Vector2 = unit.pos - unit.prev
		if motion.length_squared() > 0.000001:
			_last_headings[unit.id] = motion.angle()
		if retained.size() >= MAX_LIVE:
			continue
		var pos: Vector2 = unit.prev.lerp(unit.pos, alpha)
		if not area.has_point(pos):
			continue
		if not entries.has(unit.id) and not _create(unit.id, unit, pos):
			return
		retained[unit.id] = true
		var entry: Dictionary = entries[unit.id]
		var aim := _aim(unit, game, pos, alpha)
		if _turn_to_target_at_rest and motion.length_squared() <= 0.000001 and is_finite(aim):
			_last_headings[unit.id] = aim
		entry.heading = _last_headings.get(unit.id, entry.heading)
		var delta_pos: Vector2 = pos - entry.pos
		var distance := delta_pos.length() / diameter
		if delta_pos.dot(Vector2.from_angle(entry.actor.heading)) < 0.0:
			distance = -distance
		entry.pos = pos
		_sample_form(entry, unit, game.sim, now)
		_place(entry, view, diameter)
		entry.actor.advance(dt, entry.heading, distance if dt > 0.0 else 0.0, aim)
	for id in entries.keys():
		var entry: Dictionary = entries[id]
		var visible_area := wreck_area if entry.dead else area
		if game._hidden_team(int(entry.team)) or not visible_area.has_point(entry.pos):
			_remove(id)
		elif entry.dead:
			_place(entry, view, diameter)
			entry.actor.advance(dt, entry.heading, 0.0)
			if entry.actor.is_finished():
				_remove(id)
		elif not retained.has(id):
			_remove(id)
	if game.sim.get("finished") == true:
		now = maxf(now, _presented_at + dt)
	_presented_at = now
	var step_end := float(game.sim.tick) / float(game.sim.rules.tick_rate)
	for key in shots.keys():
		var shot: Dictionary = shots[key]
		if game._hidden_team(int(shot.team)) or now >= float(shot.impact_time) + _ordnance.IMPACT_DURATION:
			_forget(key, shot)
			continue
		# Base damage is settled directly by the projectile service, without an
		# attack_hit event. The native step must actually reach the delivery time.
		if _target_layer == "ground" and shot.target_id < 0 and not shot.hit and step_end >= float(shot.impact_time) - 0.000001:
			shot.hit = true
			shot.hit_pos = shot.native.get("goal", shot.goal)
		if not shot.released and now >= shot.launch_time:
			shot.released = true
			if has_model(key[0]):
				var entry: Dictionary = entries[key[0]]
				var goal := _goal(shot, game.sim, now)
				_fire_actor(entry.actor, (goal - Vector2(entry.pos)) / diameter, now - float(shot.launch_time), shot.side)
				var socket := _socket(entry.actor, shot.side)
				shot.origin = Vector2(entry.pos) + socket.origin * diameter
				shot.direction = socket.x
	if _indexed_tick != game.sim.tick:
		_native.clear()

func _forget(key: Array, shot: Dictionary) -> void:
	var token: Array = shot.contact_key
	if _contacts.has(token):
		_contacts[token].erase(key)
		if _contacts[token].is_empty():
			_contacts.erase(token)
	shots.erase(key)

func _key(projectile: Dictionary) -> Array:
	return [int(projectile.get("source_id", -1)), int(projectile.get("strike", -1)), float(projectile.get("launch_time", -1))]

func owns_projectile(projectile: Dictionary) -> bool:
	return projectile.get("kind") == _kind and projectile.get("weapon", {}).get("id") == _mode and shots.has(_key(projectile))

func event(data: Dictionary, before: Dictionary, game, clock: float) -> bool:
	if model == null or not game.sim.catalog.has(_kind):
		return false
	if data.type in ["death", "expired"]:
		var id := int(data.id)
		next_sides.erase(id)
		if data.type == "death" and not game._hidden_team(int(data.team)):
			var source: Dictionary = before.get(id, {})
			if has_model(id) or source.get("kind") == _kind:
				if _ensure_visible(id, source, data.pos, game, _wreck_margin) and has_model(id):
					if not source.is_empty():
						_sample_form(entries[id], source, game.sim, float(game.sim.tick) / float(game.sim.rules.tick_rate))
					_destroy(entries[id], data.pos, clock)
		_last_headings.erase(id)
		return false
	if data.type not in ["attack", "attack_hit"] or data.get("kind") != _kind or data.get("mode") != _mode or not data.has("time"):
		return false
	if game._hidden_team(int(data.team)):
		return false
	if data.type == "attack_hit":
		_record_hit(data, game.sim)
		return false
	var id := int(data.get("source_id", -1))
	if id < 0:
		return false
	var key := [id, int(data.get("strike", 0)), float(data.time)]
	if shots.has(key):
		return true
	var source: Dictionary = game.sim.by_id.get(id, before.get(id, {}))
	if source.get("kind") != _kind:
		return false
	# Each native attack has one strike (index zero). Alternate across attack
	# sequences, preserving the shooter's next launcher even when its model is culled.
	var side := int(next_sides.get(id, 0))
	next_sides[id] = 1 - side
	var pos: Vector2 = data.from
	var goal: Vector2 = data.to
	var origin := pos
	var direction := pos.direction_to(goal)
	if _ensure_visible(id, source, pos, game):
		var entry: Dictionary = entries[id]
		_sample_form(entry, source, game.sim, float(data.time))
		var socket := _socket(entry.actor, side)
		origin += socket.origin * _diameter(game.sim)
		direction = socket.x
	elif model == null:
		return false
	_register(key, data, source, side, origin, direction, game.sim)
	return true

func _ensure_visible(id: int, source: Dictionary, pos: Vector2, game, margin: float = 2.0) -> bool:
	if entries.has(id):
		return has_model(id)
	if source.is_empty() or not game._camera_rect().grow(_diameter(game.sim) * margin).has_point(pos):
		return false
	var count := 0
	for entry in entries.values():
		if not entry.dead:
			count += 1
	return count < MAX_LIVE and _create(id, source, pos)

func _contact_key(team: int, strike: int, time: float) -> Array:
	return [team, strike, roundi(time * 1000000.0)]

func _register(key: Array, data: Dictionary, source: Dictionary, side: int, origin: Vector2, direction: Vector2, sim) -> void:
	var traveling := bool(data.get("projectile", true))
	if traveling and _indexed_tick != sim.tick:
		_indexed_tick = sim.tick
		_native.clear()
		for p in sim.projectiles:
			if p.kind == _kind and p.weapon.id == _mode:
				_native[_key(p)] = p
	var native: Dictionary = _native.get(key, {}) if traveling else {}
	var target_id := int(source.get("attack_target_id", 0))
	if target_id == 0:
		target_id = int(source.get("locked_target_id", 0))
	var due := float(data.time)
	if not native.is_empty():
		due = float(native.impact_time)
		target_id = int(native.target_id)
	elif traveling:
		# The projectile can leave the native list in its launch tick.
		for weapon in sim.catalog[_kind].attack_modes:
			if weapon.id == _mode:
				var delivery: Dictionary = weapon.delivery
				if delivery.flight == "fixed":
					due += float(delivery.seconds)
				else:
					due += Vector2(data.from).distance_to(data.to) / maxf(0.001, float(delivery.speed))
				break
	var token := _contact_key(data.team, key[1], due)
	shots[key] = {"team":data.team, "side":side, "origin":origin, "direction":direction, "goal":data.to,
		"native":native, "target_id":target_id, "launch_time":float(data.time), "impact_time":due,
		"hit":false, "hit_pos":data.to, "released":false, "contact_key":token}
	if not _contacts.has(token):
		_contacts[token] = []
	_contacts[token].append(key)

func _record_hit(data: Dictionary, sim) -> void:
	# Native attack_hit identifies the victim, strike and exact delivery time.
	# Identical simultaneous contacts follow the simulator's projectile ID order.
	var token := _contact_key(data.team, data.strike, data.time)
	var candidates: Array = _contacts.get(token, [])
	var selected: Dictionary = {}
	for key in candidates:
		var shot: Dictionary = shots[key]
		if shot.has("hit_event") and is_same(shot.hit_event, data):
			return
		if shot.hit or (shot.target_id != 0 and shot.target_id != data.id):
			continue
		if selected.is_empty() or int(shot.native.get("id", 2147483647)) < int(selected.native.get("id", 2147483647)):
			selected = shot
	if selected.is_empty():
		return
	selected.target_id = data.id
	selected.hit = true
	selected.hit_event = data
	selected.hit_pos = selected.native.get("goal", selected.goal)
	# An instantaneous launch already carries the exact interpolated contact.
	if selected.native.is_empty() and float(selected.impact_time) > float(selected.launch_time):
		var victim = sim.by_id.get(data.id)
		if victim != null:
			var fraction := clampf(float(data.time) * float(sim.rules.tick_rate) - float(sim.tick - 1), 0.0, 1.0)
			selected.hit_pos = Vector2(victim.prev).lerp(victim.pos, fraction)

func _goal(shot: Dictionary, sim, now: float) -> Vector2:
	var goal: Vector2 = shot.hit_pos if shot.hit else shot.native.get("goal", shot.goal)
	if now >= shot.impact_time:
		return goal
	var target = sim.by_id.get(shot.target_id)
	if target == null:
		return goal
	var rate := float(sim.rules.tick_rate)
	var start := float(sim.tick - 1) / rate
	var span := minf(1.0 / rate, maxf(0.000001, float(shot.impact_time) - start))
	return Vector2(target.prev).lerp(goal, clampf((now - start) / span, 0.0, 1.0))

func draw_ordnance(canvas: CanvasItem, view, game, now: float) -> void:
	var area: Rect2 = game._camera_rect().grow(1.5)
	for shot in shots.values():
		if game._hidden_team(int(shot.team)) or now < shot.launch_time:
			continue
		var age := now - float(shot.impact_time)
		if age >= 0.0:
			if shot.hit and age < _ordnance.IMPACT_DURATION and area.has_point(shot.hit_pos):
				_draw_contact(canvas, view, shot.hit_pos, age, shot.side)
		elif shot.released:
			var progress := (now - float(shot.launch_time)) / (float(shot.impact_time) - float(shot.launch_time))
			var goal := _goal(shot, game.sim, now)
			if area.has_point(_ordnance.flight_position(shot.origin, goal, shot.direction, progress)):
				_ordnance.draw_flight(canvas, view, shot.origin, goal, shot.direction, progress)

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
	entry.pos = pos
	entry.dead = true
	entry.death_at = clock
	entry.actor.destroy()
