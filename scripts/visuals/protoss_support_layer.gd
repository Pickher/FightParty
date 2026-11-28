extends RefCounted
## Visible ground support units in the battlefield's shared orthographic viewport.
const RigBounds = preload("res://scripts/visuals/rig_bounds.gd")
const PATHS := {
	"sentry": "res://assets/models/sentry/sentry_display.glb",
	"disruptor": "res://assets/models/disruptor/disruptor_display.glb",
}
const MAX_LIVE := 24
const SOLAR_IDLE := &"SolarIdle"
# Project a little of the unit's height towards screen north, as on the other ground models.
const PROJECTION := Basis(Vector3.RIGHT, Vector3(0, 1, -0.45), Vector3.BACK)

var models: Dictionary = {}
var entries: Dictionary = {}
var _headings: Dictionary = {}

func load_models() -> void:
	for kind in PATHS:
		var path: String = PATHS[kind]
		if not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		var box := RigBounds.from_scene(packed)
		var extent := maxf(box.size.x, box.size.z)
		if extent > 0.0001:
			var radius := 0.5 * (Vector2(box.size.x, box.size.z).length() + 0.45 * box.size.y)
			models[kind] = {"packed":packed, "center":box.get_center(), "extent":extent, "radius":radius / extent}

func reset() -> void:
	for id in entries.keys():
		_remove(id)
	_headings.clear()

func bar_clearance(id: int, dimensions: Vector2) -> float:
	# At full turn the upper edge of either model projects up to 0.56 footprints north.
	if entries.has(id):
		return maxf(dimensions.x, dimensions.y) * 0.58
	return dimensions.y * 0.5

func _remove(id: int) -> void:
	var root: Node3D = entries[id].root
	root.hide()
	root.queue_free()
	entries.erase(id)

func _create(scene: Node3D, kind: String, heading: float) -> Dictionary:
	var asset: Dictionary = models[kind]
	var model := (asset.packed as PackedScene).instantiate() as Node3D
	var player: AnimationPlayer
	if kind == "disruptor":
		player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player == null or not player.has_animation(SOLAR_IDLE):
			model.free()
			models.erase(kind)
			return {}
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var root := Node3D.new()
	var facing := Node3D.new()
	scene.add_child(root)
	root.add_child(facing)
	facing.add_child(model)
	model.position -= Vector3(asset.center)
	if player != null:
		player.play(SOLAR_IDLE)
	return {"root":root, "facing":facing, "model":model, "heading":heading, "player":player}

# Use the first active shield link, the offensive beam, or the ongoing nova's native goal.
func _activities(sim) -> Dictionary:
	var result := {}
	for beam in sim.active_beams:
		if beam.get("kind") == "sentry" and not result.has(beam.source_id):
			result[beam.source_id] = beam
	var areas = sim.get("skill_areas")
	if areas != null:
		for area in areas:
			if area.get("kind") == "disruptor":
				result[area.source_id] = area
	return result

func _target_direction(game, unit: Dictionary, pos: Vector2, alpha: float, activity: Dictionary) -> Vector2:
	if activity.has("origin"):
		return Vector2.ZERO if game._hidden_team(1 - int(unit.team)) else pos.direction_to(activity.pos)
	var target_id := int(activity.get("target_id", unit.get("locked_target_id", 0)))
	if target_id < 0 and not game._hidden_team(1 - int(unit.team)):
		return pos.direction_to(game.sim.base_pos(1 - int(unit.team)))
	var target = game.sim.by_id.get(target_id)
	if target == null or game._hidden_team(int(target.team)) or float(target.get("hp", 1.0)) <= 0.0:
		return Vector2.ZERO
	return pos.direction_to(Vector2(target.get("prev", target.pos)).lerp(target.pos, alpha))

func sync(scene: Node3D, game, view, dt: float, clock: float, alpha: float) -> void:
	if models.is_empty():
		return
	var camera_rect: Rect2 = game._camera_rect()
	var retained := {}
	var headings := {}
	var activities: Dictionary
	var indexed := false
	for unit in game.sim.units:
		if not models.has(unit.kind) or float(unit.get("hp", 1.0)) <= 0.0 or game._hidden_team(int(unit.team)):
			continue
		var motion: Vector2 = unit.pos - unit.prev
		var desired: float = motion.angle() if not motion.is_zero_approx() else _headings.get(unit.id, 0.0 if unit.team == 0 else PI)
		headings[unit.id] = desired
		if retained.size() >= MAX_LIVE:
			continue
		var pos: Vector2 = unit.prev.lerp(unit.pos, alpha)
		var asset: Dictionary = models[unit.kind]
		var size: Array = game.sim.catalog[unit.kind].size
		var diameter := maxf(float(size[0]), float(size[1]))
		if not camera_rect.grow(diameter * float(asset.radius)).has_point(pos):
			continue
		if motion.is_zero_approx():
			if not indexed:
				activities = _activities(game.sim)
				indexed = true
			var aim := _target_direction(game, unit, pos, alpha, activities.get(unit.id, {}))
			if not aim.is_zero_approx():
				desired = aim.angle()
				headings[unit.id] = desired
		var added := not entries.has(unit.id)
		if added:
			var created := _create(scene, unit.kind, desired)
			if created.is_empty():
				continue
			entries[unit.id] = created
		retained[unit.id] = true
		var entry: Dictionary = entries[unit.id]
		entry.heading = rotate_toward(float(entry.heading), desired, 5.0 * dt)
		entry.facing.rotation.y = -float(entry.heading)
		var p: Vector2 = view.point(pos)
		var scale: float = view.pixels(diameter) / float(asset.extent)
		entry.root.transform = Transform3D(PROJECTION.scaled(Vector3.ONE * scale), Vector3(p.x, -100.0, p.y))
		var player: AnimationPlayer = entry.player
		if player != null and (added or dt > 0.0):
			var phase := fposmod(clock + float(unit.id) * 0.37, player.current_animation_length)
			player.seek(phase, true)
	_headings = headings
	for id in entries.keys():
		if not retained.has(id):
			_remove(id)
