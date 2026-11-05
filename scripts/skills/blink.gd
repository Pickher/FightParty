extends "res://scripts/skills/skill.gd"

func step(sim, unit: Dictionary, target: Dictionary, dt: float, moves: Dictionary) -> bool:
	var stats: Dictionary = sim.catalog[unit.kind]
	if sim.tick<int(unit.get("root_until_tick",0)):return false
	if not config.is_empty() and not target.is_empty() and sim.tick>=int(state.get("blink_ready_tick",0)) and float(unit.shield)<=float(stats.get("shield",0))*float(config.shield_ratio):
		var away: Vector2 = (unit.pos-target.pos).normalized()
		if away==Vector2.ZERO:away=Vector2.LEFT if unit.team==0 else Vector2.RIGHT
		moves[unit.id]=sim.clamp_to_field(unit.pos+away*float(config.distance))
		sim.teleports[unit.id]=true
		state.blink_ready_tick=sim.tick+ceili(float(config.cooldown)*float(sim.rules.tick_rate))
		sim.events.append({"type":"mobility","from":unit.pos,"to":moves[unit.id],"team":unit.team,"kind":unit.kind})
		return true
	return false

func _init() -> void:
	priority=60
	view_fields=["blink_ready_tick"]
func before_action(ctx: Dictionary) -> void:
	if ctx.can_act and not ctx.handled:ctx.handled=step(ctx.sim,owner,ctx.target,ctx.dt,ctx.moves)
