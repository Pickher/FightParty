# 中文导读：18×8 满兵营的大规模对战性能基准，不是正确性测试。
# 双方用 AI 买满 144 格，连续出兵若干波，输出每步平均/最慢耗时与峰值单位数。
extends SceneTree
const Sim = preload("res://scripts/battle_sim.gd")
const AI = preload("res://scripts/commander_ai.gd")

func _initialize() -> void:
	var waves := 8
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--waves="):waves=int(arg.trim_prefix("--waves="))
	var sim = Sim.new(5,{"start_minerals":100000,"wave_income":0})
	for team in range(2):
		for slot in AI.new(team+1).buy_list([],[],100000):
			sim.buy(team,slot.kind,slot.cell)
	var total := 0.0
	var worst := 0.0
	var peak := 0
	var count := 0
	while sim.wave < waves or sim.tick % sim.wave_ticks() != 0:
		var begin := Time.get_ticks_usec()
		sim.step()
		var spent: float = float(Time.get_ticks_usec()-begin)/1000.0
		total += spent
		worst = maxf(worst,spent)
		peak = maxi(peak,sim.units.size())
		count += 1
		if sim.finished:
			break
	print("CROWD roster %d+%d, %d ticks, %d waves: avg %.2f ms/tick, worst %.2f ms, peak %d units, bases %s" % [sim.formations[0].size(),sim.formations[1].size(),count,sim.wave,total/count,worst,peak,str(sim.bases)])
	quit()
