extends "res://scripts/attacks/attack_behavior.gd"
## 从单位前缘打出扇形。主目标全伤，次目标按碰撞圆判定并使用武器的溅射倍率。

func type_id() -> String:
	return "cone"

func can_emit(sim, source: Dictionary, target, weapon: Dictionary, origin: Vector2, goal: Vector2) -> bool:
	return target == null or origin.distance_to(goal) <= sim.attack_reach(source, target, weapon)

## 先判扇面的圆弧，再判最近的一条侧边。圆心在扇面外的大单位也可能被命中。
static func intersects_disk(origin: Vector2, direction: Vector2, length: float, half_angle: float, center: Vector2, radius: float) -> bool:
	var offset := center - origin
	if offset.length_squared() > (length + radius) * (length + radius):
		return false
	if absf(direction.angle_to(offset)) <= half_angle:
		return true
	var edge := direction.rotated(half_angle if direction.cross(offset) >= 0.0 else -half_angle)
	var closest := edge * clampf(offset.dot(edge), 0.0, length)
	return offset.distance_squared_to(closest) <= radius * radius

func emit(ctx: Dictionary, sequence: Dictionary) -> void:
	var sim = ctx.sim
	var unit: Dictionary = ctx.unit
	var weapon: Dictionary = ctx.weapon
	var start: Vector2 = ctx.source_position
	var direction := start.direction_to(ctx.goal)
	if direction.is_zero_approx():
		direction = Vector2.RIGHT if int(unit.team) == 0 else Vector2.LEFT
	var origin: Vector2 = start + direction * sim.body_radius(unit)
	var length := float(weapon.delivery.length)
	var angle_degrees := float(weapon.delivery.angle_degrees)
	var half_angle := deg_to_rad(angle_degrees * 0.5)
	var enemy := 1 - int(unit.team)
	var target_id := int(sequence.target_id)
	var strike := int(ctx.strike)
	var multiplier := float(ctx.damage_multiplier)
	var secondary := multiplier * float(weapon.get("splash_multiplier",1.0))
	ctx.impact_time = float(sim.tick - 1) * float(ctx.dt) + float(ctx.fire_offset)
	sim.events.append({"type":"cone_attack", "kind":unit.kind, "team":unit.team, "source_id":unit.id,
		"from":origin, "to":origin + direction * length, "angle_degrees":angle_degrees,
		"length":length, "mode":weapon.id, "strike":strike, "time":ctx.impact_time})

	if not ctx.target.is_empty() and sim._can_hit_unit(unit, ctx.target, weapon):
		sim.queue_strike_hit(ctx, weapon, ctx.target, strike, multiplier, true)
	var fraction := float(ctx.fire_offset) / float(ctx.dt)
	var search_radius: float = length + sim.max_body_radius + float(ctx.motion_margin)
	for victim in sim.nearby_team(origin, search_radius, enemy):
		if int(victim.id) == target_id or not sim._can_hit_unit(unit, victim, weapon):
			continue
		var position: Vector2 = victim.pos.lerp(ctx.moves.get(victim.id, victim.pos), fraction)
		if intersects_disk(origin, direction, length, half_angle, position, sim.body_radius(victim)):
			sim.queue_strike_hit(ctx, weapon, victim, strike, secondary, false)
	if weapon.attacks_base and intersects_disk(origin, direction, length, half_angle, sim.base_pos(enemy), float(sim.rules.layout.base_radius)):
		ctx.base_hits[enemy] += float(weapon.damage) * (multiplier if target_id < 0 else secondary)
