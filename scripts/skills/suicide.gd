extends "res://scripts/skills/skill.gd"
const Areas = preload("res://scripts/skills/services/area_service.gd")

func suicide(sim, unit: Dictionary, target: Dictionary, hits: Dictionary, base_hits: Array) -> bool:
	var stats: Dictionary = sim.catalog[unit.kind]
	var goal: Vector2 = sim.base_pos(1-int(unit.team)) if target.is_empty() else target.pos
	var trigger: float = sim.attack_reach(unit,target,stats)+(float(sim.rules.layout.base_radius) if target.is_empty() else 0)
	if unit.pos.distance_to(goal)>trigger:return false
	for victim in sim.nearby_team(unit.pos,float(stats.splash),1-int(unit.team)):
		if not sim._can_hit_unit(unit,victim,stats):continue
		var raw: float = float(config.structure_damage) if sim.is_structure(victim) and config.has("structure_damage") else sim.raw_damage(stats,victim.kind)
		if sim.is_structure(victim) and bool(config.get("structure_ignore_armor",false)):sim.queue_hit(hits,victim,raw,false,true)
		else:sim.queue_weapon_hit(hits,victim,stats,raw)
		sim.damage_done[int(unit.team)]+=sim.expected_damage(stats,victim)
	if unit.pos.distance_to(sim.base_pos(1-int(unit.team)))<=float(stats.splash)+float(sim.rules.layout.base_radius):
		base_hits[1-int(unit.team)]+=float(config.get("structure_damage",stats.damage))
	sim.self_destruct[unit.id]=true
	sim.events.append({"type":"area_impact","from":unit.pos,"to":unit.pos,"team":unit.team,"kind":unit.kind,"radius":stats.splash})
	return true

func _init() -> void: priority=50
func before_action(ctx: Dictionary) -> void:
	if ctx.can_act and not ctx.handled:ctx.handled=suicide(ctx.sim,owner,ctx.target,ctx.hits,ctx.base_hits)
func on_death(ctx: Dictionary) -> void:
	if ctx.sim.self_destruct.has(owner.id):return
	var stats: Dictionary = ctx.sim.catalog[owner.kind]
	var blast := {"damage":stats.damage,"damage_type":stats.damage_type,"bonus":stats.get("bonus",{}),"bonus_tags":stats.get("bonus_tags",{}),"radius":stats.splash,"target_layers":["ground"],"attacks_structures":true,"attacks_base":true,"ignore_armor":false}
	if config.has("structure_damage"):
		blast.structure_damage=config.structure_damage
		blast.structure_ignore_armor=bool(config.get("structure_ignore_armor",false))
	Areas.launch(ctx.sim,owner,owner.pos,blast)
