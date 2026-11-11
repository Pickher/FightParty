extends RefCounted
## 普通单位与独立炮位共用的攻击周期；只有纯字典状态，可直接保存快照。

static func create() -> Dictionary:
	return {"locked_target_id":0,"cooldown":0.0,"attack_phase":"idle","attack_phase_left":0.0,
		"attack_target_id":0,"attack_weapon_id":"","attack_interval":0.0,"attack_serial":0,
		"attack_cancelled_through":-1,"attack_emitted":false,"attack_ready_offset":0.0,"attack_frame_dt":0.0,"attack_rate":1.0}

## 攻速倍率统一缩短间隔、前摇、后摇，不影响子弹/传播波的飞行速度。
static func tick_attack(state: Dictionary, dt: float, rate: float) -> void:
	var elapsed := dt * maxf(0.0, rate)
	state.attack_frame_dt = dt
	state.attack_rate = maxf(0.0,rate)
	state.attack_blocked_this_frame = state.attack_phase in ["firing","backswing"] and float(state.attack_phase_left)>0.00001
	# 保留冷却在本步内结束的准确时刻；0.125秒等节奏不会逐轮向上取整。
	if state.attack_phase in ["firing","backswing"]:
		var round_left: float = float(state.attack_phase_left)
		state.attack_ready_offset=clampf((round_left+float(state.attack_interval))/maxf(rate,0.000001),0.0,dt)
		state.attack_phase_left=maxf(0.0,round_left-elapsed)
		# 本轮尚未打完时cooldown保持0；结束后用本步剩余时间推进轮后等待。
		if elapsed+0.000001>=round_left:
			state.attack_phase="idle"
			state.cooldown=maxf(0.0,float(state.attack_interval)-maxf(0.0,elapsed-round_left))
	else:
		state.attack_ready_offset=clampf(float(state.cooldown)/maxf(rate,0.000001),0.0,dt)
		state.cooldown=maxf(0.0,float(state.cooldown)-elapsed)

static func cancel_attack(state: Dictionary) -> void:
	# 包含本步刚结束、但尚未调度最后一段的序列。
	state.attack_cancelled_through = int(state.get("attack_serial",0))
	if state.attack_phase in ["windup","firing"]:
		# 序列检查serial取消未发出的段；已发射的弹体独立存在。
		state.cooldown = float(state.attack_interval) if bool(state.get("attack_emitted",false)) else 0.0
		state.attack_phase = "idle"
		state.attack_phase_left = 0.0
		state.attack_target_id = 0
		state.attack_weapon_id = ""

static func blocks_movement(state: Dictionary) -> bool:
	return bool(state.get("attack_blocked_this_frame",false)) or (state.attack_phase in ["firing","backswing"] and float(state.attack_phase_left)>0.00001)

## 启动一次出手序列，不在这里直接结算伤害。
static func ready_to_fire(state: Dictionary, weapon: Dictionary, target_id: int, eligible: bool) -> bool:
	var weapon_id: String = str(weapon.get("id", "primary"))
	if not eligible or state.attack_phase in ["firing","backswing"] or float(state.cooldown)>0.00001 or float(state.get("attack_rate",1))<=0: return false
	state.attack_target_id = target_id
	state.attack_weapon_id = weapon_id
	state.attack_serial = int(state.get("attack_serial",0))+1
	state.attack_emitted = false
	state.attack_phase = "firing"
	state.attack_blocked_this_frame = true
	var duration: float = float(weapon.get("windup",0))+float(weapon.get("attack_duration",0.1))+float(weapon.get("backswing",0))
	var remaining: float = maxf(0.0,float(state.get("attack_frame_dt",0))-float(state.get("attack_ready_offset",0)))*float(state.get("attack_rate",1))
	state.attack_phase_left = maxf(0.0,duration-remaining)
	state.attack_interval = float(weapon.interval)
	state.cooldown = 0.0
	if remaining+0.000001>=duration:
		state.attack_phase="idle"
		state.cooldown=maxf(0.0,float(weapon.interval)-maxf(0.0,remaining-duration))
	return true

