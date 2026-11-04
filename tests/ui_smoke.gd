# 中文导读：真实主场景的程序化冒烟测试，验证基本按钮路径和完整对局并截图。
# 注意：它会调用真实存档逻辑，覆盖本机最近阵容/战报。学习玩法时直接 F5，不要运行此脚本。
extends SceneTree
var game
var failed := false

## 延后到场景树准备好后运行测试。
func _initialize() -> void:
	call_deferred("run")

## 记录界面测试是否失败，结束时统一返回退出码。
func verify(ok: bool, message: String) -> void:
	if not ok:
		failed=true
		printerr("UI FAIL: "+message)

## 加载真实游戏场景，依次模拟编辑、暂停、后台通知、完成一局和重开。
## 截图必须等待 RenderingServer.frame_post_draw，确保这一帧已经绘制完。
func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	# 无窗口模式不验证音频；避免极速退出时混音线程仍持有播放对象。
	if DisplayServer.get_name() == "headless":game.speaker.stream = null
	await process_frame
	# 测试主动控制模拟时间，关闭每帧自动推进以避免时间不确定；绘图仍可按需触发。
	game.set_process(false)
	# 开局设置：弹窗挡住其他操作；预设、自定义步进、确认后按设置建局；重开再弹出并可恢复推荐。
	verify(game.setup_open,"setup popup shown before match")
	game.handle_action("start")
	verify(not game.started,"setup blocks start")
	game.handle_action("setup_pick:start_minerals:1000")
	game.handle_action("setup_step:wave_seconds:1")
	game.handle_action("setup_step:wave_income:-1")
	game.handle_action("setup_confirm")
	verify(not game.setup_open and game.sim.rules.wave_seconds==35 and game.sim.rules.wave_income==250,"custom settings applied")
	verify(game.sim.minerals[1]<=1000 and game.sim.journal.settings.start_minerals==1000,"chosen start funds recorded")
	game.handle_action("restart")
	verify(game.setup_open and game.custom_fields.has("wave_seconds"),"restart reopens setup with previous custom values")
	game.handle_action("setup_reset")
	game.handle_action("setup_confirm")
	verify(game.sim.rules.wave_seconds==30 and game.sim.rules.wave_income==300 and game.sim.journal.settings.start_minerals==600,"reset restores recommended settings")
	game.handle_action("clear")
	game.handle_action("select:guard")
	game.handle_action("cell:5")
	verify(game.sim.formations[0].size()==1,"place")
	game.handle_action("move")
	game.handle_action("cell:5")
	game.handle_action("cell:11")
	verify(game.sim.formations[0][0].cell==11,"move")
	game.handle_action("erase")
	game.handle_action("cell:11")
	verify(game.sim.formations[0].is_empty(),"erase")
	game.handle_action("select:medic")
	game.handle_action("cell:0")
	verify(game.sim.formations[0][0].kind=="medic","place medic")
	game.handle_action("move")
	game.handle_action("cell:0")
	game.handle_action("cell:6")
	verify(game.sim.formations[0][0].cell==6,"move medic")
	game.handle_action("erase")
	game.handle_action("cell:6")
	verify(game.sim.formations[0].is_empty(),"erase medic")
	game.handle_action("select:piercer")
	game.handle_action("cell:1")
	verify(game.sim.formations[0][0].kind=="piercer","place piercer")
	game.handle_action("move")
	game.handle_action("cell:1")
	game.handle_action("cell:7")
	verify(game.sim.formations[0][0].cell==7,"move piercer")
	game.handle_action("erase")
	game.handle_action("cell:7")
	verify(game.sim.formations[0].is_empty(),"erase piercer")
	game.handle_action("select:colossus")
	game.handle_action("cell:2")
	verify(game.sim.formations[0][0].kind=="colossus","place colossus")
	game.handle_action("move")
	game.handle_action("cell:2")
	game.handle_action("cell:8")
	verify(game.sim.formations[0][0].cell==8,"move colossus")
	game.handle_action("erase")
	game.handle_action("cell:8")
	verify(game.sim.formations[0].is_empty(),"erase colossus")
	game.handle_action("units_next")
	verify(game.unit_page==1,"next unit page")
	game.handle_action("select:marauder")
	game.handle_action("cell:3")
	verify(game.sim.formations[0][0].kind=="marauder","place marauder from second page")
	game.handle_action("move")
	game.handle_action("cell:3")
	game.handle_action("cell:9")
	verify(game.sim.formations[0][0].cell==9,"move marauder")
	game.handle_action("erase")
	game.handle_action("cell:9")
	verify(game.sim.formations[0].is_empty(),"erase marauder")
	game.handle_action("units_next")
	verify(game.unit_page==0,"unit pages wrap forward")
	game.handle_action("units_prev")
	verify(game.unit_page==1,"unit pages wrap backward")
	game.handle_action("select:rifle")
	verify(game.unit_page==0,"select keeps chosen card visible")
	# 565 预算混编，覆盖劫掠者及两种传播攻击的完整对局。
	game._commit([{"kind":"marauder","cell":5},{"kind":"piercer","cell":8},{"kind":"colossus","cell":6}])
	game.handle_action("start")
	game.handle_action("start")
	var before: int=game.sim.tick
	game._process(0.2)
	verify(game.sim.tick==before,"pause stops ticks")
	game.handle_action("start")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	game._process(0.2)
	verify(game.sim.tick==before,"background stops ticks")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	for i in range(1500):game.advance_tick()
	# 已出场单位取消不退款：先弹确认，拒绝后兵营不变，确认后移除且矿物不变。
	var deployed_cell: int=int(game.sim.formations[0][0].cell)
	var minerals_before: int=int(game.sim.minerals[0])
	game.handle_action("erase")
	game.handle_action("cell:%d" % deployed_cell)
	verify(game.pending_message!="" and game.sim.formations[0].size()==3,"deployed cancel asks for confirmation")
	game.handle_action("confirm_no")
	verify(game.pending_message=="" and game.sim.formations[0].size()==3,"confirmation can be declined")
	game.handle_action("cell:%d" % deployed_cell)
	game.handle_action("confirm_yes")
	verify(game.sim.formations[0].size()==2 and game.sim.minerals[0]==minerals_before,"confirmed deployed cancel gives no refund")
	game.handle_action("select:rifle")
	game.handle_action("cell:%d" % deployed_cell)
	verify(game.sim.formations[0].size()==3 and game.sim.minerals[0]==minerals_before-75,"buy into freed cell")
	# 防御塔：矿物足够时建成一座，再按一次被拒绝。
	var affordable: bool=int(game.sim.minerals[0])>=int(game.sim.catalog.tower.cost)
	game.handle_action("build_tower")
	verify(game.sim.tower_builds[0]==(1 if affordable else 0),"build tower button")
	game.handle_action("build_tower")
	verify(game.sim.tower_builds[0]<=1,"only one tower")
	game.effects.clear()
	game.selected="rifle"
	game.queue_redraw()
	for i in range(90):await process_frame
	game.queue_redraw()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var destination := "user://ui-smoke.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):destination=arg.trim_prefix("--capture=")
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png(destination)
	while not game.sim.finished:game.advance_tick()
	verify(game.sim.journal.has("result"),"full match reaches recorded result")
	game.effects.clear()
	game.queue_redraw()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png(destination.replace(".png","-result.png"))
	game.handle_action("restart")
	verify(not game.started and not game.sim.finished and game.sim.tick==0 and game.setup_open,"restart resets match and reopens setup")
	game.handle_action("setup_pick:start_minerals:0")
	game.queue_redraw()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(destination.replace(".png","-setup.png"))
	game.handle_action("setup_confirm")
	verify(game.sim.minerals==[0,0] and game.sim.formations[0].is_empty(),"zero start funds leave roster empty")
	print("UI SMOKE: ","FAIL" if failed else "PASS", " capture=",destination if DisplayServer.get_name() != "headless" else "skipped (headless)")
	game.speaker.stop()
	game.speaker.stream = null
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
