# 中文导读：战斗规则核心。只计算数据，不画单位、不播放动画。
# team=0 表示玩家，team=1 表示电脑；数组下标也沿用这个约定。
# var 定义变量，func 定义函数，Array 是数组，Dictionary 是字典，Vector2 是二维坐标。
# 当前每秒计算 20 次，每次 step() 是一个 tick；画面帧率不决定攻击速度。
extends RefCounted
## 独立的固定步战斗模拟：不依赖场景节点或渲染器。
const Economy = preload("res://scripts/economy/desert_storm_economy.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Unit = preload("res://scripts/units/unit.gd")
const WeaponDefinition = preload("res://scripts/units/weapon_definition.gd")
const BaseDefense = preload("res://scripts/units/base_defense.gd")
const AttackSequences = preload("res://scripts/skills/services/attack_sequence_service.gd")
const AttackTypes = preload("res://scripts/attacks/attack_registry.gd")
const SkillSystem = preload("res://scripts/skills/skill_system.gd")
const Shield = preload("res://scripts/skills/services/shield_service.gd")
const StatusService = preload("res://scripts/skills/services/status_service.gd")
const SlowService = preload("res://scripts/skills/services/slow_service.gd")
const AreaService = preload("res://scripts/skills/services/area_service.gd")
const SummonService = preload("res://scripts/skills/services/summon_service.gd")
var skill_system = SkillSystem.new()
var skill_areas: Array = []
var spawn_queue: Array = []
var pending_effects: Array = []
var aura_modifiers: Dictionary = {}
var teleports: Dictionary = {}
var self_destruct: Dictionary = {}

var rules: Dictionary = Catalog.rules()
var catalog: Dictionary = Catalog.units()
var definitions: Dictionary = {}
# id → Unit 实例。units/by_id/技能持有 Unit.state 的同一引用，只有一份可变状态。
var unit_instances: Dictionary = {}
# 双方种族，整局固定（开局设置的 races 覆盖 rules 默认值）；只能购买本方种族的已实装兵种。
var races: Array = ["terran", "terran"]
# 第一次交战（任何单位、结构体或基地首次受到敌方伤害）之后才公开双方种族与上一波阵容。
var revealed: bool = false
var revealed_tick: int = -1
# 双方的永久兵营：每格 {kind, cell, deployed}；每波整份生成一次。deployed 表示已至少出场一次。
var formations: Array = [[], []]
# 上一波已经出兵的阵容（只含 kind/cell），是双方都能查看的信息。
var last_formations: Array = [[], []]
# 双方当前矿物；收入和瓦斯分流由独立经济组件结算。
var minerals: Array = [0, 0]
var economy: Economy
var next_wave_tick: int = 0
# 双方已建造防御塔的次数（被摧毁不会归还次数）。
var tower_builds: Array = [0, 0]
var units: Array = []
# 已发出的传播攻击独立于发射者存活，按固定步推进。
var attack_waves: Array = []
var attack_sequences: Array = []
var projectiles: Array = []
var next_projectile_id: int = 1
var active_beams: Array = []
var bases: Array = [0.0, 0.0]
var base_defenses: Array = []
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
# 分离按模型体积检查邻居；粗桶 4 格，细桶 2 格。
var fine_buckets: Dictionary = {}
const BUCKET := 4.0
const FINE := 2.0
var max_body_radius := 0.5

## 创建一局新的战斗数据。overrides 覆盖 rules 中的同名字段（开局设置），并写入战报以便重放。
func _init(seed_value: int = 42, overrides: Dictionary = {}) -> void:
	rules.merge(overrides, true)
	economy = Economy.new(rules.economy)
	next_wave_tick = int(float(rules.first_wave_seconds)*float(rules.tick_rate))
	definitions = Catalog.definitions(catalog, rules)
	for kind in definitions:
		catalog[kind] = definitions[kind].to_data()
	races = rules.races.duplicate()
	for team in range(2):
		if not Catalog.RACES.has(races[team]):
			races[team] = "terran"
	base_defenses = [BaseDefense.create(bool(rules.get("structures", true))), BaseDefense.create(bool(rules.get("structures", true)))]
	bases = [base_max_hp(0), base_max_hp(1)]
	minerals = [int(rules.start_minerals), int(rules.start_minerals)]
	journal = {"rules_version":rules.version,"seed":seed_value,"settings":overrides.duplicate(true),"actions":[],"waves":[],"economy_events":[],"economy_config":rules.economy.duplicate(true),"initial_minerals":minerals.duplicate()}
	if bool(rules.get("structures", true)):
		for team in range(2):
			_place_structure(team, "treasury", "treasury")

## 宝库、玩家防御塔是 units 中的静止单位；基地防御层不是独立实体。
func _place_structure(team: int, kind: String, slot: String) -> Dictionary:
	return spawn_unit(team, kind, layout_pos(team,slot))

func is_structure(unit: Dictionary) -> bool:
	return bool(catalog[unit.kind].get("structure", false))

## 人族建造驻军地堡，其余种族沿用各族外观的普通防御塔。
func tower_kind(team: int) -> String:
	return "terran_bunker" if races[team]=="terran" else "tower"

## 防御塔还能否建造：未达到 tower_max_builds，且矿物足够。返回空字符串表示可以。
func tower_error(team: int) -> String:
	var error := _editable(team)
	if error.is_empty() and int(tower_builds[team]) >= int(rules.tower_max_builds):
		error = "防御塔已达建造上限"
	if error.is_empty() and int(minerals[team]) < int(catalog[tower_kind(team)].cost):
		error = "矿物不足"
	return error

## 在固定建造位立即建成一座防御塔并扣矿；被摧毁不给对方奖励，也不能重建。
func build_tower(team: int) -> String:
	var error := tower_error(team)
	if error.is_empty():
		minerals[team] -= int(catalog[tower_kind(team)].cost)
		tower_builds[team] += 1
		_place_structure(team, tower_kind(team), "tower")
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

## 所有购买入口共用矿/气/灵核钱包；价格按当前组配置，校验完成后一次性扣费。
func unit_price(kind: String) -> Dictionary:
	var stats: Dictionary = catalog[kind]
	return {"minerals":int(stats.cost),"gas":int(stats.get("gas_cost",0)),"cores":int(stats.get("core_cost",0))}

func wallet(team: int) -> Dictionary:
	return {"minerals":int(minerals[team]),"gas":int(economy.gas[team]),"cores":int(economy.cores[team])}

func resource_error(price: Dictionary, available: Dictionary) -> String:
	for key in ["minerals","gas","cores"]:
		if int(price.get(key,0))>int(available.get(key,0)):
			return str({"minerals":"矿物","gas":"瓦斯","cores":"灵核"}[key])+"不足"
	return ""

func change_wallet(team: int, price: Dictionary, direction: int) -> void:
	minerals[team]+=int(price.get("minerals",0))*direction
	economy.gas[team]+=int(price.get("gas",0))*direction
	economy.cores[team]+=int(price.get("cores",0))*direction

func refund_resources(team: int, cell: int) -> Dictionary:
	var index := _slot_index(team,cell)
	if index<0 or bool(formations[team][index].deployed):return {"minerals":0,"gas":0,"cores":0}
	return unit_price(str(formations[team][index].kind))

## 在空格购买一名永久单位，立即扣矿。
func buy(team: int, kind: String, cell: int) -> String:
	var error := _editable(team)
	if error.is_empty():
		error = kind_error(team, kind)
	if error.is_empty():
		error = _cell_error(cell)
	if error.is_empty() and _slot_index(team, cell) >= 0:
		error = "该格已有单位"
	if error.is_empty():
		error = resource_error(unit_price(kind),wallet(team))
	if error.is_empty():
		change_wallet(team,unit_price(kind),-1)
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
		change_wallet(team,refund_resources(team,cell),1)
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
	var available: Dictionary = wallet(team)
	for slot in formations[team]:
		if wanted.get(int(slot.cell), "") != slot.kind:
			sells.append(int(slot.cell))
			var refund := refund_resources(team,int(slot.cell))
			for key in available:available[key]+=int(refund[key])
	var buys: Array = []
	var cost := {"minerals":0,"gas":0,"cores":0}
	for cell in wanted:
		var index := _slot_index(team, cell)
		if index < 0 or formations[team][index].kind != wanted[cell]:
			buys.append(cell)
			var price := unit_price(str(wanted[cell]))
			for key in cost:cost[key]+=int(price[key])
	var budget_error := resource_error(cost,available)
	if not budget_error.is_empty():return budget_error
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
		"gasworks":
			return economy.set_gasworks(self,int(action.team),int(action.count))
		"exchange_gas":
			return economy.exchange_gas(self,int(action.team))
	return "未知操作"

## 某方当前在场、能造成伤害的部队数量（不含结构体与治疗等无攻击单位）。
func combat_units(team: int) -> int:
	var count := 0
	for unit in units:
		if unit.team != team or bool(catalog[unit.kind].get("structure", false)):
			continue
		if float(catalog[unit.kind].damage)>0.0 or skill_system.contributes_damage(unit):
			count += 1
	if count==0:
		for area in skill_areas:
			if int(area.team)==team and float(area.config.get("damage",0))>0:return 1
		for enemy in units:
			for dot in enemy.get("dots",[]):
				if int(dot.team)==team and tick<int(dot.until_tick):return 1
	return count

## 创建一个在战场上活动的单位：id 是唯一编号，pos 是位置，prev 用于画面插值。
## hp 是当前生命，cooldown 是距离下次攻击还要等几秒，born 是出生时的 tick。
func spawn_unit(team: int, kind: String, pos: Vector2) -> Dictionary:
	# 也支持调试工具在开局后注入新兵种。
	if not definitions.has(kind):
		definitions[kind] = Catalog.UnitDefinition.new(kind, catalog[kind], rules)
		catalog[kind] = definitions[kind].to_data()
	var instance = Unit.new(definitions[kind], next_id, team, pos, tick)
	var unit: Dictionary = instance.state
	unit_instances[next_id] = instance
	skill_system.attach(self,unit)
	next_id += 1
	units.append(unit)
	return unit

func unit_model(unit: Dictionary) -> Unit:
	return unit_instances.get(int(unit.id))

func has_tag(unit: Dictionary, tag: String) -> bool:
	return definitions[unit.kind].has_tag(tag)

func can_spend_energy(unit: Dictionary, amount: float) -> bool:
	var instance = unit_model(unit)
	return instance != null and instance.can_spend_energy(amount)

func spend_energy(unit: Dictionary, amount: float) -> bool:
	var instance = unit_model(unit)
	return instance != null and instance.spend_energy(amount, tick)

func _prune_unit_instances() -> void:
	var living: Dictionary = {}
	for unit in units: living[unit.id] = true
	for id in unit_instances.keys():
		if not living.has(id): unit_instances.erase(id)

## 双方整份兵营同时出场，标记为已部署，再发放每轮收入；不清空已有的残兵。
## 此处没有随机偏置，双方出生点绕场地中心点对称。
func _spawn_wave() -> void:
	wave += 1
	next_wave_tick = tick + wave_ticks()
	if wave >= int(rules.wave_limit):
		final_wave_tick = tick
	for team in range(2):
		last_formations[team] = []
		for slot in formations[team]:
			slot.deployed = true
			last_formations[team].append({"kind":slot.kind,"cell":slot.cell})
	journal.waves.append({"tick":tick,"wave":wave,"minerals":minerals.duplicate(),"formations":last_formations.duplicate(true),"economy":economy.ledger()})
	for team in range(2):
		var layout: Dictionary = rules.layout
		# 出兵点是队形中心。按已占用列保留前后顺序，稀疏阵容无需挤在相邻小格里。
		var first_col: int = int(rules.columns) - 1
		var last_col := 0
		for slot in last_formations[team]:
			var column: int = int(slot.cell) % int(rules.columns)
			first_col = mini(first_col,column)
			last_col = maxi(last_col,column)
		var center_col: float = float(first_col+last_col)*0.5
		var column_spacing: float = minf(float(layout.spawn_column_spacing),float(layout.spawn_width)/maxi(1,last_col-first_col))
		var row_spacing: float = float(layout.spawn_height)/maxi(1,int(rules.rows)-1)
		for slot in last_formations[team]:
			# 18×8 仍是兵营组槽位；世界出生区不再由旧版格距向前铺开几十格。
			var col: int = int(slot.cell) % int(rules.columns)
			var row: int = int(slot.cell) / int(rules.columns)
			var x: float = float(layout.spawn_x) + (float(col)-center_col)*column_spacing
			var y: float = float(layout.spawn_y) + (float(row)-float(int(rules.rows)-1)*0.5)*row_spacing
			var stats: Dictionary = catalog[slot.kind]
			var count := maxi(1,int(stats.get("spawn_count",1)))
			var pack_columns := ceili(sqrt(float(count)))
			var pack_rows := ceili(float(count)/pack_columns)
			var body: Array = stats.get("size",[1.0,1.0])
			var diameter: float = float(stats.collision_radius)*2.0
			var spacing := Vector2(maxf(float(body[0]),diameter),maxf(float(body[1]),diameter))
			for member in range(count):
				var offset := Vector2((member%pack_columns-(pack_columns-1)*0.5)*(spacing.x+0.1),(member/pack_columns-(pack_rows-1)*0.5)*(spacing.y+0.1))
				var point := Vector2(x,y)+offset
				# 出生时按体积留边；大型单位和小组边缘不被裁在地图外。
				var bounds: Dictionary = layout.bounds
				point.x=clampf(point.x,float(bounds.left)+spacing.x*0.5,float(bounds.right)-spacing.x*0.5)
				point.y=clampf(point.y,float(bounds.top)+spacing.y*0.5,float(bounds.bottom)-spacing.y*0.5)
				spawn_unit(team,slot.kind,mirror_point(team,point))
	events.append({"type":"wave","wave":wave})

## rules.layout 使用我方坐标，参考图采用绕场地中心旋转180度的点对称。
func mirror_x(team: int, x: float) -> float:
	return x if team == 0 else float(rules.world_width) - x

func mirror_point(team: int, point: Vector2) -> Vector2:
	if team==0: return point
	return Vector2(float(rules.world_width)-point.x,float(rules.world_height)-point.y if bool(rules.layout.get("point_symmetry",true)) else point.y)

func layout_pos(team: int, slot: String) -> Vector2:
	return mirror_point(team,Vector2(float(rules.layout[slot+"_x"]),float(rules.layout[slot+"_y"])))

func base_pos(team: int) -> Vector2:
	return layout_pos(team,"base")

## 点位不再共线：部队先穿越中央交战区，再经过敌方宝库，最后推进基地。
## 仅改变无锁定目标时的行军方向；发现/锁定/攻击范围仍由原战斗框架处理。
func march_goal(unit: Dictionary) -> Vector2:
	var enemy := 1-int(unit.team)
	if is_structure(unit): return base_pos(enemy)
	var route: Array = [economy.center_pos(),layout_pos(enemy,"treasury"),base_pos(enemy)]
	var stage: int = int(unit.get("march_stage",0))
	var sign_x := 1.0 if int(unit.team)==0 else -1.0
	while stage<route.size()-1:
		var waypoint: Vector2 = route[stage]
		if unit.pos.distance_to(waypoint)>2.0 and (unit.pos.x-waypoint.x)*sign_x<0: break
		stage += 1
	unit.march_stage = stage
	return route[stage]

func base_max_hp(team: int) -> float:
	return float(rules.base_hp) + (float(catalog.gate_tower.hp) if bool(base_defenses[team].active) else 0.0)

func base_has_defense(team: int) -> bool:
	return bool(base_defenses[team].active) and float(bases[team]) > float(rules.base_hp)

func base_extra_hp(team: int) -> float:
	return maxf(0.0, float(bases[team]) - float(rules.base_hp)) if base_has_defense(team) else 0.0

func clamp_to_field(point: Vector2) -> Vector2:
	var bounds: Dictionary = rules.layout.bounds
	return Vector2(clampf(point.x, float(bounds.left), float(bounds.right)), clampf(point.y, float(bounds.top), float(bounds.bottom)))

## 将战场按 4×4 格分区，给每个区域记录附近单位，减少寻敌时的遍历。
func _build_buckets() -> void:
	max_body_radius = 0.5
	buckets.clear()
	team_buckets = [{}, {}]
	fine_buckets.clear()
	by_id.clear()
	for unit in units:
		max_body_radius = maxf(max_body_radius,body_radius(unit))
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

## 按两者体积之和检查局部分离，仅在接触距离内产生避让。
func body_radius(unit: Dictionary) -> float:
	return definitions[unit.kind].collision_radius

## 行军与停步整理队形共用局部分离；只观察步初位置，避免处理顺序影响结果。
func _separation(unit: Dictionary) -> Vector2:
	var separation := Vector2.ZERO
	for other in _neighbors(unit.pos,body_radius(unit)+max_body_radius):
		if other.id == unit.id or catalog[other.kind].get("layer","ground") != catalog[unit.kind].get("layer","ground"):
			continue
		var offset: Vector2 = unit.pos-other.pos
		var contact: float = body_radius(unit)+body_radius(other)
		var distance: float = offset.length()
		if distance >= contact:continue
		# 完全重叠也能分开；用稳定 ID 决定上下方向，左右镜像局仍保持对称。
		var direction := Vector2(0,1 if int(unit.id)>int(other.id) else -1) if distance<0.00001 else offset/distance
		separation += direction*(contact-distance)/contact
	return separation

func _neighbors(pos: Vector2, radius: float = FINE) -> Array:
	var found: Array = []
	var fx := floori(pos.x / FINE)
	var fy := floori(pos.y / FINE)
	var cells := ceili(radius/FINE)
	for x in range(fx - cells, fx + cells + 1):
		for y in range(fy - cells, fy + cells + 1):
			var bucket = fine_buckets.get(Vector2i(x, y))
			if bucket == null:
				continue
			for unit in bucket:
				if pos.distance_squared_to(unit.pos) <= radius * radius:
					found.append(unit)
	return found

## 当前开火用的武器数据：防卫模式与多武器单位会合并出专用数据，其他单位就是兵种本身。
func _weapon_stats(unit: Dictionary) -> Dictionary:
	return skill_system.weapon(self,unit)

## 仅显式启用的原版近战武器按接触边缘量射程，避免0.1格武器要求模型重叠。
func attack_reach(unit: Dictionary, target: Dictionary, weapon: Dictionary) -> float:
	var reach: float = float(weapon.range)
	if bool(weapon.get("range_from_edge",false)):
		reach+=body_radius(unit)
		if not target.is_empty():reach+=body_radius(target)
	return reach

func _search_stats(unit: Dictionary) -> Dictionary:
	return skill_system.search(self,unit)

## 护甲规则：攻击力 + 对应护甲类型的穿甲加成（bonus.light / bonus.heavy）。
## 无甲（none）与特殊甲（special）不吃任何加成。返回扣护盾/护甲之前的原始伤害。
func raw_damage(weapon: Dictionary, victim_kind: String) -> float:
	var raw := float(weapon.damage)
	var armor_type: String = str(catalog[victim_kind].get("armor_type", "none"))
	if armor_type == "light" or armor_type == "heavy":
		var bonus = weapon.get("bonus")
		if bonus != null:
			raw += float(bonus.get(armor_type, 0))
	for tag in weapon.get("bonus_tags", {}):
		if definitions[victim_kind].has_tag(str(tag)):
			raw += float(weapon.bonus_tags[tag])
	return raw

## 不考虑护盾剩余量的单发预估伤害：有护盾时按原始伤害，否则减去护甲点数，至少 min_damage。
## 用于统计、事件与电脑/多武器的选择；真正扣血在 step() 末尾经 Shield.absorb 结算。
func expected_damage(weapon: Dictionary, victim: Dictionary) -> float:
	var raw := raw_damage(weapon, victim.kind)
	if raw <= 0.0:
		return 0.0
	if WeaponDefinition.ignores_armor(weapon): return raw
	if float(victim.get("shield", 0.0)) > 0.0:
		return maxf(raw - (float(catalog[victim.kind].get("shield_armor", 0))+skill_system.shield_armor_bonus(self,victim))*float(weapon.get("armor_multiplier",1)), float(rules.min_damage))+minf(float(weapon.get("shield_bonus",0)),float(victim.shield))
	return maxf(raw - (float(catalog[victim.kind].get("armor", 0))+skill_system.armor_bonus(self,victim))*float(weapon.get("armor_multiplier",1)), float(rules.min_damage))

## 索敌热点：避免 get(key, 默认数组) 每次创建临时容器。
func _can_hit_unit(unit: Dictionary, other: Dictionary, weapon: Dictionary) -> bool:
	if bool(other.get("owner_dependent",false)) and not by_id.has(int(other.get("owner_id",0))):return false
	if bool(unit.get("owner_dependent",false)):
		var parent = by_id.get(int(unit.get("owner_id",0)))
		if parent==null or parent.pos.distance_to(other.pos)>float(unit.get("leash",0)):return false
	var layers = weapon.get("target_layers")
	var layer = catalog[other.kind].get("layer")
	if layer == null:
		layer = "ground"
	var targetable: Array = catalog[other.kind].get("targetable_layers",[layer])
	var compatible := false
	for target_layer in targetable:
		if (target_layer=="ground") if layers==null else layers.has(target_layer):compatible=true
	if not compatible:return false
	# 结构体按 attacks_structures 判断（缺省同 attacks_base），解放者不能攻击建筑。
	if catalog[other.kind].get("structure", false) and not weapon.get("attacks_structures", weapon.get("attacks_base", true)):
		return false
	return true if bool(unit.get("projectile",false)) else skill_system.can_target(self,unit,other)

## 发现范围是自身射程的 150%；尚未开火时，每步重新选择追击目标。
## 开火后优先保持目标，直到其死亡、撤离或离开攻击范围；0 表示尚未锁定。同距时以稳定 ID 决定。
func _target(unit: Dictionary) -> Dictionary:
	var weapon := _search_stats(unit)
	var reach := float(weapon.range)
	var discovery: float = reach+body_radius(unit)+max_body_radius if bool(weapon.get("range_from_edge",false)) else reach
	var radius: float = skill_system.discovery_radius(self,unit,discovery*1.5)
	var locked = by_id.get(unit.locked_target_id)
	if locked != null and locked.team != unit.team and locked.hp > 0 and _can_hit_unit(unit,locked,weapon):
		if unit.pos.distance_to(locked.pos) <= attack_reach(unit,locked,_weapon_stats(unit)):
			return locked
	unit.locked_target_id=0
	if skill_system.has_priority(unit):
		var priority: Dictionary = {}
		var priority_distance := INF
		var priority_weight := -1
		for other in nearby_team(unit.pos,radius,1-int(unit.team)):
			if other.hp<=0 or skill_system.target_priority(self,unit,other)<=0 or not _can_hit_unit(unit,other,weapon):
				continue
			if other.id == unit.locked_target_id and unit.pos.distance_to(other.pos)<=reach:
				return other
			var candidate_distance: float = unit.pos.distance_to(other.pos)
			var weight: int = skill_system.target_priority(self,unit,other)
			if weight>priority_weight or (weight==priority_weight and (candidate_distance<priority_distance or (is_equal_approx(candidate_distance,priority_distance) and int(other.id)<int(priority.get("id",2147483647))))):
				priority=other
				priority_distance=candidate_distance
				priority_weight=weight
		if not priority.is_empty():
			unit.locked_target_id=0
			return priority
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
func queue_hit(hits: Dictionary, victim: Dictionary, raw: float, ranged: bool = false, ignore_armor: bool = false, shield_bonus: float = 0.0, armor_multiplier: float = 1.0) -> void:
	if raw<=0:return
	if ranged:
		raw=maxf(float(rules.min_damage),raw-float(aura_modifiers.get(victim.id,{}).get("reduction",0)))
	if not hits.has(victim.id):
		hits[victim.id] = []
	hits[victim.id].append({"raw":raw,"ignore_armor":ignore_armor,"shield_bonus":shield_bonus,"armor_multiplier":armor_multiplier} if ignore_armor or shield_bonus>0 or armor_multiplier!=1.0 else raw)

## 普通、传播、弹射武器共用伤害属性。true 额外跳过远程光环减伤。
func queue_weapon_hit(hits: Dictionary, victim: Dictionary, weapon: Dictionary, raw: float, ranged: bool = false, bonus_multiplier: float = 1.0) -> void:
	queue_hit(hits, victim, raw, ranged and str(weapon.get("damage_type", "physical")) != "true", WeaponDefinition.ignores_armor(weapon),float(weapon.get("shield_bonus",0))*bonus_multiplier,float(weapon.get("armor_multiplier",1)))

## 普通武器的一段命中；独立炮位也经过相同的溅射、护甲、护盾和命中技能结算。
func queue_direct_strike(ctx: Dictionary, weapon: Dictionary, target: Dictionary, strike: int) -> void:
	var unit: Dictionary = ctx.unit
	var center: Vector2 = ctx.get("impact_position",target.pos)
	var direct = by_id.get(int(target.id))
	var victims: Array = ([] if direct==null else [direct]) if float(weapon.splash)==0 else nearby_team(center,float(weapon.splash)+float(ctx.get("motion_margin",0)),1-int(unit.team))
	for victim in victims:
		if victim.team==unit.team or not _can_hit_unit(unit,victim,weapon):continue
		var position: Vector2 = victim.pos
		if ctx.has("impact_fraction"):position=victim.pos.lerp(ctx.moves.get(victim.id,victim.pos),float(ctx.impact_fraction))
		var distance: float = center.distance_to(position)
		if float(weapon.splash)>0 and distance>float(weapon.splash):continue
		if float(weapon.splash)<=0 and ctx.has("impact_position") and not bool(weapon.get("delivery",{}).get("tracking",true)) and distance>body_radius(victim):continue
		var multiplier: float = float(ctx.get("damage_multiplier",1.0))
		if victim.id!=target.id:
			multiplier*=WeaponDefinition.splash_damage_multiplier(weapon,distance)
		var raw: float = raw_damage(weapon,victim.kind)*multiplier
		if raw<=0:continue
		var amount: float = expected_damage({"damage":raw,"damage_type":weapon.damage_type,"shield_bonus":float(weapon.get("shield_bonus",0))*multiplier},victim)
		queue_weapon_hit(ctx.hits,victim,weapon,raw,float(weapon.range)>1.5,multiplier)
		damage_done[int(unit.team)]+=amount
		events.append({"type":"attack_hit","id":victim.id,"kind":unit.kind,"team":unit.team,"strike":strike,"amount":amount,"mode":weapon.get("id","primary"),"time":float(ctx.get("impact_time",float(tick)/float(rules.tick_rate)))})
		if ctx.has("impact_skills"):
			skill_system.wave_hit(self,{"source_id":unit.id,"kind":unit.kind,"team":unit.team,"source":unit.pos,"impact_skills":ctx.impact_skills,"weapon":weapon,"damage_multiplier":multiplier},victim,ctx.hits,ctx.pending_slows)
		else:skill_system.hit(self,unit,victim,ctx.hits,ctx.pending_slows)

## 所有移动行为共用增益/减速倍率；不修改兵种基础数值。
func _movement_speed(unit: Dictionary) -> float:
	if tick<int(unit.get("root_until_tick",0)):return 0.0
	if unit_model(unit).blocks_movement() and not skill_system.moves_while_attacking(unit): return 0.0
	return definitions[unit.kind].speed * skill_system.movement_multiplier(self,unit) * SlowService.speed_multiplier(unit,tick)

func _tick_attack_clock(unit: Dictionary, dt: float) -> void:
	unit_model(unit).tick_attack(dt, skill_system.attack_rate(self,unit))

## 固定步：撤离/出兵 → 同时决定行动 → 统一应用代价、伤害和状态 → 胜负。
func step() -> Array:
	events = []
	active_beams=[]
	if finished:
		return events
	tick += 1
	pending_effects=[]
	teleports.clear()
	self_destruct.clear()
	var dt: float = 1.0 / float(rules.tick_rate)
	# unit_lifetime 大于 0 时撤离到期单位；默认 0 表示单位一直战斗到死亡。
	var alive: Array = []
	var motion: Dictionary = {}
	var lifetime_ticks: int = int(float(rules.get("unit_lifetime", 0)) * float(rules.tick_rate))
	for unit in units:
		if (lifetime_ticks > 0 and tick - int(unit.born) >= lifetime_ticks) or (unit.has("expires_tick") and tick>=int(unit.expires_tick)):
			events.append({"type":"expired","id":unit.id})
		else:
			motion[unit.id] = unit.pos - unit.prev
			unit.prev = unit.pos
			alive.append(unit)
	units = alive
	skill_system.prune(self,units)
	_prune_unit_instances()
	if wave < int(rules.wave_limit) and tick >= next_wave_tick:
		_spawn_wave()
	_build_buckets()
	# 先把命中伤害和移动结果存下来，不立即改目标生命或位置，避免先处理的一方占便宜。
	var hits: Dictionary = {}
	var heals: Dictionary = {}
	var moves: Dictionary = {}
	var self_costs: Dictionary = {}
	var pending_slows: Dictionary = {}
	var base_hits: Array = [0.0, 0.0]
	skill_system.incoming_slows=pending_slows
	var frame := {"sim":self,"dt":dt,"hits":hits,"heals":heals,"moves":moves,"self_costs":self_costs,"base_hits":base_hits,"pending_slows":pending_slows,"motion":motion}
	skill_system.frame(frame)
	StatusService.tick(self,dt,hits)
	BaseDefense.fire(self, frame)
	for unit in units:
		var ctx: Dictionary = frame.duplicate()
		ctx.unit=unit
		ctx.can_act=true
		ctx.armed=true
		ctx.handled=false
		ctx.target={}
		if skill_system.before_target(ctx):
			unit_model(unit).cancel_attack()
			continue
		ctx.target=skill_system.select_target(self,unit,_target(unit))
		skill_system.on_target(ctx)
		var target: Dictionary = ctx.target
		var stats: Dictionary = _weapon_stats(unit)
		ctx.weapon=stats
		# 因为只有 0 和 1 两队，所以 1-team 正好得到敌方阵营。
		var enemy: int = 1 - int(unit.team)
		var goal := march_goal(unit)
		if bool(unit.get("owner_dependent",false)):
			var parent = by_id.get(int(unit.get("owner_id",0)))
			if parent!=null and (not bool(catalog[parent.kind].get("attacks_base",true)) or parent.pos.distance_to(base_pos(enemy))>float(catalog[parent.kind].range)+float(rules.layout.base_radius)):goal=parent.pos
		if unit.has("defender_goal"):
			goal = unit.defender_goal
		if not target.is_empty():
			goal = target.pos
		var distance: float = unit.pos.distance_to(goal)
		# 攻击基地时加上基地半径，相当于允许攻击到基地边缘。
		var attacking_base: bool = target.is_empty() and not unit.has("defender_goal") and goal.is_equal_approx(base_pos(enemy))
		var reach: float = attack_reach(unit,target,stats) + (float(rules.layout.base_radius) if attacking_base else 0.0)
		ctx.goal=goal
		ctx.distance=distance
		ctx.reach=reach
		skill_system.before_action(ctx)
		_tick_attack_clock(unit,dt)
		if not ctx.can_act or ctx.handled:
			unit_model(unit).cancel_attack()
			continue
		var eligible: bool = ctx.armed and float(stats.damage) > 0.0 and distance <= reach and (not target.is_empty() or (attacking_base and bool(stats.get("attacks_base", true))))
		# 基地用负编号，敌军用稳定正编号，未开火时不设置 locked_target_id。
		var target_id: int = int(target.id) if not target.is_empty() else -enemy - 1
		var attack_behavior := AttackTypes.for_weapon(stats)
		if attack_behavior.is_continuous():
			if eligible:
				ctx.damage_multiplier=skill_system.damage_multiplier(ctx) if not target.is_empty() else 1.0
				var beam_target: Dictionary = target if not target.is_empty() else {"id":target_id,"pos":goal}
				attack_behavior.tick(ctx,unit,stats,beam_target,target_id)
				skill_system.after_action(ctx)
				continue
		var fire: bool = unit_model(unit).ready_to_fire(stats, target_id, eligible)
		if distance <= reach and (not target.is_empty() or attacking_base):
			if target.is_empty() and (not attacking_base or not bool(stats.get("attacks_base",true))):
				continue
			if fire:
				ctx.damage_multiplier=skill_system.damage_multiplier(ctx) if not target.is_empty() else 1.0
				AttackSequences.launch(ctx,unit)
			# 配置允许的机动单位在攻击冷却期间也可松开队形；前摇、后摇和开火当步不移动。
			if not fire and definitions[unit.kind].separate_when_stopped and unit.attack_phase=="idle" and str(unit.get("siege_state","mobile"))=="mobile":
				var drift: Vector2 = (_separation(unit)*0.65).limit_length(1.0)*_movement_speed(unit)
				moves[unit.id]=clamp_to_field(unit.pos+drift*dt)
		else:
			var direction: Vector2 = (goal - unit.pos).normalized()
			# 局部分离：离其他单位太近时轻微避让，降低拥挤；这里不是复杂障碍物寻路。
			var separation := _separation(unit)
			# limit_length 限制方向长度，避免加上避让向量后跑得更快；clampf 把位置留在场内。
			var velocity: Vector2 = (direction + separation * 0.65).limit_length(1.0) * _movement_speed(unit)
			moves[unit.id] = clamp_to_field(unit.pos + velocity * dt)
		skill_system.after_action(ctx)
	AttackSequences.advance(self,frame)
	AttackTypes.advance(self,frame)
	AreaService.advance(self,dt,moves,hits,base_hits)
	StatusService.apply(self)
	var deaths: Array = []
	# 所有决定基于同一份步初状态，最后统一应用；同一步互相造成致命伤害时双方仍能开火。
	alive = []
	for unit in units:
		unit.pos = moves.get(unit.id, unit.pos)
		if pending_slows.has(unit.id):
			SlowService.apply(unit,pending_slows[unit.id],tick)
		# 治疗按步初缺血量封顶后再承受本步伤害，过量治疗不能充当护盾。
		if heals.has(unit.id):
			unit.hp = minf(float(catalog[unit.kind].hp), float(unit.hp) + float(heals[unit.id]))
		# 同一步的多次命中按发生顺序逐发结算：先扣护盾，再按生命护甲减免（见 shield.gd）。
		var lost: float = float(self_costs.get(unit.id,0.0))
		if hits.has(unit.id):
			var shield_before: float = float(unit.shield)
			var hp_loss := 0.0
			for hit in hits[unit.id]:
				var raw: float = float(hit.raw) if hit is Dictionary else float(hit)
				var ignore_armor: bool = bool(hit.ignore_armor) if hit is Dictionary else false
				raw=skill_system.absorb(self,unit,raw)
				var shield_bonus: float = float(hit.get("shield_bonus",0)) if hit is Dictionary and raw>0 else 0.0
				var armor_multiplier: float = float(hit.get("armor_multiplier",1)) if hit is Dictionary else 1.0
				hp_loss += Shield.absorb(self, unit, raw, ignore_armor,shield_bonus,armor_multiplier)
			lost += hp_loss
			unit.last_hit_tick = tick
			events.append({"type":"damage","id":unit.id,"amount":hp_loss + shield_before - float(unit.shield)})
		unit.hp -= lost
		if self_destruct.has(unit.id):unit.hp=0.0
		if unit.hp<=0:deaths.append(unit)
		if unit.hp > 0:
			unit_model(unit).restore(dt, tick, float(rules.tick_rate))
			skill_system.survived({"sim":self,"unit":unit,"dt":dt})
			alive.append(unit)
		elif is_structure(unit):
			# 结构体不计击杀；宝库奖励灵核，同一座宝库只会死亡一次。
			if unit.kind == "treasury":
				economy.reward_outpost(self,1-int(unit.team))
			events.append({"type":"structure_destroyed","id":unit.id,"kind":unit.kind,"pos":unit.pos,"team":unit.team})
		else:
			kills[1 - int(unit.team)] += 1
			events.append({"type":"death","id":unit.id,"pos":unit.pos,"team":unit.team})
	for dead in deaths:
		AttackSequences.target_died(self,dead)
		AttackTypes.target_died(self,dead)
		skill_system.death({"sim":self,"dead":dead})
	units = alive
	SummonService.flush(self)
	skill_system.prune(self,units)
	_prune_unit_instances()
	skill_system.end_frame(units)
	for team in range(2):
		BaseDefense.settle(self, team, float(base_hits[team]), dt)
	if not revealed and (not hits.is_empty() or float(base_hits[0]) + float(base_hits[1]) > 0.0):
		revealed = true
		revealed_tick = tick
		events.append({"type":"revealed","races":races.duplicate()})
	economy.step(self)
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

func ticks_to_next_wave() -> int:
	return maxi(0,next_wave_tick-tick) if wave<int(rules.wave_limit) else 0

func wave_ticks() -> int:
	return int(float(rules.wave_seconds) * float(rules.tick_rate))

## 记录最终结果，发出 ended 事件；界面收到后显示结算页、保存战报。
func _end(result: int) -> void:
	finished = true
	winner = result
	journal["result"] = {"winner":winner,"tick":tick,"bases":bases.duplicate(),"base_max_hp":[base_max_hp(0),base_max_hp(1)],"base_defenses":base_defenses.duplicate(true),"kills":kills.duplicate(),"minerals":minerals.duplicate(),"economy":economy.ledger()}
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
	return {"tick":tick,"wave":wave,"minerals":minerals[viewer],"economy":economy.snapshot(viewer,wave),"next_wave_tick":next_wave_tick,"bases":bases.duplicate(),
		"active_beams":active_beams.duplicate(true),
		"attack_sequences":attack_sequences.duplicate(true),"projectiles":projectiles.duplicate(true),"next_projectile_id":next_projectile_id,
		"base_max_hp":[base_max_hp(0),base_max_hp(1)],"base_defenses":base_defenses.duplicate(true),
		"units":units.map(func(unit): return unit_model(unit).snapshot()),"attack_waves":attack_waves.duplicate(true),"skill_areas":skill_areas.duplicate(true),"last_formations":public_formations,
		"races":[visible_race(viewer, 0), visible_race(viewer, 1)],"revealed":revealed,
		"own_formation":formations[viewer].duplicate(true),"finished":finished,"winner":winner}
