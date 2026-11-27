extends "res://scripts/skills/skill.gd"
const Areas = preload("res://scripts/skills/services/area_service.gd")

func _blast_radius(sim, unit: Dictionary, stats: Dictionary) -> float:
	if config.has("blast_edge_padding"):
		return float(sim.body_radius(unit)) + float(config.blast_edge_padding)
	return float(stats.splash)

func _init() -> void: priority=50

func on_attack(ctx: Dictionary) -> bool:
	var sim = ctx.sim
	var unit: Dictionary = owner
	var stats: Dictionary = ctx.weapon
	var origin: Vector2 = ctx.source_position
	var target: Dictionary = ctx.target
	var enemy := 1-int(unit.team)
	# 接触射弹已检查单位距离；基地没有单位 ID，出手当刻也需确认仍贴边。
	if target.is_empty() and origin.distance_to(sim.base_pos(enemy)) > sim.attack_reach(unit,target,stats)+float(sim.rules.layout.base_radius):
		return true
	var radius := _blast_radius(sim,unit,stats)
	var overlap := config.has("blast_edge_padding")
	var fraction := float(ctx.fire_offset)/float(ctx.dt)
	var search_radius: float = radius+float(ctx.motion_margin)+(float(sim.max_body_radius) if overlap else 0.0)
	for victim in sim.nearby_team(origin,search_radius,enemy):
		if not sim._can_hit_unit(unit,victim,stats):continue
		var position: Vector2 = victim.pos.lerp(ctx.moves.get(victim.id,victim.pos),fraction)
		var victim_reach: float = radius+(float(sim.body_radius(victim)) if overlap else 0.0)
		if position.distance_squared_to(origin)>victim_reach*victim_reach:continue
		var raw: float = float(config.structure_damage) if sim.is_structure(victim) and config.has("structure_damage") else sim.raw_damage(stats,victim.kind)
		if sim.is_structure(victim) and bool(config.get("structure_ignore_armor",false)):sim.queue_hit(ctx.hits,victim,raw,false,true)
		else:sim.queue_weapon_hit(ctx.hits,victim,stats,raw)
		sim.damage_done[int(unit.team)]+=sim.expected_damage(stats,victim)
	if origin.distance_to(sim.base_pos(enemy))<=radius+float(sim.rules.layout.base_radius):
		ctx.base_hits[enemy]+=float(config.get("structure_damage",stats.damage))
	sim.self_destruct[unit.id]=true
	sim.events.append({"type":"area_impact","from":origin,"to":origin,"team":unit.team,"kind":unit.kind,"radius":radius})
	return true

func on_death(ctx: Dictionary) -> void:
	if ctx.sim.self_destruct.has(owner.id):return
	var stats: Dictionary = ctx.sim.catalog[owner.kind]
	var blast := {"damage":stats.damage,"damage_type":stats.damage_type,"bonus":stats.get("bonus",{}),"bonus_tags":stats.get("bonus_tags",{}),"radius":_blast_radius(ctx.sim,owner,stats),"intersect_body":config.has("blast_edge_padding"),"target_layers":["ground"],"attacks_structures":true,"attacks_base":true,"ignore_armor":false}
	if config.has("structure_damage"):
		blast.structure_damage=config.structure_damage
		blast.structure_ignore_armor=bool(config.get("structure_ignore_armor",false))
	Areas.launch(ctx.sim,owner,owner.pos,blast)
