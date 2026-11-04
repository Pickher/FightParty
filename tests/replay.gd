# 中文导读：读取已完成的本地战报，按原 tick 重放双方的买、卖、移动操作，检查最终结果是否一致。
# 默认 user://last_match.json；也可在命令行 -- 后传入另一个战报路径。
# 必须使用相同规则版本和配置；修改了兵种数值后，旧战报不保证得到相同结果。
extends SceneTree
const Sim=preload("res://scripts/battle_sim.gd")

## 检查日志和版本 → 每步前提交该 tick 记录的操作 → 推进至结束 → 比较结果。
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	var path: String=args[0] if not args.is_empty() else "user://last_match.json"
	var record=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not record is Dictionary or not record.has("result") or not record.has("actions"):
		printerr("Replay requires a complete match journal")
		quit(1)
		return
	var sim=Sim.new(int(record.seed),record.get("settings",{}))
	if record.rules_version!=sim.rules.version:
		printerr("Rules version mismatch")
		quit(1)
		return
	var index:=0
	while not sim.finished:
		# 原对局的操作发生在第 tick 步结束之后、下一步开始之前。
		while index<record.actions.size() and int(record.actions[index].tick)==sim.tick:
			if sim.apply_action(record.actions[index])!="":
				printerr("Invalid recorded action at index %d" % index)
				quit(1)
				return
			index+=1
		sim.step()
	var same: bool=sim.winner==int(record.result.winner) and sim.tick==int(record.result.tick)
	for team in range(2):same=same and is_equal_approx(float(sim.bases[team]),float(record.result.bases[team]))
	print("REPLAY: ","PASS" if same else "FAIL", " tick=",sim.tick," winner=",sim.winner)
	quit(0 if same else 1)
