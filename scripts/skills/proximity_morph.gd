extends "res://scripts/skills/skill.gd"
## 接敌后单向变形。时钟与渲染共用，换形只在本步伤害结算后发生。
func _init() -> void:
	priority = 0
	view_fields = ["morph_start_tick", "morph_end_tick"]

func on_spawn(sim) -> void:
	sim.wave_march.travelers[owner.id] = owner

func on_removed(sim) -> void:
	sim.wave_march.travelers.erase(owner.id)

func march_multiplier(sim) -> float:
	if sim.wave_march.supporting(sim, owner):
		return 1.0
	var base: float = sim.definitions[owner.kind].speed
	var pace: float = sim.wave_march.escort_speed(owner, config.escort_speed)
	return minf(pace / base, 1.0) if base > 0.0 else 1.0

func before_target(ctx: Dictionary) -> bool:
	var sim = ctx.sim
	if not state.has("morph_end_tick"):
		if not sim.wave_march.detects_contact(sim, owner):
			return false
		var ticks := maxi(1, ceili(float(config.duration) * float(sim.rules.tick_rate)))
		state.morph_start_tick = sim.tick - 1
		state.morph_end_tick = state.morph_start_tick + ticks
	if sim.tick >= int(state.morph_end_tick):
		ctx.form_changes[owner.id] = config.target_kind
	return true
