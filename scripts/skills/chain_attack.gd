extends "res://scripts/skills/skill.gd"

func chain(sim, unit: Dictionary, first: Dictionary, hits: Dictionary, weapon: Dictionary = {}, effects: Dictionary = {}, multiplier: float = 1.0) -> void:
	var stats: Dictionary = sim._weapon_stats(unit) if weapon.is_empty() else weapon
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
		var factor: float = multiplier*pow(float(config.falloff),hop+1)
		var raw: float = sim.raw_damage(stats,chosen.kind)*factor
		sim.queue_weapon_hit(hits,chosen,stats,raw,true,factor)
		sim.damage_done[int(unit.team)]+=raw
		var extras := effects.duplicate(true)
		extras.erase("chain_attack")
		if not extras.is_empty():sim.skill_system.wave_hit(sim,{"source_id":unit.id,"kind":unit.kind,"team":unit.team,"source":unit.pos,"weapon":stats,"impact_skills":extras,"damage_multiplier":factor},chosen,hits,sim.skill_system.incoming_slows)
		sim.events.append({"type":"chain","from":previous.pos,"to":chosen.pos,"kind":unit.kind,"team":unit.team})
		previous=chosen

func _init() -> void: hit_effect=true
func on_hit(ctx: Dictionary) -> void:
	chain(ctx.sim,owner,ctx.victim,ctx.hits,ctx.get("weapon",{}),ctx.get("impact_skills",{}),float(ctx.get("damage_multiplier",1)))
