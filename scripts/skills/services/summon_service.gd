extends RefCounted
static func queue(sim, source: Dictionary, kind: String, count: int, position: Vector2, config: Dictionary = {}) -> int:
	if not sim.catalog.has(kind):return 0
	var existing := 0
	for child in sim.units:
		if int(child.get("owner_id",0))==int(source.id) and child.kind==kind and float(child.hp)>0:existing+=1
	for child in sim.spawn_queue:
		if int(child.owner_id)==int(source.id) and child.kind==kind:existing+=1
	var maximum: int = int(config.get("max_count",32))
	var accepted := maxi(0, mini(count,maxi(0,maximum-existing)))
	for member in range(accepted):
		var angle: float = TAU*(existing+member)/maxi(1,maximum)
		var at: Vector2 = sim.clamp_to_field(position+Vector2(cos(angle),sin(angle))*float(config.get("spawn_radius",0.8)))
		sim.spawn_queue.append({"team":source.team,"kind":kind,"pos":at,"owner_id":source.id,"lifetime":config.get("lifetime",0),"dependent":config.get("dependent",false),"leash":config.get("leash",0)})
	return accepted
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
