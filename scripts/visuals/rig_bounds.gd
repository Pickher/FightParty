extends RefCounted
## Bounds in model space, including transforms on every rigid part.

static func from_scene(resource: PackedScene) -> AABB:
	if resource == null:
		return AABB()
	var probe := resource.instantiate()
	var boxes: Array = []
	collect(probe, Transform3D.IDENTITY, boxes)
	probe.free()
	if boxes.is_empty():
		return AABB()
	var box: AABB = boxes[0]
	for part in boxes:
		box = box.merge(part)
	return box

static func collect(node: Node, parent: Transform3D, boxes: Array) -> void:
	var transform: Transform3D = parent*(node.transform if node is Node3D else Transform3D.IDENTITY)
	if node is MeshInstance3D and node.mesh!=null:boxes.append(transform*node.get_aabb())
	for child in node.get_children():collect(child,transform,boxes)
