extends "res://scripts/skills/skill.gd"
## 通用临时护盾护甲；不是额外护盾池，不会替生命护甲减伤。
func on_frame(ctx: Dictionary) -> void:
	var sim = ctx.sim
	if sim.tick<int(state.get("until_tick",0)) or sim.tick<int(state.get("ready_tick",0)):return
	var maximum: float = float(sim.catalog[owner.kind].shield)
	if maximum<=0 or (bool(config.get("requires_damaged_shields",true)) and float(owner.shield)>=maximum):return
	if not pay_energy(sim):return
	state.until_tick=sim.tick+ceili(float(config.duration)*float(sim.rules.tick_rate))
	state.ready_tick=sim.tick+ceili(float(config.cooldown)*float(sim.rules.tick_rate))
	sim.events.append({"type":"skill_used","id":owner.id,"skill":id})

func shield_armor_bonus(sim) -> float:
	return float(config.amount) if sim.tick<int(state.get("until_tick",0)) else 0.0
