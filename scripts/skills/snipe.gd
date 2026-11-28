extends "res://scripts/skills/skill.gd"

func _init() -> void:
	priority = 9
	view_fields = ["channeling_skill"]

func on_spawn(_sim) -> void:
	state.charges = int(config.charges)

func on_frame(ctx: Dictionary) -> void:
	# 先登记所有在途狙杀。新施法者共用本步的目标表，命中或施法者死亡后标记自然失效。
	if not ctx.has("snipe_claims"):
		ctx.snipe_claims = {}
	if state.has("target_id"):
		ctx.snipe_claims[state.target_id] = true

func before_target(ctx: Dictionary) -> bool:
	var sim = ctx.sim
	if state.has("target_id"):
		_continue_channel(ctx)
	elif int(state.charges) > 0 and can_pay_energy(sim):
		var target := _find_target(sim, ctx.snipe_claims)
		if target.is_empty() or not pay_energy(sim):
			return false
		state.charges -= 1
		state.target_id = target.id
		state.finish_tick = sim.tick + ceili(float(config.channel_seconds) * float(sim.rules.tick_rate))
		state.channeling_skill = id
		ctx.snipe_claims[target.id] = true
		sim.events.append({"type":"skill_used", "skill":id, "id":owner.id, "target":target.id, "team":owner.team})
	else:
		return false
	sim.mark_engaged(owner)
	sim._tick_attack_clock(owner, ctx.dt)
	return true

func _valid_target(sim, unit: Dictionary) -> bool:
	return (unit.hp > 0 and int(unit.team) != int(owner.team) and not sim.is_structure(unit)
			and sim.has_tag(unit, "biological") and not sim.has_tag(unit, "hallucination")
			and sim.tick >= int(unit.get("invulnerable_until_tick", 0)) and sim.is_visible_to(int(owner.team), unit))

func _find_target(sim, claims: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for target in sim.nearby_team(owner.pos, float(config.range), 1 - int(owner.team)):
		if float(target.hp) < float(config.min_target_hp) or claims.has(target.id):
			continue
		if not _valid_target(sim, target):
			continue
		var distance: float = owner.pos.distance_squared_to(target.pos)
		if distance < best_distance or (distance == best_distance and int(target.id) < int(best.id)):
			best = target
			best_distance = distance
	return best

func _continue_channel(ctx: Dictionary) -> void:
	var sim = ctx.sim
	var target: Dictionary = sim.by_id.get(int(state.target_id), {})
	var keep_range := float(config.range) + float(config.range_slop)
	if target.is_empty() or not _valid_target(sim, target) or owner.pos.distance_squared_to(target.pos) > keep_range * keep_range:
		# 目标失效时返还能量。出手已用掉的专用充能不重置。
		sim.unit_model(owner).energy += float(config.energy_cost)
		ctx.snipe_claims.erase(state.target_id)
		_end_channel()
		return
	if sim.tick < int(state.finish_tick):
		return
	var damage := float(config.damage)
	sim.queue_hit(ctx.hits, target, damage, false, true, 0.0, 1.0, int(owner.id))
	sim.damage_done[int(owner.team)] += minf(damage, float(target.hp) + float(target.shield))
	sim.events.append({"type":"attack_hit", "id":target.id, "kind":owner.kind, "team":owner.team, "strike":0, "amount":damage})
	sim.events.append({"type":"snipe_impact", "id":target.id, "kind":owner.kind, "team":owner.team, "from":target.pos, "to":target.pos})
	# 留到本步的伤害队列结算，避免另一幽灵锁定同一步阵亡的单位。
	_end_channel()

func _end_channel() -> void:
	state.erase("channeling_skill")
	state.erase("target_id")
	state.erase("finish_tick")
