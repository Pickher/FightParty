extends RefCounted
## 出手时间表：仅保存纯数据。死亡/中断取消未发射部分，不回收已经发出的弹体。
const Projectiles = preload("res://scripts/skills/services/projectile_service.gd")
const Lines = preload("res://scripts/skills/services/line_service.gd")

static func launch(ctx: Dictionary, state: Dictionary, mount: int = -1, base_team: int = -1) -> void:
	var sim = ctx.sim
	var unit: Dictionary = ctx.unit
	var weapon: Dictionary = ctx.weapon.duplicate(true)
	var target_id: int = int(ctx.target.id) if not ctx.target.is_empty() else -1-int(1-int(unit.team))
	sim.attack_sequences.append({"source_id":unit.id,"kind":unit.kind,"team":unit.team,
		"mount":mount,"base_team":base_team,"serial":int(state.attack_serial),
		"weapon":weapon,"target_id":target_id,"goal":ctx.goal,"source":unit.pos,
		"elapsed":0.0,"next_strike":0,"count":sim.skill_system.attack_count(sim,unit,weapon),
		"start_offset":float(state.get("attack_ready_offset",0)),"born":sim.tick,
		"damage_multiplier":float(ctx.get("damage_multiplier",1)),
		"impact_skills":sim.skill_system.impact_configs(unit)})

static func source_and_state(sim, sequence: Dictionary) -> Dictionary:
	if int(sequence.base_team)>=0:
		var team: int = int(sequence.base_team)
		if not sim.base_has_defense(team):return {}
		return {"source":{"id":-team-1,"kind":"gate_tower","team":team,"pos":sim.base_pos(team)},"state":sim.base_defenses[team]}
	var source = sim.by_id.get(int(sequence.source_id))
	if source==null or float(source.hp)<=0:return {}
	if int(sequence.mount)>=0:
		var component = sim.skill_system.get_component(source,"independent_weapons")
		if component==null or int(sequence.mount)>=component.state.mounts.size():return {}
		return {"source":source,"state":component.state.mounts[int(sequence.mount)]}
	return {"source":source,"state":source}

static func advance(sim, frame: Dictionary) -> void:
	var active: Array = []
	for sequence in sim.attack_sequences:
		var current := source_and_state(sim,sequence)
		if current.is_empty() or int(sequence.serial)<=int(current.state.get("attack_cancelled_through",-1)):continue
		var source: Dictionary = current.source
		var rate: float = 1.0 if int(sequence.base_team)>=0 else sim.skill_system.attack_rate(sim,source)
		if rate<=0:
			active.append(sequence)
			continue
		var offset: float = float(sequence.start_offset) if int(sequence.born)==sim.tick else 0.0
		var before: float = float(sequence.elapsed)
		sequence.elapsed = before+maxf(0.0,float(frame.dt)-offset)*rate
		var weapon: Dictionary = sequence.weapon
		var target = sim.by_id.get(int(sequence.target_id))
		if target!=null and float(target.hp)>0:sequence.goal=target.pos
		elif int(sequence.target_id)>0 and not bool(weapon.continue_on_target_death):continue
		while int(sequence.next_strike)<int(sequence.count):
			var strike: int = int(sequence.next_strike)
			var due: float = float(weapon.windup)+float(weapon.attack_duration)*float(strike+1)/float(sequence.count)
			if due>float(sequence.elapsed)+0.000001:break
			var fire_offset: float = clampf(offset+(due-before)/rate,0.0,float(frame.dt))
			var fraction: float = fire_offset/float(frame.dt)
			var start: Vector2 = source.pos.lerp(frame.moves.get(source.id,source.pos),fraction)
			if target!=null and float(target.hp)>0:
				sequence.goal=target.pos.lerp(frame.moves.get(target.id,target.pos),fraction)
			# 接触武器在实际挥击时仍须碰到目标；远程已发射弹体不再检查射程。
			if weapon.delivery.type=="instant" and target!=null and start.distance_to(sequence.goal)>sim.attack_reach(source,target,weapon):
				sequence.next_strike=strike+1
				continue
			var shot: Dictionary = frame.duplicate()
			shot.unit=source
			shot.weapon=weapon
			shot.target={} if target==null else target
			shot.goal=sequence.goal
			shot.strike=strike
			shot.fire_offset=fire_offset
			shot.source_position=start
			shot.damage_multiplier=sequence.damage_multiplier
			shot.impact_skills=sequence.impact_skills
			if weapon.delivery.type=="wave":
				Lines.launch_strike(sim,source,sequence.goal,weapon.delivery,weapon,strike,float(sequence.damage_multiplier),start,fire_offset,sequence.impact_skills)
			elif not sim.skill_system.attack(shot):Projectiles.launch(sim,sequence,start,sequence.goal,strike,fire_offset)
			current.state.attack_emitted=true
			if target!=null:current.state.locked_target_id=int(target.id)
			sequence.next_strike=strike+1
		if int(sequence.next_strike)<int(sequence.count):active.append(sequence)
	sim.attack_sequences=active
