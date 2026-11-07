# 中文导读：自动验证战斗规则的开发脚本，不是玩家游戏入口。
# 运行命令见 README；不需要打开游戏窗口，也不会修改玩家存档。
# 测试中不少数值固定对应 v0.1 的基线；有意改平衡后，应检查预期而非直接删除失败测试。
extends SceneTree
const Sim = preload("res://scripts/battle_sim.gd")
const LineAttack = preload("res://scripts/skills/line_attack.gd")
const AI = preload("res://scripts/commander_ai.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Shield = preload("res://scripts/skills/shield.gd")
var failures := 0
var checks := 0

## 记录一项检查；失败时打印原因并增加计数，最后用非零退出码提示失败。
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

## 不放置门口塔与宝库的模拟，用于隔离单位行为；结构体规则在 _structures() 中单独测试。
func bare(seed_value: int = 42, overrides: Dictionary = {}):
	var settings: Dictionary = overrides.duplicate(true)
	settings.structures = false
	return Sim.new(seed_value, settings)

## 测试辅助函数：生成单一兵种的简单阵容，按格子 0、1、2……放置。
func formation(kind: String, count: int) -> Array:
	var result: Array = []
	for i in range(count):
		result.append({"kind":kind,"cell":i})
	return result

## 连续推进若干模拟步，不等待真实时间，因此可以快速完成一整局测试。
func ticks(sim, count: int) -> void:
	for i in range(count):
		sim.step()

## 训练假人：只用于测试的人族重甲近战单位（相当于 0.2 版的盾卫），不进入游戏数据。
## 很多旧测试用它当靶子；它没有护盾和护甲点数，便于手算伤害。
const DUMMY := {"name":"训练假人","symbol":"?","race":"terran","status":"ready","cost":100,"hp":480,"armor_type":"heavy","armor":0,"damage":16,"interval":1.2,"range":25,"speed":34,"splash":0,"color":"7ed8ed","role":"测试","counter":"测试","layer":"ground","target_layers":["ground"]}

## SceneTree 脚本启动时运行测试集，覆盖校验、波次、残兵、胜负、AI 和性能。
func _initialize() -> void:
	Catalog.extra_units = {"dummy": DUMMY}
	_targeting()
	_medics()
	_siege()
	_siege_scanning()
	_piercers()
	_colossi_and_skills()
	_marauders()
	_stimulant_and_slow()
	_liberators()
	_spatial_equivalence()
	_structures()
	_setup_options()
	_armor_and_shields()
	_roster_data()
	_races()
	_battlecruisers()
	_economy()
	_final_phase()
	var sim = bare()
	var grid: int = int(sim.rules.columns * sim.rules.rows)
	check(sim.minerals==[600,600],"both sides start with start_minerals")
	check(sim.submit_formation(0,formation("dummy",7))!="" and sim.formations[0].is_empty() and sim.minerals[0]==600,"reject over minerals without partial purchase")
	check(sim.submit_formation(0,[{"kind":"dummy","cell":0},{"kind":"rifle","cell":0}])!="","reject duplicate cell")
	check(sim.submit_formation(0,[{"kind":"dummy","cell":grid}])!="","reject out of range")
	check(sim.submit_formation(0,[{"kind":"dummy","cell":1.5}])!="","reject fractional cell")
	check(sim.submit_formation(0,[{"kind":"unknown","cell":0}])!="","reject unknown unit")
	check(sim.submit_formation(0,[])=="","allow empty formation")
	for team in range(2):
		check(sim.submit_formation(team,Catalog.starter())=="","same validator team %d" % team)
	check(sim.minerals==[0,0],"starter roster spends all 600")
	check(not sim.get_snapshot(0).has("formations") and sim.get_snapshot(0).minerals==0,"snapshot hides opponent roster and minerals")
	ticks(sim,599)
	check(sim.units.is_empty() and sim.wave==0,"no early spawn")
	sim.step()
	check(sim.wave==1 and sim.units.size()==14,"simultaneous first wave")
	check(sim.minerals==[300,300],"wave income credited after spawn")
	var id: int = sim.units[0].id
	sim.submit_formation(0,[])
	check(sim.units[0].id==id and sim.last_formations[0].size()==7,"editing leaves battlefield intact")
	check(sim.minerals[0]==300,"cancelling deployed units refunds nothing")
	check(sim.journal.waves[0].formations[0].size()==7 and sim.journal.actions.size()==21,"journal records waves and every buy/sell")
	ticks(sim,600)
	check(sim.wave==2 and sim.units.size()>=7 and sim.last_formations[0].is_empty() and sim.last_formations[1].size()==7,"permanent roster respawns every wave")
	# 寿命为可选规则：默认 0 不撤离；配置为 90 秒时精确检查前一刻和刚到 90 秒的区别。
	var immortal = bare()
	var veteran: Dictionary = immortal.spawn_unit(0,"dummy",Vector2(100,100))
	veteran.born = -100000
	immortal.step()
	check(immortal.units.size()==1,"default rules never expire units")
	var lifetime = bare(42,{"unit_lifetime":90})
	var survivor: Dictionary = lifetime.spawn_unit(0,"dummy",Vector2(100,100))
	survivor.born = -1798
	lifetime.step()
	check(lifetime.units.size()==1,"survivor retained before expiry")
	lifetime.step()
	check(lifetime.units.is_empty(),"optional expiry exactly 90 seconds")
	var retained = bare()
	retained.spawn_unit(0,"dummy",Vector2(500,100))
	retained.tick=599
	retained.submit_formation(0,formation("rifle",1))
	retained.step()
	check(retained.units.size()==2 and retained.units[0].id==1,"next wave retains survivors")
	# 同时摧毁基地必须判平，不能因为某队先被处理就先判负。
	var draw = bare()
	draw.bases=[1.0,1.0]
	draw.spawn_unit(0,"rifle",Vector2(1150,200))
	draw.spawn_unit(1,"rifle",Vector2(50,200))
	draw.step()
	check(draw.finished and draw.winner==-1,"simultaneous base destruction draws")
	var mutual = bare()
	for team in range(2):
		mutual.spawn_unit(team,"rifle",Vector2(550+team*100,200)).hp = 1
	mutual.step()
	check(mutual.units.is_empty() and mutual.kills==[1,1],"simultaneous lethal attacks both fire")
	var commander = AI.new()
	for minerals in [0,50,600,900,1200,5000]:
		check(sim.validate_formation(commander.choose(Catalog.starter(),minerals),minerals)=="","AI obeys minerals and grid %d" % minerals)
	# 镜像公平测试：相同配置放在两侧，击杀数与基地状态应保持一致。
	var mirror = bare()
	mirror.submit_formation(0,Catalog.starter())
	mirror.submit_formation(1,Catalog.starter())
	ticks(mirror,2400)
	check(is_equal_approx(mirror.bases[0],mirror.bases[1]) and mirror.kills[0]==mirror.kills[1],"mirror battle has no side advantage")
	var replay = bare()
	replay.submit_formation(0,Catalog.starter())
	replay.submit_formation(1,Catalog.starter())
	ticks(replay,2400)
	check(replay.get_snapshot()==mirror.get_snapshot(),"same inputs reproduce same simulation")
	_counter("agent",4,"dummy",5,"armor-piercing agent vs heavy")
	_counter("rifle",4,"swarm",6,"rifle vs light")
	_counter("mortar",2,"swarm",6,"splash vs swarm")
	_counter("ultralisk",1,"rifle",5,"ultralisk armor vs rifles")
	_counter("mortar",2,"agent",2,"siege outranges agent")
	_counter("hellbat",3,"zergling",6,"flame vs light melee")
	_counter("immortal",1,"roach",3,"immortal vs heavy")
	_counter("viking",2,"liberator",1,"viking vs heavy air")
	# 压力测试使用 200 个高血量单位，避免测试过程中快速减员；这个测试不测画面 FPS。
	var stress = bare()
	for team in range(2):
		for i in range(100):
			var u: Dictionary = stress.spawn_unit(team,"dummy",Vector2(400+team*400+(i%10)*4,30+(i/10)*34))
			u.hp=1000000.0
	var begin := Time.get_ticks_usec()
	ticks(stress,600)
	var elapsed: float = float(Time.get_ticks_usec()-begin)/1000.0
	print("PERF 200 units, 600 ticks: %.2f ms total, %.3f ms/tick" % [elapsed,elapsed/600.0])
	print("RESULT %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

## 让两个等预算单兵种编队作战，交换左右位置再测一次，排查阵营顺序优势。
func _counter(a: String, a_count: int, b: String, b_count: int, label: String) -> void:
	var outcomes: Array = []
	for reverse in range(2):
		var sim = bare()
		for i in range(a_count):
			sim.spawn_unit(reverse,a,Vector2(430 if reverse==0 else 770,170+(i%3)*20))
		for i in range(b_count):
			sim.spawn_unit(1-reverse,b,Vector2(770 if reverse==0 else 430,170+(i%3)*20))
		ticks(sim,500)
		var a_survivors:=0
		var b_survivors:=0
		for unit in sim.units:
			if unit.team==reverse:a_survivors+=1
			else:b_survivors+=1
		outcomes.append([a_survivors,b_survivors])
		check(a_survivors>0 and b_survivors==0,label+" side %d" % reverse)
	print("COUNTER %s: %s" % [label,str(outcomes)])

## 发现边界、追击重选、实际开火锁定、冷却保持及失效后的重新索敌。
func _targeting() -> void:
	for kind in Catalog.units():
		var boundary = bare()
		var observer = boundary.spawn_unit(0, kind, Vector2(500,200))
		var radius: float = float(boundary.catalog[kind].range) * 1.5
		var enemy_kind: String = "liberator" if boundary.catalog[kind].get("target_layers",["ground"]) == ["air"] else "dummy"
		var enemy = boundary.spawn_unit(1, enemy_kind, Vector2(500+radius,200))
		boundary._build_buckets()
		check(boundary._target(observer).get("id",0)==enemy.id,kind+" discovers at 150% range")
		enemy.pos.x += 0.01
		boundary._build_buckets()
		check(boundary._target(observer).is_empty(),kind+" ignores beyond discovery range")
	var sim = bare()
	# 静止、高生命敌人用于隔离索敌行为，避免移动或死亡干扰测试。
	sim.catalog.dummy.speed = 0
	var shooter = sim.spawn_unit(0,"rifle",Vector2(500,200))
	var first = sim.spawn_unit(1,"dummy",Vector2(680,200))
	first.hp = 10000
	sim.step()
	check(shooter.pos.x>500 and shooter.locked_target_id==0,"pursuit moves without locking")
	var closer = sim.spawn_unit(1,"dummy",Vector2(600,200))
	closer.hp = 10000
	shooter.cooldown = 1.0
	sim.step()
	check(shooter.locked_target_id==0 and closer.hp==10000,"in range before first shot stays unlocked")
	shooter.cooldown = 0.0
	sim.step()
	check(shooter.locked_target_id==closer.id and closer.hp<10000,"first shot locks newly closer target")
	first.pos = Vector2(550,200)
	var original_hp: float = first.hp
	sim.step()
	check(shooter.locked_target_id==closer.id,"cooldown preserves lock despite closer enemy")
	shooter.cooldown = 0.0
	var locked_hp: float = closer.hp
	sim.step()
	check(first.hp==original_hp and closer.hp<locked_hp,"subsequent shot retains target")
	# 锁定目标仍在发现范围，却已离开攻击范围：必须释放并重新选择。
	closer.pos = shooter.pos + Vector2(150,0)
	shooter.cooldown = 0.0
	sim.step()
	check(shooter.locked_target_id==first.id and first.hp<original_hp,"leaving attack range triggers reselection")
	first.hp = 1
	shooter.cooldown = 0.0
	sim.step()
	check(not sim.units.has(first),"locked target killed")
	closer.pos = shooter.pos + Vector2(100,0)
	shooter.cooldown = 0.0
	sim.step()
	check(shooter.locked_target_id==closer.id,"dead target replaced")
	sim.rules.unit_lifetime = 90
	closer.born = sim.tick - int(sim.rules.unit_lifetime * sim.rules.tick_rate)
	sim.step()
	check(shooter.locked_target_id==0,"expired target releases lock")
	# 特工：按目标护甲选择武器；换弹 1.5 秒内不能开火。雷神按目标层选武器，没有换弹时间。
	var spec = bare()
	for kind in ["dummy","rifle"]:
		spec.catalog[kind].speed = 0
		spec.catalog[kind].damage = 0
	var agent = spec.spawn_unit(0,"agent",Vector2(500,200))
	var heavy = spec.spawn_unit(1,"dummy",Vector2(650,200))
	heavy.hp = 10000
	var opening: Array = spec.step()
	check(int(agent.get("weapon_index",0))==0 and heavy.hp==9910 and not opening.any(func(e): return e.type=="weapon_switch"),"agent opens with armor-piercing rounds on heavy armor")
	spec.units.erase(heavy)
	var light = spec.spawn_unit(1,"rifle",Vector2(650,200))
	light.hp = 10000
	agent.cooldown = 0
	var switching: Array = spec.step()
	check(agent.weapon_index==1 and light.hp==10000 and switching.any(func(e): return e.type=="weapon_switch" and e.weapon=="precision"),"light target starts switch to precision rounds")
	ticks(spec,29)
	check(light.hp==10000 and agent.pos==Vector2(500,200),"agent cannot fire or move during 1.5-second switch")
	spec.step()
	check(light.hp==9940 and agent.locked_target_id==light.id,"precision rounds fire after switch: 30 + 30 light bonus")
	var hammer = bare()
	hammer.catalog.dummy.speed = 0
	hammer.catalog.dummy.damage = 0
	var thor = hammer.spawn_unit(0,"thor",Vector2(500,200))
	var walker = hammer.spawn_unit(1,"dummy",Vector2(650,200))
	walker.hp = 10000
	hammer.step()
	check(thor.get("weapon_index",0)==0 and walker.hp==9820,"thor uses ground cannon on ground")
	hammer.units.erase(walker)
	var flyer = hammer.spawn_unit(1,"liberator",Vector2(700,200))
	flyer.hp = 10000
	thor.cooldown = 0
	hammer.step()
	check(thor.weapon_index==1 and flyer.hp==9928,"thor swaps to anti-air missiles instantly; no light bonus on heavy air")

## 治疗、冷却、上限、阵营与前排安全站位，双方方向均需一致。
func _medics() -> void:
	for team in range(2):
		var sim = bare()
		sim.catalog.dummy.speed = 0
		var direction: float = 1 if team == 0 else -1
		var medic = sim.spawn_unit(team,"medic",Vector2(600,200))
		var ally = sim.spawn_unit(team,"dummy",Vector2(600+direction*100,200))
		ally.hp = 200
		var enemy = sim.spawn_unit(1-team,"dummy",Vector2(600+direction*60,200))
		enemy.hp = 100
		var events: Array = sim.step()
		check(ally.hp==212 and enemy.hp==100 and medic.hp==160,"medic only heals injured ally %d" % team)
		check(events.any(func(e): return e.type=="heal"),"heal event emitted")
		sim.step()
		check(ally.hp==212,"healing respects cooldown")
		check(float(medic.pos.x)*direction<600*direction,"medic retreats from nearby enemy")
		sim.units.erase(enemy)
		medic.cooldown=0
		ally.hp=479
		sim.step()
		check(ally.hp==480,"healing capped at max hp")
		medic.hp=50
		medic.cooldown=0
		events=sim.step()
		check(medic.hp==50 and not events.any(func(e): return e.type=="heal"),"no self healing or healing full ally")
		# 医疗兵误放在前排时主动后撤；战斗单位消失后继续退向基地。
		medic.pos=Vector2(600+direction*130,200)
		var before: float = medic.pos.x
		sim.step()
		check(float(medic.pos.x)*direction<before*direction,"medic moves behind frontline")
		sim.units.erase(ally)
		before=medic.pos.x
		sim.step()
		check(float(medic.pos.x)*direction<before*direction and sim.bases==[3000.0,3000.0],"isolated medic retreats and never attacks base")
	var priority = bare()
	priority.catalog.dummy.speed=0
	priority.catalog.rifle.speed=0
	var healer=priority.spawn_unit(0,"medic",Vector2(500,200))
	var tank=priority.spawn_unit(0,"dummy",Vector2(600,200))
	var rifle=priority.spawn_unit(0,"rifle",Vector2(590,220))
	tank.hp=240
	rifle.hp=30
	priority.step()
	check(rifle.hp==42 and tank.hp==240,"heal lowest health ratio, not largest missing hp")
	healer.cooldown=0
	rifle.pos=Vector2(800,200)
	priority.step()
	check(rifle.hp==42 and tank.hp==252,"out of range ally cannot be healed")
	var support=priority.spawn_unit(0,"medic",Vector2(490,200))
	support.hp=10
	healer.cooldown=0
	priority.step()
	check(support.hp==22,"medic can heal another medic")
	# 两个治疗同时生效，过量治疗不能抵消本步本应致死的伤害。
	var lethal=bare()
	var victim=lethal.spawn_unit(0,"rifle",Vector2(600,200))
	victim.hp=119
	lethal.spawn_unit(0,"medic",Vector2(500,180))
	lethal.spawn_unit(0,"medic",Vector2(500,220))
	lethal.catalog.dummy.range = 200
	lethal.catalog.dummy.damage = 130
	lethal.spawn_unit(1,"dummy",Vector2(700,200))
	lethal.step()
	check(not lethal.units.has(victim),"overhealing cannot act as a shield")
	var ai=AI.new()
	var formation_with_medic: Array=ai.choose([],700)
	check(formation_with_medic.any(func(s): return s.kind=="medic" and int(s.cell) % int(lethal.rules.columns)==0),"AI buys medic in rear column")
	check(lethal.validate_formation(formation_with_medic,700)=="","AI medic formation within budget")

## 架设与收起按模拟时间推进，轻重甲伤害、基地攻击与锁定行为共用规则。
func _siege() -> void:
	for team in range(2):
		var sim=bare()
		sim.catalog.dummy.speed=0
		sim.catalog.rifle.speed=0
		sim.catalog.dummy.damage=0
		sim.catalog.rifle.damage=0
		var forward: float = 1 if team==0 else -1
		var gun=sim.spawn_unit(team,"mortar",Vector2(600,200))
		var heavy=sim.spawn_unit(1-team,"dummy",Vector2(600+forward*280,200))
		var light=sim.spawn_unit(1-team,"rifle",Vector2(600+forward*290,220))
		var friend=sim.spawn_unit(team,"dummy",Vector2(600+forward*285,210))
		heavy.hp=1000
		light.hp=1000
		var initial: Vector2=gun.pos
		sim.step()
		check(gun.siege_state=="mobile" and gun.locked_target_id==0,"first scan does not deploy")
		ticks(sim,10)
		check(gun.siege_state=="deploying" and gun.locked_target_id==0,"begin setup without firing lock")
		ticks(sim,29)
		check(gun.pos==initial and heavy.hp==1000 and light.hp==1000,"setup blocks movement and early firing")
		sim.step()
		check(gun.siege_state=="deployed" and heavy.hp==790 and light.hp==880,"first deployed shot: 120 + 90 heavy bonus, 120 to light")
		check(friend.hp==480 and gun.locked_target_id==heavy.id,"splash ignores friends and locks main target")
		ticks(sim,42)
		check(heavy.hp==790 and gun.pos==initial,"deployed cooldown blocks early shot and movement")
		sim.step()
		check(heavy.hp==580,"deployed second shot respects interval")
		# 目标仍在发现范围内，却离开攻击距离，必须收起，不能边架设边追击。
		heavy.pos=Vector2(600+forward*360,200)
		light.pos=Vector2(600+forward*380,220)
		sim.step()
		check(gun.siege_state=="packing" and gun.locked_target_id==0,"out of range releases lock and starts packing")
		ticks(sim,19)
		check(gun.pos==initial and gun.siege_state=="packing","packing blocks movement")
		sim.step()
		check(gun.siege_state=="mobile" and gun.pos==initial,"packing completes after full duration")
		sim.step()
		check(float(gun.pos.x)*forward>initial.x*forward,"mobile artillery resumes pursuit")
		# 转换期间新敌人出现也不能跳过收起/架设时间。
		heavy.pos=gun.pos+Vector2(forward*270,0)
		sim.step()
		ticks(sim,int(gun.siege_scan_tick)-sim.tick+10)
		check(gun.siege_state=="deploying","returning target requires new setup")
		heavy.pos=gun.pos+Vector2(forward*350,0)
		sim.step()
		check(gun.siege_state=="packing","lost target during setup triggers packing")
		heavy.pos=gun.pos+Vector2(forward*270,0)
		var before: float=heavy.hp
		ticks(sim,20)
		check(gun.siege_state=="mobile" and heavy.hp==before,"target returning during packing cannot fire")
		sim.step()
		ticks(sim,10)
		ticks(sim,29)
		check(heavy.hp==before,"new setup cannot fire early")
		sim.step()
		check(heavy.hp==before-210,"new setup fires when complete")
		# 已架设时目标死亡，只要另一个目标仍在射程内就直接转火。
		sim.units.erase(heavy)
		light.pos=gun.pos+Vector2(forward*270,0)
		gun.cooldown=0
		sim.step()
		check(gun.siege_state=="deployed" and gun.locked_target_id==light.id,"deployed gun reacquires without unnecessary setup")
	var base=bare()
	var siege=base.spawn_unit(0,"mortar",Vector2(900,200))
	base.step()
	ticks(base,29)
	check(base.bases[1]==3000,"base attack also requires setup")
	base.step()
	check(base.bases[1]==2880 and siege.siege_state=="deployed","deployed artillery attacks base")
	# 受伤炮兵在完成架设前仍可被射程内的特工击杀。
	var ambush=bare()
	var fragile=ambush.spawn_unit(0,"mortar",Vector2(500,200))
	fragile.hp=50
	ambush.spawn_unit(1,"agent",Vector2(700,200))
	ambush.step()
	check(not ambush.units.has(fragile),"agent ambush kills artillery before setup")

## 防止短暂目标导致反复架设：确认同一敌人，以及外圈接近方向。
func _siege_scanning() -> void:
	var scan=bare()
	scan.catalog.dummy.speed=0
	var gun=scan.spawn_unit(0,"mortar",Vector2(500,200))
	var first=scan.spawn_unit(1,"dummy",Vector2(770,200))
	scan.spawn_unit(0,"dummy",Vector2(510,200))
	scan.step()
	check(gun.siege_state=="mobile" and gun.locked_target_id==0,"single transient enemy only observed")
	scan.units.erase(first)
	var second=scan.spawn_unit(1,"dummy",Vector2(775,200))
	ticks(scan,10)
	check(gun.siege_state=="mobile","different ID on second scan cannot confirm first enemy")
	scan.units.erase(second)
	ticks(scan,10)
	scan.spawn_unit(1,"dummy",Vector2(780,200))
	ticks(scan,10)
	check(gun.siege_state=="mobile","empty scan clears old observations")
	ticks(scan,10)
	check(gun.siege_state=="deploying","same enemy across consecutive scans confirms setup")
	var crowd=bare()
	crowd.catalog.dummy.speed=0
	var artillery=crowd.spawn_unit(0,"mortar",Vector2(500,200))
	crowd.spawn_unit(1,"dummy",Vector2(770,180))
	crowd.spawn_unit(1,"dummy",Vector2(770,220))
	crowd.step()
	check(artillery.siege_state=="mobile","exactly X enemies still need confirmation")
	crowd.spawn_unit(1,"dummy",Vector2(780,200))
	crowd.step()
	check(artillery.siege_state=="deploying","more than X enemies deploy immediately between scans")
	# 靠近判断采用上一模拟步的位移；双方镜像均须保持架设并最终开火。
	for team in range(2):
		var sim=bare()
		var direction: float=1 if team==0 else -1
		var cannon=sim.spawn_unit(team,"mortar",Vector2(600,200))
		cannon.siege_state="deployed"
		cannon.cooldown=10
		var victim=sim.spawn_unit(1-team,"dummy",Vector2(600+direction*270,200))
		victim.hp=1
		sim.spawn_unit(team,"agent",Vector2(600+direction*100,200))
		var incoming=sim.spawn_unit(1-team,"dummy",Vector2(600+direction*350,240))
		sim.step()
		check(not sim.units.has(victim),"ally kills original target")
		sim.step()
		check(cannon.siege_state=="deployed" and cannon.pos==Vector2(600,200),"approaching outer enemy prevents packing after ally kill")
		cannon.cooldown=0
		ticks(sim,35)
		check(cannon.siege_state=="deployed" and cannon.locked_target_id==incoming.id,"held artillery fires when next enemy reaches range")
	# 120% 边界包含接近敌人；静止、远离、切向及超出边界不算接近。
	for scenario in ["approaching","stationary","away","tangent","outside"]:
		var sim=bare()
		sim.catalog.dummy.speed=0
		var cannon=sim.spawn_unit(0,"mortar",Vector2(500,200))
		cannon.siege_state="deployed"
		var x: float=860.01 if scenario=="outside" else 860.0
		var enemy=sim.spawn_unit(1,"dummy",Vector2(x,200))
		enemy.prev=enemy.pos
		if scenario=="approaching" or scenario=="outside": enemy.prev.x+=1
		elif scenario=="away": enemy.prev.x-=1
		elif scenario=="tangent": enemy.prev.y-=1
		sim.step()
		check(cannon.siege_state==("deployed" if scenario=="approaching" else "packing"),"outer approach check: "+scenario)
	# 架设中也保持相同的外圈判定，避免刚启动就因原目标死亡取消。
	var setup=bare()
	var cannon=setup.spawn_unit(0,"mortar",Vector2(500,200))
	cannon.siege_state="deploying"
	cannon.siege_until_tick=2
	var enemy=setup.spawn_unit(1,"dummy",Vector2(840,200))
	enemy.prev.x+=1
	setup.step()
	check(cannon.siege_state=="deploying","approaching enemy preserves ongoing setup")
	setup.step()
	check(cannon.siege_state=="deployed" and cannon.locked_target_id==0,"setup completes while waiting for approaching enemy")

## 地刺沿开火方向传播到固定射程，每波对每个敌人最多命中一次。
func _piercers() -> void:
	for team in range(2):
		var sim=bare()
		sim.catalog.dummy.speed=0
		sim.catalog.dummy.damage=0
		var forward: float=1 if team==0 else -1
		var gun=sim.spawn_unit(team,"piercer",Vector2(600,200))
		gun.siege_state="deployed"
		var near=sim.spawn_unit(1-team,"dummy",Vector2(600+forward*80,200))
		var far=sim.spawn_unit(1-team,"dummy",Vector2(600+forward*200,200))
		var edge=sim.spawn_unit(1-team,"dummy",Vector2(600+forward*224,200))
		var beyond=sim.spawn_unit(1-team,"dummy",Vector2(600+forward*225,200))
		var width_edge=sim.spawn_unit(1-team,"dummy",Vector2(600+forward*130,214))
		var outside=sim.spawn_unit(1-team,"dummy",Vector2(600+forward*150,214.01))
		var friend=sim.spawn_unit(team,"dummy",Vector2(600+forward*100,200))
		for victim in [near,far,edge,beyond,width_edge,outside,friend]:victim.hp=1000
		sim.step()
		check(sim.attack_waves.size()==1 and near.hp==1000 and far.hp==1000,"piercer launches without instant damage")
		check(gun.locked_target_id==near.id and sim.attack_waves[0].length==224,"near target sets direction, not line length")
		var snapshot: Dictionary=sim.get_snapshot()
		snapshot.attack_waves[0].distance=999
		check(sim.attack_waves[0].distance==0,"wave snapshot is independent")
		var behind=sim.spawn_unit(1-team,"dummy",Vector2(600-forward*10,200))
		behind.hp=1000
		ticks(sim,6)
		check(near.hp==1000,"near enemy unharmed before wave arrives")
		sim.step()
		check(near.hp==910 and far.hp==1000,"wave reaches near enemy before far enemy")
		# 发射者死亡和原目标死亡都不能取消已经发出的地刺。
		sim.units.erase(gun)
		sim.units.erase(near)
		ticks(sim,8)
		check(far.hp==1000,"far enemy unharmed until travel time elapses")
		sim.step()
		check(far.hp==910,"wave survives shooter and original target removal")
		ticks(sim,4)
		check(edge.hp==910 and beyond.hp==1000,"fixed range includes endpoint and excludes beyond it")
		check(width_edge.hp==910 and outside.hp==1000,"line half-width boundary")
		check(friend.hp==1000 and behind.hp==1000,"no friendly fire or damage behind origin")
		check(far.hp==910 and sim.attack_waves.is_empty(),"one hit per victim and completed wave cleaned up")
	var dodge=bare()
	dodge.catalog.rifle.speed=0
	dodge.catalog.rifle.damage=0
	var gun=dodge.spawn_unit(0,"piercer",Vector2(500,200))
	gun.siege_state="deployed"
	var target=dodge.spawn_unit(1,"rifle",Vector2(580,200))
	var far=dodge.spawn_unit(1,"rifle",Vector2(700,200))
	dodge.step()
	target.pos=Vector2(580,260)
	dodge.units.erase(gun)
	ticks(dodge,9)
	var late=dodge.spawn_unit(1,"rifle",Vector2(580,200))
	ticks(dodge,11)
	check(target.hp==120 and far.hp==60,"wave does not home; target can dodge while rear enemy is hit")
	check(late.hp==120,"entering behind passed wave causes no retroactive damage")
	# 本步横穿路径的敌人必须在波前到达时位于线宽内，不能只检查两个端点。
	var wave={"origin":Vector2.ZERO,"direction":Vector2.RIGHT,"distance":0.0,"half_width":14.0}
	check(LineAttack.crosses(wave,Vector2(10,30),Vector2(10,-30),20),"swept hit catches crossing during tick")
	check(not LineAttack.crosses(wave,Vector2(10,40),Vector2(10,20),20),"swept hit excludes missed path")
	var setup=bare()
	setup.catalog.dummy.speed=0
	setup.catalog.dummy.damage=0
	var burrower=setup.spawn_unit(0,"piercer",Vector2(500,200))
	var enemy=setup.spawn_unit(1,"dummy",Vector2(700,200))
	setup.step()
	check(burrower.siege_state=="mobile" and setup.attack_waves.is_empty(),"burrow uses same two-scan confirmation")
	ticks(setup,10)
	check(burrower.siege_state=="deploying","confirmed piercer starts burrowing")
	ticks(setup,19)
	check(setup.attack_waves.is_empty() and burrower.pos==Vector2(500,200),"burrowing forbids early attack and movement")
	setup.step()
	check(burrower.siege_state=="deployed" and setup.attack_waves.size()==1,"burrowed piercer launches attack")
	var hunter=setup.spawn_unit(1,"agent",Vector2(650,200))
	setup.step()
	check(hunter.locked_target_id==burrower.id and burrower.hp<515,"burrowed unit remains visible and attackable")
	setup.units.erase(enemy)
	setup.units.erase(hunter)
	setup.step()
	check(burrower.siege_state=="packing","piercer emerges when no enemies remain")
	ticks(setup,14)
	check(burrower.pos==Vector2(500,200) and burrower.siege_state=="packing","cannot move during emergence")
	setup.step()
	setup.step()
	check(burrower.siege_state=="mobile" and burrower.pos.x>500,"movement resumes only after emerging")
	var base=bare()
	var attacker=base.spawn_unit(0,"piercer",Vector2(926,200))
	attacker.siege_state="deployed"
	base.step()
	ticks(base,17)
	check(base.bases[1]==3000,"base waits for wave to reach its edge")
	base.step()
	check(base.bases[1]==2940,"base takes delayed wave damage at maximum range")
	var multi=bare()
	multi.catalog.dummy.speed=0
	multi.catalog.dummy.damage=0
	var source=multi.spawn_unit(0,"piercer",Vector2(500,200))
	var victim=multi.spawn_unit(1,"dummy",Vector2(580,200))
	LineAttack.launch(multi,source,victim.pos)
	LineAttack.launch(multi,source,victim.pos)
	multi.units.erase(source)
	ticks(multi,20)
	check(victim.hp==300,"separate waves each hit once without duplicate damage")

## 巨像横向双束传播与可配置技能复用，不保证必中。
func _colossi_and_skills() -> void:
	for team in range(2):
		var sim=bare()
		for kind in ["rifle","dummy"]:
			sim.catalog[kind].speed=0
			sim.catalog[kind].damage=0
		var forward: float=1 if team==0 else -1
		var giant=sim.spawn_unit(team,"colossus",Vector2(600,200))
		var x: float=600+forward*240
		var center=sim.spawn_unit(1-team,"rifle",Vector2(x,200))
		var top=sim.spawn_unit(1-team,"rifle",Vector2(x,140))
		var bottom=sim.spawn_unit(1-team,"dummy",Vector2(x,260))
		var width_edge=sim.spawn_unit(1-team,"dummy",Vector2(x+forward*14,220))
		var off_line=sim.spawn_unit(1-team,"dummy",Vector2(x+forward*14.01,240))
		var end=sim.spawn_unit(1-team,"dummy",Vector2(x,290))
		var outside=sim.spawn_unit(1-team,"dummy",Vector2(x,290.01))
		var friend=sim.spawn_unit(team,"dummy",Vector2(x,240))
		for unit in [center,top,bottom,width_edge,off_line,end,outside,friend]:unit.hp=1000
		sim.step()
		check(sim.attack_waves.size()==2 and not giant.has("siege_state"),"colossus fires two waves without deployment")
		check(center.hp==1000 and giant.locked_target_id==center.id,"sweep delays damage and locks primary target")
		check(sim.attack_waves[0].direction==-sim.attack_waves[1].direction and sim.attack_waves[0].direction.dot(Vector2(forward,0))==0,"sweeps start at opposite sides perpendicular to aim")
		ticks(sim,4)
		check(top.hp==955 and bottom.hp==970 and center.hp==1000,"outer enemies receive first sweep before center")
		ticks(sim,5)
		check(center.hp==1000,"center unharmed before beam arrival")
		var events: Array=sim.step()
		var center_hits: Array=events.filter(func(e): return e.type=="attack_hit" and e.id==center.id)
		check(center_hits.size()==2 and center_hits[0].strike!=center_hits[1].strike and center.hp==910,"center receives two distinct 45 damage hits")
		ticks(sim,10)
		check(top.hp==910 and bottom.hp==940 and end.hp==940,"both beams cross entire fixed transverse segment")
		check(width_edge.hp==940 and off_line.hp==1000 and outside.hp==1000,"transverse width and length boundaries")
		check(friend.hp==1000 and sim.attack_waves.is_empty(),"sweeps ignore friendly units and expire")
		ticks(sim,1)
		check(sim.attack_waves.is_empty(),"double attack uses one shared attack cooldown")
		sim.step()
		check(sim.attack_waves.size()==2,"next cooldown launches exactly two waves")
	var dodge=bare()
	dodge.catalog.rifle.speed=0
	dodge.catalog.rifle.damage=0
	var giant=dodge.spawn_unit(0,"colossus",Vector2(500,200))
	var target=dodge.spawn_unit(1,"rifle",Vector2(700,200))
	dodge.step()
	target.pos.x+=50
	dodge.units.erase(giant)
	ticks(dodge,20)
	check(target.hp==120 and dodge.attack_waves.is_empty(),"sweep stays fixed and can miss even after shooter disappears")
	# 侧翼单位第一次受击后离开横线，可躲开另一束，证明双击独立结算。
	var partial=bare()
	partial.catalog.rifle.speed=0
	partial.catalog.rifle.damage=0
	var shooter=partial.spawn_unit(0,"colossus",Vector2(500,200))
	partial.spawn_unit(1,"rifle",Vector2(700,200))
	var side=partial.spawn_unit(1,"rifle",Vector2(700,140))
	partial.step()
	ticks(partial,4)
	check(side.hp==75,"first side hit deals one strike")
	side.pos.x+=50
	partial.units.erase(shooter)
	ticks(partial,16)
	check(side.hp==75,"side target can dodge the second strike")
	# 相同技能挂载到全新 ID，仍然可以三重直线攻击并保留部署要求。
	var reuse=bare()
	reuse.catalog["borrowed"]=reuse.catalog.piercer.duplicate(true)
	reuse.catalog.borrowed.skills.multi_attack={"count":3}
	reuse.catalog.dummy.speed=0
	reuse.catalog.dummy.damage=0
	var custom=reuse.spawn_unit(0,"borrowed",Vector2(500,200))
	var victim=reuse.spawn_unit(1,"dummy",Vector2(600,200))
	reuse.step()
	check(custom.siege_state=="mobile" and reuse.attack_waves.is_empty(),"copied deployment skill gates another unit ID")
	ticks(reuse,30)
	check(custom.siege_state=="deployed" and reuse.attack_waves.size()==3,"copied line and multi-attack skills compose")
	ticks(reuse,8)
	check(victim.hp==210,"three independent line hits apply to borrowed unit")
	# 普通单体攻击也能复用双击，不依赖波形攻击。
	var instant=bare()
	instant.catalog["borrowed"]=instant.catalog.rifle.duplicate(true)
	instant.catalog.borrowed.skills={"multi_attack":{"count":2}}
	instant.catalog.rifle.speed=0
	instant.catalog.rifle.damage=0
	instant.spawn_unit(0,"borrowed",Vector2(500,200))
	var light=instant.spawn_unit(1,"rifle",Vector2(600,200))
	var instant_events: Array=instant.step()
	check(light.hp==84 and instant_events.filter(func(e): return e.type=="attack_hit" and e.team==0).size()==2,"ordinary weapon supports two separate strikes")
	var base=bare()
	base.spawn_unit(0,"colossus",Vector2(920,200))
	base.step()
	ticks(base,7)
	check(base.bases[1]==3000,"base receives no instant beam damage")
	base.step()
	check(base.bases[1]==2940,"base receives both delayed beams")
	# 全局旋转后的横线仍垂直于发射方向，不固定在屏幕上下方向。
	var diagonal=bare()
	var rotated=diagonal.spawn_unit(0,"colossus",Vector2(500,100))
	var goal=Vector2(700,250)
	LineAttack.launch(diagonal,rotated,goal)
	var direction: Vector2=(goal-rotated.pos).normalized()
	check(is_zero_approx(diagonal.attack_waves[0].direction.dot(direction)) and diagonal.attack_waves[0].origin.lerp(diagonal.attack_waves[1].origin,0.5).is_equal_approx(goal),"transverse sweep rotates around target with aim")

## 图片基础兵种：单体榴弹、普通索敌、重甲标签及四人预算。
func _marauders() -> void:
	var sim = bare()
	sim.catalog.marauder.skills = {}
	check(sim.formation_cost(formation("marauder",4))==560 and sim.validate_formation(formation("marauder",4),600)=="", "four marauders fit screenshot budget")
	sim.catalog.rifle.speed = 0
	sim.catalog.rifle.damage = 0
	sim.catalog.dummy.speed = 0
	var shooter = sim.spawn_unit(0,"marauder",Vector2(500,200))
	var light = sim.spawn_unit(1,"rifle",Vector2(640,200))
	var heavy = sim.spawn_unit(1,"dummy",Vector2(660,200))
	sim.step()
	check(light.hp==90 and heavy.hp==480 and shooter.locked_target_id==light.id,"marauder description does not override nearest targeting or add splash")
	ticks(sim,21)
	check(light.hp==90,"marauder waits full attack interval")
	sim.step()
	check(light.hp==60,"marauder fires again at 1.07 seconds")
	light.pos.x=800
	shooter.cooldown=0
	sim.step()
	check(heavy.hp==420 and shooter.locked_target_id==heavy.id,"marauder switches after range exit and adds heavy bonus")
	var armor = bare()
	armor.catalog.marauder.skills = {}
	var marauder = armor.spawn_unit(0,"marauder",Vector2(500,200))
	armor.spawn_unit(1,"rifle",Vector2(600,200))
	armor.step()
	check(marauder.hp==325,"marauder armor points reduce rifle damage 18 to 15")
	var found := false
	for seed_value in range(32):
		var army = AI.new(seed_value).choose(formation("marauder",4),1200)
		check(sim.validate_formation(army,1200)=="","AI handles marauder roster seed %d" % seed_value)
		for slot in army:
			found = found or slot.kind=="marauder"
	check(found,"AI can purchase marauder")

## 强化剂与减速必须独立于兵种 ID，按模拟时钟到期并维持同时行动公平。
func _stimulant_and_slow() -> void:
	var stim = bare()
	stim.catalog.dummy.speed = 0
	var caster = stim.spawn_unit(0,"marauder",Vector2(500,200))
	var target = stim.spawn_unit(1,"dummy",Vector2(650,200))
	target.hp = 100000
	var events: Array = stim.step()
	check(caster.hp==289 and caster.stim_until_tick==401,"stim costs 15 percent max HP and lasts 20 seconds")
	check(events.filter(func(e):return e.type=="skill_used").size()==1 and stim.damage_done[1]==0,"stim cost is one skill event, not enemy damage")
	check(is_equal_approx(stim._movement_speed(caster),54),"stim grants 50 percent movement speed")
	ticks(stim,16)
	check(target.hp==99940 and caster.hp==289,"stim neither stacks nor recasts while active; no early shot")
	stim.step()
	check(target.hp==99880,"30 percent attack speed quantizes 1.07-second interval to 17 ticks")
	stim.tick = 400
	stim.step()
	check(caster.hp==238 and caster.stim_until_tick==801,"stim can renew after expiration if still fighting")
	stim.units.erase(target)
	stim.tick = 800
	stim.step()
	check(is_equal_approx(stim._movement_speed(caster),36),"stim expires without combat and restores base speed")
	check(caster.hp==238,"stim does not consume health without enemy target")
	var low = bare()
	low.catalog.dummy.speed=0
	var fragile = low.spawn_unit(0,"marauder",Vector2(500,200))
	var foe = low.spawn_unit(1,"dummy",Vector2(650,200))
	fragile.hp=51
	low.step()
	check(fragile.hp==51 and not fragile.has("stim_until_tick") and foe.hp==420,"low health blocks stimulant but still permits firing")
	var base = bare()
	var sieger = base.spawn_unit(0,"marauder",Vector2(1100,200))
	base.step()
	check(sieger.hp==340 and not sieger.has("stim_until_tick") and base.bases[1]==2970,"base alone does not trigger stimulant")
	for reverse in range(2):
		var healing = bare()
		healing.catalog.dummy.speed=0
		if reverse==0:healing.spawn_unit(0,"medic",Vector2(450,200))
		var ally = healing.spawn_unit(0,"marauder",Vector2(500,200))
		if reverse==1:healing.spawn_unit(0,"medic",Vector2(450,200))
		healing.spawn_unit(1,"dummy",Vector2(650,200))
		healing.step()
		check(ally.hp==289,"medic cannot see future stim cost, order %d" % reverse)
		healing.step()
		check(ally.hp==301,"medic heals stim cost next tick, order %d" % reverse)
	# 比较不同单位处理顺序；首次命中的同一步仍走完整基础速度。
	for reverse in range(2):
		var slow = bare()
		var victim: Dictionary
		if reverse==0:victim=slow.spawn_unit(1,"swarm",Vector2(650,200))
		var attacker = slow.spawn_unit(0,"marauder",Vector2(500,200))
		if reverse==1:victim=slow.spawn_unit(1,"swarm",Vector2(650,200))
		slow.step()
		check(is_equal_approx(victim.pos.x,646.75),"on-hit slow does not alter already decided movement order %d" % reverse)
		attacker.cooldown=1000
		slow.units.erase(attacker)
		slow.step()
		check(is_equal_approx(victim.pos.x,645.125),"slow applies next tick and survives source removal order %d" % reverse)
		slow.tick=40
		slow.step()
		check(is_equal_approx(slow._movement_speed(victim),32.5),"slow includes entire final tick order %d" % reverse)
		slow.step()
		check(is_equal_approx(slow._movement_speed(victim),65),"slow expires after exactly 40 movement ticks order %d" % reverse)
	var refresh = bare()
	refresh.catalog.dummy.speed=0
	var a = refresh.spawn_unit(0,"marauder",Vector2(500,200))
	var b = refresh.spawn_unit(1,"dummy",Vector2(650,200))
	refresh.step()
	a.cooldown=0
	refresh.step()
	check(b.slow_multiplier==0.5 and b.slow_until_tick==43,"repeated hits refresh slow without multiplying it")
	var both = bare()
	var left = both.spawn_unit(0,"marauder",Vector2(500,200))
	var right = both.spawn_unit(1,"marauder",Vector2(600,200))
	both.step()
	check(left.hp==right.hp and is_equal_approx(both._movement_speed(left),27),"simultaneous stim and slow multiply to 75 percent speed symmetrically")
	var snapshot: Dictionary=both.get_snapshot()
	snapshot.units[0].slow_until_tick=0
	check(left.slow_until_tick>0,"snapshot status changes cannot mutate simulation")
	# 慢速光束只有实际命中才施加减速；改名兵种仍可组合多重攻击和被动。
	var wave = bare()
	wave.catalog["borrowed_slow"] = wave.catalog.colossus.duplicate(true)
	wave.catalog.borrowed_slow.skills.on_hit_slow={"speed_multiplier":0.5,"duration":2}
	wave.catalog.dummy.speed=0
	wave.spawn_unit(0,"borrowed_slow",Vector2(500,200))
	var center=wave.spawn_unit(1,"dummy",Vector2(740,200))
	wave.step()
	check(not center.has("slow_until_tick"),"line attack does not slow before arrival")
	ticks(wave,10)
	check(center.hp==420 and center.slow_multiplier==0.5,"two delayed hits apply one nonstacking slow on actual impact")
	var support = bare()
	var medic = support.spawn_unit(0,"medic",Vector2(500,200))
	medic.slow_until_tick=100
	medic.slow_multiplier=0.5
	support.step()
	check(is_equal_approx(medic.pos.x,499.1),"support movement also respects reusable slow")
	var renamed = bare()
	renamed.catalog["borrowed_stim"] = renamed.catalog.rifle.duplicate(true)
	renamed.catalog.borrowed_stim.skills={"stimulant":renamed.catalog.marauder.skills.stimulant.duplicate(true)}
	var borrowed=renamed.spawn_unit(0,"borrowed_stim",Vector2(500,200))
	renamed.spawn_unit(1,"dummy",Vector2(600,200))
	renamed.step()
	check(borrowed.hp==102 and borrowed.has("stim_until_tick"),"stimulant can be assigned to another unit without ID checks")
	var entry = bare()
	entry.catalog.dummy.speed=0
	var approaching = entry.spawn_unit(0,"marauder",Vector2(500,200))
	entry.spawn_unit(1,"dummy",Vector2(669,200))
	approaching.cooldown=10
	entry.step()
	check(not approaching.has("stim_until_tick"),"discovery alone does not trigger stimulant")
	entry.step()
	check(approaching.hp==289 and approaching.cooldown>0,"first combat tick activates stimulant even while attack is cooling down")
	approaching.hp=51
	entry.tick=approaching.stim_until_tick-1
	entry.step()
	check(approaching.hp==51 and is_equal_approx(entry._movement_speed(approaching),36),"expired stimulant rechecks health and cannot renew at lethal cost")

## 解放者：空中层、对空普通武器、防卫圈展开时序、圈内对地与不攻击基地。
func _liberators() -> void:
	for team in range(2):
		var sim = bare()
		sim.catalog.dummy.speed = 0
		sim.catalog.dummy.damage = 0
		var forward: float = 1 if team == 0 else -1
		var ship = sim.spawn_unit(team,"liberator",Vector2(600,200))
		var near = sim.spawn_unit(1-team,"dummy",Vector2(600+forward*300,200))
		var outside = sim.spawn_unit(1-team,"dummy",Vector2(600+forward*300,380))
		near.hp = 10000
		outside.hp = 10000
		sim._build_buckets()
		check(sim._target(ship).is_empty(),"mobile liberator cannot target ground %d" % team)
		check(sim._target(near).is_empty(),"ground-only dummy cannot target air %d" % team)
		sim.step()
		check(ship.siege_state=="mobile" and ship.pos==Vector2(600,200),"liberator stops to scan ground target %d" % team)
		ticks(sim,10)
		check(ship.siege_state=="deploying" and ship.has("defender_center"),"confirmed ground target starts defender mode %d" % team)
		var center: Vector2 = ship.defender_center
		check(center.distance_to(near.pos) <= 140.0 and center.distance_to(ship.pos) <= 476.0 - 140.0 + 0.001,"zone covers target and stays within weapon reach %d" % team)
		ticks(sim,57)
		check(near.hp==10000 and ship.siege_state=="deploying","defender transform takes 2.9 seconds %d" % team)
		sim.step()
		check(ship.siege_state=="deployed" and near.hp==9775,"deployed liberator hits ground target in zone for 225 %d" % team)
		check(outside.hp==10000,"ground target outside zone is ignored %d" % team)
		check(ship.pos==Vector2(600,200) and ship.defender_center==center,"defender mode is stationary with fixed zone %d" % team)
		near.pos = center + Vector2(0,141)
		ship.cooldown = 0
		sim.step()
		check(near.hp==9775 and ship.locked_target_id==0,"target leaving zone releases lock %d" % team)
	var air = bare()
	var hunter = air.spawn_unit(0,"liberator",Vector2(500,200))
	var prey = air.spawn_unit(1,"liberator",Vector2(620,200))
	var wing = air.spawn_unit(1,"liberator",Vector2(620,240))
	air.step()
	check(hunter.siege_state=="mobile" and prey.hp==455 and wing.hp==455,"mobile liberator splashes air targets")
	var rifle_sim = bare()
	var rifle = rifle_sim.spawn_unit(0,"rifle",Vector2(500,200))
	var flyer = rifle_sim.spawn_unit(1,"liberator",Vector2(620,200))
	rifle_sim._build_buckets()
	check(rifle_sim._target(rifle).get("id",0)==flyer.id,"anti-air rifle targets liberator")
	var siege = bare()
	var raider = siege.spawn_unit(0,"liberator",Vector2(1100,200))
	ticks(siege,200)
	check(siege.bases[1]==3000 and raider.siege_state=="mobile","liberator never attacks base")

## 永久兵营的买、卖、移动与退款规则；动作写入战报并可按 tick 重放。
func _economy() -> void:
	var sim = bare()
	check(sim.buy(0,"dummy",5)=="" and sim.minerals[0]==500,"buy deducts cost immediately")
	check(sim.buy(0,"rifle",5)!="" and sim.minerals[0]==500,"cannot buy into occupied cell")
	check(sim.buy(0,"gate_tower",6)!="" and sim.buy(0,"unknown",6)!="","cannot buy unknown kinds")
	check(sim.refund_value(0,5)==100 and sim.sell(0,5)=="" and sim.minerals[0]==600,"undeployed unit refunds 100 percent")
	check(sim.sell(0,5)!="","cannot sell empty cell")
	sim.buy(0,"dummy",5)
	sim.buy(0,"agent",0)
	check(sim.move(0,5,11)=="" and sim.move(0,0,11)=="" and sim.formations[0].any(func(s): return s.kind=="dummy" and s.cell==0),"move swaps cells for free")
	check(sim.minerals[0]==350,"moves cost nothing")
	ticks(sim,600)
	check(sim.is_deployed(0,0) and sim.is_deployed(0,11) and sim.minerals[0]==650,"spawned units become deployed and income arrives")
	check(sim.move(0,0,1)=="" and sim.is_deployed(0,1),"moving keeps deployed status")
	check(sim.refund_value(0,1)==0 and sim.sell(0,1)=="" and sim.minerals[0]==650,"deployed unit can be cancelled without refund")
	sim.buy(0,"rifle",2)
	check(not sim.is_deployed(0,2) and sim.refund_value(0,2)==75,"new purchase after a wave is undeployed again")
	# 整份提交：替换已出场单位不退款；矿物不足时整份拒绝，兵营不变。
	var before: Array = sim.formations[0].duplicate(true)
	check(sim.submit_formation(0,[{"kind":"thor","cell":11},{"kind":"thor","cell":12},{"kind":"thor","cell":13}])!="" and sim.formations[0]==before,"unaffordable replacement is atomic")
	check(sim.submit_formation(0,[{"kind":"medic","cell":11},{"kind":"rifle","cell":2}])=="" and sim.minerals[0]==450,"replacing deployed unit charges full price without refund")
	sim.finished = true
	check(sim.buy(0,"rifle",3)!="" and sim.sell(0,2)!="" and sim.move(0,2,3)!="","finished match rejects edits")
	# 收入与开局资金来自 rules，可被开局设置覆盖。
	var custom = bare(7,{"start_minerals":0,"wave_income":500,"wave_seconds":20})
	check(custom.minerals==[0,0] and custom.submit_formation(0,[{"kind":"rifle","cell":0}])!="","zero start funds leave first wave empty")
	ticks(custom,400)
	check(custom.wave==1 and custom.units.is_empty() and custom.minerals==[500,500],"custom interval and income")
	check(custom.journal.settings.wave_income==500,"journal records match settings")
	# 动作日志重放：按记录的 tick 在下一步前执行，结果与原局逐项一致。
	var live = bare(3)
	var ai = AI.new(3)
	for team in range(2):
		for slot in ai.buy_list([],live.formations[team],live.minerals[team]):
			live.buy(team,slot.kind,slot.cell)
	ticks(live,700)
	live.sell(0,int(live.formations[0][0].cell))
	for slot in ai.buy_list(live.visible_enemy_formation(1),live.formations[1],live.minerals[1]):
		live.buy(1,slot.kind,slot.cell)
	if live.formations[0].size()>1:
		live.move(0,int(live.formations[0][1].cell),int(live.rules.columns)-1)
	ticks(live,1500)
	var copy = bare(3,live.journal.settings)
	var index := 0
	while copy.tick < live.tick:
		while index < live.journal.actions.size() and int(live.journal.actions[index].tick)==copy.tick:
			check(copy.apply_action(live.journal.actions[index])=="","replayed action %d valid" % index)
			index += 1
		copy.step()
	check(copy.get_snapshot(0)==live.get_snapshot(0) and copy.minerals==live.minerals,"action log reproduces simulation")
	# AI 长期增量购买：每波只用自己的矿物、只放空格，总价不超过当时矿物。
	# 只检查购买逻辑，不推进战斗：每轮直接发放收入。
	var shop = bare()
	var buyer = AI.new(11)
	var ok := true
	for round_number in range(120):
		var plan: Array = buyer.buy_list(Catalog.starter(),shop.formations[1],shop.minerals[1])
		ok = ok and shop.formation_cost(plan) <= shop.minerals[1]
		for slot in plan:
			ok = ok and shop.buy(1,slot.kind,slot.cell)==""
		shop.minerals[1] += int(shop.rules.wave_income)
	check(ok and shop.formations[1].size()==int(shop.rules.columns*shop.rules.rows),"AI buys incrementally within minerals until grid is full")

## 最后一波后的胜负：先失去可攻击部队的一方失败；治疗单位不算；双方同时失去为平局；安全时限比较基地。
func _final_phase() -> void:
	var quick = bare(42,{"wave_limit":2})
	quick.submit_formation(0,[{"kind":"dummy","cell":0}])
	ticks(quick,1200)
	check(quick.wave==2 and quick.final_wave_tick==1200 and quick.finished and quick.winner==0,"after final wave, side without attackers loses")
	var limited = bare(42,{"wave_limit":1})
	ticks(limited,600)
	check(limited.finished and limited.winner==-1,"both sides without attackers after final wave draw")
	var stop = bare(42,{"wave_limit":1})
	stop.spawn_unit(0,"dummy",Vector2(100,60))
	stop.spawn_unit(1,"dummy",Vector2(1100,60))
	stop.catalog.dummy.speed=0
	ticks(stop,1300)
	check(stop.wave==1 and not stop.finished and stop.minerals==[900,900],"no spawns or income after final wave")
	var medics = bare(42,{"wave_limit":1})
	medics.spawn_unit(0,"medic",Vector2(100,200))
	medics.spawn_unit(1,"dummy",Vector2(1100,60))
	medics.catalog.dummy.speed=0
	ticks(medics,600)
	check(medics.finished and medics.winner==1,"medic-only side has no attackers")
	var capped = bare(42,{"wave_limit":1,"final_phase_max_seconds":10})
	capped.catalog.dummy.speed=0
	capped.spawn_unit(0,"dummy",Vector2(100,60))
	capped.spawn_unit(1,"dummy",Vector2(1100,60))
	capped.bases=[2500.0,2000.0]
	ticks(capped,799)
	check(not capped.finished,"safety limit not reached early")
	capped.step()
	check(capped.finished and capped.winner==0,"safety limit compares base hp")
	var empty = Sim.new()
	ticks(empty,64*600)
	check(empty.finished and empty.winner==-1 and empty.wave==64,"default match runs 64 waves")

## 加速后的索敌必须与逐个比较的暴力搜索结果完全一致（含多武器单位、空地层、防卫圈与同距 ID）。
func _spatial_equivalence() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var kinds: Array = Catalog.units().keys()
	var mismatches := 0
	var compared := 0
	for trial in range(6):
		var sim = bare()
		for i in range(160):
			var unit = sim.spawn_unit(i % 2, kinds[rng.randi_range(0, kinds.size()-1)], Vector2(rng.randf_range(30,1170), rng.randf_range(20,380)))
			if unit.has("siege_state") and rng.randf() < 0.5:
				unit.siege_state = "deployed"
				unit.defender_center = unit.pos + Vector2(rng.randf_range(-300,300), rng.randf_range(-100,100))
		# 制造同距并列：复制位置，让 ID 决定先后。
		sim.units[3].pos = sim.units[5].pos
		sim._build_buckets()
		for unit in sim.units:
			unit.locked_target_id = 0
			var expected := _brute_target(sim, unit)
			var actual: Dictionary = sim._target(unit)
			compared += 1
			if actual.get("id", 0) != expected.get("id", 0):
				mismatches += 1
			var ground := _brute_ground(sim, unit, 300.0)
			if sim.nearest_ground_enemy(unit, 300.0).get("id", 0) != ground.get("id", 0):
				mismatches += 1
	check(mismatches == 0 and compared == 960, "spatial target search matches brute force (%d mismatches)" % mismatches)

func _brute_target(sim, unit: Dictionary) -> Dictionary:
	var weapon: Dictionary = sim._search_stats(unit)
	var radius: float = float(weapon.range) * 1.5
	var best: Dictionary = {}
	var best_score := INF
	for other in sim.units:
		if other.team == unit.team or other.hp <= 0 or unit.pos.distance_to(other.pos) > radius or not sim._can_hit_unit(unit, other, weapon):
			continue
		var score: float = unit.pos.distance_to(other.pos)
		if score < best_score or (is_equal_approx(score, best_score) and int(other.id) < int(best.get("id", 2147483647))):
			best = other
			best_score = score
	return best

func _brute_ground(sim, unit: Dictionary, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for other in sim.units:
		if other.team == unit.team or other.hp <= 0 or sim.catalog[other.kind].get("layer","ground") != "ground" or sim.is_structure(other):
			continue
		var distance: float = unit.pos.distance_to(other.pos)
		if distance > radius:
			continue
		if distance < best_distance or (is_equal_approx(distance, best_distance) and int(other.id) < int(best.get("id", 2147483647))):
			best = other
			best_distance = distance
	return best

## 门口防御塔、宝库与可建造防御塔：镜像位置、静止、攻击、奖励、建造上限与 AI 规则。
func _structures() -> void:
	var sim = Sim.new()
	var kinds: Array = sim.units.map(func(u): return "%s:%d" % [u.kind,u.team])
	check(kinds.size()==4 and kinds.has("gate_tower:0") and kinds.has("treasury:1"),"each side starts with gate tower and treasury")
	for unit in sim.units:
		var mirror: Dictionary = sim.units.filter(func(o): return o.kind==unit.kind and o.team!=unit.team)[0]
		check(is_equal_approx(unit.pos.x+mirror.pos.x,1200.0) and unit.pos.y==mirror.pos.y,"structure positions mirrored: "+unit.kind)
	check(sim.buy(0,"treasury",0)!="" and sim.buy(0,"tower",0)!="" and sim.buy(0,"gate_tower",0)!="","structures are not purchasable roster units")
	var gate: Dictionary = sim.units.filter(func(u): return u.kind=="gate_tower" and u.team==1)[0]
	var raider = sim.spawn_unit(0,"dummy",gate.pos+Vector2(-200,0))
	raider.hp = 10000
	sim.catalog.dummy.speed = 0
	sim.catalog.dummy.damage = 0
	sim.step()
	check(raider.hp==9955 and gate.pos==Vector2(1100,200),"gate tower fires 45 and never moves")
	check(sim.bases==[3000.0,3000.0],"structures never attack base")
	var flyer = sim.spawn_unit(0,"liberator",gate.pos+Vector2(-150,0))
	sim._build_buckets()
	check(sim._target(gate).get("id",0) in [raider.id,flyer.id] and sim._target(flyer).is_empty(),"towers hit air; liberator cannot attack structures")
	# 宝库：反击弱；摧毁后攻击方得一次奖励，不计击杀。
	var loot = Sim.new()
	var treasury: Dictionary = loot.units.filter(func(u): return u.kind=="treasury" and u.team==1)[0]
	var looter = loot.spawn_unit(0,"agent",treasury.pos+Vector2(-100,0))
	looter.hp = 10000
	loot.catalog.agent.speed = 0
	loot.step()
	check(looter.hp==9990,"treasury counterattack is weak")
	treasury.hp = 1
	looter.cooldown = 0
	var events: Array = loot.step()
	check(not loot.units.has(treasury) and loot.minerals==[1000,600] and loot.kills==[0,0],"destroying treasury rewards attacker once without kill credit")
	check(events.any(func(e): return e.type=="structure_destroyed" and e.kind=="treasury" and e.team==1),"treasury destruction event")
	ticks(loot,10)
	check(loot.minerals==[1000,600],"treasury reward is not repeated")
	# 门口防御塔被摧毁后，基地本身没有任何攻击。
	var open = Sim.new()
	var tower_unit: Dictionary = open.units.filter(func(u): return u.kind=="gate_tower" and u.team==1)[0]
	open.units.erase(tower_unit)
	var intruder = open.spawn_unit(0,"dummy",Vector2(1150,200))
	ticks(open,40)
	check(intruder.hp==480 and open.bases[1]<3000,"base without gate tower cannot fight back")
	# 可建造防御塔：扣矿、固定建造位、每局一次、被摧毁不给奖励。
	var build = Sim.new()
	check(build.tower_error(0)=="" and build.build_tower(0)=="" and build.minerals[0]==100,"build tower costs 500")
	var built: Dictionary = build.units.filter(func(u): return u.kind=="tower")[0]
	check(built.team==0 and built.pos==Vector2(420,290),"tower built at fixed site")
	build.minerals[0] = 5000
	check(build.build_tower(0)!="" and build.minerals[0]==5000,"only one tower per match")
	built.hp = 1
	var killer = build.spawn_unit(1,"dummy",built.pos+Vector2(20,0))
	killer.hp = 100000
	build.step()
	check(not build.units.has(built) and build.minerals[1]==600 and build.build_tower(0)!="","destroyed tower gives no reward and cannot be rebuilt")
	var poor = Sim.new(42,{"start_minerals":499})
	check(poor.build_tower(1)!="" and poor.tower_builds==[0,0],"tower requires minerals")
	check(build.journal.actions.any(func(a): return a.type=="build_tower" and a.team==0),"tower build is journaled")
	# 医疗兵不治疗结构体；结构体不算最后阶段的可攻击部队。
	var care = Sim.new()
	var own_gate: Dictionary = care.units.filter(func(u): return u.kind=="gate_tower" and u.team==0)[0]
	own_gate.hp = 100
	care.spawn_unit(0,"medic",own_gate.pos+Vector2(40,0))
	care.step()
	check(own_gate.hp==100 and care.combat_units(0)==0,"medics ignore structures; structures are not combat units")
	# 带结构体的镜像对局仍然完全对称。
	var mirror = Sim.new()
	mirror.submit_formation(0,Catalog.starter())
	mirror.submit_formation(1,Catalog.starter())
	mirror.build_tower(0)
	mirror.build_tower(1)
	ticks(mirror,2400)
	var hp: Array = [0.0,0.0]
	for unit in mirror.units:
		hp[unit.team] += float(unit.hp)
	check(is_equal_approx(mirror.bases[0],mirror.bases[1]) and mirror.kills[0]==mirror.kills[1] and is_equal_approx(hp[0],hp[1]) and mirror.minerals[0]==mirror.minerals[1],"mirror battle with structures has no side advantage")
	# AI：落后（对方上一波总价高于自己兵营）且未建塔时优先建塔。
	var ai = AI.new()
	check(ai.wants_tower(Catalog.starter(),[],600,0) and not ai.wants_tower([],[],600,0) and not ai.wants_tower(Catalog.starter(),[],600,1),"AI builds tower only when behind and allowed")
	check(not ai.wants_tower(Catalog.starter(),Catalog.starter(),2000,0),"AI skips tower when roster is not behind")

## 开局设置选项：推荐值即 rules 默认值，预设都在自定义范围内且能被步进到达。
func _setup_options() -> void:
	var rules: Dictionary = Catalog.rules()
	for field in rules.setup_options:
		var option: Dictionary = rules.setup_options[field]
		check(int(option.recommended)==int(rules[field]) and option.choices.has(option.recommended),"recommended %s equals default" % field)
		for choice in option.choices:
			check(choice>=option.min and choice<=option.max and int(choice-option.min) % int(option.step)==0,"%s choice %d reachable by custom step" % [field,int(choice)])
		var sim = Sim.new(1,{field:option.max})
		check(int(sim.rules[field])==int(option.max) and int(sim.journal.settings[field])==int(option.max),"%s override applied and journaled" % field)

## 护甲五类：无甲/特殊甲不吃穿甲加成；轻/重甲 = 攻击 + 对应加成 − 护甲点数；护盾是独立一层。
func _armor_and_shields() -> void:
	var sim = bare()
	var weapon := {"damage":10,"bonus":{"light":5,"heavy":7}}
	check(sim.raw_damage(weapon,"rotling")==10 and sim.raw_damage(weapon,"thor")==10,"none and special armor receive no bonus")
	check(sim.raw_damage(weapon,"rifle")==15 and sim.raw_damage(weapon,"marauder")==17,"light and heavy receive their own bonus only")
	var tank = sim.spawn_unit(1,"marauder",Vector2(600,200))
	check(sim.expected_damage(weapon,tank)==14 and sim.expected_damage({"damage":2},tank)==0.5 and sim.expected_damage({"damage":0},tank)==0,"armor points subtract; positive hits deal at least min_damage")
	var zealot = sim.spawn_unit(1,"vanguard",Vector2(600,260))
	check(zealot.shield==135 and zealot.hp==270,"protoss units spawn with full shields")
	check(Shield.absorb(sim,zealot,60)==0 and zealot.shield==75,"shield absorbs raw damage including bonus, ignoring hp armor")
	zealot.shield = 10
	check(Shield.absorb(sim,zealot,30)==17 and zealot.shield==0,"overflow passes through and is reduced by hp armor")
	check(Shield.absorb(sim,zealot,30)==27,"no shield: damage minus armor")
	# 战斗中：同一步多次命中按顺序先扣盾；脱战 7 秒后每秒回 7.5 盾，治疗不回盾。
	var fight = bare()
	fight.catalog.rifle.speed = 0
	fight.catalog.vanguard.speed = 0
	fight.catalog.vanguard.damage = 0
	var target = fight.spawn_unit(1,"vanguard",Vector2(620,200))
	var shooters: Array = []
	for i in range(3):
		shooters.append(fight.spawn_unit(0,"rifle",Vector2(500,180+i*20)))
	fight.step()
	check(target.shield==81 and target.hp==270,"three rifle hits in one step all land on shields")
	for shooter in shooters:
		fight.units.erase(shooter)
	var hit_tick: int = fight.tick
	ticks(fight,139)
	check(target.shield==81,"no shield regeneration before 7 seconds without damage")
	fight.step()
	check(is_equal_approx(target.shield,81.375) and fight.tick-hit_tick==140,"shield regenerates 7.5 per second after delay")
	target.hp = 200
	fight.spawn_unit(1,"medic",Vector2(560,200)).cooldown = 0
	var shield_before: float = target.shield
	fight.step()
	check(target.hp==212 and is_equal_approx(target.shield,shield_before+0.375),"medic heals hp only; shields regenerate on their own")
	# 再生：蟑螂脱战 3 秒后每秒回 20 生命。
	var regen = bare()
	var roach = regen.spawn_unit(0,"roach",Vector2(100,60))
	regen.catalog.roach.speed = 0
	roach.hp = 100
	roach.last_hit_tick = 0
	ticks(regen,59)
	check(roach.hp==100,"regen waits for delay")
	regen.step()
	check(roach.hp==101,"regen restores per_second after delay")
	var kills = bare()
	kills.catalog.rifle.speed = 0
	var brittle = kills.spawn_unit(1,"stalker",Vector2(620,200))
	brittle.shield = 0
	brittle.hp = 10
	kills.spawn_unit(0,"rifle",Vector2(500,200))
	kills.step()
	check(not kills.units.has(brittle) and kills.kills[0]==1,"damage through broken shields can kill")

## 数据完整性：四个种族、合法护甲、预留兵种标注清楚、每族都有对空与反重甲手段、开局阵容合法。
func _roster_data() -> void:
	var units: Dictionary = Catalog.units()
	units.erase("dummy")
	var races: Dictionary = Catalog.races()
	check(races.keys()==Catalog.RACES,"four races in fixed order")
	var counts: Dictionary = {}
	for kind in units:
		var stats: Dictionary = units[kind]
		var structure: bool = bool(stats.get("structure",false))
		check(["none","light","heavy","special"].has(stats.get("armor_type","")) and stats.has("armor"),kind+" has valid armor type and points")
		check(stats.get("armor_type")!="none" or float(stats.armor)==0,kind+" none armor has zero armor points")
		if structure:
			check(stats.race=="neutral","structure %s is race neutral" % kind)
			continue
		check(Catalog.RACES.has(stats.get("race","")) and ["ready","stub"].has(stats.get("status","")),kind+" has race and status")
		check(stats.status=="ready" or not stats.get("pending",[]).is_empty(),kind+" stub lists pending skills")
		check(stats.has("sc2") and stats.has("role") and stats.has("counter") and stats.has("layer") and stats.has("target_layers"),kind+" has reference, descriptions and layers")
		for prereq in stats.get("requires",[]):
			check(units.has(prereq) and units[prereq].race==stats.race,"%s prerequisite %s is same race" % [kind,prereq])
		counts[stats.race] = int(counts.get(stats.race,0)) + 1
	for race in Catalog.RACES:
		var ready: Array = Catalog.race_units(units,race)
		check(int(counts.get(race,0))>=10 and ready.size()>=5,race+" has full roster and at least five ready units")
		check(ready.any(func(k): return units[k].target_layers.has("air") and float(units[k].damage)>0),race+" has ready anti-air")
		check(ready.any(func(k): return float(units[k].get("bonus",{}).get("heavy",0))>0 or units[k].get("skills",{}).has("weapon_switch") or float(units[k].get("armor",0))>=6 or units[k].get("armor_type")=="special"),race+" has a tool against heavy armor")
		var sim = bare(1,{"races":[race,race]})
		check(sim.submit_formation(0,Catalog.starter(race))=="" and sim.minerals[0]>=0,race+" starter is valid and affordable")
	for kind in ["guard","breaker","sniper"]:
		check(not units.has(kind),"retired id %s removed" % kind)
	check(units.vanguard.name=="先锋" and units.vanguard.race=="protoss" and units.swarm.race=="blight" and units.piercer.race=="zerg" and units.colossus.race=="protoss","unit reassignment follows decisions")

## 种族：整局固定、只能买本族已实装兵种；电脑只选本族兵种；每个种族镜像对局对称。
func _races() -> void:
	var sim = bare()
	check(sim.races==["terran","terran"] and sim.buy(0,"zergling",0)=="不属于本方种族","default terran rejects zerg units")
	var zerg = bare(1,{"races":["zerg","protoss"]})
	check(zerg.buy(0,"zergling",0)=="" and zerg.buy(0,"baneling",1)=="该兵种尚未实装" and zerg.buy(1,"vanguard",0)=="" and zerg.buy(1,"zergling",1)!="","each side validated against its own race")
	check(zerg.journal.settings.races==["zerg","protoss"],"races are journaled for replay")
	for race in Catalog.RACES:
		var ai = AI.new(5,race)
		var plan: Array = ai.choose(Catalog.starter("terran"),3000)
		var check_sim = bare(1,{"races":[race,race]})
		check(not plan.is_empty() and check_sim.validate_formation(plan,3000,0)=="","AI %s buys only ready units of its race" % race)
		var mirror = bare(3,{"races":[race,race]})
		mirror.submit_formation(0,Catalog.starter(race))
		mirror.submit_formation(1,Catalog.starter(race))
		ticks(mirror,1600)
		var hp: Array = [0.0,0.0]
		for unit in mirror.units:
			hp[unit.team] += float(unit.hp) + float(unit.shield)
		check(is_equal_approx(mirror.bases[0],mirror.bases[1]) and mirror.kills[0]==mirror.kills[1] and is_equal_approx(hp[0],hp[1]),race+" mirror battle has no side advantage")
	var ai = AI.new(1,"protoss")
	check(ai.counter_for("liberator")!="" and Catalog.units()[ai.counter_for("liberator")].target_layers.has("air"),"AI counter picks a unit that can hit air")
	check(AI.new(1,"terran").counter_for("immortal")!="","AI finds counters across races")
	check(bare(1,{"races":["martian","zerg"]}).races==["terran","zerg"],"unknown race falls back to terran")
	# 首次交战前看不到对方种族与上一波阵容；首次受伤后双方同时公开，之后保持公开。
	var hidden = bare(2,{"races":["zerg","blight"]})
	hidden.submit_formation(0,Catalog.starter("zerg"))
	hidden.submit_formation(1,Catalog.starter("blight"))
	ticks(hidden,int(hidden.wave_ticks())+1)
	var before: Dictionary = hidden.get_snapshot(0)
	check(hidden.wave==1 and not hidden.revealed and hidden.last_formations[1].size()==8,"first wave spawned before any engagement")
	check(before.races==["zerg",""] and before.last_formations[1].is_empty() and before.last_formations[0].size()==7,"snapshot hides enemy race and last wave before reveal")
	check(hidden.visible_enemy_formation(1).is_empty() and hidden.get_snapshot(1).races==["","blight"],"computer side is equally blind before reveal")
	var reveal_events: Array = []
	var guard := 0
	while not hidden.revealed and guard < 2000:
		for event in hidden.step():
			if event.type=="revealed":
				reveal_events.append(event)
		guard += 1
	var after: Dictionary = hidden.get_snapshot(0)
	check(hidden.revealed and reveal_events.size()==1 and hidden.revealed_tick==hidden.tick,"first hit reveals both races once")
	check(after.races==["zerg","blight"] and after.last_formations[1].size()==8 and hidden.visible_enemy_formation(1).size()==7,"after reveal both sides see races and last waves")
	var quiet = bare(2)
	ticks(quiet,200)
	check(not quiet.revealed,"no fighting keeps races hidden")

## 大和舰：激光连射按目标层换武器；大和炮引导 2 秒不动、不开火，锁定目标后必中，目标先死则不耗冷却。
func _battlecruisers() -> void:
	var stats: Dictionary = Catalog.units().battlecruiser
	check(stats.status=="ready" and stats.race=="terran" and stats.layer=="air" and stats.armor_type=="special" and int(stats.armor)==9,"battlecruiser is a ready terran special-armor air unit")
	var shop = bare()
	check(stats.requires==["liberator"] and shop.buy(0,"battlecruiser",0)=="","prerequisite recorded but not enforced")
	check(AI.new(1,"terran").pool.has("battlecruiser") and Catalog.race_units(Catalog.units(),"terran").has("battlecruiser"),"battlecruiser is in terran shop and AI pool")
	# 激光：关闭大和炮单测普通武器。对地 24/发、对空 15/发，0.16 秒间隔在 20 Hz 下量化为每 4 步一发。
	var lasers = bare()
	lasers.catalog.battlecruiser.skills.yamato.min_target_hp = 1000000
	var ship = lasers.spawn_unit(0,"battlecruiser",Vector2(500,200))
	var walker = lasers.spawn_unit(1,"dummy",Vector2(620,200))
	walker.hp = 10000
	ticks(lasers,9)
	check(ship.get("weapon_index",0)==0 and is_equal_approx(walker.hp,10000-24*3),"ground laser fires every 4 ticks for 24")
	var air = bare()
	air.catalog.battlecruiser.skills.yamato.min_target_hp = 1000000
	var hunter = air.spawn_unit(0,"battlecruiser",Vector2(500,200))
	var viking = air.spawn_unit(1,"viking",Vector2(620,200))
	viking.hp = 10000
	ticks(air,1)
	check(hunter.weapon_index==1 and is_equal_approx(viking.hp,10000-15),"air laser hits air for 15 without heavy bonus")
	check(is_equal_approx(hunter.hp,1485) or is_equal_approx(hunter.hp,1485-51),"viking bonus does not apply to special armor (60 - 9)")
	# 大和炮：250 距离（激光射程外）第 1 步开始引导，之后 40 步（2 秒）原地不动、无普通攻击，第 41 步命中 720。
	var cannon = bare()
	var bc = cannon.spawn_unit(0,"battlecruiser",Vector2(500,200))
	var big = cannon.spawn_unit(1,"dummy",Vector2(750,200))
	big.hp = 10000
	var charged := false
	var fired := 0
	var attacks := 0
	for i in range(41):
		for event in cannon.step():
			charged = charged or event.type=="yamato_charge"
			fired += 1 if event.type=="yamato" else 0
			attacks += 1 if event.type=="attack" and event.team==0 else 0
		if i < 40:
			check(bc.pos==Vector2(500,200) and fired==0,"battlecruiser holds still while channeling %d" % i)
	check(charged and fired==1 and attacks==0 and is_equal_approx(big.hp,10000-720),"yamato fires once after 2 s for 720")
	check(int(bc.yamato_ready_tick)==cannon.tick+1420 and not bc.has("yamato_target"),"yamato cooldown 71 s starts on firing")
	ticks(cannon,200)
	check(big.hp < 10000-720 and bc.pos!=Vector2(500,200) and not bc.has("yamato_target"),"lasers and movement resume during cooldown")
	# 护盾：720 先打护盾 270，溢出 450 再减护甲 3。
	var shielded = bare()
	shielded.spawn_unit(0,"battlecruiser",Vector2(500,200))
	var immortal = shielded.spawn_unit(1,"immortal",Vector2(750,200))
	ticks(shielded,41)
	check(is_equal_approx(immortal.shield,0) and is_equal_approx(immortal.hp,540-447),"yamato drains shields then hits hp minus armor")
	# 目标在引导中死亡：取消，不耗冷却。
	var cancel = bare()
	var caster = cancel.spawn_unit(0,"battlecruiser",Vector2(500,200))
	var doomed = cancel.spawn_unit(1,"dummy",Vector2(750,200))
	ticks(cancel,5)
	check(caster.has("yamato_target"),"channel started")
	cancel.units.erase(doomed)
	ticks(cancel,1)
	check(not caster.has("yamato_target") and int(caster.get("yamato_ready_tick",0))==0,"target death cancels channel without cooldown")
	# 低血目标不值得开炮：跳虫 95 生命低于 300，直接用激光。
	var small = bare(42,{"races":["terran","zerg"]})
	var picky = small.spawn_unit(0,"battlecruiser",Vector2(500,200))
	small.spawn_unit(1,"zergling",Vector2(600,200))
	ticks(small,2)
	check(not picky.has("yamato_target"),"yamato ignores targets below min_target_hp")
	# 选目标：优先单位而不是结构体，单位间取生命+护盾最高者。
	var choice = Sim.new(1)
	var picker = choice.spawn_unit(0,"battlecruiser",Vector2(900,200))
	var weak = choice.spawn_unit(1,"dummy",Vector2(1000,170))
	var strong = choice.spawn_unit(1,"dummy",Vector2(1000,230))
	strong.hp = 900
	ticks(choice,1)
	check(int(picker.get("yamato_target",0))==strong.id and weak.id!=strong.id,"yamato prefers the toughest unit over structures")
	# 镜像对称。
	var mirror = bare()
	mirror.spawn_unit(0,"battlecruiser",Vector2(430,200))
	mirror.spawn_unit(1,"battlecruiser",Vector2(770,200))
	ticks(mirror,600)
	check(mirror.units.size()==2 and is_equal_approx(mirror.units[0].hp,mirror.units[1].hp),"battlecruiser duel is symmetric")
	_battlecruiser_visual()

## 按 main.gd 的顺序驱动大和舰精灵动画：步前快照/观察 → step → 观察 → 事件 → 观察；画面时钟每步 0.05 秒。
func _visual_ticks(sim, visual, count: int) -> Array:
	var seen: Array = []
	for i in range(count):
		var before: Dictionary = {}
		for unit in sim.units:
			if unit.kind == "battlecruiser":
				before[unit.id] = unit.duplicate()
		visual.observe(sim.units)
		var events: Array = sim.step()
		visual.observe(sim.units, false)
		for event in events:
			visual.event(event, before, sim.units, true)
			seen.append(event)
		visual.observe(sim.units)
		visual.update(0.05)
	return seen

func _battlecruiser_visual() -> void:
	var Visual = load("res://scripts/battlecruiser_visual.gd")
	var visual = Visual.new()
	var sim = bare()
	var ship = sim.spawn_unit(0,"battlecruiser",Vector2(500,200))
	var target = sim.spawn_unit(1,"dummy",Vector2(750,200))
	target.hp = 10000
	_visual_ticks(sim,visual,2)
	var pose: Dictionary = visual.poses[ship.id]
	check(pose.state=="yamato" and visual.frame_index("yamato",visual.clock-float(pose.since))==0 and not pose.left,"visual: channel shows yamato charge frame, facing right")
	_visual_ticks(sim,visual,28)
	check(visual.frame_index("yamato",visual.clock-float(pose.since))==1,"visual: after 1.2 s the muzzle shows the lock frame")
	var events: Array = _visual_ticks(sim,visual,11)
	var cannon: Array = events.filter(func(e): return e.type=="yamato")
	check(cannon.size()==1 and cannon[0].muzzle=="round_muzzle" and visual.frame_index("yamato",visual.clock-float(pose.since))==2,"visual: yamato beam leaves the round muzzle on the fire frame")
	_visual_ticks(sim,visual,10)
	check(pose.state=="yamato" and visual.frame_index("yamato",visual.clock-float(pose.since))==3,"visual: recover frame after the beam")
	var lasers: Array = _visual_ticks(sim,visual,60).filter(func(e): return e.type=="attack" and e.team==0)
	var muzzles: Dictionary = {}
	for shot in lasers:
		muzzles[shot.muzzle] = true
	check(lasers.size() > 2 and muzzles.has("wing_barrel") and muzzles.has("prow_low") and not muzzles.has("round_muzzle"),"visual: ground lasers alternate wing barrel and lower prow gun")
	check(pose.state=="fire","visual: firing lasers uses the move-fire sheet")
	var offset: Vector2 = visual.muzzle_offset("round_muzzle",false,80.0)
	check(offset.x > 0 and visual.muzzle_offset("round_muzzle",true,80.0)==Vector2(-offset.x,offset.y),"visual: muzzle offsets mirror for left-facing ships")
	var enemy = sim.spawn_unit(1,"battlecruiser",Vector2(900,200))
	_visual_ticks(sim,visual,1)
	check(visual.poses[enemy.id].left,"visual: right-side ship faces left")
	ship.hp = 0
	_visual_ticks(sim,visual,1)
	check(visual.corpses.size()==1 and not visual.poses.has(ship.id) and not visual.corpses[0].left,"visual: death leaves a wreck with the last facing")
	_visual_ticks(sim,visual,29)
	check(visual.corpses.is_empty(),"visual: wreck disappears after 1.4 s")
	visual.reset()
	var air = bare()
	air.catalog.battlecruiser.skills.yamato.min_target_hp = 1000000
	var hunter = air.spawn_unit(0,"battlecruiser",Vector2(500,200))
	air.spawn_unit(1,"viking",Vector2(620,200)).hp = 10000
	var air_shots: Array = _visual_ticks(air,visual,20).filter(func(e): return e.type=="attack" and e.team==0)
	check(hunter.weapon_index==1 and air_shots.size() > 0 and air_shots.all(func(e): return e.muzzle=="prow_high"),"visual: air lasers leave the upper prow gun")
