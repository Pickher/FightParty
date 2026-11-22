extends RefCounted
## Native meshes share a rigid pivot and a sculpted intermediate shape. Their solid seams
## pass each other at different times as the individual hinges and telescoping parts move.
const ExchangeShader = preload("res://scripts/visuals/tank_shell.gdshader")

var joint: Node3D
var at_rest: Transform3D
var deployed: Transform3D
var mobile_mesh: MeshInstance3D
var siege_mesh: MeshInstance3D
var shell_phase := -1.0
var _mobile_paint: Array[ShaderMaterial] = []
var _siege_paint: Array[ShaderMaterial] = []
var _rail := Vector3.RIGHT
var _limits := Vector2.ZERO

func setup(node: Node3D, target: Transform3D, rail: Vector3) -> bool:
	joint = node
	at_rest = joint.transform
	deployed = target
	mobile_mesh = node.get_node_or_null(String(node.name) + "MobileMesh")
	siege_mesh = node.get_node_or_null(String(node.name) + "SiegeMesh")
	if mobile_mesh == null or siege_mesh == null or mobile_mesh.mesh == null or siege_mesh.mesh == null:
		return false
	_rail = rail.normalized()
	var bounds := mobile_mesh.get_aabb().merge(siege_mesh.get_aabb())
	var center := bounds.get_center().dot(_rail)
	var half := bounds.size.dot(_rail.abs()) * 0.5 + 0.005
	_limits = Vector2(center - half, center + half)
	return true

func skin(phase: float) -> void:
	if is_equal_approx(phase, shell_phase):
		return
	shell_phase = phase
	var edge_progress := smoothstep(0.38, 0.64, phase)
	var edge := lerpf(_limits.x, _limits.y, edge_progress)
	if mobile_mesh != null:
		_skin_side(mobile_mesh, _mobile_paint, 1.0, smoothstep(0.0, 0.50, phase), edge_progress, edge)
	if siege_mesh != null:
		_skin_side(siege_mesh, _siege_paint, -1.0, 1.0 - smoothstep(0.50, 1.0, phase), edge_progress, edge)

func _skin_side(mesh: MeshInstance3D, paints: Array[ShaderMaterial], sign_side: float, morph: float, progress: float, edge: float) -> void:
	mesh.visible = progress < 1.0 if sign_side > 0.0 else progress > 0.0
	if not mesh.visible:
		return
	if mesh.get_blend_shape_count() > 0 and not is_equal_approx(mesh.get_blend_shape_value(0), morph):
		mesh.set_blend_shape_value(0, morph)
	if progress > 0.0 and progress < 1.0:
		for i in mesh.mesh.get_surface_count():
			if i >= paints.size():
				var source := mesh.mesh.surface_get_material(i) as StandardMaterial3D
				paints.append(_make_paint(source, sign_side))
			paints[i].set_shader_parameter("edge", edge)
			if mesh.get_surface_override_material(i) != paints[i]:
				mesh.set_surface_override_material(i, paints[i])
	elif not paints.is_empty() and mesh.get_surface_override_material(0) != null:
		for i in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(i, null)

func _make_paint(source: StandardMaterial3D, sign_side: float) -> ShaderMaterial:
	var paint := ShaderMaterial.new()
	paint.shader = ExchangeShader
	paint.set_shader_parameter("rail", _rail)
	paint.set_shader_parameter("direction", sign_side)
	if source != null:
		paint.set_shader_parameter("paint_map", source.albedo_texture)
		paint.set_shader_parameter("metal_map", source.roughness_texture)
		paint.set_shader_parameter("light_map", source.emission_texture)
		paint.set_shader_parameter("tint", source.albedo_color)
		paint.set_shader_parameter("lamp", source.emission * source.emission_energy_multiplier if source.emission_enabled else Color.BLACK)
		paint.set_shader_parameter("metal", source.metallic)
		paint.set_shader_parameter("roughness", source.roughness)
	return paint
