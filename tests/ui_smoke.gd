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
	await process_frame
	# 测试主动控制模拟时间，关闭每帧自动推进以避免时间不确定；绘图仍可按需触发。
	game.set_process(false)
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
	game._commit(preload("res://scripts/catalog.gd").starter())
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
	game.effects.clear()
	game.selected="rifle"
	game.queue_redraw()
	for i in range(90):await process_frame
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var destination := "user://ui-smoke.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):destination=arg.trim_prefix("--capture=")
	root.get_texture().get_image().save_png(destination)
	while not game.sim.finished:game.advance_tick()
	verify(game.sim.journal.has("result"),"full match reaches recorded result")
	game.effects.clear()
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(destination.replace(".png","-result.png"))
	game.handle_action("restart")
	verify(not game.started and not game.sim.finished and game.sim.tick==0,"restart resets match")
	print("UI SMOKE: ","FAIL" if failed else "PASS", " capture=",destination)
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
