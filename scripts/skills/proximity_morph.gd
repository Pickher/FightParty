extends "res://scripts/skills/skill.gd"
## 行军形态一次性变形。锁定变形后原地完成，即使触发它的敌方已经离开。

func _init() -> void:
	priority = 0

func on_spawn(_sim) -> void:
	if config.has("travel_tags"):
		owner.form_tags = config.travel_tags.duplicate()

func on_removed(_sim) -> void:
	owner.erase("form_tags")

func before_target(ctx: Dictionary) -> bool:
	var sim = ctx.sim
	if not state.has("finish_tick"):
		if not _ground_enemy_in_range(sim):
			return false
		var ticks := maxi(1, ceili(float(config.duration) * float(sim.rules.tick_rate)))
		state.finish_tick = sim.tick + ticks - 1
	if sim.tick >= int(state.finish_tick):
		ctx.form_changes[owner.id] = config.target_kind
	return true

func _ground_enemy_in_range(sim) -> bool:
	var enemy := 1 - int(owner.team)
	var radius := float(config.radius)
	# 原图 ExtendByUnitRadius 将目标边缘计入探测范围；基地在本游戏中是独立实体。
	if sim.bases[enemy] > 0 and owner.pos.distance_to(sim.base_pos(enemy)) <= radius + float(sim.rules.layout.base_radius):
		return true
	for other in sim.nearby_team(owner.pos, radius + float(sim.max_body_radius), enemy):
		var stats: Dictionary = sim.catalog[other.kind]
		if other.hp <= 0 or stats.layer != "ground" or sim.has_tag(other, "worker"):
			continue
		if bool(other.get("summoned", false)) or stats.unit_type == "summon" or stats.get("status", "") == "summoned":
			continue
		if sim.tick < int(other.get("invulnerable_until_tick", 0)):
			continue
		if owner.pos.distance_to(other.pos) <= radius + float(sim.body_radius(other)):
			return true
	return false
