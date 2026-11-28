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

func _capture_path() -> String:
	var destination := "user://ui-smoke.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):destination=arg.trim_prefix("--capture=")
	return destination

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
	var options: Dictionary = game.sim.rules.setup_options
	var wave_option: Dictionary = options.wave_seconds
	game.handle_action("setup_pick:start_minerals:1000")
	game.handle_action("setup_step:wave_seconds:1")
	game.handle_action("setup_confirm")
	verify(not game.setup_open and int(game.sim.rules.wave_seconds)==int(wave_option.recommended)+int(wave_option.step) and int(game.sim.rules.start_minerals)==1000,"custom settings applied")
	verify(game.sim.minerals==[1000,1000] and game.sim.formations==[[],[]] and game.sim.journal.settings.start_minerals==1000,"chosen start funds recorded")
	game.handle_action("restart")
	verify(game.setup_open and game.custom_fields.has("wave_seconds"),"restart reopens setup with previous custom values")
	game.handle_action("setup_reset")
	verify(game.race_choices==["terran","random"],"reset restores recommended races")
	game.handle_action("setup_race:1:zerg")
	game.handle_action("setup_confirm")
	verify(int(game.sim.rules.wave_seconds)==int(wave_option.recommended) and int(game.sim.journal.settings.start_minerals)==int(options.start_minerals.recommended),"reset restores recommended settings")
	verify(game.sim.races==["terran","zerg"] and game.sim.journal.settings.races==["terran","zerg"],"chosen races applied and journaled")
	verify(game._shop_kinds().all(func(k): return game.sim.catalog[k].race=="terran"),"shop lists own race only")
	verify(game.sim.formations==[[],[]],"both races begin with empty barracks")
	_empty_starts_all_races()
	_saved_medic_migration()
	game.handle_action("clear")
	# 推荐开局资金买不起医疗运输机、幽灵、雷神、大和舰；编辑器路径测试直接补足资源。
	game.sim.minerals[0] = 20000
	game.sim.economy.gas[0] = 2000
	game.handle_action("select:hellbat")
	game.handle_action("cell:5")
	verify(game.sim.formations[0].size()==1,"place")
	game.handle_action("move")
	game.handle_action("cell:5")
	game.handle_action("cell:11")
	verify(game.sim.formations[0][0].cell==11,"move")
	game.handle_action("erase")
	game.handle_action("cell:11")
	verify(game.sim.formations[0].is_empty(),"erase")
	game.handle_action("select:medivac")
	game.handle_action("cell:0")
	verify(game.sim.formations[0][0].kind=="medivac","place medivac")
	game.handle_action("move")
	game.handle_action("cell:0")
	game.handle_action("cell:6")
	verify(game.sim.formations[0][0].cell==6,"move medivac")
	game.handle_action("erase")
	game.handle_action("cell:6")
	verify(game.sim.formations[0].is_empty(),"erase medivac")
	game.handle_action("select:mortar")
	game.handle_action("cell:1")
	verify(game.sim.formations[0][0].kind=="mortar","place mortar")
	game.handle_action("move")
	game.handle_action("cell:1")
	game.handle_action("cell:7")
	verify(game.sim.formations[0][0].cell==7,"move mortar")
	game.handle_action("erase")
	game.handle_action("cell:7")
	verify(game.sim.formations[0].is_empty(),"erase mortar")
	game.handle_action("select:ghost")
	game.handle_action("cell:2")
	verify(game.sim.formations[0][0].kind=="ghost","place ghost")
	game.handle_action("move")
	game.handle_action("cell:2")
	game.handle_action("cell:8")
	verify(game.sim.formations[0][0].cell==8,"move ghost")
	game.handle_action("erase")
	game.handle_action("cell:8")
	verify(game.sim.formations[0].is_empty(),"erase ghost")
	game.handle_action("units_next")
	verify(game.unit_page==1,"next unit page")
	game.handle_action("select:viking_assault")
	game.handle_action("cell:3")
	verify(game.sim.formations[0][0].kind=="viking_assault","recruit Viking assault mech from the Terran shop")
	game.handle_action("erase")
	game.handle_action("cell:3")
	game.handle_action("select:thor")
	game.handle_action("cell:3")
	verify(game.sim.formations[0][0].kind=="thor","place thor from second page")
	game.handle_action("move")
	game.handle_action("cell:3")
	game.handle_action("cell:9")
	verify(game.sim.formations[0][0].cell==9,"move thor")
	game.handle_action("erase")
	game.handle_action("cell:9")
	verify(game.sim.formations[0].is_empty(),"erase thor")
	var kinds: Array = game._shop_kinds()
	var last_page := ceili(float(kinds.size()) / game.UNITS_PER_PAGE) - 1
	game.handle_action("select:battlecruiser")
	game.handle_action("cell:4")
	verify(game.unit_page==int(kinds.find("battlecruiser") / game.UNITS_PER_PAGE) and game.sim.formations[0][0].kind=="battlecruiser","place battlecruiser from its shop page")
	game.handle_action("erase")
	game.handle_action("cell:4")
	verify(game.sim.formations[0].is_empty(),"erase battlecruiser")
	game.handle_action("select:"+str(kinds.back()))
	game.handle_action("units_next")
	verify(game.unit_page==0,"unit pages wrap forward")
	game.handle_action("units_prev")
	verify(game.unit_page==last_page,"unit pages wrap backward")
	game.handle_action("select:rifle")
	verify(game.unit_page==0,"select keeps chosen card visible")
	await _tower_placement_flow()
	# 完整对局只用会写入战报的设置：开局资金来自设置，缩短的波数与终局上限进入 settings，
	# 因此 tests/replay.gd 能逐 tick 复现这一局。默认 64 波整局与终局规则由 test_sim 的 _final_phase 覆盖。
	game.handle_action("restart")
	game.handle_action("setup_pick:start_minerals:%d" % int(options.start_minerals.max))
	game.match_settings.wave_limit = 3
	game.match_settings.final_phase_max_seconds = 120
	game.handle_action("setup_confirm")
	verify(game.sim.races==["terran","zerg"] and int(game.sim.journal.settings.wave_limit)==3,"replayable match settings journaled")
	# 混编覆盖劫掠者、喷火直线攻击与幽灵技能的完整对局。
	game._commit([{"kind":"marauder","cell":5},{"kind":"hellbat","cell":8},{"kind":"ghost","cell":6}])
	game.handle_action("start")
	game.accumulator=0.025
	game.handle_action("battle_layout")
	verify(game.formation_panel.opened and is_equal_approx(game.accumulator,0.025),"opening formation preserves fractional simulation time")
	var before_panel: int=game.sim.tick
	game._process(0.1)
	verify(game.sim.tick>before_panel,"running simulation continues with formation open")
	game.handle_action("formation:close")
	game.handle_action("start")
	game.handle_action("battle_layout")
	var before: int=game.sim.tick
	game._process(0.2)
	verify(game.sim.tick==before,"manual pause remains paused with formation open")
	game.handle_action("formation:close")
	game.handle_action("start")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	game._process(0.2)
	verify(game.sim.tick==before,"background stops ticks")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	# 第一波出场后、交战前：敌方种族、阵容与兵种外形都不公开。
	game.handle_action("battle_layout")
	while game.sim.wave < 1:game.advance_tick()
	verify(game.formation_panel.opened and not game.sim.last_formations[1].is_empty() and game.sim.last_formations[1].all(func(slot):return game.sim.catalog[slot.kind].race=="zerg"),"AI buys its own race on normal income before first wave with formation open")
	game.handle_action("formation:close")
	for i in range(10):game.advance_tick()
	verify(not game.sim.revealed and game.sim.visible_enemy_formation(0).is_empty() and game.sim.visible_race(0,1)=="","enemy hidden before first engagement")
	game.effects.clear()
	game.queue_redraw()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_capture_path().replace(".png","-hidden.png"))
	for i in range(1500):game.advance_tick()
	verify(game.sim.revealed and game.sim.visible_race(0,1)=="zerg","races revealed after engagement")
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
	verify(game.sim.formations[0].size()==3 and game.sim.minerals[0]==minerals_before-int(game.sim.catalog.rifle.cost),"buy into freed cell")
	game.effects.clear()
	game.selected="rifle"
	game.queue_redraw()
	for i in range(90):await process_frame
	game.queue_redraw()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var destination := _capture_path()
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
	# 不写预设文件：验证每个种族都从空兵营开始，同族预设只在显式载入时使用。
	game.handle_action("restart")
	game.handle_action("setup_reset")
	game.handle_action("setup_race:0:zerg")
	game.handle_action("setup_confirm")
	verify(game.sim.races[0]=="zerg" and game.selected=="zergling","player plays zerg with a zerg card selected")
	var preset_config := ConfigFile.new()
	var old_point: Array = [0.55,-2.264286]
	preset_config.set_value("player","formation_zerg",[{"kind":"zergling","cell":63,"member_positions":[old_point]}])
	game.handle_action("restart")
	game.handle_action("setup_race:0:terran")
	game.handle_action("setup_confirm")
	verify(game.sim.formations[0].is_empty() and game._read_formation_preset(preset_config).is_empty(),"terran roster does not inherit zerg units or preset")
	game.handle_action("restart")
	game.handle_action("setup_race:0:zerg")
	game.handle_action("setup_pick:start_minerals:600")
	game.handle_action("setup_confirm")
	verify(game.sim.formations[0].is_empty() and int(game.sim.minerals[0])==600,"returning to zerg does not auto-buy a saved roster")
	game.saved_formation_preset=game._read_formation_preset(preset_config)
	var preserved: Array = game.saved_formation_preset.duplicate(true)
	var price: int = int(game.sim.catalog.zergling.cost)
	verify(game._load_formation_preset()=="" and game.sim.formations[0].size()==1 and int(game.sim.minerals[0])==600-price,"legacy zerg roster explicitly loaded at its current group price")
	if not game.sim.formations[0].is_empty():
		var slot: Dictionary = game.sim.formations[0][0]
		var points: Array = slot.get("member_positions",[])
		verify(slot.kind=="zergling" and int(slot.cell)==63 and points.size()==4,"legacy zergling group expands to four members")
		if points.size()==4:
			verify(points[0]==old_point,"migration preserves the legacy point overlapping a new default")
			for i in range(points.size()):
				for j in range(i):
					var a := Vector2(float(points[i][0]),float(points[i][1]))
					var b := Vector2(float(points[j][0]),float(points[j][1]))
					verify(a.distance_to(b)>=1.0998,"generated zerglings clear same-layer occupants")
	verify(game.saved_formation_preset==preserved,"loading does not rewrite the legacy preset")
	game.handle_action("restart")
	game.handle_action("setup_reset")
	game.handle_action("setup_confirm")
	print("UI SMOKE: ","FAIL" if failed else "PASS", " capture=",destination if DisplayServer.get_name() != "headless" else "skipped (headless)")
	game.speaker.stop()
	game.speaker.stream = null
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)

