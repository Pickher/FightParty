extends "res://scripts/visuals/tracked_projectile_layer.gd"
## The recruited ground Viking walks and fires its two cannons in permanent assault form.
const Actor = preload("res://scripts/visuals/viking_actor.gd")
const Ordnance = preload("res://scripts/visuals/viking_ordnance.gd")
const MODEL_PATH := Actor.RIG_PATH
const MODE := "gatling_cannon"

func _init() -> void:
	super("viking_assault", MODE, "ground", Actor, Ordnance, 2.5)
	_turn_to_target_at_rest = true

func _socket(actor: Node3D, side: int) -> Transform2D:
	var bore: Vector3 = actor.muzzle_direction_world(MODE, side)
	return Transform2D(Vector2(bore.x, bore.z).angle(), actor.muzzle_screen_offset(MODE, side))

func _fire_actor(actor: Node3D, offset: Vector2, age: float, side: int) -> void:
	actor.fire_at(MODE, offset, age, side)

func _draw_contact(canvas: CanvasItem, view, pos: Vector2, age: float, side: int) -> void:
	draw_contact(canvas, view, pos, age, side)

## A fixed zero-second round leaves only a small chip flash at the native contact.
static func draw_contact(canvas: CanvasItem, view, pos: Vector2, age: float, side: int) -> void:
	var progress := age / 0.12
	if progress < 0.0 or progress >= 1.0:
		return
	var center: Vector2 = view.point(pos)
	var radius := clampf(float(view.pixels(0.19)), 2.5, 9.0)
	var fade := 1.0 - progress
	canvas.draw_circle(center, maxf(0.8, radius * 0.51 * fade), Color(1.0, 0.77, 0.42, fade), true, -1, true)
	if progress < 0.40:
		canvas.draw_circle(center, maxf(0.7, radius * 0.23), Color(1.0, 0.98, 0.81, fade), true, -1, true)
	var seed := fposmod(pos.x * 2.4 + pos.y * 1.7 + float(side) * 1.46, TAU)
	for i in 3:
		var ray := Vector2.from_angle(seed + float(i) * 2.23)
		var tip := center + ray * radius * (0.26 + 1.15 * sqrt(progress)) * (1.0 - 0.14 * i)
		canvas.draw_line(tip - ray * radius * 0.29 * fade, tip, Color(1.0, 0.66, 0.29, fade), 1.0, true)
