# 中文导读：战斗规则核心。只计算数据，不画单位、不播放动画。
# team=0 表示玩家，team=1 表示电脑；数组下标也沿用这个约定。
# var 定义变量，func 定义函数，Array 是数组，Dictionary 是字典，Vector2 是二维坐标。
# 当前每秒计算 20 次，每次 step() 是一个 tick；画面帧率不决定攻击速度。
extends RefCounted
## 独立的固定步战斗模拟：不依赖场景节点或渲染器。
const Catalog = preload("res://scripts/catalog.gd")
var rules: Dictionary = Catalog.rules()
var catalog: Dictionary = Catalog.units()
# 双方“下一波”的配兵计划；与战场上正在交战的 units 分开保存。
var formations: Array = [[], []]
# 上一波已经出兵的阵容，是双方都能查看的信息。
var last_formations: Array = [[], []]
var units: Array = []
var bases: Array = [3000.0, 3000.0]
var tick: int = 0
var wave: int = 0
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

## 创建一局新的战斗数据，使用配置中的基地生命，并初始化可复现的波次记录。
func _init(seed_value: int = 42) -> void:
	bases = [float(rules.base_hp), float(rules.base_hp)]
	journal = {"rules_version":rules.version,"seed":seed_value,"waves":[]}

## 计算某波的预算；不传参数（-1）表示下一波。
## 从 start_budget 起，每波加 budget_growth，不超过 max_budget；双方使用同一公式。
func budget(for_wave: int = -1) -> int:
	var number: int = wave + 1 if for_wave < 0 else for_wave
	return mini(int(rules.max_budget), int(rules.start_budget + maxi(0, number - 1) * rules.budget_growth))

## 累计一份阵容的总价；未知兵种或错误元素返回 -1，由校验函数拒绝。
func formation_cost(formation: Array) -> int:
	var total := 0
	for slot in formation:
		if not slot is Dictionary or not catalog.has(slot.get("kind", "")):
			return -1
		total += int(catalog[slot.kind].cost)
	return total

## 检查兵种、格子类型、范围、重复占格和总价。
## 返回空字符串表示合法；其他字符串是展示给玩家的错误原因。空阵容是合法的。
func validate_formation(formation: Array, allowed_budget: int) -> String:
	var occupied: Dictionary = {}
	for slot in formation:
		if not slot is Dictionary or not catalog.has(slot.get("kind", "")):
			return "未知兵种"
		# JSON 读出的数字可能是浮点数，所以允许 5.0，但拒绝 5.5 这样的非整数格子。
		var cell = slot.get("cell", -1)
		if not (cell is int or cell is float) or float(cell) != floor(float(cell)):
			return "格子编号无效"
		if cell < 0 or cell >= int(rules.columns * rules.rows):
			return "超出布阵范围"
		if occupied.has(int(cell)):
			return "同一格不能重复放置"
		occupied[int(cell)] = true
	if formation_cost(formation) > allowed_budget:
		return "预算不足，请先移除其他单位"
	return ""

## 玩家和 AI 共用的提交入口。仅在整份阵容通过检查后替换下一波配置。
## duplicate(true) 深拷贝数组及其内部字典，避免调用者继续改原数组时偷偷改变已提交内容。
func submit_formation(team: int, formation: Array) -> String:
	if team < 0 or team > 1 or finished:
		return "对局不可编辑"
	var error := validate_formation(formation, budget())
	if error.is_empty():
		formations[team] = formation.duplicate(true)
	return error

## 创建一个在战场上活动的单位：id 是唯一编号，pos 是位置，prev 用于画面插值。
## hp 是当前生命，cooldown 是距离下次攻击还要等几秒，born 是出生时的 tick。
func spawn_unit(team: int, kind: String, pos: Vector2) -> Dictionary:
	var unit := {"id":next_id,"team":team,"kind":kind,"pos":pos,"prev":pos,
		"hp":float(catalog[kind].hp),"cooldown":0.0,"born":tick}
	next_id += 1
	units.append(unit)
	return unit

