extends RefCounted
## Presents the native mortar unit and its two instantaneous cannon strikes.
const Actor = preload("res://scripts/visuals/tank_actor.gd")
const MODEL_PATH := Actor.RIG_PATH
const MOBILE := "mobile_cannon"
const SIEGE := "siege_cannon"
const MAX_LIVE := 16
const MAX_WRECKS := 6
const SHOT_DURATION := 0.13
const IMPACT_DURATION := 0.34
const DUST_ANGLES := [0.31, 1.71, 2.00, 3.22, 4.16, 5.54]
# Polar angle and reach for each individual ember.
const EMBERS := [Vector2(0.23, 1.07), Vector2(1.55, 0.66), Vector2(3.14, 1.34), Vector2(3.45, 0.78), Vector2(5.23, 1.12)]

static var _glow: ImageTexture
static var _dust: ImageTexture
static var _dust_ring: ImageTexture

var scene: Node3D
var model: PackedScene
var bounds: AABB
var entries: Dictionary = {}
var shots: Array[Dictionary] = []
# A partial deployment can be interrupted even between rendered frames or offscreen.
var _partial_packs: Dictionary = {}
var _last_headings: Dictionary = {}
var _event_tick := -1
var _tick_shots: Dictionary = {}
var _pose_tick := -1.0

func configure(shared: Node3D, resource: PackedScene, box: AABB) -> void:
	scene = shared
	model = resource
	bounds = box
	if model != null and _glow == null:
		_impact_textures()

func reset() -> void:
	for id in entries.keys():
		_remove(id)
	shots.clear()
	_tick_shots.clear()
	_partial_packs.clear()
	_last_headings.clear()
	_event_tick = -1
	_pose_tick = -1.0

func _remove(id: int) -> void:
	var actor: Node3D = entries[id].actor
	actor.hide()
	actor.queue_free()
	entries.erase(id)

func has_model(id: int) -> bool:
	return entries.has(id) and not entries[id].dead

func _diameter(sim) -> float:
	var size: Array = sim.catalog.mortar.size
	return maxf(float(size[0]), float(size[1]))

func _progress(id: int, unit: Dictionary, sim, tick: float) -> float:
	var state: String = unit.get("siege_state", "mobile")
	if state == "deployed":
		return 1.0
	if state not in ["deploying", "packing"]:
		return 0.0
	var config: Dictionary = sim.catalog.mortar.skills.deployment
	var seconds: float = config.deploy_seconds if state == "deploying" else config.pack_seconds
	var duration := maxi(1, ceili(seconds * float(sim.rules.tick_rate)))
	var remaining := clampf((float(unit.siege_until_tick) - tick) / duration, 0.0, 1.0)
	return 1.0 - remaining if state == "deploying" else remaining * float(_partial_packs.get(id, 1.0))

func observe_step(game, before: Dictionary) -> void:
	if model == null:
		return
	for id in before:
		var old: Dictionary = before[id]
		if old.kind != "mortar":
			continue
		var unit = game.sim.by_id.get(id)
		if unit == null:
			# The death event still needs this tank's interrupted pose and last heading.
			continue
		# Preserve orientation and partial folds across fog or camera changes.
		# Only sync/event are allowed to create a visible actor.
		var motion: Vector2 = unit.pos - unit.prev
		if motion.length_squared() > 0.000001:
			_last_headings[id] = motion.angle()
		if unit.get("siege_state", "mobile") != "packing":
			_partial_packs.erase(id)
		elif old.get("siege_state", "mobile") == "deploying":
			_partial_packs[id] = _progress(id, old, game.sim, float(game.sim.tick))

func _create(id: int, unit: Dictionary, pos: Vector2, progress: float) -> bool:
	var motion: Vector2 = unit.pos - unit.get("prev", unit.pos)
	var heading: float = motion.angle() if motion.length_squared() > 0.000001 else _last_headings.get(id, 0.0 if unit.team == 0 else PI)
	var actor := Actor.new()
	scene.add_child(actor)
	if not actor.setup(model, bounds, heading, progress):
		actor.hide()
		actor.queue_free()
		model = null
		return false
	entries[id] = {"actor": actor, "pos": pos, "team": unit.team, "heading": heading, "dead": false, "death_at": -1.0}
	return true

func _place(entry: Dictionary, view, diameter: float) -> void:
	var point: Vector2 = view.point(entry.pos)
	entry.actor.position = Vector3(point.x, -100.0, point.y)
	entry.actor.scale = Vector3.ONE * view.pixels(diameter)

