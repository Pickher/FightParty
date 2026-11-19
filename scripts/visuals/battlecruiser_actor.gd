extends Node3D
## All dimensions are fractions of one hull length. +X is the bow and +Z points down the map.
## The enclosing layer sets position and uniform scale, and supplies a pausable presentation delta.
const WRECK_DURATION := 1.9
const FLASH_DURATION := 0.14
const DISCHARGE_DURATION := 0.56
const TURN_RATE := 2.35
# Measured from the model’s four pod bores and central cannon, after centering and normalization.
const MAIN_PORT := Vector3(0.449, -0.036, 0.0)
const BATTERIES := [Vector3(0.036, -0.197, -0.347), Vector3(0.036, -0.197, 0.347), Vector3(0.046, 0.023, -0.332), Vector3(0.046, 0.023, 0.332)]

static var shapes: Dictionary = {}
static var paints: Dictionary = {}
static var fracture_cache: Dictionary = {}
var heading := 0.0
var bank := 0.0
var elapsed := 0.0
var charge := -1.0
var shot_age := FLASH_DURATION
var discharge_age := DISCHARGE_DURATION
var wreck_age := -1.0
var active_battery := 0
var shot_count := 0
var pivot := Node3D.new()
var hull := Node3D.new()
var skin := Node3D.new()
var source_meshes: Array[MeshInstance3D] = []
var flash: Node3D
var core: Node3D
var coils: Array[Node3D] = []
var engines: Array[Node3D] = []
var fracture_parts: Array[Node3D] = []
var smoke: Array[Node3D] = []
var blasts: Array[Node3D] = []
var sparks: Array[Node3D] = []

func setup(model: PackedScene, bounds: AABB, initial_heading: float) -> void:
	add_child(pivot)
	pivot.add_child(hull)
	hull.add_child(skin)
	# Import centering is independent of the source node's transform.
	var alignment := Node3D.new()
	skin.add_child(alignment)
	alignment.scale = Vector3.ONE / maxf(maxf(bounds.size.x, bounds.size.z), 0.001)
	var centered := Node3D.new()
	alignment.add_child(centered)
	centered.position = -bounds.get_center()
	var model_root := model.instantiate() as Node3D
	centered.add_child(model_root)
	if model_root is MeshInstance3D:
		source_meshes.append(model_root)
	for node in model_root.find_children("*", "MeshInstance3D", true, false):
		source_meshes.append(node as MeshInstance3D)
	heading = initial_heading
	pivot.rotation.y = -heading
	_update_pose()

func fire(target_layer: String = "ground") -> int:
	if wreck_age >= 0.0:
		return active_battery
	active_battery = (shot_count % 2) + (2 if target_layer == "air" else 0)
	shot_count += 1
	shot_age = 0.0
	if flash == null:
		flash = Node3D.new()
		hull.add_child(flash)
		var corona := _effect(flash, "glow", "orange", Vector3.ZERO)
		corona.scale = Vector3.ONE * 0.12
		var jet := _effect(flash, "jet", "whitehot", Vector3(0.053, 0.0, 0.0))
		jet.rotation.z = -PI / 2.0
		jet.scale = Vector3(0.022, 0.11, 0.022)
	flash.position = BATTERIES[active_battery]
	flash.show()
	_update_pose()
	return active_battery

func set_charge(active: bool, progress := 0.0) -> void:
	charge = clampf(progress, 0.0, 1.0) if active and wreck_age < 0.0 else -1.0

func fire_yamato() -> void:
	if wreck_age < 0.0:
		charge = -1.0
		discharge_age = 0.0
		_update_pose()

func destroy() -> void:
	if wreck_age >= 0.0:
		return
	wreck_age = 0.0
	charge = -1.0
	shot_age = FLASH_DURATION
	discharge_age = DISCHARGE_DURATION
	_prepare_wreck()
	_update_pose()

func is_finished() -> bool:
	return wreck_age >= WRECK_DURATION

func muzzle_world(yamato := false) -> Vector3:
	return hull.to_global(MAIN_PORT if yamato else BATTERIES[active_battery])

func muzzle_screen_offset(yamato := false) -> Vector2:
	var local := to_local(muzzle_world(yamato))
	return Vector2(local.x, local.z)

func advance(delta: float, desired_heading: float) -> void:
	var dt := maxf(delta, 0.0)
	elapsed += dt
	if wreck_age >= 0.0:
		wreck_age += dt
	else:
		var error := angle_difference(heading, desired_heading)
		heading = rotate_toward(heading, desired_heading, TURN_RATE * dt)
		bank = lerpf(bank, clampf(error * 0.66, -0.48, 0.48), 1.0 - exp(-dt * 7.0))
		shot_age = minf(shot_age + dt, FLASH_DURATION)
		discharge_age = minf(discharge_age + dt, DISCHARGE_DURATION)
	_update_pose()

