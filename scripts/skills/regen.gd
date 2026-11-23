extends "res://scripts/skills/skill.gd"

func recover(sim, unit: Dictionary, dt: float) -> void:
	var stats: Dictionary = sim.catalog[unit.kind]
	var recoverable_hp := float(stats.hp) * clampf(float(config.get("max_health_ratio", 1.0)), 0.0, 1.0)
	if float(unit.hp) >= recoverable_hp:
		return
	if sim.tick - int(unit.last_hit_tick) >= int(float(config.delay) * float(sim.rules.tick_rate)):
		unit.hp = minf(recoverable_hp, float(unit.hp) + float(config.per_second) * dt)

func on_survived(ctx: Dictionary) -> void: recover(ctx.sim,owner,ctx.dt)
