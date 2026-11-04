# 中文导读：战斗规则核心。只计算数据，不画单位、不播放动画。
# team=0 表示玩家，team=1 表示电脑；数组下标也沿用这个约定。
# var 定义变量，func 定义函数，Array 是数组，Dictionary 是字典，Vector2 是二维坐标。
# 当前每秒计算 20 次，每次 step() 是一个 tick；画面帧率不决定攻击速度。
extends RefCounted
## 独立的固定步战斗模拟：不依赖场景节点或渲染器。
const Catalog = preload("res://scripts/catalog.gd")
const Deployment = preload("res://scripts/skills/deployment.gd")
const Healing = preload("res://scripts/skills/healing.gd")
const MultiAttack = preload("res://scripts/skills/multi_attack.gd")
const LineAttack = preload("res://scripts/skills/line_attack.gd")
const Stimulant = preload("res://scripts/skills/stimulant.gd")
const OnHitSlow = preload("res://scripts/skills/on_hit_slow.gd")
const DefenderZone = preload("res://scripts/skills/defender_zone.gd")
const Shield = preload("res://scripts/skills/shield.gd")
const Regen = preload("res://scripts/skills/regen.gd")
const WeaponSwitch = preload("res://scripts/skills/weapon_switch.gd")
const Yamato = preload("res://scripts/skills/yamato.gd")
var rules: Dictionary = Catalog.rules()
var catalog: Dictionary = Catalog.units()
# 双方种族，整局固定（开局设置的 races 覆盖 rules 默认值）；只能购买本方种族的已实装兵种。
var races: Array = ["terran", "terran"]
# 第一次交战（任何单位、结构体或基地首次受到敌方伤害）之后才公开双方种族与上一波阵容。
var revealed: bool = false
var revealed_tick: int = -1
# 双方的永久兵营：每格 {kind, cell, deployed}；每波整份生成一次。deployed 表示已至少出场一次。
var formations: Array = [[], []]
# 上一波已经出兵的阵容（只含 kind/cell），是双方都能查看的信息。
var last_formations: Array = [[], []]
# 双方当前矿物；买兵立即扣除，出兵时各加 wave_income，摧毁对方宝库加 treasury_reward。
var minerals: Array = [0, 0]
# 双方已建造防御塔的次数（被摧毁不会归还次数）。
var tower_builds: Array = [0, 0]
var units: Array = []
# 已发出的传播攻击独立于发射者存活，按固定步推进。
var attack_waves: Array = []
var bases: Array = [3000.0, 3000.0]
var tick: int = 0
var wave: int = 0
# 最后一波出兵的 tick；-1 表示还没到最后一波。
var final_wave_tick: int = -1
var next_id: int = 1
var finished: bool = false
# 胜负编码：-2 尚未结束，-1 平局，0 玩家赢，1 电脑赢。
var winner: int = -2
# 本步发生的事情交给界面处理；例如 wave 出兵、attack 攻击、ended 结束。
var events: Array = []
var journal: Dictionary = {}
var kills: Array = [0, 0]
# 累计理论单位伤害（含超过剩余生命的部分），不等于实际扣除血量；不含基地伤害。
var damage_done: Array = [0.0, 0.0]
var buckets: Dictionary = {}
# 按阵营分开的同尺寸空间桶，以及本步的 id → 单位索引；只用于索敌加速，不改变选择结果。
var team_buckets: Array = [{}, {}]
var by_id: Dictionary = {}
# 带模式切换的兵种（解放者防卫）合并后的武器数据缓存。
var mode_weapons: Dictionary = {}
# 分离避让只看 20 距离内的邻居，用更细的 20×20 网格避免密集时遍历整个 80 格。
var fine_buckets: Dictionary = {}
const BUCKET := 80.0
const FINE := 20.0

## 创建一局新的战斗数据。overrides 覆盖 rules 中的同名字段（开局设置），并写入战报以便重放。
func _init(seed_value: int = 42, overrides: Dictionary = {}) -> void:
	rules.merge(overrides, true)
	races = rules.races.duplicate()
	for team in range(2):
		if not Catalog.RACES.has(races[team]):
			races[team] = "terran"
	bases = [float(rules.base_hp), float(rules.base_hp)]
	minerals = [int(rules.start_minerals), int(rules.start_minerals)]
	journal = {"rules_version":rules.version,"seed":seed_value,"settings":overrides.duplicate(true),"actions":[],"waves":[]}
	if bool(rules.get("structures", true)):
		for team in range(2):
			_place_structure(team, "gate_tower", "gate")
			_place_structure(team, "treasury", "treasury")

