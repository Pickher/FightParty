# 中文导读：自动验证战斗规则的开发脚本，不是玩家游戏入口。
# 运行命令见 README；不需要打开游戏窗口，也不会修改玩家存档。
# 测试中不少数值固定对应 v0.1 的基线；有意改平衡后，应检查预期而非直接删除失败测试。
extends SceneTree
const Sim = preload("res://scripts/battle_sim.gd")
const LineAttack = preload("res://scripts/skills/line_attack.gd")
const AI = preload("res://scripts/commander_ai.gd")
const Catalog = preload("res://scripts/catalog.gd")
var failures := 0
var checks := 0

## 记录一项检查；失败时打印原因并增加计数，最后用非零退出码提示失败。
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

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

## SceneTree 脚本启动时运行测试集，覆盖校验、波次、残兵、胜负、AI 和性能。
func _initialize() -> void:
	_targeting()
	_medics()
	_siege()
	_siege_scanning()
	_piercers()
	_colossi_and_skills()
	_marauders()
	_stimulant_and_slow()
	var sim = Sim.new()
	check(sim.budget()==600 and sim.budget(7)==1200 and sim.budget(99)==1200,"budget curve")
	check(sim.submit_formation(0,formation("guard",7))!="","reject over budget")
	check(sim.submit_formation(0,[{"kind":"guard","cell":0},{"kind":"rifle","cell":0}])!="","reject duplicate cell")
	check(sim.submit_formation(0,[{"kind":"guard","cell":24}])!="","reject out of range")
	check(sim.submit_formation(0,[{"kind":"guard","cell":1.5}])!="","reject fractional cell")
	check(sim.submit_formation(0,[{"kind":"unknown","cell":0}])!="","reject unknown unit")
	check(sim.submit_formation(0,[])=="","allow empty formation")
	for team in range(2):
		check(sim.submit_formation(team,Catalog.starter())=="","same validator team %d" % team)
	check(not sim.get_snapshot(0).has("formations"),"snapshot hides pending opponent")
	ticks(sim,599)
	check(sim.units.is_empty() and sim.wave==0,"no early spawn")
	sim.step()
	check(sim.wave==1 and sim.units.size()==14,"simultaneous first wave")
	check(sim.budget()==700,"next budget follows wave")
	var id: int = sim.units[0].id
	sim.submit_formation(0,[])
	check(sim.units[0].id==id and sim.last_formations[0].size()==7,"editing leaves battlefield intact")
	check(sim.journal.waves[0].budget==600,"journal captures wave budget")
	# 寿命边界：把出生时间放到过去，精确检查 90 秒前一刻和刚到 90 秒的区别。
	var lifetime = Sim.new()
	var survivor: Dictionary = lifetime.spawn_unit(0,"guard",Vector2(100,100))
	survivor.born = -1798
	lifetime.step()
	check(lifetime.units.size()==1,"survivor retained before expiry")
	lifetime.step()
	check(lifetime.units.is_empty(),"expiry exactly 90 seconds")
	var retained = Sim.new()
	retained.spawn_unit(0,"guard",Vector2(500,100))
	retained.tick=599
	retained.submit_formation(0,formation("rifle",1))
	retained.step()
	check(retained.units.size()==2 and retained.units[0].id==1,"next wave retains survivors")
	# 同时摧毁基地必须判平，不能因为某队先被处理就先判负。
	var draw = Sim.new()
	draw.bases=[1.0,1.0]
	draw.spawn_unit(0,"rifle",Vector2(1150,200))
	draw.spawn_unit(1,"rifle",Vector2(50,200))
	draw.step()
	check(draw.finished and draw.winner==-1,"simultaneous base destruction draws")
	var mutual = Sim.new()
	mutual.spawn_unit(0,"sniper",Vector2(550,200))
	mutual.spawn_unit(1,"sniper",Vector2(650,200))
	mutual.step()
	check(mutual.units.is_empty() and mutual.kills==[1,1],"simultaneous lethal attacks both fire")
	var empty = Sim.new()
	ticks(empty,9600)
	check(empty.finished and empty.winner==-1,"empty match times out as draw")
	var timed = Sim.new()
	timed.tick=9599
	timed.bases=[2500.0,2000.0]
	timed.step()
	check(timed.winner==0,"timeout compares base hp")
	var commander = AI.new()
	for round_number in range(1,16):
		var b: int = sim.budget(round_number)
		check(sim.validate_formation(commander.choose(Catalog.starter(),b),b)=="","AI obeys budget and grid %d" % round_number)
	# 镜像公平测试：相同配置放在两侧，击杀数与基地状态应保持一致。
	var mirror = Sim.new()
	mirror.submit_formation(0,Catalog.starter())
	mirror.submit_formation(1,Catalog.starter())
	ticks(mirror,2400)
	check(is_equal_approx(mirror.bases[0],mirror.bases[1]) and mirror.kills[0]==mirror.kills[1],"mirror battle has no side advantage")
	var replay = Sim.new()
	replay.submit_formation(0,Catalog.starter())
	replay.submit_formation(1,Catalog.starter())
	ticks(replay,2400)
	check(replay.get_snapshot()==mirror.get_snapshot(),"same inputs reproduce same simulation")
	_counter("breaker",4,"guard",5,"anti-heavy")
	_counter("rifle",4,"swarm",6,"rifle vs light")
	_counter("mortar",2,"swarm",6,"splash vs swarm")
	_counter("swarm",6,"sniper",2,"swarm vs isolated sniper")
	_counter("mortar",2,"sniper",2,"siege outranges sniper")
	# 压力测试使用 200 个高血量单位，避免测试过程中快速减员；这个测试不测画面 FPS。
	var stress = Sim.new()
	for team in range(2):
		for i in range(100):
			var u: Dictionary = stress.spawn_unit(team,"guard",Vector2(400+team*400+(i%10)*4,30+(i/10)*34))
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
		var sim = Sim.new()
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
		var boundary = Sim.new()
		var observer = boundary.spawn_unit(0, kind, Vector2(500,200))
		var radius: float = float(boundary.catalog[kind].range) * 1.5
		var enemy = boundary.spawn_unit(1, "guard", Vector2(500+radius,200))
		boundary._build_buckets()
		check(boundary._target(observer).get("id",0)==enemy.id,kind+" discovers at 150% range")
		enemy.pos.x += 0.01
		boundary._build_buckets()
		check(boundary._target(observer).is_empty(),kind+" ignores beyond discovery range")
	var sim = Sim.new()
	# 静止、高生命敌人用于隔离索敌行为，避免移动或死亡干扰测试。
	sim.catalog.guard.speed = 0
	var shooter = sim.spawn_unit(0,"rifle",Vector2(500,200))
	var first = sim.spawn_unit(1,"guard",Vector2(680,200))
	first.hp = 10000
	sim.step()
	check(shooter.pos.x>500 and shooter.locked_target_id==0,"pursuit moves without locking")
	var closer = sim.spawn_unit(1,"guard",Vector2(600,200))
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
	closer.born = sim.tick - int(sim.rules.unit_lifetime * sim.rules.tick_rate)
	sim.step()
	check(shooter.locked_target_id==0,"expired target releases lock")
	var special = Sim.new()
	special.catalog.guard.speed = 0
	special.catalog.mortar.speed = 0
	var sniper = special.spawn_unit(0,"sniper",Vector2(500,200))
	special.spawn_unit(1,"guard",Vector2(750,200))
	special.step()
	var weak = special.spawn_unit(1,"mortar",Vector2(800,200))
	special._build_buckets()
	check(special._target(sniper).get("id",0)==weak.id and sniper.locked_target_id==0,"sniper reselects fragile target during pursuit outside attack range")
	weak.pos = Vector2(700,200)
	weak.hp = 10000
	special.step()
	check(sniper.locked_target_id==weak.id,"sniper locks on firing")
	special.spawn_unit(1,"sniper",Vector2(650,200))
	special.step()
	check(sniper.locked_target_id==weak.id,"special priority cannot override valid firing lock")

