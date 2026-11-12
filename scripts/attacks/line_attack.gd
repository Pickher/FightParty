extends "res://scripts/attacks/attack_behavior.gd"
## 直线推进型：前向穿透或横向扫射；每段轨迹独立推进并判断实际命中。
const Lines = preload("res://scripts/skills/services/line_service.gd")

func type_id() -> String:
	return "line"

func emit(ctx: Dictionary, sequence: Dictionary) -> void:
	Lines.launch_strike(ctx.sim,ctx.unit,ctx.goal,ctx.weapon.delivery,ctx.weapon,int(ctx.strike),float(sequence.damage_multiplier),ctx.source_position,float(ctx.fire_offset),sequence.impact_skills)

func advance(sim, frame: Dictionary) -> void:
	Lines.advance(sim,float(frame.dt),frame.moves,frame.hits,frame.base_hits,frame.pending_slows)