func _aim(unit: Dictionary, game, pos: Vector2, alpha: float) -> float:
	var firing: bool = unit.get("attack_phase", "") in ["windup", "firing", "backswing"]
	var ids := [unit.get("attack_target_id", 0) if firing else 0, unit.get("locked_target_id", 0), unit.get("engage_id", 0)]
	for id in ids:
		var goal: Vector2
		if int(id) < 0 and firing:
			goal = game.sim.base_pos(1 - int(unit.team))
		else:
			var target = game.sim.by_id.get(id)
			if target == null or target.team == unit.team or target.get("hp", 1.0) <= 0.0 or game._hidden_team(int(target.team)):
				continue
			if game.sim.catalog.get(target.kind, {}).get("layer", "ground") != "ground":
				continue
			goal = Vector2(target.prev).lerp(target.pos, alpha)
		if pos.distance_squared_to(goal) > 0.000001:
			return pos.angle_to_point(goal)
	return NAN

func sync(game, view, dt: float, clock: float, alpha: float) -> void:
	if model == null or not game.sim.catalog.has("mortar"):
		return
	var diameter := _diameter(game.sim)
	var area: Rect2 = game._camera_rect().grow(2.0 * diameter)
	var retained := {}
	# Some UI panels clear the accumulator within the same tick.
	_pose_tick = maxf(_pose_tick, float(game.sim.tick) + alpha)
	for unit in game.sim.units:
		if unit.kind != "mortar" or game._hidden_team(int(unit.team)) or retained.size() >= MAX_LIVE:
			continue
		var pos: Vector2 = unit.prev.lerp(unit.pos, alpha)
		if not area.has_point(pos):
			continue
		var progress := _progress(unit.id, unit, game.sim, _pose_tick)
		if not entries.has(unit.id) and not _create(unit.id, unit, pos, progress):
			return
		retained[unit.id] = true
		var entry: Dictionary = entries[unit.id]
		var actor: Actor = entry.actor
		var motion: Vector2 = unit.pos - unit.prev
		if motion.length_squared() > 0.000001:
			entry.heading = motion.angle()
			_last_headings[unit.id] = entry.heading
		var distance := (pos - Vector2(entry.pos)).dot(Vector2.from_angle(actor.heading)) / diameter
		entry.pos = pos
		_place(entry, view, diameter)
		if not is_equal_approx(actor.deployment_progress, progress):
			actor.set_deployment_progress(progress)
		actor.advance(dt, entry.heading, distance if dt > 0.0 else 0.0, _aim(unit, game, pos, alpha))
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
	for i in range(shots.size() - 1, -1, -1):
		if clock - float(shots[i].at) >= IMPACT_DURATION or game._hidden_team(int(shots[i].team)):
			shots.remove_at(i)

func _ensure(id: int, unit: Dictionary, pos: Vector2, game) -> bool:
	if not game._camera_rect().grow(_diameter(game.sim) * 2.0).has_point(pos):
		return false
	if entries.has(id):
		return has_model(id)
	var count := 0
	for entry in entries.values():
		if not entry.dead:
			count += 1
	return count < MAX_LIVE and _create(id, unit, pos, _progress(id, unit, game.sim, float(game.sim.tick)))

func _destroy(entry: Dictionary, pos: Vector2, clock: float) -> void:
	var wrecks := 0
	var oldest := -1
	for id in entries:
		if entries[id].dead:
			wrecks += 1
			if oldest < 0 or entries[id].death_at < entries[oldest].death_at:
				oldest = id
	if wrecks >= MAX_WRECKS:
		_remove(oldest)
	entry.pos = pos
	entry.dead = true
	entry.death_at = clock
	entry.actor.destroy()

func event(data: Dictionary, before: Dictionary, game, clock: float) -> bool:
	if model == null or not game.sim.catalog.has("mortar"):
		return false
	if data.type in ["death", "expired"]:
		var unit: Dictionary = before.get(data.id, {})
		if unit.get("kind") != "mortar":
			return false
		if data.type == "death" and not game._hidden_team(int(unit.team)) and _ensure(data.id, unit, data.pos, game):
			_destroy(entries[data.id], data.pos, clock)
		_last_headings.erase(data.id)
		_partial_packs.erase(data.id)
		return false
	if data.get("kind") != "mortar" or game._hidden_team(int(data.team)):
		return false
	if _event_tick != game.sim.tick:
		_tick_shots.clear()
		_event_tick = game.sim.tick
	if data.type == "area_impact" or data.type == "attack_hit":
		return _contact(data)
	if data.type != "attack" or data.get("mode") not in [MOBILE, SIEGE] or data.get("projectile", false) or not data.has("time"):
		return false
	var id := int(data.get("source_id", -1))
	var unit: Dictionary = game.sim.by_id.get(id, before.get(id, {}))
	if unit.get("kind") != "mortar":
		return false
	var key := [id, int(data.get("strike", 0)), float(data.time)]
	if _tick_shots.has(key):
		return _tick_shots[key].owned
	var owned := _ensure(id, unit, data.from, game)
	var target_id := int(unit.get("attack_target_id", 0))
	if target_id == 0:
		target_id = int(unit.get("locked_target_id", 0))
	# Keep unowned launches in the current step's matching order. An offscreen
	# gun can fire at the same position as a modeled gun on the very same tick.
	var shot := {"team": data.team, "mode": data.mode, "goal": data.to, "origin": data.from,
		"owned": owned, "at": clock, "time": float(data.time), "target_id": target_id,
		"hit": target_id < 0, "radius": float(data.get("splash", 0.0)), "contact": {}}
	_tick_shots[key] = shot
	if owned:
		var entry: Dictionary = entries[id]
		var actor: Actor = entry.actor
		var diameter := _diameter(game.sim)
		actor.set_deployment_progress(1.0 if data.mode == SIEGE else 0.0)
		actor.fire_at(data.mode, (Vector2(data.to) - Vector2(entry.pos)) / diameter)
		shot.origin = Vector2(entry.pos) + actor.muzzle_screen_offset(data.mode) * diameter
		shots.append(shot)
	return owned

