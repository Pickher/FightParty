extends RefCounted

const MODEL_PATH := "res://assets/models/hellbat_mech/hellbat_mech.glb"
const PAINT = preload("res://scripts/visuals/hellbat_mech.gdshader")
const MAX_LIVE := 24
const FLAME_DURATION := 0.20
# The top-mounted nozzle points along the uploaded mesh's local +X axis.
const NOZZLE := Vector3(0.052, 0.791, -0.015)

var scene: Node3D
var model: PackedScene
var bounds := AABB()
var entries: Dictionary = {}

func configure(world: Node3D, resource: PackedScene, box: AABB) -> void:
	scene = world
	model = resource
	bounds = box

func _create(unit: Dictionary, position: Vector2, heading: float) -> Dictionary:
	var actor := Node3D.new()
	scene.add_child(actor)
	var pose := Node3D.new()
	actor.add_child(pose)
	var body := model.instantiate() as Node3D
	pose.add_child(body)
	body.position -= bounds.get_center()
	var paint := ShaderMaterial.new()
	paint.shader = PAINT
	paint.set_shader_parameter("team_paint", Color("75c4ac") if unit.team == 0 else Color("ee7c63"))
	var meshes := body.find_children("*", "MeshInstance3D", true, false)
	if body is MeshInstance3D:
		meshes.push_front(body)
	for mesh in meshes:
		mesh.material_override = paint
	return {"actor":actor, "pose":pose, "body":body, "paint":paint, "pos":position,
		"heading":heading, "phase":float(unit.id % 11), "stride":0.0, "shot_left":0.0}

func _remove(id: int) -> void:
	var actor: Node3D = entries[id].actor
	actor.hide()
	actor.queue_free()
	entries.erase(id)

func reset() -> void:
	for id in entries.keys():
		_remove(id)

func sync(game, view, dt: float, alpha: float) -> void:
	if model == null or not game.sim.catalog.has("hellbat_mech"):
		return
	var size: Array = game.sim.catalog.hellbat_mech.size
	var diameter := maxf(float(size[0]), float(size[1]))
	var visible_area: Rect2 = game._camera_rect().grow(diameter)
	var retained := {}
	for unit in game.sim.units:
		if unit.kind != "hellbat_mech" or game._hidden_team(int(unit.team)):
			continue
		var position: Vector2 = unit.prev.lerp(unit.pos, alpha)
		if retained.size() >= MAX_LIVE or not visible_area.has_point(position):
			continue
		retained[unit.id] = true
		var motion: Vector2 = unit.pos - unit.prev
		var moving := motion.length_squared() > 0.000001
		var facing: float = motion.angle() if moving else (0.0 if unit.team == 0 else PI)
		if not entries.has(unit.id):
			entries[unit.id] = _create(unit, position, facing)
		var entry: Dictionary = entries[unit.id]
		if not moving:
			var target_id := int(unit.get("attack_target_id", 0))
			var target = game.sim.by_id.get(target_id)
			facing = entry.heading
			if target != null:
				facing = position.angle_to_point(target.prev.lerp(target.pos, alpha))
			elif target_id < 0:
				facing = position.angle_to_point(game.sim.base_pos(1 - int(unit.team)))
		entry.shot_left = maxf(0.0, float(entry.shot_left) - dt)
		if entry.shot_left <= 0.0:
			entry.heading = rotate_toward(float(entry.heading), facing, dt * 10.0)
		if dt > 0.0:
			entry.phase += position.distance_to(entry.pos) * TAU / diameter
			var stride := move_toward(float(entry.stride), sin(entry.phase) if moving else 0.0, dt * 10.0)
			if not is_equal_approx(float(entry.stride), stride):
				entry.stride = stride
				entry.paint.set_shader_parameter("stride", stride)
		entry.pos = position
		var recoil := float(entry.shot_left) / FLAME_DURATION
		entry.pose.rotation = Vector3(float(entry.stride) * 0.04, 0.0, 0.24 + recoil * 0.08)
		entry.pose.position.x = -recoil * 0.04
		var screen: Vector2 = view.point(position)
		entry.actor.position = Vector3(screen.x, -100.0, screen.y)
		entry.actor.rotation.y = -float(entry.heading)
		entry.actor.scale = Vector3.ONE * view.pixels(diameter) / maxf(bounds.size.x, bounds.size.z)
	for id in entries.keys():
		if not retained.has(id):
			_remove(id)

func fire(event: Dictionary) -> void:
	var entry = entries.get(event.source_id)
	if entry != null:
		entry.heading = Vector2(event.from).angle_to_point(event.to)
		entry.shot_left = FLAME_DURATION

# Project the real socket when a model is visible. Fallback icons still show the
# same fan, using the combat event's origin, arc and endpoint.
func draw_flame(canvas: CanvasItem, view, event: Dictionary) -> void:
	var origin: Vector2 = view.point(event.from)
	var axis: Vector2 = view.point(event.to) - origin
	var start := origin
	var entry = entries.get(event.source_id)
	if entry != null:
		var nozzle: Vector3 = entry.body.to_global(NOZZLE)
		start = Vector2(nozzle.x, nozzle.z)
	var remaining := clampf(float(event.ttl) / FLAME_DURATION, 0.0, 1.0)
	var reach := axis.length() * minf(1.0, 0.5 + 2.5 * (1.0 - remaining))
	var spread := deg_to_rad(float(event.angle_degrees)) * 0.5
	for layer in range(2):
		var flame := PackedVector2Array([start])
		for i in range(11):
			var angle := axis.angle() + spread * (i * 0.2 - 1.0)
			var edge := 1.0 - 0.12 * absf(sin(float(i * 2 + int(event.source_id)) + remaining * 7.0))
			flame.append(origin + Vector2.from_angle(angle) * reach * edge)
		var color := Color("fa7027") if layer == 0 else Color("ffdb70")
		color.a = remaining * (0.72 if layer == 0 else 0.90)
		canvas.draw_colored_polygon(flame, color)
		reach *= 0.73
		spread *= 0.55
