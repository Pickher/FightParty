extends RefCounted
## 基地只用一份生命池；防御层、攻击周期均为可保存的纯字典状态。
const AttackCycle = preload("res://scripts/units/attack_cycle.gd")
const Sequences = preload("res://scripts/skills/services/attack_sequence_service.gd")
const AttackTypes = preload("res://scripts/attacks/attack_registry.gd")

static func create(active: bool) -> Dictionary:
	var state := AttackCycle.create()
	state.active = active
	return state

## 必须先判定防御层破坏，再回血；达到核心生命上限便永久失效。
static func update_phase(sim, team: int) -> void:
	var state: Dictionary = sim.base_defenses[team]
	if bool(state.active) and float(sim.bases[team]) <= float(sim.rules.base_hp):
		state.active = false
		state.merge(AttackCycle.create(), true)
		sim.events.append({"type":"base_defense_lost","team":team,"pos":sim.base_pos(team)})

static func settle(sim, team: int, damage: float, dt: float) -> void:
	sim.bases[team] = maxf(0.0, float(sim.bases[team]) - damage)
	if damage > 0:
		sim.events.append({"type":"base_damage","team":team,"amount":damage})
	update_phase(sim, team)
	# 归零的基地不能被同一步回血救活，也不能在后续恢复防御层。
	if float(sim.bases[team]) <= 0: return
	var regen: float = float(sim.catalog.gate_tower.health_regen) if sim.base_has_defense(team) else float(sim.rules.base_regen_per_second)
	sim.bases[team] = minf(sim.base_max_hp(team), float(sim.bases[team]) + regen * dt)

static func valid_target(sim, source: Dictionary, target, weapon: Dictionary) -> bool:
	return target != null and not target.is_empty() and float(target.hp) > 0 and target.team != source.team and source.pos.distance_to(target.pos) <= float(weapon.range) and sim._can_hit_unit(source, target, weapon)

static func fire(sim, frame: Dictionary) -> void:
	var weapon: Dictionary = sim.definitions.gate_tower.primary_weapon_data
	var attack_behavior := AttackTypes.for_weapon(weapon)
	for team in range(2):
		update_phase(sim, team)
		if not sim.base_has_defense(team): continue
		var state: Dictionary = sim.base_defenses[team]
		# 不加入 units，避免基地和防御塔被范围攻击重复扣血。
		var source := {"id":-team-1,"kind":"gate_tower","team":team,"pos":sim.base_pos(team)}
		AttackCycle.tick_attack(state, float(frame.dt), 1.0)
		var target = sim.by_id.get(int(state.locked_target_id))
		if not valid_target(sim, source, target, weapon):
			state.locked_target_id = 0
			target = {}
			var best_distance := INF
			for candidate in sim.nearby_team(source.pos, float(weapon.range), 1-team):
				if not valid_target(sim, source, candidate, weapon): continue
				var distance: float = source.pos.distance_squared_to(candidate.pos)
				if distance < best_distance or (is_equal_approx(distance, best_distance) and int(candidate.id) < int(target.get("id",2147483647))):
					target = candidate
					best_distance = distance
		var eligible: bool = not target.is_empty()
		var target_id: int = int(target.id) if eligible else 0
		if attack_behavior.is_continuous():
			if eligible:
				var beam: Dictionary = frame.duplicate()
				beam.unit=source
				beam.weapon=weapon
				beam.target=target
				attack_behavior.tick(beam,state,weapon,target,target_id)
			continue
		if not AttackCycle.ready_to_fire(state, weapon, target_id, eligible): continue
		state.locked_target_id = target_id
		var shot: Dictionary = frame.duplicate()
		shot.unit = source
		shot.target = target
		shot.weapon = weapon
		shot.goal = target.pos
		shot.damage_multiplier = 1.0
		Sequences.launch(shot,state,-1,team)