func _contact(data: Dictionary) -> bool:
	var area: bool = data.type == "area_impact"
	if not area and (data.get("mode") != MOBILE or not data.has("time")):
		return false
	var selected: Dictionary = {}
	for shot in _tick_shots.values():
		if not shot.contact.is_empty() and is_same(shot.contact, data):
			return area and shot.owned
		if shot.hit or shot.team != data.team:
			continue
		if area:
			if shot.mode != SIEGE or Vector2(shot.goal).distance_squared_to(data.to) > 0.000001:
				continue
		elif shot.mode != MOBILE or absf(float(shot.time) - float(data.time)) > 0.000001 or (shot.target_id != 0 and shot.target_id != data.id):
			continue
		# The projectile service settles by delivery time, then original launch order.
		if selected.is_empty() or float(shot.time) < float(selected.time):
			selected = shot
	if selected.is_empty():
		return false
	selected.contact = data
	selected.hit = true
	if area:
		selected.goal = data.to
		selected.radius = data.radius
	return area and selected.owned

func draw_ordnance(canvas: CanvasItem, view, game, clock: float) -> void:
	if shots.is_empty():
		return
	var area: Rect2 = game._camera_rect()
	for shot in shots:
		if game._hidden_team(int(shot.team)):
			continue
		var age := clock - float(shot.at)
		if age < SHOT_DURATION and area.grow(0.7).has_point(shot.origin):
			draw_shot(canvas, view, shot.origin, shot.goal, shot.mode, age)
		if shot.hit and area.grow(maxf(0.6, float(shot.radius))).has_point(shot.goal):
			draw_impact(canvas, view, shot.goal, shot.mode, shot.radius, age)

## Short incandescent particles local to the bore. Both native cannons deliver instantly.
static func draw_shot(canvas: CanvasItem, view, origin: Vector2, goal: Vector2, mode: String, age: float) -> void:
	if age < 0.0 or age >= SHOT_DURATION:
		return
	var phase := age / SHOT_DURATION
	var root: Vector2 = view.point(origin)
	var axis: Vector2 = root.direction_to(view.point(goal))
	var length := float(view.pixels(0.54 if mode == SIEGE else 0.29))
	for i in 3:
		var ray := axis.rotated((float(i) - 1.0) * 0.19)
		var tip := root + ray * length * (0.18 + 0.82 * phase) * (0.75 if i != 1 else 1.0)
		canvas.draw_line(tip - ray * length * 0.16 * (1.0 - phase), tip,
			Color(1.0, 0.75, 0.39, 0.90 * (1.0 - phase)), maxf(1.0, length * 0.07), true)

