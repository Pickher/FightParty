extends RefCounted
## One flash per native cannon shot, a short ignition at the real launch rail, and paired flight exhausts.
const FlashShader = preload("res://scripts/visuals/tank_muzzle.gdshader")
const AIR := "anti_air_missile"
# Each arm fires on alternate simulation events. The electric drive is
# engaged across the whole gap between cartridges on the same feed.
const ARM_INTERVAL := .166
const GUN_LIFE := .13
const AIR_LIFE := .13

var flashes: Array[MeshInstance3D] = [null,null]
var ages := PackedFloat32Array([2.0,2.0])
var modes := ["",""]
var rotor_angles := PackedFloat64Array([0.,0.])
var _rotor_speeds := PackedFloat32Array([0.,0.])
var _serial := 0
var _paint: Array[ShaderMaterial] = [null,null]
var _jets: Array[MeshInstance3D] = [null,null]
static var _cannon: ArrayMesh
static var _ignition: ArrayMesh
static var _exhaust: ArrayMesh

static func _ribbon(lobes: int) -> ArrayMesh:
	var build := SurfaceTool.new()
	build.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in lobes:
		for uv in [Vector2.ZERO,Vector2.DOWN,Vector2.RIGHT,Vector2.RIGHT,Vector2.DOWN,Vector2.ONE]:
			build.set_color(Color(i*.5,0.,0.))
			build.set_uv(uv)
			build.add_vertex(Vector3(uv.x,0.,uv.y-.5))
	return build.commit()

static func _plume() -> ArrayMesh:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	var build := SurfaceTool.new()
	build.begin(Mesh.PRIMITIVE_TRIANGLES)
	build.set_material(material)
	var stations := [Vector2(0.,.035), Vector2(.045,.027), Vector2(.115,.017), Vector2(.245,.003)]
	var colors := [Color(1.,.87,.57,.88),Color(.70,.86,1.,.69),Color(.29,.65,1.,.40),Color(.24,.51,1.,0.)]
	for k in stations.size()-1:
		for i in 10:
			for vertex in [Vector2i(i,k),Vector2i(i+1,k),Vector2i(i+1,k+1),Vector2i(i,k),Vector2i(i+1,k+1),Vector2i(i,k+1)]:
				var section: Vector2 = stations[vertex.y]
				var angle: float = TAU*vertex.x/10.
				build.set_color(colors[vertex.y])
				build.add_vertex(Vector3(section.x,cos(angle)*section.y,sin(angle)*section.y))
	return build.commit()

func start(parent: Node3D, side: int, mode: String, elapsed: float) -> void:
	ages[side] = maxf(0.,elapsed)
	modes[side] = mode
	_serial += 1
	if ages[side] >= (AIR_LIFE if mode == AIR else GUN_LIFE):
		return
	if _cannon == null:
		_cannon = _ribbon(3)
		_ignition = _ribbon(1)
	if flashes[side] == null:
		var fx := MeshInstance3D.new()
		fx.name = "PortFlare" + str(side)
		fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var paint := ShaderMaterial.new()
		paint.shader = FlashShader
		fx.material_override = paint
		parent.add_child(fx)
		flashes[side] = fx
		_paint[side] = paint
	flashes[side].mesh = _ignition if mode == AIR else _cannon
	_paint[side].set_shader_parameter("seed",float(_serial)*.731)
	_paint[side].set_shader_parameter("siege",0. if mode == AIR else .14)

func advance(dt: float) -> void:
	for side in 2:
		var firing: bool = not modes[side].is_empty() and modes[side] != AIR and ages[side] < ARM_INTERVAL+.016
		var previous := float(_rotor_speeds[side])
		# The seven tubes advance roughly one chamber per firing pulse;
		# the inertia is visible after the final cartridge clears.
		var target := TAU/(7.*ARM_INTERVAL) if firing else 0.
		_rotor_speeds[side] = move_toward(previous,target,dt*(200. if firing else 25.))
		rotor_angles[side] = fposmod(rotor_angles[side]+dt*(previous+_rotor_speeds[side])*.5,TAU)
		ages[side] += dt

func recoil(side: int) -> float:
	if modes[side] == AIR or ages[side] > GUN_LIFE:
		return 0.
	var age := ages[side]
	return (0.68+.32*smoothstep(0.,.016,age))*(1.-smoothstep(.018,.089,age))

func sync_flashes(muzzles: Array[Node3D], rails: Array[Node3D], diameter: float) -> void:
	for side in 2:
		var fx := flashes[side]
		if fx == null:
			continue
		var air: bool = modes[side] == AIR
		var age := float(ages[side])
		fx.visible = age < (AIR_LIFE if air else GUN_LIFE)
		if fx.visible:
			var size := Vector3(.60,.57,.57) if air else Vector3(.80,.60,.60)
			fx.global_transform = (rails[side] if air else muzzles[side]).global_transform.scaled_local(size*diameter)
			_paint[side].set_shader_parameter("age",age*(1.80 if air else 1.38))

func sync_exhausts(ports: Array[Node3D], strength: float, diameter: float) -> void:
	for side in ports.size():
		var jet := _jets[side]
		if jet == null and strength > .01:
			if _exhaust == null:
				_exhaust = _plume()
			jet = MeshInstance3D.new()
			jet.name = "EngineGlow"
			jet.mesh = _exhaust
			jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ports[side].add_child(jet)
			_jets[side] = jet
		if jet != null:
			jet.visible = strength > .01
			if jet.visible:
				jet.scale = Vector3(strength, .52+.48*strength, .52+.48*strength)*diameter

func cold() -> bool:
	return ages[0] >= GUN_LIFE and ages[1] >= GUN_LIFE and _rotor_speeds[0] == 0. and _rotor_speeds[1] == 0.

func stop() -> void:
	for side in 2:
		ages[side] = 2.
		if flashes[side] != null:
			flashes[side].hide()
		if _jets[side] != null:
			_jets[side].hide()