## 治疗、冷却、上限、阵营与前排安全站位，双方方向均需一致。
func _medics() -> void:
	for team in range(2):
		var sim = Sim.new()
		sim.catalog.guard.speed = 0
		var direction: float = 1 if team == 0 else -1
		var medic = sim.spawn_unit(team,"medic",Vector2(600,200))
		var ally = sim.spawn_unit(team,"guard",Vector2(600+direction*100,200))
		ally.hp = 200
		var enemy = sim.spawn_unit(1-team,"guard",Vector2(600+direction*60,200))
		enemy.hp = 100
		var events: Array = sim.step()
		check(ally.hp==212 and enemy.hp==100 and medic.hp==100,"medic only heals injured ally %d" % team)
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
	var priority = Sim.new()
	priority.catalog.guard.speed=0
	priority.catalog.rifle.speed=0
	var healer=priority.spawn_unit(0,"medic",Vector2(500,200))
	var tank=priority.spawn_unit(0,"guard",Vector2(600,200))
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
	var lethal=Sim.new()
	var victim=lethal.spawn_unit(0,"rifle",Vector2(600,200))
	victim.hp=119
	lethal.spawn_unit(0,"medic",Vector2(500,180))
	lethal.spawn_unit(0,"medic",Vector2(500,220))
	lethal.spawn_unit(1,"sniper",Vector2(700,200))
	lethal.step()
	check(not lethal.units.has(victim),"overhealing cannot act as a shield")
	var ai=AI.new()
	var formation_with_medic: Array=ai.choose([],700)
	check(formation_with_medic.any(func(s): return s.kind=="medic" and s.cell==0),"AI buys medic in rear cell")
	check(lethal.validate_formation(formation_with_medic,700)=="","AI medic formation within budget")

