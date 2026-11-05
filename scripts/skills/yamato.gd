extends "res://scripts/skills/skill.gd"

func step(sim, unit: Dictionary, hits: Dictionary) -> bool:
	var rate: float = float(sim.rules.tick_rate)
	if state.has("yamato_target"):
		var target = sim.by_id.get(int(state.yamato_target))
		if target == null:
			state.erase("yamato_target")
			state.erase("yamato_fire_tick")
			return false
		if sim.tick < int(state.yamato_fire_tick):
			return true
		var raw: float = float(config.damage)
		var weapon := {"damage": raw}
		sim.queue_hit(hits, target, raw)
		var amount: float = sim.expected_damage(weapon, target)
		sim.damage_done[int(unit.team)] += amount
		sim.events.append({"type":"attack_hit","id":target.id,"kind":unit.kind,"team":unit.team,"strike":0,"amount":amount})
		sim.events.append({"type":"yamato","from":unit.pos,"to":target.pos,"kind":unit.kind,"team":unit.team})
		state.erase("yamato_target")
		state.erase("yamato_fire_tick")
		state.yamato_ready_tick = sim.tick + ceili(float(config.cooldown_seconds) * rate)
		return true
	if sim.tick < int(state.get("yamato_ready_tick", 0)):
		return false
	var target := _pick(sim, unit)
	if target.is_empty():
		return false
	if not pay_energy(sim): return false
	state.yamato_target = target.id
	state.yamato_fire_tick = sim.tick + ceili(float(config.channel_seconds) * rate)
	sim.events.append({"type":"yamato_charge","id":unit.id,"target":target.id,"team":unit.team})
	return true
func _pick(sim, unit: Dictionary) -> Dictionary:
	var reach: float = float(config.range)
	var weapon := {"target_layers": ["ground", "air"], "attacks_structures": true}
	var best: Dictionary = {}
	var best_unit := false
	var best_health := 0.0
	for other in sim._nearby(unit.pos, reach):
		if other.team == unit.team or not sim._can_hit_unit(unit, other, weapon):
			continue
		var health: float = float(other.hp) + float(other.get("shield", 0.0))
		if health < float(config.min_target_hp):
			continue
		var is_unit: bool = not sim.is_structure(other)
		var better: bool = best.is_empty() or (is_unit and not best_unit)
		if not better and is_unit == best_unit:
			better = health > best_health or (is_equal_approx(health, best_health) and int(other.id) < int(best.id))
		if better:
			best = other
			best_unit = is_unit
			best_health = health
	return best

## 引导进度 0～1；不在引导时为 -1。供界面画蓄能光圈。

func _init() -> void:
	priority=10
	view_fields=["yamato_target","yamato_fire_tick","yamato_ready_tick"]
func before_target(ctx: Dictionary) -> bool:
	if not step(ctx.sim,owner,ctx.hits):return false
	ctx.sim._tick_attack_clock(owner,ctx.dt)
	return true

static func charge(sim, unit: Dictionary) -> float:
	if not unit.has("yamato_target"):
		return -1.0
	var total: float = float(sim.catalog[unit.kind].skills.yamato.channel_seconds) * float(sim.rules.tick_rate)
	return clampf(1.0 - float(int(unit.yamato_fire_tick) - sim.tick) / total, 0.0, 1.0)
