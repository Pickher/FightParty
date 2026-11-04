# 中文导读：渲染性能测试。它会打开真实游戏画面，采样约 10 秒，不是正常游玩入口。
# 这里测帧数/真实经过秒数；与 test_sim.gd 的“每个模拟步耗时”是不同指标。
extends SceneTree

## 等待场景树就绪后开始采样。
func _initialize() -> void:
	call_deferred("run")

## 生成 200 个高血量单位保持压力，保留主场景的自动模拟与绘图，统计实际画面帧数。
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.started=true
	game.sim.formations=[[],[]]
	for team in range(2):
		for i in range(100):
			var unit: Dictionary=game.sim.spawn_unit(team,"marauder",Vector2(400+team*400+(i%10)*4,30+(i/10)*34))
			unit.hp=1000000.0
	var begin:=Time.get_ticks_usec()
	var frames:=0
	while Time.get_ticks_usec()-begin<10000000:
		await process_frame
		frames+=1
	var duration: float=float(Time.get_ticks_usec()-begin)/1000000.0
	print("RENDER PERF: %d units, %d frames / %.3f sec = %.2f FPS, sim ticks=%d" % [game.sim.units.size(),frames,duration,frames/duration,game.sim.tick])
	quit()
