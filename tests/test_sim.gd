# 中文导读：自动验证战斗规则的开发脚本，不是玩家游戏入口。
# 运行命令见 README；不需要打开游戏窗口，也不会修改玩家存档。
# 坐标为格制战场（196×118，中心 field(0,0) = (98,59)）；预期数值尽量从 data/ 读取。
# 有意改平衡后，应检查预期而非直接删除失败测试。运行时脚本错误也计为失败。
extends SceneTree
const Sim = preload("res://scripts/battle_sim.gd")
const LineAttack = preload("res://scripts/skills/line_attack.gd")
const AI = preload("res://scripts/commander_ai.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Shield = preload("res://scripts/skills/services/shield_service.gd")
const WeaponDefinition = preload("res://scripts/units/weapon_definition.gd")
var failures := 0
var checks := 0
var errors: ErrorCounter

## 运行时脚本错误会中止当前分组但不会让进程失败；把错误计入失败数，避免半途崩溃的分组显示为通过。
class ErrorCounter extends Logger:
	var count := 0
	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1
	func _log_message(_message: String, _error: bool) -> void:
		pass

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

## 训练假人：只用于测试的人族重甲近战单位（格制，射程 1），不进入游戏数据。
## 很多旧测试用它当靶子；它没有护盾和护甲点数，便于手算伤害。
const DUMMY := {"name":"训练假人","symbol":"?","race":"terran","status":"ready","cost":100,"hp":480,"armor_type":"heavy","armor":0,"damage":16,"interval":1.2,"range":1.0,"speed":2.25,"splash":0,"size":[1.0,1.0],"collision_radius":0.5,"color":"7ed8ed","role":"测试","counter":"测试","layer":"ground","target_layers":["ground"],"sc2":"测试","attack_duration":0.1}

## SceneTree 脚本启动时运行测试集，覆盖校验、波次、残兵、胜负、AI 和性能。
const SECTIONS := ["_formation_pace","_core","_targeting","_medics","_siege","_siege_scanning","_piercers","_colossi_and_skills","_marauders","_stimulant_and_slow","_liberators","_spatial_equivalence","_structures","_setup_options","_armor_and_shields","_roster_data","_races","_battlecruisers","_economy","_desert_economy","_final_phase","_playtest_fixes","_sentry","_adepts","_medivacs","_hellbat_mechs"]

## 可用 `-- --only=_siege,_piercers` 只跑部分分组；每组打印耗时，便于定位慢测试。
func _initialize() -> void:
	Catalog.extra_units = {"dummy": DUMMY}
	errors = ErrorCounter.new()
	OS.add_logger(errors)
	var only: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",",false)
	for section in SECTIONS:
		if not only.is_empty() and not only.has(section):continue
		var before := failures
		var errors_before := errors.count
		var begin := Time.get_ticks_msec()
		call(section)
		if errors.count>errors_before:
			failures += errors.count-errors_before
			printerr("FAIL: %s raised %d engine/script errors" % [section,errors.count-errors_before])
		print("SECTION %s: %d failures, %d ms" % [section,failures-before,Time.get_ticks_msec()-begin])
	print("RESULT %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

## 校验、出兵、残兵、胜负、AI、镜像公平、重放、克制与压力测试。
func _core() -> void:
	var sim = bare()
	var grid: int = int(sim.rules.columns * sim.rules.rows)
	var start: int = int(sim.rules.start_minerals)
	check(sim.minerals==[start,start],"both sides start with start_minerals")
	var too_many: int = start/int(DUMMY.cost)+1
	check(sim.submit_formation(0,formation("dummy",too_many))!="" and sim.formations[0].is_empty() and sim.minerals[0]==start,"reject over minerals without partial purchase")
	check(sim.submit_formation(0,[{"kind":"dummy","cell":0},{"kind":"rifle","cell":0}])!="","reject duplicate cell")
	check(sim.submit_formation(0,[{"kind":"dummy","cell":grid}])!="","reject out of range")
	check(sim.submit_formation(0,[{"kind":"dummy","cell":1.5}])!="","reject fractional cell")
	check(sim.submit_formation(0,[{"kind":"unknown","cell":0}])!="","reject unknown unit")
	check(sim.submit_formation(0,[])=="","allow empty formation")
	# 开局资金只够两个假人；两队用同一校验器与同一阵容。
	var roster: Array = formation("dummy",start/int(DUMMY.cost))
	for team in range(2):
		check(sim.submit_formation(team,roster)=="","same validator team %d" % team)
	check(sim.minerals==[0,0],"roster spends all start minerals")
	check(not sim.get_snapshot(0).has("formations") and sim.get_snapshot(0).minerals==0,"snapshot hides opponent roster and minerals")
	var first_wave: int = int(float(sim.rules.first_wave_seconds)*float(sim.rules.tick_rate))
	ticks(sim,first_wave-1)
	check(sim.units.is_empty() and sim.wave==0,"no spawn before first_wave_seconds")
	sim.step()
	check(sim.wave==1 and sim.units.size()==roster.size()*2,"simultaneous first wave")
	# 收入按 income_seconds 定时发放，与出兵无关；首波前共发放 floor(首波tick/收入间隔) 次。
	var income_ticks: int = int(float(sim.rules.economy.income_seconds)*float(sim.rules.tick_rate))
	var paid: int = (first_wave/income_ticks)*sim.economy.base_income(0)
	check(sim.minerals==[paid,paid],"timed income accrues independently of waves")
	var id: int = sim.units[0].id
	sim.submit_formation(0,[])
	check(sim.units[0].id==id and sim.last_formations[0].size()==roster.size(),"editing leaves battlefield intact")
	check(sim.minerals[0]==paid,"cancelling deployed units refunds nothing")
	check(sim.journal.waves[0].formations[0].size()==roster.size() and sim.journal.actions.size()==roster.size()*3,"journal records waves and every buy/sell")
	ticks(sim,sim.wave_ticks())
	check(sim.wave==2 and sim.units.size()>=roster.size() and sim.last_formations[0].is_empty() and sim.last_formations[1].size()==roster.size(),"permanent roster respawns every wave")
	# 寿命为可选规则：默认 0 不撤离；配置为 90 秒时精确检查前一刻和刚到 90 秒的区别。
	var immortal = bare()
	var veteran: Dictionary = immortal.spawn_unit(0,"dummy",field(-40,0))
	veteran.born = -100000
	immortal.step()
	check(immortal.units.size()==1,"default rules never expire units")
	var lifetime = bare(42,{"unit_lifetime":90})
	var survivor: Dictionary = lifetime.spawn_unit(0,"dummy",field(-40,0))
	survivor.born = -1798
	lifetime.step()
	check(lifetime.units.size()==1,"survivor retained before expiry")
	lifetime.step()
	check(lifetime.units.is_empty(),"optional expiry exactly 90 seconds")
	var retained = bare()
	retained.spawn_unit(0,"dummy",field(-40,0))
	retained.tick=retained.next_wave_tick-1
	retained.minerals[0]=1000
	retained.submit_formation(0,formation("dummy",1))
	retained.step()
	check(retained.units.size()==2 and retained.units[0].id==1,"next wave retains survivors")
	# 同时摧毁基地必须判平，不能因为某队先被处理就先判负。
	var draw = bare()
	draw.bases=[1.0,1.0]
	for team in range(2):
		draw.spawn_unit(team,"rifle",draw.base_pos(1-team)+Vector2(-4.0 if team==0 else 4.0,0))
	ticks(draw,40)
	check(draw.finished and draw.winner==-1 and draw.bases==[0.0,0.0],"simultaneous base destruction draws")
	var mutual = bare()
	for team in range(2):
		mutual.spawn_unit(team,"rifle",field(-2.0 if team==0 else 2.0,0)).hp = 1
	var guard := 0
	while mutual.units.size()==2 and guard<100:
		mutual.step()
		guard+=1
	check(mutual.units.is_empty() and mutual.kills==[1,1],"simultaneous lethal attacks both fire")
	var commander = AI.new()
	for minerals in [0,50,600,900,1200,5000]:
		check(sim.validate_formation(commander.choose(Catalog.starter(),minerals),minerals)=="","AI obeys minerals and grid %d" % minerals)
	# 镜像公平测试：相同配置放在两侧，击杀数与基地状态应保持一致。
	var mirror = bare(42,{"start_minerals":2000})
	mirror.submit_formation(0,Catalog.starter())
	mirror.submit_formation(1,Catalog.starter())
	ticks(mirror,first_wave+1200)
	check(mirror.kills[0]+mirror.kills[1]>0,"mirror battle actually fights")
	check(is_equal_approx(mirror.bases[0],mirror.bases[1]) and mirror.kills[0]==mirror.kills[1],"mirror battle has no side advantage")
	var replay = bare(42,{"start_minerals":2000})
	replay.submit_formation(0,Catalog.starter())
	replay.submit_formation(1,Catalog.starter())
	ticks(replay,first_wave+1200)
	check(replay.get_snapshot()==mirror.get_snapshot(),"same inputs reproduce same simulation")
	_counter("agent","dummy",1500,"armor-piercing agent vs heavy")
	_counter("rifle","swarm",600,"rifle vs light")
	_counter("mortar","swarm",1700,"splash vs swarm")
	_counter("ultralisk","rifle",1800,"ultralisk armor vs rifles")
	_counter("mortar","agent",1700,"siege outranges agent")
	_counter("hellbat","zergling",900,"flame vs light melee")
	_counter("immortal","roach",1500,"immortal vs heavy")
	_counter("viking","liberator",2400,"viking vs heavy air")
	# 压力测试使用 200 个高血量单位，避免测试过程中快速减员；这个测试不测画面 FPS。
	var stress = bare()
	for team in range(2):
		for i in range(100):
			var u: Dictionary = stress.spawn_unit(team,"dummy",field((-12.0 if team==0 else 2.0)+(i%10)*1.1,-25.0+(i/10)*5.0))
			u.hp=1000000.0
	var begin := Time.get_ticks_usec()
	ticks(stress,600)
	var elapsed: float = float(Time.get_ticks_usec()-begin)/1000.0
	print("PERF 200 units, 600 ticks: %.2f ms total, %.3f ms/tick" % [elapsed,elapsed/600.0])

## 战场中心附近的坐标（格）；测试统一以中心为原点摆放单位，避免依赖出生点和基地位置。
func field(dx: float, dy: float) -> Vector2:
	return Vector2(98.0+dx,59.0+dy)

## 让两个等预算单兵种编队作战（每份按 spawn_count 出生），交换左右位置再测一次，排查阵营顺序优势。
func _counter(a: String, b: String, budget: int, label: String) -> void:
	var outcomes: Array = []
	for reverse in range(2):
		var sim = bare(42,{"races":["terran","terran"]})
		var sides: Array = [[a,reverse],[b,1-reverse]]
		for side in sides:
			var stats: Dictionary = sim.catalog[side[0]]
			var count: int = (budget/int(stats.cost))*maxi(1,int(stats.get("spawn_count",1)))
			var x: float = -7.0 if int(side[1])==0 else 7.0
			for i in range(count):
				sim.spawn_unit(int(side[1]),side[0],field(x+(-1.0 if int(side[1])==0 else 1.0)*float(i/4)*1.6,-2.4+float(i%4)*1.6))
		ticks(sim,1200)
		var a_survivors:=0
		var b_survivors:=0
		for unit in sim.units:
			if unit.team==reverse:a_survivors+=1
			else:b_survivors+=1
		outcomes.append([a_survivors,b_survivors])
	# 胜负属于平衡结论（见 PROJECT_BACKLOG G05/G06），只打印供平衡评审；规则层只要求换边结果完全一致。
	check(outcomes[0]==outcomes[1],label+" matchup is identical after swapping sides")
	print("COUNTER %s (budget %d): %s %s" % [label,budget,str(outcomes[0]),"A wins" if outcomes[0][0]>0 and outcomes[0][1]==0 else "A does not win"])

## 发现边界、追击重选、实际开火锁定、冷却保持及失效后的重新索敌。
func _targeting() -> void:
	for kind in Catalog.units():
		var boundary = bare()
		var observer = boundary.spawn_unit(0, kind, field(0,0))
		var search: Dictionary = boundary._search_stats(observer)
		var enemy_kind: String = "liberator" if search.get("target_layers",["ground"]) == ["air"] else "dummy"
		var enemy = boundary.spawn_unit(1, enemy_kind, field(30,0))
		boundary._build_buckets()
		# 发现半径 = 搜索射程（从边缘量的近战加双方体积）× 150%，再经技能修正。
		var reach: float = float(search.range)
		if bool(search.get("range_from_edge",false)):
			reach += boundary.body_radius(observer)+boundary.max_body_radius
		var radius: float = boundary.skill_system.discovery_radius(boundary,observer,reach*1.5)
		# Vector2 为 32 位浮点，边界两侧各留极小余量。
		enemy.pos = observer.pos+Vector2(radius-0.001,0)
		boundary._build_buckets()
		check(boundary._target(observer).get("id",0)==enemy.id,kind+" discovers at 150% range")
		enemy.pos.x += 0.011
		boundary._build_buckets()
		check(boundary._target(observer).is_empty(),kind+" ignores beyond discovery range")
	var sim = bare()
	# 静止、无攻击、高生命敌人用于隔离索敌行为，避免移动或死亡干扰测试。
	tune(sim,"dummy",{"speed":0,"damage":0,"hp":10000})
	var range_rifle: float = float(sim.catalog.rifle.range)
	var shooter = sim.spawn_unit(0,"rifle",field(0,0))
	var first = sim.spawn_unit(1,"dummy",field(range_rifle*1.4,0))
	sim.step()
	check(shooter.pos.x>field(0,0).x and shooter.locked_target_id==0,"pursuit moves without locking")
	var closer = sim.spawn_unit(1,"dummy",shooter.pos+Vector2(range_rifle*0.8,0))
	shooter.cooldown = 1.0
	sim.step()
	check(shooter.locked_target_id==0 and closer.hp==10000,"in range before first shot stays unlocked")
	shooter.cooldown = 0.0
	ticks(sim,strike_ticks(sim,"rifle"))
	check(shooter.locked_target_id==closer.id and closer.hp<10000,"first shot locks newly closer target")
	first.pos = shooter.pos+Vector2(range_rifle*0.4,0)
	var original_hp: float = first.hp
	sim.step()
	check(shooter.locked_target_id==closer.id,"cooldown preserves lock despite closer enemy")
	shooter.cooldown = 0.0
	var locked_hp: float = closer.hp
	ticks(sim,strike_ticks(sim,"rifle"))
	check(first.hp==original_hp and closer.hp<locked_hp,"subsequent shot retains target")
	# 锁定目标仍在发现范围，却已离开攻击范围：必须释放并重新选择。
	closer.pos = shooter.pos + Vector2(range_rifle*1.45,0)
	shooter.cooldown = 0.0
	ticks(sim,strike_ticks(sim,"rifle"))
	check(shooter.locked_target_id==first.id and first.hp<original_hp,"leaving attack range triggers reselection")
	first.hp = 1
	shooter.cooldown = 0.0
	ticks(sim,strike_ticks(sim,"rifle"))
	check(not sim.units.has(first),"locked target killed")
	closer.pos = shooter.pos + Vector2(range_rifle*0.8,0)
	shooter.cooldown = 0.0
	ticks(sim,strike_ticks(sim,"rifle"))
	check(shooter.locked_target_id==closer.id,"dead target replaced")
	sim.rules.unit_lifetime = 90
	closer.born = sim.tick - int(sim.rules.unit_lifetime * sim.rules.tick_rate)
	sim.step()
	check(shooter.locked_target_id==0,"expired target releases lock")
	# 特工：按目标护甲选择预期秒伤更高的弹种；换弹 1.5 秒内不能开火或移动。
	var spec = bare()
	tune(spec,"dummy",{"speed":0,"damage":0,"hp":10000})
	tune(spec,"rifle",{"speed":0,"damage":0,"hp":10000,"skills":{}})
	var modes: Array = spec.catalog.agent.skills.weapon_switch.weapons
	var agent = spec.spawn_unit(0,"agent",field(0,0))
	var heavy = spec.spawn_unit(1,"dummy",field(5,0))
	var opening: Array = []
	for i in range(strike_ticks(spec,"agent")):
		opening.append_array(spec.step())
	check(int(agent.get("weapon_index",0))==0 and heavy.hp==10000-spec.expected_damage(modes[0],heavy) and not opening.any(func(e): return e.type=="weapon_switch"),"agent opens with armor-piercing rounds on heavy armor")
	spec.units.erase(heavy)
	var light = spec.spawn_unit(1,"rifle",field(5,0))
	# 正在进行的一轮（含后摇）结束后才判断换弹。
	var switching: Array = []
	var waited := 0
	while not switching.any(func(e): return e.type=="weapon_switch") and waited<60:
		switching = spec.step()
		waited += 1
	check(int(agent.get("weapon_index",0))==1 and light.hp==10000 and switching.any(func(e): return e.type=="weapon_switch" and e.weapon=="precision"),"light target starts switch to precision rounds")
	check(waited>1,"switch waits for the current round's backswing")
	var switch_ticks: int = ceili(float(spec.catalog.agent.skills.weapon_switch.switch_seconds)*float(spec.rules.tick_rate))
	ticks(spec,switch_ticks-1)
	check(light.hp==10000 and agent.pos==field(0,0),"agent cannot fire or move during 1.5-second switch")
	ticks(spec,1+strike_ticks(spec,"agent",1))
	check(light.hp==10000-spec.expected_damage(modes[1],light) and agent.locked_target_id==light.id,"precision rounds fire after switch with light bonus")
	# 雷神：对地固定用重锤炮，目标换成空中时立即换到默认对空模式，无需换弹等待。
	var hammer = bare()
	tune(hammer,"dummy",{"speed":0,"damage":0,"hp":10000})
	tune(hammer,"liberator",{"speed":0,"damage":0,"hp":10000})
	var thor_modes: Array = hammer.catalog.thor.skills.weapon_switch.weapons
	var thor = hammer.spawn_unit(0,"thor",field(0,0))
	var walker = hammer.spawn_unit(1,"dummy",field(5,0))
	ticks(hammer,strike_ticks(hammer,"thor",2)+2)
	check(int(thor.get("weapon_index",-1))==2 and walker.hp==10000-2*hammer.expected_damage(thor_modes[2],walker),"thor uses two-hit ground cannon on ground")
	hammer.units.erase(walker)
	var flyer = hammer.spawn_unit(1,"liberator",field(6,0))
	thor.cooldown = 0
	var air_events: Array = []
	for i in range(strike_ticks(hammer,"thor",0)+2):
		air_events.append_array(hammer.step())
	check(int(thor.weapon_index)==0 and flyer.hp<10000 and not air_events.any(func(e): return e.type=="weapon_switch"),"thor swaps to default anti-air mode instantly")
	check(is_equal_approx(float(10000-flyer.hp),2*hammer.expected_damage(thor_modes[0],flyer)),"anti-air shells add heavy bonus minus armor per hit")

## 一轮出手到最后一段命中所需的步数（前摇 + 出手时长 + 定时弹道），用于不依赖具体数值地等待命中。
func strike_ticks(sim, kind: String, mode: int = -1) -> int:
	var weapon: Dictionary = sim.definitions[kind].primary_weapon_data
	if mode>=0:weapon=sim.catalog[kind].skills.weapon_switch.weapons[mode]
	var flight: float = float(weapon.delivery.get("seconds",0)) if str(weapon.delivery.get("flight",""))=="fixed" else 0.0
	return ceili((float(weapon.windup)+float(weapon.attack_duration)+flight)*float(sim.rules.tick_rate)-0.0001)+1

## 测试专用：修改兵种参数后重建模板，使移动、武器（含全部 attack_modes）都使用新值。
func tune(sim, kind: String, fields: Dictionary) -> void:
	var data: Dictionary = sim.catalog[kind].duplicate(true)
	for key in fields:
		data[key] = fields[key]
		for mode in data.get("attack_modes",[]):
			if mode.has(key) or key in ["damage","interval","range"]:mode[key]=fields[key]
	sim.definitions[kind] = Catalog.UnitDefinition.new(kind,data,sim.rules)
	sim.catalog[kind] = sim.definitions[kind].to_data()

## 治疗、冷却、上限、阵营与前排安全站位，双方方向均需一致。
## 医疗兵为持续光束：首个病人无切换等待，每 tick_interval 秒完整结算一次 healing。
func _medics() -> void:
	for team in range(2):
		var sim = bare()
		tune(sim,"dummy",{"speed":0,"damage":0})
		var heal: float = float(sim.definitions.medic.primary_weapon_data.healing)
		var pulse: int = ceili(float(sim.definitions.medic.primary_weapon_data.delivery.tick_interval)*float(sim.rules.tick_rate))
		var direction: float = 1 if team == 0 else -1
		var medic = sim.spawn_unit(team,"medic",field(0,0))
		var ally = sim.spawn_unit(team,"dummy",field(direction*2.5,0))
		ally.hp = 200
		var enemy = sim.spawn_unit(1-team,"dummy",field(direction*1.5,0))
		enemy.hp = 100
		var beams := false
		for i in range(pulse):
			sim.step()
			beams = beams or sim.active_beams.any(func(b): return bool(b.healing) and int(b.target_id)==ally.id)
		check(ally.hp==200+heal and enemy.hp==100 and medic.hp==float(sim.catalog.medic.hp),"medic only heals injured ally %d" % team)
		check(beams,"healing beam shown on patient %d" % team)
		sim.step()
		check(ally.hp==200+heal,"healing waits for the next pulse")
		check(float(medic.pos.x)*direction<field(0,0).x*direction,"medic retreats from nearby enemy")
		sim.units.erase(enemy)
		ally.hp=479
		ticks(sim,pulse)
		check(ally.hp==480,"healing capped at max hp")
		medic.hp=50
		sim.step()
		check(medic.hp==50 and not sim.active_beams.any(func(b): return bool(b.healing)),"no self healing or healing full ally")
		# 医疗兵误放在前排时主动后撤；战斗单位消失后继续退向己方出兵点。
		medic.pos=ally.pos+Vector2(direction*2,0)
		var before: float = medic.pos.x
		sim.step()
		check(float(medic.pos.x)*direction<before*direction,"medic moves behind frontline")
		sim.units.erase(ally)
		before=medic.pos.x
		sim.step()
		var base_hp: float = float(sim.rules.base_hp)
		check(float(medic.pos.x)*direction<before*direction and sim.bases==[base_hp,base_hp],"isolated medic retreats and never attacks base")
	var priority = bare()
	tune(priority,"dummy",{"speed":0,"damage":0})
	tune(priority,"rifle",{"speed":0,"damage":0,"skills":{}})
	tune(priority,"medic",{"speed":0})
	var heal: float = float(priority.definitions.medic.primary_weapon_data.healing)
	var pulse: int = ceili(float(priority.definitions.medic.primary_weapon_data.delivery.tick_interval)*float(priority.rules.tick_rate))
	var switch_wait: int = ceili(float(priority.definitions.medic.primary_weapon_data.delivery.switch_delay)*float(priority.rules.tick_rate))
	var healer=priority.spawn_unit(0,"medic",field(0,0))
	var tank=priority.spawn_unit(0,"dummy",field(2,0))
	var rifle=priority.spawn_unit(0,"rifle",field(1.8,0.8))
	tank.hp=240
	rifle.hp=20
	ticks(priority,pulse)
	check(rifle.hp==20+heal and tank.hp==240,"heal lowest health ratio, not largest missing hp")
	rifle.pos=field(8,0)
	ticks(priority,switch_wait+pulse)
	check(rifle.hp==20+heal and tank.hp==240+heal,"out of range ally cannot be healed")
	# 持续光束保持当前病人，即使更低比例的友军回到射程内也不频繁换人。
	rifle.pos=field(1.8,0.8)
	rifle.hp=10
	ticks(priority,pulse)
	check(rifle.hp==10 and tank.hp==240+heal*2,"beam keeps current patient while it is still injured")
	tank.hp=480
	rifle.hp=float(priority.catalog.rifle.hp)
	var support=priority.spawn_unit(0,"medic",field(-0.5,0))
	support.hp=10
	ticks(priority,switch_wait+pulse)
	check(support.hp==10+heal,"medic can heal another medic")
	# 两个治疗同时生效，过量治疗不能抵消本步本应致死的伤害：先按上限封顶再扣伤害。
	var lethal=bare()
	tune(lethal,"rifle",{"speed":0,"damage":0,"skills":{}})
	tune(lethal,"medic",{"speed":0})
	var hit: float = float(lethal.catalog.rifle.hp)+float(lethal.catalog.rifle.armor)+2
	tune(lethal,"dummy",{"speed":0,"damage":hit,"interval":5.0,"range":3.0})
	var victim=lethal.spawn_unit(0,"rifle",field(0,0))
	victim.hp=float(lethal.catalog.rifle.hp)-1
	lethal.spawn_unit(0,"medic",field(-2,-1))
	lethal.spawn_unit(0,"medic",field(-2,1))
	var attacker=lethal.spawn_unit(1,"dummy",field(2.5,0))
	# 攻击者出手后 2 步命中；令命中恰好落在两名医疗兵的第一次治疗结算步。
	attacker.cooldown=float(pulse-2)/float(lethal.rules.tick_rate)
	var died_at := -1
	var healed_that_step := false
	for i in range(pulse+2):
		lethal.step()
		if died_at<0 and not lethal.units.has(victim):
			died_at=lethal.tick
			healed_that_step=lethal.active_beams.filter(func(b): return int(b.target_id)==victim.id).size()==2
	check(died_at==pulse and healed_that_step,"two heals and a lethal hit resolve on the same step")
	check(not lethal.units.has(victim),"overhealing cannot act as a shield")
	var ai=AI.new()
	var support_formation: Array=ai.buy_list([],[],2000,0)
	check(support_formation.any(func(s): return s.kind=="medivac" and int(s.cell) % int(lethal.rules.columns)==0),"AI buys medivac in rear column")
	check(not support_formation.any(func(s):return s.kind=="medic"),"AI never buys dormant medic")
	check(lethal.validate_formation(support_formation,2000)=="","AI support formation within budget")

## 架设与收起按模拟时间推进；未确认前保持移动形态（可用移动炮），架设后换攻城炮与架设护甲。
func _siege() -> void:
	for team in range(2):
		var sim=bare()
		tune(sim,"dummy",{"speed":0,"damage":0,"hp":1000})
		tune(sim,"rifle",{"speed":0,"damage":0,"hp":1000,"skills":{}})
		var config: Dictionary=sim.catalog.mortar.skills.deployment
		var siege_weapon: Dictionary=config.weapon
		var rate: float=float(sim.rules.tick_rate)
		var scan: int=ceili(float(config.scan_seconds)*rate)
		var deploy: int=ceili(float(config.deploy_seconds)*rate)
		var pack: int=ceili(float(config.pack_seconds)*rate)
		var cycle: int=roundi((float(siege_weapon.attack_duration)+float(siege_weapon.interval))*rate)
		var forward: float = 1 if team==0 else -1
		var far: float=float(siege_weapon.range)*0.85
		var gone: float=float(siege_weapon.range)*float(config.hold_range_multiplier)+1.0
		var gun=sim.spawn_unit(team,"mortar",field(0,0))
		var heavy=sim.spawn_unit(1-team,"dummy",field(forward*far,0))
		var light=sim.spawn_unit(1-team,"rifle",field(forward*(far+0.5),0.8))
		var friend=sim.spawn_unit(team,"dummy",field(forward*(far+0.3),-0.5))
		sim.step()
		check(gun.siege_state=="mobile" and gun.locked_target_id==0,"first scan does not deploy")
		check(float(gun.pos.x)*forward>field(0,0).x*forward,"unconfirmed tank keeps advancing in mobile mode")
		ticks(sim,scan)
		check(gun.siege_state=="deploying" and gun.locked_target_id==0,"same enemy on next scan begins setup without firing lock")
		var initial: Vector2=gun.pos
		ticks(sim,deploy-1)
		check(gun.pos==initial and heavy.hp==1000 and light.hp==1000,"setup blocks movement and early firing")
		sim.step()
		check(gun.siege_state=="deployed","setup completes after deploy_seconds")
		var waited := wait_until(sim,func(): return heavy.hp<1000,20)
		var splash: float=WeaponDefinition.splash_damage_multiplier(siege_weapon,light.pos.distance_to(heavy.pos))
		var light_hit: float=maxf(sim.raw_damage(siege_weapon,"rifle")*splash-float(sim.catalog.rifle.armor),float(sim.rules.min_damage))
		check(waited>0 and heavy.hp==1000-sim.expected_damage(siege_weapon,heavy) and is_equal_approx(light.hp,1000-light_hit),"first deployed shot: siege damage + heavy bonus, reduced splash to light")
		check(friend.hp==1000 and gun.locked_target_id==heavy.id,"splash ignores friends and locks main target")
		check(sim.expected_damage({"damage":10},gun)==10-float(config.armor_override),"deployed tank uses armor_override")
		var first_hp: float=heavy.hp
		ticks(sim,cycle-1)
		check(heavy.hp==first_hp and gun.pos==initial,"deployed cooldown blocks early shot and movement")
		sim.step()
		check(heavy.hp<first_hp,"deployed second shot respects attack duration plus interval")
		# 目标仍在发现范围内，却离开 120% 保持距离，必须收起，不能边架设边追击。
		heavy.pos=gun.pos+Vector2(forward*gone,0)
		light.pos=gun.pos+Vector2(forward*(gone+0.5),0.8)
		sim.step()
		check(gun.siege_state=="packing" and gun.locked_target_id==0,"out of range releases lock and starts packing")
		ticks(sim,pack-1)
		check(gun.pos==initial and gun.siege_state=="packing","packing blocks movement")
		sim.step()
		check(gun.siege_state=="mobile" and gun.pos==initial,"packing completes after full duration")
		sim.step()
		check(float(gun.pos.x)*forward>initial.x*forward,"mobile tank resumes pursuit")
		# 转换期间新敌人出现也不能跳过收起/架设时间。
		heavy.pos=gun.pos+Vector2(forward*far,0)
		check(wait_until(sim,func(): return gun.siege_state=="deploying",scan*2+2)>0,"returning target requires new setup")
		heavy.pos=gun.pos+Vector2(forward*gone,0)
		sim.step()
		check(gun.siege_state=="packing","lost target during setup triggers packing")
		heavy.pos=gun.pos+Vector2(forward*far,0)
		var before: float=heavy.hp
		ticks(sim,pack)
		check(gun.siege_state=="mobile" and heavy.hp==before,"target returning during packing cannot fire")
		check(wait_until(sim,func(): return gun.siege_state=="deploying",scan*2+2)>0,"returning target starts another setup")
		ticks(sim,deploy-1)
		check(heavy.hp==before,"new setup cannot fire early")
		wait_until(sim,func(): return heavy.hp<before,deploy)
		check(heavy.hp==before-sim.expected_damage(siege_weapon,heavy),"new setup fires when complete")
		# 已架设时目标消失，只要另一个目标仍在射程内就直接转火。
		sim.units.erase(heavy)
		light.pos=gun.pos+Vector2(forward*far,0)
		var stayed := true
		for i in range(cycle+10):
			sim.step()
			stayed = stayed and gun.siege_state=="deployed"
			if gun.locked_target_id==light.id:break
		check(stayed and gun.locked_target_id==light.id,"deployed gun reacquires without unnecessary setup")
	var base=bare()
	var base_config: Dictionary=base.catalog.mortar.skills.deployment
	var reach: float=float(base_config.weapon.range)+float(base.rules.layout.base_radius)-1.0
	var siege=base.spawn_unit(0,"mortar",base.base_pos(1)-Vector2(reach,0))
	base.step()
	ticks(base,ceili(float(base_config.deploy_seconds)*float(base.rules.tick_rate))-1)
	var full: float=float(base.rules.base_hp)
	check(base.bases[1]==full,"base attack also requires setup")
	wait_until(base,func(): return base.bases[1]<full,30)
	var regen_tick: float=float(base.rules.base_regen_per_second)/float(base.rules.tick_rate)
	check(is_equal_approx(base.bases[1],full-float(base_config.weapon.damage)+regen_tick) and siege.siege_state=="deployed","deployed tank attacks base; base regenerates in the same step")
	# 受伤坦克在完成架设前仍可被射程内的特工击杀。
	var ambush=bare()
	var fragile=ambush.spawn_unit(0,"mortar",field(0,0))
	fragile.hp=50
	ambush.spawn_unit(1,"agent",field(6,0))
	ticks(ambush,10)
	check(not ambush.units.has(fragile),"agent ambush kills tank before setup")

## 推进模拟直到条件成立；返回推进的步数，超过上限仍未成立返回 -1。
func wait_until(sim, condition: Callable, limit: int) -> int:
	for i in range(limit):
		sim.step()
		if condition.call():return i+1
	return -1

## 防止短暂目标导致反复架设：确认同一敌人，以及外圈接近方向。距离按攻城炮射程的比例摆放。
func _siege_scanning() -> void:
	var scan=bare()
	tune(scan,"dummy",{"speed":0})
	var weapon: Dictionary=scan.catalog.mortar.skills.deployment.weapon
	var config: Dictionary=scan.catalog.mortar.skills.deployment
	var reach: float=float(weapon.range)
	var hold: float=reach*float(config.hold_range_multiplier)
	var scan_ticks: int=ceili(float(config.scan_seconds)*float(scan.rules.tick_rate))
	var gun=scan.spawn_unit(0,"mortar",field(0,0))
	var first=scan.spawn_unit(1,"dummy",field(reach*0.9,0))
	scan.spawn_unit(0,"dummy",field(0.6,1.2))
	scan.step()
	check(gun.siege_state=="mobile" and gun.locked_target_id==0,"single transient enemy only observed")
	scan.units.erase(first)
	var second=scan.spawn_unit(1,"dummy",field(reach*0.92,0))
	ticks(scan,scan_ticks)
	check(gun.siege_state=="mobile","different ID on second scan cannot confirm first enemy")
	scan.units.erase(second)
	ticks(scan,scan_ticks)
	scan.spawn_unit(1,"dummy",field(reach*0.93,0))
	ticks(scan,scan_ticks)
	check(gun.siege_state=="mobile","empty scan clears old observations")
	ticks(scan,scan_ticks)
	check(gun.siege_state=="deploying","same enemy across consecutive scans confirms setup")
	var threshold: int=int(config.deploy_enemy_threshold)
	var crowd=bare()
	tune(crowd,"dummy",{"speed":0})
	var artillery=crowd.spawn_unit(0,"mortar",field(0,0))
	for i in range(threshold):
		crowd.spawn_unit(1,"dummy",field(reach*0.9,-1.0+2.0*i))
	crowd.step()
	check(artillery.siege_state=="mobile","exactly threshold enemies still need confirmation")
	crowd.spawn_unit(1,"dummy",field(reach*0.92,0.2))
	crowd.step()
	check(artillery.siege_state=="deploying","more than threshold enemies deploy immediately between scans")
	# 靠近判断采用上一模拟步的位移；双方镜像均须保持架设并最终开火。
	for team in range(2):
		var sim=bare()
		var direction: float=1 if team==0 else -1
		var cannon=sim.spawn_unit(team,"mortar",field(0,0))
		set_skill_state(sim,cannon,"deployment","siege_state","deployed")
		cannon.cooldown=10
		var victim=sim.spawn_unit(1-team,"dummy",field(direction*reach*0.9,0))
		victim.hp=1
		sim.spawn_unit(team,"agent",field(direction*(reach*0.9-5.0),0))
		var incoming=sim.spawn_unit(1-team,"dummy",field(direction*(hold-0.4),1.7))
		wait_until(sim,func(): return not sim.units.has(victim),20)
		check(not sim.units.has(victim),"ally kills original target")
		sim.step()
		check(cannon.siege_state=="deployed" and cannon.pos==field(0,0),"approaching outer enemy prevents packing after ally kill")
		cannon.cooldown=0
		var held := true
		for i in range(80):
			sim.step()
			held = held and cannon.siege_state=="deployed"
			if cannon.locked_target_id==incoming.id:break
		check(held and cannon.locked_target_id==incoming.id,"held artillery fires when next enemy reaches range")
	# 120% 边界包含接近敌人；静止、远离、切向及超出边界不算接近。Vector2 为 32 位浮点，边界两侧各留极小余量。
	for scenario in ["approaching","stationary","away","tangent","outside"]:
		var sim=bare()
		tune(sim,"dummy",{"speed":0})
		var cannon=sim.spawn_unit(0,"mortar",field(0,0))
		set_skill_state(sim,cannon,"deployment","siege_state","deployed")
		var x: float=hold+0.01 if scenario=="outside" else hold-0.001
		var enemy=sim.spawn_unit(1,"dummy",field(x,0))
		enemy.prev=enemy.pos
		if scenario=="approaching" or scenario=="outside": enemy.prev.x+=0.05
		elif scenario=="away": enemy.prev.x-=0.05
		elif scenario=="tangent": enemy.prev.y-=0.05
		sim.step()
		check(cannon.siege_state==("deployed" if scenario=="approaching" else "packing"),"outer approach check: "+scenario)
	# 架设中也保持相同的外圈判定，避免刚启动就因原目标死亡取消。
	var setup=bare()
	var cannon=setup.spawn_unit(0,"mortar",field(0,0))
	set_skill_state(setup,cannon,"deployment","siege_state","deploying")
	set_skill_state(setup,cannon,"deployment","siege_until_tick",2)
	var enemy=setup.spawn_unit(1,"dummy",field(reach+1.0,0))
	enemy.prev.x+=0.05
	setup.step()
	check(cannon.siege_state=="deploying","approaching enemy preserves ongoing setup")
	setup.step()
	check(cannon.siege_state=="deployed" and cannon.locked_target_id==0,"setup completes while waiting for approaching enemy")

## 技能状态以组件 state 为准（单位字典上的同名字段只是每步发布的副本）；测试需改组件状态。
func set_skill_state(sim, unit: Dictionary, skill: String, key: String, value) -> void:
	sim.skill_system.get_component(unit,skill).state[key]=value
	sim.skill_system.publish(unit)

## 地刺沿开火方向传播到固定长度，每波对每个敌人最多命中一次；出手时长结束才发出。
func _piercers() -> void:
	for team in range(2):
		var sim=bare()
		tune(sim,"dummy",{"speed":0,"damage":0,"hp":1000})
		var weapon: Dictionary=sim.definitions.piercer.primary_weapon_data
		var length: float=float(weapon.delivery.length)
		var half: float=float(weapon.delivery.half_width)
		var forward: float=1 if team==0 else -1
		var gun=sim.spawn_unit(team,"piercer",field(0,0))
		set_skill_state(sim,gun,"deployment","siege_state","deployed")
		var near=sim.spawn_unit(1-team,"dummy",field(forward*2,0))
		var far=sim.spawn_unit(1-team,"dummy",field(forward*7,0))
		var edge=sim.spawn_unit(1-team,"dummy",field(forward*(length-0.001),0))
		var beyond=sim.spawn_unit(1-team,"dummy",field(forward*(length+0.01),0))
		var width_edge=sim.spawn_unit(1-team,"dummy",field(forward*4,half-0.001))
		var outside=sim.spawn_unit(1-team,"dummy",field(forward*5,half+0.01))
		var friend=sim.spawn_unit(team,"dummy",field(forward*3,0))
		var hit: float=sim.expected_damage(weapon,near)
		check(wait_until(sim,func(): return sim.attack_waves.size()==1,20)>1 and near.hp==1000 and far.hp==1000,"piercer launches after attack duration without instant damage")
		check(gun.locked_target_id==near.id and sim.attack_waves[0].length==length,"near target sets direction, not line length")
		var snapshot: Dictionary=sim.get_snapshot()
		snapshot.attack_waves[0].distance=999
		check(sim.attack_waves[0].distance<999,"wave snapshot is independent")
		var behind=sim.spawn_unit(1-team,"dummy",field(-forward*0.5,0))
		check(wait_until(sim,func(): return near.hp<1000,20)>1,"near enemy unharmed before wave arrives")
		check(near.hp==1000-hit and far.hp==1000,"wave reaches near enemy before far enemy")
		# 发射者死亡和原目标死亡都不能取消已经发出的地刺。
		sim.units.erase(gun)
		sim.units.erase(near)
		check(wait_until(sim,func(): return far.hp<1000,40)>1,"far enemy unharmed until travel time elapses")
		check(far.hp==1000-hit,"wave survives shooter and original target removal")
		wait_until(sim,func(): return sim.attack_waves.is_empty(),40)
		check(edge.hp==1000-hit and beyond.hp==1000,"fixed length includes endpoint and excludes beyond it")
		check(width_edge.hp==1000-hit and outside.hp==1000,"line half-width boundary")
		check(friend.hp==1000 and behind.hp==1000,"no friendly fire or damage behind origin")
		check(far.hp==1000-hit and sim.attack_waves.is_empty(),"one hit per victim and completed wave cleaned up")
	var dodge=bare()
	tune(dodge,"dummy",{"speed":0,"damage":0,"hp":1000})
	var gun=dodge.spawn_unit(0,"piercer",field(0,0))
	set_skill_state(dodge,gun,"deployment","siege_state","deployed")
	var target=dodge.spawn_unit(1,"dummy",field(4,0))
	var far=dodge.spawn_unit(1,"dummy",field(9,0))
	wait_until(dodge,func(): return dodge.attack_waves.size()==1,20)
	var origin: Vector2=target.pos
	target.pos=origin+Vector2(0,3)
	dodge.units.erase(gun)
	wait_until(dodge,func(): return dodge.attack_waves.is_empty() or float(dodge.attack_waves[0].distance)>5.0,40)
	var late=dodge.spawn_unit(1,"dummy",origin)
	wait_until(dodge,func(): return dodge.attack_waves.is_empty(),40)
	check(target.hp==1000 and far.hp<1000,"wave does not home; target can dodge while rear enemy is hit")
	check(late.hp==1000,"entering behind passed wave causes no retroactive damage")
	# 本步横穿路径的敌人必须在波前到达时位于线宽内，不能只检查两个端点。
	var wave={"origin":Vector2.ZERO,"direction":Vector2.RIGHT,"distance":0.0,"half_width":0.7}
	check(LineAttack.crosses(wave,Vector2(0.5,1.5),Vector2(0.5,-1.5),1.0),"swept hit catches crossing during tick")
	check(not LineAttack.crosses(wave,Vector2(0.5,2.0),Vector2(0.5,1.0),1.0),"swept hit excludes missed path")
	var setup=bare()
	tune(setup,"dummy",{"speed":0,"damage":0})
	var config: Dictionary=setup.catalog.piercer.skills.deployment
	var rate: float=float(setup.rules.tick_rate)
	var burrower=setup.spawn_unit(0,"piercer",field(0,0))
	var enemy=setup.spawn_unit(1,"dummy",field(10,0))
	setup.step()
	check(burrower.siege_state=="mobile" and setup.attack_waves.is_empty(),"burrow uses same two-scan confirmation")
	ticks(setup,ceili(float(config.scan_seconds)*rate))
	check(burrower.siege_state=="deploying","confirmed piercer starts burrowing")
	var spot: Vector2=burrower.pos
	ticks(setup,ceili(float(config.deploy_seconds)*rate)-1)
	check(setup.attack_waves.is_empty() and burrower.pos==spot,"burrowing forbids early attack and movement")
	setup.step()
	check(burrower.siege_state=="deployed","burrow completes after deploy_seconds")
	check(wait_until(setup,func(): return setup.attack_waves.size()==1,20)>0,"burrowed piercer launches attack")
	var hunter=setup.spawn_unit(1,"agent",burrower.pos+Vector2(6,0))
	wait_until(setup,func(): return burrower.hp<float(setup.catalog.piercer.hp),20)
	check(hunter.locked_target_id==burrower.id and burrower.hp<float(setup.catalog.piercer.hp),"burrowed unit remains visible and attackable")
	setup.units.erase(enemy)
	setup.units.erase(hunter)
	setup.step()
	check(burrower.siege_state=="packing","piercer emerges when no enemies remain")
	ticks(setup,ceili(float(config.pack_seconds)*rate)-1)
	check(burrower.pos==spot and burrower.siege_state=="packing","cannot move during emergence")
	setup.step()
	setup.step()
	check(burrower.siege_state=="mobile" and burrower.pos.x>spot.x,"movement resumes only after emerging")
	var base=bare()
	var base_weapon: Dictionary=base.definitions.piercer.primary_weapon_data
	var radius: float=float(base.rules.layout.base_radius)
	var attacker=base.spawn_unit(0,"piercer",base.base_pos(1)-Vector2(float(base_weapon.delivery.length)+radius-0.5,0))
	set_skill_state(base,attacker,"deployment","siege_state","deployed")
	var full: float=float(base.rules.base_hp)
	var launched := wait_until(base,func(): return not base.attack_waves.is_empty(),20)
	base.step()
	check(launched>0 and base.bases[1]==full,"base waits for wave to reach its edge")
	wait_until(base,func(): return base.bases[1]<full,40)
	var regen_tick: float=float(base.rules.base_regen_per_second)/float(base.rules.tick_rate)
	check(is_equal_approx(base.bases[1],full-float(base_weapon.damage)+regen_tick),"base takes delayed wave damage near maximum length")
	var multi=bare()
	tune(multi,"dummy",{"speed":0,"damage":0,"hp":1000})
	var source=multi.spawn_unit(0,"piercer",field(0,0))
	var victim=multi.spawn_unit(1,"dummy",field(4,0))
	LineAttack.launch(multi,source,victim.pos)
	LineAttack.launch(multi,source,victim.pos)
	multi.units.erase(source)
	ticks(multi,30)
	check(victim.hp==1000-2*multi.expected_damage(multi.definitions.piercer.primary_weapon_data,victim),"separate waves each hit once without duplicate damage")

## 巨像横向双束传播与可配置技能复用，不保证必中。两段扫射在出手时长内先后发出、方向相反。
func _colossi_and_skills() -> void:
	for team in range(2):
		var sim=bare()
		tune(sim,"rifle",{"speed":0,"damage":0,"hp":1000,"skills":{}})
		tune(sim,"dummy",{"speed":0,"damage":0,"hp":1000})
		var weapon: Dictionary=sim.definitions.colossus.primary_weapon_data
		var half_length: float=float(weapon.delivery.length)*0.5
		var half_width: float=float(weapon.delivery.half_width)
		var forward: float=1 if team==0 else -1
		var giant=sim.spawn_unit(team,"colossus",field(0,0))
		var x: float=forward*6.0
		var center=sim.spawn_unit(1-team,"rifle",field(x,0))
		var top=sim.spawn_unit(1-team,"rifle",field(x,-1.5))
		var bottom=sim.spawn_unit(1-team,"dummy",field(x,1.5))
		var width_edge=sim.spawn_unit(1-team,"dummy",field(x+forward*(half_width-0.001),0.8))
		var off_line=sim.spawn_unit(1-team,"dummy",field(x+forward*(half_width+0.01),1.2))
		var end=sim.spawn_unit(1-team,"dummy",field(x,half_length-0.001))
		var outside=sim.spawn_unit(1-team,"dummy",field(x,half_length+0.01))
		var friend=sim.spawn_unit(team,"dummy",field(x,1.0))
		var light_hit: float=sim.expected_damage(weapon,center)
		var heavy_hit: float=sim.expected_damage(weapon,bottom)
		var log: Dictionary={}
		var waves: Dictionary={}
		for i in range(40):
			for event in sim.step():
				if event.type=="attack_hit" and event.team==team:
					if not log.has(event.id):log[event.id]=[]
					log[event.id].append([sim.tick,int(event.strike)])
			for wave in sim.attack_waves:waves["%d:%d" % [int(wave.born),int(wave.strike)]]=wave
			if i==0:
				check(sim.attack_waves.is_empty() and not giant.has("siege_state"),"colossus starts its sweep without deployment or instant waves")
		var first_round: Array=waves.values().filter(func(w): return int(w.born)<=sim.tick-20)
		check(first_round.size()==2 and int(first_round[0].born)!=int(first_round[1].born),"one attack emits two sweeps at separate strike times")
		check(first_round.size()==2 and first_round[0].direction.is_equal_approx(-first_round[1].direction) and is_zero_approx(first_round[0].direction.dot(Vector2(forward,0))),"sweeps start at opposite sides perpendicular to aim")
		check(giant.locked_target_id==center.id,"sweep locks primary target")
		var first_tick := func(unit): return int(log[unit.id][0][0]) if log.has(unit.id) else 1000000
		check(first_tick.call(top)<first_tick.call(center) and first_tick.call(bottom)<first_tick.call(center),"outer enemies receive a sweep before center")
		var center_hits: Array=log.get(center.id,[]).filter(func(h): return int(h[0])<=sim.tick-20)
		check(center_hits.size()==2 and center_hits[0][1]!=center_hits[1][1] and center_hits[0][0]!=center_hits[1][0],"center receives two distinct strikes at different times")
		check(top.hp<=1000-2*light_hit and bottom.hp<=1000-2*heavy_hit and end.hp<=1000-2*heavy_hit,"both beams cross entire fixed transverse segment")
		check(width_edge.hp<1000 and off_line.hp==1000 and outside.hp==1000,"transverse width and length boundaries")
		check(friend.hp==1000,"sweeps ignore friendly units")
		var cycle: int=roundi((float(weapon.attack_duration)+float(weapon.interval))*float(sim.rules.tick_rate))
		var borns: Array=[]
		for key in waves:borns.append(int(waves[key].born))
		borns.sort()
		check(borns.size()>=4 and borns[2]-borns[0]==cycle and borns[3]-borns[1]==cycle,"double attack shares one cooldown; next cycle launches exactly two sweeps")
	var dodge=bare()
	tune(dodge,"rifle",{"speed":0,"damage":0,"skills":{}})
	var giant=dodge.spawn_unit(0,"colossus",field(0,0))
	var target=dodge.spawn_unit(1,"rifle",field(6,0))
	wait_until(dodge,func(): return not dodge.attack_waves.is_empty(),20)
	target.pos.x+=2.0
	dodge.units.erase(giant)
	ticks(dodge,40)
	check(target.hp==float(dodge.catalog.rifle.hp) and dodge.attack_waves.is_empty(),"sweep stays fixed and can miss even after shooter disappears")
	# 侧翼单位第一次受击后离开横线，可躲开另一束，证明两段独立结算。
	var partial=bare()
	tune(partial,"rifle",{"speed":0,"damage":0,"hp":1000,"skills":{}})
	var shooter=partial.spawn_unit(0,"colossus",field(0,0))
	partial.spawn_unit(1,"rifle",field(6,0))
	var side=partial.spawn_unit(1,"rifle",field(6,-1.5))
	var single: float=partial.expected_damage(partial.definitions.colossus.primary_weapon_data,side)
	wait_until(partial,func(): return side.hp<1000,30)
	check(side.hp==1000-single,"first side hit deals one strike")
	side.pos.x+=2.0
	partial.units.erase(shooter)
	ticks(partial,40)
	check(side.hp==1000-single,"side target can dodge the second strike")
	# 相同技能挂载到全新 ID，仍然可以三重直线攻击并保留部署要求。
	var reuse=bare()
	reuse.catalog["borrowed"]=reuse.catalog.piercer.duplicate(true)
	reuse.catalog.borrowed.skills.multi_attack={"count":3}
	tune(reuse,"dummy",{"speed":0,"damage":0,"hp":1000})
	var custom=reuse.spawn_unit(0,"borrowed",field(0,0))
	var victim=reuse.spawn_unit(1,"dummy",field(4,0))
	reuse.step()
	check(custom.siege_state=="mobile" and reuse.attack_waves.is_empty(),"copied deployment skill gates another unit ID")
	var config: Dictionary=reuse.catalog.piercer.skills.deployment
	ticks(reuse,ceili((float(config.scan_seconds)+float(config.deploy_seconds))*float(reuse.rules.tick_rate)))
	var launched: Dictionary={}
	for i in range(20):
		reuse.step()
		for wave in reuse.attack_waves:launched["%d:%d" % [int(wave.born),int(wave.strike)]]=true
	check(custom.siege_state=="deployed" and launched.size()==3,"copied line and multi-attack skills compose")
	check(victim.hp==1000-3*reuse.expected_damage(reuse.definitions.piercer.primary_weapon_data,victim),"three independent line hits apply to borrowed unit")
	# 普通单体攻击也能复用多段，不依赖波形攻击。
	var instant=bare()
	instant.catalog["borrowed"]=instant.catalog.rifle.duplicate(true)
	instant.catalog.borrowed.skills={"multi_attack":{"count":2}}
	tune(instant,"rifle",{"speed":0,"damage":0,"hp":1000,"skills":{}})
	instant.spawn_unit(0,"borrowed",field(0,0))
	var light=instant.spawn_unit(1,"rifle",field(4,0))
	var instant_hits := 0
	for i in range(strike_ticks(instant,"rifle")):
		instant_hits+=instant.step().filter(func(e): return e.type=="attack_hit" and e.team==0).size()
	check(light.hp==1000-2*instant.expected_damage(instant.definitions.borrowed.primary_weapon_data,light) and instant_hits==2,"ordinary weapon supports two separate strikes")
	var base=bare()
	var base_weapon: Dictionary=base.definitions.colossus.primary_weapon_data
	base.spawn_unit(0,"colossus",base.base_pos(1)-Vector2(float(base_weapon.range)+float(base.rules.layout.base_radius)-0.5,0))
	var full: float=float(base.rules.base_hp)
	var regen_tick: float=float(base.rules.base_regen_per_second)/float(base.rules.tick_rate)
	var base_hits: Array=[]
	for i in range(30):
		var before: float=base.bases[1]
		base.step()
		if base.bases[1]<before:base_hits.append(base.tick)
		if i==0:check(base.bases[1]==full,"base receives no instant beam damage")
	check(base_hits.size()==2 and base_hits[0]!=base_hits[1],"base receives both delayed beams separately")
	check(is_equal_approx(base.bases[1],minf(full,full-2*float(base_weapon.damage)+regen_tick*(30-base_hits[0]+1))),"each beam deals base damage once")
	# 全局旋转后的横线仍垂直于发射方向，不固定在屏幕上下方向。
	var diagonal=bare()
	var rotated=diagonal.spawn_unit(0,"colossus",field(0,-4))
	var goal=field(5,2)
	LineAttack.launch(diagonal,rotated,goal)
	var direction: Vector2=(goal-rotated.pos).normalized()
	check(is_zero_approx(diagonal.attack_waves[0].direction.dot(direction)) and diagonal.attack_waves[0].origin.lerp(diagonal.attack_waves[1].origin,0.5).is_equal_approx(goal),"transverse sweep rotates around target with aim")

## 掠夺者：单体榴弹、普通索敌、重甲加成；一格购买即一队（spawn_count）。
func _marauders() -> void:
	var sim = bare()
	var squad: int = int(sim.catalog.marauder.get("spawn_count",1))
	check(squad==4 and sim.formation_cost(formation("marauder",1))==int(sim.catalog.marauder.cost) and sim.validate_formation(formation("marauder",1),600)=="", "one marauder squad of four fits a 600 budget")
	tune(sim,"marauder",{"skills":{}})
	tune(sim,"rifle",{"speed":0,"damage":0,"hp":1000,"skills":{}})
	tune(sim,"dummy",{"speed":0,"hp":1000})
	var weapon: Dictionary = sim.definitions.marauder.primary_weapon_data
	var shooter = sim.spawn_unit(0,"marauder",field(0,0))
	var light = sim.spawn_unit(1,"rifle",field(4.5,0))
	var heavy = sim.spawn_unit(1,"dummy",field(5.2,0))
	wait_until(sim,func(): return light.hp<1000,30)
	check(light.hp==1000-sim.expected_damage(weapon,light) and heavy.hp==1000 and shooter.locked_target_id==light.id,"marauder targets nearest and has no splash")
	var first_tick: int = sim.tick
	var after: float = light.hp
	var gap := wait_until(sim,func(): return light.hp<after,80)
	var cycle: float = (float(weapon.attack_duration)+float(weapon.interval))*float(sim.rules.tick_rate)
	check(gap>=floori(cycle) and gap<=ceili(cycle),"marauder waits full attack duration plus interval (%d ticks)" % gap)
	light.pos.x = shooter.pos.x+float(weapon.range)*1.6
	shooter.cooldown = 0
	wait_until(sim,func(): return heavy.hp<1000,80)
	check(heavy.hp==1000-sim.expected_damage(weapon,heavy) and sim.expected_damage(weapon,heavy)>float(weapon.damage) and shooter.locked_target_id==heavy.id,"marauder switches after range exit and adds heavy bonus")
	var armor = bare()
	tune(armor,"marauder",{"skills":{},"speed":0,"damage":0})
	tune(armor,"rifle",{"skills":{},"speed":0})
	var marauder = armor.spawn_unit(0,"marauder",field(0,0))
	armor.spawn_unit(1,"rifle",field(4,0))
	wait_until(armor,func(): return marauder.hp<float(armor.catalog.marauder.hp),30)
	check(marauder.hp==float(armor.catalog.marauder.hp)-(float(armor.catalog.rifle.damage)-float(armor.catalog.marauder.armor)),"marauder armor points reduce rifle damage")
	var found := false
	for seed_value in range(32):
		var army = AI.new(seed_value).choose(formation("marauder",4),2400)
		check(sim.validate_formation(army,2400)=="","AI handles marauder roster seed %d" % seed_value)
		for slot in army:
			found = found or slot.kind=="marauder"
	check(found,"AI can purchase marauder")
	# 回归：买不起需要瓦斯的辅助兵种时，电脑仍按随机池选兵，不会只买最便宜的兵种。
	var kinds: Dictionary = {}
	for seed_value in range(8):
		for slot in AI.new(seed_value).buy_list([],[],3000,0):kinds[slot.kind]=true
	check(kinds.size()>=3 and not kinds.has("medic"),"AI without gas still buys a varied roster")

## 强化剂与减速必须独立于兵种 ID，按模拟时钟到期并维持同时行动公平。
func _stimulant_and_slow() -> void:
	var rate: float = float(Catalog.rules().tick_rate)
	var stim = bare()
	tune(stim,"dummy",{"speed":0,"damage":0,"hp":100000})
	var config: Dictionary = stim.catalog.marauder.skills.stimulant
	var cost: float = float(config.health_cost)
	var duration: int = ceili(float(config.duration)*rate)
	var max_hp: float = float(stim.catalog.marauder.hp)
	var base_speed: float = float(stim.catalog.marauder.speed)
	var caster = stim.spawn_unit(0,"marauder",field(0,0))
	var target = stim.spawn_unit(1,"dummy",field(4,0))
	var events: Array = stim.step()
	check(caster.hp==max_hp-cost and caster.stim_until_tick==stim.tick+duration,"stim costs health_cost and lasts duration")
	check(events.filter(func(e):return e.type=="skill_used").size()==1 and stim.damage_done[1]==0,"stim cost is one skill event, not enemy damage")
	check(is_equal_approx(stim.skill_system.movement_multiplier(stim,caster),float(config.speed_multiplier)),"stim grants movement speed multiplier")
	var weapon: Dictionary = stim.definitions.marauder.primary_weapon_data
	var shots: Array = []
	var casts := 0
	var before_hp: float = target.hp
	for i in range(120):
		for event in stim.step():
			casts += 1 if event.type=="skill_used" else 0
		if target.hp<before_hp:shots.append(stim.tick)
		before_hp=target.hp
	var stim_cycle: float = (float(weapon.attack_duration)+float(weapon.interval))/float(config.attack_multiplier)*rate
	check(casts==0 and caster.hp==max_hp-cost,"stim neither stacks nor recasts while active")
	check(shots.size()>=3 and shots[2]-shots[1]>=floori(stim_cycle) and shots[2]-shots[1]<=ceili(stim_cycle),"stim attack multiplier shortens the whole round")
	stim.tick = int(caster.stim_until_tick)-1
	stim.step()
	check(caster.hp==max_hp-cost*2 and caster.stim_until_tick==stim.tick+duration,"stim can renew after expiration if still fighting")
	stim.units.erase(target)
	stim.tick = int(caster.stim_until_tick)-1
	stim.step()
	check(is_equal_approx(stim._movement_speed(caster),base_speed),"stim expires without combat and restores base speed")
	check(caster.hp==max_hp-cost*2,"stim does not consume health without enemy target")
	var low = bare()
	tune(low,"dummy",{"speed":0,"damage":0,"hp":1000})
	var fragile = low.spawn_unit(0,"marauder",field(0,0))
	var foe = low.spawn_unit(1,"dummy",field(4,0))
	fragile.hp=cost
	wait_until(low,func(): return foe.hp<1000,30)
	check(fragile.hp==cost and not fragile.has("stim_until_tick") and foe.hp<1000,"low health blocks stimulant but still permits firing")
	var base = bare()
	var sieger = base.spawn_unit(0,"marauder",base.base_pos(1)-Vector2(float(weapon.range)+float(base.rules.layout.base_radius)-0.5,0))
	wait_until(base,func(): return base.bases[1]<float(base.rules.base_hp),40)
	check(sieger.hp==max_hp and not sieger.has("stim_until_tick") and base.bases[1]<float(base.rules.base_hp),"base alone does not trigger stimulant")
	for reverse in range(2):
		var healing = bare()
		tune(healing,"dummy",{"speed":0,"damage":0,"hp":100000})
		tune(healing,"medic",{"speed":0})
		var heal: float = float(healing.definitions.medic.primary_weapon_data.healing)
		var pulse: int = ceili(float(healing.definitions.medic.primary_weapon_data.delivery.tick_interval)*rate)
		if reverse==0:healing.spawn_unit(0,"medic",field(-2,0))
		var ally = healing.spawn_unit(0,"marauder",field(0,0))
		if reverse==1:healing.spawn_unit(0,"medic",field(-2,0))
		healing.spawn_unit(1,"dummy",field(4,0))
		healing.step()
		check(ally.hp==max_hp-cost,"medic cannot see future stim cost, order %d" % reverse)
		ticks(healing,pulse)
		check(ally.hp==max_hp-cost+heal,"medic heals stim cost on its first pulse, order %d" % reverse)
	# 比较不同单位处理顺序；首次命中的同一步仍走完整基础速度，下一步才减速。
	var slow_config: Dictionary = Catalog.units().marauder.skills.on_hit_slow
	var slow_ticks: int = ceili(float(slow_config.duration)*rate)+1
	for reverse in range(2):
		var slow = bare()
		tune(slow,"marauder",{"speed":0,"skills":{"on_hit_slow":slow_config}})
		tune(slow,"swarm",{"damage":0,"hp":1000})
		var victim: Dictionary
		if reverse==0:victim=slow.spawn_unit(1,"swarm",field(5.5,0))
		var attacker = slow.spawn_unit(0,"marauder",field(0,0))
		if reverse==1:victim=slow.spawn_unit(1,"swarm",field(5.5,0))
		var swarm_speed: float = float(slow.catalog.swarm.speed)/rate
		var start: Vector2 = victim.pos
		wait_until(slow,func(): return victim.hp<1000,30)
		var hit_tick: int = slow.tick
		check(is_equal_approx(victim.pos.distance_to(victim.prev),swarm_speed),"on-hit slow does not alter already decided movement order %d" % reverse)
		attacker.cooldown=1000
		slow.units.erase(attacker)
		slow.step()
		check(is_equal_approx(victim.pos.distance_to(victim.prev),swarm_speed*float(slow_config.speed_multiplier)) and victim.pos!=start,"slow applies next tick and survives source removal order %d" % reverse)
		slow.tick=hit_tick+slow_ticks-2
		slow.step()
		check(is_equal_approx(slow._movement_speed(victim),float(slow.catalog.swarm.speed)*float(slow_config.speed_multiplier)),"slow includes entire final tick order %d" % reverse)
		slow.step()
		check(is_equal_approx(slow._movement_speed(victim),float(slow.catalog.swarm.speed)),"slow expires after exactly duration movement ticks order %d" % reverse)
	var refresh = bare()
	tune(refresh,"dummy",{"speed":0,"damage":0,"hp":1000})
	tune(refresh,"marauder",{"skills":{"on_hit_slow":slow_config}})
	var a = refresh.spawn_unit(0,"marauder",field(0,0))
	var b = refresh.spawn_unit(1,"dummy",field(4,0))
	wait_until(refresh,func(): return b.hp<1000,30)
	var first_hp: float = b.hp
	a.cooldown=0
	wait_until(refresh,func(): return b.hp<first_hp,60)
	check(b.slow_multiplier==float(slow_config.speed_multiplier) and b.slow_until_tick==refresh.tick+slow_ticks,"repeated hits refresh slow without multiplying it")
	var both = bare()
	var left = both.spawn_unit(0,"marauder",field(-2.5,0))
	var right = both.spawn_unit(1,"marauder",field(2.5,0))
	wait_until(both,func(): return left.has("slow_until_tick"),40)
	check(left.hp==right.hp and is_equal_approx(both._movement_speed(left),base_speed*float(config.speed_multiplier)*float(slow_config.speed_multiplier)),"simultaneous stim and slow multiply speed symmetrically")
	var snapshot: Dictionary=both.get_snapshot()
	snapshot.units[0].slow_until_tick=0
	check(left.slow_until_tick>0,"snapshot status changes cannot mutate simulation")
	# 减速光束只有实际命中才施加减速；改名兵种仍可组合多段攻击和被动。
	var wave = bare()
	wave.catalog["borrowed_slow"] = wave.catalog.colossus.duplicate(true)
	wave.catalog.borrowed_slow.skills.on_hit_slow={"speed_multiplier":0.5,"duration":2}
	tune(wave,"dummy",{"speed":0,"damage":0,"hp":1000})
	wave.spawn_unit(0,"borrowed_slow",field(0,0))
	var center=wave.spawn_unit(1,"dummy",field(6,0))
	wait_until(wave,func(): return not wave.attack_waves.is_empty(),20)
	check(not center.has("slow_until_tick"),"line attack does not slow before arrival")
	var strikes: Array = []
	for i in range(30):
		for event in wave.step():
			if event.type=="attack_hit" and event.id==center.id:strikes.append(wave.tick)
	check(strikes.size()>=2 and center.slow_multiplier==0.5,"each delayed hit applies the same nonstacking slow on actual impact")
	var support = bare()
	var medic = support.spawn_unit(0,"medic",field(0,0))
	medic.slow_until_tick=100
	medic.slow_multiplier=0.5
	support.step()
	check(is_equal_approx(medic.pos.distance_to(medic.prev),float(support.catalog.medic.speed)*0.5/rate),"support movement also respects reusable slow")
	var renamed = bare()
	renamed.catalog["borrowed_stim"] = renamed.catalog.rifle.duplicate(true)
	renamed.catalog.borrowed_stim.skills={"stimulant":renamed.catalog.marauder.skills.stimulant.duplicate(true)}
	tune(renamed,"dummy",{"speed":0,"damage":0})
	var borrowed=renamed.spawn_unit(0,"borrowed_stim",field(0,0))
	renamed.spawn_unit(1,"dummy",field(4,0))
	renamed.step()
	check(borrowed.hp==float(renamed.catalog.rifle.hp)-cost and borrowed.has("stim_until_tick"),"stimulant can be assigned to another unit without ID checks")
	var entry = bare()
	tune(entry,"dummy",{"speed":0,"damage":0,"hp":1000})
	var approaching = entry.spawn_unit(0,"marauder",field(0,0))
	entry.spawn_unit(1,"dummy",field(float(weapon.range)+0.1,0))
	approaching.cooldown=10
	entry.step()
	check(not approaching.has("stim_until_tick"),"discovery alone does not trigger stimulant")
	entry.step()
	check(approaching.hp==max_hp-cost and approaching.cooldown>0,"first combat tick activates stimulant even while attack is cooling down")
	approaching.hp=cost
	entry.tick=int(approaching.stim_until_tick)-1
	entry.step()
	check(approaching.hp==cost and is_equal_approx(entry.skill_system.movement_multiplier(entry,approaching),1.0) and not entry.skill_system.get_component(approaching,"stimulant").active_at(entry.tick),"expired stimulant rechecks health and cannot renew at lethal cost")

## 解放者：空中层、对空普通武器、防卫模式展开时序、前向扇形内对地与不攻击基地。
func _liberators() -> void:
	for team in range(2):
		var sim = bare()
		tune(sim,"dummy",{"speed":0,"damage":0,"hp":10000})
		var config: Dictionary = sim.catalog.liberator.skills.defender_zone
		var zone_weapon: Dictionary = config.weapon
		var reach: float = float(zone_weapon.range)
		var angle: float = float(config.angle_degrees)
		var rate: float = float(sim.rules.tick_rate)
		var forward: float = 1 if team == 0 else -1
		var ship = sim.spawn_unit(team,"liberator",field(0,0))
		var start: Vector2 = ship.pos
		var near = sim.spawn_unit(1-team,"dummy",field(forward*12,0))
		var aside: float = 12.0*tan(deg_to_rad(angle*0.5+5.0))
		var outside = sim.spawn_unit(1-team,"dummy",field(forward*12,aside))
		var zone = sim.skill_system.get_component(ship,"defender_zone")
		sim._build_buckets()
		check(sim._target(ship).is_empty(),"mobile liberator cannot target ground %d" % team)
		check(sim._target(near).is_empty(),"ground-only dummy cannot target air %d" % team)
		sim.step()
		check(ship.siege_state=="mobile" and ship.pos==start,"liberator stops to scan ground target %d" % team)
		ticks(sim,ceili(float(config.scan_seconds)*rate))
		check(ship.siege_state=="deploying","confirmed ground target starts defender mode %d" % team)
		check(zone.in_sector(ship,near.pos,reach,angle) and not zone.in_sector(ship,outside.pos,reach,angle),"forward sector covers target, excludes flank %d" % team)
		ticks(sim,ceili(float(config.deploy_seconds)*rate)-1)
		check(near.hp==10000 and ship.siege_state=="deploying","defender transform takes deploy_seconds %d" % team)
		sim.step()
		check(ship.siege_state=="deployed","defender mode completes %d" % team)
		wait_until(sim,func(): return near.hp<10000,40)
		check(near.hp==10000-sim.expected_damage(zone_weapon,near),"deployed liberator hits ground target in zone %d" % team)
		check(outside.hp==10000,"ground target outside zone is ignored %d" % team)
		check(ship.pos==start,"defender mode is stationary %d" % team)
		near.pos = ship.pos+Vector2(forward*12,-aside)
		var hp: float = near.hp
		ship.cooldown = 0
		ticks(sim,ceili((float(zone_weapon.attack_duration)+float(zone_weapon.interval))*rate))
		check(near.hp==hp and ship.locked_target_id==0,"target leaving zone releases lock %d" % team)
	var air = bare()
	var hunter = air.spawn_unit(0,"liberator",field(0,0))
	var prey = air.spawn_unit(1,"liberator",field(4,0))
	var wing = air.spawn_unit(1,"liberator",field(4,1.0))
	tune(air,"liberator",{"speed":0})
	var anti_air: Dictionary = air.definitions.liberator.primary_weapon_data
	wait_until(air,func(): return prey.hp<float(air.catalog.liberator.hp) or wing.hp<float(air.catalog.liberator.hp),30)
	check(hunter.siege_state=="mobile" and prey.hp==float(air.catalog.liberator.hp)-air.expected_damage(anti_air,prey) and wing.hp==float(air.catalog.liberator.hp),"mobile liberator hits nearest air target; anti-air burst has no splash")
	var rifle_sim = bare()
	var rifle = rifle_sim.spawn_unit(0,"rifle",field(0,0))
	var flyer = rifle_sim.spawn_unit(1,"liberator",field(4,0))
	rifle_sim._build_buckets()
	check(rifle_sim._target(rifle).get("id",0)==flyer.id,"anti-air rifle targets liberator")
	var siege = bare()
	var raider = siege.spawn_unit(0,"liberator",siege.base_pos(1)-Vector2(4,0))
	ticks(siege,200)
	check(siege.bases[1]==float(siege.rules.base_hp) and raider.siege_state=="mobile","liberator never attacks base")

## 永久兵营的买、卖、移动与退款规则；动作写入战报并可按 tick 重放。
func _economy() -> void:
	var funds := 1000
	var sim = bare(42,{"start_minerals":funds})
	var cost: Dictionary = {}
	for kind in ["dummy","agent","rifle","hellbat"]:cost[kind]=int(sim.catalog[kind].cost)
	check(sim.buy(0,"dummy",5)=="" and sim.minerals[0]==funds-cost.dummy,"buy deducts cost immediately")
	check(sim.buy(0,"rifle",5)!="" and sim.minerals[0]==funds-cost.dummy,"cannot buy into occupied cell")
	check(sim.buy(0,"gate_tower",6)!="" and sim.buy(0,"unknown",6)!="","cannot buy unknown kinds")
	check(sim.refund_value(0,5)==cost.dummy and sim.sell(0,5)=="" and sim.minerals[0]==funds,"undeployed unit refunds 100 percent")
	check(sim.sell(0,5)!="","cannot sell empty cell")
	sim.buy(0,"dummy",5)
	sim.buy(0,"agent",0)
	check(sim.move(0,5,11)=="" and sim.move(0,0,11)=="" and sim.formations[0].any(func(s): return s.kind=="dummy" and s.cell==0),"move swaps cells for free")
	var spent: int = funds-cost.dummy-cost.agent
	check(sim.minerals[0]==spent,"moves cost nothing")
	var income_ticks: int = int(float(sim.rules.economy.income_seconds)*float(sim.rules.tick_rate))
	ticks(sim,int(sim.next_wave_tick)+1)
	var paid: int = (sim.tick/income_ticks)*sim.economy.base_income(0)
	check(sim.is_deployed(0,0) and sim.is_deployed(0,11) and sim.minerals[0]==spent+paid,"spawned units become deployed and timed income arrives")
	check(sim.move(0,0,1)=="" and sim.is_deployed(0,1),"moving keeps deployed status")
	var held: int = sim.minerals[0]
	check(sim.refund_value(0,1)==0 and sim.sell(0,1)=="" and sim.minerals[0]==held,"deployed unit can be cancelled without refund")
	sim.buy(0,"rifle",2)
	check(not sim.is_deployed(0,2) and sim.refund_value(0,2)==cost.rifle,"new purchase after a wave is undeployed again")
	# 整份提交：替换已出场单位不退款；矿物不足时整份拒绝，兵营不变。
	var before: Array = sim.formations[0].duplicate(true)
	held = sim.minerals[0]
	check(sim.submit_formation(0,[{"kind":"thor","cell":11},{"kind":"thor","cell":12},{"kind":"thor","cell":13}])!="" and sim.formations[0]==before and sim.minerals[0]==held,"unaffordable replacement is atomic")
	check(sim.submit_formation(0,[{"kind":"hellbat","cell":11},{"kind":"rifle","cell":2}])=="" and sim.minerals[0]==held-cost.hellbat,"replacing deployed unit charges full price without refund")
	sim.finished = true
	check(sim.buy(0,"rifle",3)!="" and sim.sell(0,2)!="" and sim.move(0,2,3)!="","finished match rejects edits")
	# 开局资金与出兵间隔来自 rules，可被开局设置覆盖；收入按定时经济发放，与出兵无关。
	var custom = bare(7,{"start_minerals":0,"wave_seconds":20})
	check(custom.minerals==[0,0] and custom.submit_formation(0,[{"kind":"rifle","cell":0}])!="","zero start funds reject purchases")
	ticks(custom,int(custom.next_wave_tick)+1)
	var first_paid: int = (custom.tick/income_ticks)*custom.economy.base_income(0)
	check(custom.wave==1 and custom.units.is_empty() and custom.minerals==[first_paid,first_paid],"first wave empty; timed income still paid")
	ticks(custom,20*int(custom.rules.tick_rate))
	check(custom.wave==2,"custom wave interval")
	check(custom.journal.settings.wave_seconds==20 and custom.journal.settings.start_minerals==0,"journal records match settings")
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
		shop.minerals[1] += 1000
	check(ok and shop.formations[1].size()==int(shop.rules.columns*shop.rules.rows),"AI buys incrementally within minerals until grid is full")

## 沙漠风暴周期经济：分档收入、停薪、气厂分流与上限、瓦斯兑换、中央井占领。预期值从 rules.economy 读取。
## 直接改 sim.wave 只为跳到指定阶段；测试期间始终早于首波出兵时刻，不会触发出兵。
func _desert_economy() -> void:
	var config: Dictionary = Catalog.rules().economy
	var tiers: Array = config.income_tiers
	var probe = bare(42,{"start_minerals":0})
	var tier_ok := true
	for index in range(tiers.size()):
		var tier: Dictionary = tiers[index]
		tier_ok = tier_ok and probe.economy.base_income(int(tier.wave))==int(tier.minerals)
		if index>0:tier_ok = tier_ok and probe.economy.base_income(int(tier.wave)-1)==int(tiers[index-1].minerals)
	check(tier_ok,"income tiers switch exactly at configured waves")
	var income_ticks: int = int(float(config.income_seconds)*float(probe.rules.tick_rate))
	var base: int = probe.economy.base_income(0)
	ticks(probe,income_ticks-1)
	check(probe.minerals==[0,0],"no income before the first income interval")
	ticks(probe,1)
	check(probe.minerals==[base,base],"both sides receive the same timed income")
	ticks(probe,income_ticks)
	check(probe.minerals==[2*base,2*base],"income repeats every income interval")
	var halted = bare(42,{"start_minerals":0,"wave_limit":int(config.income_stop_wave)+10})
	halted.wave = int(config.income_stop_wave)
	ticks(halted,income_ticks*2)
	check(halted.minerals==[0,0] and halted.economy.set_gasworks(halted,0,1)!="","income and gasworks stop at income_stop_wave")
	# 气厂：按当前阶段上限建造；每座把基础收入的固定比例转为瓦斯，矿物相应减少，不额外生成资源。
	var works = bare(42,{"start_minerals":0})
	var initial_limit: int = int(config.gasworks_initial_limit)
	var expanded_limit: int = int(config.gasworks_expanded_limit)
	check(works.economy.set_gasworks(works,0,initial_limit+1)!="" and works.economy.set_gasworks(works,0,-1)!="","gasworks above the initial limit are rejected")
	works.wave = int(config.gasworks_unlock_wave)
	check(works.economy.set_gasworks(works,0,expanded_limit)=="" and works.economy.set_gasworks(works,0,expanded_limit+1)!="","gasworks limit expands at the unlock wave")
	var split = bare(42,{"start_minerals":0})
	split.wave = int(tiers[1].wave)
	var count := 2
	check(split.economy.set_gasworks(split,0,count)=="","gasworks can be built within the limit")
	var tier_income: int = split.economy.base_income(split.wave)
	var diverted: int = int(round(tier_income*float(config.gasworks_fraction)*count))
	ticks(split,income_ticks)
	check(diverted>0 and split.minerals[0]==tier_income-diverted and split.economy.gas[0]==diverted,"gasworks divert part of base income into gas")
	check(split.minerals[1]==tier_income and split.economy.gas[1]==0,"opponent income is unaffected by our gasworks")
	check(split.economy.exchange_gas(split,0)=="" and split.minerals[0]==tier_income and split.economy.gas[0]==0,"gas exchanges back to minerals one to one")
	check(split.economy.exchange_gas(split,0)!="","exchange needs gas")
	var logged: Array = split.journal.actions.map(func(action): return str(action.type))
	check(logged.has("gasworks") and logged.has("exchange_gas"),"economy actions are journaled")
	# 中央井：开放前不占领；开放后最近的一方占领；无人或等距时保持原归属；结构体不能占领；控制方获得额外矿物。
	var well = bare(42,{"start_minerals":0})
	var runner = well.spawn_unit(0,"rifle",field(0,0))
	ticks(well,1)
	check(well.economy.center_owner==-1,"center cannot be captured before it opens")
	well.wave = int(config.center_unlock_wave)
	well.economy.last_scan_tick = -1
	runner.pos = field(0,0)
	runner.prev = runner.pos
	ticks(well,1)
	check(well.economy.center_owner==0 and well.journal.economy_events.any(func(event): return event.type=="center_captured" and int(event.team)==0),"nearest side captures the open center and it is journaled")
	var rates: Array = [well.economy.rates(0,well.wave),well.economy.rates(1,well.wave)]
	var open_income: int = well.economy.base_income(well.wave)
	check(int(rates[0].minerals)==open_income+int(config.center_bonus) and int(rates[1].minerals)==open_income,"center owner gets the bonus minerals")
	well.units.clear()
	well.spawn_unit(1,"rifle",field(0,0))
	well.economy.last_scan_tick = -1
	ticks(well,1)
	check(well.economy.center_owner==1,"the other side can take the center")
	well.units.clear()
	well.spawn_unit(0,"treasury",field(0,0))
	well.economy.last_scan_tick = -1
	ticks(well,1)
	check(well.economy.center_owner==1,"structures cannot capture and an empty center keeps its owner")
	# 等距判定若落到“否则归后者”，会把归属交给 1；先让 0 占领，才能检出这种偏向。
	well.units.clear()
	well.spawn_unit(0,"rifle",field(0,0))
	well.economy.last_scan_tick = -1
	ticks(well,1)
	well.units.clear()
	well.spawn_unit(0,"rifle",field(-1,0))
	well.spawn_unit(1,"rifle",field(1,0))
	well.economy.last_scan_tick = -1
	ticks(well,1)
	check(well.economy.center_owner==0,"equal distance keeps the previous owner")

## 最后一波后的胜负：先失去可攻击部队的一方失败；治疗单位不算；双方同时失去为平局；安全时限比较基地。
func _final_phase() -> void:
	var rules: Dictionary = Catalog.rules()
	var rate: int = int(rules.tick_rate)
	var first_tick: int = int(float(rules.first_wave_seconds)*rate)
	var wave_ticks: int = int(float(rules.wave_seconds)*rate)
	var quick = bare(42,{"wave_limit":2})
	quick.submit_formation(0,[{"kind":"dummy","cell":0}])
	wait_until(quick,func(): return quick.finished,first_tick+wave_ticks+10)
	check(quick.wave==2 and quick.final_wave_tick==first_tick+wave_ticks and quick.finished and quick.winner==0,"after final wave, side without attackers loses")
	var limited = bare(42,{"wave_limit":1})
	wait_until(limited,func(): return limited.finished,first_tick+10)
	check(limited.finished and limited.winner==-1 and limited.tick==first_tick,"both sides without attackers after final wave draw")
	var stop = bare(42,{"wave_limit":1})
	tune(stop,"dummy",{"speed":0})
	stop.spawn_unit(0,"dummy",field(-60,0))
	stop.spawn_unit(1,"dummy",field(60,0))
	ticks(stop,first_tick+1)
	var frozen: Array = stop.minerals.duplicate()
	ticks(stop,wave_ticks*2)
	check(stop.wave==1 and not stop.finished and stop.minerals==frozen and stop.economy.set_gasworks(stop,0,1)!="","no spawns or income after final wave")
	var medics = bare(42,{"wave_limit":1})
	tune(medics,"dummy",{"speed":0})
	medics.spawn_unit(0,"medic",field(-60,0))
	medics.spawn_unit(1,"dummy",field(60,0))
	wait_until(medics,func(): return medics.finished,first_tick+10)
	check(medics.finished and medics.winner==1,"medic-only side has no attackers")
	var capped = bare(42,{"wave_limit":1,"final_phase_max_seconds":10})
	tune(capped,"dummy",{"speed":0})
	capped.spawn_unit(0,"dummy",field(-60,0))
	capped.spawn_unit(1,"dummy",field(60,0))
	capped.bases=[9500.0,9000.0]
	ticks(capped,first_tick+10*rate-1)
	check(not capped.finished,"safety limit not reached early")
	capped.step()
	check(capped.finished and capped.winner==0,"safety limit compares base hp")
	var empty = Sim.new()
	var last_wave: int = int(rules.wave_limit)
	wait_until(empty,func(): return empty.finished,first_tick+(last_wave-1)*wave_ticks+10)
	check(empty.finished and empty.winner==-1 and empty.wave==last_wave and empty.final_wave_tick==first_tick+(last_wave-1)*wave_ticks,"default match runs wave_limit waves")

## 加速后的索敌必须与逐个比较的暴力搜索结果完全一致（含多武器单位、空地层、防卫圈与同距 ID）。
func _spatial_equivalence() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var kinds: Array = Catalog.units().keys()
	var mismatches := 0
	var compared := 0
	for trial in range(6):
		var sim = bare()
		var size := Vector2(float(sim.rules.world_width), float(sim.rules.world_height))
		for i in range(160):
			var unit = sim.spawn_unit(i % 2, kinds[rng.randi_range(0, kinds.size()-1)], Vector2(rng.randf_range(2,size.x-2), rng.randf_range(2,size.y-2)))
			for skill in ["deployment","defender_zone"]:
				if sim.skill_system.get_component(unit,skill) != null and rng.randf() < 0.5:
					set_skill_state(sim,unit,skill,"siege_state","deployed")
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
			var ground := _brute_ground(sim, unit, 40.0)
			if sim.nearest_ground_enemy(unit, 40.0).get("id", 0) != ground.get("id", 0):
				mismatches += 1
	check(mismatches == 0 and compared == 960, "spatial target search matches brute force (%d mismatches)" % mismatches)

## 与 _target 相同的发现半径（贴边射程加体型）与优先级规则，但逐个遍历全部单位。
func _brute_target(sim, unit: Dictionary) -> Dictionary:
	var weapon: Dictionary = sim._search_stats(unit)
	var discovery: float = float(weapon.range)
	if bool(weapon.get("range_from_edge",false)):
		discovery += sim.body_radius(unit)+sim.max_body_radius
	var radius: float = sim.skill_system.discovery_radius(sim,unit,discovery*1.5)
	var prioritized: bool = sim.skill_system.has_priority(unit)
	var best: Dictionary = {}
	var best_score := INF
	var best_weight := -1
	for other in sim.units:
		if other.team == unit.team or other.hp <= 0 or unit.pos.distance_to(other.pos) > radius or not sim._can_hit_unit(unit, other, weapon):
			continue
		var score: float = unit.pos.distance_to(other.pos)
		var weight: int = sim.skill_system.target_priority(sim,unit,other) if prioritized else 0
		if prioritized and weight <= 0:
			continue
		if weight > best_weight or (weight == best_weight and (score < best_score or (is_equal_approx(score, best_score) and int(other.id) < int(best.get("id", 2147483647))))):
			best = other
			best_score = score
			best_weight = weight
	if prioritized and best.is_empty():
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

## 基地防御层、宝库与可建造防御塔：中心对称、静止、攻击、灵核奖励、选址与建造上限、AI 规则。
func _structures() -> void:
	var sim = Sim.new()
	var center := Vector2(float(sim.rules.world_width), float(sim.rules.world_height))
	var kinds: Array = sim.units.map(func(u): return "%s:%d" % [u.kind,u.team])
	check(kinds.size()==2 and kinds.has("treasury:0") and kinds.has("treasury:1"),"each side starts with one treasury unit")
	check(sim.units[0].pos+sim.units[1].pos==center,"treasury positions are point-symmetric")
	var full: float = float(sim.rules.base_hp)+float(sim.catalog.gate_tower.hp)
	check(sim.bases==[full,full] and sim.base_has_defense(0) and sim.base_has_defense(1),"base starts with defense layer on top of core hp")
	check(sim.buy(0,"treasury",0)!="" and sim.buy(0,"tower",0)!="" and sim.buy(0,"gate_tower",0)!="" and sim.buy(0,sim.tower_kind(0),0)!="","structures are not purchasable roster units")
	# 基地防御层：不在 units 中，静止在基地中心，对地对空单体反击。
	var gate_weapon: Dictionary = sim.definitions.gate_tower.primary_weapon_data
	var gate_range: float = float(gate_weapon.range)
	var guard = Sim.new()
	guard.units = guard.units.filter(func(u): return u.kind!="treasury")
	tune(guard,"dummy",{"speed":0,"damage":0,"hp":10000})
	var raider = guard.spawn_unit(0,"dummy",guard.base_pos(1)-Vector2(gate_range-1.0,0))
	check(wait_until(guard,func(): return raider.hp<10000,40)>=0 and raider.hp==10000-guard.expected_damage(gate_weapon,raider),"base defense hits ground intruder for gate damage")
	check(guard.bases==[full,full],"structures never attack base")
	guard.units.erase(raider)
	var flyer = guard.spawn_unit(0,"liberator",guard.base_pos(1)-Vector2(gate_range-1.0,1.0))
	tune(guard,"liberator",{"speed":0})
	var flyer_hp: float = flyer.hp
	check(wait_until(guard,func(): return flyer.hp<flyer_hp,40)>=0,"base defense hits air")
	var treasury_enemy: Dictionary = sim.units.filter(func(u): return u.kind=="treasury" and u.team==1)[0]
	check(not sim._can_hit_unit(flyer,treasury_enemy,sim.catalog.liberator.skills.defender_zone.weapon),"liberator cannot attack structures")
	# 防御层在基地生命跌到核心上限时永久失效，此后基地没有反击，回血改为核心回血。
	var open = Sim.new()
	open.units.clear()
	open.bases[1] = float(open.rules.base_hp)+1.0
	tune(open,"dummy",{"speed":0,"hp":10000})
	var intruder = open.spawn_unit(0,"dummy",open.base_pos(1)-Vector2(1.0+float(open.catalog.dummy.range)*0.5,0))
	var lost := false
	for i in range(60):
		for event in open.step():
			if event.type=="base_defense_lost" and event.team==1:lost=true
	check(lost and not open.base_has_defense(1) and open.base_max_hp(1)==float(open.rules.base_hp),"defense layer is lost permanently at core hp")
	var hp_after: float = intruder.hp
	ticks(open,40)
	check(intruder.hp==hp_after and open.bases[1]<float(open.rules.base_hp),"base without defense layer cannot fight back")
	# 宝库：反击弱；摧毁后攻击方得灵核奖励，不计击杀，只奖励一次。
	var loot = Sim.new()
	var treasury: Dictionary = loot.units.filter(func(u): return u.kind=="treasury" and u.team==1)[0]
	var treasury_weapon: Dictionary = loot.definitions.treasury.primary_weapon_data
	tune(loot,"agent",{"speed":0,"hp":10000})
	var looter = loot.spawn_unit(0,"agent",treasury.pos-Vector2(float(treasury_weapon.range)-0.5,0))
	check(wait_until(loot,func(): return looter.hp<10000,60)>=0 and looter.hp==10000-loot.expected_damage(treasury_weapon,looter),"treasury counterattack is weak")
	treasury.hp = 1
	treasury.shield = 0
	var destroyed := false
	for i in range(200):
		for event in loot.step():
			if event.type=="structure_destroyed" and event.kind=="treasury" and event.team==1:destroyed=true
		if destroyed:break
	var reward: int = int(loot.rules.economy.outpost_core_reward)
	check(destroyed and not loot.units.has(treasury) and loot.economy.cores==[reward,0] and loot.kills==[0,0],"destroying treasury rewards attacker cores once without kill credit")
	ticks(loot,10)
	check(loot.economy.cores==[reward,0],"treasury reward is not repeated")
	# 可建造防御塔：种族专用、扣矿、选址校验、每局一次、被摧毁不给奖励。
	var build = Sim.new(42,{"races":["terran","terran"],"start_minerals":600})
	var tower_kind: String = build.tower_kind(0)
	var tower_cost: int = int(build.catalog[tower_kind].cost)
	check(tower_kind=="terran_bunker" and tower_cost==600,"terran bunker costs 600 minerals")
	var middle: float = float(build.rules.world_width)*0.5
	check(build.tower_error(0,Vector2(middle,40))!="" and build.tower_error(0,build.base_pos(0))!="" and build.tower_error(0,build.layout_pos(0,"treasury"))!="" and build.tower_error(0,Vector2(0.5,40))!="","tower placement rejects midline, base, treasury and border")
	check(build.tower_error(0)=="" and build.build_tower(0)=="" and build.minerals[0]==0,"exact bunker price can be spent to build")
	var built: Dictionary = build.units.filter(func(u): return u.kind==tower_kind)[0]
	check(built.team==0 and built.pos==build.layout_pos(0,"tower"),"tower without position uses layout site")
	build.minerals[0] = 5000
	check(build.build_tower(0)!="" and build.minerals[0]==5000,"only one tower per match")
	built.hp = 1
	tune(build,"rifle",{"speed":0,"hp":100000,"skills":{}})
	build.spawn_unit(1,"rifle",built.pos+Vector2(3.0,0))
	wait_until(build,func(): return not build.units.has(built),60)
	check(not build.units.has(built) and build.economy.cores==[0,0] and build.kills[1]==0 and build.build_tower(0)!="","destroyed tower gives no reward and cannot be rebuilt")
	var poor = Sim.new(42,{"races":["terran","terran"],"start_minerals":tower_cost-1})
	check(poor.build_tower(1)!="" and poor.minerals[1]==tower_cost-1 and poor.tower_builds==[0,0],"unaffordable bunker spends neither minerals nor build allowance")
	check(build.journal.actions.any(func(a): return a.type=="build_tower" and a.team==0),"tower build is journaled")
	# 医疗兵不治疗结构体；结构体不算最后阶段的可攻击部队。
	var care = Sim.new()
	var own_treasury: Dictionary = care.units.filter(func(u): return u.kind=="treasury" and u.team==0)[0]
	own_treasury.hp = 100
	care.spawn_unit(0,"medic",own_treasury.pos+Vector2(2,0))
	ticks(care,20)
	check(own_treasury.hp<=100+float(care.catalog.treasury.health_regen)+0.01 and care.combat_units(0)==0,"medics ignore structures; structures are not combat units")
	# 带结构体的镜像对局仍然完全对称。
	var mirror = Sim.new(42,{"start_minerals":2000})
	mirror.submit_formation(0,Catalog.starter())
	mirror.submit_formation(1,Catalog.starter())
	mirror.build_tower(0)
	mirror.build_tower(1)
	ticks(mirror,int(float(mirror.rules.first_wave_seconds)*float(mirror.rules.tick_rate))+1200)
	var hp: Array = [0.0,0.0]
	for unit in mirror.units:
		hp[unit.team] += float(unit.hp)
	check(is_equal_approx(mirror.bases[0],mirror.bases[1]) and mirror.kills[0]==mirror.kills[1] and is_equal_approx(hp[0],hp[1]) and mirror.minerals[0]==mirror.minerals[1],"mirror battle with structures has no side advantage")
	# AI：落后（对方上一波总价高于自己兵营）且未建塔时优先建塔，买不起就攒矿。
	var ai = AI.new()
	var bunker: int = int(ai.catalog[Catalog.tower_kind(ai.race)].cost)
	check(ai.wants_tower(Catalog.starter(),[],bunker,0) and not ai.wants_tower([],[],bunker,0) and not ai.wants_tower(Catalog.starter(),[],bunker,1),"AI builds tower only when behind and allowed")
	check(ai.tower_plan(Catalog.starter(),[],bunker-1,0)=="save","AI saves minerals for tower when behind")
	check(not ai.wants_tower(Catalog.starter(),Catalog.starter(),2000,0),"AI skips tower when roster is not behind")
	_terran_bunker()

func _terran_bunker() -> void:
	var sim = bare()
	tune(sim, "medivac", {"speed":0, "hp":5000, "skills":{}})
	tune(sim, "dummy", {"speed":0, "hp":5000, "damage":0})
	var hull: Dictionary = sim.spawn_unit(0, "terran_bunker", field(0,0))
	var rate := int(sim.rules.tick_rate)
	check(hull.hp == 1800 and sim.catalog.terran_bunker.armor == 3, "standard Desert Storm bunker hull")
	hull.hp = 1000
	ticks(sim, rate)
	check(hull.hp == 1000, "fire suppression stays off above half health")
	hull.hp = 880
	ticks(sim, rate)
	check(is_equal_approx(hull.hp, 895.0), "fire suppression restores 15 HP per second")
	ticks(sim, rate)
	check(is_equal_approx(hull.hp, 900.0), "fire suppression stops exactly at half health")

	# 飞行目标仅在步枪射程内，地面目标仅在榴弹射程内。记录两组独立炮位的实际出手。
	var flyer: Dictionary = sim.spawn_unit(1, "medivac", field(0,6.5))
	var ground: Dictionary = sim.spawn_unit(1, "dummy", field(7.5,0))
	var first_volley := {"garrison_rifle":0, "garrison_marauder":0}
	var volleys := {"garrison_rifle":[], "garrison_marauder":[]}
	var injections: Dictionary = {}
	for _step in range(rate):
		for event in sim.step():
			if event.type == "skill_used" and event.id == hull.id and event.skill == "stimulant":
				injections[event.mount] = event.health_cost
			if event.type != "attack" or event.kind != "terran_bunker":
				continue
			var mode := str(event.mode)
			if not volleys.has(mode):
				continue
			var times: Array = volleys[mode]
			if times.is_empty() or not is_equal_approx(times.back(), event.time):
				times.append(event.time)
			if times.size() == 1:
				first_volley[mode] += 1
	check(first_volley == {"garrison_rifle":6, "garrison_marauder":2}, "six independent rifles and two grenadiers can engage air and ground simultaneously")
	check(injections.size() == 8 and hull.hp == 900, "each garrison soldier injects without damaging the bunker")
	var mounts: Array = sim.skill_system.get_component(hull, "independent_weapons").state.mounts
	for index in injections:
		var mount: Dictionary = mounts[index]
		var group: Dictionary = sim.catalog.terran_bunker.skills.independent_weapons.weapons[mount.group_index]
		check(injections[index] == 10 and is_equal_approx(mount.crew.hp, float(group.crew_hp) - 10 + (rate - 1.0) / rate), "each soldier regenerates its own lost health")
	for mode in volleys:
		var times: Array = volleys[mode]
		var base_period := 0.8608 / 3.0 if mode == "garrison_rifle" else 0.5
		check(times.size() >= 2 and absf(times[1] - times[0] - base_period / 1.5) < 0.002, "garrison stimulant scales volley cadence once " + str(mode))
	check(flyer.hp < 5000 and int(flyer.get("slow_until_tick", 0)) == 0, "rifle impacts never apply concussive slow")
	check(ground.hp < 5000 and ground.get("slow_multiplier", 1.0) == 0.5, "grenade impacts slow an eligible ground target")
	var immune: Dictionary = sim.spawn_unit(1, "thor", field(7,1))
	var pending: Dictionary = {}
	sim.skill_system.hit(sim, hull, immune, {}, pending, sim.definitions.terran_bunker.weapons.garrison_marauder.to_data())
	check(pending.is_empty(), "massive targets are immune to bunker concussive shells")
	flyer.pos = field(0,4)
	var turret_times: Array = []
	for _step in range(rate):
		for event in sim.step():
			if event.type == "attack" and event.kind == "terran_bunker" and event.mode == "shrike_turret":
				turret_times.append(event.time)
	check(turret_times.size() >= 2 and absf(turret_times[1] - turret_times[0] - 0.8608 / 3.0) < 0.002, "the built-in Shrike turret fires independently with no crew stimulant")

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

## 护甲五类：无甲/特殊甲不吃穿甲加成；轻/重甲 = 攻击 + 对应加成 − 护甲点数；护盾是独立一层，先减护盾护甲。
func _armor_and_shields() -> void:
	var sim = bare()
	var weapon := {"damage":10,"bonus":{"light":5,"heavy":7}}
	check(sim.raw_damage(weapon,"rotling")==10 and sim.raw_damage(weapon,"thor")==10,"none and special armor receive no bonus")
	check(sim.raw_damage(weapon,"rifle")==15 and sim.raw_damage(weapon,"marauder")==17,"light and heavy receive their own bonus only")
	var tank = sim.spawn_unit(1,"marauder",field(0,0))
	var tank_armor: float = float(sim.catalog.marauder.armor)
	var floor_damage: float = float(sim.rules.min_damage)
	check(sim.expected_damage(weapon,tank)==17-tank_armor and sim.expected_damage({"damage":tank_armor-1},tank)==floor_damage and sim.expected_damage({"damage":0},tank)==0,"armor points subtract; positive hits deal at least min_damage")
	var zealot = sim.spawn_unit(1,"vanguard",field(0,3))
	var max_shield: float = float(sim.catalog.vanguard.shield)
	var max_hp: float = float(sim.catalog.vanguard.hp)
	var shield_armor: float = float(sim.catalog.vanguard.shield_armor)
	var hp_armor: float = float(sim.catalog.vanguard.armor)
	check(max_shield>0 and zealot.shield==max_shield and zealot.hp==max_hp,"protoss units spawn with full shields")
	check(Shield.absorb(sim,zealot,60)==0 and zealot.shield==max_shield-(60-shield_armor),"shield absorbs raw damage minus shield armor, ignoring hp armor")
	zealot.shield = 10
	check(Shield.absorb(sim,zealot,30)==30-shield_armor-10-hp_armor and zealot.shield==0,"overflow passes through and is reduced by hp armor")
	check(Shield.absorb(sim,zealot,30)==30-hp_armor,"no shield: damage minus armor")
	check(Shield.absorb(sim,zealot,30,true)==30,"armor-ignoring damage skips both armors")
	# 战斗中：同一步多次命中按顺序先扣盾；脱战 shield_regen_delay 秒后按 shield_regen 回盾，治疗不回盾。
	var fight = bare()
	var rate: float = float(fight.rules.tick_rate)
	tune(fight,"rifle",{"speed":0,"skills":{}})
	tune(fight,"vanguard",{"speed":0,"damage":0,"skills":{}})
	var target = fight.spawn_unit(1,"vanguard",field(0,0))
	var shooters: Array = []
	for i in range(3):
		shooters.append(fight.spawn_unit(0,"rifle",field(-4,i-1)))
	var per_hit: float = maxf(fight.raw_damage(fight.definitions.rifle.primary_weapon_data,"vanguard")-shield_armor,floor_damage)
	wait_until(fight,func(): return target.shield<max_shield,40)
	check(is_equal_approx(target.shield,max_shield-3*per_hit) and target.hp==max_hp,"three rifle hits in one step all land on shields")
	for shooter in shooters:
		fight.units.erase(shooter)
	var after_hits: float = target.shield
	var delay_ticks: int = roundi(float(fight.catalog.vanguard.shield_regen_delay)*rate)
	var regen_step: float = float(fight.catalog.vanguard.shield_regen)/rate
	ticks(fight,delay_ticks-2)
	check(target.shield==after_hits,"no shield regeneration before delay without damage")
	ticks(fight,3)
	check(target.shield>after_hits and target.shield<=after_hits+2*regen_step+0.0001,"shield regenerates shield_regen per second after delay")
	target.hp = max_hp-50
	fight.spawn_unit(1,"medic",field(1.5,0))
	var heal: float = float(fight.definitions.medic.primary_weapon_data.healing)
	var shield_before: float = target.shield
	var steps: int = wait_until(fight,func(): return target.hp>max_hp-50,40)
	check(target.hp==max_hp-50+heal and is_equal_approx(target.shield,minf(max_shield,shield_before+steps*regen_step)),"medic heals hp only; shields regenerate on their own")
	# 再生：憎恶脱战 health_regen_delay 秒后每秒回 health_regen 生命。
	var regen = bare()
	tune(regen,"abomination",{"speed":0})
	var abomination = regen.spawn_unit(0,"abomination",field(0,0))
	var hp_regen: float = float(regen.catalog.abomination.health_regen)
	var hp_delay: int = roundi(float(regen.catalog.abomination.health_regen_delay)*rate)
	abomination.hp = 100
	abomination.last_hit_tick = regen.tick
	ticks(regen,hp_delay-2)
	check(abomination.hp==100,"regen waits for delay")
	ticks(regen,3)
	check(abomination.hp>100 and abomination.hp<=100+2*hp_regen/rate+0.0001,"regen restores health_regen per second after delay")
	var kills = bare()
	tune(kills,"rifle",{"speed":0,"skills":{}})
	var brittle = kills.spawn_unit(1,"stalker",field(0,0))
	brittle.shield = 0
	brittle.hp = 1
	kills.spawn_unit(0,"rifle",field(-4,0))
	wait_until(kills,func(): return not kills.units.has(brittle),40)
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
		# armor_type=none 只表示未分类（不吃轻/重甲加成），仍可有护甲点数，见 SC2_BALANCE_REFERENCE。
		check(float(stats.get("armor",0))>=0,kind+" armor points are not negative")
		if structure:
			check(stats.race=="neutral" or Catalog.tower_kind(str(stats.race))==kind,"structure %s is neutral or its race's tower" % kind)
			continue
		check(Catalog.RACES.has(stats.get("race","")) and ["ready","stub","summoned"].has(stats.get("status","")),kind+" has race and status")
		if stats.status=="summoned":
			check(not Catalog.race_units(units,str(stats.race),true).has(kind) and stats.has("layer"),kind+" summon is not purchasable and has a layer")
			continue
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
		var starter_cost := 0
		for slot in Catalog.starter(race):starter_cost+=int(units[slot.kind].cost)
		var sim = bare(1,{"races":[race,race],"start_minerals":starter_cost})
		check(sim.submit_formation(0,Catalog.starter(race))=="" and sim.minerals[0]==0,race+" starter is valid and costs its catalog total")
		var default_start: int = int(Catalog.rules().start_minerals)
		if starter_cost>default_start:
			print("WARN: %s starter costs %d > start_minerals %d; default match falls back to an empty roster" % [race,starter_cost,default_start])
	for kind in ["guard","breaker","sniper"]:
		check(not units.has(kind),"retired id %s removed" % kind)
	check(units.vanguard.name=="先锋" and units.vanguard.race=="protoss" and units.swarm.race=="blight" and units.piercer.race=="zerg" and units.colossus.race=="protoss","unit reassignment follows decisions")

## 逐步比较双方总生命、护盾、击杀、基地与单位数。返回首次交战 tick、交战后 1 秒内是否仍完全对称、首次失衡 tick（0 表示未失衡）。
func _mirror_run(sim, total: int) -> Dictionary:
	var contact := 0
	var diverged := 0
	var through := true
	var rate := int(sim.rules.tick_rate)
	for i in range(total):
		var events: Array = sim.step()
		if contact==0 and events.any(func(e): return e.type=="damage"):contact=sim.tick
		var totals: Array = [[0.0,0.0,0],[0.0,0.0,0]]
		for unit in sim.units:
			totals[unit.team][0]+=float(unit.hp)
			totals[unit.team][1]+=float(unit.shield)
			totals[unit.team][2]+=1
		var even: bool = is_equal_approx(totals[0][0],totals[1][0]) and is_equal_approx(totals[0][1],totals[1][1]) and totals[0][2]==totals[1][2] and sim.kills[0]==sim.kills[1] and is_equal_approx(sim.bases[0],sim.bases[1])
		if not even and diverged==0:
			diverged=sim.tick
			if contact==0 or sim.tick<=contact+rate:through=false
	return {"contact":contact,"diverged":diverged,"symmetric_through_contact":through}

## 种族：整局固定、只能买本族已实装兵种；电脑只选本族兵种；每个种族镜像对局对称。
func _races() -> void:
	var sim = bare()
	check(sim.races==["terran","terran"] and sim.buy(0,"zergling",0)=="不属于本方种族","default terran rejects zerg units")
	# 当前名册没有预留兵种，临时注入一个本族 stub 验证“尚未实装”拒绝规则。
	var stub: Dictionary = DUMMY.duplicate(true)
	stub.race = "zerg"
	stub.status = "stub"
	stub.pending = ["测试用预留"]
	Catalog.extra_units = {"dummy": DUMMY, "stub_probe": stub}
	var zerg = bare(1,{"races":["zerg","protoss"],"start_minerals":2000})
	Catalog.extra_units = {"dummy": DUMMY}
	check(zerg.buy(0,"zergling",0)=="" and zerg.buy(0,"stub_probe",1)=="该兵种尚未实装" and zerg.buy(1,"vanguard",0)=="" and zerg.buy(1,"zergling",1)!="","each side validated against its own race")
	check(zerg.journal.settings.races==["zerg","protoss"],"races are journaled for replay")
	for race in Catalog.RACES:
		var ai = AI.new(5,race)
		var plan: Array = ai.choose(Catalog.starter("terran"),3000)
		var check_sim = bare(1,{"races":[race,race]})
		check(not plan.is_empty() and check_sim.validate_formation(plan,3000,0)=="","AI %s buys only ready units of its race" % race)
		var starter: Array = Catalog.starter(race)
		var mirror = bare(3,{"races":[race,race],"start_minerals":sim.formation_cost(starter)})
		mirror.submit_formation(0,starter)
		mirror.submit_formation(1,starter)
		var outcome: Dictionary = _mirror_run(mirror,int(mirror.next_wave_tick)+1200)
		check(outcome.contact>0 and outcome.symmetric_through_contact,race+" mirror battle is symmetric through first contact")
		if outcome.diverged>0:
			print("INFO: %s mirror diverges at tick %d (float32 rounding at point-symmetric coordinates)" % [race,outcome.diverged])
	var ai = AI.new(1,"protoss")
	check(ai.counter_for("liberator")!="" and Catalog.units()[ai.counter_for("liberator")].target_layers.has("air"),"AI counter picks a unit that can hit air")
	check(AI.new(1,"terran").counter_for("immortal")!="","AI finds counters across races")
	check(bare(1,{"races":["martian","zerg"]}).races==["terran","zerg"],"unknown race falls back to terran")
	# 首次交战前看不到对方种族与上一波阵容；首次受伤后双方同时公开，之后保持公开。
	var zerg_starter: Array = Catalog.starter("zerg")
	var blight_starter: Array = Catalog.starter("blight")
	var budget := maxi(sim.formation_cost(zerg_starter),sim.formation_cost(blight_starter))
	var hidden = bare(2,{"races":["zerg","blight"],"start_minerals":budget})
	hidden.submit_formation(0,zerg_starter)
	hidden.submit_formation(1,blight_starter)
	ticks(hidden,int(hidden.next_wave_tick)+1)
	var before: Dictionary = hidden.get_snapshot(0)
	check(hidden.wave==1 and not hidden.revealed and hidden.last_formations[1].size()==blight_starter.size(),"first wave spawned before any engagement")
	check(before.races==["zerg",""] and before.last_formations[1].is_empty() and before.last_formations[0].size()==zerg_starter.size(),"snapshot hides enemy race and last wave before reveal")
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
	check(after.races==["zerg","blight"] and after.last_formations[1].size()==blight_starter.size() and hidden.visible_enemy_formation(1).size()==zerg_starter.size(),"after reveal both sides see races and last waves")
	var quiet = bare(2)
	ticks(quiet,200)
	check(not quiet.revealed,"no fighting keeps races hidden")

## 大和舰：激光连射按目标层换武器；大和炮引导期间不动、不开火，锁定目标后必中，目标先死则不耗冷却。
func _battlecruisers() -> void:
	var stats: Dictionary = Catalog.units().battlecruiser
	check(stats.status=="ready" and stats.race=="terran" and stats.layer=="air" and stats.armor_type=="heavy" and int(stats.armor)==6,"battlecruiser is a ready terran heavy-armor air unit")
	var shop = bare(42,{"start_minerals":int(stats.cost)})
	check(stats.requires==["liberator"] and shop.buy(0,"battlecruiser",0)=="","prerequisite recorded but not enforced")
	check(AI.new(1,"terran").pool.has("battlecruiser") and Catalog.race_units(Catalog.units(),"terran").has("battlecruiser"),"battlecruiser is in terran shop and AI pool")
	var yamato: Dictionary = stats.skills.yamato
	var rate: float = float(Catalog.rules().tick_rate)
	# 激光：关闭大和炮单测普通武器。对地/对空各用一套激光，按目标层切换。
	var lasers = bare()
	tune(lasers,"battlecruiser",{"speed":0,"skills":{"weapon_switch":stats.skills.weapon_switch}})
	tune(lasers,"dummy",{"speed":0,"damage":0,"hp":10000})
	var ship = lasers.spawn_unit(0,"battlecruiser",field(0,0))
	var walker = lasers.spawn_unit(1,"dummy",field(5,0))
	var ground_laser: Dictionary = lasers.definitions.battlecruiser.weapons.ats_laser.to_data()
	wait_until(lasers,func(): return walker.hp<10000,20)
	check(ship.get("weapon_index",0)==0 and walker.hp==10000-lasers.expected_damage(ground_laser,walker),"ground laser hits ground target")
	var shots := 0
	var window: int = 40
	for i in range(window):
		for event in lasers.step():
			if event.type=="attack" and event.team==0:shots+=1
	var cycle: int = ceili((float(ground_laser.attack_duration)+float(ground_laser.interval))*rate-0.0001)
	check(abs(shots-window/cycle)<=1,"ground laser repeats every attack cycle (%d shots in %d ticks)" % [shots,window])
	var air = bare()
	tune(air,"battlecruiser",{"speed":0,"skills":{"weapon_switch":stats.skills.weapon_switch}})
	tune(air,"viking",{"speed":0,"damage":0,"hp":10000})
	var hunter = air.spawn_unit(0,"battlecruiser",field(0,0))
	var viking = air.spawn_unit(1,"viking",field(5,0))
	wait_until(air,func(): return viking.hp<10000,20)
	check(hunter.weapon_index==1 and viking.hp==10000-air.expected_damage(air.definitions.battlecruiser.weapons.ata_laser.to_data(),viking),"air laser hits air target")
	# 大和炮：激光射程外、大和炮射程内第 1 步开始引导；引导期间原地不动、无普通攻击，结束当步命中。
	var cannon = bare()
	tune(cannon,"dummy",{"speed":0,"damage":0,"hp":10000})
	var bc = cannon.spawn_unit(0,"battlecruiser",field(0,0))
	var start: Vector2 = bc.pos
	var big = cannon.spawn_unit(1,"dummy",field(float(yamato.range)-1.0,0))
	var channel: int = ceili(float(yamato.channel_seconds)*rate)
	var charged := false
	var fired := 0
	var attacks := 0
	var still := true
	for i in range(channel+1):
		for event in cannon.step():
			charged = charged or event.type=="yamato_charge"
			fired += 1 if event.type=="yamato" else 0
			attacks += 1 if event.type=="attack" and event.team==0 else 0
		if i < channel and (bc.pos!=start or fired>0):still=false
	check(still,"battlecruiser holds still while channeling")
	check(charged and fired==1 and attacks==0 and big.hp==10000-float(yamato.damage),"yamato fires once after channel for its damage")
	check(int(bc.yamato_ready_tick)==cannon.tick+ceili(float(yamato.cooldown_seconds)*rate) and not bc.has("yamato_target"),"yamato cooldown starts on firing")
	ticks(cannon,200)
	check(big.hp<10000-float(yamato.damage) and bc.pos!=start and not bc.has("yamato_target"),"lasers and movement resume during cooldown")
	# 护盾：大和炮先减护盾护甲打护盾，溢出再减生命护甲。
	var shielded = bare()
	tune(shielded,"immortal",{"speed":0,"damage":0,"hp":1000,"skills":{}})
	shielded.spawn_unit(0,"battlecruiser",field(0,0))
	var immortal = shielded.spawn_unit(1,"immortal",field(float(yamato.range)-1.0,0))
	var im: Dictionary = shielded.catalog.immortal
	ticks(shielded,channel+1)
	var overflow: float = float(yamato.damage)-float(im.shield_armor)-float(im.shield)
	check(immortal.shield==0 and immortal.hp==1000-(overflow-float(im.armor)),"yamato drains shields then hits hp minus armor")
	# 目标在引导中死亡：取消，不耗冷却。
	var cancel = bare()
	var caster = cancel.spawn_unit(0,"battlecruiser",field(0,0))
	var doomed = cancel.spawn_unit(1,"dummy",field(float(yamato.range)-1.0,0))
	ticks(cancel,5)
	check(caster.has("yamato_target"),"channel started")
	cancel.units.erase(doomed)
	ticks(cancel,1)
	check(not caster.has("yamato_target") and int(caster.get("yamato_ready_tick",0))==0,"target death cancels channel without cooldown")
	# 低血目标不值得开炮：跳虫生命低于 min_target_hp，直接用激光。
	var small = bare(42,{"races":["terran","zerg"]})
	var picky = small.spawn_unit(0,"battlecruiser",field(0,0))
	small.spawn_unit(1,"zergling",field(5,0))
	check(float(small.catalog.zergling.hp)<float(yamato.min_target_hp),"zergling is below yamato threshold")
	ticks(small,2)
	check(not picky.has("yamato_target"),"yamato ignores targets below min_target_hp")
	# 选目标：优先单位而不是结构体，单位间取生命+护盾最高者。
	var choice = Sim.new(1)
	tune(choice,"dummy",{"speed":0,"damage":0,"hp":1000})
	var vault: Dictionary = choice.units.filter(func(u): return u.kind=="treasury" and u.team==1)[0]
	var picker = choice.spawn_unit(0,"battlecruiser",vault.pos-Vector2(7,0))
	var weak = choice.spawn_unit(1,"dummy",vault.pos-Vector2(2,1.5))
	var strong = choice.spawn_unit(1,"dummy",vault.pos-Vector2(2,-1.5))
	weak.hp = 500
	strong.hp = 900
	ticks(choice,1)
	check(int(picker.get("yamato_target",0))==strong.id and weak.id!=strong.id,"yamato prefers the toughest unit over structures")
	# 镜像对称。
	var mirror = bare()
	mirror.spawn_unit(0,"battlecruiser",field(-8,0))
	mirror.spawn_unit(1,"battlecruiser",field(8,0))
	ticks(mirror,600)
	var survivors: Array = [mirror.units.filter(func(u): return u.team==0),mirror.units.filter(func(u): return u.team==1)]
	var even: bool = survivors[0].size()==survivors[1].size() and (survivors[0].is_empty() or is_equal_approx(survivors[0][0].hp,survivors[1][0].hp))
	check(even and mirror.kills[0]==mirror.kills[1] and is_equal_approx(mirror.damage_done[0],mirror.damage_done[1]) and mirror.damage_done[0]>0,"battlecruiser duel is symmetric")

## 按 main.gd 的顺序驱动大和舰精灵动画：步前快照/观察 → step → 观察 → 事件 → 观察；画面时钟每步 0.05 秒。
## 试玩反馈：恶火分离半径 0.75 + 停步散开，降低坦克溅射叠伤；沙漠风暴 30 格交战半径，近战被远程溅射时转向攻击者。
func _playtest_fixes() -> void:
	var legacy: Dictionary = Catalog.units().hellbat.duplicate(true)
	legacy.collision_radius = 0.6
	legacy.separate_when_stopped = false
	Catalog.extra_units = {"dummy":DUMMY, "post":PLAYTEST_POST, "artillery":PLAYTEST_ARTILLERY, "hellbat_legacy":legacy}
	_hellion_data()
	_hellion_splash()
	_melee_engages_long_range_attacker()
	_melee_stays_with_army()
	_engage_respects_layers_and_radius()
	Catalog.extra_units = {"dummy":DUMMY}

## 静止、无伤害、极高生命的靶子，只用来吸引火力。
const PLAYTEST_POST := {"name":"测试靶","symbol":"?","race":"zerg","status":"ready","cost":100,"hp":1000000,"armor_type":"heavy","armor":0,"damage":0,"interval":1,"range":0,"speed":0,"splash":0,"color":"ffffff","role":"测试","counter":"测试","layer":"ground","target_layers":["ground"],"size":[1,1]}
## 不可击杀的固定远程溅射炮，数值取自坦克架设炮（射程13、溅射2.5、内圈60%/外圈30%）。
const PLAYTEST_ARTILLERY := {"name":"测试远程炮","symbol":"?","race":"zerg","status":"ready","cost":100,"hp":1000000,"armor_type":"heavy","armor":0,"damage":15,"interval":1.5,"range":13,"speed":0,"splash":2.5,"splash_multiplier":0.3,"splash_inner_ratio":0.5,"splash_inner_multiplier":0.6,"color":"ffffff","role":"测试","counter":"测试","layer":"ground","target_layers":["ground"],"size":[1.6,1.6],"collision_radius":0.8}

func _hellion_data() -> void:
	var hellbat: Dictionary = Catalog.units().hellbat
	check(is_equal_approx(float(hellbat.collision_radius), 0.75), "hellion uses Desert Storm SeparationRadius 0.75")
	check(bool(hellbat.separate_when_stopped), "hellion spreads out during attack cooldown like marines")

## 六辆恶火从紧密方阵冲向一排靶子；身后的远程炮持续溅射。返回 {splash 暴露度, 恶火实际损失生命}。
func _hellion_run(kind: String) -> Dictionary:
	var sim = bare()
	# 单独比较车身分散的效果，两个样本都保留车形。
	var vehicle_skills: Dictionary = sim.catalog[kind].skills.duplicate(true)
	vehicle_skills.erase("proximity_morph")
	tune(sim,kind,{"skills":vehicle_skills})
	var hellions: Array = []
	for i in range(6):
		hellions.append(sim.spawn_unit(0, kind, field(-38.0 + float(i % 2) * 1.2, -3.0 + float(i / 2) * 1.2)))
	for i in range(5):
		sim.spawn_unit(1, "post", field(-28.0, -5.0 + float(i) * 2.0))
	sim.spawn_unit(1, "artillery", field(-20.0, -1.0))
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
	var ling: Dictionary = sim.spawn_unit(0, "zergling", field(-38.0, 0.0))
	var gun: Dictionary = sim.spawn_unit(1, "artillery", field(-28.0, 11.0))
	var was_hit := false
	var closest := INF
	for i in range(200):
		sim.step()
		if float(ling.hp) < float(Catalog.units().zergling.hp):
			was_hit = true
		closest = minf(closest, ling.pos.distance_to(gun.pos))
	check(closest < 2.5, "zergling closes in on the long-range attacker (closest %.1f)" % closest)
	check(float(gun.hp) < float(PLAYTEST_ARTILLERY.hp), "zergling actually attacks the long-range attacker")
	check(ling.pos.x < field(-18.0, 0.0).x, "zergling does not run off along the march route (x %.1f)" % ling.pos.x)
	check(was_hit or float(gun.hp) < float(PLAYTEST_ARTILLERY.hp), "scenario exercises the long-range engagement")

## 先锋与追猎者同行；敌方远程炮在追猎者射程外轰击：近战不能独自沿路线冲走，应和部队一起压向敌人。
func _melee_stays_with_army() -> void:
	var sim = bare()
	var zealot: Dictionary = sim.spawn_unit(0, "vanguard", field(-38.0, 0.0))
	var stalker: Dictionary = sim.spawn_unit(0, "stalker", field(-39.0, 0.0))
	var gun: Dictionary = sim.spawn_unit(1, "artillery", field(-34.0, 13.0))
	var spread := 0.0
	for i in range(120):
		sim.step()
		spread = maxf(spread, zealot.pos.distance_to(stalker.pos))
	check(zealot.pos.distance_to(gun.pos) < 3.0, "melee unit engages the attacker instead of marching past it")
	check(spread < 12.0, "melee unit stays within reach of its army (max gap %.1f)" % spread)

func _engage_respects_layers_and_radius() -> void:
	var sim = bare()
	var ling: Dictionary = sim.spawn_unit(0, "zergling", field(-38.0, 0.0))
	sim.spawn_unit(1, "viking", field(-36.0, 7.0))
	sim.spawn_unit(1, "post", field(-38.0, float(sim.rules.engage_radius) + 6.0))
	ticks(sim, 40)
	check(ling.pos.x > field(-33.0, 0.0).x and absf(ling.pos.y - field(0, 0).y) < 2.0, "ground melee ignores air and out-of-radius enemies and keeps marching")

## 哨兵：500 矿一组 2 名；防御护盾不叠开；回盾优先于攻击，并在前线消失后后撤。
func _sentry() -> void:
	_sentry_pack()
	_sentry_shield_not_doubled()
	_sentry_shield_opens_after_cover_ends()
	_sentry_restore_rules()
	_sentry_attack_and_retreat()

func _sentry_quiet():
	var sim = bare()
	tune(sim, "sentry", {"speed":0, "energy_regen":0, "shield_regen":0})
	tune(sim, "vanguard", {"speed":0, "shield_regen":0, "skills":{}})
	tune(sim, "dummy", {"speed":0, "damage":0, "hp":100000})
	return sim

func _sentry_pack() -> void:
	var stats: Dictionary = Catalog.units().sentry
	check(int(stats.cost)==500 and int(stats.spawn_count)==2 and int(stats.gas_cost)==0 and int(stats.core_cost)==0, "sentry pack is 500 minerals for 2")
	check(is_equal_approx(float(stats.attack_modes[0].damage), 4.5) and is_equal_approx(float(stats.attack_modes[0].shield_bonus), 4.0), "sentry damage is half of 9; shield bonus stays 4")
	check(is_equal_approx(float(stats.skills.aura.energy_cost), 100.0) and is_equal_approx(float(stats.skills.aura.radius), 4.5) and is_equal_approx(float(stats.skills.aura.duration), 12.86), "guardian shield keeps radius 4.5 and duration 12.86, costs 100")
	check(int(stats.energy)==200 and is_equal_approx(float(stats.initial_energy), 50.0), "sentry energy pool stays 200 / 50")
	var restore: Dictionary = stats.skills.shield_restore
	check(int(restore.max_targets)==2 and is_equal_approx(float(restore.shield_per_pulse), 5.0) and is_equal_approx(float(restore.energy_per_pulse), 2.0) and is_equal_approx(float(restore.pulse_seconds), 0.5), "restore is +5 shield and -2 energy per 0.5s")
	var sim = bare(42, {"races":["protoss","protoss"], "start_minerals":500})
	check(sim.formation_cost([{"kind":"sentry","cell":0}])==500, "one sentry slot costs the pack price")
	check(sim.buy(0, "sentry", 4)=="" and sim.minerals[0]==0, "buying one sentry pack spends 500")
	check(sim.refund_value(0, 4)==500 and sim.sell(0, 4)=="" and sim.minerals[0]==500, "undeployed sentry pack refunds 500")
	check(sim.buy(0, "sentry", 4)=="", "rebuy sentry pack")
	sim.tick=sim.next_wave_tick-1
	sim.step()
	var born := 0
	for unit in sim.units:
		if unit.team==0 and unit.kind=="sentry":born+=1
	check(born==2, "one pack spawns two sentries")
	var held: int = sim.minerals[0]
	check(sim.refund_value(0, 4)==0 and sim.sell(0, 4)=="" and sim.minerals[0]==held, "deployed sentry pack refunds nothing")
	var ai = AI.new(2, "protoss")
	check(not ai._affordable("sentry", 499, 0, 0) and ai._affordable("sentry", 500, 0, 0), "AI prices a sentry pack at 500")
	var poor: Array = ai.buy_list([], [], 499)
	check(poor.size()>0 and not poor.any(func(slot): return slot.kind=="sentry"), "AI does not buy a sentry pack below 500")

func _sentry_shield_not_doubled() -> void:
	var sim = _sentry_quiet()
	var radius: float = float(sim.catalog.sentry.skills.aura.radius)
	var reduction: float = float(sim.catalog.sentry.skills.aura.ranged_damage_reduction)
	var opener = sim.spawn_unit(0, "sentry", field(0, 0))
	opener.energy=100
	var ally = sim.spawn_unit(0, "vanguard", field(1, 0))
	sim.spawn_unit(1, "dummy", field(4, 0))
	sim.step()
	check(is_equal_approx(float(opener.energy), 0.0) and sim.tick<int(opener.aura_until_tick), "sentry spends 100 energy to open guardian shield")
	var inside = sim.spawn_unit(0, "sentry", field(2, 0))
	inside.energy=200
	var outside = sim.spawn_unit(0, "sentry", field(radius+2.5, 0))
	outside.energy=200
	sim.step()
	check(is_equal_approx(float(inside.energy), 200.0) and int(inside.get("aura_until_tick", 0))==0, "sentry inside an open shield does not open its own")
	check(is_equal_approx(float(outside.energy), 100.0) and sim.tick<int(outside.aura_until_tick), "sentry outside that shield still opens its own")
	check(is_equal_approx(float(sim.aura_modifiers[ally.id].reduction), reduction) and reduction<reduction*2.0, "overlapping sentries do not double the shield reduction")

func _sentry_shield_opens_after_cover_ends() -> void:
	var sim = _sentry_quiet()
	var skills: Dictionary = sim.catalog.sentry.skills.duplicate(true)
	skills.aura.duration=0.5
	skills.aura.cooldown=0.5
	tune(sim, "sentry", {"speed":0, "energy_regen":0, "shield_regen":0, "skills":skills})
	var opener = sim.spawn_unit(0, "sentry", field(0, 0))
	opener.energy=100
	var covered = sim.spawn_unit(0, "sentry", field(2, 0))
	covered.energy=200
	sim.spawn_unit(1, "dummy", field(4, 0))
	sim.step()
	var until: int = int(opener.aura_until_tick)
	check(is_equal_approx(float(covered.energy), 200.0) and sim.tick<until, "covered sentry waits while the first shield is up")
	while sim.tick<until:
		sim.step()
	check(is_equal_approx(float(covered.energy), 100.0) and sim.tick<int(covered.aura_until_tick), "covered sentry opens its shield once the other shield disappears")

func _sentry_restore_rules() -> void:
	var sim = _sentry_quiet()
	var pulse: int = ceili(float(sim.catalog.sentry.skills.shield_restore.pulse_seconds)*float(sim.rules.tick_rate))
	var sentry = sim.spawn_unit(0, "sentry", field(0, 0))
	sentry.energy=40
	var shields: Array = [40.0, 60.0, 80.0]
	var allies: Array = []
	for i in range(3):
		var ally = sim.spawn_unit(0, "vanguard", field(-2.0-float(i), 0))
		ally.shield=shields[i]
		allies.append(ally)
	var enemy = sim.spawn_unit(1, "dummy", field(4, 0))
	var enemy_hp: float = enemy.hp
	ticks(sim, pulse-1)
	check(is_equal_approx(float(allies[0].shield), 40.0) and is_equal_approx(float(sentry.energy), 40.0) and is_equal_approx(enemy.hp, enemy_hp), "restore waits until the 0.5s settlement")
	sim.step()
	check(is_equal_approx(float(allies[0].shield), 45.0) and is_equal_approx(float(allies[1].shield), 65.0) and is_equal_approx(float(allies[2].shield), 80.0), "one sentry restores its two lowest shields and leaves the third")
	check(is_equal_approx(float(sentry.energy), 38.0), "two restores still spend 2 energy per 0.5s")
	check(is_equal_approx(enemy.hp, enemy_hp), "restore takes priority over attacking")
	var other = _sentry_quiet()
	var first = other.spawn_unit(0, "sentry", field(0, 0))
	var second = other.spawn_unit(0, "sentry", field(0.4, 0))
	first.energy=40
	second.energy=40
	var shared = other.spawn_unit(0, "vanguard", field(-1.5, 0))
	shared.shield=50
	other.spawn_unit(1, "dummy", field(4, 0))
	ticks(other, pulse)
	check(is_equal_approx(float(shared.shield), 55.0), "two sentries do not restore the same unit")
	check(is_equal_approx(float(first.energy), 38.0) and is_equal_approx(float(second.energy), 40.0), "only the sentry that locked the target spends energy")

func _sentry_attack_and_retreat() -> void:
	var sim = _sentry_quiet()
	var pulse: int = ceili(float(sim.catalog.sentry.skills.shield_restore.pulse_seconds)*float(sim.rules.tick_rate))
	var sentry = sim.spawn_unit(0, "sentry", field(0, 0))
	sentry.energy=0
	var ally = sim.spawn_unit(0, "vanguard", field(-3, 0))
	var enemy = sim.spawn_unit(1, "dummy", field(4, 0))
	var before: float = enemy.hp
	ticks(sim, pulse-1)
	check(is_equal_approx(enemy.hp, before), "sentry beam waits a full 0.5s")
	sim.step()
	check(is_equal_approx(before-enemy.hp, 4.5), "full nearby shields let the sentry attack for half its old damage")
	var moving = bare()
	tune(moving, "vanguard", {"speed":0, "shield_regen":0, "skills":{}})
	tune(moving, "dummy", {"speed":0, "damage":0, "hp":100000})
	var runner = moving.spawn_unit(0, "sentry", field(0, 0))
	runner.energy=0
	var foe = moving.spawn_unit(1, "dummy", field(4, 0))
	var x0: float = runner.pos.x
	ticks(moving, 20)
	check(runner.pos.x<x0 and is_equal_approx(foe.hp, float(moving.catalog.dummy.hp)), "lone sentry retreats and does not push into the enemy")
	var wave = moving.spawn_unit(0, "vanguard", field(-30, 0))
	var gap: float = runner.pos.distance_to(wave.pos)
	var x1: float = runner.pos.x
	ticks(moving, 30)
	check(runner.pos.x<x1 and runner.pos.distance_to(wave.pos)<gap and is_equal_approx(foe.hp, float(moving.catalog.dummy.hp)), "sentry follows the next wave instead of the enemy")
	var falling = bare()
	tune(falling, "vanguard", {"speed":0, "shield_regen":0, "skills":{}})
	tune(falling, "dummy", {"speed":0, "damage":0, "hp":100000})
	var fighter = falling.spawn_unit(0, "sentry", field(0, 0))
	fighter.energy=0
	var front = falling.spawn_unit(0, "vanguard", field(-3, 0))
	var target = falling.spawn_unit(1, "dummy", field(4, 0))
	ticks(falling, pulse)
	check(target.hp<100000.0, "sentry attacks while a nearby attacker still has a full shield")
	var left: float = target.hp
	var x2: float = fighter.pos.x
	front.hp=0
	ticks(falling, 20)
	check(fighter.pos.x<x2-0.5 and is_equal_approx(target.hp, left), "sentry retreats once nearby attackers are dead and stops shooting")

## 新增待运行回归：编队限速只进入普通行军入口，不改变原始移动/闪现接口。
func _formation_pace() -> void:
	for team in range(2):
		for kind in ["archon","stalker"]:
			var sim=bare()
			var unit=sim.spawn_unit(team,kind,field(0,0))
			var base: float=float(sim.definitions[kind].speed)
			var radius: float=float(sim.catalog[kind].skills.formation_pace.radius)
			var same=sim.spawn_unit(team,kind,field(1,0))
			var enemy=sim.spawn_unit(1-team,"medic",field(2,0))
			sim._build_buckets()
			check(is_equal_approx(sim._march_speed(unit),base),"same kind and enemy do not cap %s/%d" % [kind,team])
			var friend=sim.spawn_unit(team,"medic",field(3,0))
			sim._build_buckets()
			var pace: float=float(sim.definitions.medic.speed)
			check(is_equal_approx(sim._march_speed(unit),pace),"other-kind mobile support sets march pace %s/%d" % [kind,team])
			check(is_equal_approx(sim._movement_speed(unit),base),"ordinary movement mechanics and idle drift keep original speed")
			friend.root_until_tick=sim.tick+100
			friend.slow_until_tick=sim.tick+100
			friend.slow_multiplier=0.1
			check(is_equal_approx(sim._march_speed(unit),pace),"companion temporary locks/slows never freeze or recursively slow march")
			unit.slow_until_tick=sim.tick+100
			unit.slow_multiplier=0.5
			check(is_equal_approx(sim._march_speed(unit),pace*0.5),"own slow still multiplies capped march speed")
			unit.root_until_tick=sim.tick+100
			check(sim._march_speed(unit)==0,"own root still prevents movement")
			unit.root_until_tick=0
			unit.slow_until_tick=0
			unit.attack_blocked_this_frame=true
			check(sim._march_speed(unit)==0,"own attack lock still prevents movement")
			unit.attack_blocked_this_frame=false
			friend.pos=field(radius,0)
			sim._build_buckets()
			check(is_equal_approx(sim._march_speed(unit),pace),"radius boundary included")
			friend.pos=field(radius+0.01,0)
			sim._build_buckets()
			check(is_equal_approx(sim._march_speed(unit),base),"outside radius restores own march speed")
			friend.pos=field(3,0)
			friend.hp=0
			sim._build_buckets()
			check(is_equal_approx(sim._march_speed(unit),base),"dead friend does not cap")
			var flyer=sim.spawn_unit(team,"void_ray",field(3,0))
			sim._build_buckets()
			var air_pace: float=minf(base,float(sim.definitions.void_ray.speed))
			check(is_equal_approx(sim._march_speed(unit),air_pace),"ordinary air allies count")
			var before: float=sim._march_speed(unit)
			sim.units.reverse()
			sim._build_buckets()
			check(is_equal_approx(sim._march_speed(unit),before),"unit iteration order does not alter reference pace")
	var mixed=bare()
	var archon=mixed.spawn_unit(0,"archon",field(0,0))
	var stalker=mixed.spawn_unit(0,"stalker",field(2,0))
	mixed._build_buckets()
	var archon_base: float=float(mixed.definitions.archon.speed)
	check(is_equal_approx(mixed._march_speed(archon),archon_base) and is_equal_approx(mixed._march_speed(stalker),archon_base),"archon and stalker are different categories without mutual recursive cap")
	var slow=mixed.spawn_unit(0,"medic",field(-2,0))
	mixed._build_buckets()
	check(is_equal_approx(mixed._march_speed(archon),float(mixed.definitions.medic.speed)),"slowest nearby type sets reference")
	tune(mixed,"medic",{"speed":0})
	mixed._build_buckets()
	check(is_equal_approx(mixed._march_speed(archon),archon_base),"zero base speed does not freeze march")
	var isolated=bare()
	var solo=isolated.spawn_unit(0,"stalker",field(0,0))
	isolated.spawn_unit(0,"locust",field(1,0))
	isolated.spawn_unit(0,"tower",field(2,0))
	isolated._build_buckets()
	check(is_equal_approx(isolated._march_speed(solo),float(isolated.definitions.stalker.speed)),"summons and structures do not set march pace")
	check(not isolated.catalog.zergling.skills.has("formation_pace"),"zergling combat mobility unchanged")

	var blink=preload("res://scripts/skills/blink.gd").new()
	blink.configure("blink",stalker,mixed.catalog.stalker.skills.blink)
	stalker.shield=0
	stalker.last_hit_tick=mixed.tick
	var moves: Dictionary={}
	var threat=mixed.spawn_unit(1,"dummy",stalker.pos+Vector2(3,0))
	var origin: Vector2=stalker.pos
	check(blink.step(mixed,stalker,threat,1.0/float(mixed.rules.tick_rate),moves),"mixed army retains damage-triggered stalker blink")
	check(moves.has(stalker.id) and is_equal_approx(origin.distance_to(moves[stalker.id]),float(mixed.catalog.stalker.skills.blink.distance)),"blink distance is not limited by formation pace")

## 经过正常攻击结算区分主目标与溅射，避免仅凭受伤时间错误触发后撤。
func _adepts() -> void:
	for scenario in ["ground", "air", "splash", "full_shield"]:
		var sim = bare()
		tune(sim, "adept", {"speed":0, "damage":0, "shield_regen":0})
		var attacker_layer := "air" if scenario == "air" else "ground"
		tune(sim, "rifle", {"layer":attacker_layer, "speed":0, "skills":{}, "splash":3 if scenario=="splash" else 0})
		var adept: Dictionary = sim.spawn_unit(0, "adept", field(0,0))
		if scenario != "full_shield":
			adept.shield = 10.0
		if scenario == "splash":
			tune(sim, "dummy", {"speed":0, "damage":0})
			sim.spawn_unit(0, "dummy", field(2,0))
		sim.spawn_unit(1, "rifle", field(4,0))
		var initial_shield: float = adept.shield
		check(wait_until(sim,func(): return adept.shield < initial_shield,30)>0, "adept actually takes a hit: "+scenario)
		sim.step()
		check(adept.has("shade_position") == (scenario=="ground"), "only a direct ground hit against low shields starts retreat: "+scenario)
		if scenario=="ground":
			var retreat_origin: Vector2 = adept.pos
			var retreat: Dictionary = sim.catalog.adept.skills.psionic_transfer
			check(wait_until(sim,func(): return sim.teleports.has(adept.id),60)>0, "retreat shade resolves")
			check(adept.pos.is_equal_approx(retreat_origin - Vector2.RIGHT * float(retreat.retreat_distance)), "retreat teleports away from the attacker")

	var waves = bare(42,{"races":["protoss","terran"], "start_minerals":280, "first_wave_seconds":0.05})
	var rate := int(waves.rules.tick_rate)
	check(waves.buy(0,"adept",0)=="" and waves.minerals[0]==0, "one 280-mineral adept pack")
	waves.step()
	var first_wave: Array = waves.units.duplicate()
	check(first_wave.size()==2 and first_wave.all(func(u):return u.adept_tactic=="retreat"), "two adepts spawn with the default tactic")
	check(waves.set_adept_tactic(0,"support")=="" and first_wave.all(func(u):return u.adept_tactic=="retreat"), "tactic change preserves existing adepts")
	waves.next_wave_tick=waves.tick+1
	waves.step()
	var next_wave: Array = waves.units.filter(func(u):return u.born==waves.tick)
	check(next_wave.size()==2 and next_wave.all(func(u):return u.adept_tactic=="support"), "next wave takes the new tactic")
	if next_wave.size()!=2:return
	var advancing: Dictionary = next_wave[0]
	var origin: Vector2 = advancing.pos
	var forward := origin.direction_to(waves.base_pos(1))
	tune(waves, "dummy", {"speed":0, "damage":0, "hp":10000})
	waves.spawn_unit(1,"dummy",origin+forward*15)
	check(wait_until(waves,func():return advancing.has("shade_position"),rate)>0, "support sends a shade before reaching the enemy")
	check(wait_until(waves,func():return waves.teleports.has(advancing.id),rate*5)>0, "support shade teleports its owner near the enemy")
	check((advancing.pos-origin).dot(forward)>0, "support teleports forward")
	for i in range(rate*3):
		waves.step()
		if advancing.has("shade_position") or waves.teleports.has(advancing.id):
			check(false, "support transfer launched again for the same adept")
			break

## 车型在行军与接敌之间保持同一个实体；机甲喷火使用独立的扇形判定。
func _hellbat_mechs() -> void:
	var shop = bare(42, {"start_minerals":640, "first_wave_seconds":0.05})
	check(shop.buy(0,"hellbat",0)=="" and shop.minerals[0]==260, "380 minerals buy one Hellion")
	check(shop.buy(0,"hellbat_mech",1)=="" and shop.minerals[0]==0, "260 minerals buy one Hellbat")
	shop.step()
	check(shop.units.filter(func(u): return u.kind=="hellbat").size()==1 and shop.units.filter(func(u): return u.kind=="hellbat_mech").size()==1, "each recruitment deploys one unit in its purchased form")

	var solo = bare()
	var car: Dictionary = solo.spawn_unit(0,"hellbat",field(0,0))
	var original_id: int = car.id
	var full_speed := float(solo.catalog.hellbat.speed)
	var tick_rate := int(solo.rules.tick_rate)
	tune(solo,"viking",{"speed":0,"skills":{}})
	solo.spawn_unit(1,"viking",field(2,0))
	var start: Vector2 = car.pos
	solo.step()
	var solo_speed: float = start.distance_to(car.pos) * tick_rate
	check(solo_speed > 0.0 and solo_speed < full_speed and not car.has("morph_start_tick"), "solo Hellion advances at escort pace and ignores an aircraft in its own discovery range")
	car.hp = float(solo.catalog.hellbat.hp) * 0.5
	tune(solo,"dummy",{"speed":0,"damage":0})
	var own_discovery := float(solo.catalog.hellbat.range) * 1.5
	var enemy: Dictionary = solo.spawn_unit(1,"dummy",car.pos + Vector2.RIGHT * (own_discovery - 0.02))
	start = car.pos
	solo.step()
	check(car.has("morph_start_tick") and car.pos==start, "a ground enemy inside personal discovery range starts a stationary morph")
	var morph_ticks := ceili(float(solo.catalog.hellbat.skills.proximity_morph.duration) * tick_rate)
	enemy.pos += Vector2.RIGHT * 24.0
	ticks(solo,morph_ticks-2)
	check(car.kind=="hellbat" and car.pos==start, "vehicle stays stationary in its original form until the morph finishes")
	solo.step()
	check(car.kind=="hellbat_mech" and car.id==original_id and solo.by_id.get(original_id)==car, "transformation finishes on schedule with the same live unit")
	check(is_equal_approx(float(car.hp),float(solo.catalog.hellbat_mech.hp)*0.5), "morph preserves the health fraction even if the original contact leaves")
	solo.step()
	check(car.pos.distance_to(start)>0.0, "mech advances again after completing the morph")

	for ship in ["battlecruiser", "carrier"]:
		_hellion_supports_ship(ship)

	for team in range(2):
		_hellion_wave_contact(team, false)
		_hellion_wave_contact(team, true)

	for team in range(2):
		var sim = bare()
		tune(sim,"hellbat_mech",{"speed":0, "separate_when_stopped":false})
		tune(sim,"dummy",{"speed":0, "damage":0})
		tune(sim,"rifle",{"speed":0, "damage":0, "skills":{}, "separate_when_stopped":false})
		tune(sim,"viking",{"speed":0, "skills":{}})
		var direction := Vector2.RIGHT if team == 0 else Vector2.LEFT
		var mech: Dictionary = sim.spawn_unit(team,"hellbat_mech",field(0,0))
		var muzzle: Vector2 = mech.pos + direction * sim.body_radius(mech)
		var primary: Dictionary = sim.spawn_unit(1-team,"dummy",muzzle + direction * 0.55)
		var light: Dictionary = sim.spawn_unit(1-team,"rifle",muzzle + direction * 1.7 + Vector2.UP * 0.55)
		var edge: Dictionary = sim.spawn_unit(1-team,"dummy",muzzle + direction * 1.3 + Vector2.DOWN * 0.85)
		var side: Dictionary = sim.spawn_unit(1-team,"dummy",muzzle + direction * 1.4 + Vector2.UP * 2.0)
		var far_target: Dictionary = sim.spawn_unit(1-team,"dummy",muzzle + direction * 3.0)
		var aircraft: Dictionary = sim.spawn_unit(1-team,"viking",muzzle + direction * 1.6)
		var ally: Dictionary = sim.spawn_unit(team,"dummy",muzzle + direction * 1.7)
		var hp := float(DUMMY.hp)
		check(wait_until(sim,func(): return primary.hp < hp, 20)>0, "hellbat fires at a ground target")
		check(is_equal_approx(float(primary.hp),hp-24.0) and is_equal_approx(float(edge.hp),hp-24.0), "one hit on the primary and a ground unit whose body touches the cone")
		var light_damage := 49.0 - float(sim.catalog.rifle.armor)
		check(is_equal_approx(float(light.hp),float(sim.catalog.rifle.hp)-light_damage), "light splash target takes 24 + 25 before armor")
		check(side.hp==hp and far_target.hp==hp and ally.hp==hp and aircraft.hp==sim.catalog.viking.hp, "side, range, team and layer limit the flame cone")

## 快速同伴也不能把随队速度抬至全速；前方舰艇的激光或拦截机交火属于真实支援目标。
func _hellion_supports_ship(kind: String) -> void:
	var sim = bare()
	tune(sim,"dummy",{"speed":8.0})
	tune(sim,"roach",{"speed":0, "damage":0, "skills":{}})
	var ship: Dictionary=sim.spawn_unit(0,kind,field(25,0))
	sim.wave+=1
	var vehicle: Dictionary=sim.spawn_unit(0,"hellbat",field(-25,0))
	sim.spawn_unit(0,"dummy",field(-29,3))
	var start: Vector2=vehicle.pos
	var rate := float(sim.rules.tick_rate)
	var escort := float(sim.catalog.hellbat.skills.proximity_morph.escort_speed)
	sim.step()
	check(absf(start.distance_to(vehicle.pos)*rate-escort)<0.01, "fast same-wave allies respect the escort speed cap")
	var target: Dictionary=sim.spawn_unit(1,"roach",ship.pos+Vector2.RIGHT*5.0)
	var hp := float(target.hp)
	check(wait_until(sim,func(): return target.hp<hp,80)>0, kind+" engages the enemy ahead of the new wave")
	start=vehicle.pos
	sim.step()
	check(absf(start.distance_to(vehicle.pos)*rate-float(sim.catalog.hellbat.speed))<0.01, kind+" fire draws full-speed reinforcements")
	ship.hp=0
	start=vehicle.pos
	sim.step()
	check(absf(start.distance_to(vehicle.pos)*rate-escort)<0.01, "losing the last fighting veteran restores escort pace")

## 先部署一名老兵，再部署有前哨和恶火的第二波。只有前方仍在战斗的老兵才让恶火独立侦察、全速增援。
func _hellion_wave_contact(team: int, veteran_ahead: bool) -> void:
	var sim = bare(42, {"start_minerals":600, "first_wave_seconds":0.05})
	tune(sim,"dummy",{"speed":1.8, "range":5, "damage":1})
	tune(sim,"roach",{"speed":0, "damage":0, "skills":{}})
	check(sim.buy(team,"dummy",0)=="", "first wave recruits a veteran")
	sim.step()
	var veteran: Dictionary = sim.units[0]
	check(sim.buy(team,"hellbat",1)=="", "next wave can add an advancing Hellion")
	sim.next_wave_tick=sim.tick+1
	sim.step()
	var scout: Dictionary = sim.units.filter(func(u): return u.kind=="dummy" and u.id!=veteran.id)[0]
	var vehicle: Dictionary = sim.units.filter(func(u): return u.kind=="hellbat")[0]
	var forward := Vector2.RIGHT if team==0 else Vector2.LEFT
	var rate := float(sim.rules.tick_rate)
	vehicle.pos=field(0,0)
	scout.pos=vehicle.pos+forward*8.0
	veteran.pos=vehicle.pos+forward*(35.0 if veteran_ahead else -35.0)
	var start: Vector2=vehicle.pos
	sim.step()
	check(absf(start.distance_to(vehicle.pos)*rate - float(sim.catalog.dummy.speed))<0.01, "an idle survivor leaves the new Hellion at its current wave's pace")
	var opponent: Dictionary = sim.spawn_unit(1-team,"roach",veteran.pos+forward*2.0)
	var initial_hp: float = opponent.hp
	check(wait_until(sim, func(): return opponent.hp<initial_hp, 30)>0, "old wave has actually exchanged fire")
	start=vehicle.pos
	sim.step()
	var expected_speed: float = sim.catalog.hellbat.speed if veteran_ahead else sim.catalog.dummy.speed
	check(absf(start.distance_to(vehicle.pos)*rate-expected_speed)<0.01, "only a fighting survivor ahead prompts full-speed reinforcement")
	var contact: Dictionary = sim.spawn_unit(1-team,"roach",scout.pos+forward*5.5)
	sim.step()
	if veteran_ahead:
		check(not vehicle.has("morph_start_tick"), "reinforcing Hellion ignores contact reported only by a new-wave scout")
		contact.pos=vehicle.pos+forward*4.0
		sim.step()
		check(vehicle.has("morph_start_tick"), "reinforcing Hellion starts morphing on its own contact")
	else:
		check(vehicle.has("morph_start_tick"), "in escort mode a ground sighting from the same wave triggers morphing beyond the Hellion's own discovery radius")

## 医疗运输机的自动双束、持续能耗及多机治疗占用。
func _medivacs() -> void:
	var shop=bare()
	check(not Catalog.race_units(shop.catalog,"terran",true).has("medic"),"retired medic hidden even in legacy shop")
	check(Catalog.race_units(shop.catalog,"terran").has("medivac"),"medivac playable")
	check(shop.kind_error(0,"medic")!="" and shop.validate_formation(formation("medic",1),9999)!="","retired medic rejected on purchase and restore")
	shop.formations[0]=[]
	shop.minerals[0]=850
	check(shop.buy(0,"medivac",0)=="" and shop.minerals[0]==0,"medivac group costs 850 minerals")
	check(int(shop.catalog.medivac.spawn_count)==2,"medivac group spawns two")
	check(shop.sell(0,0)=="" and shop.minerals[0]==850,"undeployed medivac group refunds 850")
	var weapon: Dictionary = shop.definitions.medivac.primary_weapon_data
	var config: Dictionary = shop.catalog.medivac.skills.medivac_healing
	check(is_equal_approx(weapon.delivery.tick_interval, 0.111 / 1.4) and weapon.healing == 1, "Medivac uses Faster real-time campaign healing")
	check(is_equal_approx(config.energy_cost, 0.33) and is_equal_approx(shop.catalog.medivac.energy_regen, 1.575), "Medivac energy drain and regeneration use the same clock")
	for team in range(2):
		var sim = bare()
		tune(sim, "medivac", {"speed":0, "energy_regen":0})
		tune(sim, "rifle", {"speed":0, "damage":0, "skills":{}})
		tune(sim, "hellbat", {"speed":0, "damage":0, "skills":{}})
		var craft: Dictionary = sim.spawn_unit(team, "medivac", field(0,0))
		var primary: Dictionary = sim.spawn_unit(team, "rifle", field(1,0))
		var secondary: Dictionary = sim.spawn_unit(team, "rifle", field(0,1))
		var reserve: Dictionary = sim.spawn_unit(team, "rifle", field(-1,0))
		var machine: Dictionary = sim.spawn_unit(team, "hellbat", field(0,-1))
		primary.hp = 10
		secondary.hp = 20
		reserve.hp = 40
		machine.hp = 1
		craft.hp = 50
		ticks(sim, 2 * int(sim.rules.tick_rate))
		var first_ticks := int(primary.hp) - 10
		var second_ticks := int(secondary.hp) - 20
		check(first_ticks >= 24 and first_ticks <= 25, "single beam averages 12.6 HP/s without rounding each pulse to a frame")
		check(second_ticks >= 23 and second_ticks <= first_ticks and reserve.hp == 40, "secondary beam runs its own clock after its first scan")
		check(machine.hp == 1 and craft.hp == 50, "only biological patients are eligible")
		check(is_equal_approx(craft.energy, 200.0 - 0.33 * (first_ticks + second_ticks)), "each applied pulse spends energy from its own craft")
		check(sim.active_beams.size() == 2 and sim.combat_units(team) == 0, "the two visible healing beams count as support")
		craft.energy = 0
		var hp_before: float = primary.hp
		ticks(sim, 4)
		check(primary.hp == hp_before and sim.active_beams.is_empty(), "empty Medivac stops channeling")
		tune(sim, "rifle", {"layer":"air"})
		craft.energy = 1.99
		ticks(sim, 4)
		check(primary.hp == hp_before, "restarting requires two energy even for the previous patient")
		craft.energy = 2
		ticks(sim, 8)
		check(primary.hp > hp_before and craft.energy < 1.99, "air biological patients can be healed after recharging")
		_medivac_shared_patient(team)
	_medivac_patient_priority()
	var flee=bare()
	var craft=flee.spawn_unit(0,"medivac",field(0,0))
	flee.spawn_unit(1,"rifle",field(2,0))
	var before: float=craft.pos.x
	flee.step()
	check(craft.pos.x<before,"medivac retreats from anti-air threat")


func _medivac_shared_patient(team: int) -> void:
	var sim = bare()
	tune(sim, "medivac", {"speed":0, "energy_regen":0})
	tune(sim, "rifle", {"speed":0, "damage":0, "skills":{}})
	var first: Dictionary = sim.spawn_unit(team, "medivac", field(0,0))
	var second: Dictionary = sim.spawn_unit(team, "medivac", field(0,1))
	var patient: Dictionary = sim.spawn_unit(team, "rifle", field(1,0))
	patient.hp = 5
	ticks(sim, int(sim.rules.tick_rate))
	check(sim.active_beams.size() == 1 and patient.hp >= 16 and patient.hp <= 17, "overlapping Medivacs cannot stack healing on one patient")
	if sim.active_beams.size() != 1:
		return
	var owner_id: int = sim.active_beams[0].source_id
	var current: Dictionary = first if first.id == owner_id else second
	var standby: Dictionary = second if first.id == owner_id else first
	check(standby.energy == 200, "another craft's occupied patient costs the waiting Medivac no energy")
	current.energy = 0
	var before: float = patient.hp
	ticks(sim, 6)
	check(patient.hp > before and sim.active_beams.size() == 1 and sim.active_beams[0].source_id == standby.id, "ending a channel releases the patient to the other Medivac")
	patient.pos = field(7,0)
	before = patient.hp
	ticks(sim, 4)
	check(patient.hp == before and sim.active_beams.is_empty(), "discovery range alone cannot keep an out-of-range beam active")
	patient.pos = field(1,0)
	ticks(sim, 4)
	check(patient.hp > before, "returning to healing range starts a fresh channel")
	patient.hp = sim.catalog.rifle.hp
	ticks(sim, 2)
	check(sim.active_beams.is_empty(), "full patients release the healing channel")


func _medivac_patient_priority() -> void:
	var sim = bare()
	tune(sim, "medivac", {"speed":0, "energy_regen":0})
	tune(sim, "hellbat_mech", {"speed":0, "damage":0, "skills":{}})
	tune(sim, "rifle", {"speed":0, "damage":0, "skills":{}})
	sim.spawn_unit(0, "medivac", field(0,0))
	var primary: Dictionary = sim.spawn_unit(0, "hellbat_mech", field(2,0))
	var other_hellbat: Dictionary = sim.spawn_unit(0, "hellbat_mech", field(-2,0))
	var rifle: Dictionary = sim.spawn_unit(0, "rifle", field(0,2))
	primary.hp = 33
	other_hellbat.hp = 45
	rifle.hp = 20
	ticks(sim, 4)
	check(primary.hp > 33 and rifle.hp > 20 and other_hellbat.hp == 45, "primary prefers lowest life fraction, secondary prefers lowest current life and biological-mechanical units qualify")
