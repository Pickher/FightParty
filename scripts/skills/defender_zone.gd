extends RefCounted
const Deployment = preload("res://scripts/skills/deployment.gd")

## 复用部署扫描/收放计时，展开时固定圆形警戒区；单位自身仍是飞行单位。
## 展开后的武器 = 兵种数据合并防卫武器；按兵种缓存在 sim.mode_weapons，避免每次深拷贝。
static func weapon(sim, unit: Dictionary) -> Dictionary:
	var base: Dictionary = sim.catalog[unit.kind]
	if unit.get("siege_state","mobile") == "mobile":
		return base
	if not sim.mode_weapons.has(unit.kind):
		var result: Dictionary = base.duplicate(true)
		result.merge(base.skills.defender_zone.weapon,true)
		sim.mode_weapons[unit.kind] = result
	return sim.mode_weapons[unit.kind]

static func contains(sim, unit: Dictionary, point: Vector2) -> bool:
	if unit.get("siege_state","mobile") == "mobile":
		return true
	return unit.has("defender_center") and point.distance_squared_to(unit.defender_center) <= pow(float(sim.catalog[unit.kind].skills.defender_zone.radius),2)

## 优先处理发现范围内的空军；没有空军时，接近地面目标并按部署规则圈地。
## 返回是否可继续普通移动/攻击；转换中或等待空圈时保持原地。
static func prepare(sim, unit: Dictionary, motion: Dictionary) -> bool:
	var config: Dictionary = sim.catalog[unit.kind].skills.defender_zone
	unit.erase("defender_goal")
	if unit.siege_state == "mobile":
		unit.erase("defender_center")
		var air_target: Dictionary = sim._target(unit)
		if not air_target.is_empty():
			unit.siege_scan_ids = []
			unit.siege_scan_tick = 0
			return true
		var reach: float = float(config.weapon.range)
		var nearest: Dictionary = sim.nearest_ground_enemy(unit,reach*1.5)
		var distance: float = INF if nearest.is_empty() else unit.pos.distance_to(nearest.pos)
		if not nearest.is_empty():
			unit.defender_goal = nearest.pos
		var allowed: bool = Deployment.can_act(sim,unit,distance<=reach,false,motion,
			{"config":config,"range":reach,"target_layers":["ground"]})
		if unit.siege_state == "deploying":
			# 最远圈边不超过对地射程；圈中心不跟随敌人移动。
			unit.defender_center = unit.pos + (nearest.pos-unit.pos).limit_length(maxf(0.0,reach-float(config.radius)))
			unit.locked_target_id = 0
		return allowed
	var occupied := false
	for other in sim.nearby_team(unit.defender_center,float(config.radius),1-int(unit.team)):
		if other.hp > 0 and sim.catalog[other.kind].get("layer","ground") == "ground":
			occupied = true
			break
	return Deployment.can_act(sim,unit,occupied,false,motion,
		{"config":config,"range":config.radius,"center":unit.defender_center,"target_layers":["ground"]})
