extends "res://scripts/skills/skill.gd"


func _init() -> void:
	priority=40
	view_fields=["stim_until_tick","stim_attack_multiplier","stim_speed_multiplier"]

## 敌人进入射程且允许攻击时自动使用；只记自身扣血，最后与本步伤害统一结算。
func activate(sim, unit: Dictionary, costs: Dictionary) -> void:
	var stats: Dictionary = sim.catalog[unit.kind]
	if config.is_empty() or active_at(sim.tick):
		return
	var cost: float = float(stats.hp) * float(config.health_cost_ratio)
	if float(unit.hp) <= cost:
		return
	if not pay_energy(sim): return
	costs[unit.id] = cost
	state.stim_until_tick = sim.tick + ceili(float(config.duration) * float(sim.rules.tick_rate))
	state.stim_attack_multiplier = float(config.attack_multiplier)
	state.stim_speed_multiplier = float(config.speed_multiplier)
	sim.events.append({"type":"skill_used","id":unit.id,"skill":"stimulant","health_cost":cost})

func active_at(tick: int) -> bool:
	return tick < int(state.get("stim_until_tick",0))

func current_attack_rate(tick: int) -> float:
	return float(state.stim_attack_multiplier) if active_at(tick) else 1.0

func current_move_multiplier(tick: int) -> float:
	return float(state.stim_speed_multiplier) if active_at(tick) else 1.0
func before_action(ctx: Dictionary) -> void:
	if ctx.can_act and not ctx.target.is_empty() and ctx.distance<=ctx.reach:activate(ctx.sim,owner,ctx.self_costs)
func movement_multiplier(sim) -> float: return current_move_multiplier(sim.tick)
func attack_rate(sim) -> float: return current_attack_rate(sim.tick)
