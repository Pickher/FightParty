extends RefCounted

## 召唤先排队，整步结算后入场，新单位从下一步起行动。
static func queue(sim, source: Dictionary, kind: String, count: int, position: Vector2, config: Dictionary = {}) -> void:
	if not sim.catalog.has(kind):return
	var existing := 0
	for child in sim.units:
		if int(child.get("owner_id",0))==int(source.id) and child.kind==kind and float(child.hp)>0:existing+=1
	for child in sim.spawn_queue:
		if int(child.owner_id)==int(source.id) and child.kind==kind and float(child.hp)>0:existing+=1
	var maximum: int = int(config.get("max_count",32))
	for member in range(mini(count,maxi(0,maximum-existing))):
		var angle: float = TAU*(existing+member)/maxi(1,maximum)
		var at: Vector2 = sim.clamp_to_field(position+Vector2(cos(angle),sin(angle))*float(config.get("spawn_radius",0.8)))
		sim.spawn_queue.append({"team":source.team,"kind":kind,"pos":at,"owner_id":source.id,"lifetime":config.get("lifetime",0),"dependent":config.get("dependent",false),"leash":config.get("leash",0)})

static func step(sim, unit: Dictionary, target: Dictionary) -> void:
	var config: Dictionary = sim.catalog[unit.kind].get("skills",{}).get("summon",{})
	if config.is_empty() or config.get("on","")!="timer" or sim.tick<int(unit.get("summon_ready_tick",0)):return
	if bool(config.get("requires_combat",true)):
		var destination: Vector2 = sim.base_pos(1-int(unit.team)) if target.is_empty() else target.pos
		var reach: float = float(sim.catalog[unit.kind].range)+(float(sim.rules.layout.base_radius) if target.is_empty() else 0.0)
		if (target.is_empty() and not bool(config.get("allow_base",false))) or unit.pos.distance_to(destination)>reach:return
	var location: Vector2 = unit.pos if target.is_empty() else target.pos
	if bool(config.get("dependent",false)):location=unit.pos
	queue(sim,unit,str(config.kind),int(config.count),location,config)
	unit.summon_ready_tick=sim.tick+ceili(float(config.interval)*float(sim.rules.tick_rate))

static func on_hit(sim, unit: Dictionary, target: Dictionary) -> void:
	var config: Dictionary = sim.catalog[unit.kind].get("skills",{}).get("summon",{})
	if config.is_empty() or config.get("on","")!="hit":return
	queue(sim,unit,str(config.kind),int(config.count),target.pos,config)

static func flush(sim) -> void:
	var living: Dictionary = {}
	for unit in sim.units:living[unit.id]=true
	for request in sim.spawn_queue:
		if bool(request.dependent) and not living.has(request.owner_id):continue
		var unit: Dictionary = sim.spawn_unit(int(request.team),str(request.kind),request.pos)
		unit.owner_id=int(request.owner_id)
		unit.summoned=true
		unit.owner_dependent=bool(request.dependent)
		unit.leash=float(request.leash)
		if float(request.lifetime)>0:unit.expires_tick=sim.tick+ceili(float(request.lifetime)*float(sim.rules.tick_rate))
	sim.units=sim.units.filter(func(u):return not bool(u.get("owner_dependent",false)) or living.has(int(u.get("owner_id",0))))
	sim.spawn_queue=[]
