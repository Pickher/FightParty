extends RefCounted

## 命中后排队，统一结算时施加，避免先处理的单位提前影响对手本步移动。
static func queue_hit(sim, victim: Dictionary, config: Dictionary, pending: Dictionary) -> void:
	if config.is_empty():
		return
	var effect: Dictionary = pending.get(victim.id,{"multiplier":1.0,"until_tick":0})
	effect.multiplier = minf(float(effect.multiplier),float(config.speed_multiplier))
	# 本步移动已决定，从下一步起完整持续 duration 秒。
	effect.until_tick = maxi(int(effect.until_tick),sim.tick + ceili(float(config.duration) * float(sim.rules.tick_rate)) + 1)
	pending[victim.id] = effect

static func apply(unit: Dictionary, effect: Dictionary, tick: int) -> void:
	# 同名状态不叠乘；取最强减速及最晚到期时间。
	unit.slow_multiplier = minf(speed_multiplier(unit,tick),float(effect.multiplier))
	unit.slow_until_tick = maxi(int(unit.get("slow_until_tick",0)),int(effect.until_tick))

static func speed_multiplier(unit: Dictionary, tick: int) -> float:
	return float(unit.slow_multiplier) if tick < int(unit.get("slow_until_tick",0)) else 1.0
