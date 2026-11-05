extends "res://scripts/skills/skill.gd"

func attack_count(_sim, value: int) -> int: return value*maxi(1,int(config.get("count",1)))
