extends "res://scripts/skills/skill.gd"

func chain(sim, unit: Dictionary, first: Dictionary, hits: Dictionary) -> void:
	var stats: Dictionary = sim._weapon_stats(unit)
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
		sim.queue_weapon_hit(hits,chosen,stats,raw,true)
		sim.damage_done[int(unit.team)]+=raw
		sim.skill_system.hit(sim,unit,chosen,hits)
		sim.events.append({"type":"chain","from":previous.pos,"to":chosen.pos,"kind":unit.kind,"team":unit.team})
		previous=chosen

func after_attack(ctx: Dictionary) -> void:
	if not ctx.target.is_empty():chain(ctx.sim,owner,ctx.target,ctx.hits)
