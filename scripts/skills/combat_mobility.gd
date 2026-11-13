extends "res://scripts/skills/skill.gd"
## 原图的交战移速行为：脱战时移除修正，不能把速度上限当成基础移速。
func on_target(ctx: Dictionary) -> void:
	state.engaged = not ctx.target.is_empty() or owner.get("attack_phase", "idle")=="firing"

func movement_multiplier(sim) -> float:
	if not bool(state.get("engaged",false)): return 1.0
	var base: float = float(sim.catalog[owner.kind].speed)
	if base<=0.0: return 1.0
	var speed := base
	for modifier in config.get("modifiers",[]):
		speed=maxf(0.0,speed+float(modifier.get("speed_bonus",0)))*float(modifier.get("speed_multiplier",1))
		if modifier.has("speed_maximum"):speed=minf(speed,float(modifier.speed_maximum))
	return speed/base
