extends "res://scripts/skills/skill.gd"


func _init() -> void:
	priority=40
	view_fields=["stim_until_tick","stim_attack_multiplier","stim_speed_multiplier"]

## 交战时检查当前生命，通过后在本步结算中扣血。
func before_action(ctx: Dictionary) -> void:
	if not ctx.can_act or not ctx.armed or not ctx.weapon_engaged:
		return
	var sim = ctx.sim
	if config.is_empty() or active_at(sim.tick) or sim.tick<int(state.get("stim_ready_tick",0)):
		return
	var max_hp: float = float(sim.catalog[owner.kind].hp)
	var cost := float(config.get("health_cost", max_hp * float(config.get("health_cost_ratio", 0))))
	var health_threshold := cost * maxf(1.0, float(config.get("min_health_cost_multiplier", 1.0)))
	if float(owner.hp) <= health_threshold or not pay_energy(sim):
		return
	ctx.self_costs[owner.id] = cost
	state.stim_ready_tick=sim.tick+ceili(float(config.get("cooldown",0))*float(sim.rules.tick_rate))
	state.stim_until_tick = sim.tick + ceili(float(config.duration) * float(sim.rules.tick_rate))
	state.stim_attack_multiplier = float(config.attack_multiplier)
	state.stim_speed_multiplier = float(config.speed_multiplier)
	sim.events.append({"type":"skill_used","id":owner.id,"skill":"stimulant","health_cost":cost})

func active_at(tick: int) -> bool:
	return tick < int(state.get("stim_until_tick",0))

func current_attack_rate(tick: int) -> float:
	return float(state.stim_attack_multiplier) if active_at(tick) else 1.0

func current_move_multiplier(tick: int) -> float:
	return float(state.stim_speed_multiplier) if active_at(tick) else 1.0
func movement_multiplier(sim) -> float: return current_move_multiplier(sim.tick)
func attack_rate(sim) -> float: return current_attack_rate(sim.tick)