## 架设与收起按模拟时间推进，轻重甲伤害、基地攻击与锁定行为共用规则。
func _siege() -> void:
	for team in range(2):
		var sim=Sim.new()
		sim.catalog.guard.speed=0
		sim.catalog.rifle.speed=0
		sim.catalog.guard.damage=0
		sim.catalog.rifle.damage=0
		var forward: float = 1 if team==0 else -1
		var gun=sim.spawn_unit(team,"mortar",Vector2(600,200))
		var heavy=sim.spawn_unit(1-team,"guard",Vector2(600+forward*280,200))
		var light=sim.spawn_unit(1-team,"rifle",Vector2(600+forward*290,220))
		var friend=sim.spawn_unit(team,"guard",Vector2(600+forward*285,210))
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
		check(gun.siege_state=="deployed" and heavy.hp==865 and light.hp==892,"first deployed shot damages heavy and light armor")
		check(friend.hp==480 and gun.locked_target_id==heavy.id,"splash ignores friends and locks main target")
		ticks(sim,55)
		check(heavy.hp==865 and gun.pos==initial,"deployed cooldown blocks early shot and movement")
		sim.step()
		check(heavy.hp==730,"deployed second shot respects interval")
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
		check(heavy.hp==before-135,"new setup fires when complete")
		# 已架设时目标死亡，只要另一个目标仍在射程内就直接转火。
		sim.units.erase(heavy)
		light.pos=gun.pos+Vector2(forward*270,0)
		gun.cooldown=0
		sim.step()
		check(gun.siege_state=="deployed" and gun.locked_target_id==light.id,"deployed gun reacquires without unnecessary setup")
	var base=Sim.new()
	var siege=base.spawn_unit(0,"mortar",Vector2(900,200))
	base.step()
	ticks(base,29)
	check(base.bases[1]==3000,"base attack also requires setup")
	base.step()
	check(base.bases[1]==2910 and siege.siege_state=="deployed","deployed artillery attacks base")
	# 脆弱炮兵在完成架设前仍可被射程内狙击手击杀。
	var ambush=Sim.new()
	var fragile=ambush.spawn_unit(0,"mortar",Vector2(500,200))
	ambush.spawn_unit(1,"sniper",Vector2(700,200))
	ambush.step()
	check(not ambush.units.has(fragile),"sniper ambush kills artillery before setup")

