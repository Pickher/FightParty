extends RefCounted
## A single missile leaves its real rack and turns toward the current native goal.
const DirectHit = preload("res://scripts/visuals/marauder_ordnance.gd")
const IMPACT_DURATION := DirectHit.IMPACT_DURATION

static func flight_position(origin: Vector2, goal: Vector2, direction: Vector2, progress: float) -> Vector2:
	var span := origin.distance_to(goal)
	var axis := direction.normalized() if not direction.is_zero_approx() else origin.direction_to(goal)
	var first := origin + axis * minf(1.1, span * 0.32)
	var last := goal - first.direction_to(goal) * minf(1.6, span * 0.33)
	return origin.bezier_interpolate(first, last, goal, clampf(progress, 0.0, 1.0))

static func draw_flight(canvas: CanvasItem, view, origin: Vector2, goal: Vector2, direction: Vector2, progress: float) -> void:
	if progress <= 0.0 or progress >= 1.0:
		return
	var position := flight_position(origin, goal, direction, progress)
	var near := flight_position(origin, goal, direction, progress - 0.008)
	var ahead := flight_position(origin, goal, direction, progress + 0.008)
	draw_missile(canvas, view, origin, position, near.direction_to(ahead))

static func draw_missile(canvas: CanvasItem, view, origin: Vector2, position: Vector2, direction: Vector2) -> void:
	var tip: Vector2 = view.point(position)
	var traveled: float = tip.distance_to(view.point(origin))
	if traveled < 0.45 or direction.is_zero_approx():
		return
	var axis: Vector2 = tip.direction_to(view.point(position + direction))
	var length := clampf(float(view.pixels(0.29)), 3.9, 14.0)
	var exposed := minf(traveled, length)
	var rear := tip - axis * exposed
	var width := axis.orthogonal() * maxf(1.0, length * 0.15)
	var shoulder := tip - axis * minf(exposed, length * 0.37)
	if exposed < length * 0.38:
		var nose := width * exposed / (length * 0.38)
		canvas.draw_colored_polygon(PackedVector2Array([tip, rear + nose, rear - nose]), Color("f5fcff"))
		return
	var clearance := traveled - length
	if clearance > 0.5:
		var tail := rear - axis * minf(clearance, length * 1.35)
		canvas.draw_line(rear, tail, Color(0.71, 0.78, 0.81, 0.40), maxf(1.1, length * 0.15), true)
		var flame := rear - axis * minf(clearance, length * 0.78)
		canvas.draw_colored_polygon(PackedVector2Array([rear + width * 0.82, flame, rear - width * 0.82]), Color("ff9742"))
		canvas.draw_line(rear, rear.lerp(flame, 0.5), Color("fff5ca"), maxf(1.0, length * 0.12), true)
	canvas.draw_colored_polygon(PackedVector2Array([tip, shoulder+width, rear+width*0.62, rear-width*0.62, shoulder-width]), Color("cedde5"))
	canvas.draw_line(tip - axis * (length * 0.1), shoulder, Color("fcffff"), maxf(1.0, length * 0.14), true)
	if exposed > length * 0.81:
		var fins := rear + axis * length * 0.26
		canvas.draw_colored_polygon(PackedVector2Array([fins, rear+width*1.6, rear-width*1.6]), Color("718693"))

static func draw_impact(canvas: CanvasItem, view, pos: Vector2, age: float, serial: int = 0) -> void:
	DirectHit.draw_impact(canvas, view, pos, age, serial)
