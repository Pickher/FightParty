# 中文导读：电脑如何选择下一波阵容。它只做选择，不负责移动、攻击或扣血。
# 初学者可以先改 counters 的克制映射或 choices 的权重，观察电脑的选择变化。
extends RefCounted
const Catalog = preload("res://scripts/catalog.gd")
var catalog: Dictionary = Catalog.units()
var rng := RandomNumberGenerator.new()

## 给随机生成器设置种子。相同种子与调用顺序会产生相同选择，方便复现问题。
func _init(seed_value: int = 42) -> void:
	rng.seed = seed_value

## 公平约束：这里只接收已公开信息，不接收模拟器对象，更不能偷看玩家待出兵阵容。
## 输入：敌方上一波的公开阵容，以及本波预算；输出：准备提交的阵容数组。
## 最终仍由 BattleSim.submit_formation() 校验，AI 不能绕开玩家同样遵守的规则。
func choose(last_enemy: Array, budget: int) -> Array:
	# 键是观察到的敌方兵种，值是准备购买的反制兵种；ID 必须存在于 units.json。
	var counters := {"guard":"breaker","rifle":"mortar","breaker":"swarm","swarm":"mortar","mortar":"swarm","sniper":"swarm","medic":"sniper","piercer":"mortar","colossus":"breaker","marauder":"breaker","liberator":"rifle"}
	# 抽取池里同一兵种出现越多，选中的机会越大。这里给步枪兵较高的基础权重。
	var choices: Array = ["rifle","rifle","swarm","piercer","colossus","marauder","liberator"]
	for slot in last_enemy:
		choices.append(counters.get(slot.kind,"rifle"))
	var result: Array = []
	var left := budget
	# 放置顺序：先前排、后后排。当前布局固定为 6×4，改网格要一起改这里。
	var cells: Array = [5,23,11,17,4,22,10,16,3,21,9,15,2,20,8,14,1,19,7,13,0,18,6,12]
	for i in range(24):
		# 预算足够时先放两个盾卫，其余位置从抽取池选择。买不起时尝试更便宜的蜂群。
		var kind: String = "guard" if i < 2 else str(choices[rng.randi_range(0, choices.size()-1)])
		# 较高预算时带一名医疗兵，优先安排在后排。
		if i == 2 and budget >= 700:
			kind = "medic"
			cells.erase(0)
			cells.insert(i,0)
		if int(catalog[kind].cost) > left:
			kind = "swarm"
		if int(catalog[kind].cost) > left:
			break
		result.append({"kind":kind,"cell":cells[i]})
		# 只扣本次配兵的剩余预算，不会给电脑额外收入。
		left -= int(catalog[kind].cost)
	return result
