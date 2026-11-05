extends "res://scripts/skills/skill.gd"
const Summons = preload("res://scripts/skills/services/summon_service.gd")

func step(sim, unit: Dictionary, target: Dictionary) -> void:
	if config.is_empty() or config.get("on","")!="timer" or sim.tick<int(state.get("summon_ready_tick",0)):return
	if bool(config.get("requires_combat",true)):
		var destination: Vector2 = sim.base_pos(1-int(unit.team)) if target.is_empty() else target.pos
		var reach: float = float(sim.catalog[unit.kind].range)+(float(sim.rules.layout.base_radius) if target.is_empty() else 0.0)
		if (target.is_empty() and not bool(config.get("allow_base",false))) or unit.pos.distance_to(destination)>reach:return
	var location: Vector2 = unit.pos if target.is_empty() else target.pos
	if bool(config.get("dependent",false)):location=unit.pos
	Summons.queue(sim,unit,str(config.kind),int(config.count),location,config)
	state.summon_ready_tick=sim.tick+ceili(float(config.interval)*float(sim.rules.tick_rate))

func _init() -> void:
	hit_effect=true
	view_fields=["summon_ready_tick"]
func on_target(ctx: Dictionary) -> void: step(ctx.sim,owner,ctx.target)
func on_hit(ctx: Dictionary) -> void:
	if config.get("on","")=="hit":Summons.queue(ctx.sim,owner,str(config.kind),int(config.count),ctx.victim.pos,config)
func after_attack(ctx: Dictionary) -> void:
	if ctx.target.is_empty() and config.get("on","")=="hit":Summons.queue(ctx.sim,owner,str(config.kind),int(config.count),ctx.goal,config)

func contributes_damage() -> bool: return true
