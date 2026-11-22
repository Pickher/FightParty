extends RefCounted
## The original Hellion rig and three matching exterior sections assemble in mech model space.
const RigBounds = preload("res://scripts/visuals/rig_bounds.gd")
const Hellion = preload("res://scripts/visuals/hellion_actor.gd")
const CAR_RIG := "res://assets/models/hellbat/hellion_rig.glb"
const CAR_HULL := "res://assets/models/hellbat/hellion_wreck.glb"
const FIT := 1.01901

var car: Hellion
var body: MeshInstance3D
var sections: Array[MeshInstance3D] = []
var panels: Array[Node3D] = []
var parked: Array[Transform3D] = []
var stored: Array[Transform3D] = []
var slots: Array[Vector2] = []
static var car_bounds := AABB()

func setup(frame: Node3D) -> void:
	var rig := load(CAR_RIG) as PackedScene
	if car_bounds.size == Vector3.ZERO:
		car_bounds = RigBounds.from_scene(rig)
	car = Hellion.new()
	frame.add_child(car)
	car.setup(rig, car_bounds, 0.0)
	car.position = car_bounds.get_center() * FIT
	car.scale = Vector3.ONE * FIT / car.length_factor
	body = car.model_root.find_child("Body", true, false)
	var pieces := (load(CAR_HULL) as PackedScene).instantiate()
	car.model_root.add_child(pieces)
	for piece_name in ["NoseChunk", "CockpitChunk", "EngineChunk"]:
		var part := pieces.find_child(piece_name, true, false) as MeshInstance3D
		part.set_surface_override_material(0, Hellion.original_paint)
		sections.append(part)
	# Panels deploy from close-fitting volumes under the shoulder armor and fuel pods.
	_register(sections[0], Vector3(.10,.40,0), Vector3(0,0,-1.14), Vector3(.19,.62,.84), .30,.92)
	_register(sections[1], Vector3(.01,.45,0), Vector3(0,0,-.76), Vector3(.44,.46,.68), .34,.86)
	_register(sections[2], Vector3(-.08,.38,0), Vector3(0,0,.94), Vector3(.44,.48,.68), .30,.89)
	for i in car.wheels.size():
		var side := -1.0 if i % 2 == 0 else 1.0
		var front := i < 2
		var origin := Vector3(.02,.105,side * .155) if front else Vector3(-.09,.45,side * .245)
		_register(car.wheels[i], origin, Vector3(side * .35,0,0), Vector3(.62,.62,.21), .20 if front else .28, .79 if front else .86)
	_register(car.turret, Vector3(-.21,.57,0), Vector3(0,0,-.45), Vector3(.38,.46,.66), .43,.95)
	set_progress(0.0)

func _register(part: Node3D, position: Vector3, angles: Vector3, size: Vector3, start: float, stop: float) -> void:
	panels.append(part)
	parked.append(part.transform)
	stored.append(Transform3D(Basis.from_euler(angles) * Basis.from_scale(size), position))
	slots.append(Vector2(start, stop))

func set_progress(p: float) -> void:
	car.visible = p > 0.19
	body.visible = p >= 1.0
	for i in panels.size():
		var part := panels[i]
		var w := smoothstep(slots[i].x, slots[i].y, p)
		part.visible = w > 0.0 and (i >= sections.size() or p < 1.0)
		if not part.visible:
			continue
		var pose := stored[i].interpolate_with(parked[i], w)
		var arc := sin(PI * w)
		if i >= 3 and i <= 6:
			pose.origin.z += signf(parked[i].origin.z) * 0.056 * arc
		else:
			pose.origin.y += 0.034 * arc
		part.transform = pose
	car.suspension.rotation = Vector3(0.11, 0, -0.085) * smoothstep(.77,1.0,p)