## 防止短暂目标导致反复架设：确认同一敌人，以及外圈接近方向。
func _siege_scanning() -> void:
	var scan=Sim.new()
	scan.catalog.guard.speed=0
	var gun=scan.spawn_unit(0,"mortar",Vector2(500,200))
	var first=scan.spawn_unit(1,"guard",Vector2(770,200))
	scan.spawn_unit(0,"guard",Vector2(510,200))
	scan.step()
	check(gun.siege_state=="mobile" and gun.locked_target_id==0,"single transient enemy only observed")
	scan.units.erase(first)
	var second=scan.spawn_unit(1,"guard",Vector2(775,200))
	ticks(scan,10)
	check(gun.siege_state=="mobile","different ID on second scan cannot confirm first enemy")
	scan.units.erase(second)
	ticks(scan,10)
	scan.spawn_unit(1,"guard",Vector2(780,200))
	ticks(scan,10)
	check(gun.siege_state=="mobile","empty scan clears old observations")
	ticks(scan,10)
	check(gun.siege_state=="deploying","same enemy across consecutive scans confirms setup")
	var crowd=Sim.new()
	crowd.catalog.guard.speed=0
	var artillery=crowd.spawn_unit(0,"mortar",Vector2(500,200))
	crowd.spawn_unit(1,"guard",Vector2(770,180))
	crowd.spawn_unit(1,"guard",Vector2(770,220))
	crowd.step()
	check(artillery.siege_state=="mobile","exactly X enemies still need confirmation")
	crowd.spawn_unit(1,"guard",Vector2(780,200))
	crowd.step()
	check(artillery.siege_state=="deploying","more than X enemies deploy immediately between scans")
	# 靠近判断采用上一模拟步的位移；双方镜像均须保持架设并最终开火。
	for team in range(2):
		var sim=Sim.new()
		var direction: float=1 if team==0 else -1
		var cannon=sim.spawn_unit(team,"mortar",Vector2(600,200))
		cannon.siege_state="deployed"
		cannon.cooldown=10
		var victim=sim.spawn_unit(1-team,"guard",Vector2(600+direction*270,200))
		victim.hp=1
		sim.spawn_unit(team,"sniper",Vector2(600+direction*100,200))
		var incoming=sim.spawn_unit(1-team,"guard",Vector2(600+direction*350,240))
		sim.step()
		check(not sim.units.has(victim),"ally kills original target")
		sim.step()
		check(cannon.siege_state=="deployed" and cannon.pos==Vector2(600,200),"approaching outer enemy prevents packing after ally kill")
		cannon.cooldown=0
		ticks(sim,35)
		check(cannon.siege_state=="deployed" and cannon.locked_target_id==incoming.id,"held artillery fires when next enemy reaches range")
	# 120% 边界包含接近敌人；静止、远离、切向及超出边界不算接近。
	for scenario in ["approaching","stationary","away","tangent","outside"]:
		var sim=Sim.new()
		sim.catalog.guard.speed=0
		var cannon=sim.spawn_unit(0,"mortar",Vector2(500,200))
		cannon.siege_state="deployed"
		var x: float=860.01 if scenario=="outside" else 860.0
		var enemy=sim.spawn_unit(1,"guard",Vector2(x,200))
		enemy.prev=enemy.pos
		if scenario=="approaching" or scenario=="outside": enemy.prev.x+=1
		elif scenario=="away": enemy.prev.x-=1
		elif scenario=="tangent": enemy.prev.y-=1
		sim.step()
		check(cannon.siege_state==("deployed" if scenario=="approaching" else "packing"),"outer approach check: "+scenario)
	# 架设中也保持相同的外圈判定，避免刚启动就因原目标死亡取消。
	var setup=Sim.new()
	var cannon=setup.spawn_unit(0,"mortar",Vector2(500,200))
	cannon.siege_state="deploying"
	cannon.siege_until_tick=2
	var enemy=setup.spawn_unit(1,"guard",Vector2(840,200))
	enemy.prev.x+=1
	setup.step()
	check(cannon.siege_state=="deploying","approaching enemy preserves ongoing setup")
	setup.step()
	check(cannon.siege_state=="deployed" and cannon.locked_target_id==0,"setup completes while waiting for approaching enemy")

