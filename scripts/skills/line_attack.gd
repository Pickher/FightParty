extends "res://scripts/skills/skill.gd"
const Line = preload("res://scripts/skills/services/line_service.gd")

func on_attack(ctx: Dictionary) -> bool:
	Line.launch(ctx.sim,owner,ctx.goal,config,float(ctx.get("damage_multiplier",1.0)))
	return true

## 几何工具保留兼容入口，实际传播由场上实体服务负责。
func crosses(wave: Dictionary, start: Vector2, finish: Vector2, distance: float) -> bool:
	return Line.crosses(wave,start,finish,distance)

static func launch(sim, unit: Dictionary, goal: Vector2) -> void:
	# 兼容旧几何测试入口，运行仍由实例组件执行。
	for component in sim.skill_system.components(unit):
		if component.id=="line_attack":
			component.on_attack({"sim":sim,"goal":goal,"damage_multiplier":1.0})
			return
