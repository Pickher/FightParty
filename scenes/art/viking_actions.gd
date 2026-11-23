extends Node3D
## Presents the same rigid actor, muzzle effects and missile drawing used on the battlefield.

const Viking = preload("res://scripts/visuals/viking_actor.gd")
const Missiles = preload("res://scripts/visuals/viking_ordnance.gd")
const RigBounds = preload("res://scripts/visuals/rig_bounds.gd")
const MODEL = preload("res://assets/models/viking/viking_rig.glb")
const FONT = preload("res://assets/NotoSansSC.ttf")
enum Action { TRANSFORM, WALK, GROUND_FIRE, GROUND_WRECK, FLIGHT, AIR_FIRE, AIR_WRECK }
enum Angle { QUARTER, SIDE, TOP }
const ACTION_NAMES := ["起飞与降落", "地面行走", "机炮攻击", "地面被毁", "巡航转向", "对空导弹", "空中被毁"]
const VIEW_NAMES := ["立体视角", "侧面", "战场俯视"]
const TAKEOFF_AT := 0.30
const LAND_AT := 2.37
const WRECK_AT := 0.70
const LOOP_SECONDS := 4.0
const DIAMETER_CELLS := 1.5
const MISSILE_SPEED := 20.0
const CANNON_INTERVAL := 0.083

var action := Action.TRANSFORM
var angle := Angle.QUARTER
var repeat := true
var paused := false
var time := 0.0
var actor
var bounds: AABB
var next_shot := 0.0
var burst_round := 0
var launch_at := -INF
var arrival := 0.0
var origin := Vector3.ZERO
var bore := Vector3.RIGHT
var goal := Vector3.ZERO
var action_menu := OptionButton.new()
var view_menu := OptionButton.new()
var pause_button := Button.new()
var slow_button := Button.new()

func _ready() -> void:
	bounds = RigBounds.from_scene(MODEL)
	for title in ACTION_NAMES:
		action_menu.add_item(title)
	for title in VIEW_NAMES:
		view_menu.add_item(title)
	action_menu.item_selected.connect(play)
	view_menu.item_selected.connect(set_view)
	pause_button.pressed.connect(func(): set_paused(not paused))
	slow_button.text = "0.5× 慢放"
	slow_button.toggle_mode = true
	var replay := Button.new()
	replay.text = "重播"
	replay.pressed.connect(func(): play(action))
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 22
	$Controls/Toolbar.theme = theme
	for control in [action_menu, view_menu, pause_button, slow_button, replay]:
		$Controls/Toolbar.add_child(control)
	$Ballistics.draw.connect(_draw_missile)
	play(action)

func set_paused(value: bool) -> void:
	paused = value
	pause_button.text = "继续" if paused else "暂停"

func play(selected: int) -> void:
	if is_instance_valid(actor):
		actor.hide()
		actor.queue_free()
	if action != selected:
		slow_button.button_pressed = false
	action = selected
	action_menu.select(action)
	time = 0.0
	next_shot = 0.48
	burst_round = 0
	launch_at = -INF
	set_paused(false)
	actor = Viking.new()
	add_child(actor)
	frame_camera($Camera, angle)
	actor.setup(MODEL, bounds, 0.0, 1.0 if action in [Action.FLIGHT, Action.AIR_FIRE, Action.AIR_WRECK] else 0.0)
	$Floor.position.y = actor.ground_height - 0.003
	frame_camera($Camera, angle)
	$Ballistics.queue_redraw()

func set_view(selected: int) -> void:
	if angle == selected:
		return
	var elapsed := time
	var frozen := paused
	angle = selected
	view_menu.select(angle)
	play(action)
	# Recreate the tactical camera projection at exactly the current pose.
	while elapsed - time > 0.0001:
		advance_pose(minf(1.0 / 60.0, elapsed - time))
	set_paused(frozen)

func _process(delta: float) -> void:
	if not paused:
		advance_pose(minf(delta, 0.1) * (0.5 if slow_button.button_pressed else 1.0))

