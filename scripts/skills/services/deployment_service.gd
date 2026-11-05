extends RefCounted

## 所有挂载 deployment 技能的单位共用这组状态。
static func initialize(state: Dictionary) -> void:
	state["siege_state"] = "mobile"
	state["siege_until_tick"] = 0
	state["siege_scan_tick"] = 0
	state["siege_scan_ids"] = []

## 少量敌人需要连续两次扫描确认同一 ID，多于阈值则立即架设。
## 已展开/正在展开时，120% 射程内仍有靠近的敌人就继续保持。
## motion 是统一保存的上一步位移，不依赖本步单位处理顺序。
static func can_act(sim, unit: Dictionary, state: Dictionary, in_range: bool, base_in_range: bool, motion: Dictionary, context: Dictionary = {}) -> bool:
	var stats: Dictionary = sim.catalog[unit.kind]
	var config: Dictionary = context.config
	var ids: Array = []
	var approaching := false
	var reach: float = float(context.get("range",stats.range))
	var center: Vector2 = context.get("center",unit.pos)
	var layers: Array = context.get("target_layers",stats.get("target_layers",["ground"]))
	var hits_structures: bool = bool(stats.get("attacks_structures", stats.get("attacks_base", true)))
	for other in sim.nearby_team(center, reach * float(config.hold_range_multiplier), 1 - int(unit.team)):
		if other.hp <= 0 or (not hits_structures and sim.is_structure(other)):
			continue
		if not layers.has(sim.catalog[other.kind].get("layer","ground")):
			continue
		if context.has("sector_angle_degrees"):
			var offset: Vector2 = other.pos-center
			var direction := Vector2.RIGHT if unit.team==0 else Vector2.LEFT
			if offset.length_squared()>0.000001 and direction.dot(offset.normalized())<cos(deg_to_rad(float(context.sector_angle_degrees)*0.5)):
				continue
		if center.distance_squared_to(other.pos) <= reach * reach:
			ids.append(other.id)
		var displacement: Vector2 = motion.get(other.id, Vector2.ZERO)
		if displacement.dot(center - other.pos) > 0.001:
			approaching = true
	var keep_deployed: bool = not ids.is_empty() or approaching or base_in_range
	match state.siege_state:
		"mobile":
			# 基地不会短暂进出射程，仍可直接启动架设。
			var confirmed: bool = base_in_range or ids.size() > int(config.deploy_enemy_threshold)
			if sim.tick >= int(state.siege_scan_tick):
				for id in ids:
					if state.siege_scan_ids.has(id):
						confirmed = true
				state.siege_scan_ids = ids
				state.siege_scan_tick = sim.tick + maxi(1, ceili(float(config.scan_seconds) * float(sim.rules.tick_rate)))
			if not confirmed:
				# 已进入射程时停下来观察，不能在等待确认时绕过架设直接开炮。
				return not in_range
			state.siege_state = "deploying"
			state.siege_until_tick = sim.tick + ceili(float(config.deploy_seconds) * float(sim.rules.tick_rate))
			return false
		"deploying":
			if keep_deployed:
				if sim.tick < int(state.siege_until_tick):
					return false
				state.siege_state = "deployed"
				return in_range
		"deployed":
			if keep_deployed:
				return in_range
		"packing":
			if sim.tick >= int(state.siege_until_tick):
				state.siege_state = "mobile"
			return false
	# 只有射程内无敌人，且外围无靠近敌人，才收起；清除旧扫描，避免复用旧确认。
	state.siege_state = "packing"
	state.siege_until_tick = sim.tick + ceili(float(config.pack_seconds) * float(sim.rules.tick_rate))
	state.siege_scan_ids = []
	state.siege_scan_tick = 0
	unit.locked_target_id = 0
	return false