## 锁定双方本波阵容，记录战报，再生成新单位；不清空已有的残兵。
## 此处没有随机偏置，双方出生点按水平方向镜像。
func _spawn_wave() -> void:
	wave += 1
	last_formations = formations.duplicate(true)
	journal.waves.append({"tick":tick,"wave":wave,"budget":budget(wave),"formations":last_formations.duplicate(true)})
	for team in range(2):
		for slot in last_formations[team]:
			# 取余 % 得到列，整数除法 / 得到行。出生位置仍以 1200×400 战场为基础。
			var col: int = int(slot.cell) % int(rules.columns)
			var row: int = int(slot.cell) / int(rules.columns)
			var x: float = 90.0 + col * 28.0
			spawn_unit(team, slot.kind, Vector2(x if team == 0 else 1200.0 - x, 104.0 + row * 64.0))
	events.append({"type":"wave","wave":wave})

## 将战场按 80×80 逻辑单位分区，给每个区域记录附近单位，减少寻敌时的遍历。
func _build_buckets() -> void:
	buckets.clear()
	for unit in units:
		var key := Vector2i(floori(unit.pos.x / 80.0), floori(unit.pos.y / 80.0))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(unit)

## 只检查圆形范围覆盖到的空间桶，再用距离过滤，返回真正位于半径内的单位。
## 这里不区分敌我，调用处负责筛选阵营。距离平方比较可以省去开平方。
func _nearby(pos: Vector2, radius: float) -> Array:
	var found: Array = []
	for x in range(floori((pos.x - radius) / 80.0), floori((pos.x + radius) / 80.0) + 1):
		for y in range(floori((pos.y - radius) / 80.0), floori((pos.y + radius) / 80.0) + 1):
			for unit in buckets.get(Vector2i(x,y), []):
				if pos.distance_squared_to(unit.pos) <= radius * radius:
					found.append(unit)
	return found

