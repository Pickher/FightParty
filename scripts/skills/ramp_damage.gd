extends "res://scripts/skills/skill.gd"

func multiplier(sim, unit: Dictionary, target: Dictionary) -> float:
	if config.is_empty():return 1.0
	if int(state.get("ramp_target",0))!=int(target.id) or sim.tick-int(state.get("ramp_last_tick",0))>ceili(float(sim.catalog[unit.kind].interval)*float(sim.rules.tick_rate))+2:
		state.ramp_target=target.id
		state.ramp_start_tick=sim.tick
	state.ramp_last_tick=sim.tick
	return minf(float(config.max_multiplier),1.0+float(config.per_second)*float(sim.tick-int(state.ramp_start_tick))/float(sim.rules.tick_rate))

func damage_multiplier(ctx: Dictionary) -> float: return multiplier(ctx.sim,owner,ctx.target)

func _init() -> void:
	view_fields=["ramp_target","ramp_start_tick","ramp_last_tick"]
