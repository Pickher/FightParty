extends RefCounted
## A rigid assembly and its two joint frames. Meshes stay attached for the entire travel.

var joint: Node3D
var at_rest: Transform3D
var deployed: Transform3D
var meshes: Array[MeshInstance3D] = []
var _timing: Vector4
var _pose: Transform3D
var _progress := -1.0
var _reset_motion := false
var _suspension := 0.0

func setup(node: Node3D, target: Transform3D, timing: Vector4) -> void:
	joint = node
	at_rest = node.transform
	deployed = target
	_timing = timing
	if node.name == &"Hull":
		_suspension = 1.0
	elif String(node.name).begins_with("Crank"):
		_suspension = -1.0
	_reset_motion = node.name in [&"Hull", &"Turret", &"Mount", &"BarrelP", &"BarrelN", &"CenterBarrel"]

func set_progress(p: float) -> void:
	if _progress == p:
		# Driving, aiming and recoil are added on top of this mechanical pose.
		if _reset_motion:
			joint.transform = _pose
		return
	_progress = p
	var turn := smoothstep(_timing.x, _timing.y, p)
	var slide := smoothstep(_timing.z, _timing.w, p)
	var orientation := at_rest.basis.slerp(deployed.basis, turn)
	_pose = Transform3D(orientation, at_rest.origin.lerp(deployed.origin, slide))
	if _suspension != 0.0:
		# The vertical plungers unload the hull while keeping their bogies grounded.
		var unlock := smoothstep(0.0, 0.10, p) * (1.0 - smoothstep(0.18, 0.62, p))
		_pose.origin.y += _suspension * 0.010 * unlock
	joint.transform = _pose
