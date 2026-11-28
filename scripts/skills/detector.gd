extends "res://scripts/skills/skill.gd"
## 阵营共享探测。保存单位引用以跟随移动，死亡、撤离或变形时解除登记。

func on_spawn(sim) -> void:
	sim.detectors[owner.team][owner.id] = {"unit":owner, "radius":float(config.radius)}

func on_removed(sim) -> void:
	sim.detectors[owner.team].erase(owner.id)
