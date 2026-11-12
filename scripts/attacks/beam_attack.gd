extends "res://scripts/attacks/attack_behavior.gd"
## 激光型：持续显示，周期性完整结算伤害/治疗，共用目标切换等待。
const Beams = preload("res://scripts/skills/services/beam_service.gd")

func type_id() -> String:
	return "beam"

func is_continuous() -> bool:
	return true

func current_target(clock_owner: Dictionary) -> int:
	return int(Beams.state_for(clock_owner).target_id)

func tick(ctx: Dictionary, clock_owner: Dictionary, weapon: Dictionary, target: Dictionary, target_id: int, healing: bool = false) -> void:
	Beams.apply(ctx,clock_owner,weapon,target,target_id,healing)

func hit_count(_weapon: Dictionary) -> int:
	return 1

func skill_name(weapon: Dictionary) -> String:
	return "持续治疗" if float(weapon.get("healing",0))>0 else "持续光束"
