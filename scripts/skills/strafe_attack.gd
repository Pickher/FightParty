extends "res://scripts/skills/skill.gd"
## 切入、穿越、转向再切入；移动与开火解耦，伤害仍走原武器序列。
## 航段只在目标/阶段变化时生成，随机状态属于单位快照，不使用全局随机源。

func _init() -> void:
	priority=60
	view_fields=["strafe_heading","strafe_phase","strafe_target_id"]

func on_spawn(sim) -> void:
	state.random_state=posmod(int(sim.journal.get("seed",1))+int(owner.id)*104729,2147483646)+1
	state.strafe_heading=Vector2.RIGHT if int(owner.team)==0 else Vector2.LEFT
	state.strafe_phase="return"
	state.strafe_target_id=0
	state.pass_fired=false

func moves_while_attacking() -> bool:return true

func _random() -> float:
	state.random_state=(int(state.random_state)*48271)%2147483647
	return float(state.random_state)/2147483647.0

func _parent(sim) -> Dictionary:
	var parent: Dictionary = sim.by_id.get(int(owner.get("owner_id",0)),{})
	return parent if not parent.is_empty() and float(parent.hp)>0 else {}

func _valid_target(sim, target: Dictionary, weapon: Dictionary) -> bool:
	return not target.is_empty() and float(target.hp)>0 and int(target.team)!=int(owner.team) and sim._can_hit_unit(owner,target,weapon)

func select_target(sim, target: Dictionary) -> Dictionary:
	var parent := _parent(sim)
	if bool(owner.get("owner_dependent",false)) and parent.is_empty():return {}
	var weapon: Dictionary = sim._weapon_stats(owner)
	# 掠过后会暂时飞出自身射程，继续原航段而不是按普通开火锁反复换敌人。
	var current: Dictionary = sim.by_id.get(int(state.strafe_target_id),{})
	if _valid_target(sim,current,weapon):return current
	if parent.is_empty():return target
	# 母舰没有普通伤害，不会建立普通攻击锁；召唤组件发布它本步的作战目标。
	var commanded: Dictionary = sim.by_id.get(int(parent.get("summon_target_id",0)),{})
	if _valid_target(sim,commanded,weapon):return commanded
	# 没有有效母舰指令时在发射范围内找新目标；既有目标/指令可保持到 leash 距离。
	var radius := minf(float(sim._search_stats(parent).range),float(owner.get("leash",0)))
	var best: Dictionary = {}
	var nearest := INF
	for enemy in sim.nearby_team(parent.pos,radius,1-int(owner.team)):
		if not _valid_target(sim,enemy,weapon):continue
		var distance: float = parent.pos.distance_squared_to(enemy.pos)
		if distance<nearest or (is_equal_approx(distance,nearest) and int(enemy.id)<int(best.get("id",2147483647))):
			best=enemy
			nearest=distance
	return best

func _plan_pass(sim, center: Vector2) -> void:
	var radial: Vector2 = owner.pos-center
	if radial.length_squared()<0.0001:radial=-Vector2(state.strafe_heading)
	var angle := deg_to_rad(float(config.get("approach_angle_degrees",65)))*(_random()*2.0-1.0)
	var axis := radial.normalized().rotated(angle)
	var side := Vector2(-axis.y,axis.x)
	# 横向偏移始终小于武器射程，保证航线经过可射击区；不改变真实武器射程。
	var spread := minf(float(config.get("lateral_spread",0.75)),float(sim._weapon_stats(owner).range)*0.65)
	var offset := side*spread*(_random()*2.0-1.0)
	var length := maxf(0.5,float(config.get("pass_distance",3.0)))
	state.entry_offset=axis*length+offset
	state.exit_offset=-axis*length+offset
	state.strafe_phase="approach"
	state.pass_fired=false

func _waypoint(sim, center: Vector2, offset: Vector2) -> Vector2:
	return sim.clamp_to_field(center+offset)

