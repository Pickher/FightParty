extends "res://scripts/skills/skill.gd"

func _init() -> void:
	view_fields = ["cloaked"]

func on_spawn(_sim) -> void:
	state.cloaked = true
