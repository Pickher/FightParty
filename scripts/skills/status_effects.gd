extends RefCounted

## 光环以步初位置统一采样，同名效果取最强值；本步单位遍历顺序不会改变增益。
static func prepare(sim) -> void:
	sim.aura_modifiers.clear()
	for unit in sim.units:
		var config: Dictionary = sim.catalog[unit.kind].get("skills",{}).get("aura",{})
		if config.is_empty():continue
		if bool(config.get("requires_combat",false)):
			if sim.tick>=int(unit.get("aura_until_tick",0)):
				if sim.tick<int(unit.get("aura_ready_tick",0)):continue
				var threat := false
				for enemy in sim.nearby_team(unit.pos,float(config.radius)+3,1-int(unit.team)):
					if enemy.hp>0:
						threat=true
						break
				if not threat:continue
				unit.aura_until_tick=sim.tick+ceili(float(config.duration)*float(sim.rules.tick_rate))
				unit.aura_ready_tick=sim.tick+ceili(float(config.cooldown)*float(sim.rules.tick_rate))
		for ally in sim.nearby_team(unit.pos,float(config.radius),int(unit.team)):
			if sim.is_structure(ally):continue
			var value: Dictionary = sim.aura_modifiers.get(ally.id,{"reduction":0.0,"attack_rate":1.0})
			value.reduction=maxf(float(value.reduction),float(config.get("ranged_damage_reduction",0)))
			value.attack_rate=maxf(float(value.attack_rate),float(config.get("ally_attack_rate",1)))
			sim.aura_modifiers[ally.id]=value

static func attack_rate(sim, unit: Dictionary) -> float:
	return float(sim.aura_modifiers.get(unit.id,{}).get("attack_rate",1))

static func tick(sim, dt: float, hits: Dictionary) -> void:
	for unit in sim.units:
		var active: Array = []
		for dot in unit.get("dots",[]):
			if sim.tick>=int(dot.until_tick):continue
			active.append(dot)
			sim.queue_hit(hits,unit,float(dot.rate)*dt,false,true)
			sim.damage_done[int(dot.team)]+=float(dot.rate)*dt
		unit.dots=active
	var aura_damage: Dictionary = {}
	for source in sim.units:
		var config: Dictionary = sim.catalog[source.kind].get("skills",{}).get("aura",{})
		if float(config.get("enemy_dot_per_second",0))<=0:continue
		for enemy in sim.nearby_team(source.pos,float(config.radius),1-int(source.team)):
			if sim.is_structure(enemy):continue
			var key := "%s:%d:%d" % [str(source.kind),int(source.team),int(enemy.id)]
			aura_damage[key]={"victim":enemy,"team":source.team,"rate":config.enemy_dot_per_second}
	for value in aura_damage.values():
		sim.queue_hit(hits,value.victim,float(value.rate)*dt,false,true)
		sim.damage_done[int(value.team)]+=float(value.rate)*dt

## 所有新状态延迟至统一结算施加，命中当步不改变已经决定的移动。
static func queue_dot(sim, victim: Dictionary, config: Dictionary, source: Dictionary) -> void:
	if config.is_empty():return
	sim.pending_effects.append({"id":victim.id,"type":"dot","rate":config.per_second,"until_tick":sim.tick+ceili(float(config.duration)*float(sim.rules.tick_rate))+1,"team":source.team,"kind":source.kind,"max_stacks":int(config.get("max_stacks",1))})

static func queue_root(sim, victim: Dictionary, seconds: float) -> void:
	if seconds>0 and not sim.is_structure(victim):
		sim.pending_effects.append({"id":victim.id,"type":"root","until_tick":sim.tick+ceili(seconds*float(sim.rules.tick_rate))+1})

static func apply(sim) -> void:
	for effect in sim.pending_effects:
		var unit = sim.by_id.get(int(effect.id))
		if unit==null:continue
		if effect.type=="root":
			unit.root_until_tick=maxi(int(unit.get("root_until_tick",0)),int(effect.until_tick))
		else:
			var dots: Array = unit.get("dots",[])
			var matches: Array = []
			for dot in dots:
				if dot.kind==effect.kind and dot.team==effect.team:matches.append(dot)
			if matches.size()>=int(effect.max_stacks):
				matches.sort_custom(func(a,b):return int(a.until_tick)<int(b.until_tick))
				dots.erase(matches[0])
			dots.append(effect.duplicate(true))
			unit.dots=dots

## 不朽者被击中时自动激活额外屏障，先于普通护盾吸收；按模拟时钟冷却。
static func barrier_absorb(sim, unit: Dictionary, raw: float) -> float:
	var config: Dictionary = sim.catalog[unit.kind].get("skills",{}).get("barrier",{})
	if config.is_empty() or raw<=0:return raw
	if sim.tick>=int(unit.get("barrier_until_tick",0)):
		unit.barrier_hp=0.0
		if sim.tick>=int(unit.get("barrier_ready_tick",0)):
			unit.barrier_hp=float(config.amount)
			unit.barrier_until_tick=sim.tick+ceili(float(config.duration)*float(sim.rules.tick_rate))
			unit.barrier_ready_tick=sim.tick+ceili(float(config.cooldown)*float(sim.rules.tick_rate))
	var absorbed: float = minf(raw,float(unit.get("barrier_hp",0)))
	unit.barrier_hp=float(unit.get("barrier_hp",0))-absorbed
	return raw-absorbed
