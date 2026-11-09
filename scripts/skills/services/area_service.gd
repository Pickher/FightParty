extends RefCounted
const Slow = preload("res://scripts/skills/services/slow_service.gd")
const Status = preload("res://scripts/skills/services/status_service.gd")
static func eligible(sim, stats: Dictionary, config: Dictionary, victim: Dictionary) -> bool:
	return config.get("target_layers",stats.get("target_layers",["ground"])).has(sim.catalog[victim.kind].get("layer","ground")) and (bool(config.get("attacks_structures",false)) or not sim.is_structure(victim))
static func launch(sim, source: Dictionary, location: Vector2, config: Dictionary) -> void:
	var delay_ticks := maxi(1,ceili(float(config.get("delay",0))*float(sim.rules.tick_rate)))
	var area := {"source_id":source.id,"team":source.team,"kind":source.kind,"origin":source.pos,"pos":location,"born":sim.tick,"ready_tick":sim.tick+delay_ticks,"config":config.duplicate(true),"rooted":{},"pulse":0}
	sim.skill_areas.append(area)
	sim.events.append({"type":"area_cast","from":source.pos,"to":location,"team":source.team,"kind":source.kind,"radius":config.radius})
static func advance(sim, dt: float, moves: Dictionary, hits: Dictionary, base_hits: Array) -> void:
	var active: Array = []
	var periodic: Dictionary = {}
	for area in sim.skill_areas:
		if sim.tick<int(area.ready_tick):
			active.append(area)
			continue
		var config: Dictionary = area.config
		var duration: float = float(config.get("duration",0))
		var ticks_total := 1 if bool(config.get("dot_on_impact",false)) else maxi(1,ceili(duration*float(sim.rules.tick_rate)))
		var amount: float = float(config.get("damage",0))/ticks_total
		var stats: Dictionary = sim.catalog[area.kind]
		# 先决定全部单位位置，再在本步末尾按实际位置判定法术范围。
		for victim in sim.units:
			if victim.hp<=0 or not eligible(sim,stats,config,victim):continue
			if victim.team==area.team and not bool(config.get("friendly_fire",false)):continue
			if bool(config.get("immune_same_kind",false)) and victim.kind==area.kind:continue
			var position: Vector2 = moves.get(victim.id,victim.pos)
			if position.distance_squared_to(area.pos)>pow(float(config.radius),2):continue
			if not area.rooted.has(victim.id):
				Status.queue_root(sim,victim,float(config.get("root_seconds",0)))
				area.rooted[victim.id]=true
			if bool(config.get("dot_on_impact",false)):
				Status.queue_dot(sim,victim,{"per_second":sim.raw_damage(config,victim.kind)/maxf(duration,dt),"duration":duration,"max_stacks":1},{"team":area.team,"kind":area.kind})
				if not sim.is_structure(victim):
					Slow.queue_hit(sim,victim,{"speed_multiplier":float(config.get("slow_multiplier",1)),"duration":duration},sim.skill_system.incoming_slows)
			elif duration>0:
				# 同类持续区域不叠加，避免多个风暴在同一步重复扣血。
				var key := "%s:%d:%d" % [str(config.get("effect",area.kind)),int(area.team),int(victim.id)]
				var raw: float = sim.raw_damage(config,victim.kind) / ticks_total
				if not periodic.has(key) or raw > float(periodic[key].amount):
					periodic[key]={"amount":raw,"victim":victim,"team":area.team,"config":config}
			else:
				var raw: float = float(config.structure_damage) if sim.is_structure(victim) and config.has("structure_damage") else sim.raw_damage(config,victim.kind)
				if sim.is_structure(victim) and bool(config.get("structure_ignore_armor",false)):
					sim.queue_hit(hits,victim,raw,false,true)
				elif config.has("damage_type"):
					sim.queue_weapon_hit(hits,victim,config,raw)
				else:
					sim.queue_hit(hits,victim,raw,false,bool(config.get("ignore_armor",true)),float(config.get("shield_bonus",0)))
				sim.damage_done[int(area.team)]+=raw
		if bool(config.get("attacks_base",false)):
			for team in range(2):
				if team==int(area.team) and not bool(config.get("friendly_fire",false)):continue
				if sim.base_pos(team).distance_to(area.pos)<=float(config.radius)+float(sim.rules.layout.base_radius):base_hits[team]+=float(config.get("structure_damage",amount))
		area.pulse=int(area.pulse)+1
		if int(area.pulse)<ticks_total:active.append(area)
		else:sim.events.append({"type":"area_impact","from":area.pos,"to":area.pos,"team":area.team,"kind":area.kind,"radius":config.radius})
	for value in periodic.values():
		if value.config.has("damage_type"):
			sim.queue_weapon_hit(hits,value.victim,value.config,float(value.amount))
		else:
			sim.queue_hit(hits,value.victim,float(value.amount),false,bool(value.config.get("ignore_armor",true)))
		sim.damage_done[int(value.team)]+=float(value.amount)
	sim.skill_areas=active