## 结构体（门口防御塔、宝库、防御塔）也是 units 中的静止单位，坐标来自 layout 的 <name>_x/<name>_y。
func _place_structure(team: int, kind: String, slot: String) -> Dictionary:
	var layout: Dictionary = rules.layout
	return spawn_unit(team, kind, Vector2(mirror_x(team, float(layout[slot + "_x"])), float(layout[slot + "_y"])))

func is_structure(unit: Dictionary) -> bool:
	return bool(catalog[unit.kind].get("structure", false))

## 防御塔还能否建造：未达到 tower_max_builds，且矿物足够。返回空字符串表示可以。
func tower_error(team: int) -> String:
	var error := _editable(team)
	if error.is_empty() and int(tower_builds[team]) >= int(rules.tower_max_builds):
		error = "防御塔已达建造上限"
	if error.is_empty() and int(minerals[team]) < int(catalog.tower.cost):
		error = "矿物不足"
	return error

## 在固定建造位立即建成一座防御塔并扣矿；被摧毁不给对方奖励，也不能重建。
func build_tower(team: int) -> String:
	var error := tower_error(team)
	if error.is_empty():
		minerals[team] -= int(catalog.tower.cost)
		tower_builds[team] += 1
		_place_structure(team, "tower", "tower")
		events.append({"type":"tower_built","team":team})
		_log(team, {"type":"build_tower"})
	return error

## 累计一份阵容的总价；未知兵种或错误元素返回 -1，由校验函数拒绝。
func formation_cost(formation: Array) -> int:
	var total := 0
	for slot in formation:
		if not slot is Dictionary or not _buyable(slot.get("kind", "")):
			return -1
		total += int(catalog[slot.kind].cost)
	return total

func _buyable(kind) -> bool:
	return kind is String and catalog.has(kind) and not bool(catalog[kind].get("structure", false))

## 某方能否购买该兵种：未知兵种、结构体、未实装（stub）或不属于本方种族都会被拒绝。
func kind_error(team: int, kind) -> String:
	if not _buyable(kind):
		return "未知兵种"
	if not Catalog.is_ready(catalog[kind]):
		return "该兵种尚未实装"
	if str(catalog[kind].get("race", "")) != str(races[team]):
		return "不属于本方种族"
	return ""

func _cell_error(cell) -> String:
	# JSON 读出的数字可能是浮点数，所以允许 5.0，但拒绝 5.5 这样的非整数格子。
	if not (cell is int or cell is float) or float(cell) != floor(float(cell)):
		return "格子编号无效"
	if cell < 0 or cell >= int(rules.columns * rules.rows):
		return "超出布阵范围"
	return ""

## 检查兵种（含种族与实装状态）、格子类型、范围、重复占格和总价。
## 返回空字符串表示合法；其他字符串是展示给玩家的错误原因。空阵容是合法的。
func validate_formation(formation: Array, allowed_budget: int, team: int = 0) -> String:
	var occupied: Dictionary = {}
	for slot in formation:
		if not slot is Dictionary:
			return "未知兵种"
		var kind_problem := kind_error(team, slot.get("kind", ""))
		if not kind_problem.is_empty():
			return kind_problem
		var error := _cell_error(slot.get("cell", -1))
		if not error.is_empty():
			return error
		if occupied.has(int(slot.cell)):
			return "同一格不能重复放置"
		occupied[int(slot.cell)] = true
	if formation_cost(formation) > allowed_budget:
		return "矿物不足，请先移除其他单位"
	return ""

func _slot_index(team: int, cell: int) -> int:
	for i in range(formations[team].size()):
		if int(formations[team][i].cell) == cell:
			return i
	return -1

## 取消某格单位可退还的矿物：本轮新买未出场退全款，已出场过的不退。
func refund_value(team: int, cell: int) -> int:
	var index := _slot_index(team, cell)
	if index < 0 or bool(formations[team][index].deployed):
		return 0
	return int(catalog[formations[team][index].kind].cost)

func is_deployed(team: int, cell: int) -> bool:
	var index := _slot_index(team, cell)
	return index >= 0 and bool(formations[team][index].deployed)

func _editable(team: int) -> String:
	return "对局不可编辑" if team < 0 or team > 1 or finished else ""

func _log(team: int, action: Dictionary) -> void:
	action.tick = tick
	action.team = team
	journal.actions.append(action)

## 在空格购买一名永久单位，立即扣矿。
func buy(team: int, kind: String, cell: int) -> String:
	var error := _editable(team)
	if error.is_empty():
		error = kind_error(team, kind)
	if error.is_empty():
		error = _cell_error(cell)
	if error.is_empty() and _slot_index(team, cell) >= 0:
		error = "该格已有单位"
	if error.is_empty() and int(catalog[kind].cost) > int(minerals[team]):
		error = "矿物不足"
	if error.is_empty():
		minerals[team] -= int(catalog[kind].cost)
		formations[team].append({"kind":kind,"cell":cell,"deployed":false})
		_log(team, {"type":"buy","kind":kind,"cell":cell})
	return error

