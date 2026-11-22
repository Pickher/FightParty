extends RefCounted
## Owns the articulated rig from the first frame of a vehicle's actual morph.
const Actor = preload("res://scripts/visuals/hellbat_actor.gd")
const MODEL_PATH := Actor.RIG_PATH
const MAX_LIVE := 24
const MAX_WRECKS := 8
const FLAME_DURATION := 0.32

var scene: Node3D
var model: PackedScene
var bounds := AABB()
var entries: Dictionary = {}
var travel_layer

func configure(world: Node3D, resource: PackedScene, box: AABB) -> void:
	scene = world
	model = resource
	bounds = box

func _remove(id: int) -> void:
	var actor: Actor = entries[id].actor
	actor.hide()
	actor.queue_free()
	entries.erase(id)

func reset() -> void:
	for id in entries.keys():
		_remove(id)

func has_model(id: int) -> bool:
	return entries.has(id) and not entries[id].dead

func _create(unit: Dictionary, pos: Vector2, heading: float, progress: float) -> Dictionary:
	# If this vehicle was visible last frame, unfold facing the way it actually drove.
	if travel_layer != null and travel_layer.has_model(unit.id):
		heading = travel_layer.entries[unit.id].actor.heading
	var actor := Actor.new()
	scene.add_child(actor)
	actor.setup(model, bounds, heading)
	actor.set_vehicle_progress(progress)
	return {"actor":actor, "team":unit.team, "pos":pos, "heading":heading,
		"diameter":1.0, "dead":false, "death_at":0.0, "last_shot":-INF}

func _place(entry: Dictionary, view) -> void:
	var point: Vector2 = view.point(entry.pos)
	entry.actor.position = Vector3(point.x, -100.0, point.y)
	entry.actor.scale = Vector3.ONE * view.pixels(entry.diameter)
	var actor: Actor = entry.actor
	if actor.vehicle_progress > 0:
		actor.position -= (actor.vehicle.global_position - actor.global_position) * actor.vehicle_progress

func sync(game, view, dt: float, alpha: float) -> void:
	if model == null or not game.sim.catalog.has("hellbat_mech"):
		return
	var mech_size: Array = game.sim.catalog.hellbat_mech.size
	var diameter := maxf(float(mech_size[0]), float(mech_size[1]))
	var car_size: Array = game.sim.catalog.hellbat.size
	var car_diameter := maxf(float(car_size[0]), float(car_size[1]))
	var area: Rect2 = game._camera_rect().grow(2.0 * maxf(diameter, car_diameter))
	var retained := {}
	for unit in game.sim.units:
		var transforming: bool = unit.kind == "hellbat" and unit.has("morph_start_tick")
		if (not transforming and unit.kind != "hellbat_mech") or game._hidden_team(int(unit.team)):
			continue
		var pos: Vector2 = unit.prev.lerp(unit.pos, alpha)
		if retained.size() >= MAX_LIVE or not area.has_point(pos):
			continue
		retained[unit.id] = true
		var progress := 0.0 # Actor progress runs from standing mech (0) to folded car (1).
		if transforming:
			var span: int = unit.morph_end_tick - unit.morph_start_tick
			progress = clampf((unit.morph_end_tick - (game.sim.tick - 1 + alpha)) / maxf(1.0, span), 0.0, 1.0)
		var motion: Vector2 = unit.pos - unit.prev
		var moving := motion.length_squared() > 0.000001
		if not entries.has(unit.id):
			var heading := motion.angle() if moving else (0.0 if unit.team == 0 else PI)
			entries[unit.id] = _create(unit, pos, heading, progress)
		var entry: Dictionary = entries[unit.id]
		var actor: Actor = entry.actor
		if not is_equal_approx(actor.vehicle_progress, progress):
			actor.set_vehicle_progress(progress)
		var delta_pos: Vector2 = pos - entry.pos
		entry.pos = pos
		if moving:
			entry.heading = motion.angle()
		var aim := NAN
		var target_id := int(unit.get("attack_target_id", 0))
		var target = game.sim.by_id.get(target_id)
		if target != null and not game._hidden_team(int(target.team)):
			aim = pos.angle_to_point(target.prev.lerp(target.pos, alpha))
		elif target_id < 0:
			aim = pos.angle_to_point(game.sim.base_pos(1 - int(unit.team)))
		entry.diameter = diameter
		if progress > 0:
			# Match the normal Hellion's size and center at the car endpoint.
			var car_factor: float = actor.length_factor * actor.vehicle.scale.x
			entry.diameter = lerpf(diameter, car_diameter / car_factor, progress)
		_place(entry, view)
		var distance := delta_pos.dot(Vector2.from_angle(actor.heading)) / float(entry.diameter)
		actor.advance(dt, entry.heading, distance if dt > 0 else 0.0, aim)
	for id in entries.keys():
		var entry: Dictionary = entries[id]
		if game._hidden_team(int(entry.team)) or not area.has_point(entry.pos):
			_remove(id)
		elif entry.dead:
			_place(entry, view)
			entry.actor.advance(dt, entry.heading, 0.0)
			if entry.actor.is_finished():
				_remove(id)
		elif not retained.has(id):
			_remove(id)