## 地刺沿开火方向传播到固定射程，每波对每个敌人最多命中一次。
func _piercers() -> void:
	for team in range(2):
		var sim=Sim.new()
		sim.catalog.guard.speed=0
		sim.catalog.guard.damage=0
		var forward: float=1 if team==0 else -1
		var gun=sim.spawn_unit(team,"piercer",Vector2(600,200))
		gun.siege_state="deployed"
		var near=sim.spawn_unit(1-team,"guard",Vector2(600+forward*80,200))
		var far=sim.spawn_unit(1-team,"guard",Vector2(600+forward*200,200))
		var edge=sim.spawn_unit(1-team,"guard",Vector2(600+forward*260,200))
		var beyond=sim.spawn_unit(1-team,"guard",Vector2(600+forward*261,200))
		var width_edge=sim.spawn_unit(1-team,"guard",Vector2(600+forward*130,214))
		var outside=sim.spawn_unit(1-team,"guard",Vector2(600+forward*150,214.01))
		var friend=sim.spawn_unit(team,"guard",Vector2(600+forward*100,200))
		for victim in [near,far,edge,beyond,width_edge,outside,friend]:victim.hp=1000
		sim.step()
		check(sim.attack_waves.size()==1 and near.hp==1000 and far.hp==1000,"piercer launches without instant damage")
		check(gun.locked_target_id==near.id and sim.attack_waves[0].length==260,"near target sets direction, not line length")
		var snapshot: Dictionary=sim.get_snapshot()
		snapshot.attack_waves[0].distance=999
		check(sim.attack_waves[0].distance==0,"wave snapshot is independent")
		var behind=sim.spawn_unit(1-team,"guard",Vector2(600-forward*10,200))
		behind.hp=1000
		ticks(sim,6)
		check(near.hp==1000,"near enemy unharmed before wave arrives")
		sim.step()
		check(near.hp==932.5 and far.hp==1000,"wave reaches near enemy before far enemy")
		# 发射者死亡和原目标死亡都不能取消已经发出的地刺。
		sim.units.erase(gun)
		sim.units.erase(near)
		ticks(sim,8)
		check(far.hp==1000,"far enemy unharmed until travel time elapses")
		sim.step()
		check(far.hp==932.5,"wave survives shooter and original target removal")
		ticks(sim,4)
		check(edge.hp==932.5 and beyond.hp==1000,"fixed range includes endpoint and excludes beyond it")
		check(width_edge.hp==932.5 and outside.hp==1000,"line half-width boundary")
		check(friend.hp==1000 and behind.hp==1000,"no friendly fire or damage behind origin")
		check(far.hp==932.5 and sim.attack_waves.is_empty(),"one hit per victim and completed wave cleaned up")
	var dodge=Sim.new()
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
	check(target.hp==120 and far.hp==75,"wave does not home; target can dodge while rear enemy is hit")
	check(late.hp==120,"entering behind passed wave causes no retroactive damage")
	# 本步横穿路径的敌人必须在波前到达时位于线宽内，不能只检查两个端点。
	var wave={"origin":Vector2.ZERO,"direction":Vector2.RIGHT,"distance":0.0,"half_width":14.0}
	check(LineAttack.crosses(wave,Vector2(10,30),Vector2(10,-30),20),"swept hit catches crossing during tick")
	check(not LineAttack.crosses(wave,Vector2(10,40),Vector2(10,20),20),"swept hit excludes missed path")
	var setup=Sim.new()
	setup.catalog.guard.speed=0
	setup.catalog.guard.damage=0
	var burrower=setup.spawn_unit(0,"piercer",Vector2(500,200))
	var enemy=setup.spawn_unit(1,"guard",Vector2(700,200))
	setup.step()
	check(burrower.siege_state=="mobile" and setup.attack_waves.is_empty(),"burrow uses same two-scan confirmation")
	ticks(setup,10)
	check(burrower.siege_state=="deploying","confirmed piercer starts burrowing")
	ticks(setup,19)
	check(setup.attack_waves.is_empty() and burrower.pos==Vector2(500,200),"burrowing forbids early attack and movement")
	setup.step()
	check(burrower.siege_state=="deployed" and setup.attack_waves.size()==1,"burrowed piercer launches attack")
	var sniper=setup.spawn_unit(1,"sniper",Vector2(650,200))
	setup.step()
	check(sniper.locked_target_id==burrower.id and burrower.hp<180,"burrowed unit remains visible and attackable")
	setup.units.erase(enemy)
	setup.units.erase(sniper)
	setup.step()
	check(burrower.siege_state=="packing","piercer emerges when no enemies remain")
	ticks(setup,14)
	check(burrower.pos==Vector2(500,200) and burrower.siege_state=="packing","cannot move during emergence")
	setup.step()
	setup.step()
	check(burrower.siege_state=="mobile" and burrower.pos.x>500,"movement resumes only after emerging")
	var base=Sim.new()
	var attacker=base.spawn_unit(0,"piercer",Vector2(890,200))
	attacker.siege_state="deployed"
	base.step()
	ticks(base,19)
	check(base.bases[1]==3000,"base waits for wave to reach its edge")
	base.step()
	check(base.bases[1]==2955,"base takes delayed wave damage at maximum range")
	var multi=Sim.new()
	multi.catalog.guard.speed=0
	multi.catalog.guard.damage=0
	var source=multi.spawn_unit(0,"piercer",Vector2(500,200))
	var victim=multi.spawn_unit(1,"guard",Vector2(580,200))
	LineAttack.launch(multi,source,victim.pos)
	LineAttack.launch(multi,source,victim.pos)
	multi.units.erase(source)
	ticks(multi,20)
	check(victim.hp==345,"separate waves each hit once without duplicate damage")

