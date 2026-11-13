extends RefCounted
## 每个单位、每个挂载技能各自创建实例。组件不持有 sim，避免引用环。
var id: String = ""
var owner: Dictionary = {}
var config: Dictionary = {}
var state: Dictionary = {}
var priority: int = 100
var hit_effect := false
var published_keys: Array = []
var view_fields: Array = []

func configure(skill_id: String, unit: Dictionary, parameters: Dictionary) -> void:
	id=skill_id
	owner=unit
	config=parameters.duplicate(true)
	state={}

func on_spawn(_sim) -> void: pass
func on_removed(_sim) -> void: pass
func on_frame(_ctx: Dictionary) -> void: pass
func before_target(_ctx: Dictionary) -> bool: return false
func select_target(_sim, target: Dictionary) -> Dictionary: return target
func on_target(_ctx: Dictionary) -> void: pass
func before_action(_ctx: Dictionary) -> void: pass
func after_action(_ctx: Dictionary) -> void: pass
func moves_while_attacking() -> bool: return false
func on_attack(_ctx: Dictionary) -> bool: return false
func after_attack(_ctx: Dictionary) -> void: pass
func on_hit(_ctx: Dictionary) -> void: pass
func on_death(_ctx: Dictionary) -> void: pass
func on_unit_death(_ctx: Dictionary) -> void: pass
func on_survived(_ctx: Dictionary) -> void: pass
func modify_weapon(_sim, weapon: Dictionary) -> Dictionary: return weapon
func modify_search(_sim, weapon: Dictionary) -> Dictionary: return weapon
func can_target(_sim, _victim: Dictionary) -> bool: return true
func discovery_radius(_sim, value: float) -> float: return value
func target_priority(_sim, _victim: Dictionary) -> int: return 0
func has_target_priority() -> bool: return false
func contributes_damage() -> bool: return false
func movement_multiplier(_sim) -> float: return 1.0
func attack_rate(_sim) -> float: return 1.0
func attack_count(_sim, value: int) -> int: return value
func damage_multiplier(_ctx: Dictionary) -> float: return 1.0
func absorb(_ctx: Dictionary, raw: float) -> float: return raw
func armor_bonus(_sim) -> float: return 0.0
func shield_armor_bonus(_sim) -> float: return 0.0

## 兼容当前画面读取的平面字段；逻辑状态以组件 state 为准，投影为深拷贝。
func publish() -> void:
	for key in published_keys:
		if not state.has(key):owner.erase(key)
	published_keys=[]
	for key in view_fields:
		if state.has(key):
			var value = state[key]
			owner[key]=value.duplicate(true) if value is Dictionary or value is Array else value
			published_keys.append(key)

func snapshot() -> Dictionary:
	return state.duplicate(true)

## 主动技能在确认可施放后、创建效果前调用；默认费用为 0，保持旧配置有效。
## 扣费落在 Unit 的公共能量池，多个技能不会各自持有一份能量。
func can_pay_energy(sim) -> bool:
	var cost := maxf(0.0, float(config.get("energy_cost", 0)))
	return cost == 0.0 or sim.can_spend_energy(owner, cost)

func pay_energy(sim) -> bool:
	var cost := maxf(0.0, float(config.get("energy_cost", 0)))
	return cost == 0.0 or sim.spend_energy(owner, cost)
