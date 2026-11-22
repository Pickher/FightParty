extends Node3D
## Standalone model viewer. The tank, weapon effects and wreck use the battle renderer.

const Tank = preload("res://scripts/visuals/tank_actor.gd")
const Weapons = preload("res://scripts/visuals/tank_layer.gd")
const RigBounds = preload("res://scripts/visuals/rig_bounds.gd")
const MODEL = preload("res://assets/models/mortar/mortar_rig.glb")
const FONT = preload("res://assets/NotoSansSC.ttf")

enum Action { DRIVE, MOBILE_FIRE, DEPLOY_PACK, SIEGE_FIRE, MOBILE_WRECK, SIEGE_WRECK }
enum Angle { QUARTER, PROFILE, OVERHEAD, PLAN, FRONT, COMPARISON }
const ACTION_NAMES := ["移动", "机动炮开火", "架起与收回", "攻城炮开火", "机动模式被毁", "架起模式被毁"]
const VIEW_NAMES := ["立体视角", "侧视", "战场俯视", "顶部", "低位正面", "三视图"]
const COMPARISON_ANGLES := [Angle.QUARTER, Angle.PLAN, Angle.FRONT]
const COMPARISON_LABELS := ["立体视角", "顶部 · 四角展开", "正面 · 双侧支架"]
const CELL_DIAMETER := 1.6
const DEPLOY_AT := 0.30
const PACK_AT := 2.47
const DEATH_AT := 0.43
const LOOP_LENGTH := 3.87

var action := Action.DEPLOY_PACK
var angle := Angle.COMPARISON
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
var slow_button := Button.new()
var comparison_views: Array[SubViewport] = []

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
	var restart := Button.new()
	restart.text = "重播"
	restart.pressed.connect(func(): play(action))
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 22
	$Controls/Toolbar.theme = theme
	for control in [action_menu, view_menu, pause_button, slow_button, restart]:
		$Controls/Toolbar.add_child(control)
	$Ballistics.draw.connect(_draw_shot)
	get_viewport().size_changed.connect(_resize_comparison)
	play(action)

func set_paused(value: bool) -> void:
	paused = value
	pause_button.text = "继续" if paused else "暂停"

func play(selected: int) -> void:
	if selected != action:
		if selected == Action.DEPLOY_PACK:
			angle = Angle.COMPARISON
		elif angle == Angle.COMPARISON:
			angle = Angle.QUARTER
		slow_button.button_pressed = false
	if is_instance_valid(actor):
		actor.hide()
		actor.queue_free()
	action = selected
	action_menu.select(action)
	view_menu.set_item_disabled(Angle.COMPARISON, action != Action.DEPLOY_PACK)
	view_menu.select(angle)
	var compare := angle == Angle.COMPARISON
	if compare and comparison_views.is_empty():
		_create_comparison()
	$Comparison.visible = compare
	$Camera.cull_mask = 0 if compare else 0xfffff
	for view in comparison_views:
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if compare else SubViewport.UPDATE_DISABLED
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
	if angle == Angle.PLAN:
		actor.presentation.transform = Transform3D.IDENTITY
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
		advance_pose(minf(delta, 0.1) * (0.5 if slow_button.button_pressed else 1.0))

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
			var since := previous
			if previous < DEPLOY_AT and time >= DEPLOY_AT:
				actor.advance(DEPLOY_AT - since, heading, 0.0)
				actor.set_deployed(true)
				since = DEPLOY_AT
			if previous < PACK_AT and time >= PACK_AT:
				actor.advance(PACK_AT - since, heading, 0.0)
				actor.set_deployed(false)
				since = PACK_AT
			dt = time - since
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
		_point_camera(camera, _inspection_direction(angle), Vector3(0.01, -0.015, 0.0), 1.26, _inspection_up(angle))
		return
	elif action == Action.MOBILE_WRECK or action == Action.SIEGE_WRECK:
		direction = Vector3(0.62, 0.99, 1.25)
		focus.y -= 0.10
		height = 1.76
	if angle == Angle.PROFILE:
		direction = Vector3(0.07, 0.34, 1.38)
	elif angle in [Angle.PLAN, Angle.FRONT, Angle.OVERHEAD]:
		direction = _inspection_direction(angle)
	_point_camera(camera, direction, focus, height, _inspection_up(angle))

func _inspection_up(selected: int) -> Vector3:
	if selected == Angle.PLAN:
		return Vector3.RIGHT
	return Vector3.FORWARD if selected == Angle.OVERHEAD else Vector3.UP

func _point_camera(camera: Camera3D, direction: Vector3, focus: Vector3, span: float, up: Vector3) -> void:
	camera.size = span
	camera.position = focus + direction.normalized() * 5.0
	camera.look_at(focus, up)

func _inspection_direction(selected: int) -> Vector3:
	match selected:
		Angle.PLAN, Angle.OVERHEAD:
			return Vector3.UP
		Angle.FRONT:
			return Vector3(1.0, 0.34, 0.0)
		Angle.PROFILE:
			return Vector3(0.07, 0.34, 1.38)
	return Vector3(0.85, 0.85, 1.18)

func _create_comparison() -> void:
	for i in COMPARISON_ANGLES.size():
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 4)
		$Comparison/Views.add_child(column)
		var container := SubViewportContainer.new()
		container.stretch = true
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(container)
		var view := SubViewport.new()
		view.world_3d = get_world_3d()
		view.msaa_3d = Viewport.MSAA_4X
		container.add_child(view)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		view.add_child(camera)
		camera.current = true
		var selected: int = COMPARISON_ANGLES[i]
		var focus := Vector3(0.01, -0.015, 0.0)
		_point_camera(camera, _inspection_direction(selected), focus, 1.38, _inspection_up(selected))
		var label := Label.new()
		label.text = COMPARISON_LABELS[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", FONT)
		label.add_theme_font_size_override("font_size", 19)
		column.add_child(label)
		comparison_views.append(view)
	_resize_comparison()

func _resize_comparison() -> void:
	if comparison_views.is_empty():
		return
	var area := get_viewport().get_visible_rect().size
	var frame_width := minf(area.x - 24.0, maxf(180.0, (area.y - 120.0) * 4.0))
	var frame_height := maxf(70.0, minf(area.y - 90.0, frame_width * 0.285 + 36.0))
	var frames: HBoxContainer = $Comparison/Views
	frames.offset_left = -frame_width * 0.5
	frames.offset_right = frame_width * 0.5
	frames.offset_top = -frame_height * 0.5
	frames.offset_bottom = frame_height * 0.5

# Project both endpoints from the gallery camera before submitting them to the
# actual two-dimensional battle effects renderer. Its distances are measured in cells.
func pixels(cells: float) -> float:
	return cells / CELL_DIAMETER * get_viewport().get_visible_rect().size.y / float($Camera.size)

func point(plane: Vector2) -> Vector2:
	return plane * pixels(1.0)

func _draw_shot() -> void:
	var age := time - shot_at
	if age > 0.40 or $Comparison.visible:
		return
	var camera: Camera3D = $Camera
	var from := camera.unproject_position(origin) / pixels(1.0)
	var to := camera.unproject_position(target) / pixels(1.0)
	var bore := camera.unproject_position(origin + shot_axis) / pixels(1.0)
	Weapons.draw_shot($Ballistics, self, from, bore, shot_mode, age)
	Weapons.draw_impact($Ballistics, self, to, shot_mode, 2.5 if shot_mode == "siege_cannon" else 0.0, age)
