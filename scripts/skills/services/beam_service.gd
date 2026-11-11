extends RefCounted
## 连续武器/治疗共用目标切换与周期结算；每0.5秒完整命中一次，光束画面持续存在。
static func state_for(owner: Dictionary) -> Dictionary:
	if not owner.has("beam_state"):
		owner.beam_state={"target_id":0,"mode_id":"","wait_until":0.0,"accumulator":0.0}
	return owner.beam_state

static func apply(ctx: Dictionary, clock_owner: Dictionary, weapon: Dictionary, target: Dictionary, target_id: int, healing: bool = false) -> void:
	var sim = ctx.sim
	var source: Dictionary = ctx.unit
	var state := state_for(clock_owner)
	var delivery: Dictionary = weapon.delivery
	var now: float = float(sim.tick-1)/float(sim.rules.tick_rate)
	if str(state.mode_id)!=str(weapon.id):
		state.mode_id=weapon.id
		state.accumulator=0.0
	if int(state.target_id)!=target_id:
		state.wait_until=now+(float(delivery.switch_delay) if int(state.target_id)!=0 else 0.0)
		state.target_id=target_id
		state.accumulator=0.0
	var elapsed: float = clampf(now+float(ctx.dt)-maxf(now,float(state.wait_until)),0.0,float(ctx.dt))
	if elapsed<=0.000001:return
	var step_seconds: float = float(delivery.tick_interval)
	var goal: Vector2 = target.pos
	var rate: float = sim.skill_system.attack_rate(sim,source)
	if rate<=0:return
	var cost: float = float(ctx.get("healing_energy_per_period",0))
	if healing and not sim.can_spend_energy(source,cost):
		state.accumulator=0.0
		return
	state.accumulator=float(state.accumulator)+elapsed*rate
	clock_owner.locked_target_id=target_id if target_id>0 else 0
	sim.active_beams.append({"source_id":source.id,"target_id":target_id,"from":source.pos,"to":goal,
		"kind":source.kind,"mode":weapon.id,"team":source.team,"healing":healing})
	while float(state.accumulator)+0.000001>=step_seconds:
		state.accumulator=maxf(0.0,float(state.accumulator)-step_seconds)
		if healing:
			if not sim.spend_energy(source,cost):continue
			ctx.heals[target_id]=float(ctx.heals.get(target_id,0))+float(weapon.get("healing",0))
		else:
			var multiplier: float = float(ctx.get("damage_multiplier",1))
			if target_id<0:
				ctx.base_hits[-target_id-1]+=float(weapon.damage)*multiplier
			else:
				var pulse: Dictionary = ctx.duplicate()
				pulse.damage_multiplier=multiplier
				sim.queue_direct_strike(pulse,weapon,target,0)
			sim.events.append({"type":"beam_tick","source_id":source.id,"target":target_id,"mode":weapon.id,"team":source.team})
