extends SceneTree
var game
var failed := false

func _initialize() -> void:
	call_deferred("run")

func verify(ok: bool, message: String) -> void:
	if not ok:
		failed=true
		printerr("UI FAIL: "+message)

func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
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