## 普通兵种选附近最近的敌人；狙击手对射程内低基础生命目标给予优先权。
## 比较的是配置 hp，不是敌人剩余 hp；同分时用稳定 id 决定，以便复现。
func _target(unit: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	for other in _nearby(unit.pos, 290.0):
		if other.team == unit.team:
			continue
		var distance: float = unit.pos.distance_to(other.pos)
		var score := distance
		if unit.kind == "sniper" and distance <= float(catalog.sniper.range):
			score = distance * 0.1 + float(catalog[other.kind].hp) * 0.2
		if score < best_score or (is_equal_approx(score, best_score) and int(other.id) < int(best.get("id", 2147483647))):
			best = other
			best_score = score
	return best

## 核心循环：计时与撤离 → 到点出兵 → 寻敌/决定行动 → 统一应用伤害 → 判定胜负。
## 每次只推进一个固定步，返回本步事件。对局结束后调用不会再推进时间。
func step() -> Array:
	events = []
	if finished:
		return events
	tick += 1
	var dt: float = 1.0 / float(rules.tick_rate)
	# 先撤离到期单位，再生成下一波；默认 90 秒寿命 / 30 秒间隔，最多三波共存。
	var alive: Array = []
	for unit in units:
		if tick - int(unit.born) >= int(rules.unit_lifetime * rules.tick_rate):
			events.append({"type":"expired","id":unit.id})
		else:
			unit.prev = unit.pos
			alive.append(unit)
	units = alive
	if tick % int(rules.wave_seconds * rules.tick_rate) == 0 and tick < int(rules.match_seconds * rules.tick_rate):
		_spawn_wave()
	_build_buckets()
	# 先把命中伤害和移动结果存下来，不立即改目标生命或位置，避免先处理的一方占便宜。
	var hits: Dictionary = {}
	var moves: Dictionary = {}
	var base_hits: Array = [0.0, 0.0]
	for unit in units:
		var stats: Dictionary = catalog[unit.kind]
		unit.cooldown = maxf(0.0, float(unit.cooldown) - dt)
		var target := _target(unit)
		# 因为只有 0 和 1 两队，所以 1-team 正好得到敌方阵营。
		var enemy: int = 1 - int(unit.team)
		var goal := Vector2(1170.0 if enemy == 1 else 30.0, 200.0)
		if not target.is_empty():
			goal = target.pos
		var distance: float = unit.pos.distance_to(goal)
		# 攻击基地时给基地中心额外 20 的判定距离，相当于允许攻击到基地边缘。
		var reach: float = float(stats.range) + (20.0 if target.is_empty() else 0.0)
		if distance <= reach:
			if float(unit.cooldown) <= 0.00001:
				unit.cooldown = float(stats.interval)
				if target.is_empty():
					base_hits[enemy] += float(stats.damage)
				else:
					# splash=0 时只命中一个目标；大于 0 时以目标位置为圆心搜集范围内单位。
					var victims: Array = [target] if float(stats.splash) == 0 else _nearby(target.pos, float(stats.splash))
					for victim in victims:
						if victim.team != unit.team:
							# 按受击单位的 armor 标签选择攻击者的 light_multiplier 或 heavy_multiplier。
							var multiplier: float = float(stats[catalog[victim.kind].armor + "_multiplier"])
							var amount: float = float(stats.damage) * multiplier
							hits[victim.id] = float(hits.get(victim.id, 0.0)) + amount
							damage_done[int(unit.team)] += amount
					events.append({"type":"attack","from":unit.pos,"to":goal,"kind":unit.kind,"team":unit.team})
		else:
			var direction: Vector2 = (goal - unit.pos).normalized()
			# 局部分离：离其他单位太近时轻微避让，降低拥挤；这里不是复杂障碍物寻路。
			var separation := Vector2.ZERO
			for other in _nearby(unit.pos, 20.0):
				if other.id == unit.id:
					continue
				var offset: Vector2 = unit.pos - other.pos
				if offset.length_squared() > 0.01:
					separation += offset.normalized() * (20.0 - offset.length()) / 20.0
			# limit_length 限制方向长度，避免加上避让向量后跑得更快；clampf 把位置留在场内。
			var velocity: Vector2 = (direction + separation * 0.65).limit_length(1.0) * float(stats.speed)
			moves[unit.id] = Vector2(clampf(unit.pos.x + velocity.x * dt, 30.0, 1170.0), clampf(unit.pos.y + velocity.y * dt, 20.0, 380.0))
	# 所有决定基于同一份步初状态，最后统一应用；同一步互相造成致命伤害时双方仍能开火。
	alive = []
	for unit in units:
		unit.pos = moves.get(unit.id, unit.pos)
		unit.hp -= float(hits.get(unit.id, 0.0))
		if hits.has(unit.id):
			events.append({"type":"damage","id":unit.id,"amount":hits[unit.id]})
		if unit.hp > 0:
			alive.append(unit)
		else:
			kills[1 - int(unit.team)] += 1
			events.append({"type":"death","id":unit.id,"pos":unit.pos,"team":unit.team})
	units = alive
	for team in range(2):
		bases[team] = maxf(0.0, float(bases[team]) - float(base_hits[team]))
		if base_hits[team] > 0:
			events.append({"type":"base_damage","team":team,"amount":base_hits[team]})
	# 先结算双方基地伤害，再判断同一步双双归零。超时比较剩余生命（双方初始血量相同）。
	if bases[0] <= 0 or bases[1] <= 0:
		_end(-1 if bases[0] <= 0 and bases[1] <= 0 else (0 if bases[1] <= 0 else 1))
	elif tick >= int(rules.match_seconds * rules.tick_rate):
		_end(-1 if is_equal_approx(bases[0], bases[1]) else (0 if bases[0] > bases[1] else 1))
	return events

## 记录最终结果，发出 ended 事件；界面收到后显示结算页、保存战报。
func _end(result: int) -> void:
	finished = true
	winner = result
	journal["result"] = {"winner":winner,"tick":tick,"bases":bases.duplicate(),"kills":kills.duplicate()}
	events.append({"type":"ended","winner":winner})

## 给指定玩家一份可读取的状态副本。包含已公开阵容与自己的待出兵阵容。
## 不包含对方下一波阵容；未来联网也应保留这个信息边界。
func get_snapshot(viewer: int = 0) -> Dictionary:
	return {"tick":tick,"wave":wave,"budget":budget(),"bases":bases.duplicate(),
		"units":units.duplicate(true),"last_formations":last_formations.duplicate(true),
		"own_formation":formations[viewer].duplicate(true),"finished":finished,"winner":winner}
