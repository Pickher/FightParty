extends "res://scripts/skills/skill.gd"

const Areas = preload("res://scripts/skills/services/area_service.gd")

func _init() -> void:
	priority = 8

func before_target(ctx: Dictionary) -> bool:
	var sim = ctx.sim
	if owner.has("channeling_skill") or sim.tick < int(state.get("ready_tick", 0)) or not can_pay_energy(sim):
		return false
	var target := _find_target(sim)
	if target.is_empty() or not pay_energy(sim):
		return false
	var enemy_team := 1 - int(owner.team)
	var reservation_end: int = sim.tick + ceili(float(config.reservation_seconds) * float(sim.rules.tick_rate))
	for enemy in sim.nearby_team(target.pos, float(config.radius), enemy_team):
		if _visible_candidate(sim, enemy):
			enemy.emp_reserved_until_tick = reservation_end

	var pulse := config.duplicate()
	pulse.effect = "emp"
	pulse.projectile = true
	pulse.target_layers = ["ground", "air"]
	pulse.attacks_structures = true
	pulse.delay = owner.pos.distance_to(target.pos) / float(config.projectile_speed)
	Areas.launch(sim, owner, target.pos, pulse)
	state.ready_tick = sim.tick + ceili(float(config.cooldown) * float(sim.rules.tick_rate))
	owner.locked_target_id = 0
	sim.mark_engaged(owner)
	sim._tick_attack_clock(owner, ctx.dt)
	sim.events.append({"type":"skill_used", "skill":id, "id":owner.id, "target":target.id, "team":owner.team})
	return true

func _visible_candidate(sim, unit: Dictionary) -> bool:
	return (unit.hp > 0 and sim.tick >= int(unit.get("invulnerable_until_tick", 0))
			and not sim.has_tag(unit, "hallucination") and sim.is_visible_to(int(owner.team), unit))

func _find_target(sim) -> Dictionary:
	var enemy_team := 1 - int(owner.team)
	var minimum := int(config.min_targets)
	var threshold := float(config.min_vital)
	var radius := float(config.radius)
	var reach := float(config.range)
	var centers: Array = []
	var charged: Dictionary = {}
	for enemy in sim.nearby_team(owner.pos, reach + radius, enemy_team):
		if not _visible_candidate(sim, enemy):
			continue
		if maxf(float(enemy.shield), float(enemy.energy)) >= threshold:
			charged[enemy.id] = true
		if owner.pos.distance_squared_to(enemy.pos) <= reach * reach and sim.tick >= int(enemy.get("emp_reserved_until_tick", 0)):
			centers.append(enemy)
	# 纯无盾、无能量的兵群无需逐个试算落点。
	if charged.size() < minimum:
		return {}
	var best: Dictionary = {}
	var best_count := minimum - 1
	var best_distance := INF
	for candidate in centers:
		var count := 0
		for neighbor in sim.nearby_team(candidate.pos, radius, enemy_team):
			if charged.has(neighbor.id):
				count += 1
		if count < minimum or count < best_count:
			continue
		var distance: float = owner.pos.distance_squared_to(candidate.pos)
		if count == best_count and (distance > best_distance or (distance == best_distance and int(candidate.id) >= int(best.id))):
			continue
		best = candidate
		best_count = count
		best_distance = distance
	return best
