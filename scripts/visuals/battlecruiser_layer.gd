extends RefCounted

const Actor = preload("res://scripts/visuals/battlecruiser_actor.gd")
const Yamato = preload("res://scripts/skills/yamato.gd")
const MODEL_PATH := "res://assets/models/battlecruiser/battlecruiser.glb"
const MAX_LIVE := 24
const MAX_WRECKS := 8
const AIM_HOLD := 0.30

var scene: Node3D
var model: PackedScene
var bounds: AABB
var entries: Dictionary = {}
var traces: Array[Dictionary] = []

func configure(shared_world: Node3D, resource: PackedScene, model_bounds: AABB) -> void:
	scene = shared_world
	model = resource
	bounds = model_bounds

func reset() -> void:
	for id in entries.keys():
		_remove(id)
	traces.clear()

func _remove(id: int) -> void:
	var actor: Node3D = entries[id].actor
	actor.hide()
	actor.queue_free()
	entries.erase(id)

func has_model(id: int) -> bool:
	return entries.has(id) and not entries[id].dead

func _create(id: int, team: int, pos: Vector2, heading: float) -> Dictionary:
	var actor = Actor.new()
	scene.add_child(actor)
	actor.setup(model, bounds, heading)
	var entry := {"actor": actor, "team": team, "pos": pos, "heading": heading,
		"aim_until": -1.0, "dead": false, "death_at": -1.0}
	entries[id] = entry
	return entry

func _live_count() -> int:
	var count := 0
	for entry in entries.values():
		if not entry.dead:
			count += 1
	return count

func _ship_size(game) -> float:
	var body: Array = game.sim.catalog["battlecruiser"].size
	return maxf(float(body[0]), float(body[1]))

func _place(entry: Dictionary, view, ship_size: float) -> void:
	var p: Vector2 = view.point(entry.pos)
	entry.actor.position = Vector3(p.x, 0, p.y)
	entry.actor.scale = Vector3.ONE * view.pixels(ship_size)

func sync(game, view, dt: float, clock: float, alpha: float) -> void:
	if model == null or not game.sim.catalog.has("battlecruiser"):
		return
	var diameter := _ship_size(game)
	var visible_area: Rect2 = game._camera_rect().grow(diameter * 2.0)
	var retained: Dictionary = {}
	for unit in game.sim.units:
		if unit.kind != "battlecruiser" or game._hidden_team(int(unit.team)):
			continue
		var pos: Vector2 = unit.prev.lerp(unit.pos, alpha)
		if not visible_area.has_point(pos) or retained.size() >= MAX_LIVE:
			continue
		var id := int(unit.id)
		retained[id] = true
		var motion: Vector2 = unit.pos - unit.prev
		var moving := motion.length_squared() > 0.000001
		if not entries.has(id):
			var initial := motion.angle() if moving else (0.0 if unit.team == 0 else PI)
			_create(id, unit.team, pos, initial)
		var entry: Dictionary = entries[id]
		entry.pos = pos
		var charge := Yamato.charge(game.sim, unit)
		var target = game.sim.by_id.get(unit.get("yamato_target", -1))
		if charge >= 0.0 and target != null:
			var aim: Vector2 = target.pos - pos
			if aim.length_squared() > 0.000001:
				entry.heading = aim.angle()
		elif moving and clock >= entry.aim_until:
			entry.heading = motion.angle()
		_place(entry, view, diameter)
		entry.actor.set_charge(charge >= 0.0, maxf(charge, 0.0))
		entry.actor.advance(dt, entry.heading)

	for id in entries.keys():
		var entry: Dictionary = entries[id]
		if game._hidden_team(int(entry.team)) or not visible_area.has_point(entry.pos):
			_remove(id)
		elif entry.dead:
			_place(entry, view, diameter)
			entry.actor.advance(dt, entry.heading)
			if entry.actor.is_finished():
				_remove(id)
		elif not retained.has(id):
			_remove(id)
	for i in range(traces.size() - 1, -1, -1):
		if clock - float(traces[i].at) >= float(traces[i].duration) or game._hidden_team(int(traces[i].team)):
			traces.remove_at(i)

# Yamato's release event carries an origin but no source ID. Only match ships
# whose channel was due on this tick, using the target to resolve stacked hulls.
func _yamato_source(event_data: Dictionary, before: Dictionary, game) -> int:
	var best := -1
	var distance := INF
	for id in before:
		var ship: Dictionary = before[id]
		if ship.kind != "battlecruiser" or ship.team != event_data.team or (ship.fire_tick < 0 or ship.fire_tick > game.sim.tick) or ship.get("released", false):
			continue
		var origin: Vector2 = event_data.from
		if not origin.is_equal_approx(ship.pos):
			continue
		# The release target coordinate is from step start, before moves and deaths.
		var error: float = ship.target_pos.distance_squared_to(event_data.to)
		if error < distance:
			distance = error
			best = id
	if best >= 0:
		# This private step snapshot is consumed once per simultaneous release.
		before[best]["released"] = true
	return best

