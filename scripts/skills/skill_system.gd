extends RefCounted
## 配置键 → 独立组件类。新增技能只注册一次，兵种只需挂参数。
const TYPES := {
	"weapon_buff":preload("res://scripts/skills/weapon_buff.gd"),
	"mobile_attack":preload("res://scripts/skills/mobile_attack.gd"),
	"independent_weapons":preload("res://scripts/skills/independent_weapons.gd"),
	"deployment":preload("res://scripts/skills/deployment.gd"),
	"defender_zone":preload("res://scripts/skills/defender_zone.gd"),
	"healing":preload("res://scripts/skills/healing.gd"),
	"stimulant":preload("res://scripts/skills/stimulant.gd"),
	"multi_attack":preload("res://scripts/skills/multi_attack.gd"),
	"line_attack":preload("res://scripts/skills/line_attack.gd"),
	"weapon_switch":preload("res://scripts/skills/weapon_switch.gd"),
	"yamato":preload("res://scripts/skills/yamato.gd"),
	"regen":preload("res://scripts/skills/regen.gd"),
	"on_hit_slow":preload("res://scripts/skills/on_hit_slow.gd"),
	"delayed_area":preload("res://scripts/skills/delayed_area.gd"),
	"blink":preload("res://scripts/skills/blink.gd"),
	"charge":preload("res://scripts/skills/charge.gd"),
	"dive":preload("res://scripts/skills/dive.gd"),
	"aura":preload("res://scripts/skills/aura.gd"),
	"barrier":preload("res://scripts/skills/barrier.gd"),
	"dot":preload("res://scripts/skills/dot.gd"),
	"ramp_damage":preload("res://scripts/skills/ramp_damage.gd"),
	"chain_attack":preload("res://scripts/skills/chain_attack.gd"),
	"suicide":preload("res://scripts/skills/suicide.gd"),
	"summon":preload("res://scripts/skills/summon.gd"),
	"on_death":preload("res://scripts/skills/on_death.gd"),
	"corpse_raise":preload("res://scripts/skills/corpse_raise.gd")
}
var instances: Dictionary = {}
var incoming_slows: Dictionary = {}

func attach(sim, unit: Dictionary) -> void:
	var configured: Dictionary = sim.catalog[unit.kind].get("skills",{})
	assert(not (configured.has("deployment") and configured.has("defender_zone")),"不能同时挂载两套部署技能")
	var attached: Array = []
	for key in configured:
		assert(TYPES.has(key),"未注册技能："+str(key))
		assert(configured[key] is Dictionary,"技能参数必须是字典："+str(key))
		var component = TYPES[key].new()
		component.configure(str(key),unit,configured[key])
		component.on_spawn(sim)
		attached.append(component)
	attached.sort_custom(func(a,b):return a.priority<b.priority or (a.priority==b.priority and a.id<b.id))
	instances[unit.id]=attached
	publish(unit)

func components(unit: Dictionary) -> Array: return instances.get(unit.id,[])
func publish(unit: Dictionary) -> void:
	var snapshots: Dictionary = {}
	for component in components(unit):
		component.publish()
		snapshots[component.id]=component.snapshot()
	unit.skill_states=snapshots

func prune(sim, units: Array) -> void:
	var alive: Dictionary = {}
	for unit in units:alive[unit.id]=true
	for id in instances.keys():
		if not alive.has(id):
			for component in instances[id]:component.on_removed(sim)
			instances.erase(id)

func frame(ctx: Dictionary) -> void:
	ctx.sim.aura_modifiers.clear()
	ctx.aura_damage={}
	for unit in ctx.sim.units:
		for component in components(unit):component.on_frame(ctx)
		publish(unit)
	for value in ctx.aura_damage.values():
		ctx.sim.queue_hit(ctx.hits,value.victim,float(value.rate)*float(ctx.dt),false,true)
		ctx.sim.damage_done[int(value.team)]+=float(value.rate)*float(ctx.dt)

func before_target(ctx: Dictionary) -> bool:
	for component in components(ctx.unit):
		if component.before_target(ctx):
			publish(ctx.unit)
			return true
	publish(ctx.unit)
	return false

## 在武器选择前修正目标，空地武器会依据最终目标切换。
func select_target(sim, unit: Dictionary, target: Dictionary) -> Dictionary:
	for component in components(unit):target=component.select_target(sim,target)
	publish(unit)
	return target
func after_action(ctx: Dictionary) -> void:
	for component in components(ctx.unit):component.after_action(ctx)
	publish(ctx.unit)
func moves_while_attacking(unit: Dictionary) -> bool:
	for component in components(unit):
		if component.moves_while_attacking():return true
	return false

