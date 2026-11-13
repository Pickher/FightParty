extends "res://scripts/skills/skill.gd"

func step(sim, unit: Dictionary, target: Dictionary, dt: float, moves: Dictionary) -> bool:
	var stats: Dictionary = sim.catalog[unit.kind]
	if sim.tick<int(unit.get("root_until_tick",0)):return false
	var threshold: float = float(config.get("shield_threshold",float(stats.get("shield",0))*float(config.get("shield_ratio",0.35))))
	var low_shields: bool = float(unit.shield)<threshold if config.has("shield_threshold") else float(unit.shield)<=threshold
	var new_damage: bool = not bool(config.get("damage_trigger",false)) or int(unit.get("last_hit_tick",-1000000))>int(state.get("handled_hit_tick",-1000000))
	if not config.is_empty() and not target.is_empty() and new_damage and sim.tick>=int(state.get("blink_ready_tick",0)) and low_shields:
		if not pay_energy(sim): return false
		var away: Vector2 = (unit.pos-target.pos).normalized()
		if away==Vector2.ZERO:away=Vector2.LEFT if unit.team==0 else Vector2.RIGHT
		moves[unit.id]=sim.clamp_to_field(unit.pos+away*float(config.distance))
		sim.teleports[unit.id]=true
		state.invulnerable_until_tick=sim.tick+ceili(float(config.get("invulnerable_seconds",0))*float(sim.rules.tick_rate))
		state.handled_hit_tick=int(unit.get("last_hit_tick",sim.tick))
		state.blink_ready_tick=sim.tick+ceili(float(config.cooldown)*float(sim.rules.tick_rate))
		sim.events.append({"type":"mobility","from":unit.pos,"to":moves[unit.id],"team":unit.team,"kind":unit.kind})
		return true
	return false

func _init() -> void:
	priority=60
	view_fields=["blink_ready_tick"]
func before_action(ctx: Dictionary) -> void:
	if ctx.can_act and not ctx.handled:ctx.handled=step(ctx.sim,owner,ctx.target,ctx.dt,ctx.moves)

func absorb(ctx: Dictionary, raw: float) -> float:
	return 0.0 if ctx.sim.tick<int(state.get("invulnerable_until_tick",0)) else raw
