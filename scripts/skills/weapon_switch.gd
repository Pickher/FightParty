extends "res://scripts/skills/skill.gd"

func best_index(sim, unit: Dictionary, target: Dictionary) -> int:
	var weapons: Array = config.weapons
	var current: int = int(state.get("weapon_index", 0))
	if config.get("policy","") == "air_superiority":
		if target.is_empty() or sim.catalog[target.kind].get("layer","ground") != "air":
			return 2
		var light: Array = []
		var heavy := 0
		var scan_range := 0.0
		for weapon in weapons:scan_range=maxf(scan_range,float(weapon.range))
		for enemy in sim.nearby_team(unit.pos,scan_range,1-int(unit.team)):
			if enemy.hp<=0 or sim.catalog[enemy.kind].get("layer","ground")!="air":
				continue
			var armor: String = sim.catalog[enemy.kind].get("armor_type","none")
			if armor=="light":light.append(enemy)
			elif armor=="heavy":heavy+=1
		if light.size()>=int(config.light_air_threshold) and light.size()>heavy:
			for center in light:
				var cluster := 0
				for enemy in light:
					if center.pos.distance_to(enemy.pos)<=float(config.cluster_radius):cluster+=1
				if cluster>=int(config.light_air_threshold):return 1
		return int(config.get("default_index",0))
	if target.is_empty():
		if bool(weapons[current].get("attacks_base", true)):
			return current
		for i in range(weapons.size()):
			if bool(weapons[i].get("attacks_base", true)):
				return i
		return current
	var layer: String = str(sim.catalog[target.kind].get("layer", "ground"))
	var best := current
	var best_score := -1.0
	for i in range(weapons.size()):
		var layers: Array = weapons[i].get("target_layers", sim.catalog[unit.kind].get("target_layers", ["ground"]))
		if not layers.has(layer):
			continue
		var score: float = sim.expected_damage(weapons[i], target)*int(weapons[i].get("hit_count",1)) / (float(weapons[i].interval)+float(weapons[i].get("attack_duration",0)))
		if score > best_score + 0.00001 or (is_equal_approx(score, best_score) and i == current):
			best = i
			best_score = score
	return best

## 每步在开火前调用：需要换武器时开始计时并发出事件。返回本步能否开火。
func prepare(sim, unit: Dictionary, target: Dictionary) -> bool:
	var wanted := best_index(sim, unit, target)
	if config.get("policy","")=="air_superiority":
		# 对地武器始终可用；只有两套对空模式相互切换需要切换耗时。
		if wanted==2:
			state.weapon_index=2
			return true
		if wanted!=int(state.get("air_weapon_index",int(config.get("default_index",0)))):
			state.air_weapon_index=wanted
			state.switch_until_tick=sim.tick+ceili(float(config.switch_seconds)*float(sim.rules.tick_rate))
			sim.events.append({"type":"weapon_switch","id":unit.id,"weapon":str(config.weapons[wanted].id)})
		state.weapon_index=wanted
		return sim.tick>=int(state.get("switch_until_tick",0))
	if wanted != int(state.get("weapon_index", 0)):
		state.weapon_index = wanted
		state.switch_until_tick = sim.tick + ceili(float(config.switch_seconds) * float(sim.rules.tick_rate))
		sim.events.append({"type":"weapon_switch","id":unit.id,"weapon":str(config.weapons[wanted].id)})
	return sim.tick >= int(state.get("switch_until_tick", 0))

var weapon_cache: Dictionary = {}
func _init() -> void:
	priority=40
	view_fields=["weapon_index","air_weapon_index","switch_until_tick"]
func on_target(ctx: Dictionary) -> void:
	if owner.get("attack_phase","")=="firing":return
	ctx.armed=prepare(ctx.sim,owner,ctx.target)
func modify_weapon(_sim, weapon: Dictionary) -> Dictionary:
	var index: int = int(state.get("weapon_index",0))
	if not weapon_cache.has(index):
		var current: Dictionary = weapon.duplicate(true)
		current.erase("bonus")
		current.merge(config.weapons[index].duplicate(true),true)
		weapon_cache[index]=current
	return weapon_cache[index]
func modify_search(sim, _weapon: Dictionary) -> Dictionary:
	var result: Dictionary = sim.definitions[owner.kind].primary_weapon_data.duplicate(true)
	result.target_layers=[]
	for mode in config.weapons:
		result.range=maxf(float(result.range),float(mode.range))
		for layer in mode.target_layers:
			if not result.target_layers.has(layer):result.target_layers.append(layer)
	return result
func has_target_priority() -> bool: return config.has("preferred_layer")
func target_priority(sim, victim: Dictionary) -> int:
	return 1 if config.has("preferred_layer") and sim.catalog[victim.kind].get("layer","ground")==config.preferred_layer else 0
