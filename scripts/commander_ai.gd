# 中文导读：电脑如何决定购买哪些永久单位。它只做选择，不负责移动、攻击或扣血。
# 电脑只从本方种族的已实装兵种里选；反制不查表，而是按兵种数据现算“每矿每秒伤害”。
# 初学者可以先改 races.json 里各种族的 ai 参数，观察电脑的选择变化。
extends RefCounted
const Catalog = preload("res://scripts/catalog.gd")
const Sim = preload("res://scripts/battle_sim.gd")
var catalog: Dictionary = Catalog.units()
var rules: Dictionary = Catalog.rules()
var rng := RandomNumberGenerator.new()
var race: String = "terran"
# 本种族可选兵种（已实装、非结构体），顺序与 units.json 一致。
var pool: Array = []
var config: Dictionary = {}
# 只用来调用护甲公式，不推进战斗。
var calculator = Sim.new(0, {"structures": false})
# 射程低于此值的单位视为前排，优先放在最靠前的空格；其余放在后方空格。
const FRONT_RANGE := 60.0

## 给随机生成器设置种子。相同种子与调用顺序会产生相同选择，方便复现问题。
func _init(seed_value: int = 42, race_id: String = "terran") -> void:
	rng.seed = seed_value
	race = race_id
	pool = Catalog.race_units(catalog, race)
	config = Catalog.races()[race].get("ai", {})

## 对某个敌方兵种最划算的本族兵种：能打到它的武器里，(单发预估伤害 / 间隔) / 价格最高者。
## 预估伤害含穿甲加成与护甲点数（见 BattleSim.expected_damage）；同分取 pool 中靠前的。
func counter_for(enemy_kind: String) -> String:
	var victim := {"kind": enemy_kind, "shield": float(catalog[enemy_kind].get("shield", 0))}
	var layer: String = str(catalog[enemy_kind].get("layer", "ground"))
	var best := ""
	var best_score := 0.0
	for kind in pool:
		var stats: Dictionary = catalog[kind]
		var weapons: Array = stats.get("skills", {}).get("weapon_switch", {}).get("weapons", [stats])
		var score := 0.0
		for weapon in weapons:
			if not weapon.get("target_layers", stats.get("target_layers", ["ground"])).has(layer) or float(weapon.get("damage", 0)) <= 0.0:
				continue
			score = maxf(score, calculator.expected_damage(weapon, victim) / float(weapon.interval))
		score /= float(stats.cost)
		if score > best_score + 0.000001:
			best = kind
			best_score = score
	return best

## 公平约束：只接收敌方上一波的公开阵容、自己的兵营和矿物，不接收模拟器对象。
## 返回准备购买的 [{kind, cell}]，只使用空格，总价不超过 minerals；仍由 BattleSim.buy() 校验。
func buy_list(last_enemy: Array, roster: Array, minerals: int) -> Array:
	if pool.is_empty():
		return []
	var front: String = str(config.get("front", ""))
	var support: String = str(config.get("support", ""))
	# 辅助兵种（医疗兵）只按下面的规则买一个，不进随机池，避免兵营里堆满不会攻击的单位。
	var choices: Array = pool.filter(func(kind): return kind != support)
	for slot in last_enemy:
		if catalog.has(slot.kind):
			var answer := counter_for(slot.kind)
			if answer != "" and answer != support:
				choices.append(answer)
	var cheapest: String = pool[0]
	for kind in pool:
		if int(catalog[kind].cost) < int(catalog[cheapest].cost):
			cheapest = kind
	var taken: Dictionary = {}
	var fronts := 0
	var has_support := false
	for slot in roster:
		taken[int(slot.cell)] = true
		fronts += 1 if slot.kind == front else 0
		has_support = has_support or slot.kind == support
	var result: Array = []
	var left := minerals
	while true:
		# 兵营里先保证 front_min 个前排；配置了辅助兵种时，兵营总价加可用矿物达到 support_value 就带一个。
		var kind: String = str(choices[rng.randi_range(0, choices.size()-1)])
		if front != "" and fronts < int(config.get("front_min", 0)):
			kind = front
		elif support != "" and not has_support and _roster_value(roster) + minerals >= int(config.get("support_value", 0)):
			kind = support
		if int(catalog[kind].cost) > left:
			kind = cheapest
		if int(catalog[kind].cost) > left:
			break
		var cell := _free_cell(taken, float(catalog[kind].range) < FRONT_RANGE and kind != support)
		if cell < 0:
			break
		taken[cell] = true
		fronts += 1 if kind == front else 0
		has_support = has_support or kind == support
		result.append({"kind":kind,"cell":cell})
		left -= int(catalog[kind].cost)
	return result

## 防御塔策略：对方上一波总价高于自己兵营（落后）且还能建塔时，买得起就建（"build"），
## 买不起就本轮不买兵、攒矿（"save"）；其他情况返回空字符串。
func tower_plan(last_enemy: Array, roster: Array, minerals: int, builds: int) -> String:
	if builds >= int(rules.tower_max_builds) or _roster_value(last_enemy) <= _roster_value(roster):
		return ""
	return "build" if minerals >= int(catalog.tower.cost) else "save"

func wants_tower(last_enemy: Array, roster: Array, minerals: int, builds: int) -> bool:
	return tower_plan(last_enemy, roster, minerals, builds) == "build"

## 从空兵营开始的一整份阵容，供测试与旧接口使用。
func choose(last_enemy: Array, budget: int) -> Array:
	return buy_list(last_enemy, [], budget)

func _roster_value(roster: Array) -> int:
	var total := 0
	for slot in roster:
		if catalog.has(slot.kind):
			total += int(catalog[slot.kind].cost)
	return total

## 前排单位从最右（最靠前）一列找空格，后排单位从最左一列找；同列内从中间行向两侧。
func _free_cell(taken: Dictionary, front: bool) -> int:
	var columns := int(rules.columns)
	var rows := int(rules.rows)
	var row_order: Array = []
	for offset in range(rows):
		var row: int = (rows - 1) / 2 + (offset + 1) / 2 * (1 if offset % 2 == 1 else -1)
		row_order.append(row)
	for step in range(columns):
		var col: int = columns - 1 - step if front else step
		for row in row_order:
			var cell: int = row * columns + col
			if not taken.has(cell):
				return cell
	return -1
