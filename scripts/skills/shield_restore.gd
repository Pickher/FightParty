extends "res://scripts/skills/skill.gd"
## 哨兵回盾：同时最多锁定若干友军，每名友军只被一名哨兵锁定。
## 锁按本步单位顺序认领，先处理的哨兵保留自己上一拍的目标。
static var _sessions: Dictionary = {}

func _init() -> void:
	priority=0
	view_fields=["shield_restore_targets"]

func before_target(ctx: Dictionary) -> bool:
	var sim = ctx.sim
	var unit: Dictionary = owner
	var weapon: Dictionary = sim._weapon_stats(unit)
	var restore_range: float = float(config.get("range", weapon.range))
	var nearby: float = float(config.get("nearby_radius", restore_range*1.5))
	var wounded := _wounded(sim, unit, weapon, nearby)
	var chosen := _claim(sim, unit, weapon, nearby, wounded)
	_pulse(sim, unit, ctx, chosen, restore_range)
	if not _attackers_nearby(sim, unit, nearby):
		_move(sim, unit, ctx.dt, ctx.moves, _follow_goal(sim, unit))
		return true
	if not wounded.is_empty():
		var goal: Vector2 = unit.pos
		for ally in chosen:
			if unit.pos.distance_to(ally.pos)>restore_range:
				goal=ally.pos
				break
		_move(sim, unit, ctx.dt, ctx.moves, goal)
		return true
	return false

func _locks(sim) -> Dictionary:
	var key := int(sim.get_instance_id())
	var session: Dictionary = _sessions.get(key, {})
	if int(session.get("tick", -1))!=int(sim.tick):
		session={"tick":int(sim.tick),"locks":{}}
		_sessions[key]=session
	return session.locks

func _claim(sim, unit: Dictionary, weapon: Dictionary, nearby: float, wounded: Array) -> Array:
	var locks := _locks(sim)
	var max_targets := maxi(1, int(config.get("max_targets", 2)))
	var chosen: Array = []
	for raw_id in state.get("targets", []):
		if chosen.size()>=max_targets:break
		var ally = sim.by_id.get(int(raw_id))
		if ally==null or not _needs_shield(sim, unit, ally, weapon):continue
		if unit.pos.distance_to(ally.pos)>nearby:continue
		if locks.has(ally.id) and int(locks[ally.id])!=int(unit.id):continue
		chosen.append(ally)
		locks[ally.id]=unit.id
	for ally in wounded:
		if chosen.size()>=max_targets:break
		if locks.has(ally.id):continue
		chosen.append(ally)
		locks[ally.id]=unit.id
	state.targets=[]
	for ally in chosen:state.targets.append(int(ally.id))
	state.shield_restore_targets=state.targets.duplicate()
	return chosen

func _pulse(sim, unit: Dictionary, ctx: Dictionary, chosen: Array, restore_range: float) -> void:
	var in_range: Array = []
	for ally in chosen:
		if unit.pos.distance_to(ally.pos)<=restore_range:in_range.append(ally)
	if in_range.is_empty():
		state.accumulator=0.0
		return
	var step_seconds: float = float(config.get("pulse_seconds", 0.5))
	state.accumulator=float(state.get("accumulator", 0.0))+float(ctx.dt)
	for ally in in_range:
		sim.active_beams.append({"source_id":unit.id,"target_id":ally.id,"from":unit.pos,"to":ally.pos,"kind":unit.kind,"mode":"shield_restore","team":unit.team,"healing":false,"shield_restore":true})
	var cost: float = float(config.get("energy_per_pulse", 2))
	var amount: float = float(config.get("shield_per_pulse", 5))
	while float(state.accumulator)+0.000001>=step_seconds:
		state.accumulator=maxf(0.0, float(state.accumulator)-step_seconds)
		if not sim.spend_energy(unit, cost):continue
		for ally in in_range:
			ctx.shield_gains[ally.id]=float(ctx.shield_gains.get(ally.id, 0.0))+amount

func _wounded(sim, unit: Dictionary, weapon: Dictionary, nearby: float) -> Array:
	var found: Array = []
	for ally in sim.nearby_team(unit.pos, nearby, int(unit.team)):
		if _needs_shield(sim, unit, ally, weapon):found.append(ally)
	found.sort_custom(func(a, b):
		var left: float = float(a.shield)/float(sim.catalog[a.kind].shield)
		var right: float = float(b.shield)/float(sim.catalog[b.kind].shield)
		if not is_equal_approx(left, right):return left<right
		return int(a.id)<int(b.id)
	)
	return found

func _needs_shield(sim, unit: Dictionary, ally: Dictionary, weapon: Dictionary) -> bool:
	if int(ally.team)!=int(unit.team) or int(ally.id)==int(unit.id) or ally.hp<=0 or sim.is_structure(ally):return false
	var stats: Dictionary = sim.catalog[ally.kind]
	var maximum: float = float(stats.get("shield", 0))
	if maximum<=0.0 or float(ally.shield)>=maximum-0.001:return false
	return weapon.get("target_layers", ["ground"]).has(stats.get("layer", "ground"))

## 可攻击友军：地面、非建筑、伤害大于 0。医疗兵伤害为 0，不把哨兵留在前线。
func _can_front(sim, unit: Dictionary, ally: Dictionary) -> bool:
	if int(ally.team)!=int(unit.team) or int(ally.id)==int(unit.id) or ally.hp<=0 or sim.is_structure(ally):return false
	var stats: Dictionary = sim.catalog[ally.kind]
	return str(stats.get("layer", "ground"))=="ground" and float(stats.get("damage", 0))>0.0

func _attackers_nearby(sim, unit: Dictionary, nearby: float) -> bool:
	for ally in sim.nearby_team(unit.pos, nearby, int(unit.team)):
		if _can_front(sim, unit, ally):return true
	return false

func _follow_goal(sim, unit: Dictionary) -> Vector2:
	var forward: float = 1.0 if int(unit.team)==0 else -1.0
	var front: Dictionary = {}
	for ally in sim.units:
		if not _can_front(sim, unit, ally):continue
		if front.is_empty() or float(ally.pos.x)*forward>float(front.pos.x)*forward:front=ally
	if front.is_empty():return Vector2(sim.mirror_x(unit.team, float(sim.rules.layout.spawn_x)), unit.pos.y)
	return Vector2(float(front.pos.x)-float(config.follow_distance)*forward, front.pos.y)

func _safe_x(sim, unit: Dictionary) -> float:
	var forward: float = 1.0 if int(unit.team)==0 else -1.0
	var front: Dictionary = {}
	for ally in sim.units:
		if not _can_front(sim, unit, ally):continue
		if front.is_empty() or float(ally.pos.x)*forward>float(front.pos.x)*forward:front=ally
	var spawn_x: float = sim.mirror_x(unit.team, float(sim.rules.layout.spawn_x))
	var safe: float = float(front.pos.x)*forward-float(config.follow_distance) if not front.is_empty() else spawn_x*forward
	for enemy in sim.nearby_team(unit.pos, float(config.nearby_radius), 1-int(unit.team)):
		safe=minf(safe, float(enemy.pos.x)*forward-float(config.danger_distance))
	return safe

func _move(sim, unit: Dictionary, dt: float, moves: Dictionary, goal: Vector2) -> void:
	var forward: float = 1.0 if int(unit.team)==0 else -1.0
	goal.x=minf(float(goal.x)*forward, _safe_x(sim, unit))*forward
	moves[unit.id]=unit.pos.move_toward(sim.clamp_to_field(goal), sim._movement_speed(unit)*dt)
