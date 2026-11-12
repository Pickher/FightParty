extends RefCounted
## 主对抗经济。数值来自 rules.economy；资源、占领与支付时钟独立于战斗武器。
var config: Dictionary
var gas: Array = [0, 0]
var cores: Array = [0, 0]
var gasworks: Array = [0, 0]
var center_owner: int = -1
var last_income_tick: int = 0
var last_scan_tick: int = -1
var last_tier: int = 0

func _init(settings: Dictionary) -> void:
	config = settings.duplicate(true)

func base_income(wave: int) -> int:
	var amount := 0
	for tier in config.income_tiers:
		if wave >= int(tier.wave): amount = int(tier.minerals)
	return amount

func gasworks_limit(wave: int) -> int:
	return int(config.gasworks_expanded_limit) if wave >= int(config.gasworks_unlock_wave) else int(config.gasworks_initial_limit)

func rates(team: int, wave: int) -> Dictionary:
	if wave >= int(config.income_stop_wave): return {"minerals":0, "gas":0}
	var diverted := int(round(base_income(wave) * float(config.gasworks_fraction) * int(gasworks[team])))
	return {"minerals":base_income(wave)-diverted+(int(config.center_bonus) if center_owner==team else 0), "gas":diverted}

func set_gasworks(sim, team: int, count: int) -> String:
	if team < 0 or team > 1: return "无效阵营"
	if sim.finished or sim.wave >= int(config.income_stop_wave): return "经济已停止"
	if count < 0 or count > gasworks_limit(sim.wave): return "超出当前气厂上限"
	gasworks[team] = count
	sim._log(team,{"type":"gasworks", "count":count})
	return ""

## 当前没有指挥官阵营，采用参考图无阵营的 1:1、无限次兑换。
func exchange_gas(sim, team: int) -> String:
	if team < 0 or team > 1: return "无效阵营"
	if sim.finished: return "对局已结束"
	var amount: int = int(gas[team])
	if amount <= 0: return "没有可兑换的瓦斯"
	gas[team] = 0
	sim.minerals[team] += amount
	sim._log(team,{"type":"exchange_gas", "amount":amount})
	return ""

func reward_outpost(sim, team: int) -> void:
	cores[team] += int(config.outpost_core_reward)
	sim.events.append({"type":"core_reward", "team":team, "amount":int(config.outpost_core_reward)})

func center_active(wave: int) -> bool:
	return wave >= int(config.center_unlock_wave)

func center_pos() -> Vector2:
	return Vector2(float(config.center_x),float(config.center_y))

func _capture(sim) -> void:
	# 原图为自动施法选取附近单位。双方等距时保留原归属，避免遍历顺序偏袒某方。
	var nearest: Array = [INF, INF]
	var radius_squared := pow(float(config.center_capture_radius),2)
	for unit in sim.units:
		if float(unit.hp)<=0 or sim.is_structure(unit) or bool(unit.get("summoned",false)) or sim.has_tag(unit,"worker"): continue
		var distance: float = unit.pos.distance_squared_to(center_pos())
		if distance <= radius_squared:
			nearest[int(unit.team)] = minf(float(nearest[int(unit.team)]),distance)
	if is_equal_approx(float(nearest[0]),float(nearest[1])): return
	var owner := 0 if float(nearest[0])<float(nearest[1]) else 1
	if owner != center_owner:
		center_owner = owner
		sim.events.append({"type":"center_captured", "team":owner})
		sim.journal.economy_events.append({"tick":sim.tick,"type":"center_captured","team":owner})

func step(sim) -> void:
	var rate: int = int(sim.rules.tick_rate)
	if sim.finished or float(sim.bases[0])<=0 or float(sim.bases[1])<=0: return
	var tier := base_income(sim.wave)
	if last_tier != tier:
		last_tier = tier
		sim.events.append({"type":"income_tier", "amount":tier})
	if sim.wave >= int(config.income_stop_wave): return
	if center_active(sim.wave) and (last_scan_tick<0 or sim.tick-last_scan_tick>=int(float(config.center_scan_seconds)*rate)):
		last_scan_tick = sim.tick
		_capture(sim)
	if sim.tick-last_income_tick < int(float(config.income_seconds)*rate): return
	last_income_tick = sim.tick
	for team in range(2):
		var income := rates(team,sim.wave)
		sim.minerals[team] += int(income.minerals)
		gas[team] += int(income.gas)
	sim.events.append({"type":"income"})

func snapshot(team: int, wave: int) -> Dictionary:
	return {"gas":gas[team],"cores":cores[team],"gasworks":gasworks[team],"gasworks_limit":gasworks_limit(wave),
		"income":rates(team,wave),"center_owner":center_owner,"center_active":center_active(wave)}

func ledger() -> Dictionary:
	return {"gas":gas.duplicate(),"cores":cores.duplicate(),"gasworks":gasworks.duplicate(),"center_owner":center_owner}