## 发送原生单指触屏事件，位置使用实际窗口坐标，包括宽屏留边。
func _tower_touch(pressed: bool, screen_point: Vector2) -> void:
	var finger := InputEventScreenTouch.new()
	finger.index = 0
	finger.pressed = pressed
	finger.position = screen_point
	game._gui_input(finger)

func _tower_placement_flow() -> void:
	var site: Vector2 = game.sim.suggested_tower_position(0)
	var funds: int = game.sim.minerals[0]
	var cost: int = game.sim.catalog[game.sim.tower_kind(0)].cost
	game._set_camera_scale(32.0)
	game.camera_center = site + Vector2(-4,2)
	var view: Rect2 = game._camera_rect()
	game.handle_action("build_tower")
	verify(game.placing_tower and not game.tower_preview_visible and game._camera_rect()==view,"placement from battle preserves its camera and starts without a ghost")
	game.handle_action("build_tower")
	verify(not game.placing_tower and game.sim.minerals[0]==funds,"the build button cancels site selection without charging")
	game.handle_action("build_tower")
	await process_frame
	await process_frame
	var point: Vector2 = game._ui_origin() + game._world(site)*game._ui_scale()
	_tower_touch(true,point)
	verify(not game.tower_preview_visible,"touch down cannot propose a tower site")
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.relative = Vector2(70,0)*game._ui_scale()
	drag.position = point+drag.relative
	game._gui_input(drag)
	_tower_touch(false,drag.position)
	verify(game._camera_rect()!=view and game.placing_tower and not game.tower_preview_visible,"drag pans the battlefield without proposing a site on release")
	point = game._ui_origin()+game._world(site)*game._ui_scale()
	_tower_touch(true,point)
	_tower_touch(false,point)
	verify(game.tower_preview_visible and game.tower_preview.is_equal_approx(site) and not game.sim.tower_alive(0),"a touch tap previews the selected world position without building")
	game.handle_action("tower_reselect")
	verify(game.placing_tower and not game.tower_preview_visible and game.sim.minerals[0]==funds,"cancel in the confirmation returns to free site selection")
	await process_frame
	await process_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = point
	click.pressed = true
	game._gui_input(click)
	verify(not game.tower_preview_visible,"mouse down does not select a site")
	click.pressed = false
	game._gui_input(click)
	verify(game.tower_preview_visible and game.sim.minerals[0]==funds,"mouse release requests confirmation before charging")
	await process_frame
	await process_frame
	var confirm_buttons: Array = game.buttons.filter(func(b): return b.action=="tower_confirm")
	verify(confirm_buttons.size()==1,"tower preview offers a confirmation button")
	if confirm_buttons.size()!=1:return
	var confirm_center: Vector2 = game._ui_origin()+confirm_buttons[0].rect.get_center()*game._ui_scale()
	_tower_touch(true,confirm_center)
	verify(not game.sim.tower_alive(0),"touching confirm does not spend before release")
	drag.relative=Vector2(24,0)*game._ui_scale()
	drag.position=confirm_center+drag.relative
	game._gui_input(drag)
	_tower_touch(false,confirm_center)
	verify(game.tower_preview_visible and game.sim.minerals[0]==funds,"sliding off and back onto confirm does not buy")
	_tower_touch(true,confirm_center)
	_tower_touch(false,confirm_center)
	game.handle_action("tower_confirm")
	verify(not game.placing_tower and not game.tower_preview_visible and game.sim.tower_alive(0) and game.sim.minerals[0]==funds-cost,"only one confirmed purchase is charged")
	var towers: Array = game.sim.units.filter(func(u): return u.team==0 and u.kind==game.sim.tower_kind(0))
	verify(towers.size()==1 and towers[0].pos.is_equal_approx(site),"built tower matches ghost position")
	game.handle_action("build_tower")
	verify(not game.placing_tower,"a live tower disables further site selection")
	if towers.size()==1:
		towers[0].hp=0
		game.advance_tick()
		game.handle_action("build_tower")
		verify(not game.placing_tower and game.messages[0]=="60秒后才能再次建造","cooldown click reports the remaining seconds")

