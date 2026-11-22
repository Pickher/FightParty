extends RefCounted

const Actor = preload("res://scripts/visuals/hellion_actor.gd")
const MODEL_PATH := "res://assets/models/hellbat/hellion_rig.glb"
const MAX_LIVE := 24
const MAX_WRECKS := 8
var model: PackedScene
var bounds := AABB()
var scene: Node3D
var entries: Dictionary = {}
var _clock := 0.0
var _composite_ground_only := false

func initialize(host) -> void:
	if not host.ready_model or not ResourceLoader.exists(MODEL_PATH):
		return
	model = load(MODEL_PATH) as PackedScene
	if model == null:
		return
	var probe := model.instantiate()
	var boxes: Array = []
	host._collect_bounds(probe, Transform3D.IDENTITY, boxes)
	probe.free()
	if boxes.is_empty():
		model = null
		return
	bounds = boxes[0]
	for box in boxes:
		bounds = bounds.merge(box)
	scene = host.scene
	host.hellbat_mechs.travel_layer = self

func reset() -> void:
	for id in entries.keys():
		_remove(id)
	_clock = 0.0

# The aircraft renderer owns this viewport and already composites its texture
# for its own actors. When only ground vehicles are present, wake and draw it here.
func sync_shared(view, host, delta: float) -> void:
	if model == null:
		return
	var game = host.game
	var paused: bool = not game.started or game.paused or game.backgrounded or game.help_open or game.economy_open or game.setup_open
	var dt := 0.0 if paused else minf(delta, 0.1)
	var alpha := clampf(float(game.accumulator) * float(game.sim.rules.tick_rate), 0.0, 1.0)
	sync(game, view, dt, alpha)
	_composite_ground_only = not entries.is_empty() and host.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
	if _composite_ground_only:
		host.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func draw_if_ground_only(canvas: CanvasItem, host, view) -> void:
	if _composite_ground_only and not entries.is_empty():
		canvas.draw_texture_rect(host.viewport.get_texture(), Rect2(Vector2.ZERO, view.viewport_size()), false)

func _remove(id: int) -> void:
	var actor: Node3D = entries[id].actor
	actor.hide()
	actor.queue_free()
	entries.erase(id)

func has_model(id: int) -> bool:
	return entries.has(id) and not entries[id].dead

func _create(unit: Dictionary, pos: Vector2, heading: float) -> Dictionary:
	var actor = Actor.new()
	scene.add_child(actor)
	actor.setup(model, bounds, heading)
	var entry := {"actor": actor, "team": unit.team, "pos": pos, "heading": heading,
		"dead": false, "death_at": 0.0, "flame_until": -1.0, "last_wave": Vector2i(-1, -1)}
	entries[unit.id] = entry
	return entry

func _diameter(game) -> float:
	var size: Array = game.sim.catalog.hellbat.size
	return maxf(float(size[0]), float(size[1]))

func _position(entry: Dictionary, view, diameter: float) -> void:
	var screen: Vector2 = view.point(entry.pos)
	# Ground hulls are always below craft in the shared top-down orthographic world.
	entry.actor.position = Vector3(screen.x, -100.0, screen.y)
	entry.actor.scale = Vector3.ONE * view.pixels(diameter)

func _target_point(game, unit: Dictionary, alpha: float) -> Variant:
	var firing: bool = unit.get("attack_phase", "idle") in ["windup", "firing", "backswing"]
	var ids := [unit.get("attack_target_id", 0) if firing else 0,
		unit.get("locked_target_id", 0), unit.get("engage_id", 0)]
	for id in ids:
		if int(id) < 0 and firing:
			return game.sim.base_pos(1 - int(unit.team))
		var target = game.sim.by_id.get(id)
		if target != null and target.team != unit.team and target.get("hp", 1.0) > 0.0 and not game._hidden_team(int(target.team)):
			return target.prev.lerp(target.pos, alpha)
	return null

