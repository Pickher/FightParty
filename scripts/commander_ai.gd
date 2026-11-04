# 中文导读：电脑如何决定购买哪些永久单位。它只做选择，不负责移动、攻击或扣血。
# 初学者可以先改 counters 的克制映射或 choices 的权重，观察电脑的选择变化。
extends RefCounted
const Catalog = preload("res://scripts/catalog.gd")
var catalog: Dictionary = Catalog.units()
var rules: Dictionary = Catalog.rules()
var rng := RandomNumberGenerator.new()
# 键是观察到的敌方兵种，值是准备购买的反制兵种；ID 必须存在于 units.json。
const COUNTERS := {"guard":"breaker","rifle":"mortar","breaker":"swarm","swarm":"mortar","mortar":"swarm","sniper":"swarm","medic":"sniper","piercer":"mortar","colossus":"breaker","marauder":"breaker","liberator":"rifle"}
# 射程低于此值的单位视为前排，优先放在最靠前的空格；其余放在后方空格。
const FRONT_RANGE := 60.0

## 给随机生成器设置种子。相同种子与调用顺序会产生相同选择，方便复现问题。
func _init(seed_value: int = 42) -> void:
	rng.seed = seed_value

## 公平约束：只接收敌方上一波的公开阵容、自己的兵营和矿物，不接收模拟器对象。
## 返回准备购买的 [{kind, cell}]，只使用空格，总价不超过 minerals；仍由 BattleSim.buy() 校验。
func buy_list(last_enemy: Array, roster: Array, minerals: int) -> Array:
	var choices: Array = ["rifle","rifle","swarm","piercer","colossus","marauder","liberator"]
	for slot in last_enemy:
		choices.append(COUNTERS.get(slot.kind,"rifle"))
	var taken: Dictionary = {}
	var guards := 0
	var has_medic := false
	for slot in roster:
		taken[int(slot.cell)] = true
		guards += 1 if slot.kind == "guard" else 0
		has_medic = has_medic or slot.kind == "medic"
	var result: Array = []
	var left := minerals
	while true:
		# 兵营里先保证两个盾卫；兵营总价加可用矿物达到 700 时带一名医疗兵，其余从抽取池选择。
		var kind: String = str(choices[rng.randi_range(0, choices.size()-1)])
		if guards < 2:
			kind = "guard"
		elif not has_medic and _roster_value(roster) + minerals >= 700:
			kind = "medic"
		if int(catalog[kind].cost) > left:
			kind = "swarm"
		if int(catalog[kind].cost) > left:
			break
		var cell := _free_cell(taken, float(catalog[kind].range) < FRONT_RANGE and kind != "medic")
		if cell < 0:
			break
		taken[cell] = true
		guards += 1 if kind == "guard" else 0
		has_medic = has_medic or kind == "medic"
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
