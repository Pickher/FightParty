extends RefCounted
## 行军决策使用步初快照。同波的兵只扫描一次；两边的决策与出兵和遍历顺序无关。
var travelers: Dictionary = {}
var cohorts: Array[Dictionary] = [{}, {}]

func prepare(sim) -> void:
	for team in cohorts:
		team.clear()
	if travelers.is_empty():
		return
	for unit in travelers.values():
		var team: Dictionary = cohorts[unit.team]
		if not team.has(unit.wave_id):
			team[unit.wave_id] = {"pace":INF, "front":-INF, "members":[], "contact":false}

	for unit in sim.units:
		var team: Dictionary = cohorts[unit.team]
		if team.is_empty() or not _is_wave_member(sim, unit):
			continue
		var group = team.get(unit.wave_id)
		if group != null:
			group.members.append(unit)
			var speed: float = sim.definitions[unit.kind].speed
			if speed > 0.0 and not travelers.has(unit.id):
				group.pace = minf(group.pace, speed)

		# 最近一秒正在还击或受伤的旧波残兵才是支援对象，静止建筑不占前线。
		var last_combat := maxi(int(unit.get("last_engaged_tick", -1000000)), int(unit.last_hit_tick))
		if sim.tick - last_combat > float(sim.rules.tick_rate):
			continue
		var progress: float = sim.mirror_x(unit.team, unit.pos.x)
		for cohort_wave in team:
			if cohort_wave > unit.wave_id:
				team[cohort_wave].front = maxf(team[cohort_wave].front, progress)

	# 只为当前仍需集体行军的波次计算全队接触；支援车辆单独用自身视距判断。
	for unit in travelers.values():
		var group: Dictionary = cohorts[unit.team][unit.wave_id]
		if not supporting(sim, unit) and not group.members.is_empty():
			for member in group.members:
				if sees_ground_enemy(sim, member):
					group.contact = true
					break
			group.members.clear()

func _is_wave_member(sim, unit: Dictionary) -> bool:
	var stats: Dictionary = sim.catalog[unit.kind]
	return unit.hp > 0 and not sim.is_structure(unit) and not unit.get("summoned", false) and stats.get("status", "") != "summoned" and stats.get("unit_type", "unit") != "summon"

func supporting(sim, unit: Dictionary) -> bool:
	var group = cohorts[unit.team].get(unit.wave_id)
	return group != null and group.front > sim.mirror_x(unit.team, unit.pos.x)

func escort_speed(unit: Dictionary, fallback: float) -> float:
	var group = cohorts[unit.team].get(unit.wave_id)
	return minf(group.pace, fallback) if group != null else fallback

func detects_contact(sim, unit: Dictionary) -> bool:
	if supporting(sim, unit):
		return sees_ground_enemy(sim, unit)
	return cohorts[unit.team][unit.wave_id].contact

func sees_ground_enemy(sim, unit: Dictionary) -> bool:
	var weapon: Dictionary = sim._search_stats(unit)
	if not weapon.target_layers.has("ground") or (float(weapon.damage) <= 0 and not sim.skill_system.contributes_damage(unit)):
		return false
	var radius: float = sim.discovery_range(unit, weapon)
	var enemy := 1 - int(unit.team)
	if weapon.attacks_base and sim.bases[enemy] > 0 and unit.pos.distance_to(sim.base_pos(enemy)) <= radius + float(sim.rules.layout.base_radius):
		return true
	for other in sim.nearby_team(unit.pos, radius, enemy):
		if other.hp <= 0 or sim.catalog[other.kind].layer != "ground" or sim.tick < int(other.get("invulnerable_until_tick", 0)):
			continue
		if sim._can_hit_unit(unit, other, weapon):
			return true
	return false
