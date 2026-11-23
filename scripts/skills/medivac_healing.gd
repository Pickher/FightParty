extends "res://scripts/skills/skill.gd"
## 医疗运输机的主治疗指令和自动副束共用伤员标记，各自保留下一次治疗的时间。
const Beams = preload("res://scripts/skills/services/beam_service.gd")
const TIME_EPSILON := 0.000000001

func _init() -> void:
	priority = 0
	view_fields = ["medical_targets"]

func on_spawn(_sim) -> void:
	state.beams = []
	state.next_scan = 0.0
	state.medical_targets = []

func _patient(ctx: Dictionary, ally: Dictionary) -> bool:
	var sim = ctx.sim
	if int(ally.team) != int(owner.team) or ally.id == owner.id or ally.hp <= 0 or sim.is_structure(ally):
		return false
	var stats: Dictionary = sim.catalog[ally.kind]
	if not stats.tags.has("biological") or stats.tags.has("hallucination") or sim.tick < int(ally.get("invulnerable_until_tick", 0)):
		return false
	return float(ally.hp) + float(ctx.heals.get(ally.id, 0)) < float(stats.hp) - 0.000001

func on_frame(ctx: Dictionary) -> void:
	# 先由所有医疗机登记存续的治疗。出兵顺序较早的空闲医疗机也不会抢走已有伤员。
	if not ctx.has("medivac_claims"):
		ctx.medivac_claims = {}
		ctx.medivac_idle = []
	if owner.hp <= 0:
		state.beams.clear()
		state.medical_targets.clear()
		return
	var sim = ctx.sim
	var weapon: Dictionary = sim._weapon_stats(owner)
	var powered: bool = sim.can_spend_energy(owner, float(config.sustain_energy))
	for beam in state.beams.duplicate():
		var patient: Dictionary = sim.by_id.get(beam.target_id, {})
		var radius: float = float(config.secondary_range) if beam.awaiting_range_check else float(weapon.range)
		if powered and not patient.is_empty() and _patient(ctx, patient) and owner.pos.distance_to(patient.pos) <= radius and not ctx.medivac_claims.has(patient.id):
			ctx.medivac_claims[patient.id] = owner.id
		else:
			state.beams.erase(beam)
	if state.beams.is_empty() and sim.can_spend_energy(owner, float(config.start_energy)):
		ctx.medivac_idle.append(self)

func _best_patient(ctx: Dictionary, candidates: Array, radius: float, by_fraction: bool) -> Dictionary:
	var best: Dictionary = {}
	var best_life := INF
	var best_distance := INF
	for ally in candidates:
		if ctx.medivac_claims.has(ally.id) or not _patient(ctx, ally):
			continue
		var distance: float = owner.pos.distance_squared_to(ally.pos)
		if distance > radius * radius:
			continue
		var life := float(ally.hp) + float(ctx.heals.get(ally.id, 0))
		if by_fraction:
			life /= float(ctx.sim.catalog[ally.kind].hp)
		if life > best_life:
			continue
		if life == best_life:
			if distance > best_distance or (distance == best_distance and int(ally.id) >= int(best.id)):
				continue
		best = ally
		best_life = life
		best_distance = distance
	return best

func _start_beam(ctx: Dictionary, patient: Dictionary, at: float, period: float, secondary: bool) -> void:
	ctx.medivac_claims[patient.id] = owner.id
	state.beams.append({"target_id":patient.id, "next_pulse":at + period, "awaiting_range_check":secondary})

func _issue_primary(ctx: Dictionary) -> void:
	var sim = ctx.sim
	var weapon: Dictionary = sim._weapon_stats(owner)
	var radius := float(weapon.range)
	var nearby: Array = sim.nearby_team(owner.pos, radius, int(owner.team))
	var primary := _best_patient(ctx, nearby, radius, true)
	if not primary.is_empty():
		var now := float(sim.tick - 1) / float(sim.rules.tick_rate)
		_start_beam(ctx, primary, now, float(weapon.delivery.tick_interval), false)
		state.next_scan = now + float(config.scan_interval)

