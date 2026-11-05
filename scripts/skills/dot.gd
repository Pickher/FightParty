extends "res://scripts/skills/skill.gd"
const Status = preload("res://scripts/skills/services/status_service.gd")

func _init() -> void: hit_effect=true
func on_hit(ctx: Dictionary) -> void: Status.queue_dot(ctx.sim,ctx.victim,config,owner)