func _update_pose() -> void:
	pivot.rotation.y = -heading
	var kick := exp(-shot_age * 36.0) if shot_age < FLASH_DURATION else 0.0
	var heavy_kick := 0.0
	if discharge_age < DISCHARGE_DURATION:
		heavy_kick = exp(-discharge_age * 7.0) * sin(minf(discharge_age * 36.0, PI / 2.0) + 0.15)
	hull.position = Vector3(-0.018 * kick - 0.12 * heavy_kick, 0.0, 0.0)
	hull.rotation = Vector3(0.15 + bank, 0.0, -0.09 + 0.13 * heavy_kick)
	if flash != null:
		flash.visible = shot_age < FLASH_DURATION and wreck_age < 0.0
		if flash.visible:
			var fade := 1.0 - shot_age / FLASH_DURATION
			flash.scale = Vector3.ONE * (0.22 + fade * 0.78)
	_update_thrust()
	_update_cannon()
	if wreck_age >= 0.0:
		_update_wreck()

func _update_thrust() -> void:
	var amount := clampf(absf(bank) * 2.0, 0.0, 1.0)
	if engines.is_empty() and amount > 0.1 and wreck_age < 0.0:
		for side in [-1.0, 1.0]:
			var jet := _effect(hull, "jet", "exhaust", Vector3(-0.51, 0.023, float(side) * 0.332))
			jet.rotation.z = PI / 2.0
			engines.append(jet)
	for i in engines.size():
		var engine := engines[i]
		engine.visible = amount > 0.06 and wreck_age < 0.0
		if engine.visible:
			var thrust := amount if ((bank > 0.0) == (i == 0)) else amount * 0.30
			engine.scale = Vector3(0.035, 0.06 + thrust * 0.15, 0.035)
			engine.position.x = -0.49 - engine.scale.y / 2.0

func _update_cannon() -> void:
	var firing := discharge_age < DISCHARGE_DURATION
	var active := (charge >= 0.0 or firing) and wreck_age < 0.0
	if core == null and active:
		core = _effect(hull, "glow", "plasma", MAIN_PORT + Vector3(0.01, 0.018, 0))
		for i in 3:
			var ring := _effect(hull, "ring", "arc", MAIN_PORT)
			ring.rotation.z = 1.12
			coils.append(ring)
	if core == null:
		return
	core.visible = active
	for i in coils.size():
		var ring := coils[i]
		ring.visible = active
		if not active:
			continue
		if firing:
			# Pressure rings roll forward from the central bore, then dissipate.
			var t := clampf((discharge_age - i * 0.046) / 0.32, 0.0, 1.0)
			ring.visible = t > 0.0 and t < 1.0
			ring.position = MAIN_PORT + Vector3(0.06 + t * 0.48, 0.02, 0.0)
			ring.scale = Vector3.ONE * (0.12 + 0.26 * sin(t * PI))
		else:
			# Each induction loop contracts into the barrel, with its own phase.
			var phase := fposmod(elapsed * (1.1 + charge * 1.8) + i / 3.0, 1.0)
			ring.position = MAIN_PORT + Vector3(0.014 + (1.0 - phase) * 0.09, 0.018, 0.0)
			ring.scale = Vector3.ONE * (0.065 + charge * 0.065 + (1.0 - phase) * 0.14)
	if firing:
		core.scale = Vector3.ONE * (0.48 * pow(1.0 - discharge_age / DISCHARGE_DURATION, 2.0) + 0.018)
	elif active:
		core.scale = Vector3.ONE * (0.07 + 0.27 * charge * charge + sin(elapsed * 24.0) * 0.014)

func _prepare_wreck() -> void:
	# Ship is imported as a single textured mesh. Preserve its UVs/materials in three jagged
	# sections; share these meshes across wrecks and create the instances only on destruction.
	for i in 3:
		var part := Node3D.new()
		hull.add_child(part)
		fracture_parts.append(part)
	for source in source_meshes:
		if source.mesh == null:
			continue
		var relative := hull.global_transform.affine_inverse() * source.global_transform
		var sections := _fracture_meshes(source.mesh, relative)
		for i in sections.size():
			if sections[i] == null:
				continue
			var shard := MeshInstance3D.new()
			shard.mesh = sections[i]
			shard.transform = relative
			fracture_parts[i].add_child(shard)
	for part in fracture_parts:
		part.hide()
	for i in 3:
		blasts.append(_effect(pivot, "glow", "orange", Vector3.ZERO))
		smoke.append(_effect(pivot, "glow", "smoke", Vector3.ZERO))
	for i in 8:
		sparks.append(_effect(pivot, "jet", "ember", Vector3.ZERO))

