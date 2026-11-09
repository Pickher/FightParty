extends "res://scripts/skills/skill.gd"

func _init() -> void:
	priority=60

func moves_while_attacking() -> bool:return true

func select_target(sim, target: Dictionary) -> Dictionary:
	# 统计此单位所有可攻击层，而不是只看当前空/地武器，避免切炮前漏掉目标。
	var search: Dictionary = sim._search_stats(owner)
	var reach: float = float(search.range)
	var nearby: Array = []
	for enemy in sim.nearby_team(owner.pos,reach,1-int(owner.team)):
		if enemy.hp>0 and sim._can_hit_unit(owner,enemy,search):nearby.append(enemy)
	state.in_range_count=nearby.size()
	if nearby.is_empty():return target
	# 普通索敌已处理锁定有效期；只在它选中了范围外目标时，优先留下范围内的敌人。
	if not target.is_empty():
		for enemy in nearby:
			if enemy.id==target.id:return target
	var best: Dictionary = {}
	var best_distance := INF
	for enemy in nearby:
		var distance: float = owner.pos.distance_squared_to(enemy.pos)
		if distance<best_distance or (is_equal_approx(distance,best_distance) and int(enemy.id)<int(best.get("id",2147483647))):
			best=enemy
			best_distance=distance
	return best

func after_action(ctx: Dictionary) -> void:
	var count: int = int(state.get("in_range_count",0))
	if count>int(config.get("single_target_limit",1)):
		# 有其他敌人可打时不追着当前目标移动，也不提前打断有效锁定。
		ctx.moves.erase(owner.id)
		return
	if count==0 or ctx.target.is_empty():return
	var sim = ctx.sim
	var speed: float = sim._movement_speed(owner)
	if speed<=0:return
	var offset: Vector2 = owner.pos-ctx.target.pos
	var away: Vector2 = offset.normalized()
	if away==Vector2.ZERO:away=Vector2.LEFT if owner.team==0 else Vector2.RIGHT
	var preferred: float = clampf(float(config.get("preferred_distance",5.5)),0.0,float(ctx.weapon.range))
	var desired: Vector2 = ctx.target.pos+away*preferred
	var dt: float = float(ctx.dt)
	var radial: Vector2 = (desired-owner.pos).limit_length(speed*dt)/dt
	# 只在切向分离队形，避免避让把单位推过射程边界；总移动速度仍受上限约束。
	var separation: Vector2 = sim._separation(owner)
	var tangent: Vector2 = separation-away*separation.dot(away)
	var velocity: Vector2 = (radial+tangent*speed*0.65).limit_length(speed)
	ctx.moves[owner.id]=sim.clamp_to_field(owner.pos+velocity*dt)