## 巨像横向双束传播与可配置技能复用，不保证必中。
func _colossi_and_skills() -> void:
	for team in range(2):
		var sim=Sim.new()
		for kind in ["rifle","guard"]:
			sim.catalog[kind].speed=0
			sim.catalog[kind].damage=0
		var forward: float=1 if team==0 else -1
		var giant=sim.spawn_unit(team,"colossus",Vector2(600,200))
		var x: float=600+forward*240
		var center=sim.spawn_unit(1-team,"rifle",Vector2(x,200))
		var top=sim.spawn_unit(1-team,"rifle",Vector2(x,140))
		var bottom=sim.spawn_unit(1-team,"guard",Vector2(x,260))
		var width_edge=sim.spawn_unit(1-team,"guard",Vector2(x+forward*14,220))
		var off_line=sim.spawn_unit(1-team,"guard",Vector2(x+forward*14.01,240))
		var end=sim.spawn_unit(1-team,"guard",Vector2(x,290))
		var outside=sim.spawn_unit(1-team,"guard",Vector2(x,290.01))
		var friend=sim.spawn_unit(team,"guard",Vector2(x,240))
		for unit in [center,top,bottom,width_edge,off_line,end,outside,friend]:unit.hp=1000
		sim.step()
		check(sim.attack_waves.size()==2 and not giant.has("siege_state"),"colossus fires two waves without deployment")
		check(center.hp==1000 and giant.locked_target_id==center.id,"sweep delays damage and locks primary target")
		check(sim.attack_waves[0].direction==-sim.attack_waves[1].direction and sim.attack_waves[0].direction.dot(Vector2(forward,0))==0,"sweeps start at opposite sides perpendicular to aim")
		ticks(sim,4)
		check(top.hp==964 and bottom.hp==976 and center.hp==1000,"outer enemies receive first sweep before center")
		ticks(sim,5)
		check(center.hp==1000,"center unharmed before beam arrival")
		var events: Array=sim.step()
		var center_hits: Array=events.filter(func(e): return e.type=="attack_hit" and e.id==center.id)
		check(center_hits.size()==2 and center_hits[0].strike!=center_hits[1].strike and center.hp==928,"center receives two distinct 36 damage hits")
		ticks(sim,10)
		check(top.hp==928 and bottom.hp==952 and end.hp==952,"both beams cross entire fixed transverse segment")
		check(width_edge.hp==952 and off_line.hp==1000 and outside.hp==1000,"transverse width and length boundaries")
		check(friend.hp==1000 and sim.attack_waves.is_empty(),"sweeps ignore friendly units and expire")
		ticks(sim,27)
		check(sim.attack_waves.is_empty(),"double attack uses one shared attack cooldown")
		sim.step()
		check(sim.attack_waves.size()==2,"next cooldown launches exactly two waves")
	var dodge=Sim.new()
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
	var partial=Sim.new()
	partial.catalog.rifle.speed=0
	partial.catalog.rifle.damage=0
	var shooter=partial.spawn_unit(0,"colossus",Vector2(500,200))
	partial.spawn_unit(1,"rifle",Vector2(700,200))
	var side=partial.spawn_unit(1,"rifle",Vector2(700,140))
	partial.step()
	ticks(partial,4)
	check(side.hp==84,"first side hit deals one strike")
	side.pos.x+=50
	partial.units.erase(shooter)
	ticks(partial,16)
	check(side.hp==84,"side target can dodge the second strike")
	# 相同技能挂载到全新 ID，仍然可以三重直线攻击并保留部署要求。
	var reuse=Sim.new()
	reuse.catalog["borrowed"]=reuse.catalog.piercer.duplicate(true)
	reuse.catalog.borrowed.skills.multi_attack={"count":3}
	reuse.catalog.guard.speed=0
	reuse.catalog.guard.damage=0
	var custom=reuse.spawn_unit(0,"borrowed",Vector2(500,200))
	var victim=reuse.spawn_unit(1,"guard",Vector2(600,200))
	reuse.step()
	check(custom.siege_state=="mobile" and reuse.attack_waves.is_empty(),"copied deployment skill gates another unit ID")
	ticks(reuse,30)
	check(custom.siege_state=="deployed" and reuse.attack_waves.size()==3,"copied line and multi-attack skills compose")
	ticks(reuse,8)
	check(victim.hp==277.5,"three independent line hits apply to borrowed unit")
	# 普通单体攻击也能复用双击，不依赖波形攻击。
	var instant=Sim.new()
	instant.catalog["borrowed"]=instant.catalog.rifle.duplicate(true)
	instant.catalog.borrowed.skills={"multi_attack":{"count":2}}
	instant.catalog.rifle.speed=0
	instant.catalog.rifle.damage=0
	instant.spawn_unit(0,"borrowed",Vector2(500,200))
	var light=instant.spawn_unit(1,"rifle",Vector2(600,200))
	var instant_events: Array=instant.step()
	check(is_equal_approx(light.hp,69.6) and instant_events.filter(func(e): return e.type=="attack_hit" and e.team==0).size()==2,"ordinary weapon supports two separate strikes")
	var base=Sim.new()
	base.spawn_unit(0,"colossus",Vector2(920,200))
	base.step()
	ticks(base,7)
	check(base.bases[1]==3000,"base receives no instant beam damage")
	base.step()
	check(base.bases[1]==2952,"base receives both delayed beams")
	# 全局旋转后的横线仍垂直于发射方向，不固定在屏幕上下方向。
	var diagonal=Sim.new()
	var rotated=diagonal.spawn_unit(0,"colossus",Vector2(500,100))
	var goal=Vector2(700,250)
	LineAttack.launch(diagonal,rotated,goal)
	var direction: Vector2=(goal-rotated.pos).normalized()
	check(is_zero_approx(diagonal.attack_waves[0].direction.dot(direction)) and diagonal.attack_waves[0].origin.lerp(diagonal.attack_waves[1].origin,0.5).is_equal_approx(goal),"transverse sweep rotates around target with aim")

