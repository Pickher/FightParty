extends Node
## Presentation only. One shared transparent world; no physics or simulation writes.
const BattlecruiserLayer = preload("res://scripts/visuals/battlecruiser_layer.gd")
const ThorLayer = preload("res://scripts/visuals/thor_layer.gd")
const ENABLED := true # Source-level fallback/performance comparison switch.
const MODEL_PATH := "res://assets/models/medivac/medivac.glb"
const MAX_LIVE := 32
const MAX_WRECKS := 12
const MAX_TARGET_EDGE := 1024
var game
var battlecruisers = BattlecruiserLayer.new()
var thors = ThorLayer.new()
var viewport: SubViewport
var camera: Camera3D
var scene: Node3D
var packed: PackedScene
var entries: Dictionary = {}
var bursts: Array = []
var clock := 0.0
var view_size := Vector2.ONE
var bounds := AABB()
var ready_model := false

func _ready() -> void:
	if not ENABLED:return
	packed = load(MODEL_PATH) as PackedScene if ResourceLoader.exists(MODEL_PATH) else null
	bounds = _model_bounds(packed)
	if maxf(bounds.size.x, bounds.size.z) < 0.0001:
		packed = null
	var path := BattlecruiserLayer.MODEL_PATH
	var flagship: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
	var flagship_bounds := _model_bounds(flagship)
	if maxf(flagship_bounds.size.x, flagship_bounds.size.z) < 0.0001:
		flagship = null
	var walker: PackedScene = load(ThorLayer.MODEL_PATH) as PackedScene if ResourceLoader.exists(ThorLayer.MODEL_PATH) else null
	var walker_bounds := _model_bounds(walker)
	if maxf(walker_bounds.size.x, walker_bounds.size.z) < 0.0001:
		walker = null
	if packed == null and flagship == null and walker == null:return
	viewport=SubViewport.new()
	viewport.transparent_bg=true
	viewport.own_world_3d=true
	viewport.size=Vector2i(2,2)
	viewport.render_target_clear_mode=SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d=Viewport.MSAA_DISABLED
	add_child(viewport)
	scene=Node3D.new()
	viewport.add_child(scene)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	camera.rotation_degrees=Vector3(-90,0,0)
	camera.near=0.1
	camera.far=4000
	scene.add_child(camera)
	camera.current=true
	var environment=WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("c9dcf5")
	environment.environment.ambient_light_energy=0.75
	scene.add_child(environment)
	var light=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-55,-30,0)
	light.light_energy=1.4
	light.shadow_enabled=false
	scene.add_child(light)
	battlecruisers.configure(scene, flagship, flagship_bounds)
	thors.configure(scene, walker, walker_bounds)
	ready_model=true

func _model_bounds(resource: PackedScene) -> AABB:
	if resource == null:
		return AABB()
	var probe := resource.instantiate()
	var boxes: Array = []
	_collect_bounds(probe, Transform3D.IDENTITY, boxes)
	probe.free()
	if boxes.is_empty():
		return AABB()
	var box: AABB = boxes[0]
	for part in boxes:
		box = box.merge(part)
	return box

func _collect_bounds(node: Node, parent: Transform3D, boxes: Array) -> void:
	var transform: Transform3D = parent*(node.transform if node is Node3D else Transform3D.IDENTITY)
	if node is MeshInstance3D and node.mesh!=null:boxes.append(transform*node.get_aabb())
	for child in node.get_children():_collect_bounds(child,transform,boxes)

func reset() -> void:
	for entry in entries.values():
		entry.root.hide()
		entry.root.queue_free()
	entries.clear()
	bursts.clear()
	battlecruisers.reset()
	thors.reset()
	clock=0

func _glow(color: Color) -> MeshInstance3D:
	var node=MeshInstance3D.new()
	var sphere=SphereMesh.new()
	sphere.radius=0.06
	sphere.height=0.12
	sphere.radial_segments=8
	sphere.rings=4
	node.mesh=sphere
	var material=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=color
	node.material_override=material
	return node