func _update_wreck() -> void:
	var t := clampf(wreck_age / WRECK_DURATION, 0.0, 1.0)
	var split := clampf((wreck_age - 0.28) / 1.12, 0.0, 1.0)
	var drift := 1.0 - pow(1.0 - split, 2.0)
	hull.position = Vector3(-0.16 * t, -0.32 * t, 0.22 * t)
	hull.rotation = Vector3(0.15 + bank + 0.93 * t, -0.36 * t, -0.09 - 0.49 * t)
	skin.visible = wreck_age < 0.28
	for i in fracture_parts.size():
		var part := fracture_parts[i]
		var side := float(i - 1)
		part.visible = not skin.visible and t < 0.98
		part.position = Vector3(side * drift * 0.35, -drift * absf(side) * 0.1, side * drift * 0.21)
		part.rotation = Vector3(side * drift * 0.37, -side * drift * 0.46, drift * (0.16 + side * 0.57))
		part.scale = Vector3.ONE * (1.0 - smoothstep(0.64, 0.98, t) * 0.98)
	for i in blasts.size():
		var start := [0.0, 0.24, 0.47]
		var origin := Vector3(0.20 - i * 0.18, 0.25, sin(i * 2.2) * 0.14)
		var burst_age := wreck_age - float(start[i])
		var blast := blasts[i]
		blast.visible = burst_age >= 0.0 and burst_age < 0.40
		if blast.visible:
			blast.position = origin
			var pulse := sin(clampf((burst_age + 0.025) / 0.43, 0.0, 1.0) * PI)
			blast.scale = Vector3.ONE * (0.1 + 0.49 * pulse)
		var plume := smoke[i]
		var smoke_t := clampf((burst_age - 0.08) / 1.05, 0.0, 1.0)
		plume.visible = smoke_t > 0.0 and smoke_t < 1.0
		if plume.visible:
			plume.position = origin + Vector3(-smoke_t * 0.20, smoke_t * 0.32, smoke_t * 0.09)
			plume.scale = Vector3.ONE * (0.18 + 0.38 * sin(smoke_t * PI)) * (1.0 - smoothstep(0.73, 1.0, smoke_t))
	for i in sparks.size():
		var spark := sparks[i]
		var spark_t := clampf((wreck_age - 0.18 - (i % 3) * 0.075) / 0.72, 0.0, 1.0)
		spark.visible = spark_t > 0.0 and spark_t < 1.0
		if spark.visible:
			var angle := i * 2.4 + 0.32
			var distance := 0.08 + spark_t * (0.48 + 0.10 * (i % 3))
			spark.position = Vector3(cos(angle) * distance, 0.10 + sin(spark_t * PI) * 0.28, sin(angle) * distance)
			spark.rotation = Vector3(0.0, -angle, -PI / 2.0)
			spark.scale = Vector3(0.019, 0.105, 0.019) * (1.0 - spark_t)

static func _fracture_meshes(mesh: Mesh, to_hull: Transform3D) -> Array:
	if fracture_cache.has(mesh):
		return fracture_cache[mesh]
	var sections := [ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new()]
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			indices.resize(verts.size())
			for i in verts.size():
				indices[i] = i
		var groups: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
		for i in range(0, indices.size() - 2, 3):
			var center := to_hull * ((verts[indices[i]] + verts[indices[i + 1]] + verts[indices[i + 2]]) / 3.0)
			var slice := center.x + center.z * 0.27 + 0.025 * sin(center.z * 37.0)
			var group := 0 if slice < -0.145 else (1 if slice < 0.13 else 2)
			groups[group].append(indices[i])
			groups[group].append(indices[i + 1])
			groups[group].append(indices[i + 2])
		for i in 3:
			if groups[i].is_empty():
				continue
			var part: ArrayMesh = sections[i]
			var partial := arrays.duplicate()
			partial[Mesh.ARRAY_INDEX] = groups[i]
			part.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, partial)
			part.surface_set_material(part.get_surface_count() - 1, mesh.surface_get_material(surface))
	for i in 3:
		if sections[i].get_surface_count() == 0:
			sections[i] = null
	fracture_cache[mesh] = sections
	return sections

static func _effect(parent: Node3D, shape: String, paint: String, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	if not shapes.has(shape):
		match shape:
			"ring":
				var torus := TorusMesh.new()
				torus.inner_radius = 0.45
				torus.outer_radius = 0.5
				torus.rings = 20
				torus.ring_segments = 5
				shapes[shape] = torus
			"jet":
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.5
				cone.height = 1.0
				cone.radial_segments = 8
				cone.rings = 0
				shapes[shape] = cone
			"glow":
				var quad := QuadMesh.new()
				quad.size = Vector2.ONE
				shapes[shape] = quad
	node.mesh = shapes[shape]
	if not paints.has(paint):
		var colors := {"orange":Color("ff963c"), "whitehot":Color("ffeabe"), "plasma":Color("ffac56"), "arc":Color("ffcc83"), "exhaust":Color("72cffc"), "smoke":Color("3c4044"), "ember":Color("ffcb76")}
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = colors[paint]
		if shape == "glow":
			var gradient := Gradient.new()
			gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.58, 1.0])
			gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.94), Color(1, 1, 1, 0.34), Color(1, 1, 1, 0)])
			var glow_map := GradientTexture2D.new()
			glow_map.width = 64
			glow_map.height = 64
			glow_map.fill = GradientTexture2D.FILL_RADIAL
			glow_map.fill_from = Vector2(0.5, 0.5)
			glow_map.fill_to = Vector2(1.0, 0.5)
			glow_map.gradient = gradient
			material.albedo_texture = glow_map
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			material.billboard_keep_scale = true
			material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if paint == "smoke" else BaseMaterial3D.BLEND_MODE_ADD
		paints[paint] = material
	node.material_override = paints[paint]
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	node.position = at
	return node
