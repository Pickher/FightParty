extends RefCounted
const MultiAttack = preload("res://scripts/skills/multi_attack.gd")
const OnHitSlow = preload("res://scripts/skills/on_hit_slow.gd")

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
			"light_multiplier":float(stats.light_multiplier),"heavy_multiplier":float(stats.heavy_multiplier),
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
		for victim in sim.units:
			if victim.team == wave.team or wave.hit_ids.has(victim.id):
				continue
			if not wave.get("target_layers",["ground"]).has(sim.catalog[victim.kind].get("layer","ground")):
				continue
			var finish: Vector2 = victim.pos.lerp(moves.get(victim.id,victim.pos),duration_fraction)
			if crosses(wave, victim.pos, finish, next_distance):
				wave.hit_ids[victim.id] = true
				var multiplier: float = float(wave[sim.catalog[victim.kind].armor + "_multiplier"])
				var amount: float = float(wave.damage) * multiplier
				hits[victim.id] = float(hits.get(victim.id,0.0)) + amount
				sim.damage_done[int(wave.team)] += amount
				sim.events.append({"type":"attack_hit","id":victim.id,"kind":wave.kind,"team":wave.team,"strike":wave.strike,"amount":amount})
				OnHitSlow.queue_hit(sim,victim,wave.on_hit_slow,pending_slows)
		# 基地按半径 20 计算首次接触，同样等待前沿到达，且每波只命中一次。
		var enemy: int = 1 - int(wave.team)
		var base_offset: Vector2 = Vector2(1170.0 if enemy == 1 else 30.0,200.0) - wave.origin
		var side: float = wave.direction.cross(base_offset)
		if wave.get("attacks_base",true) and not wave.base_hit and absf(side) <= 20.0:
			var contact := maxf(0.0,base_offset.dot(wave.direction) - sqrt(400.0 - side * side))
			if base_offset.dot(wave.direction) >= 0.0 and contact >= float(wave.distance) and contact <= next_distance:
				base_hits[enemy] += float(wave.damage)
				wave.base_hit = true
		sim.events.append({"type":"line_attack","kind":wave.kind,"effect":wave.effect,"source":wave.source,"team":wave.team,
			"from":wave.origin + wave.direction * float(wave.distance),"to":wave.origin + wave.direction * next_distance})
		wave.distance = next_distance
		if next_distance < float(wave.length):
			active.append(wave)
	sim.attack_waves = active

