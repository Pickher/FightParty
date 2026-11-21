extends RefCounted
## Presentation state for visible walkers in the shared battle viewport.
const Actor = preload("res://scripts/visuals/thor_actor.gd")
const MODEL_PATH := "res://assets/models/thor/thor_rig.glb"
const MAX_LIVE := 16
const MAX_WRECKS := 6
const MODES := ["high_impact", "javelin", "hammer"]
var model: PackedScene
var scene: Node3D
var bounds: AABB
var entries: Dictionary = {}
var switches: Dictionary = {}
var launch_offsets: Dictionary = {}

func configure(shared_world: Node3D, resource: PackedScene, model_bounds: AABB) -> void:
	scene = shared_world
	model = resource
	bounds = model_bounds

func reset() -> void:
	for id in entries.keys():
		_remove(id)
	switches.clear()
	launch_offsets.clear()

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

func event(data: Dictionary, before: Dictionary, game, clock: float) -> void:
	if model == null or not game.sim.catalog.has("thor"):
		return
	var kind := str(data.type)
	if kind not in ["attack", "weapon_switch", "death"]:
		return
	if kind == "attack" and (data.get("kind") != "thor" or data.get("mode") not in MODES):
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
		return
	if not entries.has(id):
		var count := 0
		for entry in entries.values():
			if not entry.dead:
				count += 1
		if count >= MAX_LIVE:
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
	entry.actor.fire_at(mode, strike, target_offset)
	if data.get("projectile", false) and data.has("time"):
		var key := [id, strike, float(data.time)]
		launch_offsets[key] = entry.actor.muzzle_screen_offset(mode, strike) * diameter

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

func draw_javelin(canvas: CanvasItem, view, projectile: Dictionary, now: float) -> bool:
	if projectile.get("weapon", {}).get("id") != "javelin" or launch_offsets.is_empty():
		return false
	var key := _projectile_key(projectile)
	if not launch_offsets.has(key):
		return false
	var origin: Vector2 = projectile.origin + launch_offsets[key]
	var axis: Vector2 = view.point(projectile.goal) - view.point(origin)
	if axis.length_squared() < 0.000001:
		return false
	axis = axis.normalized()
	var tip: Vector2 = view.point(projectile.pos + projectile_offset(projectile, now))
	var body := clampf(view.pixels(0.22), 2.6, 8.5)
	var shoulder := tip - axis * body * 0.43
	var nozzle := tip - axis * body
	var span := axis.orthogonal() * maxf(0.85, body * 0.22)
	# One tracking projectile carries its own exhaust; the 3D tube flash stays at launch.
	var flicker := 0.85 + 0.15 * sin((now - float(projectile.launch_time)) * 47.0 + int(projectile.strike))
	var tail := nozzle - axis * clampf(view.pixels(0.35), 3.3, 12.0) * flicker
	canvas.draw_colored_polygon(PackedVector2Array([nozzle+span, tail, nozzle-span]), Color("fa7228"))
	canvas.draw_line(nozzle, nozzle.lerp(tail, 0.57), Color("ffe6a5"), maxf(1.0, body * 0.22), true)
	canvas.draw_colored_polygon(PackedVector2Array([tip, shoulder+span, nozzle+span*0.65,
		nozzle-span*0.65, shoulder-span]), Color("9fb9c7"))
	canvas.draw_line(shoulder, tip, Color("f2faff"), maxf(1.0, body * 0.26), true)
	return true

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
