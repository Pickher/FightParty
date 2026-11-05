extends RefCounted
const UnitDefinition = preload("res://scripts/units/unit_definition.gd")
## 一个实际战场单位。state 是唯一可变存储；技能/画面使用的是同一个字典引用。
## 不把对象写进 state，快照和重放仍然只有纯数据，也不会形成循环引用。
var definition: UnitDefinition
var state: Dictionary
var id: int:
	get: return int(state.id)
var hp: float:
	get: return float(state.hp)
	set(value): state.hp = clampf(value, 0.0, definition.max_hp)
var shield: float:
	get: return float(state.shield)
	set(value): state.shield = clampf(value, 0.0, definition.max_shield)
var energy: float:
	get: return float(state.energy)
	set(value): state.energy = clampf(value, 0.0, definition.max_energy)
var position: Vector2:
	get: return state.pos
	set(value): state.pos = value

func _init(template: UnitDefinition, unit_id: int, team: int, point: Vector2, tick: int) -> void:
	definition = template
	state = {"id":unit_id, "team":team, "kind":template.kind,
		"pos":point, "prev":point, "hp":template.max_hp, "shield":template.max_shield,
		"energy":template.initial_energy, "born":tick, "locked_target_id":0,
		"last_hit_tick":-1000000, "last_energy_spend_tick":-1000000,
		"cooldown":0.0, "attack_phase":"idle", "attack_phase_left":0.0,
		"attack_target_id":0, "attack_weapon_id":"", "attack_interval":0.0}

func has_tag(tag: String) -> bool:
	return definition.has_tag(tag)

func can_spend_energy(amount: float) -> bool:
	return amount >= 0.0 and energy + 0.000001 >= amount

func spend_energy(amount: float, tick: int) -> bool:
	if not can_spend_energy(amount): return false
	if amount > 0.0:
		energy -= amount
		state.last_energy_spend_tick = tick
	return true

func restore(dt: float, tick: int, tick_rate: float) -> void:
	if hp <= 0.0: return
	var since_hit: float = float(tick - int(state.last_hit_tick)) / tick_rate
	if since_hit >= definition.health_regen_delay:
		hp += definition.health_regen * dt
	if since_hit >= definition.shield_regen_delay:
		shield += definition.shield_regen * dt
	if float(tick - int(state.last_energy_spend_tick)) / tick_rate >= definition.energy_regen_delay:
		energy += definition.energy_regen * dt

## 攻速倍率统一缩短间隔、前摇、后摇，不影响子弹/传播波的飞行速度。
func tick_attack(dt: float, rate: float) -> void:
	var elapsed := dt * maxf(0.0, rate)
	state.cooldown = maxf(0.0, float(state.cooldown) - elapsed)
	state.attack_phase_left = maxf(0.0, float(state.attack_phase_left) - elapsed)
	if state.attack_phase == "backswing" and float(state.attack_phase_left) <= 0.00001:
		state.attack_phase = "idle"

func cancel_attack() -> void:
	if state.attack_phase == "windup":
		# 未开火的前摇可中断；不锁定目标，也不消耗一次完整攻击间隔。
		state.cooldown = 0.0
		state.attack_phase = "idle"
		state.attack_phase_left = 0.0
		state.attack_target_id = 0
		state.attack_weapon_id = ""

func blocks_movement() -> bool:
	return state.attack_phase == "backswing" and float(state.attack_phase_left) > 0.00001

## 每步选敌后调用：换目标、换武器或失去开火条件会取消原前摇。
func ready_to_fire(weapon: Dictionary, target_id: int, eligible: bool) -> bool:
	var weapon_id: String = str(weapon.get("id", "primary"))
	if state.attack_phase == "windup" and (not eligible or target_id != int(state.attack_target_id) or weapon_id != str(state.attack_weapon_id)):
		cancel_attack()
	if not eligible or blocks_movement(): return false
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

func snapshot() -> Dictionary:
	return state.duplicate(true)
