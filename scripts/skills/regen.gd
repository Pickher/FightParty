extends RefCounted

## 脱战再生：连续 delay 秒未受伤后，每秒回复 per_second 生命，不超过上限。
## 受伤时间与护盾共用 unit.last_hit_tick（见 shield.gd）。
static func recover(sim, unit: Dictionary, dt: float) -> void:
	var stats: Dictionary = sim.catalog[unit.kind]
	var config = stats.get("skills", {}).get("regen")
	if config == null or float(unit.hp) >= float(stats.hp):
		return
	if sim.tick - int(unit.last_hit_tick) >= int(float(config.delay) * float(sim.rules.tick_rate)):
		unit.hp = minf(float(stats.hp), float(unit.hp) + float(config.per_second) * dt)