## 图片基础兵种：单体榴弹、普通索敌、重甲标签及四人预算。
func _marauders() -> void:
	var sim = Sim.new()
	sim.catalog.marauder.skills = {}
	check(sim.formation_cost(formation("marauder",4))==560 and sim.validate_formation(formation("marauder",4),600)=="", "four marauders fit screenshot budget")
	sim.catalog.rifle.speed = 0
	sim.catalog.rifle.damage = 0
	sim.catalog.guard.speed = 0
	var shooter = sim.spawn_unit(0,"marauder",Vector2(500,200))
	var light = sim.spawn_unit(1,"rifle",Vector2(640,200))
	var heavy = sim.spawn_unit(1,"guard",Vector2(660,200))
	sim.step()
	check(light.hp==94 and heavy.hp==480 and shooter.locked_target_id==light.id,"marauder description does not override nearest targeting or add splash")
	ticks(sim,29)
	check(light.hp==94,"marauder waits full attack interval")
	sim.step()
	check(light.hp==68,"marauder fires again at 1.5 seconds")
	light.pos.x=800
	shooter.cooldown=0
	sim.step()
	check(heavy.hp==454 and shooter.locked_target_id==heavy.id,"marauder switches after range exit and applies base heavy damage")
	var armor = Sim.new()
	armor.catalog.marauder.skills = {}
	var marauder = armor.spawn_unit(0,"marauder",Vector2(500,200))
	armor.spawn_unit(1,"rifle",Vector2(600,200))
	armor.step()
	check(is_equal_approx(marauder.hp,116.9),"marauder uses existing heavy armor tag, not flat armor reduction")
	var found := false
	for seed_value in range(32):
		var army = AI.new(seed_value).choose(formation("marauder",4),1200)
		check(sim.validate_formation(army,1200)=="","AI handles marauder roster seed %d" % seed_value)
		for slot in army:
			found = found or slot.kind=="marauder"
	check(found,"AI can purchase marauder")

