extends RefCounted
const Deployment = preload("res://scripts/skills/deployment.gd")

## 自身为顶点、朝敌方固定展开的扇形；两种模式始终属于空中单位。
static func weapon(sim, unit: Dictionary) -> Dictionary:
	var base: Dictionary = sim.catalog[unit.kind]
	if unit.get("siege_state","mobile") == "mobile":return base
	if not sim.mode_weapons.has(unit.kind):
		var result: Dictionary = base.duplicate(true)
		result.merge(base.skills.defender_zone.weapon,true)
		sim.mode_weapons[unit.kind]=result
	return sim.mode_weapons[unit.kind]

static func in_sector(unit: Dictionary, point: Vector2, reach: float, angle: float) -> bool:
	var offset: Vector2 = point-unit.pos
	if offset.length_squared()>reach*reach:return false
	if offset.length_squared()<0.000001:return true
	var forward := Vector2.RIGHT if unit.team==0 else Vector2.LEFT
	return forward.dot(offset.normalized())>=cos(deg_to_rad(angle*0.5))

static func contains(sim, unit: Dictionary, point: Vector2) -> bool:
	if unit.get("siege_state","mobile")=="mobile":return true
	var config: Dictionary = sim.catalog[unit.kind].skills.defender_zone
	return in_sector(unit,point,float(config.weapon.range),float(config.angle_degrees))

static func prepare(sim, unit: Dictionary, motion: Dictionary) -> bool:
	var config: Dictionary = sim.catalog[unit.kind].skills.defender_zone
	var reach: float = float(config.weapon.range)
	unit.erase("defender_goal")
	unit.erase("defender_center")
	var context := {"config":config,"range":reach,"center":unit.pos,"target_layers":["ground"],"sector_angle_degrees":config.angle_degrees}
	if unit.siege_state=="mobile":
		if not sim._target(unit).is_empty():
			unit.siege_scan_ids=[]
			unit.siege_scan_tick=0
			return true
		var nearest: Dictionary = sim.nearest_ground_enemy(unit,reach*1.5)
		if not nearest.is_empty():
			unit.defender_goal=nearest.pos
			if not in_sector(unit,nearest.pos,reach*1.5,float(config.angle_degrees)):
				# 横向对齐目标，但保持机体在目标后方；不把扇形转到己方方向。
				var forward: float = 1.0 if unit.team==0 else -1.0
				unit.defender_goal=sim.clamp_to_field(Vector2(float(nearest.pos.x)-forward*reach*0.8,nearest.pos.y))
				unit.siege_scan_ids=[]
				unit.siege_scan_tick=0
				return true
		var in_range: bool = not nearest.is_empty() and in_sector(unit,nearest.pos,reach,float(config.angle_degrees))
		return Deployment.can_act(sim,unit,in_range,false,motion,context)
	var occupied := false
	for enemy in sim.nearby_team(unit.pos,reach,1-int(unit.team)):
		if enemy.hp>0 and sim.catalog[enemy.kind].get("layer","ground")=="ground" and not sim.is_structure(enemy) and in_sector(unit,enemy.pos,reach,float(config.angle_degrees)):
			occupied=true
			break
	return Deployment.can_act(sim,unit,occupied,false,motion,context)
