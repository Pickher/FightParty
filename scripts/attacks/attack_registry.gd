extends RefCounted
## 新增攻击类型：实现AttackBehavior并在此数组注册一次，无需改兵种/基地/炮位调用。
const Behavior = preload("res://scripts/attacks/attack_behavior.gd")
const TYPE_SCRIPTS := [
	preload("res://scripts/attacks/projectile_attack.gd"),
	preload("res://scripts/attacks/beam_attack.gd"),
	preload("res://scripts/attacks/line_attack.gd")
]
const ALIASES := {"instant":"projectile","fixed":"projectile","distance":"projectile","wave":"line"}
static var _types: Dictionary = {}
static var _ordered: Array = []

static func _initialize() -> void:
	if not _types.is_empty():return
	for behavior_script in TYPE_SCRIPTS:
		var behavior: Behavior = behavior_script.new()
		assert(not _types.has(behavior.type_id()),"攻击类型重复："+behavior.type_id())
		_types[behavior.type_id()]=behavior
		_ordered.append(behavior)

## 仅在读配置/构造武器时复制参数；旧版枚举保留兼容，运行中不重复分配。
static func normalize_delivery(parameters: Dictionary) -> Dictionary:
	var result := parameters.duplicate(true)
	var old_type: String = str(result.get("type","instant"))
	result.type=ALIASES.get(old_type,old_type)
	if result.type=="projectile":
		if old_type in ["instant","fixed","distance"]:
			result.flight="contact" if old_type=="instant" else old_type
		elif not result.has("flight"):
			result.flight="distance" if result.has("speed") else ("fixed" if result.has("seconds") else "contact")
	return result

static func for_delivery(delivery: Dictionary) -> Behavior:
	_initialize()
	var attack_type: String = str(delivery.get("type","projectile"))
	attack_type=str(ALIASES.get(attack_type,attack_type))
	assert(_types.has(attack_type),"未知攻击类型："+attack_type)
	return _types[attack_type]

static func for_weapon(weapon: Dictionary) -> Behavior:
	var delivery = weapon.get("delivery")
	return for_delivery({} if delivery==null else delivery)

static func advance(sim, frame: Dictionary) -> void:
	_initialize()
	# 注册顺序固定，保持不同类型在同一步中的结算顺序一致。
	for behavior in _ordered:behavior.advance(sim,frame)

static func target_died(sim, dead: Dictionary) -> void:
	_initialize()
	for behavior in _ordered:behavior.target_died(sim,dead)