func before_action(ctx: Dictionary) -> void:
	var sim = ctx.sim
	var parent := _parent(sim)
	var target_id := int(ctx.target.get("id",0))
	# 基地不在单位索引中；沿用母舰进入基地发射距离后才允许子机攻城的规则。
	if target_id==0 and ctx.goal.is_equal_approx(sim.base_pos(1-int(owner.team))) and bool(ctx.weapon.get("attacks_base",true)):
		if not bool(owner.get("owner_dependent",false)) or (not parent.is_empty() and parent.pos.distance_to(ctx.goal)<=float(sim._search_stats(parent).range)+float(sim.rules.layout.base_radius)):
			target_id=-1-int(1-int(owner.team))
	if target_id==0:
		state.strafe_target_id=0
		state.strafe_phase="return"
		ctx.armed=false
		return
	if target_id!=int(state.strafe_target_id) or state.strafe_phase=="return":
		state.strafe_target_id=target_id
		_plan_pass(sim,ctx.goal)
	var speed: float = sim._movement_speed(owner)
	var turn_rate := deg_to_rad(maxf(1.0,float(config.get("turn_rate_degrees",540))))
	# 航点容差覆盖最小转弯半径，否则高速飞机可能永远追着同一点绕圈。
	var arrival := maxf(float(config.get("arrival_radius",0.6)),maxf(speed*float(ctx.dt)*1.2,speed/turn_rate*1.1))
	if state.strafe_phase=="approach" and owner.pos.distance_to(_waypoint(sim,ctx.goal,state.entry_offset))<=arrival:
		state.strafe_phase="cross"
	elif state.strafe_phase=="cross" and owner.pos.distance_to(_waypoint(sim,ctx.goal,state.exit_offset))<=arrival:
		_plan_pass(sim,ctx.goal)
	state.serial_before=int(owner.get("attack_serial",0))
	# 每次掠过最多启动一轮，冷却/多段/护甲/弹道均由公共攻击系统控制。
	ctx.armed=bool(ctx.armed) and state.strafe_phase=="cross" and not bool(state.pass_fired)

func _fly(ctx: Dictionary, goal: Vector2) -> void:
	var sim = ctx.sim
	var speed: float = sim._movement_speed(owner)
	if speed<=0:
		ctx.moves.erase(owner.id)
		return
	var delta: Vector2 = goal-owner.pos
	if delta.length_squared()<0.0001:
		ctx.moves.erase(owner.id)
		return
	var heading: Vector2 = state.strafe_heading
	var turn := deg_to_rad(maxf(1.0,float(config.get("turn_rate_degrees",540))))*float(ctx.dt)
	heading=Vector2.from_angle(rotate_toward(heading.angle(),delta.angle(),turn))
	# 小幅避让不覆盖主飞行方向，避免刚出舰时被母舰体积挤回后方。
	var direction: Vector2 = (heading+sim._separation(owner).limit_length(1.0)*0.15).normalized()
	var destination: Vector2 = sim.clamp_to_field(owner.pos+direction*minf(speed*float(ctx.dt),delta.length()))
	var motion: Vector2 = destination-owner.pos
	if motion.length_squared()>0.0001:state.strafe_heading=motion.normalized()
	ctx.moves[owner.id]=destination

func after_action(ctx: Dictionary) -> void:
	if state.strafe_phase=="return":
		var parent := _parent(ctx.sim)
		if parent.is_empty():return
		var radius := maxf(0.0,float(config.get("follow_radius",1.2)))
		var angle := TAU*float(posmod(int(owner.id),8))/8.0
		var holding: Vector2 = ctx.sim.clamp_to_field(parent.pos+Vector2.from_angle(angle)*radius)
		if owner.pos.distance_to(holding)>radius:_fly(ctx,holding)
		else:
			# 无目标时随母舰待命，不向敌方基地独自行军。
			ctx.moves[owner.id]=owner.pos.move_toward(holding,ctx.sim._movement_speed(owner)*float(ctx.dt))
		return
	if int(owner.get("attack_serial",0))>int(state.get("serial_before",0)):state.pass_fired=true
	var offset: Vector2 = state.entry_offset if state.strafe_phase=="approach" else state.exit_offset
	_fly(ctx,_waypoint(ctx.sim,ctx.goal,offset))