## 取消某格单位：只影响之后的波次，战场上已有的单位不受影响。
func sell(team: int, cell: int) -> String:
	var error := _editable(team)
	var index := _slot_index(team, cell)
	if error.is_empty() and index < 0:
		error = "该格没有单位"
	if error.is_empty():
		minerals[team] += refund_value(team, cell)
		formations[team].remove_at(index)
		_log(team, {"type":"sell","cell":cell})
	return error

## 移动或交换两格单位；免费，并保留各自的出场状态。
func move(team: int, from_cell: int, to_cell: int) -> String:
	var error := _editable(team)
	if error.is_empty():
		error = _cell_error(to_cell)
	if error.is_empty() and _slot_index(team, from_cell) < 0:
		error = "来源格没有单位"
	if error.is_empty():
		for slot in formations[team]:
			if int(slot.cell) == from_cell:
				slot.cell = to_cell
			elif int(slot.cell) == to_cell:
				slot.cell = from_cell
		_log(team, {"type":"move","from":from_cell,"to":to_cell})
	return error

## 便捷入口：把兵营改成指定阵容。按格比较，同格同兵种保留，其余先卖后买；
## 只有整份合法且矿物足够才执行，否则原兵营不变。UI 移动单位请用 move() 以保留出场状态。
func submit_formation(team: int, formation: Array) -> String:
	var error := _editable(team)
	if error.is_empty():
		error = validate_formation(formation, 2147483647, team)
	if not error.is_empty():
		return error
	var wanted: Dictionary = {}
	for slot in formation:
		wanted[int(slot.cell)] = slot.kind
	var sells: Array = []
	var available: int = int(minerals[team])
	for slot in formations[team]:
		if wanted.get(int(slot.cell), "") != slot.kind:
			sells.append(int(slot.cell))
			available += refund_value(team, int(slot.cell))
	var buys: Array = []
	var cost := 0
	for cell in wanted:
		var index := _slot_index(team, cell)
		if index < 0 or formations[team][index].kind != wanted[cell]:
			buys.append(cell)
			cost += int(catalog[wanted[cell]].cost)
	if cost > available:
		return "矿物不足，请先移除其他单位"
	for cell in sells:
		sell(team, cell)
	for cell in buys:
		buy(team, wanted[cell], cell)
	return ""

## 重放战报中的一个操作；返回值与原操作相同。
func apply_action(action: Dictionary) -> String:
	match str(action.get("type", "")):
		"buy":
			return buy(int(action.team), str(action.kind), int(action.cell))
		"sell":
			return sell(int(action.team), int(action.cell))
		"move":
			return move(int(action.team), int(action.from), int(action.to))
		"build_tower":
			return build_tower(int(action.team))
	return "未知操作"

## 某方当前在场、能造成伤害的部队数量（不含结构体与治疗等无攻击单位）。
func combat_units(team: int) -> int:
	var count := 0
	for unit in units:
		if unit.team != team or bool(catalog[unit.kind].get("structure", false)):
			continue
		if float(catalog[unit.kind].damage) > 0.0:
			count += 1
	return count

## 创建一个在战场上活动的单位：id 是唯一编号，pos 是位置，prev 用于画面插值。
## hp 是当前生命，cooldown 是距离下次攻击还要等几秒，born 是出生时的 tick。
func spawn_unit(team: int, kind: String, pos: Vector2) -> Dictionary:
	var unit := {"id":next_id,"team":team,"kind":kind,"pos":pos,"prev":pos,
		"hp":float(catalog[kind].hp),"cooldown":0.0,"born":tick,"locked_target_id":0}
	if catalog[kind].get("skills",{}).has("deployment") or catalog[kind].get("skills",{}).has("defender_zone"):
		Deployment.initialize(unit)
	Shield.initialize(self, unit)
	next_id += 1
	units.append(unit)
	return unit