## 仅准备待运行回归：不写设置文件，检查迁移先于提交/恢复排布。
func _saved_medic_migration() -> void:
	var saved: Array = [
		{"kind":"hellbat","cell":2,"member_positions":[[-4,0],[-4,2]]},
		{"kind":"medic","cell":3,"member_positions":[[-4,0]]},
		{"kind":"hellbat","cell":9,"member_positions":[[4,0],[4,2]]}
	]
	var untouched: Array = saved.duplicate(true)
	var migrated: Array = game._migrate_saved_formation(saved)
	verify(migrated==[saved[0],saved[2]] and saved==untouched,"migration retains other slots and exact positions without modifying input")
	verify(not migrated.any(func(slot):return slot.kind=="medivac"),"migration never substitutes medivac")
	game.sim.submit_formation(0,[])
	game.sim.minerals[0]=20000
	verify(game.sim.submit_formation(0,migrated)=="" and game._restore_deployment(migrated)=="","retained formation and positions restore after retired medic removed")
	verify(game.sim.formations[0].size()==2 and game.sim.formations[0][0].member_positions==saved[0].member_positions and game.sim.formations[0][1].member_positions==saved[2].member_positions,"retained member positions are not reset")
	# 显式读取历史特工预设并恢复到本局，新兵种仍占原来的格位和单兵坐标。
	game.sim.submit_formation(0,[])
	var old_preset: Array = [{"kind":"agent","cell":4,"member_positions":[[-1,0]]}]
	var previous_preset: Array = game.saved_formation_preset
	game.saved_formation_preset = old_preset
	verify(game._load_formation_preset()=="","restore a legacy Ghost preset")
	var slots: Array = game.sim.formations[0]
	verify(slots.size()==1 and slots[0].kind=="ghost" and slots[0].cell==4 and slots[0].member_positions==old_preset[0].member_positions,"legacy Ghost keeps its cell and member position")
	verify(old_preset[0].kind=="agent","loading leaves the original preset intact")
	game.saved_formation_preset = previous_preset
	var only_medic: Array = game._migrate_saved_formation([saved[1]])
	verify(only_medic.is_empty() and game.sim.submit_formation(0,only_medic)=="" and game.sim.formations[0].is_empty(),"medic-only save intentionally restores empty army, not starter")
	verify(game._migrate_saved_formation([{"kind":"unknown","cell":0},17]).size()==2,"migration does not hide unrelated invalid entries")
	game.sim.races[0]="zerg"
	verify(game._migrate_saved_formation(saved)==saved,"other races retain existing validation behavior")
	game.sim.races[0]="terran"
	game.sim.catalog.medic.available=true
	verify(game._migrate_saved_formation(saved)==saved,"re-enabled medic is not removed")
	game.sim.catalog.medic.available=false

