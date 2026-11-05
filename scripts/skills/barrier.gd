extends "res://scripts/skills/skill.gd"

func barrier_absorb(sim, unit: Dictionary, raw: float) -> float:
	if config.is_empty() or raw<=0:return raw
	if sim.tick>=int(state.get("barrier_until_tick",0)):
		state.barrier_hp=0.0
		if sim.tick>=int(state.get("barrier_ready_tick",0)):
			state.barrier_hp=float(config.amount)
			state.barrier_until_tick=sim.tick+ceili(float(config.duration)*float(sim.rules.tick_rate))
			state.barrier_ready_tick=sim.tick+ceili(float(config.cooldown)*float(sim.rules.tick_rate))
	var absorbed: float = minf(raw,float(state.get("barrier_hp",0)))
	state.barrier_hp=float(state.get("barrier_hp",0))-absorbed
	return raw-absorbed

func absorb(ctx: Dictionary, raw: float) -> float: return barrier_absorb(ctx.sim,owner,raw)

func _init() -> void:
	view_fields=["barrier_until_tick","barrier_ready_tick","barrier_hp"]
