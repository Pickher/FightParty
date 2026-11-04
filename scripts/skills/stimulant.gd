extends RefCounted

## 敌人进入射程且允许攻击时自动使用；只记自身扣血，最后与本步伤害统一结算。
static func activate(sim, unit: Dictionary, costs: Dictionary) -> void:
	var stats: Dictionary = sim.catalog[unit.kind]
	var config: Dictionary = stats.get("skills",{}).get("stimulant",{})
	if config.is_empty() or active(unit,sim.tick):
		return
	var cost: float = float(stats.hp) * float(config.health_cost_ratio)
	if float(unit.hp) <= cost:
		return
	costs[unit.id] = cost
	unit.stim_until_tick = sim.tick + ceili(float(config.duration) * float(sim.rules.tick_rate))
	unit.stim_attack_multiplier = float(config.attack_multiplier)
	unit.stim_speed_multiplier = float(config.speed_multiplier)
	sim.events.append({"type":"skill_used","id":unit.id,"skill":"stimulant","health_cost":cost})

static func active(unit: Dictionary, tick: int) -> bool:
	return tick < int(unit.get("stim_until_tick",0))

static func attack_rate(unit: Dictionary, tick: int) -> float:
	return float(unit.stim_attack_multiplier) if active(unit,tick) else 1.0

static func speed_multiplier(unit: Dictionary, tick: int) -> float:
	return float(unit.stim_speed_multiplier) if active(unit,tick) else 1.0