## Regression fixture only; no saved file writes from these helpers.
func _empty_starts_all_races() -> void:
	var choices: Array=game.race_choices.duplicate()
	for race in ["terran","zerg","protoss","blight"]:
		game.race_choices=[race,race]
		game._new_match()
		verify(game.sim.races==[race,race] and game.sim.formations==[[],[]],race+" has no system starter for either side")
		verify(game.sim.minerals==[int(game.sim.rules.start_minerals),int(game.sim.rules.start_minerals)],race+" starts without purchases")
	game.race_choices=choices
	game._new_match()
	var saved: Array=[{"kind":"hellbat","cell":2,"member_positions":[[-4,0]]}]
	game.saved_formation_preset=saved
	game.sim.minerals[0]=0
	verify(game._load_formation_preset()!="" and game.sim.formations[0].is_empty(),"insufficient resources leave preset unloaded")
	game.sim.minerals[0]=20000
	game.saved_formation_preset=[{"kind":"hellbat","cell":2,"member_positions":[[9999,0]]}]
	var actions_before: int=game.sim.journal.actions.size()
	verify(game._load_formation_preset()!="" and game.sim.formations[0].is_empty() and game.sim.minerals[0]==20000 and game.sim.journal.actions.size()==actions_before,"invalid positions do not purchase, spend, or journal")
	game.saved_formation_preset=saved
	verify(game._load_formation_preset()=="" and game.sim.formations[0].size()==1 and game.sim.minerals[0]==20000-460,"legacy Hellion slot buys one current pack")
	if game.sim.formations[0].size()==1:
		var points: Array = game.sim.formations[0][0].get("member_positions",[])
		verify(points.size()==2 and points[0]==saved[0].member_positions[0] and points[1]!=points[0],"legacy Hellion keeps its position and the second vehicle receives its own")
	game._new_match()
	verify(game.sim.formations==[[],[]],"a preset never auto-applies in a new match")
