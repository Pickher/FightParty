extends RefCounted
## 攻击行为的公共接口。实现类无单位状态；独立状态通过ctx/clock_owner传入。
## 武器模式持有数值，行为负责出手后的投送方式；命中与护甲仍走公共结算。

func type_id() -> String:
	return ""

func is_continuous() -> bool:
	return false

func current_target(_clock_owner: Dictionary) -> int:
	return 0

func tick(_ctx: Dictionary, _clock_owner: Dictionary, _weapon: Dictionary, _target: Dictionary, _target_id: int, _healing: bool = false) -> void:
	assert(false,"此攻击行为没有实现连续作用入口")

func can_emit(_sim, _source: Dictionary, _target, _weapon: Dictionary, _origin: Vector2, _goal: Vector2) -> bool:
	return true

func emit(_ctx: Dictionary, _sequence: Dictionary) -> void:
	assert(false,"此攻击行为没有实现单段出手入口")

func advance(_sim, _frame: Dictionary) -> void:
	pass

func target_died(_sim, _dead: Dictionary) -> void:
	pass

func hit_count(weapon: Dictionary) -> int:
	return maxi(1,int(weapon.get("hit_count",1)))

func skill_name(_weapon: Dictionary) -> String:
	return ""

func expected_dps(sim, weapon: Dictionary, victim: Dictionary) -> float:
	var cycle: float = float(weapon.interval)+float(weapon.get("attack_duration",0))+float(weapon.get("windup",0))+float(weapon.get("backswing",0))
	return sim.expected_damage(weapon,victim)*hit_count(weapon)/maxf(0.001,cycle)
