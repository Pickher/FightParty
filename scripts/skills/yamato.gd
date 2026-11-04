extends RefCounted

## 大和炮：引导 channel_seconds 秒后对锁定目标打出一发 damage 的单体重炮，冷却 cooldown_seconds 秒。
## 只在冷却好、yamato 射程内有生命+护盾不低于 min_target_hp 的敌方单位时开始引导；
## 优先非结构体，按生命+护盾从高到低，同分取 ID 小的；没有合格单位时才考虑结构体。基地不是目标。
## 引导期间不能移动、不能用普通武器开火——这是它的破绽。目标一经锁定，走出射程也照样命中；
## 目标在引导中死亡则取消，不消耗冷却。出生时冷却就绪。
## 伤害不吃护甲类型加成，经护盾与护甲点数正常结算（与普通命中同一套 queue_hit）。

## 每步在普通行动之前调用。返回 true 表示本步在引导（或刚开炮），单位不再移动、不再普通攻击。
static func step(sim, unit: Dictionary, hits: Dictionary) -> bool:
	var config: Dictionary = sim.catalog[unit.kind].skills.yamato
	var rate: float = float(sim.rules.tick_rate)
	if unit.has("yamato_target"):
		var target = sim.by_id.get(int(unit.yamato_target))
		if target == null:
			unit.erase("yamato_target")
			unit.erase("yamato_fire_tick")
			return false
		if sim.tick < int(unit.yamato_fire_tick):
			return true
		var raw: float = float(config.damage)
		var weapon := {"damage": raw}
		sim.queue_hit(hits, target, raw)
		var amount: float = sim.expected_damage(weapon, target)
		sim.damage_done[int(unit.team)] += amount
		sim.events.append({"type":"attack_hit","id":target.id,"kind":unit.kind,"team":unit.team,"strike":0,"amount":amount})
		sim.events.append({"type":"yamato","from":unit.pos,"to":target.pos,"kind":unit.kind,"team":unit.team})
		unit.erase("yamato_target")
		unit.erase("yamato_fire_tick")
		unit.yamato_ready_tick = sim.tick + ceili(float(config.cooldown_seconds) * rate)
		return true
	if sim.tick < int(unit.get("yamato_ready_tick", 0)):
		return false
	var target := _pick(sim, unit, config)
	if target.is_empty():
		return false
	unit.yamato_target = target.id
	unit.yamato_fire_tick = sim.tick + ceili(float(config.channel_seconds) * rate)
	sim.events.append({"type":"yamato_charge","id":unit.id,"target":target.id,"team":unit.team})
	return true

static func _pick(sim, unit: Dictionary, config: Dictionary) -> Dictionary:
	var reach: float = float(config.range)
	var weapon := {"target_layers": ["ground", "air"], "attacks_structures": true}
	var best: Dictionary = {}
	var best_unit := false
	var best_health := 0.0
	for other in sim._nearby(unit.pos, reach):
		if other.team == unit.team or not sim._can_hit_unit(unit, other, weapon):
			continue
		var health: float = float(other.hp) + float(other.get("shield", 0.0))
		if health < float(config.min_target_hp):
			continue
		var is_unit: bool = not sim.is_structure(other)
		var better: bool = best.is_empty() or (is_unit and not best_unit)
		if not better and is_unit == best_unit:
			better = health > best_health or (is_equal_approx(health, best_health) and int(other.id) < int(best.id))
		if better:
			best = other
			best_unit = is_unit
			best_health = health
	return best

## 引导进度 0～1；不在引导时为 -1。供界面画蓄能光圈。
static func charge(sim, unit: Dictionary) -> float:
	if not unit.has("yamato_target"):
		return -1.0
	var total: float = float(sim.catalog[unit.kind].skills.yamato.channel_seconds) * float(sim.rules.tick_rate)
	return clampf(1.0 - float(int(unit.yamato_fire_tick) - sim.tick) / total, 0.0, 1.0)
