extends "res://scripts/attacks/attack_behavior.gd"
## 射弹型：接触命中、固定飞行耗时、按距离飞行。固定耗时0即发射时命中。
const Projectiles = preload("res://scripts/skills/services/projectile_service.gd")

func type_id() -> String:
	return "projectile"

func can_emit(sim, source: Dictionary, target, weapon: Dictionary, origin: Vector2, goal: Vector2) -> bool:
	return str(weapon.delivery.flight)!="contact" or target==null or origin.distance_to(goal)<=sim.attack_reach(source,target,weapon)

func emit(ctx: Dictionary, sequence: Dictionary) -> void:
	Projectiles.launch(ctx.sim,sequence,ctx.source_position,ctx.goal,int(ctx.strike),float(ctx.fire_offset))

func advance(sim, frame: Dictionary) -> void:
	Projectiles.advance(sim,frame)

func target_died(sim, dead: Dictionary) -> void:
	Projectiles.target_died(sim,dead)