func on_target(ctx: Dictionary) -> void:
	for component in components(ctx.unit):component.on_target(ctx)
	publish(ctx.unit)
func before_action(ctx: Dictionary) -> void:
	for component in components(ctx.unit):
		component.before_action(ctx)
		if ctx.handled:break
	publish(ctx.unit)
func attack(ctx: Dictionary) -> bool:
	for component in components(ctx.unit):
		if component.on_attack(ctx):
			publish(ctx.unit)
			return true
	return false
func after_attack(ctx: Dictionary) -> void:
	for component in components(ctx.unit):component.after_attack(ctx)
	publish(ctx.unit)

func hit(sim, unit: Dictionary, victim: Dictionary, hits: Dictionary, slows = null) -> void:
	var ctx := {"sim":sim,"unit":unit,"victim":victim,"hits":hits,"pending_slows":incoming_slows if slows==null else slows}
	for component in components(unit):component.on_hit(ctx)
	publish(unit)

## 传播攻击带配置快照；不把组件对象塞进世界快照或投射物。
func impact_configs(unit: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for component in components(unit):
		if component.hit_effect:result[component.id]=component.config.duplicate(true)
	return result
func wave_hit(sim, wave: Dictionary, victim: Dictionary, hits: Dictionary, slows: Dictionary) -> void:
	var source := {"id":int(wave.source_id),"kind":wave.kind,"team":wave.team,"pos":wave.source}
	var ctx := {"sim":sim,"unit":source,"victim":victim,"hits":hits,"pending_slows":slows}
	for key in wave.impact_skills:
		var component=TYPES[key].new()
		component.configure(str(key),source,wave.impact_skills[key])
		component.on_hit(ctx)

func death(ctx: Dictionary) -> void:
	for component in components(ctx.dead):component.on_death(ctx)
	for unit in ctx.sim.units:
		for component in components(unit):component.on_unit_death(ctx)
	publish(ctx.dead)
func survived(ctx: Dictionary) -> void:
	for component in components(ctx.unit):component.on_survived(ctx)
	publish(ctx.unit)
func absorb(sim, unit: Dictionary, value: float) -> float:
	var ctx := {"sim":sim,"unit":unit}
	for component in components(unit):value=component.absorb(ctx,value)
	publish(unit)
	return value

func weapon(sim, unit: Dictionary) -> Dictionary:
	var value: Dictionary = sim.definitions[unit.kind].primary_weapon_data
	for component in components(unit):value=component.modify_weapon(sim,value)
	return value
func search(sim, unit: Dictionary) -> Dictionary:
	var value: Dictionary = weapon(sim,unit)
	for component in components(unit):value=component.modify_search(sim,value)
	return value
func can_target(sim, unit: Dictionary, victim: Dictionary) -> bool:
	for component in components(unit):
		if not component.can_target(sim,victim):return false
	return true
func discovery_radius(sim, unit: Dictionary, value: float) -> float:
	for component in components(unit):value=component.discovery_radius(sim,value)
	return value
func has_priority(unit: Dictionary) -> bool:
	for component in components(unit):
		if component.has_target_priority():return true
	return false
func target_priority(sim, unit: Dictionary, victim: Dictionary) -> int:
	var value := 0
	for component in components(unit):value+=component.target_priority(sim,victim)
	return value
func movement_multiplier(sim, unit: Dictionary) -> float:
	var value := 1.0
	for component in components(unit):value*=component.movement_multiplier(sim)
	return value
func attack_rate(sim, unit: Dictionary) -> float:
	var value: float = float(sim.aura_modifiers.get(unit.id,{}).get("attack_rate",1))
	for component in components(unit):value*=component.attack_rate(sim)
	return value
## 武器按模式配置段数；旧 multi_attack 组件仍可额外乘算。
func attack_count(sim, unit: Dictionary, active_weapon: Dictionary = {}) -> int:
	var stats: Dictionary = weapon(sim,unit) if active_weapon.is_empty() else active_weapon
	var value := maxi(1,int(stats.get("hit_count",1)))
	for component in components(unit):value=component.attack_count(sim,value)
	return value
func damage_multiplier(ctx: Dictionary) -> float:
	var value := 1.0
	for component in components(ctx.unit):value*=component.damage_multiplier(ctx)
	publish(ctx.unit)
	return value

func contributes_damage(unit: Dictionary) -> bool:
	for component in components(unit):
		if component.contributes_damage():return true
	return false

func end_frame(units: Array) -> void:
	for unit in units:publish(unit)

func get_component(unit: Dictionary, key: String):
	for component in components(unit):
		if component.id==key:return component
	return null
