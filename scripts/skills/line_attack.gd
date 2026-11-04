extends RefCounted
const MultiAttack = preload("res://scripts/skills/multi_attack.gd")
const OnHitSlow = preload("res://scripts/skills/on_hit_slow.gd")
# 单位一步的最大位移（约 5）加余量，用于缩小波前扫过区域的候选范围。
const MOVE_MARGIN := 1.0

## 一个普通攻击周期生成 count 条独立传播轨迹；每条有自己的命中记录。
## forward 从自身出发；transverse 以目标位置为中心，垂直于开火方向扫过。
static func launch(sim, unit: Dictionary, goal: Vector2) -> void:
	var stats: Dictionary = sim._weapon_stats(unit)
	var config: Dictionary = stats.skills.line_attack
	var forward: Vector2 = (goal - unit.pos).normalized()
	if forward == Vector2.ZERO:
		forward = Vector2.RIGHT if unit.team == 0 else Vector2.LEFT
	var length: float = float(config.get("length",stats.range))
	for strike in range(MultiAttack.count(stats)):
		var origin: Vector2 = unit.pos
		var direction: Vector2 = forward
		if config.pattern == "transverse":
			var side: Vector2 = Vector2(-forward.y,forward.x) * MultiAttack.side(strike)
			origin = goal + side * length * 0.5
			direction = -side
		sim.attack_waves.append({"origin":origin,"direction":direction,"source":unit.pos,
			"team":unit.team,"kind":unit.kind,"effect":config.effect,"strike":strike,
			"distance":0.0,"length":length,"speed":float(config.speed),
			"half_width":float(config.half_width),"damage":float(stats.damage),
			"bonus":stats.get("bonus",{}).duplicate(),
			"on_hit_slow":stats.skills.get("on_hit_slow",{}).duplicate(true),
			"target_layers":stats.get("target_layers",["ground"]).duplicate(),"attacks_base":stats.get("attacks_base",true),
			"born":sim.tick,"hit_ids":{},"base_hit":false})

## 检查单位在本步的运动轨迹是否穿过推进中的攻击前沿。
## 在前沿实际到达时判断横向宽度，允许敌军闪避或进入路径；不会补伤前沿后方。
static func crosses(wave: Dictionary, start: Vector2, finish: Vector2, next_distance: float) -> bool:
	var offset: Vector2 = start - wave.origin
	var end_offset: Vector2 = finish - wave.origin
	var a: float = offset.dot(wave.direction) - float(wave.distance)
	var b: float = end_offset.dot(wave.direction) - next_distance
	var side_a: float = wave.direction.cross(offset)
	var side_b: float = wave.direction.cross(end_offset)
	if absf(a - b) < 0.00001:
		return absf(a) < 0.00001 and minf(side_a,side_b) <= float(wave.half_width) and maxf(side_a,side_b) >= -float(wave.half_width)
	var fraction: float = a / (a - b)
	return fraction >= 0.0 and fraction <= 1.0 and absf(lerpf(side_a,side_b,fraction)) <= float(wave.half_width)

## 推进整条波，扫过前沿的单位每波只受伤一次；射程末端不会越界。
static func advance(sim, dt: float, moves: Dictionary, hits: Dictionary, base_hits: Array, pending_slows: Dictionary) -> void:
	var active: Array = []
	for wave in sim.attack_waves:
		# 发射当步只创建波；下一模拟步才开始传播，避免瞬间命中。
		if int(wave.born) == sim.tick:
			active.append(wave)
			continue
		var next_distance := minf(float(wave.length), float(wave.distance) + float(wave.speed) * dt)
		var duration_fraction: float = (next_distance - float(wave.distance)) / (float(wave.speed) * dt)
		# 只检查前沿本步扫过区域附近的敌人；单位一步最多移动约 5，留 MOVE_MARGIN 余量。
		var layers: Array = wave.get("target_layers",["ground"])
		var middle: float = (float(wave.distance) + next_distance) * 0.5
		var sweep_radius: float = Vector2((next_distance - float(wave.distance)) * 0.5, float(wave.half_width)).length() + MOVE_MARGIN
		for victim in sim.nearby_team(wave.origin + wave.direction * middle, sweep_radius, 1 - int(wave.team)):
			if wave.hit_ids.has(victim.id):
				continue
			var targetable: Array = sim.catalog[victim.kind].get("targetable_layers",[sim.catalog[victim.kind].get("layer","ground")])
			var compatible := false
			for layer in targetable:
				if layers.has(layer):compatible=true
			if not compatible:continue
			if sim.is_structure(victim) and not bool(wave.get("attacks_structures", wave.get("attacks_base", true))):
				continue
			var finish: Vector2 = victim.pos.lerp(moves.get(victim.id,victim.pos),duration_fraction)
			var start: Vector2 = finish if sim.teleports.has(victim.id) else victim.pos
			if crosses(wave, start, finish, next_distance):
				wave.hit_ids[victim.id] = true
				var amount: float = sim.expected_damage(wave, victim)
				sim.queue_hit(hits, victim, sim.raw_damage(wave, victim.kind),true)
				sim.damage_done[int(wave.team)] += amount
				sim.events.append({"type":"attack_hit","id":victim.id,"kind":wave.kind,"team":wave.team,"strike":wave.strike,"amount":amount})
				OnHitSlow.queue_hit(sim,victim,wave.on_hit_slow,pending_slows)
		# 基地按 layout.base_radius 计算首次接触，同样等待前沿到达，且每波只命中一次。
		var enemy: int = 1 - int(wave.team)
		var radius: float = float(sim.rules.layout.base_radius)
		var base_offset: Vector2 = sim.base_pos(enemy) - wave.origin
		var side: float = wave.direction.cross(base_offset)
		if wave.get("attacks_base",true) and not wave.base_hit and absf(side) <= radius:
			var contact := maxf(0.0,base_offset.dot(wave.direction) - sqrt(radius * radius - side * side))
			if base_offset.dot(wave.direction) >= 0.0 and contact >= float(wave.distance) and contact <= next_distance:
				base_hits[enemy] += float(wave.damage)
				wave.base_hit = true
		sim.events.append({"type":"line_attack","kind":wave.kind,"effect":wave.effect,"source":wave.source,"team":wave.team,
			"from":wave.origin + wave.direction * float(wave.distance),"to":wave.origin + wave.direction * next_distance})
		wave.distance = next_distance
		if next_distance < float(wave.length):
			active.append(wave)
	sim.attack_waves = active

