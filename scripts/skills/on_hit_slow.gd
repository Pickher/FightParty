extends "res://scripts/skills/skill.gd"
const Slow = preload("res://scripts/skills/services/slow_service.gd")

func _init() -> void: hit_effect=true
func on_hit(ctx: Dictionary) -> void: Slow.queue_hit(ctx.sim,ctx.victim,config,ctx.pending_slows)
