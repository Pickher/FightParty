extends RefCounted
## 弹体不依赖发射者存活；每段独立飞行，命中时才查询范围并结算护盾/护甲。
const Summons = preload("res://scripts/skills/services/summon_service.gd")

static func launch(sim, sequence: Dictionary, origin: Vector2, goal: Vector2, strike: int, offset: float) -> void:
	var weapon: Dictionary = sequence.weapon
	var delivery: Dictionary = weapon.delivery
	var duration := 0.0
	if delivery.type=="fixed":duration=float(delivery.seconds)
	elif delivery.type=="distance":duration=origin.distance_to(goal)/maxf(0.001,float(delivery.speed))
	var now: float = float(sim.tick-1)/float(sim.rules.tick_rate)+offset
	var projectile := {"source_id":sequence.source_id,"team":sequence.team,"kind":sequence.kind,
		"id":sim.next_projectile_id,
		"origin":origin,"pos":origin,"goal":goal,"target_id":sequence.target_id,
		"weapon":weapon.duplicate(true),"impact_skills":sequence.impact_skills.duplicate(true),
		"damage_multiplier":sequence.damage_multiplier,"strike":strike,
		"launch_time":now,"impact_time":now+duration}
	sim.projectiles.append(projectile)
	sim.next_projectile_id+=1
	sim.events.append({"type":"attack","from":origin,"to":goal,"kind":sequence.kind,"team":sequence.team,
		"source_id":sequence.source_id,"splash":weapon.splash,"mode":weapon.id,"strike":strike,"projectile":duration>0,"time":now})

static func advance(sim, frame: Dictionary) -> void:
	var active: Array = []
	var start_time: float = float(sim.tick-1)/float(sim.rules.tick_rate)
	var end_time: float = float(sim.tick)/float(sim.rules.tick_rate)
	var margin := 0.0
	for unit in sim.units:margin=maxf(margin,unit.pos.distance_to(frame.moves.get(unit.id,unit.pos)))
	# 不同弹速可使后发先至；同刻用递增ID保证确定的结算顺序。
	sim.projectiles.sort_custom(func(a,b):return int(a.id)<int(b.id) if float(a.impact_time)==float(b.impact_time) else float(a.impact_time)<float(b.impact_time))
	for projectile in sim.projectiles:
		var target = sim.by_id.get(int(projectile.target_id))
		var tracking: bool = bool(projectile.weapon.delivery.get("tracking",true))
		var fraction: float = clampf((float(projectile.impact_time)-start_time)/float(frame.dt),0.0,1.0)
		if tracking and target!=null and float(target.hp)>0:
			projectile.goal=target.pos.lerp(frame.moves.get(target.id,target.pos),fraction if float(projectile.impact_time)<=end_time+0.000001 else 1.0)
		var duration: float = float(projectile.impact_time)-float(projectile.launch_time)
		projectile.pos=projectile.origin.lerp(projectile.goal,clampf((end_time-float(projectile.launch_time))/maxf(0.000001,duration),0.0,1.0))
		if float(projectile.impact_time)>end_time+0.000001:
			active.append(projectile)
			continue
		var source := {"id":projectile.source_id,"team":projectile.team,"kind":projectile.kind,"pos":projectile.origin,"projectile":true}
		if int(projectile.target_id)<0:
			var enemy: int = -int(projectile.target_id)-1
			if bool(projectile.weapon.attacks_base):
				frame.base_hits[enemy]+=float(projectile.weapon.damage)*float(projectile.damage_multiplier)
				var summon: Dictionary = projectile.impact_skills.get("summon",{})
				if summon.get("on","")=="hit":Summons.queue(sim,source,str(summon.kind),int(summon.count),projectile.goal,summon)
			continue
		if float(projectile.weapon.splash)<=0 and (target==null or float(target.hp)<=0):continue
		var shot: Dictionary = frame.duplicate()
		shot.unit=source
		shot.target={"id":projectile.target_id,"pos":projectile.goal}
		shot.impact_position=projectile.goal
		shot.impact_fraction=fraction
		shot.impact_time=projectile.impact_time
		shot.motion_margin=margin
		shot.damage_multiplier=projectile.damage_multiplier
		shot.impact_skills=projectile.impact_skills
		shot.weapon=projectile.weapon
		sim.queue_direct_strike(shot,projectile.weapon,shot.target,int(projectile.strike))
		if float(projectile.weapon.splash)>0:
			sim.events.append({"type":"area_impact","from":projectile.goal,"to":projectile.goal,"radius":projectile.weapon.splash,"kind":projectile.kind,"team":projectile.team})
	sim.projectiles=active

static func target_died(sim, dead: Dictionary) -> void:
	for sequence in sim.attack_sequences:
		if int(sequence.target_id)==int(dead.id):sequence.goal=dead.pos
	for projectile in sim.projectiles:
		if int(projectile.target_id)==int(dead.id) and bool(projectile.weapon.delivery.get("tracking",true)):projectile.goal=dead.pos
