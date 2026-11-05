extends "res://scripts/skills/skill.gd"
const Deployment = preload("res://scripts/skills/services/deployment_service.gd")

func _init() -> void:
	priority=30
	view_fields=["siege_state","siege_until_tick","siege_scan_tick","siege_scan_ids"]
func on_spawn(_sim) -> void: Deployment.initialize(state)
func before_action(ctx: Dictionary) -> void:
	if not ctx.can_act:return
	ctx.can_act=Deployment.can_act(ctx.sim,owner,state,ctx.distance<=ctx.reach,ctx.target.is_empty() and ctx.distance<=ctx.reach and bool(ctx.weapon.get("attacks_base",true)),ctx.motion,{"config":config})
