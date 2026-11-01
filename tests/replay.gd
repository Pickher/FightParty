extends SceneTree
const Sim=preload("res://scripts/battle_sim.gd")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	var path: String=args[0] if not args.is_empty() else "user://last_match.json"
	var record=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not record is Dictionary or not record.has("result"):
		printerr("Replay requires a complete match journal")
		quit(1)
		return
	var sim=Sim.new(int(record.seed))
	if record.rules_version!=sim.rules.version:
		printerr("Rules version mismatch")
		quit(1)
		return
	var index:=0
	while not sim.finished:
		if index<record.waves.size() and int(record.waves[index].tick)==sim.tick+1:
			for team in range(2):
				if sim.submit_formation(team,record.waves[index].formations[team])!="":
					printerr("Invalid recorded formation")
					quit(1)
					return
			index+=1
		sim.step()
	var same: bool=sim.winner==int(record.result.winner) and sim.tick==int(record.result.tick)
	for team in range(2):same=same and is_equal_approx(float(sim.bases[team]),float(record.result.bases[team]))
	print("REPLAY: ","PASS" if same else "FAIL", " tick=",sim.tick," winner=",sim.winner)
	quit(0 if same else 1)
