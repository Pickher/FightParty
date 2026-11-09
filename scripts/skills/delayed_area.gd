extends "res://scripts/skills/skill.gd"
const Areas = preload("res://scripts/skills/services/area_service.gd")

func cast(sim, unit: Dictionary) -> bool:
	var stats: Dictionary = sim.catalog[unit.kind]
	if config.is_empty() or sim.tick<int(state.get("area_ready_tick",0)):return false
	var reach: float = float(config.get("range",stats.range))
	var radius: float = float(config.radius)
	var chosen: Dictionary = {}
	var count := -1
	var distance := INF
	for enemy in sim.nearby_team(unit.pos,reach,1-int(unit.team)):
		if enemy.hp<=0 or not Areas.eligible(sim,stats,config,enemy):continue
		var neighbors := 0
		for other in sim.nearby_team(enemy.pos,radius,1-int(unit.team)):
			if other.hp>0 and Areas.eligible(sim,stats,config,other):neighbors+=1
		var d: float = unit.pos.distance_to(enemy.pos)
		if neighbors>count or (neighbors==count and (d<distance or (is_equal_approx(d,distance) and int(enemy.id)<int(chosen.get("id",2147483647))))):
			chosen=enemy
			count=neighbors
			distance=d
	if chosen.is_empty():
		if not bool(config.get("attacks_base",false)):return false
		var base: Vector2 = sim.base_pos(1-int(unit.team))
		var offset: Vector2 = base-unit.pos
		if offset.length()>reach+float(sim.rules.layout.base_radius):return false
		if not pay_energy(sim): return false
		var spot: Vector2 = base-offset.normalized()*float(sim.rules.layout.base_radius)
		Areas.launch(sim,unit,spot,config)
	else:
		if not pay_energy(sim): return false
		Areas.launch(sim,unit,chosen.pos,config)
	state.area_ready_tick=sim.tick+ceili(float(config.cooldown)*float(sim.rules.tick_rate))
	if float(config.get("channel_seconds",0))>0:
		unit.root_until_tick=maxi(int(unit.get("root_until_tick",0)),sim.tick+ceili(float(config.channel_seconds)*float(sim.rules.tick_rate)))
	return true

func _init() -> void:
	priority=20
	view_fields=["area_ready_tick"]
func before_target(ctx: Dictionary) -> bool:
	cast(ctx.sim,owner)
	return false

func contributes_damage() -> bool: return float(config.get("damage",0))>0
