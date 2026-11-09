extends "res://scripts/skills/skill.gd"

func _init() -> void:priority=45
func active(sim) -> bool:return sim.tick<int(state.get("buff_until_tick",0))
func on_target(ctx: Dictionary) -> void:
	var sim = ctx.sim
	if active(sim) or sim.tick<int(state.get("buff_ready_tick",0)) or ctx.target.is_empty():return
	if str(sim.catalog[ctx.target.kind].armor_type)!=str(config.get("required_armor","heavy")):return
	if owner.pos.distance_to(ctx.target.pos)>float(sim._weapon_stats(owner).range):return
	if not pay_energy(sim):return
	state.buff_until_tick=sim.tick+ceili(float(config.duration)*float(sim.rules.tick_rate))
	state.buff_ready_tick=sim.tick+ceili(float(config.cooldown)*float(sim.rules.tick_rate))
	sim.events.append({"type":"skill_used","id":owner.id,"skill":"weapon_buff"})
func modify_weapon(sim, weapon: Dictionary) -> Dictionary:
	if not active(sim):return weapon
	var result: Dictionary = weapon.duplicate(true)
	for armor in config.get("bonus",{}):result.bonus[armor]=float(result.bonus.get(armor,0))+float(config.bonus[armor])
	return result
func movement_multiplier(sim) -> float:return float(config.get("speed_multiplier",1)) if active(sim) else 1.0
