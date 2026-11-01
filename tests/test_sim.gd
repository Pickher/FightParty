# 中文导读：自动验证战斗规则的开发脚本，不是玩家游戏入口。
# 运行命令见 README；不需要打开游戏窗口，也不会修改玩家存档。
# 测试中不少数值固定对应 v0.1 的基线；有意改平衡后，应检查预期而非直接删除失败测试。
extends SceneTree
const Sim = preload("res://scripts/battle_sim.gd")
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
	_counter("sniper",2,"mortar",2,"sniper vs fragile artillery")
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
