extends RefCounted

## SC2 式护盾：独立于生命的一层。伤害先扣护盾，护盾不吃护甲点数（穿甲加成照常计算）；
## 打穿护盾的剩余伤害再按生命护甲减免。连续 rules.shield_regen_delay 秒未受伤后按
## rules.shield_regen_per_second 回盾。治疗只回生命，不回护盾。
static func initialize(sim, unit: Dictionary) -> void:
	unit["shield"] = float(sim.catalog[unit.kind].get("shield", 0))
	unit["last_hit_tick"] = -1000000

## 结算一次命中：raw 是已含穿甲加成的攻击力（0 表示无伤害，不套用最低伤害）。
## 返回扣除的生命值，护盾变化直接写回 unit。
static func absorb(sim, unit: Dictionary, raw: float) -> float:
	if raw <= 0.0:
		return 0.0
	var stats: Dictionary = sim.catalog[unit.kind]
	var minimum: float = float(sim.rules.min_damage)
	var armor: float = float(stats.get("armor", 0))
	if float(unit.get("shield", 0.0)) <= 0.0:
		return maxf(raw - armor, minimum)
	var to_shield: float = maxf(raw, minimum)
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
	if sim.tick - int(unit.last_hit_tick) >= int(float(sim.rules.shield_regen_delay) * float(sim.rules.tick_rate)):
		unit.shield = minf(maximum, float(unit.shield) + float(sim.rules.shield_regen_per_second) * dt)
