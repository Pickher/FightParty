extends "res://scripts/skills/skill.gd"

func step(sim, unit: Dictionary, target: Dictionary, dt: float, moves: Dictionary) -> bool:
	var stats: Dictionary = sim.catalog[unit.kind]
	if sim.tick<int(unit.get("root_until_tick",0)):return false
	if config.is_empty() or target.is_empty():return false
	var distance: float = unit.pos.distance_to(target.pos)
	if distance<=float(stats.range):
		state.charge_until_tick=0
		return false
	if sim.tick>=int(state.get("charge_ready_tick",0)) and distance<=float(config.range):
		state.charge_until_tick=sim.tick+ceili(float(config.duration)*float(sim.rules.tick_rate))
		state.charge_ready_tick=sim.tick+ceili(float(config.cooldown)*float(sim.rules.tick_rate))
	if sim.tick<int(state.get("charge_until_tick",0)):
		moves[unit.id]=sim.clamp_to_field(unit.pos.move_toward(target.pos,minf(distance-float(stats.range),sim._movement_speed(unit)*float(config.speed_multiplier)*dt)))
		return true
	return false

func _init() -> void:
	priority=60
	view_fields=["charge_until_tick","charge_ready_tick"]
func before_action(ctx: Dictionary) -> void:
	if ctx.can_act and not ctx.handled:ctx.handled=step(ctx.sim,owner,ctx.target,ctx.dt,ctx.moves)

func discovery_radius(_sim, value: float) -> float: return maxf(value,float(config.range))
