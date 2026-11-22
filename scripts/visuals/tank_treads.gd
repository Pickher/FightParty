extends RefCounted
## One GPU-instanced belt per bank. Every shoe advances around the imported closed loop.
const TreadShader = preload("res://scripts/visuals/tank_treads.gdshader")
const SAMPLES := 128
static var layouts: Dictionary = {}

var renderer := MultiMeshInstance3D.new()
var material := ShaderMaterial.new()

func setup(bank: Node3D) -> bool:
	if not layouts.has(bank.name):
		var loop := _loop(bank)
		if loop.size() != 16:
			return false
		var image := Image.create_empty(SAMPLES, 1, false, Image.FORMAT_RGBAF)
		var length := _write_samples(image, loop)
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = mesh
		batch.instance_count = maxi(14, roundi(length / 0.043))
		for i in batch.instance_count:
			batch.set_instance_transform(i, Transform3D.IDENTITY)
		# Vertex displacement occurs on the GPU, outside the box's default bounds.
		batch.custom_aabb = AABB(Vector3(-1,-0.6,-0.6), Vector3(2,1.2,1.2))
		var width := bank.get_node_or_null(String(bank.name) + "TrackWidth") as Node3D
		if width == null:
			return false
		layouts[bank.name] = {"batch": batch, "texture": ImageTexture.create_from_image(image),
				"length": length, "width": absf(width.position.z)}
	var layout: Dictionary = layouts[bank.name]
	renderer.name = "MovingShoes"
	renderer.multimesh = layout.batch
	renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material.shader = TreadShader
	material.set_shader_parameter("shoe_path", layout.texture)
	material.set_shader_parameter("perimeter", layout.length)
	material.set_shader_parameter("belt_width", layout.width)
	material.set_shader_parameter("shoe_count", float(layout.batch.instance_count))
	renderer.material_override = material
	bank.add_child(renderer)
	return true

static func _loop(bank: Node3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in 16:
		var marker := bank.get_node_or_null("%sPath%02d" % [bank.name, i]) as Node3D
		if marker == null:
			break
		points.append(marker.position)
	return points

static func _write_samples(image: Image, points: PackedVector3Array) -> float:
	var lengths := PackedFloat32Array([0.0])
	for i in points.size():
		lengths.append(lengths[-1] + points[i].distance_to(points[(i + 1) % points.size()]))
	var total := lengths[-1]
	var i := 0
	for column in SAMPLES:
		var distance := total * (column + 0.5) / SAMPLES
		while i < points.size() - 1 and distance > lengths[i + 1]:
			i += 1
		var f := inverse_lerp(lengths[i], lengths[i + 1], distance)
		var point := points[i].lerp(points[(i + 1) % points.size()], f)
		image.set_pixel(column, 0, Color(point.x, point.y, point.z, 1.0))
	return total
