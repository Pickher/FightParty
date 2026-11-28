extends RefCounted
## Static portraits shared by the recruitment panel and the barracks shop.
const DIRECTORY := "res://assets/ui/recruits/"
const SELECTED_SECONDARY := Color("adbacb")
const THUMBNAIL_SIZE := 64
const THUMBNAIL_PATH := DIRECTORY + "thumbnails.tres"
static var _portraits: Dictionary = {}
static var _thumbnails: SpriteFrames
static var _checked_atlas := false
static var _backdrops: Dictionary = {}

static func _texture(kind: String, thumbnail: bool) -> Texture2D:
	if thumbnail:
		if not _checked_atlas:
			_checked_atlas = true
			if ResourceLoader.exists(THUMBNAIL_PATH):
				_thumbnails = load(THUMBNAIL_PATH) as SpriteFrames
		if _thumbnails != null and _thumbnails.has_animation(kind) and _thumbnails.get_frame_count(kind) > 0:
			var frame := _thumbnails.get_frame_texture(kind, 0)
			if frame != null:
				return frame
	if not _portraits.has(kind):
		var path := DIRECTORY + kind + ".png"
		_portraits[kind] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _portraits[kind]

static func _background(protoss: bool = false) -> GradientTexture2D:
	if _backdrops.has(protoss):
		return _backdrops[protoss]
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.40, 0.76, 1.0])
	if protoss:
		gradient.colors = PackedColorArray([Color("285649"), Color("1b3c32"), Color("112a23"), Color("0b1b17")])
	else:
		gradient.colors = PackedColorArray([Color("67508a"), Color("473460"), Color("29213c"), Color("171421")])
	var backdrop := GradientTexture2D.new()
	backdrop.width = 192
	backdrop.height = 192
	backdrop.gradient = gradient
	backdrop.fill = GradientTexture2D.FILL_RADIAL
	backdrop.fill_from = Vector2(0.36, 0.34)
	backdrop.fill_to = Vector2(1.0, 0.99)
	_backdrops[protoss] = backdrop
	return backdrop

static func draw(game, rect: Rect2, kind: String, selected: bool = false, enabled: bool = true) -> void:
	var stats: Dictionary = game.sim.catalog.get(kind, {})
	var protoss: bool = stats.get("race", "") == "protoss"
	var inner := rect.grow(-1.0)
	var border := Color("86d5b8") if selected else Color("675b76")
	var bevel := Color(0.82, 0.75, 0.90, 0.20)
	if protoss:
		border = Color("9ceec9") if selected else Color("3b7863")
		bevel = Color("a5d6bb33")
	game.draw_rect(rect, border)
	game.draw_texture_rect(_background(protoss), inner, false)
	var texture := _texture(kind, rect.size.x <= THUMBNAIL_SIZE)
	if texture != null:
		game.draw_texture_rect(texture, inner, false, Color.WHITE if enabled else Color(0.67, 0.68, 0.71, 0.65))
	else:
		var color := Color(stats.get("color", "adbacb"))
		game._draw_unit(rect.get_center(), kind, Color(color, 1.0 if enabled else 0.45), rect.size.x * 0.23)
	game.draw_line(inner.position, inner.position + Vector2(inner.size.x, 0), bevel)
	game.draw_line(inner.position, inner.position + Vector2(0, inner.size.y), bevel)
