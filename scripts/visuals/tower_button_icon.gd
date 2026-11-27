extends RefCounted

const UnitArt = preload("res://scripts/unit_art.gd")
const MASK := Color(0.18, 0.21, 0.25, 0.86)

## 灰色遮罩从十二点钟方向顺时针揭开，剩余比例直接取自模拟时钟。
static func draw(canvas: CanvasItem, center: Vector2, radius: float, kind: String, race: String, tint: Color, remaining_fraction: float = 0.0) -> void:
	canvas.draw_circle(center, radius, Color("112030"))
	UnitArt.structure(canvas, center, kind, race, radius * 0.68, tint)
	var remaining := clampf(remaining_fraction, 0.0, 1.0)
	if remaining >= 1.0:
		canvas.draw_circle(center, radius, MASK)
	elif remaining > 0.0:
		var sweep := TAU * remaining
		var start := -PI * 0.5 + TAU - sweep
		var segments := ceili(40.0 * remaining)
		var sector := PackedVector2Array([center])
		for index in range(segments + 1):
			var angle := start + sweep * float(index) / float(segments)
			sector.append(center + Vector2.from_angle(angle) * radius)
		canvas.draw_colored_polygon(sector, MASK)
		canvas.draw_line(center, sector[1], Color("bcc5ce"), 1.0, true)
	canvas.draw_arc(center, radius, 0.0, TAU, 40, Color(tint, 0.65), 1.0, true)
