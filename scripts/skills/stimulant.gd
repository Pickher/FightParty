extends "res://scripts/skills/skill.gd"


func _init() -> void:
	priority=40
	view_fields=["stim_until_tick","stim_attack_multiplier","stim_speed_multiplier"]

## 返回应由使用者支付的生命值。普通单位在本步末结算，驻军从各自的生命池支付。
func activate(sim, max_hp: float) -> float:
	if config.is_empty() or active_at(sim.tick) or sim.tick<int(state.get("stim_ready_tick",0)):
		return -1.0
	var cost := float(config.get("health_cost", max_hp * float(config.get("health_cost_ratio", 0))))
	if float(owner.hp) <= cost or not pay_energy(sim):
		return -1.0
	state.stim_ready_tick=sim.tick+ceili(float(config.get("cooldown",0))*float(sim.rules.tick_rate))
	state.stim_until_tick = sim.tick + ceili(float(config.duration) * float(sim.rules.tick_rate))
	state.stim_attack_multiplier = float(config.attack_multiplier)
	state.stim_speed_multiplier = float(config.speed_multiplier)
	var event := {"type":"skill_used","id":owner.id,"skill":"stimulant","health_cost":cost}
	if owner.has("mount_index"):
		event.mount = owner.mount_index
	sim.events.append(event)
	return cost

func active_at(tick: int) -> bool:
	return tick < int(state.get("stim_until_tick",0))

func current_attack_rate(tick: int) -> float:
	return float(state.stim_attack_multiplier) if active_at(tick) else 1.0

func current_move_multiplier(tick: int) -> float:
	return float(state.stim_speed_multiplier) if active_at(tick) else 1.0
func before_action(ctx: Dictionary) -> void:
	if ctx.can_act and not ctx.target.is_empty() and ctx.distance <= ctx.reach:
		var cost := activate(ctx.sim, float(ctx.sim.catalog[owner.kind].hp))
		if cost >= 0:
			ctx.self_costs[owner.id] = cost
func movement_multiplier(sim) -> float: return current_move_multiplier(sim.tick)
func attack_rate(sim) -> float: return current_attack_rate(sim.tick)
