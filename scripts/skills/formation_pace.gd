extends "res://scripts/skills/skill.gd"
## 混编行军只向下限速。参考邻居模板基础速度，不读取其瞬时动作或递归查询限速。
func march_multiplier(sim) -> float:
	var base: float = float(sim.definitions[owner.kind].speed)
	if base<=0.0:return 1.0
	var pace: float = base
	for ally in sim.nearby_team(owner.pos,float(config.get("radius",12)),int(owner.team)):
		if ally.kind==owner.kind or float(ally.hp)<=0 or sim.is_structure(ally):continue
		var stats: Dictionary = sim.catalog[ally.kind]
		# 飞行军队、普通辅助单位都算其他类别；临时召唤物不作为行军参照。
		if str(stats.get("unit_type","unit"))=="summon" or str(stats.get("status",""))=="summoned" or bool(ally.get("owner_dependent",false)):continue
		var other_speed: float = float(sim.definitions[ally.kind].speed)
		if other_speed>0.0:pace=minf(pace,other_speed)
	return pace/base
