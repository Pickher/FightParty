extends RefCounted

## 护盾独立于生命：伤害先减 shield_armor（默认 0）再扣护盾，溢出减生命护甲。
## 自然回盾由 Unit.restore 按兵种参数处理；recharge 保留为旧调用的兼容入口。
## 治疗只回生命，不回护盾；忽略护甲的伤害同时跳过两种护甲。
static func initialize(sim, unit: Dictionary) -> void:
	unit["shield"] = float(sim.catalog[unit.kind].get("shield", 0))
	unit["last_hit_tick"] = -1000000

## 结算一次命中：raw 是已含穿甲加成的攻击力（0 表示无伤害，不套用最低伤害）。
## 返回扣除的生命值，护盾变化直接写回 unit。
static func absorb(sim, unit: Dictionary, raw: float, ignore_armor: bool = false) -> float:
	if raw <= 0.0:
		return 0.0
	var stats: Dictionary = sim.catalog[unit.kind]
	var minimum: float = 0.0 if ignore_armor else float(sim.rules.min_damage)
	var armor: float = 0.0 if ignore_armor else float(stats.get("armor", 0))
	if float(unit.get("shield", 0.0)) <= 0.0:
		return maxf(raw - armor, minimum)
	var shield_armor: float = 0.0 if ignore_armor else float(stats.get("shield_armor", 0))
	var to_shield: float = maxf(raw - shield_armor, minimum)
	if to_shield <= float(unit.shield):
		unit.shield = float(unit.shield) - to_shield
		return 0.0
	var leftover: float = to_shield - float(unit.shield)
	unit.shield = 0.0
	return maxf(leftover - armor, 0.0)

## 每步调用：脱战足够久就回盾，不超过上限。
static func recharge(sim, unit: Dictionary, dt: float) -> void:
	var maximum: float = float(sim.catalog[unit.kind].get("shield", 0))
	if maximum <= 0.0 or float(unit.shield) >= maximum:
		return
	var stats: Dictionary = sim.catalog[unit.kind]
	if float(sim.tick - int(unit.last_hit_tick)) / float(sim.rules.tick_rate) >= float(stats.get("shield_regen_delay", sim.rules.shield_regen_delay)):
		unit.shield = minf(maximum, float(unit.shield) + float(stats.get("shield_regen", sim.rules.shield_regen_per_second)) * dt)
