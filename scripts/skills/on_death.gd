extends "res://scripts/skills/skill.gd"
const Summoning = preload("res://scripts/skills/services/summon_service.gd")
const Areas = preload("res://scripts/skills/services/area_service.gd")

func on_death(ctx: Dictionary) -> void:
	var sim = ctx.sim
	var unit: Dictionary = owner
	if config.has("summon"):Summoning.queue(sim,unit,str(config.summon),int(config.count),unit.pos,{"lifetime":15})
	if config.has("area"):
		var area: Dictionary = config.area.duplicate(true)
		if area.has("dot"):
			area.damage=float(area.dot.per_second)*float(area.dot.duration)
			area.duration=area.dot.duration
		area.delay=0
		Areas.launch(sim,unit,unit.pos,area)
