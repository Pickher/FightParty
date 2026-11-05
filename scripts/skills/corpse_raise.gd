extends "res://scripts/skills/skill.gd"
const Summoning = preload("res://scripts/skills/services/summon_service.gd")

func on_unit_death(ctx: Dictionary) -> void:
	var sim = ctx.sim
	var dead: Dictionary = ctx.dead
	if bool(dead.get("summoned",false)) or float(owner.hp)<=0 or sim.self_destruct.has(owner.id):return
	if dead.pos.distance_to(owner.pos)>float(config.radius):return
	var roll: int = posmod(int(dead.id)*1103515245+int(owner.id)*12345+sim.tick,10000)
	if roll<int(float(config.chance)*10000):Summoning.queue(sim,owner,str(config.summon),1,dead.pos,config)