## 强化剂与减速必须独立于兵种 ID，按模拟时钟到期并维持同时行动公平。
func _stimulant_and_slow() -> void:
	var stim = Sim.new()
	stim.catalog.guard.speed = 0
	var caster = stim.spawn_unit(0,"marauder",Vector2(500,200))
	var target = stim.spawn_unit(1,"guard",Vector2(650,200))
	target.hp = 100000
	var events: Array = stim.step()
	check(caster.hp==106.25 and caster.stim_until_tick==401,"stim costs 15 percent max HP and lasts 20 seconds")
	check(events.filter(func(e):return e.type=="skill_used").size()==1 and stim.damage_done[1]==0,"stim cost is one skill event, not enemy damage")
	check(is_equal_approx(stim._movement_speed(caster),54),"stim grants 50 percent movement speed")
	ticks(stim,23)
	check(target.hp==99974 and caster.hp==106.25,"stim neither stacks nor recasts while active; no early shot")
	stim.step()
	check(target.hp==99948,"30 percent attack speed quantizes 1.5-second interval to 24 ticks")
	stim.tick = 400
	stim.step()
	check(caster.hp==87.5 and caster.stim_until_tick==801,"stim can renew after expiration if still fighting")
	stim.units.erase(target)
	stim.tick = 800
	stim.step()
	check(is_equal_approx(stim._movement_speed(caster),36),"stim expires without combat and restores base speed")
	check(caster.hp==87.5,"stim does not consume health without enemy target")
	var low = Sim.new()
	low.catalog.guard.speed=0
	var fragile = low.spawn_unit(0,"marauder",Vector2(500,200))
	var foe = low.spawn_unit(1,"guard",Vector2(650,200))
	fragile.hp=18.75
	low.step()
	check(fragile.hp==18.75 and not fragile.has("stim_until_tick") and foe.hp==454,"low health blocks stimulant but still permits firing")
	var base = Sim.new()
	var sieger = base.spawn_unit(0,"marauder",Vector2(1100,200))
	base.step()
	check(sieger.hp==125 and not sieger.has("stim_until_tick") and base.bases[1]==2974,"base alone does not trigger stimulant")
	for reverse in range(2):
		var healing = Sim.new()
		healing.catalog.guard.speed=0
		if reverse==0:healing.spawn_unit(0,"medic",Vector2(450,200))
		var ally = healing.spawn_unit(0,"marauder",Vector2(500,200))
		if reverse==1:healing.spawn_unit(0,"medic",Vector2(450,200))
		healing.spawn_unit(1,"guard",Vector2(650,200))
		healing.step()
		check(ally.hp==106.25,"medic cannot see future stim cost, order %d" % reverse)
		healing.step()
		check(ally.hp==118.25,"medic heals stim cost next tick, order %d" % reverse)
	# 比较不同单位处理顺序；首次命中的同一步仍走完整基础速度。
	for reverse in range(2):
		var slow = Sim.new()
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
	var refresh = Sim.new()
	refresh.catalog.guard.speed=0
	var a = refresh.spawn_unit(0,"marauder",Vector2(500,200))
	var b = refresh.spawn_unit(1,"guard",Vector2(650,200))
	refresh.step()
	a.cooldown=0
	refresh.step()
	check(b.slow_multiplier==0.5 and b.slow_until_tick==43,"repeated hits refresh slow without multiplying it")
	var both = Sim.new()
	var left = both.spawn_unit(0,"marauder",Vector2(500,200))
	var right = both.spawn_unit(1,"marauder",Vector2(600,200))
	both.step()
	check(left.hp==right.hp and is_equal_approx(both._movement_speed(left),27),"simultaneous stim and slow multiply to 75 percent speed symmetrically")
	var snapshot: Dictionary=both.get_snapshot()
	snapshot.units[0].slow_until_tick=0
	check(left.slow_until_tick>0,"snapshot status changes cannot mutate simulation")
	# 慢速光束只有实际命中才施加减速；改名兵种仍可组合多重攻击和被动。
	var wave = Sim.new()
	wave.catalog["borrowed_slow"] = wave.catalog.colossus.duplicate(true)
	wave.catalog.borrowed_slow.skills.on_hit_slow={"speed_multiplier":0.5,"duration":2}
	wave.catalog.guard.speed=0
	wave.spawn_unit(0,"borrowed_slow",Vector2(500,200))
	var center=wave.spawn_unit(1,"guard",Vector2(740,200))
	wave.step()
	check(not center.has("slow_until_tick"),"line attack does not slow before arrival")
	ticks(wave,10)
	check(center.hp==432 and center.slow_multiplier==0.5,"two delayed hits apply one nonstacking slow on actual impact")
	var support = Sim.new()
	var medic = support.spawn_unit(0,"medic",Vector2(500,200))
	medic.slow_until_tick=100
	medic.slow_multiplier=0.5
	support.step()
	check(is_equal_approx(medic.pos.x,499.1),"support movement also respects reusable slow")
	var renamed = Sim.new()
	renamed.catalog["borrowed_stim"] = renamed.catalog.rifle.duplicate(true)
	renamed.catalog.borrowed_stim.skills={"stimulant":renamed.catalog.marauder.skills.stimulant.duplicate(true)}
	var borrowed=renamed.spawn_unit(0,"borrowed_stim",Vector2(500,200))
	renamed.spawn_unit(1,"guard",Vector2(600,200))
	renamed.step()
	check(borrowed.hp==102 and borrowed.has("stim_until_tick"),"stimulant can be assigned to another unit without ID checks")
	var entry = Sim.new()
	entry.catalog.guard.speed=0
	var approaching = entry.spawn_unit(0,"marauder",Vector2(500,200))
	entry.spawn_unit(1,"guard",Vector2(669,200))
	approaching.cooldown=10
	entry.step()
	check(not approaching.has("stim_until_tick"),"discovery alone does not trigger stimulant")
	entry.step()
	check(approaching.hp==106.25 and approaching.cooldown>0,"first combat tick activates stimulant even while attack is cooling down")
	approaching.hp=18.75
	entry.tick=approaching.stim_until_tick-1
	entry.step()
	check(approaching.hp==18.75 and is_equal_approx(entry._movement_speed(approaching),36),"expired stimulant rechecks health and cannot renew at lethal cost")
