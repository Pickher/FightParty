extends RefCounted
const AttackTypes = preload("res://scripts/attacks/attack_registry.gd")
## 独立攻击模式。interval 是整轮出手结束后的等待时间，弹道另行推进。
var id: String = "primary"
var damage: float = 0.0
var healing: float = 0.0
## 每轮独立命中次数，每次都使用完整单段伤害并单独扣甲。
var hit_count: int = 1
var strike_offsets: Array = []
var attack_duration: float = 0.1
var delivery: Dictionary = {}
var continue_on_target_death: bool = false
var shield_bonus: float = 0.0
var range_from_edge: bool = false
var damage_type: String = "physical"
var bonus: Dictionary = {}
var bonus_tags: Dictionary = {}
var range: float = 0.0
var interval: float = 1.0
var windup: float = 0.0
var backswing: float = 0.0
var armor_multiplier: float = 1.0
var splash_rings: Array = []
var splash: float = 0.0
var splash_multiplier: float = 1.0
## 可选内圈，半径为总溅射半径的此比例；0表示沿用单档溅射。
var splash_inner_ratio: float = 0.0
var splash_inner_multiplier: float = 1.0
var target_layers: Array = ["ground"]
var attacks_base: bool = true
var attacks_structures: bool = true
var _data: Dictionary = {}

func _init(parameters: Dictionary = {}, weapon_id: String = "primary") -> void:
	# 只保留武器字段，避免把整份兵种/技能配置递归复制进每套武器。
	for key in ["label"]:
		if parameters.has(key):
			var value = parameters[key]
			_data[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	id = str(parameters.get("id", weapon_id))
	damage = maxf(0.0, float(parameters.get("damage", 0)))
	healing = maxf(0.0,float(parameters.get("healing",0)))
	hit_count = maxi(1,int(parameters.get("hit_count",1)))
	attack_duration = maxf(0.001,float(parameters.get("attack_duration",0.1)))
	strike_offsets=parameters.get("strike_offsets",[]).duplicate()
	delivery = AttackTypes.normalize_delivery(parameters.get("delivery",{"type":"instant"}))
	continue_on_target_death = bool(parameters.get("continue_on_target_death",float(parameters.get("splash",0))>0))
	shield_bonus = maxf(0.0,float(parameters.get("shield_bonus",0)))
	range_from_edge = bool(parameters.get("range_from_edge",false))
	damage_type = str(parameters.get("damage_type", "physical"))
	assert(damage_type in ["physical", "spell", "true"], "未知伤害类型：" + damage_type)
	bonus = parameters.get("bonus", {}).duplicate(true)
	bonus_tags = parameters.get("bonus_tags", {}).duplicate(true)
	range = maxf(0.0, float(parameters.get("range", 0)))
	windup = maxf(0.0, float(parameters.get("windup", 0)))
	backswing = maxf(0.0, float(parameters.get("backswing", 0)))
	interval = maxf(0.0 if AttackTypes.for_delivery(delivery).is_continuous() else 0.001, float(parameters.get("interval", 1)))
	armor_multiplier=maxf(0.0,float(parameters.get("armor_multiplier",1)))
	splash_rings=parameters.get("splash_rings",[]).duplicate(true)
	splash_rings.sort_custom(func(a,b):return float(a.radius)<float(b.radius))
	splash = maxf(0.0, float(parameters.get("splash", 0)))
	splash_multiplier = clampf(float(parameters.get("splash_multiplier",1.0)),0.0,1.0)
	splash_inner_ratio = clampf(float(parameters.get("splash_inner_ratio",0.0)),0.0,1.0)
	splash_inner_multiplier = clampf(float(parameters.get("splash_inner_multiplier",splash_multiplier)),0.0,1.0)
	target_layers = parameters.get("target_layers", ["ground"]).duplicate()
	attacks_base = bool(parameters.get("attacks_base", true))
	attacks_structures = bool(parameters.get("attacks_structures", attacks_base))

func to_data() -> Dictionary:
	var result := _data.duplicate(true)
	result.merge({"id":id, "damage":damage, "healing":healing, "hit_count":hit_count, "shield_bonus":shield_bonus, "range_from_edge":range_from_edge, "damage_type":damage_type,
		"attack_duration":attack_duration,"strike_offsets":strike_offsets.duplicate(),"delivery":delivery.duplicate(true),"continue_on_target_death":continue_on_target_death,
		"bonus":bonus.duplicate(true), "bonus_tags":bonus_tags.duplicate(true), "range":range, "interval":interval,
		"windup":windup, "backswing":backswing, "armor_multiplier":armor_multiplier,"splash_rings":splash_rings.duplicate(true),"splash":splash, "splash_multiplier":splash_multiplier,
		"splash_inner_ratio":splash_inner_ratio, "splash_inner_multiplier":splash_inner_multiplier,
		"target_layers":target_layers.duplicate(), "attacks_base":attacks_base,
		"attacks_structures":attacks_structures}, true)
	return result

static func ignores_armor(weapon: Dictionary) -> bool:
	return str(weapon.get("damage_type", "physical")) in ["spell", "true"]

## 仅用于次目标；主目标始终不衰减。距离按爆心与受击者中心计算。
static func splash_damage_multiplier(weapon: Dictionary, distance: float) -> float:
	for ring in weapon.get("splash_rings",[]):
		if distance<=float(ring.radius):return float(ring.multiplier)
	if not weapon.get("splash_rings",[]).is_empty():return 0.0
	var inner_ratio: float = float(weapon.get("splash_inner_ratio",0.0))
	var outer: float = float(weapon.get("splash_multiplier",1.0))
	if inner_ratio > 0.0 and distance <= float(weapon.splash) * inner_ratio:
		return float(weapon.get("splash_inner_multiplier",outer))
	return outer
