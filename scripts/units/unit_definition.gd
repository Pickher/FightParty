extends RefCounted
const WeaponDefinition = preload("res://scripts/units/weapon_definition.gd")
## 所有兵种共用的模板，构造后作为只读数据使用；不保存任何战场状态。
var kind: String
var max_hp: float
var max_shield: float
var max_energy: float
var initial_energy: float
var speed: float
var armor: float
var shield_armor: float
var armor_type: String
var race: String
var layer: String
var unit_type: String
var tags: Array = []
var size: Vector2
var collision_radius: float
var separate_when_stopped: bool
var health_regen: float
var health_regen_delay: float
var shield_regen: float
var shield_regen_delay: float
var energy_regen: float
var energy_regen_delay: float
var skills: Dictionary = {}
var weapons: Dictionary = {}
var primary_weapon: WeaponDefinition
var primary_weapon_data: Dictionary
var _data: Dictionary = {}

func _init(unit_kind: String, parameters: Dictionary, rules: Dictionary = {}) -> void:
	kind = unit_kind
	_data = parameters.duplicate(true)
	max_hp = maxf(1.0, float(parameters.get("hp", 1)))
	max_shield = maxf(0.0, float(parameters.get("shield", 0)))
	max_energy = maxf(0.0, float(parameters.get("energy", 0)))
	initial_energy = clampf(float(parameters.get("initial_energy", max_energy)), 0.0, max_energy)
	speed = maxf(0.0, float(parameters.get("speed", 0)))
	armor = maxf(0.0, float(parameters.get("armor", 0)))
	shield_armor = maxf(0.0, float(parameters.get("shield_armor", 0)))
	armor_type = str(parameters.get("armor_type", "none"))
	race = str(parameters.get("race", ""))
	layer = str(parameters.get("layer", "ground"))
	unit_type = str(parameters.get("unit_type", "structure" if parameters.get("structure", false) else "unit"))
	tags = parameters.get("tags", []).duplicate()
	for tag in [layer, armor_type, unit_type]:
		if not tags.has(tag): tags.append(tag)
	var dimensions: Array = parameters.get("size", [1.0, 1.0])
	size = Vector2(maxf(0.01, float(dimensions[0])), maxf(0.01, float(dimensions[1])))
	collision_radius = maxf(0.01,float(parameters.get("collision_radius",maxf(size.x,size.y)*0.5)))
	separate_when_stopped = bool(parameters.get("separate_when_stopped",false))
	health_regen = maxf(0.0, float(parameters.get("health_regen", 0)))
	health_regen_delay = maxf(0.0, float(parameters.get("health_regen_delay", 0)))
	shield_regen = maxf(0.0, float(parameters.get("shield_regen", rules.get("shield_regen_per_second", 7.5))))
	shield_regen_delay = maxf(0.0, float(parameters.get("shield_regen_delay", rules.get("shield_regen_delay", 7))))
	energy_regen = maxf(0.0, float(parameters.get("energy_regen", 0)))
	energy_regen_delay = maxf(0.0, float(parameters.get("energy_regen_delay", 0)))
	skills = parameters.get("skills", {}).duplicate(true)
	# 顶层旧武器字段继续可读；新配置可把主武器写进 weapon。
	var primary_data := parameters.duplicate(true)
	primary_data.merge(parameters.get("weapon", {}), true)
	primary_weapon = WeaponDefinition.new(primary_data)
	primary_weapon_data = primary_weapon.to_data()
	weapons["primary"] = primary_weapon
	if skills.has("weapon_switch"):
		var modes: Array = skills.weapon_switch.weapons
		for i in range(modes.size()):
			var mode: Dictionary = primary_weapon.to_data()
			mode["bonus"] = {}
			mode["bonus_tags"] = {}
			mode.merge(modes[i], true)
			mode.id = str(modes[i].get("id", "mode_%d" % i))
			# 不继承主武器的结构体开火开关覆盖模式自身的 attacks_base。
			if not modes[i].has("attacks_structures"):
				mode.attacks_structures = bool(mode.get("attacks_base", true))
			var definition = WeaponDefinition.new(mode, "mode_%d" % i)
			weapons[definition.id] = definition
			modes[i] = definition.to_data()
	for skill_id in ["deployment","defender_zone"]:
		if not skills.has(skill_id) or not skills[skill_id].has("weapon"):continue
		var configured: Dictionary = skills[skill_id].weapon
		var deployed: Dictionary = primary_weapon.to_data()
		deployed.merge(configured, true)
		deployed.id = "deployed" if skill_id=="deployment" else "defense"
		if not configured.has("attacks_structures"):
			deployed.attacks_structures=bool(deployed.get("attacks_base",true))
		var definition = WeaponDefinition.new(deployed,str(deployed.id))
		weapons[definition.id] = definition
		skills[skill_id].weapon = definition.to_data()

func has_tag(tag: String) -> bool:
	return tags.has(tag)

## 与商店、AI、已有技能兼容的规范化配置视图；不是运行中的单位状态。
func to_data() -> Dictionary:
	var result := _data.duplicate(true)
	result.merge(primary_weapon.to_data(), true)
	result.merge({"hp":max_hp, "shield":max_shield, "energy":max_energy,
		"initial_energy":initial_energy, "speed":speed, "armor":armor,
		"shield_armor":shield_armor, "armor_type":armor_type, "race":race,
		"layer":layer, "unit_type":unit_type, "structure":unit_type == "structure",
		"tags":tags.duplicate(), "size":[size.x, size.y],
		"collision_radius":collision_radius, "separate_when_stopped":separate_when_stopped,
		"health_regen":health_regen, "health_regen_delay":health_regen_delay,
		"shield_regen":shield_regen, "shield_regen_delay":shield_regen_delay,
		"energy_regen":energy_regen, "energy_regen_delay":energy_regen_delay,
		"skills":skills.duplicate(true)}, true)
	return result