func event(event_data: Dictionary, before: Dictionary, game, clock: float) -> bool:
	if model == null:
		return false
	var kind := str(event_data.type)
	var id := -1
	if kind == "death":
		id = int(event_data.id)
		if not before.has(id) or before[id].kind != "battlecruiser":
			return false
	elif kind in ["attack", "yamato"] and event_data.kind == "battlecruiser":
		id = int(event_data.get("source_id", -1)) if kind == "attack" else _yamato_source(event_data, before, game)
	else:
		return false

	var pos: Vector2 = event_data.pos if kind == "death" else event_data.from
	var team := int(event_data.team)
	var diameter := _ship_size(game)
	if id < 0 or game._hidden_team(team) or not game._camera_rect().grow(diameter * 2.0).has_point(pos):
		return false
	if not entries.has(id):
		if _live_count() >= MAX_LIVE:
			return false
		_create(id, team, pos, 0.0 if team == 0 else PI)
	var entry: Dictionary = entries[id]
	if entry.dead:
		return false
	if kind == "death":
		var oldest_id := -1
		var oldest_at := INF
		var count := 0
		for other_id in entries:
			var other: Dictionary = entries[other_id]
			if other.dead:
				count += 1
				if float(other.death_at) < oldest_at:
					oldest_at = other.death_at
					oldest_id = other_id
		if count >= MAX_WRECKS:
			_remove(oldest_id)
		entry.dead = true
		entry.death_at = clock
		entry.pos = pos
		entry.actor.destroy()
		return true

	var direction: Vector2 = event_data.to - pos
	if direction.length_squared() > 0.000001:
		entry.heading = direction.angle()
	entry.aim_until = clock + AIM_HOLD
	var heavy := kind == "yamato"
	if heavy:
		entry.actor.fire_yamato()
	else:
		entry.actor.fire("air" if event_data.get("mode", "") == "ata_laser" else "ground")
	# Store the socket in world cells for camera movement and source removal.
	# Draw the main beam from the current muzzle while the recoiling hull is visible.
	var offset: Vector2 = entry.actor.muzzle_screen_offset(heavy) * diameter
	traces.append({"kind": kind, "id": id, "team": team, "from": pos, "offset": offset,
		"to": event_data.to, "at": clock, "duration": 0.48 if heavy else 0.105,
		"launch_time": event_data.get("time", -1.0)})
	return true

func owns_projectile(projectile: Dictionary) -> bool:
	if projectile.kind != "battlecruiser":
		return false
	for trace in traces:
		if trace.id == projectile.source_id and trace.kind == "attack" and is_equal_approx(trace.launch_time, projectile.launch_time):
			return true
	return false

func draw_traces(canvas: CanvasItem, view, clock: float) -> void:
	for trace in traces:
		var start: Vector2 = view.point(trace.from + trace.offset)
		if trace.kind == "yamato" and has_model(trace.id):
			var socket: Vector3 = entries[trace.id].actor.muzzle_world(true)
			start = Vector2(socket.x, socket.z)
		var finish: Vector2 = view.point(trace.to)
		var t := clampf((clock - float(trace.at)) / float(trace.duration), 0, 1)
		var fade := 1.0 - t
		if trace.kind == "yamato":
			_draw_yamato_beam(canvas, start, finish, view.pixels(1.0), t)
		else:
			var tip := start.lerp(finish, minf(1.0, 0.10 + t * 1.35))
			var tail := start.lerp(finish, clampf(t * 1.35 - 0.34, 0, 1))
			var width := maxf(1.2, view.pixels(0.05))
			canvas.draw_line(tail, tip, Color(1.0, 0.48, 0.12, fade * 0.8), width * 1.8, true)
			canvas.draw_line(tail.lerp(tip, 0.33), tip, Color(1.0, 0.93, 0.76, fade), width, true)

func _draw_yamato_beam(canvas: CanvasItem, start: Vector2, finish: Vector2, cell: float, t: float) -> void:
	var fade := 1.0 - t
	var tip := start.lerp(finish, minf(1.0, 0.28 + t * 9.0))
	var radius := maxf(1.8, cell * 0.21) * fade
	var direction := tip - start
	if direction.length_squared() > 0.001:
		var normal := direction.normalized().orthogonal()
		var color := Color(1.0, 0.37, 0.08, fade * 0.36)
		canvas.draw_colored_polygon(PackedVector2Array([start + normal * radius * 0.40,
			tip + normal * radius, tip - normal * radius, start - normal * radius * 0.40]), color)
		canvas.draw_line(start, tip, Color(1.0, 0.64, 0.22, fade), maxf(1.5, radius * 0.70), true)
		canvas.draw_line(start, tip, Color(1.0, 0.98, 0.87, fade), maxf(1.0, radius * 0.23), true)
	if t >= 0.08:
		var impact := (t - 0.08) / 0.92
		var glow := maxf(2.5, cell * 0.26)
		canvas.draw_circle(finish, glow * (1.0 + impact * 0.5), Color(1.0, 0.40, 0.10, fade * 0.18))
		canvas.draw_circle(finish, glow * 0.57 * fade, Color(1.0, 0.79, 0.45, fade * 0.82))
		canvas.draw_arc(finish, maxf(1.0, glow * (0.35 + impact * 1.8)), 0, TAU, 32,
			Color(1.0, 0.83, 0.55, fade * fade), maxf(1.0, cell * 0.025 * fade), true)