## 双方整份兵营同时出场，标记为已部署，再发放每轮收入；不清空已有的残兵。
## 此处没有随机偏置，双方出生点按水平方向镜像。
func _spawn_wave() -> void:
	wave += 1
	if wave >= int(rules.wave_limit):
		final_wave_tick = tick
	for team in range(2):
		last_formations[team] = []
		for slot in formations[team]:
			slot.deployed = true
			last_formations[team].append({"kind":slot.kind,"cell":slot.cell})
	journal.waves.append({"tick":tick,"wave":wave,"minerals":minerals.duplicate(),"formations":last_formations.duplicate(true)})
	for team in range(2):
		for slot in last_formations[team]:
			# 取余 % 得到列，整数除法 / 得到行。出生区坐标来自 rules.layout。
			var col: int = int(slot.cell) % int(rules.columns)
			var row: int = int(slot.cell) / int(rules.columns)
			var layout: Dictionary = rules.layout
			var x: float = float(layout.spawn_x) + col * float(layout.spawn_dx)
			spawn_unit(team, slot.kind, Vector2(mirror_x(team, x), float(layout.spawn_y) + row * float(layout.spawn_dy)))
		minerals[team] += int(rules.wave_income)
	events.append({"type":"wave","wave":wave})

## rules.layout 以我方（team 0）坐标填写，敌方按战场宽度水平镜像。
func mirror_x(team: int, x: float) -> float:
	return x if team == 0 else float(rules.world_width) - x

func base_pos(team: int) -> Vector2:
	return Vector2(mirror_x(team, float(rules.layout.base_x)), float(rules.layout.base_y))

func clamp_to_field(point: Vector2) -> Vector2:
	var bounds: Dictionary = rules.layout.bounds
	return Vector2(clampf(point.x, float(bounds.left), float(bounds.right)), clampf(point.y, float(bounds.top), float(bounds.bottom)))

## 将战场按 80×80 逻辑单位分区，给每个区域记录附近单位，减少寻敌时的遍历。
func _build_buckets() -> void:
	buckets.clear()
	team_buckets = [{}, {}]
	fine_buckets.clear()
	by_id.clear()
	for unit in units:
		by_id[unit.id] = unit
		var key := Vector2i(floori(unit.pos.x / BUCKET), floori(unit.pos.y / BUCKET))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(unit)
		var side: Dictionary = team_buckets[int(unit.team)]
		if not side.has(key):
			side[key] = []
		side[key].append(unit)
		var fine := Vector2i(floori(unit.pos.x / FINE), floori(unit.pos.y / FINE))
		if not fine_buckets.has(fine):
			fine_buckets[fine] = []
		fine_buckets[fine].append(unit)

## 只检查圆形范围覆盖到的空间桶，再用距离过滤，返回真正位于半径内的单位。
## 这里不区分敌我，调用处负责筛选阵营。距离平方比较可以省去开平方。
func _nearby(pos: Vector2, radius: float) -> Array:
	var found: Array = []
	for x in range(floori((pos.x - radius) / BUCKET), floori((pos.x + radius) / BUCKET) + 1):
		for y in range(floori((pos.y - radius) / BUCKET), floori((pos.y + radius) / BUCKET) + 1):
			var bucket = buckets.get(Vector2i(x,y))
			if bucket == null:
				continue
			for unit in bucket:
				if pos.distance_squared_to(unit.pos) <= radius * radius:
					found.append(unit)
	return found

## 分离避让用：返回 20 距离内的单位，遍历顺序与 _nearby(pos, 20) 无关，仅用于求和。
func _neighbors(pos: Vector2) -> Array:
	var found: Array = []
	var fx := floori(pos.x / FINE)
	var fy := floori(pos.y / FINE)
	for x in range(fx - 1, fx + 2):
		for y in range(fy - 1, fy + 2):
			var bucket = fine_buckets.get(Vector2i(x, y))
			if bucket == null:
				continue
			for unit in bucket:
				if pos.distance_squared_to(unit.pos) <= FINE * FINE:
					found.append(unit)
	return found

## 当前开火用的武器数据：防卫模式与多武器单位会合并出专用数据，其他单位就是兵种本身。
func _weapon_stats(unit: Dictionary) -> Dictionary:
	var skills = catalog[unit.kind].get("skills")
	if skills != null and skills.has("defender_zone"):
		return DefenderZone.weapon(self,unit)
	if skills != null and skills.has("weapon_switch"):
		return WeaponSwitch.weapon(self,unit)
	return catalog[unit.kind]

## 索敌用的数据：多武器单位按兵种的射程与目标层（各武器的并集）找目标，其余同开火武器。
func _search_stats(unit: Dictionary) -> Dictionary:
	var skills = catalog[unit.kind].get("skills")
	return catalog[unit.kind] if skills != null and skills.has("weapon_switch") else _weapon_stats(unit)

## 护甲规则：攻击力 + 对应护甲类型的穿甲加成（bonus.light / bonus.heavy）。
## 无甲（none）与特殊甲（special）不吃任何加成。返回扣护盾/护甲之前的原始伤害。
func raw_damage(weapon: Dictionary, victim_kind: String) -> float:
	var raw := float(weapon.damage)
	var armor_type: String = str(catalog[victim_kind].get("armor_type", "none"))
	if armor_type == "light" or armor_type == "heavy":
		var bonus = weapon.get("bonus")
		if bonus != null:
			raw += float(bonus.get(armor_type, 0))
	return raw

