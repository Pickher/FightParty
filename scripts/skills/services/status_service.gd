extends RefCounted
static func tick(sim, dt: float, hits: Dictionary) -> void:
	for unit in sim.units:
		var active: Array = []
		for dot in unit.get("dots",[]):
			if sim.tick>=int(dot.until_tick):continue
			active.append(dot)
			sim.queue_hit(hits,unit,float(dot.rate)*dt,false,true)
			sim.damage_done[int(dot.team)]+=float(dot.rate)*dt
		unit.dots=active

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
