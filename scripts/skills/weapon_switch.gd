extends RefCounted

## 多武器单位（特工、雷神）：按当前目标选择每秒伤害最高的武器。
## 换到另一把武器需要 switch_seconds，期间不能开火——这是特工的弱点窗口；雷神为 0。
## 索敌用兵种本身的 range / target_layers（各武器的并集），开火距离用当前武器的 range。
## 当前武器合并后的数据按“兵种:序号”缓存在 sim.mode_weapons，避免每次深拷贝。
static func weapon(sim, unit: Dictionary) -> Dictionary:
	var key := "%s:%d" % [unit.kind, int(unit.get("weapon_index", 0))]
	if not sim.mode_weapons.has(key):
		var base: Dictionary = sim.catalog[unit.kind]
		var result: Dictionary = base.duplicate(true)
		result.erase("bonus")
		result.merge(base.skills.weapon_switch.weapons[int(unit.get("weapon_index", 0))], true)
		sim.mode_weapons[key] = result
	return sim.mode_weapons[key]

## 选择对目标最有效的武器；同分保留当前武器。没有目标（攻击基地）时用第一把能打基地的武器。
static func best_index(sim, unit: Dictionary, target: Dictionary) -> int:
	var weapons: Array = sim.catalog[unit.kind].skills.weapon_switch.weapons
	var current: int = int(unit.get("weapon_index", 0))
	if target.is_empty():
		if bool(weapons[current].get("attacks_base", true)):
			return current
		for i in range(weapons.size()):
			if bool(weapons[i].get("attacks_base", true)):
				return i
		return current
	var layer: String = str(sim.catalog[target.kind].get("layer", "ground"))
	var best := current
	var best_score := -1.0
	for i in range(weapons.size()):
		var layers: Array = weapons[i].get("target_layers", sim.catalog[unit.kind].get("target_layers", ["ground"]))
		if not layers.has(layer):
			continue
		var score: float = sim.expected_damage(weapons[i], target) / float(weapons[i].interval)
		if score > best_score + 0.00001 or (is_equal_approx(score, best_score) and i == current):
			best = i
			best_score = score
	return best

## 每步在开火前调用：需要换武器时开始计时并发出事件。返回本步能否开火。
static func prepare(sim, unit: Dictionary, target: Dictionary) -> bool:
	var config: Dictionary = sim.catalog[unit.kind].skills.weapon_switch
	var wanted := best_index(sim, unit, target)
	if wanted != int(unit.get("weapon_index", 0)):
		unit.weapon_index = wanted
		unit.switch_until_tick = sim.tick + ceili(float(config.switch_seconds) * float(sim.rules.tick_rate))
		sim.events.append({"type":"weapon_switch","id":unit.id,"weapon":str(config.weapons[wanted].id)})
	return sim.tick >= int(unit.get("switch_until_tick", 0))