## 不考虑护盾剩余量的单发预估伤害：有护盾时按原始伤害，否则减去护甲点数，至少 min_damage。
## 用于统计、事件与电脑/多武器的选择；真正扣血在 step() 末尾经 Shield.absorb 结算。
func expected_damage(weapon: Dictionary, victim: Dictionary) -> float:
	var raw := raw_damage(weapon, victim.kind)
	if raw <= 0.0:
		return 0.0
	if float(victim.get("shield", 0.0)) > 0.0:
		return maxf(raw, float(rules.min_damage))
	return maxf(raw - float(catalog[victim.kind].get("armor", 0)), float(rules.min_damage))

## 索敌热点：避免 get(key, 默认数组) 每次创建临时容器。
func _can_hit_unit(unit: Dictionary, other: Dictionary, weapon: Dictionary) -> bool:
	var layers = weapon.get("target_layers")
	var layer = catalog[other.kind].get("layer")
	if layer == null:
		layer = "ground"
	if (layer != "ground") if layers == null else not layers.has(layer):
		return false
	# 结构体按 attacks_structures 判断（缺省同 attacks_base），解放者不能攻击建筑。
	if catalog[other.kind].get("structure", false) and not weapon.get("attacks_structures", weapon.get("attacks_base", true)):
		return false
	var skills = catalog[unit.kind].get("skills")
	return skills == null or not skills.has("defender_zone") or DefenderZone.contains(self,unit,other.pos)

## 发现范围是自身射程的 150%；尚未开火时，每步重新选择追击目标。
## 开火后优先保持目标，直到其死亡、撤离或离开攻击范围；0 表示尚未锁定。同距时以稳定 ID 决定。
func _target(unit: Dictionary) -> Dictionary:
	var weapon := _search_stats(unit)
	var reach := float(weapon.range)
	var radius := reach * 1.5
	var locked = by_id.get(unit.locked_target_id)
	if locked != null and locked.team != unit.team and locked.hp > 0 and _can_hit_unit(unit,locked,weapon):
		if unit.pos.distance_to(locked.pos) <= reach:
			return locked
	unit.locked_target_id = 0
	var best: Dictionary = {}
	var best_score := INF
	var enemies: Dictionary = team_buckets[1 - int(unit.team)]
	var area := _search_area(unit.pos, radius)
	# 按空间桶的环由近到远搜索。第 ring 环内任何单位距离至少 (ring-1)×BUCKET，
	# 已找到更近目标时可以提前结束。
	for ring in range(int(area.rings)):
		if best_score < float(ring - 1) * BUCKET:
			break
		for key in _ring_cells(area, ring):
			var bucket = enemies.get(key)
			if bucket == null or _cell_distance(unit.pos, key) > minf(best_score, radius):
				continue
			for other in bucket:
				if other.hp <= 0:
					continue
				var distance: float = unit.pos.distance_to(other.pos)
				if distance > radius or not _can_hit_unit(unit,other,weapon):
					continue
				var score := distance
				if score < best_score or (is_equal_approx(score, best_score) and int(other.id) < int(best.get("id", 2147483647))):
					best = other
					best_score = score
	return best

