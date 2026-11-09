extends RefCounted
## 普通单位与独立炮位共用的攻击周期；只有纯字典状态，可直接保存快照。

static func create() -> Dictionary:
	return {"locked_target_id":0,"cooldown":0.0,"attack_phase":"idle","attack_phase_left":0.0,
		"attack_target_id":0,"attack_weapon_id":"","attack_interval":0.0}

## 攻速倍率统一缩短间隔、前摇、后摇，不影响子弹/传播波的飞行速度。
static func tick_attack(state: Dictionary, dt: float, rate: float) -> void:
	var elapsed := dt * maxf(0.0, rate)
	state.cooldown = maxf(0.0, float(state.cooldown) - elapsed)
	state.attack_phase_left = maxf(0.0, float(state.attack_phase_left) - elapsed)
	if state.attack_phase == "backswing" and float(state.attack_phase_left) <= 0.00001:
		state.attack_phase = "idle"

static func cancel_attack(state: Dictionary) -> void:
	if state.attack_phase == "windup":
		# 未开火的前摇可中断；不锁定目标，也不消耗一次完整攻击间隔。
		state.cooldown = 0.0
		state.attack_phase = "idle"
		state.attack_phase_left = 0.0
		state.attack_target_id = 0
		state.attack_weapon_id = ""

static func blocks_movement(state: Dictionary) -> bool:
	return state.attack_phase == "backswing" and float(state.attack_phase_left) > 0.00001

## 每步选敌后调用：换目标、换武器或失去开火条件会取消原前摇。
static func ready_to_fire(state: Dictionary, weapon: Dictionary, target_id: int, eligible: bool) -> bool:
	var weapon_id: String = str(weapon.get("id", "primary"))
	if state.attack_phase == "windup" and (not eligible or target_id != int(state.attack_target_id) or weapon_id != str(state.attack_weapon_id)):
		cancel_attack(state)
	if not eligible or blocks_movement(state): return false
	if state.attack_phase == "idle":
		if float(state.cooldown) > 0.00001: return false
		state.attack_target_id = target_id
		state.attack_weapon_id = weapon_id
		state.attack_phase = "windup"
		state.attack_phase_left = maxf(0.0, float(weapon.get("windup", 0)))
		state.attack_interval = maxf(float(weapon.interval), float(weapon.get("windup", 0)) + float(weapon.get("backswing", 0)))
		state.cooldown = state.attack_interval
	if float(state.attack_phase_left) > 0.00001: return false
	state.attack_phase = "backswing"
	state.attack_phase_left = maxf(0.0, float(weapon.get("backswing", 0)))
	if float(state.attack_phase_left) <= 0.00001: state.attack_phase = "idle"
	return true

