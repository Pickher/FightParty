extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.started=true
	game.sim.formations=[[],[]]
	for team in range(2):
		for i in range(100):
			var unit: Dictionary=game.sim.spawn_unit(team,"guard",Vector2(400+team*400+(i%10)*4,30+(i/10)*34))
			unit.hp=1000000.0
	var begin:=Time.get_ticks_usec()
	var frames:=0
	while Time.get_ticks_usec()-begin<10000000:
		await process_frame
		frames+=1
	var duration: float=float(Time.get_ticks_usec()-begin)/1000000.0
	print("RENDER PERF: %d units, %d frames / %.3f sec = %.2f FPS, sim ticks=%d" % [game.sim.units.size(),frames,duration,frames/duration,game.sim.tick])
	quit()
