## 验证 Excel 新增兵种相关的界面翻页与 AI 行为。仅修改内存，不写配置和玩家存档。
## godot --headless --path . --script res://tests/test_unit_editor.gd
extends SceneTree
const Main = preload("res://scripts/main.gd")
const AI = preload("res://scripts/commander_ai.gd")
const Sim = preload("res://scripts/battle_sim.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var main = Main.new()
	root.add_child(main)
	main.sim.catalog["assassin"] = main.sim.catalog.rifle.duplicate(true)
	main.sim.catalog.assassin.name = "测试刺客"
	main.handle_action("unit_next")
	check(main.unit_page == 1, "第七个兵种应有第二页")
	main.handle_action("select:assassin")
	check(main.selected == "assassin", "新增兵种可选中")
	main.handle_action("unit_next")
	check(main.unit_page == 0, "下一页循环到首页")
	main.handle_action("unit_prev")
	check(main.unit_page == 1, "上一页循环到末页")
	var ai = AI.new(42)
	ai.catalog = main.sim.catalog.duplicate(true)
	var seen := false
	for i in range(100):
		var formation: Array = ai.choose([], 600)
		check(main.sim.validate_formation(formation, 600) == "", "AI 必须遵守预算")
		for slot in formation:
			if slot.kind == "assassin":
				seen = true
	check(seen, "AI 能购买新增兵种")
	# 将所有旧兵种改为买不起，只留下新增兵种，确认保底选择按实际价格。
	for kind in ai.catalog:
		ai.catalog[kind].cost = 1000
	ai.catalog.assassin.cost = 50
	var cheap: Array = ai.choose([], 600)
	check(cheap.size() == 12, "AI 应使用新的最低价兵种")
	for slot in cheap:
		check(slot.kind == "assassin", "最低价选择错误")
	# 等待绘制回调，覆盖含新增卡片的 UI 代码路径。
	await process_frame
	await process_frame
	main.queue_free()
	print("Unit editor failures: ", failures)
	quit(0 if failures == 0 else 1)
