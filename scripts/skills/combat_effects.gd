extends RefCounted
const Status = preload("res://scripts/skills/status_effects.gd")
const Summoning = preload("res://scripts/skills/summoning.gd")
const Areas = preload("res://scripts/skills/area_effects.gd")

static func damage_multiplier(sim, unit: Dictionary, target: Dictionary) -> float:
	var config: Dictionary = sim.catalog[unit.kind].get("skills",{}).get("ramp_damage",{})
	if config.is_empty():return 1.0
	if int(unit.get("ramp_target",0))!=int(target.id) or sim.tick-int(unit.get("ramp_last_tick",0))>ceili(float(sim.catalog[unit.kind].interval)*float(sim.rules.tick_rate))+2:
		unit.ramp_target=target.id
		unit.ramp_start_tick=sim.tick
	unit.ramp_last_tick=sim.tick
	return minf(float(config.max_multiplier),1.0+float(config.per_second)*float(sim.tick-int(unit.ramp_start_tick))/float(sim.rules.tick_rate))

static func on_hit(sim, unit: Dictionary, victim: Dictionary) -> void:
	Status.queue_dot(sim,victim,sim.catalog[unit.kind].get("skills",{}).get("dot",{}),unit)

static func chain(sim, unit: Dictionary, first: Dictionary, hits: Dictionary) -> void:
	var stats: Dictionary = sim.catalog[unit.kind]
	var config: Dictionary = stats.get("skills",{}).get("chain_attack",{})
	if config.is_empty():return
	var struck: Dictionary = {first.id:true}
	var previous := first
	for hop in range(int(config.bounces)):
		var chosen: Dictionary = {}
		var distance := INF
		for victim in sim.nearby_team(previous.pos,float(config.radius),1-int(unit.team)):
			if struck.has(victim.id) or victim.hp<=0 or not sim._can_hit_unit(unit,victim,stats):continue
			var candidate: float = previous.pos.distance_to(victim.pos)
			if candidate<distance or (is_equal_approx(candidate,distance) and int(victim.id)<int(chosen.get("id",2147483647))):
				chosen=victim
				distance=candidate
		if chosen.is_empty():break
		struck[chosen.id]=true
		var raw: float = sim.raw_damage(stats,chosen.kind)*pow(float(config.falloff),hop+1)
		sim.queue_hit(hits,chosen,raw,true)
		sim.damage_done[int(unit.team)]+=raw
		on_hit(sim,unit,chosen)
		sim.events.append({"type":"chain","from":previous.pos,"to":chosen.pos,"kind":unit.kind,"team":unit.team})
		previous=chosen

static func suicide(sim, unit: Dictionary, target: Dictionary, hits: Dictionary, base_hits: Array) -> bool:
	var stats: Dictionary = sim.catalog[unit.kind]
	if not stats.get("skills",{}).has("suicide"):return false
	var goal: Vector2 = sim.base_pos(1-int(unit.team)) if target.is_empty() else target.pos
	var trigger: float = float(stats.range)+(float(sim.rules.layout.base_radius) if target.is_empty() else 0)
	if unit.pos.distance_to(goal)>trigger:return false
	for victim in sim.nearby_team(unit.pos,float(stats.splash),1-int(unit.team)):
		if not sim._can_hit_unit(unit,victim,stats):continue
		var raw: float = sim.raw_damage(stats,victim.kind)
		sim.queue_hit(hits,victim,raw)
		sim.damage_done[int(unit.team)]+=sim.expected_damage(stats,victim)
	if unit.pos.distance_to(sim.base_pos(1-int(unit.team)))<=float(stats.splash)+float(sim.rules.layout.base_radius):
		base_hits[1-int(unit.team)]+=float(stats.damage)
	sim.self_destruct[unit.id]=true
	sim.events.append({"type":"area_impact","from":unit.pos,"to":unit.pos,"team":unit.team,"kind":unit.kind,"radius":stats.splash})
	return true

static func death(sim, unit: Dictionary) -> void:
	var skills: Dictionary = sim.catalog[unit.kind].get("skills",{})
	var config: Dictionary = skills.get("on_death",{})
	if skills.has("suicide") and not sim.self_destruct.has(unit.id):
		var stats: Dictionary = sim.catalog[unit.kind]
		Areas.launch(sim,unit,unit.pos,{"damage":stats.damage,"bonus":stats.get("bonus",{}),"radius":stats.splash,"effect":"baneling","target_layers":["ground"],"attacks_structures":true,"attacks_base":true,"ignore_armor":false})
	if config.has("summon"):Summoning.queue(sim,unit,str(config.summon),int(config.count),unit.pos,{"lifetime":15})
	if config.has("area"):
		var area: Dictionary = config.area.duplicate(true)
		if area.has("dot"):
			area.damage=float(area.dot.per_second)*float(area.dot.duration)
			area.duration=area.dot.duration
		area.delay=0
		Areas.launch(sim,unit,unit.pos,area)
	# 腐族尸体复生仅处理非召唤物，避免召唤物死亡无限递归。
	if bool(unit.get("summoned",false)):return
	for raiser in sim.units:
		if sim.self_destruct.has(raiser.id) or float(raiser.hp)<=0:continue
		var raise_config: Dictionary = sim.catalog[raiser.kind].get("skills",{}).get("corpse_raise",{})
		if raise_config.is_empty() or unit.pos.distance_to(raiser.pos)>float(raise_config.radius):continue
		var roll: int = posmod(int(unit.id)*1103515245+int(raiser.id)*12345+sim.tick,10000)
		if roll<int(float(raise_config.chance)*10000):
			Summoning.queue(sim,raiser,str(raise_config.summon),1,unit.pos,raise_config)
