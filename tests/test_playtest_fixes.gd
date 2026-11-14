# 中文导读：试玩反馈回归测试——恶火扎堆吃溅射、近战被远程溅射后脱离部队。
# 运行：godot --headless --path . --script res://tests/test_playtest_fixes.gd
extends SceneTree
const Sim = preload("res://scripts/battle_sim.gd")
const Catalog = preload("res://scripts/catalog.gd")
const WeaponDefinition = preload("res://scripts/units/weapon_definition.gd")
var failures := 0
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

## 静止、无伤害、极高生命的靶子，只用来吸引火力。
const POST := {"name":"测试靶","symbol":"?","race":"zerg","status":"ready","cost":100,"hp":1000000,"armor_type":"heavy","armor":0,"damage":0,"interval":1,"range":0,"speed":0,"splash":0,"color":"ffffff","role":"测试","counter":"测试","layer":"ground","target_layers":["ground"],"size":[1,1]}
## 不可击杀的固定远程溅射炮，数值取自坦克架设炮（射程13、溅射2.5、内圈60%/外圈30%）。
const ARTILLERY := {"name":"测试远程炮","symbol":"?","race":"zerg","status":"ready","cost":100,"hp":1000000,"armor_type":"heavy","armor":0,"damage":15,"interval":1.5,"range":13,"speed":0,"splash":2.5,"splash_multiplier":0.3,"splash_inner_ratio":0.5,"splash_inner_multiplier":0.6,"color":"ffffff","role":"测试","counter":"测试","layer":"ground","target_layers":["ground"],"size":[1.6,1.6],"collision_radius":0.8}

func bare():
	return Sim.new(42, {"structures":false})

func ticks(sim, count: int) -> void:
	for i in range(count):
		sim.step()

func _initialize() -> void:
	var legacy: Dictionary = Catalog.units().hellbat.duplicate(true)
	legacy.collision_radius = 0.6
	legacy.separate_when_stopped = false
	Catalog.extra_units = {"post":POST, "artillery":ARTILLERY, "hellbat_legacy":legacy}
	_hellion_data()
	_hellion_splash()
	_melee_engages_long_range_attacker()
	_melee_stays_with_army()
	_engage_respects_layers_and_radius()
	print("RESULT %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _hellion_data() -> void:
	var hellbat: Dictionary = Catalog.units().hellbat
	check(is_equal_approx(float(hellbat.collision_radius), 0.75), "hellion uses Desert Storm SeparationRadius 0.75")
	check(bool(hellbat.separate_when_stopped), "hellion spreads out during attack cooldown like marines")

## 六辆恶火从紧密方阵冲向一排靶子；身后的远程炮持续溅射。返回 {splash 暴露度, 恶火实际损失生命}。
func _hellion_run(kind: String) -> Dictionary:
	var sim = bare()
	var hellions: Array = []
	for i in range(6):
		hellions.append(sim.spawn_unit(0, kind, Vector2(60.0 + float(i % 2) * 1.2, 56.0 + float(i / 2) * 1.2)))
	for i in range(5):
		sim.spawn_unit(1, "post", Vector2(70.0, 54.0 + float(i) * 2.0))
	sim.spawn_unit(1, "artillery", Vector2(78.0, 58.0))
	ticks(sim, 200)
	var siege: Dictionary = Catalog.units().mortar.attack_modes[1]
	var exposure := 0.0
	for a in hellions:
		for b in hellions:
			if a.id == b.id:
				continue
			var distance: float = a.pos.distance_to(b.pos)
			if distance <= float(siege.splash):
				exposure += WeaponDefinition.splash_damage_multiplier(siege, distance)
	var lost := 0.0
	for unit in hellions:
		lost += float(Catalog.units()[kind].hp) - maxf(0.0, float(unit.hp))
	return {"exposure":exposure / float(hellions.size()), "lost":lost}

func _hellion_splash() -> void:
	var before := _hellion_run("hellbat_legacy")
	var after := _hellion_run("hellbat")
	print("HELLION splash exposure per shot %.3f -> %.3f, hp lost %.1f -> %.1f" % [before.exposure, after.exposure, before.lost, after.lost])
	check(float(after.exposure) < float(before.exposure) * 0.75, "hellions settle with at least 25% less tank-splash overlap")
	check(float(after.lost) < float(before.lost), "hellions take less real splash damage than with the old radius")

## 一只跳虫沿行军路线前进，路线侧方11格外有远程溅射炮开火：跳虫必须转向攻击炮，不能继续沿路线离开交战。
func _melee_engages_long_range_attacker() -> void:
	var sim = bare()
	var ling: Dictionary = sim.spawn_unit(0, "zergling", Vector2(60.0, 59.0))
	var gun: Dictionary = sim.spawn_unit(1, "artillery", Vector2(70.0, 70.0))
	var was_hit := false
	var closest := INF
	for i in range(200):
		sim.step()
		if float(ling.hp) < float(Catalog.units().zergling.hp):
			was_hit = true
		closest = minf(closest, ling.pos.distance_to(gun.pos))
	check(closest < 2.5, "zergling closes in on the long-range attacker (closest %.1f)" % closest)
	check(float(gun.hp) < float(ARTILLERY.hp), "zergling actually attacks the long-range attacker")
	check(ling.pos.x < 80.0, "zergling does not run off along the march route (x %.1f)" % ling.pos.x)
	check(was_hit or float(gun.hp) < float(ARTILLERY.hp), "scenario exercises the long-range engagement")

## 先锋与追猎者同行；敌方远程炮在追猎者射程外轰击：近战不能独自沿路线冲走，应和部队一起压向敌人。
func _melee_stays_with_army() -> void:
	var sim = bare()
	var zealot: Dictionary = sim.spawn_unit(0, "vanguard", Vector2(60.0, 59.0))
	var stalker: Dictionary = sim.spawn_unit(0, "stalker", Vector2(59.0, 59.0))
	var gun: Dictionary = sim.spawn_unit(1, "artillery", Vector2(64.0, 72.0))
	var spread := 0.0
	for i in range(120):
		sim.step()
		spread = maxf(spread, zealot.pos.distance_to(stalker.pos))
	check(zealot.pos.distance_to(gun.pos) < 3.0, "melee unit engages the attacker instead of marching past it")
	check(spread < 12.0, "melee unit stays within reach of its army (max gap %.1f)" % spread)

func _engage_respects_layers_and_radius() -> void:
	var sim = bare()
	var ling: Dictionary = sim.spawn_unit(0, "zergling", Vector2(60.0, 59.0))
	sim.spawn_unit(1, "viking", Vector2(62.0, 66.0))
	sim.spawn_unit(1, "post", Vector2(60.0, 59.0 + float(sim.rules.get("engage_radius",30)) + 6.0))
	ticks(sim, 40)
	check(ling.pos.x > 65.0 and absf(ling.pos.y - 59.0) < 2.0, "ground melee ignores air and out-of-radius enemies and keeps marching")
