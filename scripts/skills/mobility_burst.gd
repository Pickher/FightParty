extends "res://scripts/skills/skill.gd"
## 通用短时加速：用于原图刺蛇的脱离近战加速，不改变武器射速。
func on_spawn(sim) -> void:
	state.ready_tick=sim.tick+ceili(float(config.get("initial_cooldown",0))*float(sim.rules.tick_rate))

func on_target(ctx: Dictionary) -> void:
	var sim = ctx.sim
	if sim.tick<int(state.get("ready_tick",0)) or sim.tick<int(state.get("until_tick",0)):return
	var nearby := false
	for enemy in sim.nearby_team(owner.pos,float(config.enemy_radius),1-int(owner.team)):
		if float(enemy.hp)>0:nearby=true;break
	if bool(config.get("only_out_of_combat",true)) and nearby:return
	if not pay_energy(sim):return
	state.until_tick=sim.tick+ceili(float(config.duration)*float(sim.rules.tick_rate))
	state.ready_tick=sim.tick+ceili(float(config.cooldown)*float(sim.rules.tick_rate))
	sim.events.append({"type":"skill_used","id":owner.id,"skill":id})

func movement_multiplier(sim) -> float:
	return float(config.speed_multiplier) if sim.tick<int(state.get("until_tick",0)) else 1.0