func _create(unit: Dictionary) -> Dictionary:
	var root=Node3D.new()
	scene.add_child(root)
	var pose=Node3D.new()
	root.add_child(pose)
	var model=packed.instantiate()
	pose.add_child(model)
	model.position-=bounds.get_center()
	var exhausts: Array = []
	# Original interpretation: model nose is +X, twin engine tails toward -X.
	for side in [-1,1]:
		var exhaust=_glow(Color("7bcbff"))
		exhaust.position=Vector3(-bounds.size.x*0.48,0,side*bounds.size.z*0.29)
		pose.add_child(exhaust)
		exhausts.append(exhaust)
	var lamp=_glow(Color("83ffbd"))
	lamp.position=Vector3(bounds.size.x*0.13,bounds.size.y*0.6,0)
	pose.add_child(lamp)
	var motion: Vector2 = unit.pos-unit.prev
	var heading: float = motion.angle() if motion.length_squared()>0.000001 else (0.0 if int(unit.team)==0 else PI)
	return {"root":root,"pose":pose,"exhausts":exhausts,"lamp":lamp,"heading":heading,"pos":unit.pos,"team":unit.team,"dead":false,"born":clock,"size":1.6}

func before_tick() -> Dictionary:
	var result: Dictionary = {}
	if not ready_model:return result
	for unit in game.sim.units:
		if unit.kind not in ["medivac", "battlecruiser", "thor"]:continue
		if unit.kind == "medivac" and game._hidden_team(int(unit.team)):continue
		var snapshot := {"kind": unit.kind, "pos": unit.pos, "team": unit.team}
		if unit.kind == "thor":
			snapshot.prev = unit.prev
			snapshot.air_weapon_index = unit.get("air_weapon_index", 0)
			snapshot.switch_until_tick = unit.get("switch_until_tick", 0)
		elif unit.kind == "battlecruiser":
			snapshot.fire_tick = int(unit.get("yamato_fire_tick", -1))
			snapshot.target = int(unit.get("yamato_target", -1))
			var target = game.sim.by_id.get(snapshot.target)
			snapshot.target_pos = target.pos if target != null else unit.pos
		result[unit.id] = snapshot
	return result

func events(tick_events: Array, before: Dictionary) -> void:
	if not ready_model:return
	for event in tick_events:
		if str(event.type)!="death" or not before.has(event.id):continue
		var old: Dictionary = before[event.id]
		if old.kind != "medivac" or game._hidden_team(int(old.team)):continue
		if bursts.size()>=MAX_WRECKS:bursts.pop_front()
		bursts.append({"pos":event.pos,"team":old.team,"at":clock,"id":event.id})
		if entries.has(event.id):
			entries[event.id].dead=true
			entries[event.id].at=clock
			entries[event.id].pos=event.pos

func sync(view, delta: float) -> void:
	if not ready_model or game.sim==null:return
	var running: bool = not (not game.started or game.paused or game.backgrounded or game.help_open or game.economy_open or game.setup_open)
	var dt: float = minf(delta,0.1) if running else 0.0
	clock+=dt
	view_size=view.viewport_size()
	var factor: float = minf(1.0,float(MAX_TARGET_EDGE)/maxf(view_size.x,view_size.y))
	var target_size:=Vector2i(maxi(2,roundi(view_size.x*factor)),maxi(2,roundi(view_size.y*factor)))
	if viewport.size!=target_size:viewport.size=target_size
	camera.size=maxf(1,view_size.y)
	camera.position=Vector3(view_size.x*0.5,1500,view_size.y*0.5)
	var alpha: float = clampf(float(game.accumulator)*float(game.sim.rules.tick_rate),0,1)
	var healing: Dictionary = {}
	for beam in game.sim.active_beams:
		if bool(beam.get("healing",false)):healing[beam.source_id]=true
	var retained: Dictionary = {}
	var count := 0
	for unit in game.sim.units:
		if packed == null or unit.kind!="medivac" or game._hidden_team(int(unit.team)):continue
		var position: Vector2 = unit.prev.lerp(unit.pos,alpha)
		if not game._camera_rect().grow(2).has_point(position) or count>=MAX_LIVE:continue
		count+=1
		retained[unit.id]=true
		if not entries.has(unit.id):entries[unit.id]=_create(unit)
		var entry: Dictionary = entries[unit.id]
		entry.pos=position
		var body: Array = game.sim.catalog.medivac.size
		entry.size=maxf(float(body[0]),float(body[1]))
		var motion: Vector2 = unit.pos-unit.prev
		var moving: bool = motion.length_squared()>0.000001
		var desired: float = motion.angle() if moving else float(entry.heading)
		var turn: float = angle_difference(float(entry.heading),desired)
		entry.heading=lerp_angle(float(entry.heading),desired,1.0-exp(-dt*8.0))
		entry.root.rotation.y=-float(entry.heading)
		entry.pose.rotation.z=lerpf(entry.pose.rotation.z,0.17+(-0.06 if moving else 0.02),1.0-exp(-dt*5))
		entry.pose.rotation.x=lerpf(entry.pose.rotation.x,clampf(turn*0.20,-0.18,0.18),1.0-exp(-dt*6))
		var screen: Vector2 = view.point(position)
		var diameter: float = view.pixels(float(entry.size))
		entry.root.position=Vector3(screen.x,0,screen.y+sin(clock*2.7+float(unit.id))*diameter*0.025)
		entry.root.scale=Vector3.ONE*diameter/maxf(bounds.size.x,bounds.size.z)
		for exhaust in entry.exhausts:
			exhaust.visible=moving
			exhaust.scale=Vector3(1.6+0.15*sin(clock*22+float(unit.id)),0.6,0.6)
		entry.lamp.visible=healing.has(unit.id)
	for id in entries.keys():
		var entry: Dictionary = entries[id]
		if game._hidden_team(int(entry.team)):
			entry.root.hide()
			entry.root.queue_free()
			entries.erase(id)
		elif bool(entry.dead):
			var age: float = clock-float(entry.at)
			if age>0.65 or not bursts.any(func(b):return int(b.id)==int(id)):
				entry.root.hide()
				entry.root.queue_free()
				entries.erase(id)
			else:
				var p: Vector2 = view.point(entry.pos)
				entry.root.position=Vector3(p.x+view.pixels(age*0.2),-age*3,p.y+view.pixels(age*0.25))
				entry.pose.rotation.x+=dt*1.8
				entry.pose.rotation.z+=dt*1.1
				entry.root.scale=Vector3.ONE*view.pixels(float(entry.size))/maxf(bounds.size.x,bounds.size.z)*(1.0-age*0.7)
				entry.lamp.visible=false
				for exhaust in entry.exhausts:exhaust.visible=false
		elif not retained.has(id):
			entry.root.hide()
			entry.root.queue_free()
			entries.erase(id)
	bursts=bursts.filter(func(b):return clock-float(b.at)<1.0 and not game._hidden_team(int(b.team)))
	battlecruisers.sync(game, view, dt, clock, alpha)
	thors.sync(game, view, dt, clock, alpha)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _has_actors() else SubViewport.UPDATE_DISABLED