func advance_pose(delta: float) -> void:
	var since := time
	time += delta
	var heading := 0.0
	var distance := 0.0
	var aim := NAN
	if action == Action.TRANSFORM:
		if since < TAKEOFF_AT:
			var step_time := minf(time, TAKEOFF_AT) - since
			var step_distance := step_time / (TAKEOFF_AT * 3.0)
			actor.position.x += step_distance
			actor.advance(step_time, 0.0, step_distance)
			since += step_time
			if time >= TAKEOFF_AT:
				actor.set_flight_mode(true)
		if since < LAND_AT and time >= LAND_AT:
			actor.advance(LAND_AT - since, 0.0, 0.0)
			actor.set_flight_mode(false)
			since = LAND_AT
	elif action in [Action.WALK, Action.FLIGHT]:
		var airborne := action == Action.FLIGHT
		heading = (0.73 if airborne else 0.52) * smoothstep(0.35, 1.55, time) - 1.09 * smoothstep(1.92, 3.52, time)
		distance = (0.93 if airborne else 0.62) * delta
		actor.position += Vector3(cos(heading), 0, sin(heading)) * distance
	elif action in [Action.GROUND_FIRE, Action.AIR_FIRE]:
		aim = -0.08
	elif since < WRECK_AT and time >= WRECK_AT:
		actor.advance(WRECK_AT - since, 0.0, 0.0)
		actor.destroy()
		since = WRECK_AT

	# Each real gatling event spins and ignites only its selected arm.
	if action == Action.GROUND_FIRE:
		while next_shot <= time:
			actor.advance(next_shot - since, heading, 0.0, aim)
			actor.fire(Viking.GROUND, aim)
			since = next_shot
			burst_round = (burst_round + 1) % 16
			next_shot += 0.61 if burst_round == 0 else CANNON_INTERVAL
	elif action == Action.AIR_FIRE and next_shot <= time:
		actor.advance(next_shot - since, heading, 0.0, aim)
		actor.fire(Viking.AIR, aim)
		origin = actor.muzzle_world(Viking.AIR)
		bore = actor.muzzle_direction_world(Viking.AIR)
		goal = Vector3(1.83, origin.y + 0.10, -0.18)
		launch_at = next_shot
		arrival = origin.distance_to(goal) * DIAMETER_CELLS / MISSILE_SPEED
		since = next_shot
		next_shot += 2.0
	actor.advance(time - since, heading, distance, aim)
	if actor.is_finished():
		actor.hide()
	frame_camera($Camera, angle)
	$Ballistics.queue_redraw()
	if repeat and time >= LOOP_SECONDS:
		play(action)

func frame_camera(camera: Camera3D, selected: int) -> void:
	var center := Vector3(0.02, 0.08, 0.0)
	var direction := Vector3(0.90, 1.38, 1.30)
	var span := 1.51
	match action:
		Action.TRANSFORM:
			center += actor.position
			center.y = 0.175
			span = 1.82
		Action.WALK, Action.FLIGHT:
			center += actor.position * 0.94
			center.y = -0.05 if action == Action.WALK else 0.33
			span = 1.51 if action == Action.WALK else 1.76
		Action.GROUND_FIRE:
			center = Vector3(0.04, 0.0, 0.0)
			direction = Vector3(0.70, 0.61, 1.27)
			span = 1.32
		Action.AIR_FIRE:
			center = Vector3(0.60, 0.26, 0.0)
			span = 1.97
			direction = Vector3(0.70, 0.81, 1.40)
		Action.GROUND_WRECK, Action.AIR_WRECK:
			span = 2.28 if action == Action.GROUND_WRECK else 2.75
			center = Vector3(0.18, -0.08, 0.0) if action == Action.GROUND_WRECK else Vector3(0.57, -0.10, 0.0)
			direction = Vector3(0.92, 1.02, 1.30)
	if selected == Angle.SIDE:
		direction = Vector3(0.09, 0.34, 1.28)
	elif selected == Angle.TOP:
		direction = Vector3.UP
	camera.size = span
	camera.position = center + direction.normalized() * 5.0
	camera.look_at(center, Vector3.FORWARD if selected == Angle.TOP else Vector3.UP)

# Convert the gallery projection to the same cell-space drawing API as the battle view.
func pixels(cells: float) -> float:
	return cells / DIAMETER_CELLS * get_viewport().get_visible_rect().size.y / float($Camera.size)

func point(plane: Vector2) -> Vector2:
	return plane * pixels(1.0)

func _project(world: Vector3) -> Vector2:
	return $Camera.unproject_position(world) / pixels(1.0)

func _draw_missile() -> void:
	var age := time - launch_at
	if action != Action.AIR_FIRE or age >= arrival + Missiles.IMPACT_DURATION:
		return
	if age < arrival:
		var t := clampf(age / maxf(0.001, arrival), 0.0, 1.0)
		var axis := (_project(origin + bore) - _project(origin)).normalized()
		Missiles.draw_flight($Ballistics, self, _project(origin), _project(goal), axis, t)
	else:
		Missiles.draw_impact($Ballistics, self, _project(goal), age - arrival)
