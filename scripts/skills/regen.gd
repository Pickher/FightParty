extends "res://scripts/skills/skill.gd"

func recover(sim, unit: Dictionary, dt: float) -> void:
	var stats: Dictionary = sim.catalog[unit.kind]
	if config == null or float(unit.hp) >= float(stats.hp):
		return
	if sim.tick - int(unit.last_hit_tick) >= int(float(config.delay) * float(sim.rules.tick_rate)):
		unit.hp = minf(float(stats.hp), float(unit.hp) + float(config.per_second) * dt)

func on_survived(ctx: Dictionary) -> void: recover(ctx.sim,owner,ctx.dt)
