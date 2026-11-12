extends "res://scripts/skills/skill.gd"
const AttackTypes = preload("res://scripts/attacks/attack_registry.gd")

func step(sim, unit: Dictionary, dt: float, heals: Dictionary, moves: Dictionary) -> void:
	var stats: Dictionary = sim.catalog[unit.kind]
	var weapon: Dictionary = sim._weapon_stats(unit)
	var attack_behavior := AttackTypes.for_weapon(weapon)
	var forward: float = 1.0 if unit.team == 0 else -1.0
	var front: Dictionary = {}
	for ally in sim.units:
		if ally.team != unit.team or sim.is_structure(ally) or sim.catalog[ally.kind].get("skills",{}).has("healing") or sim.catalog[ally.kind].get("layer","ground") != "ground":
			continue
		if front.is_empty() or float(ally.pos.x) * forward > float(front.pos.x) * forward:
			front = ally
	var goal := Vector2(sim.mirror_x(unit.team, float(sim.rules.layout.spawn_x)), unit.pos.y)
	var safe_x: float = goal.x * forward
	if not front.is_empty():
		safe_x = float(front.pos.x) * forward - float(config.follow_distance)
		goal = Vector2(safe_x * forward, front.pos.y)
	for enemy in sim._nearby(unit.pos, float(stats.range) * 1.5):
		if enemy.team != unit.team:
			safe_x = minf(safe_x, float(enemy.pos.x) * forward - float(config.danger_distance))
	var patient: Dictionary = {}
	var chase: Dictionary = {}
	var best_ratio := INF
	var chase_ratio := INF
	for ally in sim._nearby(unit.pos, float(stats.range) * 1.5):
		if ally.team != unit.team or ally.id == unit.id or ally.hp <= 0 or sim.is_structure(ally):
			continue
		if not weapon.target_layers.has(sim.catalog[ally.kind].get("layer","ground")):continue
		var ratio: float = float(ally.hp) / float(sim.catalog[ally.kind].hp)
		if ratio >= 1.0:
			continue
		var distance: float = unit.pos.distance_to(ally.pos)
		if ratio < chase_ratio or (is_equal_approx(ratio, chase_ratio) and int(ally.id) < int(chase.get("id",2147483647))):
			chase = ally
			chase_ratio = ratio
		if distance <= float(stats.range) and (ratio < best_ratio or (is_equal_approx(ratio, best_ratio) and int(ally.id) < int(patient.get("id",2147483647)))):
			patient = ally
			best_ratio = ratio
	# 持续治疗当前病人，避免反复比较血量比例导致频繁换人。
	if attack_behavior.is_continuous():
		var current = sim.by_id.get(attack_behavior.current_target(unit))
		if current!=null and int(current.team)==int(unit.team) and float(current.hp)>0 and float(current.hp)<float(sim.catalog[current.kind].hp) and not sim.is_structure(current) and weapon.target_layers.has(sim.catalog[current.kind].get("layer","ground")) and unit.pos.distance_to(current.pos)<=float(weapon.range):patient=current
	if not patient.is_empty():
		goal = unit.pos
		if attack_behavior.is_continuous():
			attack_behavior.tick({"sim":sim,"unit":unit,"dt":dt,"heals":heals,"healing_energy_per_period":float(config.get("energy_cost",0))},unit,weapon,patient,int(patient.id),true)
		elif float(unit.cooldown) <= 0.00001 and pay_energy(sim):
			unit.cooldown = float(stats.interval)
			heals[patient.id] = float(heals.get(patient.id,0.0)) + float(config.get("heal",weapon.healing))
			sim.events.append({"type":"heal","from":unit.pos,"to":patient.pos,"kind":unit.kind,"team":unit.team})
	elif not chase.is_empty() and not front.is_empty():
		goal = chase.pos
	# 即使正在治疗，也必须退回前排后方或远离逼近的敌军。
	goal.x = minf(float(goal.x) * forward, safe_x) * forward
	goal = sim.clamp_to_field(goal)
	moves[unit.id] = unit.pos.move_toward(goal, sim._movement_speed(unit) * dt)

func _init() -> void: priority=0
func before_target(ctx: Dictionary) -> bool:
	ctx.sim._tick_attack_clock(owner,ctx.dt)
	step(ctx.sim,owner,ctx.dt,ctx.heals,ctx.moves)
	return true
