extends "res://scripts/skills/skill.gd"
## 空中双束医疗。独立于保留的医疗兵组件，不把医疗机变成攻击单位。
const Beams = preload("res://scripts/skills/services/beam_service.gd")

func _init() -> void:
	priority=0
	view_fields=["medical_targets"]

func _patient(sim, ally: Dictionary) -> bool:
	if int(ally.team)!=int(owner.team) or int(ally.id)==int(owner.id) or float(ally.hp)<=0 or sim.is_structure(ally):return false
	var stats: Dictionary = sim.catalog[ally.kind]
	if not stats.get("tags",[]).has("biological"):return false
	if stats.get("tags",[]).has("hallucination"):return false
	return float(ally.hp)<float(stats.hp)-0.00001

func before_target(ctx: Dictionary) -> bool:
	var sim = ctx.sim
	var unit: Dictionary = owner
	var weapon: Dictionary = sim._weapon_stats(unit)
	var radius: float = float(config.get("acquire_range",weapon.range))
	var candidates: Array = []
	for ally in sim.nearby_team(unit.pos,radius,int(unit.team)):
		if _patient(sim,ally):candidates.append(ally)
	candidates.sort_custom(func(a,b):
		var ar: float = float(a.hp)/float(sim.catalog[a.kind].hp)
		var br: float = float(b.hp)/float(sim.catalog[b.kind].hp)
		if not is_equal_approx(ar,br):return ar<br
		var ad: float = unit.pos.distance_squared_to(a.pos)
		var bd: float = unit.pos.distance_squared_to(b.pos)
		return ad<bd if not is_equal_approx(ad,bd) else int(a.id)<int(b.id)
	)
	var count: int = maxi(1,int(config.get("max_targets",2)))
	if not state.has("beams"):
		state.beams=[]
		for i in range(count):state.beams.append({})
	var chosen: Array = []
	var used: Dictionary = {}
	# 保留仍有效且在治疗范围内的锁，避免低血量排序抖动重复等待。
	for clock_owner in state.beams:
		var target_id: int = int(Beams.state_for(clock_owner).target_id)
		var previous = sim.by_id.get(target_id)
		if previous!=null and _patient(sim,previous) and unit.pos.distance_to(previous.pos)<=float(weapon.range) and not used.has(target_id):
			chosen.append(previous)
			used[target_id]=true
		else:chosen.append({})
	for i in range(count):
		if not chosen[i].is_empty():continue
		for ally in candidates:
			if used.has(ally.id) or unit.pos.distance_to(ally.pos)>float(weapon.range):continue
			chosen[i]=ally
			used[ally.id]=true
			break
	state.medical_targets=[]
	var has_patient := false
	for i in range(count):
		var patient: Dictionary = chosen[i]
		if patient.is_empty():
			# An interrupted beam must not bank healing time for a later target.
			Beams.state_for(state.beams[i]).accumulator=0.0
			continue
		has_patient=true
		state.medical_targets.append(int(patient.id))
		Beams.apply({"sim":sim,"unit":unit,"dt":ctx.dt,"heals":ctx.heals,"healing_energy_per_period":float(config.get("energy_cost",0))},state.beams[i],weapon,patient,int(patient.id),true)
	var forward: float = 1.0 if int(unit.team)==0 else -1.0
	var front: Dictionary = {}
	for ally in sim.units:
		if int(ally.team)!=int(unit.team) or float(ally.hp)<=0 or sim.is_structure(ally) or float(sim.catalog[ally.kind].damage)<=0:continue
		if front.is_empty() or float(ally.pos.x)*forward>float(front.pos.x)*forward:front=ally
	var goal := Vector2(sim.mirror_x(unit.team,float(sim.rules.layout.spawn_x)),unit.pos.y)
	if not front.is_empty():goal=Vector2(float(front.pos.x)-float(config.follow_distance)*forward,front.pos.y)
	var safe_x: float = goal.x*forward
	if has_patient:goal=unit.pos
	elif not candidates.is_empty() and not front.is_empty():goal=candidates[0].pos
	for enemy in sim._nearby(unit.pos,radius):
		if int(enemy.team)==int(unit.team) or float(enemy.hp)<=0:continue
		# 不因纯地面武器逃跑，但对所有能对空的攻击模式避战。
		for mode in sim.catalog[enemy.kind].get("attack_modes",[]):
			if float(mode.get("damage",0))>0 and mode.get("target_layers",[]).has("air"):
				safe_x=minf(safe_x,float(enemy.pos.x)*forward-float(config.danger_distance))
				break
	goal.x=minf(goal.x*forward,safe_x)*forward
	ctx.moves[unit.id]=unit.pos.move_toward(sim.clamp_to_field(goal),sim._movement_speed(unit)*float(ctx.dt))
	return true
