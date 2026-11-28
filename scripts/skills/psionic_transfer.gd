extends "res://scripts/skills/skill.gd"
## 投影只保存位置，不加入单位列表。它不能索敌、承伤、占点，也不占地面碰撞。

func _init() -> void:
	view_fields=["shade_position","shade_previous"]

func on_spawn(sim) -> void:
	if owner.get("adept_tactic","retreat")=="support":
		state.launch_tick=sim.tick+ceili(float(config.launch_delay)*float(sim.rules.tick_rate))
	else:
		# 定向命中在真正扣血/盾后才记录来源。溅射、持续伤害、其他单位的锁定不触发后撤。
		owner.direct_hit_sources={}

func _launch(destination: Vector2) -> void:
	state.shade_position=owner.pos
	state.shade_previous=owner.pos
	state.destination=destination

func _near_ground_enemy(sim, position: Vector2) -> bool:
	var enemy := 1-int(owner.team)
	var reach := float(config.contact_range)
	if position.distance_to(sim.base_pos(enemy))<=reach+float(sim.rules.layout.base_radius):return true
	for unit in sim.visible_enemies_near(position,reach+float(sim.max_body_radius),int(owner.team)):
		if unit.hp<=0 or sim.catalog[unit.kind].get("layer","ground")!="ground":continue
		if position.distance_to(unit.pos)<=reach+float(sim.body_radius(unit)):return true
	return false

func _retreat_attacker(sim) -> Dictionary:
	if float(owner.shield)>=float(config.retreat_shield_threshold) or sim.tick<int(state.get("ready_tick",0)):return {}
	# 弹道命中后才响应，过了这一帧不能用旧伤害再次触发。
	if int(owner.get("direct_hit_tick",-100))!=int(sim.tick)-1:return {}
	var nearest: Dictionary = {}
	var enemy := 1-int(owner.team)
	var best := float(config.attacker_range)*float(config.attacker_range)
	for source_id in owner.direct_hit_sources:
		var attacker: Dictionary
		if int(source_id)==-enemy-1 and sim.base_has_defense(enemy):
			attacker={"id":source_id,"pos":sim.base_pos(enemy)}
		else:
			attacker=sim.by_id.get(source_id,{})
			if attacker.is_empty() or attacker.team!=enemy or attacker.hp<=0:continue
			if not sim.is_visible_to(owner.team,attacker):continue
			if sim.catalog[attacker.kind].get("layer","ground")!="ground":continue
		var distance: float = owner.pos.distance_squared_to(attacker.pos)
		if distance<best or (distance==best and int(attacker.id)<int(nearest.get("id",2147483647))):
			best=distance
			nearest=attacker
	return nearest

func before_target(ctx: Dictionary) -> bool:
	var sim = ctx.sim
	var support: bool = owner.get("adept_tactic","retreat")=="support"
	if not state.has("shade_position"):
		if support:
			if not state.has("launch_tick") or sim.tick<int(state.launch_tick):return false
			state.erase("launch_tick")
			_launch(sim.base_pos(1-int(owner.team)))
		else:
			var attacker := _retreat_attacker(sim)
			if attacker.is_empty():return false
			var away: Vector2 = owner.pos-attacker.pos
			if away.is_zero_approx():away=Vector2.LEFT if int(owner.team)==0 else Vector2.RIGHT
			_launch(sim.clamp_to_field(owner.pos+away.normalized()*float(config.retreat_distance)))
			state.ready_tick=sim.tick+ceili(float(config.retreat_cooldown)*float(sim.rules.tick_rate))
	var previous: Vector2 = state.shade_position
	var destination: Vector2 = state.destination
	var speed := float(config.shade_speed if support else config.retreat_speed)
	var position := previous.move_toward(destination,speed*float(ctx.dt))
	state.shade_previous=previous
	state.shade_position=position
	if not position.is_equal_approx(destination) and not (support and _near_ground_enemy(sim,position)):return false
	ctx.moves[owner.id]=position
	sim.teleports[owner.id]=true
	owner.locked_target_id=0
	state.erase("shade_previous")
	state.erase("shade_position")
	state.erase("destination")
	return true
