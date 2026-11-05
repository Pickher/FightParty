extends "res://scripts/skills/skill.gd"

func _init() -> void:
	priority=10
	view_fields=["aura_until_tick","aura_ready_tick"]
func on_frame(ctx: Dictionary) -> void:
	prepare(ctx.sim,owner)
	if bool(config.get("requires_combat", false)) and ctx.sim.tick >= int(state.get("aura_until_tick", 0)): return
	if float(config.get("enemy_dot_per_second",0))<=0:return
	for enemy in ctx.sim.nearby_team(owner.pos,float(config.radius),1-int(owner.team)):
		if ctx.sim.is_structure(enemy):continue
		var key := "%s:%d:%d" % [str(owner.kind),int(owner.team),int(enemy.id)]
		ctx.aura_damage[key]={"victim":enemy,"team":owner.team,"rate":config.enemy_dot_per_second}
func prepare(sim, unit: Dictionary) -> void:
	if bool(config.get("requires_combat",false)):
		if sim.tick>=int(state.get("aura_until_tick",0)):
			if sim.tick<int(state.get("aura_ready_tick",0)):return
			var threat := false
			for enemy in sim.nearby_team(unit.pos,float(config.radius)+3,1-int(unit.team)):
				if enemy.hp>0:
					threat=true
					break
			if not threat:return
			if not pay_energy(sim): return
			state.aura_until_tick=sim.tick+ceili(float(config.duration)*float(sim.rules.tick_rate))
			state.aura_ready_tick=sim.tick+ceili(float(config.cooldown)*float(sim.rules.tick_rate))
	for ally in sim.nearby_team(unit.pos,float(config.radius),int(unit.team)):
		if sim.is_structure(ally):continue
		var value: Dictionary = sim.aura_modifiers.get(ally.id,{"reduction":0.0,"attack_rate":1.0})
		value.reduction=maxf(float(value.reduction),float(config.get("ranged_damage_reduction",0)))
		value.attack_rate=maxf(float(value.attack_rate),float(config.get("ally_attack_rate",1)))
		sim.aura_modifiers[ally.id]=value

func contributes_damage() -> bool: return float(config.get("enemy_dot_per_second",0))>0