## 距离最近（同距按 ID）的存活敌方地面单位（不含结构体），供防卫圈选择圈地方向。
func nearest_ground_enemy(unit: Dictionary, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	var enemies: Dictionary = team_buckets[1 - int(unit.team)]
	var area := _search_area(unit.pos, radius)
	for ring in range(int(area.rings)):
		if best_distance < float(ring - 1) * BUCKET:
			break
		for key in _ring_cells(area, ring):
			var bucket = enemies.get(key)
			if bucket == null or _cell_distance(unit.pos, key) > minf(best_distance, radius):
				continue
			for other in bucket:
				if other.hp <= 0 or catalog[other.kind].get("layer","ground") != "ground" or catalog[other.kind].get("structure", false):
					continue
				var distance: float = unit.pos.distance_to(other.pos)
				if distance > radius:
					continue
				if distance < best_distance or (is_equal_approx(distance,best_distance) and int(other.id) < int(best.get("id",2147483647))):
					best = other
					best_distance = distance
	return best

## 点到某个空间桶矩形的最短距离；大于当前最佳距离的桶不可能有更近目标。
func _cell_distance(pos: Vector2, key: Vector2i) -> float:
	var dx: float = maxf(maxf(float(key.x) * BUCKET - pos.x, pos.x - float(key.x + 1) * BUCKET), 0.0)
	var dy: float = maxf(maxf(float(key.y) * BUCKET - pos.y, pos.y - float(key.y + 1) * BUCKET), 0.0)
	return sqrt(dx * dx + dy * dy)

## 搜索圆的包围盒（按空间桶编号）与需要搜索的环数。
func _search_area(pos: Vector2, radius: float) -> Dictionary:
	var cx := floori(pos.x / BUCKET)
	var cy := floori(pos.y / BUCKET)
	var low := Vector2i(floori((pos.x - radius) / BUCKET), floori((pos.y - radius) / BUCKET))
	var high := Vector2i(floori((pos.x + radius) / BUCKET), floori((pos.y + radius) / BUCKET))
	var rings: int = maxi(maxi(cx - low.x, high.x - cx), maxi(cy - low.y, high.y - cy)) + 1
	return {"cx":cx,"cy":cy,"low":low,"high":high,"rings":rings}

## 以 (cx, cy) 为中心第 ring 环、且位于包围盒内的空间桶编号。
func _ring_cells(area: Dictionary, ring: int) -> Array:
	var cells: Array = []
	var cx: int = area.cx
	var cy: int = area.cy
	var low: Vector2i = area.low
	var high: Vector2i = area.high
	for x in range(maxi(cx - ring, low.x), mini(cx + ring, high.x) + 1):
		if x == cx - ring or x == cx + ring:
			for y in range(maxi(cy - ring, low.y), mini(cy + ring, high.y) + 1):
				cells.append(Vector2i(x, y))
		else:
			if cy - ring >= low.y:
				cells.append(Vector2i(x, cy - ring))
			if cy + ring <= high.y:
				cells.append(Vector2i(x, cy + ring))
	return cells

## 只返回指定阵营、位于半径内的单位；顺序与 _nearby 无关，调用处不得依赖顺序。
func nearby_team(pos: Vector2, radius: float, team: int) -> Array:
	var found: Array = []
	var side: Dictionary = team_buckets[team]
	for x in range(floori((pos.x - radius) / BUCKET), floori((pos.x + radius) / BUCKET) + 1):
		for y in range(floori((pos.y - radius) / BUCKET), floori((pos.y + radius) / BUCKET) + 1):
			var bucket = side.get(Vector2i(x,y))
			if bucket == null:
				continue
			for unit in bucket:
				if pos.distance_squared_to(unit.pos) <= radius * radius:
					found.append(unit)
	return found

## 把一次命中的原始伤害（含穿甲加成）排入本步待结算列表；hits 是 id → 原始伤害数组。
func queue_hit(hits: Dictionary, victim: Dictionary, raw: float) -> void:
	if not hits.has(victim.id):
		hits[victim.id] = []
	hits[victim.id].append(raw)

## 所有移动行为共用增益/减速倍率；不修改兵种基础数值。
func _movement_speed(unit: Dictionary) -> float:
	return float(catalog[unit.kind].speed) * Stimulant.speed_multiplier(unit,tick) * OnHitSlow.speed_multiplier(unit,tick)

## 固定步：撤离/出兵 → 同时决定行动 → 统一应用代价、伤害和状态 → 胜负。
func step() -> Array:
	events = []
	if finished:
		return events
	tick += 1
	var dt: float = 1.0 / float(rules.tick_rate)
	# unit_lifetime 大于 0 时撤离到期单位；默认 0 表示单位一直战斗到死亡。
	var alive: Array = []
	var motion: Dictionary = {}
	var lifetime_ticks: int = int(float(rules.get("unit_lifetime", 0)) * float(rules.tick_rate))
	for unit in units:
		if lifetime_ticks > 0 and tick - int(unit.born) >= lifetime_ticks:
			events.append({"type":"expired","id":unit.id})
		else:
			motion[unit.id] = unit.pos - unit.prev
			unit.prev = unit.pos
			alive.append(unit)
	units = alive
	if wave < int(rules.wave_limit) and tick % wave_ticks() == 0:
		_spawn_wave()
	_build_buckets()
	# 先把命中伤害和移动结果存下来，不立即改目标生命或位置，避免先处理的一方占便宜。
	var hits: Dictionary = {}
	var heals: Dictionary = {}
	var moves: Dictionary = {}
	var self_costs: Dictionary = {}
	var pending_slows: Dictionary = {}
	var base_hits: Array = [0.0, 0.0]
	for unit in units:
		var stats: Dictionary = catalog[unit.kind]
		var skills: Dictionary = stats.get("skills",{})
		if skills.has("healing"):
			unit.cooldown = maxf(0.0, float(unit.cooldown) - dt)
			Healing.step(self, unit, dt, heals, moves)
			continue
		# 大和炮引导期间（含开炮那一步）原地不动、不用普通武器；普通冷却照常恢复。
		if skills.has("yamato") and Yamato.step(self, unit, hits):
			unit.cooldown = maxf(0.0, float(unit.cooldown) - dt)
			continue
		var mode_allowed := true
		if skills.has("defender_zone"):
			mode_allowed = DefenderZone.prepare(self,unit,motion)
			stats = _weapon_stats(unit)
		var target := _target(unit)
		# 多武器单位按目标换武器；换弹期间 armed 为 false，单位原地等待、不能开火。
		var armed := true
		if skills.has("weapon_switch"):
			armed = WeaponSwitch.prepare(self, unit, target)
			stats = _weapon_stats(unit)
		# 因为只有 0 和 1 两队，所以 1-team 正好得到敌方阵营。
		var enemy: int = 1 - int(unit.team)
		var goal := base_pos(enemy)
		if unit.has("defender_goal"):
			goal = unit.defender_goal
		if not target.is_empty():
			goal = target.pos
		var distance: float = unit.pos.distance_to(goal)
		# 攻击基地时加上基地半径，相当于允许攻击到基地边缘。
		var reach: float = float(stats.range) + (float(rules.layout.base_radius) if target.is_empty() else 0.0)
		var can_act: bool = mode_allowed and (not skills.has("deployment") or Deployment.can_act(self, unit, distance <= reach, target.is_empty() and distance <= reach and bool(stats.get("attacks_base",true)), motion))
		if can_act and not target.is_empty() and distance <= reach:
			Stimulant.activate(self,unit,self_costs)
		# cooldown 保存基础攻击时间；增益改变消耗速度，兼容中途生效/到期。
		unit.cooldown = maxf(0.0, float(unit.cooldown) - dt * Stimulant.attack_rate(unit,tick))
		if not can_act:
			continue
		if distance <= reach:
			if target.is_empty() and (unit.has("defender_goal") or not bool(stats.get("attacks_base",true))):
				continue
			if armed and float(unit.cooldown) <= 0.00001:
				unit.cooldown = float(stats.interval)
				if skills.has("line_attack"):
					if not target.is_empty():
						unit.locked_target_id = target.id
					LineAttack.launch(self, unit, goal)
				else:
					for strike in range(MultiAttack.count(stats)):
						if target.is_empty():
							base_hits[enemy] += float(stats.damage)
						else:
							# 只有实际开火才锁定；追击和等待首次攻击冷却时仍可重新选敌。
							unit.locked_target_id = target.id
							# splash=0 时只命中一个目标；大于 0 时以目标位置为圆心搜集范围内单位。
							var victims: Array = [target] if float(stats.splash) == 0 else _nearby(target.pos, float(stats.splash))
							for victim in victims:
								if victim.team != unit.team and _can_hit_unit(unit,victim,stats):
									# 按受击单位的护甲类型加上穿甲加成；护盾与护甲点数在统一结算时扣除。
									var amount: float = expected_damage(stats, victim)
									queue_hit(hits, victim, raw_damage(stats, victim.kind))
									damage_done[int(unit.team)] += amount
									events.append({"type":"attack_hit","id":victim.id,"kind":unit.kind,"team":unit.team,"strike":strike,"amount":amount})
									OnHitSlow.queue_hit(self,victim,skills.get("on_hit_slow",{}),pending_slows)
							events.append({"type":"attack","from":unit.pos,"to":goal,"kind":unit.kind,"team":unit.team})
		else:
			var direction: Vector2 = (goal - unit.pos).normalized()
			# 局部分离：离其他单位太近时轻微避让，降低拥挤；这里不是复杂障碍物寻路。
			var separation := Vector2.ZERO
			for other in _neighbors(unit.pos):
				if other.id == unit.id:
					continue
				if catalog[other.kind].get("layer","ground") != stats.get("layer","ground"):
					continue
				var offset: Vector2 = unit.pos - other.pos
				if offset.length_squared() > 0.01:
					separation += offset.normalized() * (20.0 - offset.length()) / 20.0
			# limit_length 限制方向长度，避免加上避让向量后跑得更快；clampf 把位置留在场内。
			var velocity: Vector2 = (direction + separation * 0.65).limit_length(1.0) * _movement_speed(unit)
			moves[unit.id] = clamp_to_field(unit.pos + velocity * dt)
	LineAttack.advance(self, dt, moves, hits, base_hits, pending_slows)
	# 所有决定基于同一份步初状态，最后统一应用；同一步互相造成致命伤害时双方仍能开火。
	alive = []
	for unit in units:
		unit.pos = moves.get(unit.id, unit.pos)
		if pending_slows.has(unit.id):
			OnHitSlow.apply(unit,pending_slows[unit.id],tick)
		# 治疗按步初缺血量封顶后再承受本步伤害，过量治疗不能充当护盾。
		if heals.has(unit.id):
			unit.hp = minf(float(catalog[unit.kind].hp), float(unit.hp) + float(heals[unit.id]))
		# 同一步的多次命中按发生顺序逐发结算：先扣护盾，再按生命护甲减免（见 shield.gd）。
		var lost: float = float(self_costs.get(unit.id,0.0))
		if hits.has(unit.id):
			var shield_before: float = float(unit.shield)
			var hp_loss := 0.0
			for raw in hits[unit.id]:
				hp_loss += Shield.absorb(self, unit, float(raw))
			lost += hp_loss
			unit.last_hit_tick = tick
			events.append({"type":"damage","id":unit.id,"amount":hp_loss + shield_before - float(unit.shield)})
		unit.hp -= lost
		if unit.hp > 0:
			Shield.recharge(self, unit, dt)
			Regen.recover(self, unit, dt)
			alive.append(unit)
		elif is_structure(unit):
			# 结构体不计击杀；只有宝库给攻击方奖励，同一座宝库只会死亡一次。
			if unit.kind == "treasury":
				minerals[1 - int(unit.team)] += int(rules.treasury_reward)
			events.append({"type":"structure_destroyed","id":unit.id,"kind":unit.kind,"pos":unit.pos,"team":unit.team})
		else:
			kills[1 - int(unit.team)] += 1
			events.append({"type":"death","id":unit.id,"pos":unit.pos,"team":unit.team})
	units = alive
	for team in range(2):
		bases[team] = maxf(0.0, float(bases[team]) - float(base_hits[team]))
		if base_hits[team] > 0:
			events.append({"type":"base_damage","team":team,"amount":base_hits[team]})
	if not revealed and (not hits.is_empty() or float(base_hits[0]) + float(base_hits[1]) > 0.0):
		revealed = true
		revealed_tick = tick
		events.append({"type":"revealed","races":races.duplicate()})
	# 先结算双方基地伤害，再判断同一步双双归零。
	# 最后一波出场后，先失去全部可攻击部队的一方判负；超过安全时限则比较基地剩余生命。
	if bases[0] <= 0 or bases[1] <= 0:
		_end(-1 if bases[0] <= 0 and bases[1] <= 0 else (0 if bases[1] <= 0 else 1))
	elif final_wave_tick >= 0:
		var armed: Array = [combat_units(0) > 0, combat_units(1) > 0]
		if not armed[0] or not armed[1]:
			_end(-1 if not armed[0] and not armed[1] else (0 if armed[0] else 1))
		elif tick - final_wave_tick >= int(float(rules.final_phase_max_seconds) * float(rules.tick_rate)):
			_end(-1 if is_equal_approx(bases[0], bases[1]) else (0 if bases[0] > bases[1] else 1))
	return events

func wave_ticks() -> int:
	return int(float(rules.wave_seconds) * float(rules.tick_rate))

## 记录最终结果，发出 ended 事件；界面收到后显示结算页、保存战报。
func _end(result: int) -> void:
	finished = true
	winner = result
	journal["result"] = {"winner":winner,"tick":tick,"bases":bases.duplicate(),"kills":kills.duplicate()}
	events.append({"type":"ended","winner":winner})

## viewer 能看到的对方上一波阵容：首次交战前为空数组。电脑与敌情栏都只能用它。
func visible_enemy_formation(viewer: int) -> Array:
	return last_formations[1 - viewer].duplicate(true) if revealed else []

## viewer 眼中某方的种族；首次交战前对方种族为空字符串。
func visible_race(viewer: int, team: int) -> String:
	return str(races[team]) if revealed or team == viewer else ""

## 给指定玩家一份可读取的状态副本。包含已公开阵容、自己的兵营与矿物。
## 不包含对方兵营的最新改动与对方矿物；首次交战前也不含对方种族与上一波阵容。
func get_snapshot(viewer: int = 0) -> Dictionary:
	var public_formations: Array = [[], []]
	public_formations[viewer] = last_formations[viewer].duplicate(true)
	public_formations[1 - viewer] = visible_enemy_formation(viewer)
	return {"tick":tick,"wave":wave,"minerals":minerals[viewer],"bases":bases.duplicate(),
		"units":units.duplicate(true),"attack_waves":attack_waves.duplicate(true),"last_formations":public_formations,
		"races":[visible_race(viewer, 0), visible_race(viewer, 1)],"revealed":revealed,
		"own_formation":formations[viewer].duplicate(true),"finished":finished,"winner":winner}
