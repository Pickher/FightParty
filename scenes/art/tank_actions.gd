extends Node3D
## Standalone model viewer. The tank, weapon effects and wreck use the battle renderer.

const Tank = preload("res://scripts/visuals/tank_actor.gd")
const Weapons = preload("res://scripts/visuals/tank_layer.gd")
const RigBounds = preload("res://scripts/visuals/rig_bounds.gd")
const MODEL = preload("res://assets/models/mortar/mortar_rig.glb")
const FONT = preload("res://assets/NotoSansSC.ttf")

enum Action { DRIVE, MOBILE_FIRE, DEPLOY_PACK, SIEGE_FIRE, MOBILE_WRECK, SIEGE_WRECK }
enum Angle { QUARTER, PROFILE, OVERHEAD }
const ACTION_NAMES := ["移动", "机动炮开火", "架起与收回", "攻城炮开火", "机动模式被毁", "架起模式被毁"]
const VIEW_NAMES := ["立体视角", "侧视", "战场俯视"]
const CELL_DIAMETER := 1.6
const DEPLOY_AT := 0.30
const PACK_AT := 2.47
const DEATH_AT := 0.43
const LOOP_LENGTH := 3.87

var action := Action.DRIVE
var angle := Angle.QUARTER
var actor
var bounds: AABB
var time := 0.0
var repeat := true
var paused := false
var next_shot := 0.0
var shot_at := -INF
var shot_mode := ""
var origin := Vector3.ZERO
var shot_axis := Vector3.RIGHT
var target := Vector3.ZERO
var action_menu := OptionButton.new()
var view_menu := OptionButton.new()
var pause_button := Button.new()

func _ready() -> void:
	bounds = RigBounds.from_scene(MODEL)
	for title in ACTION_NAMES:
		action_menu.add_item(title)
	for title in VIEW_NAMES:
		view_menu.add_item(title)
	action_menu.item_selected.connect(play)
	view_menu.item_selected.connect(set_view)
	pause_button.pressed.connect(func(): set_paused(not paused))
	var restart := Button.new()
	restart.text = "重播"
	restart.pressed.connect(func(): play(action))
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 22
	$Controls/Toolbar.theme = theme
	for control in [action_menu, view_menu, pause_button, restart]:
		$Controls/Toolbar.add_child(control)
	$Ballistics.draw.connect(_draw_shot)
	play(action)

func set_paused(value: bool) -> void:
	paused = value
	pause_button.text = "继续" if paused else "暂停"

func play(selected: int) -> void:
	if is_instance_valid(actor):
		actor.hide()
		actor.queue_free()
	action = selected
	action_menu.select(action)
	time = 0.0
	shot_at = -INF
	next_shot = 0.44 if action == Action.MOBILE_FIRE else 0.48
	set_paused(false)
	actor = Tank.new()
	add_child(actor)
	# Configure the camera before setup so the actor can recognize the battle view.
	_frame_tank()
	var deployed := action == Action.SIEGE_FIRE or action == Action.SIEGE_WRECK
	actor.setup(MODEL, bounds, 0.0, 1.0 if deployed else 0.0)
	$Floor.position.y = actor.ground_height - 0.002
	_frame_tank()
	$Ballistics.queue_redraw()

func set_view(selected: int) -> void:
	var elapsed := time
	var was_paused := paused
	angle = selected
	view_menu.select(angle)
	play(action)
	# Rebuild the camera-dependent projection while retaining the selected pose.
	while elapsed - time > 0.0001:
		advance_pose(minf(1.0 / 60.0, elapsed - time))
	set_paused(was_paused)

func _process(delta: float) -> void:
	if not paused:
		advance_pose(minf(delta, 0.1))

func advance_pose(dt: float) -> void:
	var previous := time
	time += dt
	var heading := 0.0
	var distance := 0.0
	var aim := NAN
	var firing := false
	match action:
		Action.DRIVE:
			heading = 0.42 * smoothstep(0.42, 1.65, time) - 0.61 * smoothstep(2.08, 3.34, time)
			distance = 0.43 * dt
		Action.DEPLOY_PACK:
			if previous < DEPLOY_AT and time >= DEPLOY_AT:
				actor.set_deployed(true)
			if previous < PACK_AT and time >= PACK_AT:
				actor.set_deployed(false)
		Action.MOBILE_FIRE, Action.SIEGE_FIRE:
			target = Vector3(1.045, actor.ground_height + 0.006, -0.13)
			var toward := Vector2(target.x - actor.position.x, target.z - actor.position.z)
			aim = toward.angle()
			firing = time >= next_shot
		Action.MOBILE_WRECK, Action.SIEGE_WRECK:
			if previous < DEATH_AT and time >= DEATH_AT:
				actor.destroy()
	actor.position += Vector3(cos(heading), 0, sin(heading)) * distance
	actor.advance(dt, heading, distance, aim)
	if firing:
		shot_mode = "mobile_cannon" if action == Action.MOBILE_FIRE else "siege_cannon"
		actor.fire_at(shot_mode, Vector2(target.x - actor.position.x, target.z - actor.position.z))
		origin = actor.muzzle_world(shot_mode)
		shot_axis = actor.muzzle_direction_world(shot_mode)
		shot_at = time
		next_shot += 1.24 if action == Action.MOBILE_FIRE else 3.30
	if actor.is_finished():
		actor.hide()
	_frame_tank()
	$Ballistics.queue_redraw()
	if repeat and time >= LOOP_LENGTH:
		play(action)

func _frame_tank() -> void:
	var camera: Camera3D = $Camera
	var direction := Vector3(0.85, 0.72, 1.18)
	var focus := Vector3(0.025, 0.02, 0.0)
	var height := 1.06
	if action == Action.DRIVE:
		focus += actor.position * 0.88
	elif action == Action.MOBILE_FIRE or action == Action.SIEGE_FIRE:
		direction = Vector3(0.20, 0.60, 1.23)
		focus += Vector3(0.39, -0.01, 0.0)
		height = 1.35
	elif action == Action.DEPLOY_PACK:
		height = 1.24
	elif action == Action.MOBILE_WRECK or action == Action.SIEGE_WRECK:
		direction = Vector3(0.62, 0.99, 1.25)
		focus.y -= 0.10
		height = 1.76
	if angle == Angle.PROFILE:
		direction = Vector3(0.07, 0.34, 1.38)
	elif angle == Angle.OVERHEAD:
		direction = Vector3.UP
	camera.size = height
	camera.position = focus + direction.normalized() * 5.0
	camera.look_at(focus, Vector3.FORWARD if angle == Angle.OVERHEAD else Vector3.UP)

# Project both endpoints from the gallery camera before submitting them to the
# actual two-dimensional battle effects renderer. Its distances are measured in cells.
func pixels(cells: float) -> float:
	return cells / CELL_DIAMETER * get_viewport().get_visible_rect().size.y / float($Camera.size)

func point(plane: Vector2) -> Vector2:
	return plane * pixels(1.0)

func _draw_shot() -> void:
	var age := time - shot_at
	if age > 0.40:
		return
	var camera: Camera3D = $Camera
	var from := camera.unproject_position(origin) / pixels(1.0)
	var to := camera.unproject_position(target) / pixels(1.0)
	var bore := camera.unproject_position(origin + shot_axis) / pixels(1.0)
	Weapons.draw_shot($Ballistics, self, from, bore, shot_mode, age)
	Weapons.draw_impact($Ballistics, self, to, shot_mode, 2.5 if shot_mode == "siege_cannon" else 0.0, age)
