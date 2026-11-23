extends RefCounted
## Presentation of deployed ground Vikings in the shared orthographic battlefield.
const MODEL_PATH := "res://assets/models/viking/viking_assault_rig.glb"
const MAX_LIVE := 24
var scene: Node3D
var model: PackedScene
var bounds := AABB()
var entries: Dictionary = {}

func configure(world: Node3D, resource: PackedScene, box: AABB) -> void:
	scene = world
	model = resource
	bounds = box

func _remove(id: int) -> void:
	entries[id].root.hide()
	entries[id].root.queue_free()
	entries.erase(id)

func reset() -> void:
	for id in entries.keys():
		_remove(id)

func _create(heading: float, position: Vector2) -> Dictionary:
	var root := Node3D.new()
	scene.add_child(root)
	# The battlefield camera looks straight down. Project some of the mech's
	# height towards screen north, matching the other ground walkers.
	var pitch := Node3D.new()
	root.add_child(pitch)
	pitch.basis = Basis(Vector3.RIGHT, Vector3(0, 1, -0.56), Vector3.BACK)
	var facing := Node3D.new()
	pitch.add_child(facing)
	facing.rotation.y = -heading
	var rig := model.instantiate() as Node3D
	facing.add_child(rig)
	rig.position = -bounds.get_center()
	var left_gun := rig.find_child("GunLeft", true, false) as Node3D
	var right_gun := rig.find_child("GunRight", true, false) as Node3D
	return {"root":root, "facing":facing, "heading":heading, "pos":position,
		"phase":0.0, "stride":0.0, "left_leg":rig.find_child("LegLeft", true, false),
		"right_leg":rig.find_child("LegRight", true, false), "left_gun":left_gun, "right_gun":right_gun,
		"left_rest":left_gun.position.x, "right_rest":right_gun.position.x, "recoil":0.0}

func fire(id: int) -> void:
	if entries.has(id):
		entries[id].recoil = 1.0

func sync(game, view, dt: float, alpha: float) -> void:
	if model == null or not game.sim.catalog.has("viking_assault"):
		return
	var size: Array = game.sim.catalog.viking_assault.size
	var diameter := maxf(float(size[0]), float(size[1]))
	var area: Rect2 = game._camera_rect().grow(diameter)
	var retained := {}
	for unit in game.sim.units:
		if unit.kind != "viking_assault" or game._hidden_team(int(unit.team)):
			continue
		var pos: Vector2 = unit.prev.lerp(unit.pos, alpha)
		if retained.size() >= MAX_LIVE or not area.has_point(pos):
			continue
		retained[unit.id] = true
		var motion: Vector2 = unit.pos - unit.prev
		var moving := motion.length_squared() > 0.000001
		if not entries.has(unit.id):
			var initial := motion.angle() if moving else (0.0 if unit.team == 0 else PI)
			entries[unit.id] = _create(initial, pos)
		var entry: Dictionary = entries[unit.id]
		var heading := float(entry.heading)
		if moving:
			heading = motion.angle()
		elif int(unit.attack_target_id) != 0:
			var target = game.sim.by_id.get(unit.attack_target_id)
			if target != null:
				heading = pos.angle_to_point(target.pos)
			elif unit.attack_target_id < 0:
				heading = pos.angle_to_point(game.sim.base_pos(1 - int(unit.team)))
		entry.heading = rotate_toward(float(entry.heading), heading, dt * 7.0)
		entry.facing.rotation.y = -float(entry.heading)
		entry.stride = move_toward(float(entry.stride), 1.0 if moving else 0.0, dt * 8.0)
		entry.phase = fmod(float(entry.phase) + pos.distance_to(entry.pos) * TAU / diameter, TAU)
		var swing := 0.24 * sin(float(entry.phase)) * float(entry.stride)
		entry.left_leg.rotation.z = swing
		entry.right_leg.rotation.z = -swing
		entry.recoil = move_toward(float(entry.recoil), 0.0, dt * 6.0)
		entry.left_gun.position.x = float(entry.left_rest) - 0.045 * float(entry.recoil)
		entry.right_gun.position.x = float(entry.right_rest) - 0.045 * float(entry.recoil)
		entry.pos = pos
		var screen: Vector2 = view.point(pos)
		entry.root.position = Vector3(screen.x, -100.0, screen.y)
		entry.root.scale = Vector3.ONE * view.pixels(diameter) / maxf(bounds.size.x, bounds.size.z)
	for id in entries.keys():
		if not retained.has(id):
			_remove(id)