## Bake soft lit dust, shell pressure and incandescent gradients once for every impact.
static func _impact_textures() -> void:
	var size := 96
	var glow := Image.create_empty(size, size, true, Image.FORMAT_RGBA8)
	var cloud := Image.create_empty(size, size, true, Image.FORMAT_RGBA8)
	var ring := Image.create_empty(size, size, true, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 5029
	noise.frequency = 0.069
	noise.fractal_octaves = 3
	for y in size:
		for x in size:
			var uv := (Vector2(x + 0.5, y + 0.5) / float(size) - Vector2(0.5, 0.5)) * 2.0
			var r := uv.length()
			var grain := noise.get_noise_2d(x, y)
			var a := exp(-4.6 * r * r) * (1.0 - smoothstep(0.80, 1.0, r))
			glow.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
			# The illuminated side and lobed boundary give even a small puff some depth.
			var light := clampf(0.81 - uv.dot(Vector2(0.20, 0.29)) + grain * 0.30, 0.48, 1.0)
			a = (1.0 - smoothstep(0.16, 0.88, r + grain * 0.29)) * (0.83 + 0.17 * grain)
			cloud.set_pixel(x, y, Color(light, light, light, a))
			var ridge := (r - 0.84 - grain * 0.043) / (0.044 + 0.019 * (1.0 + grain))
			a = exp(-ridge * ridge) * clampf(0.52 + grain * 1.12, 0.06, 0.98)
			ring.set_pixel(x, y, Color(light, light, light, a))
	for image in [glow, cloud, ring]:
		image.generate_mipmaps()
	_glow = ImageTexture.create_from_image(glow)
	_dust = ImageTexture.create_from_image(cloud)
	_dust_ring = ImageTexture.create_from_image(ring)

static func _stamp(canvas: CanvasItem, texture: Texture2D, pos: Vector2, extent: Vector2, tint: Color) -> void:
	canvas.draw_texture_rect(texture, Rect2(pos - extent, extent * 2.0), false, tint)

static func draw_impact(canvas: CanvasItem, view, goal: Vector2, mode: String, radius: float, age: float) -> void:
	var siege := mode == SIEGE
	var duration := IMPACT_DURATION if siege else 0.19
	if age < 0.0 or age >= duration:
		return
	if _glow == null:
		_impact_textures()
	var phase := age / duration
	var travel := sqrt(phase)
	var center: Vector2 = view.point(goal)
	var size := clampf(float(view.pixels(0.63 if siege else 0.29)), 4.6 if siege else 3.2, 68.0 if siege else 36.0)
	var seed := fposmod(goal.dot(Vector2(3.1, 1.7)), TAU)
	var fade := 1.0 - smoothstep(0.32, 1.0, phase)
	if siege:
		var dust := smoothstep(0.0, 0.17, phase) * fade
		if radius > 0.0:
			# The peak of the dust rim reaches the native full splash radius (0.84 of the stamp).
			var extent := float(view.pixels(radius)) * lerpf(0.12, 1.0, 1.0 - pow(1.0 - phase, 2.0)) / 0.84
			_stamp(canvas, _dust_ring, center, Vector2.ONE * extent, Color(0.85, 0.73, 0.55, 0.76 * dust))
		for i in DUST_ANGLES.size():
			var angle := seed + float(DUST_ANGLES[i])
			var direction := Vector2.from_angle(angle)
			var drift := direction * size * (0.10 + travel * (0.66 + 0.13 * (i % 3)))
			var p := center + drift + Vector2.UP * size * phase * 0.42
			var extent := Vector2(1.0, 0.85) * size * (0.23 + 0.43 * travel) * (0.88 + 0.11 * (i % 3))
			_stamp(canvas, _dust, p, extent, Color(0.58, 0.52, 0.46, 0.79 * dust))
			_stamp(canvas, _dust, p - extent * 0.20, extent * 0.77, Color(0.81, 0.73, 0.62, 0.49 * dust))
	var flash := 1.0 - smoothstep(0.06, 0.66, phase)
	if flash > 0.0:
		var fire_size := size * (0.48 + 0.41 * sin(PI * travel))
		_stamp(canvas, _glow, center, Vector2(1.12, 0.94) * fire_size, Color(1.0, 0.39, 0.09, 0.98 * flash))
		for i in 3:
			var offset := Vector2.from_angle(seed + float(i) * 2.23) * fire_size * (0.10 + 0.18 * travel)
			var lobe := Vector2.ONE * fire_size * (0.51 - 0.08 * i)
			_stamp(canvas, _dust, center + offset, lobe, Color(1.0, 0.79, 0.43, flash))
		_stamp(canvas, _glow, center, Vector2(1.0, 0.87) * fire_size * 0.57, Color(1.0, 0.99, 0.90, flash))
	# A few incandescent chips separate late enough to leave a single hot initial contact.
	for i in (EMBERS.size() if siege else 4):
		var ember: Vector2 = EMBERS[i]
		var ray := Vector2.from_angle(seed + ember.x) * size * ember.y
		var tip := center + ray * (0.09 + 1.03 * travel) + Vector2.DOWN * size * 0.36 * phase * phase
		var chip := maxf(1.25, size * (0.081 + 0.018 * (i % 3))) * (1.0 - phase * 0.40)
		var tail := tip - ray * 0.10 * fade
		_stamp(canvas, _glow, tail, Vector2.ONE * chip * 1.5, Color(1.0, 0.43, 0.12, 0.71 * fade))
		_stamp(canvas, _glow, tip.lerp(tail, 0.41), Vector2.ONE * chip * 1.12, Color(1.0, 0.70, 0.32, 0.95 * fade))
		_stamp(canvas, _glow, tip, Vector2.ONE * chip, Color(1.0, 0.93, 0.72, fade))
