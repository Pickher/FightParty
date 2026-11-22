extends RefCounted
const AttackCycle = preload("res://scripts/units/attack_cycle.gd")
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
	state.merge(AttackCycle.create(),true)

## 同一实体更换模板。保留伤势比例、外部状态及别人锁定的 ID。
func change_form(template: UnitDefinition) -> void:
	var health_ratio := hp / definition.max_hp
	var previous_serial := int(state.attack_serial)
	definition = template
	state.kind = template.kind
	hp = health_ratio * template.max_hp
	state.shield = minf(shield, template.max_shield)
	state.energy = minf(energy, template.max_energy)
	state.merge(AttackCycle.create(), true)
	# 旧武器未发射的段作废，已飞出的弹体继续使用发射时的快照。
	state.attack_serial = previous_serial
	state.attack_cancelled_through = previous_serial
	state.erase("attack_blocked_this_frame")
	state.erase("engage_id")
	state.erase("beam_state")

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
	# 回血、回盾独立判断等待时间；回盾不要求生命先恢复到上限。
	if since_hit >= definition.health_regen_delay:
		hp += definition.health_regen * dt
	if since_hit >= definition.shield_regen_delay:
		shield += definition.shield_regen * dt
	if float(tick - int(state.last_energy_spend_tick)) / tick_rate >= definition.energy_regen_delay:
		energy += definition.energy_regen * dt

## 攻击状态机同时供普通单位和驻军炮位使用。
func tick_attack(dt: float, rate: float) -> void:
	AttackCycle.tick_attack(state,dt,rate)
func cancel_attack() -> void:
	AttackCycle.cancel_attack(state)
func blocks_movement() -> bool:
	return AttackCycle.blocks_movement(state)
func ready_to_fire(weapon: Dictionary, target_id: int, eligible: bool) -> bool:
	return AttackCycle.ready_to_fire(state,weapon,target_id,eligible)

func snapshot() -> Dictionary:
	return state.duplicate(true)
