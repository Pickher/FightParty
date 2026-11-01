extends RefCounted
## Pure fixed-step simulation. No scene nodes or rendering dependencies.
const Catalog = preload("res://scripts/catalog.gd")
var rules: Dictionary = Catalog.rules()
var catalog: Dictionary = Catalog.units()
var formations: Array = [[], []]
var last_formations: Array = [[], []]
var units: Array = []
var bases: Array = [3000.0, 3000.0]
var tick: int = 0
var wave: int = 0
var next_id: int = 1
var finished: bool = false
var winner: int = -2
var events: Array = []
var journal: Dictionary = {}
var kills: Array = [0, 0]
var damage_done: Array = [0.0, 0.0]
var buckets: Dictionary = {}

func _init(seed_value: int = 42) -> void:
	bases = [float(rules.base_hp), float(rules.base_hp)]
	journal = {"rules_version":rules.version,"seed":seed_value,"waves":[]}

func budget(for_wave: int = -1) -> int:
	var number: int = wave + 1 if for_wave < 0 else for_wave
	return mini(int(rules.max_budget), int(rules.start_budget + maxi(0, number - 1) * rules.budget_growth))

func formation_cost(formation: Array) -> int:
	var total := 0
	for slot in formation:
		if not slot is Dictionary or not catalog.has(slot.get("kind", "")):
			return -1
		total += int(catalog[slot.kind].cost)
	return total

func validate_formation(formation: Array, allowed_budget: int) -> String:
	var occupied: Dictionary = {}
	for slot in formation:
		if not slot is Dictionary or not catalog.has(slot.get("kind", "")):
			return "未知兵种"
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

func submit_formation(team: int, formation: Array) -> String:
	if team < 0 or team > 1 or finished:
		return "对局不可编辑"
	var error := validate_formation(formation, budget())
	if error.is_empty():
		formations[team] = formation.duplicate(true)
	return error

func spawn_unit(team: int, kind: String, pos: Vector2) -> Dictionary:
	var unit := {"id":next_id,"team":team,"kind":kind,"pos":pos,"prev":pos,
		"hp":float(catalog[kind].hp),"cooldown":0.0,"born":tick}
	next_id += 1
	units.append(unit)
	return unit

func _spawn_wave() -> void:
	wave += 1
	last_formations = formations.duplicate(true)
	journal.waves.append({"tick":tick,"wave":wave,"budget":budget(wave),"formations":last_formations.duplicate(true)})
	for team in range(2):
		for slot in last_formations[team]:
			var col: int = int(slot.cell) % int(rules.columns)
			var row: int = int(slot.cell) / int(rules.columns)
			var x: float = 90.0 + col * 28.0
			spawn_unit(team, slot.kind, Vector2(x if team == 0 else 1200.0 - x, 104.0 + row * 64.0))
	events.append({"type":"wave","wave":wave})

func _build_buckets() -> void:
	buckets.clear()
	for unit in units:
		var key := Vector2i(floori(unit.pos.x / 80.0), floori(unit.pos.y / 80.0))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(unit)

func _nearby(pos: Vector2, radius: float) -> Array:
	var found: Array = []
	for x in range(floori((pos.x - radius) / 80.0), floori((pos.x + radius) / 80.0) + 1):
		for y in range(floori((pos.y - radius) / 80.0), floori((pos.y + radius) / 80.0) + 1):
			for unit in buckets.get(Vector2i(x,y), []):
				if pos.distance_squared_to(unit.pos) <= radius * radius:
					found.append(unit)
	return found

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

func step() -> Array:
	events = []
	if finished:
		return events
	tick += 1
	var dt: float = 1.0 / float(rules.tick_rate)
	# Expire before spawning, so at most three waves coexist.
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
	var hits: Dictionary = {}
	var moves: Dictionary = {}
	var base_hits: Array = [0.0, 0.0]
	for unit in units:
		var stats: Dictionary = catalog[unit.kind]
		unit.cooldown = maxf(0.0, float(unit.cooldown) - dt)
		var target := _target(unit)
		var enemy: int = 1 - int(unit.team)
		var goal := Vector2(1170.0 if enemy == 1 else 30.0, 200.0)
		if not target.is_empty():
			goal = target.pos
		var distance: float = unit.pos.distance_to(goal)
		var reach: float = float(stats.range) + (20.0 if target.is_empty() else 0.0)
		if distance <= reach:
			if float(unit.cooldown) <= 0.00001:
				unit.cooldown = float(stats.interval)
				if target.is_empty():
					base_hits[enemy] += float(stats.damage)
				else:
					var victims: Array = [target] if float(stats.splash) == 0 else _nearby(target.pos, float(stats.splash))
					for victim in victims:
						if victim.team != unit.team:
							var multiplier: float = float(stats[catalog[victim.kind].armor + "_multiplier"])
							var amount: float = float(stats.damage) * multiplier
							hits[victim.id] = float(hits.get(victim.id, 0.0)) + amount
							damage_done[int(unit.team)] += amount
					events.append({"type":"attack","from":unit.pos,"to":goal,"kind":unit.kind,"team":unit.team})
		else:
			var direction: Vector2 = (goal - unit.pos).normalized()
			var separation := Vector2.ZERO
			for other in _nearby(unit.pos, 20.0):
				if other.id == unit.id:
					continue
				var offset: Vector2 = unit.pos - other.pos
				if offset.length_squared() > 0.01:
					separation += offset.normalized() * (20.0 - offset.length()) / 20.0
			var velocity: Vector2 = (direction + separation * 0.65).limit_length(1.0) * float(stats.speed)
			moves[unit.id] = Vector2(clampf(unit.pos.x + velocity.x * dt, 30.0, 1170.0), clampf(unit.pos.y + velocity.y * dt, 20.0, 380.0))
	# All decisions use the same pre-step state, then all damage is applied together.
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
	if bases[0] <= 0 or bases[1] <= 0:
		_end(-1 if bases[0] <= 0 and bases[1] <= 0 else (0 if bases[1] <= 0 else 1))
	elif tick >= int(rules.match_seconds * rules.tick_rate):
		_end(-1 if is_equal_approx(bases[0], bases[1]) else (0 if bases[0] > bases[1] else 1))
	return events

func _end(result: int) -> void:
	finished = true
	winner = result
	journal["result"] = {"winner":winner,"tick":tick,"bases":bases.duplicate(),"kills":kills.duplicate()}
	events.append({"type":"ended","winner":winner})

func get_snapshot(viewer: int = 0) -> Dictionary:
	return {"tick":tick,"wave":wave,"budget":budget(),"bases":bases.duplicate(),
		"units":units.duplicate(true),"last_formations":last_formations.duplicate(true),
		"own_formation":formations[viewer].duplicate(true),"finished":finished,"winner":winner}