func _has_actors() -> bool:
	return not entries.is_empty() or not battlecruisers.entries.is_empty() or not thors.entries.is_empty()

func has_model(id: int) -> bool:
	return ready_model and ((entries.has(id) and not bool(entries[id].dead)) or battlecruisers.has_model(id) or thors.has_model(id))

func draw_layer(canvas: CanvasItem, view) -> void:
	if not ready_model:return
	if _has_actors():canvas.draw_texture_rect(viewport.get_texture(),Rect2(Vector2.ZERO,view_size),false)
	for burst in bursts:
		var age: float = clock-float(burst.at)
		var p: Vector2 = view.point(burst.pos)
		var fade: float = 1.0-age
		canvas.draw_circle(p,maxf(2,view.pixels(0.25+age*0.5)),Color(1,0.48,0.12,fade*0.45))
		for i in range(4):
			var angle: float = float(i)*TAU/4.0+float(int(burst.id)%7)*0.3
			var at: Vector2 = p+Vector2(cos(angle),sin(angle))*view.pixels(age*0.8)
			canvas.draw_circle(at,maxf(1,view.pixels(0.09*(1-age))),Color(0.7,0.72,0.75,fade))

## Only redraw beams owned by visible 3D craft; old path handles every fallback.
func owns_heal(beam: Dictionary) -> bool:
	return bool(beam.get("healing",false)) and entries.has(beam.source_id) and not entries[beam.source_id].dead

func draw_healing(canvas: CanvasItem, view) -> void:
	var alpha: float = clampf(float(game.accumulator)*float(game.sim.rules.tick_rate),0,1)
	for beam in game.sim.active_beams:
		if not owns_heal(beam):continue
		var entry: Dictionary = entries[int(beam.source_id)]
		var target = game.sim.by_id.get(int(beam.target_id))
		var end: Vector2 = target.prev.lerp(target.pos,alpha) if target!=null else beam.to
		# Screen anchor uses the same interpolated root and hover as the actual model.
		var from := Vector2(float(entry.root.position.x),float(entry.root.position.z))
		var to: Vector2 = view.point(end)
		var tint: Color = Color("85efd9") if int(beam.team)==0 else game.CORAL
		canvas.draw_line(from,to,Color(tint,0.25),maxf(3,view.pixels(0.16)))
		canvas.draw_line(from,to,tint,maxf(1.5,view.pixels(0.06)))
		canvas.draw_circle(from,maxf(1.5,view.pixels(0.08)),Color(tint,0.7))
