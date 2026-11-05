extends "res://scripts/skills/skill.gd"
const Deployment = preload("res://scripts/skills/services/deployment_service.gd")

func in_sector(unit: Dictionary, point: Vector2, reach: float, angle: float) -> bool:
	var offset: Vector2 = point-unit.pos
	if offset.length_squared()>reach*reach:return false
	if offset.length_squared()<0.000001:return true
	var forward := Vector2.RIGHT if unit.team==0 else Vector2.LEFT
	return forward.dot(offset.normalized())>=cos(deg_to_rad(angle*0.5))
func contains(sim, unit: Dictionary, point: Vector2) -> bool:
	if state.get("siege_state","mobile")=="mobile":return true
	return in_sector(unit,point,float(config.weapon.range),float(config.angle_degrees))
func prepare(sim, unit: Dictionary, motion: Dictionary) -> bool:
	var reach: float = float(config.weapon.range)
	unit.erase("defender_goal")
	unit.erase("defender_center")
	var context := {"config":config,"range":reach,"center":unit.pos,"target_layers":["ground"],"sector_angle_degrees":config.angle_degrees}
	if state.siege_state=="mobile":
		if not sim._target(unit).is_empty():
			state.siege_scan_ids=[]
			state.siege_scan_tick=0
			return true
		var nearest: Dictionary = sim.nearest_ground_enemy(unit,reach*1.5)
		if not nearest.is_empty():
			unit.defender_goal=nearest.pos
			if not in_sector(unit,nearest.pos,reach*1.5,float(config.angle_degrees)):
				# 横向对齐目标，但保持机体在目标后方；不把扇形转到己方方向。
				var forward: float = 1.0 if unit.team==0 else -1.0
				unit.defender_goal=sim.clamp_to_field(Vector2(float(nearest.pos.x)-forward*reach*0.8,nearest.pos.y))
				state.siege_scan_ids=[]
				state.siege_scan_tick=0
				return true
		var in_range: bool = not nearest.is_empty() and in_sector(unit,nearest.pos,reach,float(config.angle_degrees))
		return Deployment.can_act(sim,unit,state,in_range,false,motion,context)
	var occupied := false
	for enemy in sim.nearby_team(unit.pos,reach,1-int(unit.team)):
		if enemy.hp>0 and sim.catalog[enemy.kind].get("layer","ground")=="ground" and not sim.is_structure(enemy) and in_sector(unit,enemy.pos,reach,float(config.angle_degrees)):
			occupied=true
			break
	return Deployment.can_act(sim,unit,state,occupied,false,motion,context)

var weapon_cache: Dictionary = {}
func _init() -> void:
	priority=30
	view_fields=["siege_state","siege_until_tick","siege_scan_tick","siege_scan_ids"]
func on_spawn(_sim) -> void: Deployment.initialize(state)
func before_target(ctx: Dictionary) -> bool:
	ctx.can_act=prepare(ctx.sim,owner,ctx.motion)
	return false
func modify_weapon(sim, weapon: Dictionary) -> Dictionary:
	if state.get("siege_state","mobile")=="mobile":return weapon
	if weapon_cache.is_empty():
		weapon_cache=weapon.duplicate(true)
		weapon_cache.merge(config.weapon.duplicate(true),true)
	return weapon_cache
func can_target(sim, victim: Dictionary) -> bool: return contains(sim,owner,victim.pos)