func sync(game, view, dt: float, alpha: float) -> void:
	if model == null or not game.sim.catalog.has("hellbat"):
		return
	_clock += dt
	var diameter := _diameter(game)
	var area: Rect2 = game._camera_rect().grow(diameter * 2.0)
	var retained: Dictionary = {}
	for unit in game.sim.units:
		if unit.kind != "hellbat" or game._hidden_team(int(unit.team)):
			continue
		if unit.has("morph_start_tick") and game.medivac_visual.hellbat_mechs.has_model(unit.id):
			continue
		var pos: Vector2 = unit.prev.lerp(unit.pos, alpha)
		if retained.size() >= MAX_LIVE or not area.has_point(pos):
			continue
		retained[unit.id] = true
		var motion: Vector2 = unit.pos - unit.prev
		var moving := motion.length_squared() > 0.000001
		if not entries.has(unit.id):
			_create(unit, pos, motion.angle() if moving else (0.0 if unit.team == 0 else PI))
		var entry: Dictionary = entries[unit.id]
		var odometer: float = (pos - Vector2(entry.pos)).dot(Vector2.from_angle(entry.actor.heading)) / diameter
		entry.pos = pos
		if moving:
			entry.heading = motion.angle()
		var target_offset := Vector2.INF
		if _clock >= entry.flame_until:
			var target = _target_point(game, unit, alpha)
			if target != null:
				target_offset = (Vector2(target) - pos) / diameter
		_position(entry, view, diameter)
		entry.actor.advance(dt, entry.heading, odometer if dt > 0 else 0.0, NAN, target_offset)

	for id in entries.keys():
		var entry: Dictionary = entries[id]
		if game._hidden_team(int(entry.team)) or not area.has_point(entry.pos):
			_remove(id)
		elif entry.dead:
			_position(entry, view, diameter)
			entry.actor.advance(dt, entry.heading, 0.0)
			if entry.actor.is_finished():
				_remove(id)
		elif not retained.has(id):
			_remove(id)

# The public line_attack drawing segment has no source ID. Keep references to the
# waves before advance removes a completed wave; their own final distance is updated in place.
func before_step(sim) -> Array:
	var waves: Array = []
	if model != null:
		for wave in sim.attack_waves:
			if wave.kind == "hellbat" and wave.effect == "flame":
				waves.append(wave)
	return waves

func observe_step(game, previous: Array, events: Array) -> Dictionary:
	var owned: Dictionary = {}
	if model == null or not game.sim.catalog.has("hellbat"):
		return owned
	# Index only Hellion wavefronts. One bucket can contain several overlapping shots.
	var by_tip: Dictionary = {}
	var seen: Dictionary = {}
	for wave in previous + game.sim.attack_waves:
		if wave.kind != "hellbat" or wave.effect != "flame":
			continue
		var token := Vector3i(wave.source_id, wave.born, wave.strike)
		if seen.has(token):
			continue
		seen[token] = true
		var tip: Vector2 = wave.origin + wave.direction * float(wave.distance)
		if not by_tip.has(tip):
			by_tip[tip] = []
		by_tip[tip].append(wave)
	for i in events.size():
		var event: Dictionary = events[i]
		if event.type == "death" and has_model(event.id):
			_destroy(event.id, event.pos)
		elif event.type == "line_attack" and event.kind == "hellbat" and event.effect == "flame":
			var matches: Array = by_tip.get(event.to, [])
			for j in matches.size():
				var wave: Dictionary = matches[j]
				if event.team != wave.team or event.source != wave.source:
					continue
				matches.remove_at(j)
				if has_model(wave.source_id) and not game._hidden_team(int(wave.team)):
					var entry: Dictionary = entries[wave.source_id]
					var token := Vector2i(wave.born, wave.strike)
					# Never restart a plume for each segment. A hull entering the view mid-wave
					# keeps the existing travelling 2D segment instead of replaying a late shot.
					if entry.last_wave != token and Vector2(event.from).is_equal_approx(wave.origin):
						entry.last_wave = token
						var diameter := _diameter(game)
						var direction: Vector2 = wave.direction
						var nozzle: Vector2 = entry.actor.aim_nozzle(direction.angle())
						var reach := maxf(0.03, float(wave.length) / diameter - nozzle.dot(direction))
						var duration := reach * diameter / float(wave.speed)
						entry.flame_until = _clock + duration + Actor.FLAME_AFTERGLOW
						entry.actor.fire(reach, duration)
					if entry.last_wave == token:
						owned[i] = int(wave.source_id)
				break
	return owned

func _destroy(id: int, pos: Vector2) -> void:
	var wrecks := 0
	var oldest := -1
	for other in entries:
		if not entries[other].dead:
			continue
		wrecks += 1
		if oldest == -1 or entries[other].death_at < entries[oldest].death_at:
			oldest = other
	if wrecks >= MAX_WRECKS:
		_remove(oldest)
	var entry: Dictionary = entries[id]
	entry.dead = true
	entry.death_at = _clock
	entry.pos = pos
	entry.actor.destroy()
