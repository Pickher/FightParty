extends "res://scripts/skills/skill.gd"
const AttackCycle = preload("res://scripts/units/attack_cycle.gd")
const Sequences = preload("res://scripts/skills/services/attack_sequence_service.gd")

## 一组可复用的驻军炮位：count 决定独立炮位数量，weapon 决定每套武器。
## 不生成可走出建筑的友军实体；建筑被摧毁时全部炮位随组件回收。
func _init() -> void:
	priority=20

func on_spawn(_sim) -> void:
	state.mounts=[]
	for group_index in range(config.weapons.size()):
		for i in range(int(config.weapons[group_index].count)):
			var mount := AttackCycle.create()
			mount.group_index=group_index
			state.mounts.append(mount)

func valid_target(sim, target, weapon: Dictionary) -> bool:
	return target!=null and target.hp>0 and target.team!=owner.team and owner.pos.distance_to(target.pos)<=float(weapon.range) and sim._can_hit_unit(owner,target,weapon)

func pick_target(sim, weapon: Dictionary, assigned: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_load := 2147483647
	var best_distance := INF
	for enemy in sim.nearby_team(owner.pos,float(weapon.range),1-int(owner.team)):
		if not valid_target(sim,enemy,weapon):continue
		var target_load: int = int(assigned.get(enemy.id,0))
		var distance: float = owner.pos.distance_squared_to(enemy.pos)
		if target_load<best_load or (target_load==best_load and (distance<best_distance or (is_equal_approx(distance,best_distance) and int(enemy.id)<int(best.get("id",2147483647))))):
			best=enemy
			best_load=target_load
			best_distance=distance
	return best

func before_target(ctx: Dictionary) -> bool:
	var sim = ctx.sim
	var assigned: Dictionary = {}
	# 先统计仍有效的锁定，避免新索敌挤占其他炮位的目标；一旦开火不主动换人。
	for mount in state.mounts:
		var weapon: Dictionary = config.weapons[int(mount.group_index)].weapon
		var locked = sim.by_id.get(int(mount.locked_target_id))
		if valid_target(sim,locked,weapon):assigned[locked.id]=int(assigned.get(locked.id,0))+1
		else:mount.locked_target_id=0
	for index in range(state.mounts.size()):
		var mount: Dictionary = state.mounts[index]
		var weapon: Dictionary = config.weapons[int(mount.group_index)].weapon
		AttackCycle.tick_attack(mount,float(ctx.dt),sim.skill_system.attack_rate(sim,owner))
		var target = sim.by_id.get(int(mount.locked_target_id))
		if target==null:
			target=pick_target(sim,weapon,assigned)
			if not target.is_empty():assigned[target.id]=int(assigned.get(target.id,0))+1
		var eligible: bool = target!=null and not target.is_empty() and float(weapon.damage)>0
		var target_id: int = int(target.id) if eligible else 0
		if not AttackCycle.ready_to_fire(mount,weapon,target_id,eligible):continue
		mount.locked_target_id=target_id
		var shot: Dictionary = ctx.duplicate()
		shot.target=target
		shot.weapon=weapon
		shot.goal=target.pos
		shot.damage_multiplier=sim.skill_system.damage_multiplier(shot)
		Sequences.launch(shot,mount,index)
	sim._tick_attack_clock(owner,float(ctx.dt))
	return true

func contributes_damage() -> bool:return true
