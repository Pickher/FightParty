extends "res://scripts/skills/skill.gd"
const Slow = preload("res://scripts/skills/services/slow_service.gd")

func _init() -> void: hit_effect=true

func on_hit(ctx: Dictionary) -> void:
	var weapon_modes: Array = config.get("weapon_modes", [])
	if not weapon_modes.is_empty() and not weapon_modes.has(ctx.weapon.get("id", "")):
		return
	for tag in config.get("exclude_tags", []):
		if ctx.sim.has_tag(ctx.victim, tag):
			return
	Slow.queue_hit(ctx.sim, ctx.victim, config, ctx.pending_slows)