func _advance_healing(ctx: Dictionary, candidates: Array, weapon: Dictionary) -> void:
	var sim = ctx.sim
	var now := float(sim.tick - 1) / float(sim.rules.tick_rate)
	var end := now + float(ctx.dt)
	var period := float(weapon.delivery.tick_interval)
	var scan_interval := float(config.scan_interval)
	if period <= 0.0 or scan_interval <= 0.0:
		return
	# 本步中途停束时，目标标记保留到下一步开始，避免另一架机按更早的步内扫描时间接手。
	while not state.beams.is_empty():
		var event_time := float(state.next_scan)
		for beam in state.beams:
			event_time = minf(event_time, float(beam.next_pulse))
		if event_time > end + TIME_EPSILON:
			break
		for beam in state.beams.duplicate():
			if float(beam.next_pulse) > event_time + TIME_EPSILON:
				continue
			var patient: Dictionary = sim.by_id[beam.target_id]
			if owner.pos.distance_to(patient.pos) > float(weapon.range) or not _patient(ctx, patient):
				state.beams.erase(beam)
				continue
			beam.awaiting_range_check = false
			beam.next_pulse = float(beam.next_pulse) + period
			var paid := Beams.heal_tick(ctx, patient.id, float(weapon.healing), float(config.energy_cost))
			if not paid or not sim.can_spend_energy(owner, float(config.sustain_energy)):
				state.beams.clear()
				return
			if not _patient(ctx, patient):
				state.beams.erase(beam)
		if float(state.next_scan) <= event_time + TIME_EPSILON:
			state.next_scan = float(state.next_scan) + scan_interval
			if not state.beams.is_empty() and state.beams.size() < int(config.max_targets) and sim.can_spend_energy(owner, float(config.start_energy)):
				var secondary := _best_patient(ctx, candidates, float(config.secondary_range), false)
				if not secondary.is_empty():
					_start_beam(ctx, secondary, event_time, period, true)

func before_target(ctx: Dictionary) -> bool:
	# 本步起点先让每架空闲机认领主目标，再开始步内的副束扫描。
	for healer in ctx.medivac_idle:
		healer._issue_primary(ctx)
	ctx.medivac_idle.clear()
	if owner.hp <= 0:
		return true
	var sim = ctx.sim
	var weapon: Dictionary = sim._weapon_stats(owner)
	var radius := float(config.acquire_range)
	var candidates: Array = sim.nearby_team(owner.pos, radius, int(owner.team))
	_advance_healing(ctx, candidates, weapon)
	state.medical_targets.clear()
	for beam in state.beams:
		var patient: Dictionary = sim.by_id[beam.target_id]
		state.medical_targets.append(patient.id)
		Beams.show_beam(sim, owner, weapon, patient, patient.id, true)
	_move_with_allies(ctx, candidates, weapon)
	return true

func _move_with_allies(ctx: Dictionary, candidates: Array, weapon: Dictionary) -> void:
	var sim = ctx.sim
	var forward := 1.0 if int(owner.team) == 0 else -1.0
	var front: Dictionary = {}
	for ally in sim.units:
		if ally.team != owner.team or ally.hp <= 0 or sim.is_structure(ally) or float(sim.catalog[ally.kind].damage) <= 0:
			continue
		if front.is_empty() or float(ally.pos.x) * forward > float(front.pos.x) * forward:
			front = ally
	var goal := Vector2(sim.mirror_x(owner.team, float(sim.rules.layout.spawn_x)), owner.pos.y)
	if not front.is_empty():
		goal = Vector2(float(front.pos.x) - float(config.follow_distance) * forward, front.pos.y)
	var safe_x: float = goal.x * forward if not front.is_empty() else INF
	if not state.beams.is_empty():
		# 施放不中断飞行；尽量跟上前排并把当前伤员留在治疗距离内。
		var patient: Dictionary = sim.by_id[state.beams[0].target_id]
		goal = patient.pos.move_toward(goal, float(weapon.range))
	elif sim.can_spend_energy(owner, float(config.start_energy)):
		var next_patient := _best_patient(ctx, candidates, float(config.acquire_range), true)
		if not next_patient.is_empty():
			goal = next_patient.pos
	for enemy in sim._nearby(owner.pos, float(config.acquire_range)):
		if enemy.team == owner.team or enemy.hp <= 0:
			continue
		for mode in sim.catalog[enemy.kind].get("attack_modes", []):
			if float(mode.get("damage", 0)) > 0 and mode.get("target_layers", []).has("air"):
				safe_x = minf(safe_x, float(enemy.pos.x) * forward - float(config.danger_distance))
				break
	goal.x = minf(goal.x * forward, safe_x) * forward
	ctx.moves[owner.id] = owner.pos.move_toward(sim.clamp_to_field(goal), sim._movement_speed(owner) * float(ctx.dt))
