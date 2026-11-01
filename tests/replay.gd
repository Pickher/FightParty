# 中文导读：读取已完成的本地战报，按原波次重放阵容，检查最终结果是否一致。
# 默认 user://last_match.json；也可在命令行 -- 后传入另一个战报路径。
# 必须使用相同规则版本和配置；修改了兵种数值后，旧战报不保证得到相同结果。
extends SceneTree
const Sim=preload("res://scripts/battle_sim.gd")

## 检查日志和版本 → 在每个出兵边界前提交记录的阵容 → 推进至结束 → 比较结果。
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
		# 在下一次 step 即将触发出兵时提交那一波的阵容，保持原对局的时间顺序。
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