func fire(event: Dictionary) -> void:
	if not has_model(event.source_id):
		return
	var entry: Dictionary = entries[event.source_id]
	var actor: Actor = entry.actor
	if actor.vehicle_progress > 0.0:
		# Several simulation ticks can finish before the next draw on a busy frame.
		actor.set_vehicle_progress(0.0)
	var axis := Vector2(event.from).direction_to(event.to)
	var port := actor.to_local(actor.muzzle_world())
	var target_offset: Vector2 = (event.to - entry.pos) / float(entry.diameter)
	var reach := maxf(0.03, (target_offset - Vector2(port.x, port.z)).dot(axis))
	actor.fire(reach, FLAME_DURATION, axis.angle(), float(event.angle_degrees))
	entry.last_shot = float(event.time)

func destroy(event: Dictionary, now: float) -> void:
	if not has_model(event.id):
		return
	var wrecks := 0
	var oldest := -1
	for id in entries:
		if entries[id].dead:
			wrecks += 1
			if oldest < 0 or entries[id].death_at < entries[oldest].death_at:
				oldest = id
	if wrecks >= MAX_WRECKS:
		_remove(oldest)
	var entry: Dictionary = entries[event.id]
	entry.dead = true
	entry.death_at = now
	entry.pos = event.pos
	entry.actor.destroy()

func draw_fallback_flame(canvas: CanvasItem, view, event: Dictionary) -> void:
	var entry = entries.get(event.source_id)
	if entry != null and is_equal_approx(float(entry.last_shot), float(event.time)):
		return
	var origin: Vector2 = view.point(event.from)
	var axis: Vector2 = view.point(event.to) - origin
	var remaining := clampf(float(event.ttl) / FLAME_DURATION, 0.0, 1.0)
	var reach := axis.length() * minf(1.0, 0.5 + 2.5 * (1.0 - remaining))
	var spread := deg_to_rad(float(event.angle_degrees)) * 0.5
	for layer in 2:
		var flame := PackedVector2Array([origin])
		for i in 11:
			var angle := axis.angle() + spread * (i * 0.2 - 1.0)
			var edge := 1.0 - 0.12 * absf(sin(float(i * 2 + int(event.source_id)) + remaining * 7.0))
			flame.append(origin + Vector2.from_angle(angle) * reach * edge)
		var color := Color("fa7027") if layer == 0 else Color("ffdb70")
		color.a = remaining * (0.72 if layer == 0 else 0.90)
		canvas.draw_colored_polygon(flame, color)
		reach *= 0.73
		spread *= 0.55
