extends RefCounted

## 闪烁为瞬移、冲锋为高速移动；根须阻止位移，绕后不包含隐身或无敌。
static func step(sim, unit: Dictionary, target: Dictionary, dt: float, moves: Dictionary) -> bool:
	var stats: Dictionary = sim.catalog[unit.kind]
	var skills: Dictionary = stats.get("skills",{})
	if sim.tick<int(unit.get("root_until_tick",0)):return false
	var blink: Dictionary = skills.get("blink",{})
	if not blink.is_empty() and not target.is_empty() and sim.tick>=int(unit.get("blink_ready_tick",0)) and float(unit.shield)<=float(stats.get("shield",0))*float(blink.shield_ratio):
		var away: Vector2 = (unit.pos-target.pos).normalized()
		if away==Vector2.ZERO:away=Vector2.LEFT if unit.team==0 else Vector2.RIGHT
		moves[unit.id]=sim.clamp_to_field(unit.pos+away*float(blink.distance))
		sim.teleports[unit.id]=true
		unit.blink_ready_tick=sim.tick+ceili(float(blink.cooldown)*float(sim.rules.tick_rate))
		sim.events.append({"type":"mobility","from":unit.pos,"to":moves[unit.id],"team":unit.team,"kind":unit.kind})
		return true
	var dive: Dictionary = skills.get("dive",{})
	if not dive.is_empty() and not target.is_empty() and sim.tick>=int(unit.get("dive_ready_tick",0)):
		var back: Dictionary = {}
		var score := -1.0
		for enemy in sim.nearby_team(unit.pos,float(dive.range),1-int(unit.team)):
			if enemy.hp<=0 or sim.is_structure(enemy) or not sim._can_hit_unit(unit,enemy,stats):continue
			var value: float = float(sim.catalog[enemy.kind].range)
			if value>score or (is_equal_approx(value,score) and int(enemy.id)<int(back.get("id",2147483647))):
				back=enemy
				score=value
		if not back.is_empty():
			var behind: float = 1.0 if unit.team==0 else -1.0
			moves[unit.id]=sim.clamp_to_field(back.pos+Vector2(behind*0.7,0))
			sim.teleports[unit.id]=true
			unit.dive_ready_tick=sim.tick+ceili(float(dive.cooldown)*float(sim.rules.tick_rate))
			unit.locked_target_id=0
			sim.events.append({"type":"mobility","from":unit.pos,"to":moves[unit.id],"team":unit.team,"kind":unit.kind})
			return true
	var charge: Dictionary = skills.get("charge",{})
	if charge.is_empty() or target.is_empty():return false
	var distance: float = unit.pos.distance_to(target.pos)
	if distance<=float(stats.range):
		unit.charge_until_tick=0
		return false
	if sim.tick>=int(unit.get("charge_ready_tick",0)) and distance<=float(charge.range):
		unit.charge_until_tick=sim.tick+ceili(float(charge.duration)*float(sim.rules.tick_rate))
		unit.charge_ready_tick=sim.tick+ceili(float(charge.cooldown)*float(sim.rules.tick_rate))
	if sim.tick<int(unit.get("charge_until_tick",0)):
		moves[unit.id]=sim.clamp_to_field(unit.pos.move_toward(target.pos,minf(distance-float(stats.range),sim._movement_speed(unit)*float(charge.speed_multiplier)*dt)))
		return true
	return false
