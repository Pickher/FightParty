extends RefCounted
## Static portraits shared by the recruitment panel and the barracks shop.
const DIRECTORY := "res://assets/ui/recruits/"
const SELECTED_SECONDARY := Color("adbacb")
const THUMBNAIL_SIZE := 64
const THUMBNAIL_PATH := DIRECTORY + "thumbnails.tres"
static var _portraits: Dictionary = {}
static var _thumbnails: SpriteFrames
static var _checked_atlas := false
static var _backdrop: GradientTexture2D

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

static func _background() -> GradientTexture2D:
	if _backdrop == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.40, 0.76, 1.0])
		gradient.colors = PackedColorArray([Color("67508a"), Color("473460"), Color("29213c"), Color("171421")])
		_backdrop = GradientTexture2D.new()
		_backdrop.width = 192
		_backdrop.height = 192
		_backdrop.gradient = gradient
		_backdrop.fill = GradientTexture2D.FILL_RADIAL
		_backdrop.fill_from = Vector2(0.36, 0.34)
		_backdrop.fill_to = Vector2(1.0, 0.99)
	return _backdrop

static func draw(game, rect: Rect2, kind: String, selected: bool = false, enabled: bool = true) -> void:
	var inner := rect.grow(-1.0)
	game.draw_rect(rect, Color("86d5b8") if selected else Color("675b76"))
	game.draw_texture_rect(_background(), inner, false)
	var texture := _texture(kind, rect.size.x <= THUMBNAIL_SIZE)
	if texture != null:
		game.draw_texture_rect(texture, inner, false, Color.WHITE if enabled else Color(0.67, 0.68, 0.71, 0.65))
	else:
		var color := Color(game.sim.catalog[kind].color)
		game._draw_unit(rect.get_center(), kind, Color(color, 1.0 if enabled else 0.45), rect.size.x * 0.23)
	var bevel := Color(0.82, 0.75, 0.90, 0.20)
	game.draw_line(inner.position, inner.position + Vector2(inner.size.x, 0), bevel)
	game.draw_line(inner.position, inner.position + Vector2(0, inner.size.y), bevel)
