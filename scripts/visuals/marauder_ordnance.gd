extends RefCounted
## Draw a compact concussive grenade from the physical muzzle to the tracked gameplay contact.

const IMPACT_DURATION := 0.19
static var _impact_glow: GradientTexture2D

static func flight_position(origin: Vector2, goal: Vector2, direction: Vector2, progress: float) -> Vector2:
	var span := goal - origin
	var length := span.length()
	if length < 0.001:
		return goal
	var axis := span / length
	var bore := direction.normalized() if direction.length_squared() > 0.000001 else axis
	var first := origin + bore * minf(length * 0.40, 1.5)
	var last := goal - axis * minf(length * 0.26, 1.1) + Vector2.UP * minf(length * 0.18, 0.48)
	return origin.bezier_interpolate(first, last, goal, clampf(progress, 0.0, 1.0))

static func draw_flight(canvas: CanvasItem, view, origin: Vector2, goal: Vector2, direction: Vector2, progress: float) -> void:
	if progress <= 0.0 or progress >= 1.0:
		return
	var tip: Vector2 = view.point(flight_position(origin, goal, direction, progress))
	var previous: Vector2 = view.point(flight_position(origin, goal, direction, progress - 0.007))
	var axis := (tip - previous).normalized()
	if axis.is_zero_approx():
		return
	var traveled: float = tip.distance_to(view.point(origin))
	var body := clampf(float(view.pixels(0.24)), 3.1, 9.0)
	var exposed := minf(traveled, body)
	if exposed < 0.3:
		return
	var span := axis.orthogonal() * maxf(0.90, body * 0.22)
	var rear := tip - axis * exposed
	if exposed < body * 0.43:
		var nose_half_width := span * (exposed / (body * 0.43))
		canvas.draw_colored_polygon(PackedVector2Array([tip, rear + nose_half_width, rear - nose_half_width]), Color("fff2c8"))
		return
	var shoulder := tip - axis * body * 0.43
	# Keep the capsule readable using markings on its body. This mode has no tracer or trail.
	canvas.draw_colored_polygon(PackedVector2Array([
		tip, shoulder + span, rear + span * 0.88, rear - span * 0.88, shoulder - span,
	]), Color("a1b9bd"))
	canvas.draw_line(shoulder, tip, Color("fff0c1"), maxf(1.0, body * 0.19), true)
	canvas.draw_line(rear.lerp(shoulder, 0.30) + span * 0.69, rear.lerp(shoulder, 0.30) - span * 0.62,
		Color("bd8b46"), maxf(1.0, body * 0.15), true)

static func draw_impact(canvas: CanvasItem, view, position: Vector2, age: float, serial: int = 0) -> void:
	if age < 0.0 or age >= IMPACT_DURATION:
		return
	if _impact_glow == null:
		_impact_glow = GradientTexture2D.new()
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.32, 0.72, 1.0])
		gradient.colors = PackedColorArray([Color.WHITE, Color(1,1,1,0.80), Color(1,1,1,0.19), Color(1,1,1,0)])
		_impact_glow.gradient = gradient
		_impact_glow.fill = GradientTexture2D.FILL_RADIAL
		_impact_glow.fill_from = Vector2(0.5, 0.5)
		_impact_glow.fill_to = Vector2(1.0, 0.5)
	var progress := age / IMPACT_DURATION
	var center: Vector2 = view.point(position)
	var radius := clampf(float(view.pixels(0.44)), 4.5, 24.0)
	var glow := radius * (0.36 + 0.53 * sqrt(progress))
	var fade := 1.0 - smoothstep(0.07, 1.0, progress)
	canvas.draw_texture_rect(_impact_glow, Rect2(center - Vector2.ONE * glow, Vector2.ONE * glow * 2.0),
		false, Color(1.0, 0.53, 0.15, fade))
	var highlight := glow * 0.48
	canvas.draw_texture_rect(_impact_glow, Rect2(center - Vector2.ONE * highlight, Vector2.ONE * highlight * 2.0),
		false, Color(1.0, 0.95, 0.65, fade))
	for i in 5:
		var angle := i * TAU / 5.0 + float(serial % 11) * 0.73 + sin(i * 2.7) * 0.19
		var ray := Vector2.from_angle(angle) * radius * (0.64 + 0.23 * cos(i + serial))
		var spark := center + ray * (0.17 + 0.93 * sqrt(progress))
		canvas.draw_line(spark - ray * 0.18 * fade, spark, Color(1,0.74,0.36,fade), maxf(1.0, radius * 0.067), true)
