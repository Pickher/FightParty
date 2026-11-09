extends Node2D
const Yamato = preload("res://scripts/skills/yamato.gd")
const UnitArt = preload("res://scripts/unit_art.gd")
## 独立的战场画布由 SubViewport 裁剪；缩放只影响显示，不改模拟单位。
var game
const AREA := Vector2(1300,352)

func _process(_delta: float) -> void:
	queue_redraw()

func point(pos: Vector2) -> Vector2:
	var view: Rect2 = game._camera_rect()
	return (pos-view.position)*AREA/view.size

func pixels(value: float) -> float:
	return value*AREA.x/game._camera_rect().size.x

func label(pos: Vector2, content: String, color: Color, font_size: int = 12) -> void:
	draw_string(game.FONT,pos,content,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func bar(pos: Vector2, width: float, value: float, color: Color) -> void:
	draw_rect(Rect2(pos,Vector2(width,3)),Color("263245"))
	draw_rect(Rect2(pos,Vector2(width*clampf(value,0,1),3)),color)

func ring(center: Vector2, reach: float, color: Color) -> void:
	draw_arc(point(center),pixels(reach),0,TAU,48,color,1)

func _draw() -> void:
	if game==null:return
	var sim = game.sim
	# 大和舰原图以3格模型标定，主体、炮口、残骸统一随模型尺寸缩放。
	var bc_body: Array = sim.catalog["battlecruiser"].get("size",[3.0,3.0])
	var bc_cell: float = pixels(maxf(float(bc_body[0]),float(bc_body[1]))/3.0)
	var view: Rect2 = game._camera_rect()
	draw_rect(Rect2(Vector2.ZERO,AREA),Color("0d1c2b"))
	var spacing: float = 1.0 if pixels(1.0)>=12.0 else 5.0
	for x in range(floori(view.position.x/spacing),ceili(view.end.x/spacing)+1):
		var px: float = point(Vector2(x*spacing,0)).x
		draw_line(Vector2(px,0),Vector2(px,AREA.y),Color("172a3a"))
	for y in range(floori(view.position.y/spacing),ceili(view.end.y/spacing)+1):
		var py: float = point(Vector2(0,y*spacing)).y
		draw_line(Vector2(0,py),Vector2(AREA.x,py),Color("172a3a"))
	draw_rect(Rect2(point(Vector2.ZERO),Vector2(pixels(sim.rules.world_width),pixels(sim.rules.world_height))),Color("3c4d60"),false,1)
	var middle_x: float = point(Vector2(float(sim.rules.world_width)*0.5,0)).x
	draw_line(Vector2(middle_x,0),Vector2(middle_x,AREA.y),Color("526579"),1)
	for team in range(2):
		var base: Vector2 = sim.base_pos(team)
		var p := point(base)
		var color: Color = game.MINT if team==0 else game.CORAL
		var r := pixels(float(sim.rules.layout.base_radius))
		if view.grow(float(sim.rules.layout.base_radius)).has_point(base):
			draw_circle(p,r,Color(color,0.15))
			draw_arc(p,r,0,TAU,32,color,2)
			label(p+Vector2(-14,-r-4),"基地",color)
		var spawn_point := Vector2(sim.mirror_x(team,float(sim.rules.layout.spawn_x)),float(sim.rules.layout.spawn_y))
		if view.grow(1.0).has_point(spawn_point):
			var spawn_screen := point(spawn_point)
			draw_arc(spawn_screen,pixels(0.4),0,TAU,16,Color(color,0.55),1)
			label(spawn_screen+Vector2(-14,pixels(0.4)+12),"出兵",Color(color,0.7),10)
	for area in sim.skill_areas:
		var config: Dictionary = area.config
		var tint: Color = game.CORAL if game._hidden_team(int(area.team)) else Color(sim.catalog[area.kind].color)
		var pending: bool = sim.tick<int(area.ready_tick)
		ring(area.pos,float(config.radius),Color(tint,0.4 if pending else 0.9))
		if not pending:draw_circle(point(area.pos),pixels(float(config.radius)),Color(tint,0.12))
		if pending and bool(config.get("projectile",false)):
			var progress: float = clampf(float(sim.tick-int(area.born))/maxf(1.0,float(int(area.ready_tick)-int(area.born))),0,1)
			draw_circle(point(area.origin.lerp(area.pos,progress)),maxf(2,pixels(0.35)),tint)
	for unit in sim.units:
		if not game._hidden_team(int(unit.team)) and unit.has("siege_state") and sim.catalog[unit.kind].get("skills",{}).has("defender_zone") and unit.siege_state!="mobile":
			var config: Dictionary = sim.catalog[unit.kind].skills.defender_zone
			var sector := PackedVector2Array([point(unit.pos)])
			var axis: float = 0.0 if unit.team==0 else PI
			var half_angle: float = deg_to_rad(float(config.angle_degrees)*0.5)
			for i in range(25):
				var a: float = axis-half_angle+2.0*half_angle*i/24.0
				sector.append(point(unit.pos+Vector2(cos(a),sin(a))*float(config.weapon.range)))
			var color: Color = game.MINT if unit.team==0 else game.CORAL
			draw_colored_polygon(sector,Color(color,0.08))
			sector.append(sector[0])
			draw_polyline(sector,Color(color,0.6),1.5)
	for effect in game.effects:
		var color: Color = game.MINT if effect.team==0 else game.CORAL
		var a := point(effect.from)
		if effect.has("muzzle"):
			# 大和舰：激光从炮管、大和炮从圆形炮口画起（精灵上的位置）。
			a += game.bc_visual.muzzle_offset(str(effect.muzzle),bool(effect.left),bc_cell)
		var b := point(effect.to)
		if effect.type=="area_impact":
			ring(effect.to,float(effect.radius),Color(color,clampf(float(effect.ttl)/0.16,0,1)))
			continue
		if effect.type=="yamato":
			var fade: float = clampf(float(effect.ttl)/0.5,0,1)
			draw_line(a,b,Color(Color("ffb347"),fade),maxf(2,pixels(0.35)))
			draw_line(a,b,Color(game.INK,fade),1)
			draw_circle(b,maxf(2,pixels(0.5))*fade,Color(Color("ffb347"),fade*0.4))
			continue
		if effect.type=="line_attack":
			color=Color(game.sim.catalog[effect.kind].color) if not game._hidden_team(int(effect.team)) else game.CORAL
			color.a=clampf(float(effect.ttl)/0.24,0,1)
			var width: float = float(effect.get("half_width",0.3))*2.0 if str(effect.get("effect",""))=="flame" else 0.15
			draw_line(a,b,color,maxf(1,pixels(width)))
		else:
			color.a=clampf(float(effect.ttl)/0.16,0,1)
			if effect.has("muzzle"):color=Color(Color("ffb347"),color.a)
			draw_line(a,b,color,1.5)
			if float(effect.get("splash",0))>0:
				ring(effect.to,float(effect.splash),Color(color,color.a*0.5))
	var alpha: float = clampf(float(game.accumulator)*float(sim.rules.tick_rate),0,1)
	var rifle_body: Array = sim.catalog["rifle"].get("size",[0.8,0.8])
	# 图集含透明留白，整帧约为主体三倍；跟随世界尺寸和相机缩放。
	var rifle_frame_world: float = maxf(float(rifle_body[0]),float(rifle_body[1]))*3.0
	for corpse in game.rifle_visual.corpses:
		if view.grow(rifle_frame_world*2.0).has_point(corpse.pos):
			game.rifle_visual.draw_corpse(self,point(corpse.pos),corpse,pixels(rifle_frame_world))
	for corpse in game.bc_visual.corpses:
		if view.grow(4.0).has_point(corpse.pos):
			game.bc_visual.draw_corpse(self,point(corpse.pos),corpse,bc_cell)
	for unit in sim.units:
		var position: Vector2 = unit.prev.lerp(unit.pos,alpha)
		var stats: Dictionary = sim.catalog[unit.kind]
		var body: Array = stats.get("size",[1.0,1.0])
		if not view.grow(maxf(float(body[0]),float(body[1]))*(3.0 if unit.kind=="rifle" else 1.0)).has_point(position):continue
		var p := point(position)
		var dimensions := Vector2(pixels(float(body[0])),pixels(float(body[1])))
		var color: Color = game.MINT if unit.team==0 else game.CORAL
		var hidden: bool = game._hidden_team(int(unit.team))
		var tint: Color = Color("4a5a6c") if hidden else Color(stats.color)
		# 模型的边界与配置的宽高一致；全图不额外放大，近景下才显示细节。
		if sim.is_structure(unit):
			draw_rect(Rect2(p-dimensions*0.5,dimensions),Color(color,0.3))
			draw_rect(Rect2(p-dimensions*0.5,dimensions),color,false,1)
			UnitArt.structure(self,p,unit.kind,game.sim.visible_race(0,int(unit.team)),minf(dimensions.x,dimensions.y)/3.0,game._race_color(game.sim.visible_race(0,int(unit.team))))
			if game.camera_zoom>=2:label(p+Vector2(-16,-dimensions.y*0.5-5),str(stats.name),color)
		else:
			draw_rect(Rect2(p-dimensions*.5,dimensions),Color(tint,0.14))
			if hidden:draw_rect(Rect2(p-dimensions*.5,dimensions),tint)
			elif unit.kind == "rifle":
				draw_arc(p,maxf(dimensions.x,dimensions.y)*0.55,0,TAU,16,Color(color,0.8),1)
				game.rifle_visual.draw_unit(self,p,unit,pixels(rifle_frame_world))
			elif unit.kind == "battlecruiser":
				# 精灵按模型尺寸从原3格标定缩放，避免只改占地而舰体不变。
				draw_arc(p,maxf(dimensions.x,dimensions.y)*0.55,0,TAU,24,Color(color,0.8),1)
				game.bc_visual.draw_unit(self,p,unit,bc_cell)
			else:UnitArt.draw(self,p,unit.kind,tint,minf(dimensions.x,dimensions.y)/3.0,str(stats.get("symbol","?")))

		if game.camera_zoom<3:continue
		if hidden:
			label(p+Vector2(-3,4),"?",color)
			continue
		if sim.tick<int(unit.get("barrier_until_tick",0)) and float(unit.get("barrier_hp",0))>0:
			draw_arc(p,maxf(4,dimensions.x*.7),0,TAU,20,Color("b9a2ff"),2)
		if sim.tick<int(unit.get("root_until_tick",0)):
			draw_line(p-Vector2(dimensions.x*.5,0),p+Vector2(dimensions.x*.5,0),Color("9cba51"),2)
		if stats.get("skills",{}).has("aura") and sim.tick<int(unit.get("aura_until_tick",0)):
			ring(position,float(stats.skills.aura.radius),Color(game.SHIELD,0.25))
		if stats.get("skills",{}).has("yamato"):
			var charge: float = Yamato.charge(sim,unit)
			if charge>=0:
				draw_arc(p,maxf(4,dimensions.x*.6),-PI*.5,-PI*.5+TAU*charge,24,Color("ffb347"),2)
				var locked = sim.by_id.get(int(unit.yamato_target))
				if locked!=null:draw_line(p,point(locked.pos),Color(Color("ffb347"),0.35),1)
		bar(p+Vector2(-dimensions.x*.5,-dimensions.y*.5-5),dimensions.x,float(unit.hp)/float(stats.hp),color)
		if float(stats.get("shield",0))>0:
			bar(p+Vector2(-dimensions.x*.5,-dimensions.y*.5-9),dimensions.x,float(unit.shield)/float(stats.shield),game.SHIELD)
		if float(stats.get("energy",0))>0:
			var energy_y: float = -13.0 if float(stats.shield)>0 else -9.0
			bar(p+Vector2(-dimensions.x*.5,-dimensions.y*.5+energy_y),dimensions.x,float(unit.energy)/float(stats.energy),Color("ad86ef"))
		if sim.tick<int(unit.get("stim_until_tick",0)):
			draw_rect(Rect2(p-dimensions*.5,dimensions),Color("ffbe65"),false,1.5)
		if sim.tick<int(unit.get("slow_until_tick",0)):
			draw_line(p+Vector2(-dimensions.x*.5,dimensions.y*.5+2),p+Vector2(dimensions.x*.5,dimensions.y*.5+2),Color("77cfff"),2)
		if unit.has("siege_state") and unit.siege_state!="mobile":
			var skills: Dictionary = stats.skills
			var config: Dictionary = skills.defender_zone if skills.has("defender_zone") else skills.deployment
			var state: String = unit.siege_state
			if state=="deploying" or state=="packing":
				var duration: float = float(config.deploy_seconds) if state=="deploying" else float(config.pack_seconds)
				var progress: float = 1.0-float(unit.siege_until_tick-sim.tick)/(duration*float(sim.rules.tick_rate))
				bar(p+Vector2(-dimensions.x*.5,dimensions.y*.5+5),dimensions.x,progress,Color("f5b66e"))
			elif state=="deployed":
				draw_rect(Rect2(p-dimensions*.5-Vector2.ONE,dimensions+Vector2.ONE*2),color,false,1)
		if unit.has("weapon_index") and game.camera_zoom>=6:
			var config: Dictionary = stats.skills.weapon_switch
			label(p+Vector2(-15,dimensions.y*.5+16),str(config.weapons[int(unit.weapon_index)].label),color,10)
