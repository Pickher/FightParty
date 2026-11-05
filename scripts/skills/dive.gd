extends "res://scripts/skills/skill.gd"

func step(sim, unit: Dictionary, target: Dictionary, dt: float, moves: Dictionary) -> bool:
	var stats: Dictionary = sim.catalog[unit.kind]
	if sim.tick<int(unit.get("root_until_tick",0)):return false
	if not config.is_empty() and not target.is_empty() and sim.tick>=int(state.get("dive_ready_tick",0)):
		var back: Dictionary = {}
		var score := -1.0
		for enemy in sim.nearby_team(unit.pos,float(config.range),1-int(unit.team)):
			if enemy.hp<=0 or sim.is_structure(enemy) or not sim._can_hit_unit(unit,enemy,stats):continue
			var value: float = float(sim.catalog[enemy.kind].range)
			if value>score or (is_equal_approx(value,score) and int(enemy.id)<int(back.get("id",2147483647))):
				back=enemy
				score=value
		if not back.is_empty():
			if not pay_energy(sim): return false
			var behind: float = 1.0 if unit.team==0 else -1.0
			moves[unit.id]=sim.clamp_to_field(back.pos+Vector2(behind*0.7,0))
			sim.teleports[unit.id]=true
			state.dive_ready_tick=sim.tick+ceili(float(config.cooldown)*float(sim.rules.tick_rate))
			unit.locked_target_id=0
			sim.events.append({"type":"mobility","from":unit.pos,"to":moves[unit.id],"team":unit.team,"kind":unit.kind})
			return true
	return false

func _init() -> void:
	priority=60
	view_fields=["dive_ready_tick"]
func before_action(ctx: Dictionary) -> void:
	if ctx.can_act and not ctx.handled:ctx.handled=step(ctx.sim,owner,ctx.target,ctx.dt,ctx.moves)

func discovery_radius(_sim, value: float) -> float: return maxf(value,float(config.range))
