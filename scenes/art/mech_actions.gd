extends Node3D
## Isolated art viewer. The controls and camera drive the same actors as the battlefield.

const Marauder = preload("res://scripts/visuals/marauder_actor.gd")
const Hellbat = preload("res://scripts/visuals/hellbat_actor.gd")
const Grenade = preload("res://scripts/visuals/marauder_ordnance.gd")
const RigBounds = preload("res://scripts/visuals/rig_bounds.gd")
const MODELS := [
	preload("res://assets/models/marauder/marauder_rig.glb"),
	preload("res://assets/models/hellbat_mech/hellbat_mech_rig.glb"),
]
const FONT = preload("res://assets/NotoSansSC.ttf")
enum Action { MOVE, TURN, ATTACK, DESTROY, TRANSFORM }
const ACTION_NAMES := ["移动", "转向", "攻击", "被毁", "变形为恶火"]
const VIEW_NAMES := ["立体视角", "侧面", "战场俯视", "正面"]
const DIRECTIONS := [Vector3(2.6, 1.85, 3.7), Vector3(0.08, 1.25, 4.2), Vector3.UP, Vector3(4.2, 0.74, 0.05)]
@export var grid_material: Material

var unit_index := -1
var action := Action.MOVE
var camera_index := 0
var model_bounds: Array[AABB] = []
var actor
var time := 0.0
var next_shot := 0.0
var triggered := false
var shots: Array[Dictionary] = []
var actions := OptionButton.new()
var repeat := true
const PREVIEW_FLIGHT := 2.0 * 1.2 / 20.0

func _ready() -> void:
	for model in MODELS:
		model_bounds.append(RigBounds.from_scene(model))
	_make_grid()
	_make_controls()
	$Overlay.draw.connect(_draw_grenades)
	play(0, Action.MOVE)

func _make_grid() -> void:
	var grid := ImmediateMesh.new()
	grid.surface_begin(Mesh.PRIMITIVE_LINES, grid_material)
	for i in range(-24, 25):
		var x := i * 0.5
		grid.surface_add_vertex(Vector3(x, 0, -12))
		grid.surface_add_vertex(Vector3(x, 0, 12))
		grid.surface_add_vertex(Vector3(-12, 0, x))
		grid.surface_add_vertex(Vector3(12, 0, x))
	grid.surface_end()
	var lines := MeshInstance3D.new()
	lines.mesh = grid
	lines.position.y = 0.001
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	$Ground.add_child(lines)

func _make_controls() -> void:
	var units := OptionButton.new()
	units.add_item("劫掠者")
	units.add_item("恶蝠")
	units.item_selected.connect(func(index: int): play(index, mini(action, Action.DESTROY) if index == 0 else action))
	actions.item_selected.connect(func(index: int): play(unit_index, index))
	var views := OptionButton.new()
	for title in VIEW_NAMES:
		views.add_item(title)
	views.item_selected.connect(set_view)
	var restart := Button.new()
	restart.text = "重播"
	restart.pressed.connect(func(): play(unit_index, action))
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 23
	$Controls/Toolbar.theme = theme
	for control in [units, actions, views, restart]:
		$Controls/Toolbar.add_child(control)

func play(kind: int, animation: int) -> void:
	if is_instance_valid(actor):
		actor.hide()
		actor.queue_free()
	var changed_unit := kind != unit_index
	unit_index = kind
	action = animation
	time = 0.0
	next_shot = 0.48
	triggered = false
	shots.clear()
	if changed_unit:
		actions.clear()
		for i in range(5 if kind == 1 else 4):
			actions.add_item(ACTION_NAMES[i])
	actions.select(action)
	actor = Marauder.new() if kind == 0 else Hellbat.new()
	add_child(actor)
	_update_camera()
	actor.setup(MODELS[kind], model_bounds[kind], 0.0)
	$Ground.position.y = actor.ground_height - 0.004
	_update_camera()
	$Overlay.queue_redraw()

func set_view(index: int) -> void:
	if index != camera_index:
		camera_index = index
		play(unit_index, action)

func _update_camera() -> void:
	var camera: Camera3D = $Camera
	var center := actor.position as Vector3
	var extent := 1.88
	var direction: Vector3 = DIRECTIONS[camera_index]
	if action == Action.ATTACK:
		center.x += 0.54
		extent = 2.45
		if unit_index == 1 and camera_index == 0:
			direction = Vector3(1.65, 3.05, 3.85)
	elif action == Action.DESTROY:
		extent = 2.65
		if camera_index == 0:
			direction = Vector3(-2.5, 2.30, 3.50)
	elif action == Action.TRANSFORM:
		extent = 2.07
	camera.size = extent
	camera.position = center + direction * 2.1
	camera.look_at(center, Vector3.FORWARD if camera_index == 2 else Vector3.UP)

func _process(delta: float) -> void:
	advance_pose(minf(delta, 0.1))

func advance_pose(dt: float) -> void:
	time += dt
	var distance := 0.0
	var heading := 0.0
	var aim := NAN
	match action:
		Action.MOVE:
			distance = 0.67 * dt
		Action.TURN:
			heading = PI * smoothstep(0.26, 1.48, time) - PI * smoothstep(1.81, 3.08, time)
		Action.ATTACK:
			aim = 0.0
			if time >= next_shot:
				if unit_index == 0:
					if actor.fire_at(Vector2(2.0, 0.0)):
						shots.append({"at": time, "origin": actor.muzzle_world(), "axis": actor.muzzle_direction_world()})
					next_shot += 1.5
				else:
					actor.fire(2.15, 1.05, aim)
					next_shot += 1.65
		Action.DESTROY:
			if not triggered and time >= 0.35:
				triggered = true
				actor.destroy()
		Action.TRANSFORM:
			if not triggered and time >= 0.36:
				triggered = true
				actor.set_vehicle_form(true)
			if actor.vehicle_progress >= 0.999 and time > 1.85:
				distance = 0.55 * dt
	actor.position.x += distance
	actor.advance(dt, heading, distance, aim)
	if action == Action.DESTROY and actor.is_finished():
		actor.hide()
	shots = shots.filter(func(shot): return time - shot.at < PREVIEW_FLIGHT + Grenade.IMPACT_DURATION)
	_update_camera()
	$Overlay.queue_redraw()
	if repeat and time >= 4.0:
		play(unit_index, action)

# Ordnance geometry accepts battlefield-plane coordinates. Project the oblique
# gallery camera to that same drawing API so the grenade starts in the barrel.
func pixels(length_in_scene: float) -> float:
	return length_in_scene * get_viewport().get_visible_rect().size.y / $Camera.size

func point(position: Vector2) -> Vector2:
	return position * pixels(1.0)

func _draw_grenades() -> void:
	var camera: Camera3D = $Camera
	for shot in shots:
		var since := time - float(shot.at)
		var at: Vector3 = shot.origin
		var goal := Vector3(2.0, actor.ground_height + 0.07, 0.0)
		var from: Vector2 = camera.unproject_position(at) / pixels(1.0)
		var to: Vector2 = camera.unproject_position(goal) / pixels(1.0)
		var ahead: Vector3 = at + shot.axis
		var projected := camera.unproject_position(ahead) - camera.unproject_position(at)
		if since < PREVIEW_FLIGHT:
			Grenade.draw_flight($Overlay, self, from, to, projected.normalized(), since / PREVIEW_FLIGHT)
		else:
			Grenade.draw_impact($Overlay, self, to, since - PREVIEW_FLIGHT)
