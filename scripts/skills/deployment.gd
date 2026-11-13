extends "res://scripts/skills/skill.gd"
const Deployment = preload("res://scripts/skills/services/deployment_service.gd")

func _init() -> void:
	priority=30
	view_fields=["siege_state","siege_until_tick","siege_scan_tick","siege_scan_ids"]
func on_spawn(_sim) -> void: Deployment.initialize(state)

## 配有架设武器的单位在选定本步武器前推进变形，避免刚架好仍用移动炮开火。
func before_target(ctx: Dictionary) -> bool:
	if not config.has("weapon") or not ctx.can_act:return false
	var sim = ctx.sim
	var weapon: Dictionary = config.weapon
	var target: Dictionary = sim._target(owner)
	var goal: Vector2 = sim.base_pos(1-int(owner.team)) if target.is_empty() else target.pos
	var reach: float = float(weapon.range)
	var base_in_range: bool = target.is_empty() and bool(weapon.attacks_base) and owner.pos.distance_to(goal)<=reach+float(sim.rules.layout.base_radius)
	var in_range: bool = owner.pos.distance_to(goal)<=reach or base_in_range
	ctx.can_act=Deployment.can_act(sim,owner,state,in_range,base_in_range,ctx.motion,
		{"config":config,"range":reach,"target_layers":weapon.target_layers,"attacks_structures":weapon.attacks_structures})
	return false

func before_action(ctx: Dictionary) -> void:
	if config.has("weapon"):return
	if not ctx.can_act:return
	ctx.can_act=Deployment.can_act(ctx.sim,owner,state,ctx.distance<=ctx.reach,ctx.target.is_empty() and ctx.distance<=ctx.reach and bool(ctx.weapon.get("attacks_base",true)),ctx.motion,{"config":config})

func modify_weapon(_sim, weapon: Dictionary) -> Dictionary:
	if config.has("weapon") and state.get("siege_state","mobile")=="deployed":return config.weapon
	return weapon

func modify_search(_sim, weapon: Dictionary) -> Dictionary:
	# 移动模式也能发现架设炮射程附近的敌人；能否开火仍由当前武器判定。
	return config.weapon if config.has("weapon") else weapon

func movement_multiplier(_sim) -> float:
	return 1.0 if state.get("siege_state","mobile")=="mobile" else 0.0

func armor_bonus(sim) -> float:
	if not config.has("armor_override") or state.get("siege_state","mobile")!="deployed": return 0.0
	return float(config.armor_override)-float(sim.catalog[owner.kind].armor)
