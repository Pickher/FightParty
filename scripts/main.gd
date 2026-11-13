# 中文导读：游戏入口，负责界面、输入、本地对局调度和存档。战斗规则在 battle_sim.gd。
# Control 是 2D 界面节点。_ready / _process / _draw 等以下划线开头的回调由 Godot 自动调用。
# 初学时先找到 handle_action（按钮做什么）和 _draw_editor（配兵界面长什么样）。
# 当前 UI 是代码直接绘制的，编辑器里不会出现每张卡片的独立 Button 节点。
# 将来升级 3D 时可替换战场表现，继续使用 sim 计算出的状态和事件。
extends Control
const UnitSummary = preload("res://scripts/unit_summary.gd")
const UnitArt = preload("res://scripts/unit_art.gd")
const BattleView = preload("res://scripts/battle_view.gd")
# preload 在脚本加载时引入其他脚本；Sim.new() 会创建独立的战斗实例。
const Sim = preload("res://scripts/battle_sim.gd")
const RifleVisual = preload("res://scripts/rifle_visual.gd")
var rifle_visual = RifleVisual.new()
const BattlecruiserVisual = preload("res://scripts/battlecruiser_visual.gd")
var bc_visual = BattlecruiserVisual.new()
const AI = preload("res://scripts/commander_ai.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Yamato = preload("res://scripts/skills/yamato.gd")
# 界面颜色常量。修改这里可以调整主题；不会改变兵种伤害或阵营规则。
const INK := Color("e4edf8")
const MUTED := Color("8e9fb5")
const MINT := Color("70e2b4")
const CORAL := Color("ff927f")
const PANEL := Color("101e30")
const SHIELD := Color("6fb6ff")
const FONT = preload("res://assets/NotoSansSC.ttf")
var sim = Sim.new()
var ai = AI.new()
# selected 是当前选中的兵种 ID，也可能是 erase（删除）或 move（移动）工具。
var selected := "rifle"
const UNITS_PER_PAGE := 9
var unit_page := 0
# 移动模式第一次点击的来源格；-1 表示还没选来源。
var move_source := -1
var started := false
var paused := false
var backgrounded := false
var help_open := false
var economy_open := false
var placing_tower := false
var tower_preview := Vector2.ZERO
var tower_preview_visible := false
# 累计还没有交给模拟器处理的真实时间，单位为秒。
var accumulator := 0.0
# 每次重绘重新生成的按钮点击区域。effects 保存短暂视觉特效，ttl 表示剩余显示秒数。
var buttons: Array = []
var effects: Array = []
var messages: Array = ["先选兵种，再点格子。绿色部队属于你。"]
var volume := 0.4
var speaker := AudioStreamPlayer.new()
var journal_error := false
var elapsed_ui := 0.0
# 取消已出场单位不退款，需要二次确认；确认前把目标阵容暂存在这里。pending_message 为空表示没有待确认操作。
var pending_formation: Array = []
var pending_message := ""
# 开局设置弹窗：每局开始前选择，双方使用同一份设置；字段与选项来自 rules.setup_options。
var setup_open := true
var match_settings: Dictionary = {}
# 玩家选了“自定义”的字段；自定义时显示 −/+ 步进。
var custom_fields: Dictionary = {}
# 开局弹窗的种族选择：[我方, 电脑]，可为 random；建局时把 random 换成具体种族再交给模拟器并写入战报。
var race_choices: Array = ["terran", "random"]
var race_rng := RandomNumberGenerator.new()
# races.json 的种族表（名称、主题色），只用于界面显示。
var race_info: Dictionary = Catalog.races()

## 节点进入场景后初始化：接管点击、准备音效、读取设置、建立对局、开启每帧更新。
var battle_viewport: SubViewport
var camera_zoom := 1.0
var camera_center := Vector2.ZERO
const CLOSE_ZOOM := 2.5
const MAX_ZOOM := 8.0
var battle_dragging := false
const BATTLE_RECT := Rect2(70,157,1300,352)

func _ready() -> void:
	battle_viewport=SubViewport.new()
	battle_viewport.size=Vector2i(1300,352)
	battle_viewport.disable_3d=true
	battle_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(battle_viewport)
	var renderer=BattleView.new()
	renderer.game=self
	battle_viewport.add_child(renderer)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(speaker)
	race_rng.randomize()
	_make_sound()
	_load_settings()
	_new_match()
	setup_open = true
	set_process(true)

## 用衰减正弦波生成短提示音，避免依赖外部音频文件。
## 每个采样点写成 16 位小端字节；这段不影响游戏规则，可最后再研究。
func _make_sound() -> void:
	var data := PackedByteArray()
	for i in range(3200):
		var value := int(sin(float(i) * TAU * 660.0 / 22050.0) * 9000.0 * (1.0 - float(i) / 3200.0))
		data.append(value & 255)
		data.append((value >> 8) & 255)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = data
	speaker.stream = stream

## 新建模拟器与 AI，尝试用开局资金买回上次的兵营；买不起则用默认阵容，再买不起则留空。
## 重置开始、暂停和特效状态。进入游戏后仍要点击“开始准备”才会计时。
func _new_match() -> void:
	var overrides: Dictionary = match_settings.duplicate()
	overrides["races"] = [_resolve_race(race_choices[0]), _resolve_race(race_choices[1])]
	sim = Sim.new(42, overrides)
	camera_zoom=2.0
	economy_open=false
	placing_tower=false
	tower_preview_visible=false
	camera_center=Vector2(float(sim.rules.world_width)*0.5,float(sim.rules.world_height)*0.5)
	ai = AI.new(42, sim.races[1])
	var prior: Array = Catalog.starter(sim.races[0])
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		# 每个种族单独记住兵营；旧版只有一份 formation，按当前种族校验，不合法就用默认阵容。
		var saved = config.get_value("player", "formation_" + str(sim.races[0]), config.get_value("player", "formation", prior))
		if saved is Array:
			prior = saved
	if sim.submit_formation(0, prior) != "":
		sim.submit_formation(0, Catalog.starter(sim.races[0]))
	if not sim.catalog.has(selected) or sim.kind_error(0, selected) != "":
		selected = _shop_kinds()[0]
	_ai_shop()
	started = false
	paused = false
	accumulator = 0.0
	effects.clear()
	rifle_visual.reset()
	bc_visual.reset()
	messages = ["兵营永久保留；每3秒收入，中央资源井第10波开放。"]
	pending_formation = []
	move_source = -1
	journal_error = false
	queue_redraw()

## random 在建局时随机成具体种族；结果写入战报，重放时不再随机。
func _resolve_race(choice: String) -> String:
	if Catalog.RACES.has(choice):
		return choice
	return Catalog.RACES[race_rng.randi_range(0, Catalog.RACES.size() - 1)]

func _race_name(race: String) -> String:
	return str(race_info[race].name) if race_info.has(race) else "随机"

## 从 user://settings.cfg 读取音量；user:// 是玩家数据目录，不是源码目录。
func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		volume = clampf(float(config.get_value("audio","volume",0.4)), 0.0, 1.0)
	speaker.volume_db = linear_to_db(maxf(volume, 0.001))
	match_settings = _recommended_settings()
	custom_fields.clear()
	var options: Dictionary = Catalog.rules().setup_options
	for field in options:
		var value = config.get_value("match", field, match_settings[field]) if int(config.get_value("match","economy_schema",0))==1 else match_settings[field]
		if (value is int or value is float) and value >= options[field].min and value <= options[field].max:
			match_settings[field] = int(value)
			if not options[field].choices.has(int(value)):
				custom_fields[field] = true
	race_choices = Catalog.rules().race_setup.recommended.duplicate()
	for index in range(2):
		var choice = config.get_value("match", "race_%d" % index, race_choices[index])
		if choice is String and (Catalog.RACES.has(choice) or choice == "random"):
			race_choices[index] = choice

## 每个设置字段的推荐值。
func _recommended_settings() -> Dictionary:
	var result: Dictionary = {}
	var options: Dictionary = Catalog.rules().setup_options
	for field in options:
		result[field] = int(options[field].recommended)
	return result

## 保存当前音量、开局设置和本方种族的下一波阵容；先读入旧文件，保留其他种族的兵营。失败只给提示，不影响继续战斗。
func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("audio","volume",volume)
	var formation: Array = []
	for slot in sim.formations[0]:
		formation.append({"kind":slot.kind,"cell":slot.cell})
	if config.has_section_key("player","formation"):
		config.erase_section_key("player","formation")
	config.set_value("player","formation_"+str(sim.races[0]),formation)
	config.set_value("match","economy_schema",1)
	for field in match_settings:
		config.set_value("match",field,match_settings[field])
	for index in range(2):
		config.set_value("match","race_%d" % index,race_choices[index])
	if config.save("user://settings.cfg") != OK:
		_note("设置保存失败；本局仍可继续。")

## 写出最近一局的波次记录；最终结束事件会补写结果，用于重现战斗。
func _save_journal() -> void:
	var file := FileAccess.open("user://last_match.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(sim.journal, "  "))
	elif not journal_error:
		journal_error = true
		_note("战报保存失败；本局仍可继续。")

## 接收操作系统切后台/恢复通知。恢复时清空积累时间，避免把后台时间补算进战斗。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		backgrounded = true
		if OS.is_debug_build():
			print("LIFECYCLE paused tick=",sim.tick)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		backgrounded = false
		accumulator = 0.0
		if OS.is_debug_build():
			print("LIFECYCLE resumed tick=",sim.tick)

## Godot 每个画面帧调用一次，delta 是上一帧到这一帧经过的秒数。
## 累计够 0.05 秒才推进一步战斗；特效按画面时间更新，并请求重绘。
func _process(delta: float) -> void:
	elapsed_ui += delta
	if started and not paused and not backgrounded and not help_open and not economy_open and not sim.finished:
		# 每帧最多积累 0.25 秒，防止卡顿后瞬间补算过多步。当前节拍固定 20 Hz。
		# 如果修改 rules.json 的 tick_rate，必须同步这里的 0.05 和下面插值、时间显示等计算。
		accumulator += minf(delta, 0.25)
		while accumulator >= 0.05:
			accumulator -= 0.05
			advance_tick()
	if not paused and not backgrounded and not help_open and not economy_open:
		rifle_visual.update(delta)
		bc_visual.update(delta)
	for effect in effects:
		effect.ttl -= delta
	effects = effects.filter(func(e): return e.ttl > 0)
	queue_redraw()

## 推进战斗一步并消费事件；显示攻击、更新波次战报，以及让 AI 计划下一波。
## AI 只拿到玩家刚刚出兵的公开阵容，不拿到玩家正在修改的下一波。
func advance_tick() -> void:
	var rifle_before: Dictionary = {}
	for unit in sim.units:
		if unit.kind == "rifle":
			rifle_before[unit.id] = unit.duplicate()
			rifle_before[unit.id]["body_radius"] = sim.body_radius(unit)
	# rifle_visual 会把快照里死亡的单位都当成特战队员残骸，大和舰另存一份。
	var bc_before: Dictionary = {}
	for unit in sim.units:
		if unit.kind == "battlecruiser":
			bc_before[unit.id] = unit.duplicate()
	rifle_visual.observe(sim.units)
	bc_visual.observe(sim.units)
	var tick_events: Array = sim.step()
	# 新出场单位也可接收本步动画事件，同时保留刚死亡单位的姿态供死亡动画使用。
	rifle_visual.observe(sim.units, false)
	bc_visual.observe(sim.units, false)
	for unit in sim.units:
		if unit.kind == "rifle" and not rifle_before.has(unit.id):
			rifle_before[unit.id] = unit.duplicate()
			rifle_before[unit.id]["body_radius"] = sim.body_radius(unit)
	var shop_due := false
	var journal_due := false
	for event in tick_events:
		rifle_visual.event(event, rifle_before, sim.units, sim.revealed)
		bc_visual.event(event, bc_before, sim.units, sim.revealed)
		if event.type == "attack" or event.type == "heal" or event.type == "line_attack" or event.type == "yamato" or event.type == "chain" or event.type == "mobility" or event.type == "area_impact":
			event.ttl = 0.5 if event.type == "yamato" else (0.24 if event.type == "line_attack" else 0.16)
			effects.append(event)
		elif event.type == "wave":
			_note("第 %d 波出兵 · 我方 %d / 敌方 %d" % [sim.wave,sim.last_formations[0].size(),sim.last_formations[1].size()])
			shop_due = true
			journal_due = true
			if volume > 0:
				speaker.play()
		elif event.type == "income":
			shop_due = true
		elif event.type == "center_captured":
			_note("%s占领中央资源井 · 每3秒额外+3矿" % ("我方" if event.team==0 else "敌方"))
		elif event.type == "income_tier" and sim.wave>0:
			_note("基础收入提高至 %d 矿/3秒" % int(event.amount))
		elif event.type == "base_defense_lost":
			_note("%s基地防御失效 · 无法恢复" % ("我方" if event.team == 0 else "敌方"))
		elif event.type == "structure_destroyed":
			var names := {"treasury":"宝库","gate_tower":"基地防御模块","tower":"防御塔","terran_bunker":"地堡"}
			var side: String = "我方" if event.team == 0 else "敌方"
			if event.kind == "treasury":
				_note("%s宝库被摧毁 · %s +1 灵核" % [side,"敌方" if event.team == 0 else "我方"])
			else:
				_note("%s%s被摧毁" % [side,names.get(event.kind,"建筑")])
		elif event.type == "revealed":
			_note("首次交战 · 敌方种族：%s" % _race_name(str(sim.races[1])))
		elif event.type == "tower_built" and event.team == 1:
			_note("敌方建造了防御塔")
		elif event.type == "ended":
			placing_tower=false
			tower_preview_visible=false
			journal_due = true
			speaker.play()
	if shop_due and not sim.finished:
		_ai_shop()
	if journal_due:
		_save_journal()
	rifle_visual.observe(sim.units)
	bc_visual.observe(sim.units)

## 电脑在开局、出兵和每次收入后用当前矿物增量购买；首次交战后才看到玩家刚出场的阵容，之前当作一无所知。
## 落后时先建防御塔，买不起就本轮攒矿不买兵。
func _ai_shop() -> void:
	var seen: Array = sim.visible_enemy_formation(1)
	var plan: String = ai.tower_plan(seen, sim.formations[1], int(sim.minerals[1]), int(sim.tower_builds[1]))
	if plan == "build":
		sim.build_tower(1,sim.suggested_tower_position(1))
	elif plan == "save":
		return
	# 瓦斯兵种按同一分流规则攒气，不发额外资源；补齐后恢复矿物收入。
	var needs_gas := false
	for kind in ai.pool:
		if int(sim.catalog[kind].get("gas_cost",0))<=0:continue
		var owned := false
		for entry in sim.formations[1]:
			if entry.kind==kind:owned=true;break
		if not owned:needs_gas=true;break
	var gasworks := 2 if needs_gas else 0
	if int(sim.economy.gasworks[1])!=gasworks:
		sim.economy.set_gasworks(sim,1,gasworks)
	for slot in ai.buy_list(seen, sim.formations[1], int(sim.minerals[1]),int(sim.economy.gas[1]),int(sim.economy.cores[1])):
		sim.buy(1, slot.kind, slot.cell)

## 将最新提示放在消息列表最前面，最多保留五条；界面显示最新一条。
func _note(message: String) -> void:
	messages.push_front(message)
	if messages.size() > 5:
		messages.pop_back()

## 绘制一行文字。pos 是文字基线位置，font_size 是字号，color 是颜色。
func _text(pos: Vector2, message: String, font_size: int = 20, color: Color = INK) -> void:
	draw_string(FONT, pos, message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## 绘制圆角面板；StyleBoxFlat 指定背景、边框和圆角。
func _panel(rect: Rect2, color: Color = PANEL, border: Color = Color("26384e"), radius: int = 12) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	draw_style_box(style, rect)

## 绘制按钮，同时将点击矩形和动作名加入 buttons，稍后由 _gui_input 判定点击。
func _button(rect: Rect2, label: String, action: String, active: bool = false) -> void:
	_panel(rect, Color("204b43") if active else Color("192b40"), MINT if active else Color("34465c"))
	_text(rect.position + Vector2(14, rect.size.y * 0.5 + 7), label, 19, MINT if active else INK)
	buttons.append({"rect":rect,"action":action})

## 绘制进度条/血条；ratio 是 0～1 的比例，先画底色，再画剩余部分。
func _bar(rect: Rect2, ratio: float, color: Color) -> void:
	draw_rect(rect, Color("263245"))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(ratio,0,1),rect.size.y)),color)

## 按 1440×900 的设计坐标绘制整屏，再缩放到当前窗口尺寸。
## 这一步只表现数据；不要把扣血、出兵等游戏规则写进这里。
func _draw() -> void:
	if not is_node_ready():
		return
	draw_set_transform(Vector2.ZERO,0,size / Vector2(1440,900))
	buttons.clear()
	draw_rect(Rect2(0,0,1440,900),Color("091321"))
	_text(Vector2(32,43),"FIGHT / PARTY",30,MINT)
	_text(Vector2(33,70),"公平配兵 · 自动推进",16,MUTED)
	var limit: int = int(sim.rules.wave_limit)
	if sim.wave < limit:
		_text(Vector2(400,37),"下一波  %d / %d" % [sim.wave+1,limit],18,MUTED)
		var countdown: int = int(ceil(float(sim.ticks_to_next_wave()) / float(sim.rules.tick_rate)))
		_text(Vector2(400,74),"%02d 秒" % countdown,30,INK)
	else:
		_text(Vector2(400,37),"已出满 %d 波" % limit,18,MUTED)
		_text(Vector2(400,74),"最终决战",30,CORAL)
	var income: Dictionary = sim.economy.rates(0,sim.wave)
	_text(Vector2(577,37),"矿物 +%d/3秒" % int(income.minerals),16,MUTED)
	_text(Vector2(577,74),str(int(sim.minerals[0])),28,MINT)
	_text(Vector2(745,37),"瓦斯 +%d/3秒" % int(income.gas),16,MUTED)
	_text(Vector2(745,74),str(int(sim.economy.gas[0])),26,SHIELD)
	_text(Vector2(895,37),"灵核",16,MUTED)
	_text(Vector2(895,74),str(int(sim.economy.cores[0])),26,Color("ffcd70"))
	_button(Rect2(1000,24,120,48),"音量 %d" % int(volume*100),"volume")
	_button(Rect2(1132,24,120,48),"玩法说明","help")
	_button(Rect2(1264,24,144,48),"开始准备" if not started else ("继续战斗" if paused else "暂停战斗"),"start",true)
	_draw_battle()
	_draw_editor()
	_text(Vector2(34,882),"v%s  /  战局 %02d:%02d  /  无击杀收入" % [str(sim.rules.version),sim.tick/int(sim.rules.tick_rate)/60,sim.tick/int(sim.rules.tick_rate)%60],16,MUTED)
	_text(Vector2(1000,882),"%d FPS   ·   %d 个战场单位" % [Engine.get_frames_per_second(),sim.units.size()],16,MUTED)
	if not started and not placing_tower:
		_panel(Rect2(440,263,560,130), Color("102d32"), MINT)
		_text(Vector2(475,308),"先布阵，再让军队替你战斗。",28,MINT)
		_text(Vector2(475,346),"点击右上角「开始准备」，%d 秒后双方同时出兵。" % int(sim.rules.first_wave_seconds),18)
		_text(Vector2(475,373),"买下的单位每波都会出场；不能直接指挥场上单位。",18,MUTED)
	if paused and not sim.finished and not placing_tower:
		_panel(Rect2(525,284,390,90))
		_text(Vector2(580,338),"已暂停 · 阵容仍可调整",25,MINT)
	if sim.finished:
		_draw_result()
	if pending_message != "":
		_draw_confirm()
	if setup_open:
		_draw_setup()
	if help_open:
		_draw_help()
	if economy_open:
		_draw_economy()

## 把逻辑战场坐标（rules.world_width × world_height）转换成 1300×352 的屏幕战场区域坐标。
## 未来改 3D 时，这种位置映射应交给独立的 3D 战场表现层。
func _camera_rect() -> Rect2:
	var width: float = maxf(float(sim.rules.world_width),float(sim.rules.world_height)*BATTLE_RECT.size.x/BATTLE_RECT.size.y)/camera_zoom
	var span := Vector2(width,width*BATTLE_RECT.size.y/BATTLE_RECT.size.x)
	var center := camera_center
	for axis in range(2):
		var extent: float = float(sim.rules.world_width) if axis==0 else float(sim.rules.world_height)
		center[axis]=extent*0.5 if span[axis]>=extent else clampf(center[axis],span[axis]*0.5,extent-span[axis]*0.5)
	return Rect2(center-span*.5,span)

func _world(pos: Vector2) -> Vector2:
	var view := _camera_rect()
	return BATTLE_RECT.position+(pos-view.position)*BATTLE_RECT.size/view.size

func _draw_battle() -> void:
	_panel(Rect2(32,98,1376,458),Color("0d1c2b"))
	for team in range(2):
		var color: Color = MINT if team==0 else CORAL
		var x: float = 56 if team==0 else 1000
		_text(Vector2(x,130),"我方基地" if team==0 else "敌方基地",18,color)
		var capacity: float = sim.base_max_hp(team)
		_bar(Rect2(x+104,116,230,10),float(sim.bases[team])/capacity,color)
		if sim.base_has_defense(team):
			var extra_width: float = 230.0*sim.base_extra_hp(team)/capacity
			draw_rect(Rect2(x+104+230.0*float(sim.rules.base_hp)/capacity,116,extra_width,10),Color("ffcd70"))
		_text(Vector2(x+344,130),str(int(sim.bases[team])),16,color)
	if battle_viewport!=null:
		draw_texture_rect(battle_viewport.get_texture(),BATTLE_RECT,false)
	if placing_tower:
		draw_rect(Rect2(BATTLE_RECT.position,Vector2(BATTLE_RECT.size.x,38)),Color(0.03,0.09,0.12,0.92))
		_text(BATTLE_RECT.position+Vector2(12,26),"选择己方半场落点建塔 · 绿色可建，红色不可建 · 右键 / Esc取消",17,MINT)
		_button(Rect2(BATTLE_RECT.end.x-130,BATTLE_RECT.position.y+3,120,32),"取消选址","cancel_tower")
	_text(Vector2(56,539),"%s × %s 格 · 拖动战场平移 · 滚轮缩放" % [sim.rules.world_width,sim.rules.world_height],15,MUTED)
	_button(Rect2(590,517,70,30),"全图","camera_all")
	_button(Rect2(668,517,70,30),"近景","camera_close")
	_button(Rect2(746,517,70,30),"己方","camera_home")
	_button(Rect2(824,517,70,30),"中线","camera_middle")
	_button(Rect2(902,517,70,30),"敌方","camera_enemy")
	_button(Rect2(982,517,40,30),"−","camera_out")
	_button(Rect2(1030,517,40,30),"+","camera_in")
	_text(Vector2(1085,539),"缩放 %.1f 倍" % camera_zoom,15,MUTED)

## 对方种族尚未公开时，界面不能画出对方的兵种外形。
func _hidden_team(team: int) -> bool:
	return team != 0 and not sim.revealed

func _race_color(race: String) -> Color:
	return Color(str(race_info[race].color)) if race_info.has(race) else MUTED

## 结构体：淡色射程圈（按战场缩放）、按种族区分的外形（数值相同）、阵营圈与较宽血条。
func _draw_structure_shape(p: Vector2, kind: String, race: String, radius: float) -> void:
	UnitArt.structure(self,p,kind,race,radius,_race_color(race))

func _draw_unit(p: Vector2, kind: String, color: Color, radius: float) -> void:
	if kind == "rifle":
		rifle_visual.draw_frame(self,p,"idle",0,rifle_visual.clock,radius*6.0)
		return
	if kind == "battlecruiser":
		# 卡片/格子图标用精灵 idle 首帧；舰长约 2 倍 radius。
		bc_visual.draw_frame(self,p,"idle",false,0.0,radius*0.65,Color(1,1,1,color.a))
		return
	UnitArt.draw(self,p,kind,color,radius,str(sim.catalog[kind].get("symbol","?")))

func _draw_editor() -> void:
	var columns: int = int(sim.rules.columns)
	var rows: int = int(sim.rules.rows)
	_panel(Rect2(32,573,700,287))
	_text(Vector2(52,604),"兵营布阵",23)
	_text(Vector2(178,602),"金框：本轮新买，取消全额退回",15,Color("e6c28e"))
	_text(Vector2(590,602),"后排  →  前线",18,MINT)
	# 把兵营转为“格子编号 → 兵营格”的字典，方便逐格绘制。
	var occupied := {}
	for slot in sim.formations[0]:
		occupied[int(slot.cell)] = slot
	# 网格区域固定 646×189，按列数与行数等分；金色边框表示本轮新买、取消可全额退回。
	var pitch := Vector2(646.0 / columns, 189.0 / rows)
	for cell in range(columns * rows):
		var rect := Rect2(Vector2(52,616) + Vector2(cell % columns, cell / columns) * pitch, pitch - Vector2(3,3))
		var border: Color = Color("30475a")
		if cell == move_source:
			border = MINT
		elif occupied.has(cell) and not bool(occupied[cell].deployed):
			border = Color("e6c28e")
		_panel(rect,Color("1c3445") if occupied.has(cell) else Color("102335"),border,4)
		if occupied.has(cell):
			_draw_unit(rect.get_center(),occupied[cell].kind,Color(sim.catalog[occupied[cell].kind].color),minf(rect.size.y*0.4,11))
		buttons.append({"rect":rect,"action":"cell:%d" % cell})
	_button(Rect2(52,816,110,32),"移除单位","erase",selected=="erase")
	_button(Rect2(174,816,110,32),"移动位置","move",selected=="move")
	_button(Rect2(296,816,122,32),"清空兵营","clear")
	var tower_cost: int = int(sim.catalog[sim.tower_kind(0)].cost)
	if int(sim.tower_builds[0]) >= int(sim.rules.tower_max_builds):
		_panel(Rect2(440,816,180,32),Color("142233"),Color("2b3b50"))
		_text(Vector2(454,839),"防御塔已建造",17,MUTED)
	else:
		_button(Rect2(440,816,180,32),"取消选址" if placing_tower else "建造防御塔 %d" % tower_cost,"build_tower",placing_tower or int(sim.minerals[0]) >= tower_cost)
	_button(Rect2(632,816,80,32),"经济","economy")
	_panel(Rect2(746,573,452,287))
	_text(Vector2(764,604),"选择兵种",23)
	var kinds: Array = _shop_kinds()
	var page_count := ceili(float(kinds.size()) / UNITS_PER_PAGE)
	if page_count > 1:
		_button(Rect2(860,579,30,32),"<","units_prev")
		_text(Vector2(894,602),"%d/%d" % [unit_page+1,page_count],15,MUTED)
		_button(Rect2(927,579,30,32),">","units_next")
	var cost: int = sim.formation_cost(sim.formations[0])
	_text(Vector2(968,603),"兵营 %d · 可用 %d" % [cost,int(sim.minerals[0])],17,MINT)
	var i := 0
	for kind in kinds.slice(unit_page*UNITS_PER_PAGE,(unit_page+1)*UNITS_PER_PAGE):
		var stats: Dictionary = sim.catalog[kind]
		var rect := Rect2(762+(i%3)*146,616+(i/3)*55,140,50)
		if not Catalog.is_ready(stats):
			_panel(rect,Color("111c2a"),Color("243344"))
			_draw_unit(rect.position+Vector2(20,20),kind,Color(Color(stats.color),0.35),9)
			_text(rect.position+Vector2(37,25),stats.name,17 if stats.name.length() <= 4 else 13,MUTED)
			_text(rect.position+Vector2(10,44),"尚未实装",12,Color("5d6e82"))
			i += 1
			continue
		_panel(rect,Color("233e41") if selected==kind else Color("17293c"),MINT if selected==kind else Color("304358"))
		_draw_unit(rect.position+Vector2(20,20),kind,Color(stats.color),9)
		_text(rect.position+Vector2(37,25),stats.name,19 if stats.name.length() <= 3 else (15 if stats.name.length() == 4 else 12))
		_text(rect.position+Vector2(102,24),str(int(stats.cost)),16,MINT)
		_text(rect.position+Vector2(10,44),"%d/组 · %s" % [int(stats.get("spawn_count",1)),("另需%d瓦斯" % int(stats.get("gas_cost",0))) if int(stats.get("gas_cost",0))>0 else str(stats.role)],11,MUTED)
		buttons.append({"rect":rect,"action":"select:"+kind})
		i += 1
	if sim.catalog.has(selected):
		var summary: String = UnitSummary.text(sim.catalog[selected])
		var font_size := 14
		while font_size>11 and FONT.get_multiline_string_size(summary,HORIZONTAL_ALIGNMENT_LEFT,416,font_size).y>68:
			font_size-=1
		draw_multiline_string(FONT,Vector2(764,786+FONT.get_ascent(font_size)),summary,HORIZONTAL_ALIGNMENT_LEFT,416,font_size,4,MUTED)
	else:
		_text(Vector2(764,806),"点击要取消的单位；已出场过的不退款" if selected=="erase" else "先点单位，再点目标格；占用格会交换，免费。",17,MINT)
	_panel(Rect2(1212,573,196,287))
	_text(Vector2(1226,604),"敌情 / 上一波",20,CORAL)
	var counts: Dictionary = {}
	for slot in sim.visible_enemy_formation(0):
		counts[slot.kind] = int(counts.get(slot.kind,0))+int(sim.catalog[slot.kind].get("spawn_count",1))
	if not sim.revealed:
		_text(Vector2(1226,636),"尚未交战",16,MUTED)
		_text(Vector2(1226,658),"种族与阵容未知",14,MUTED)
	else:
		_text(Vector2(1226,632),"敌方种族：%s" % _race_name(str(sim.races[1])),15,_race_color(str(sim.races[1])))
		if counts.is_empty():
			_text(Vector2(1226,654),"上一波没有兵",14,MUTED)
		var n := 0
		for kind in counts:
			var label: String = "%s×%d" % [sim.catalog[kind].name,counts[kind]]
			_text(Vector2(1226+(n%2)*92,652+(n/2)*17),label,14 if label.length() <= 6 else 11)
			n+=1
	_text(Vector2(1226,742),"下一波敌方配置保密",14,MUTED)
	_text(Vector2(1226,770),"击破 %d / 损失 %d" % [sim.kills[0],sim.kills[1]],16,MINT)
	_text(Vector2(1226,798),"最新战报",14,MUTED)
	var message: String = messages[0]
	_text(Vector2(1226,822),message.left(12),14,Color("e6c28e"))
	if message.length()>12:
		_text(Vector2(1226,842),message.substr(12,12),14,Color("e6c28e"))

## 本方种族的兵种卡片（含未实装的预留兵种，显示为灰色、不可选），顺序与 units.json 一致。
func _shop_kinds() -> Array:
	return Catalog.race_units(sim.catalog, str(sim.races[0]), true)

## 经济面板暂停计时，所有资源修改仍经过模拟器并写入战报动作。
func _draw_economy() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(0,0,0,0.82))
	_panel(Rect2(280,150,880,600),PANEL,MINT)
	buttons.clear()
	_text(Vector2(320,205),"经济与中央资源井",30,MINT)
	var income: Dictionary = sim.economy.rates(0,sim.wave)
	var owner: int = sim.economy.center_owner
	var center_status: String = "第10波开放" if not sim.economy.center_active(sim.wave) else ("无人占领" if owner<0 else ("我方控制" if owner==0 else "敌方控制"))
	var lines := [
		"当前收入：%d 矿 / %d 瓦斯，每3秒结算" % [int(income.minerals),int(income.gas)],
		"基础收入：30 → 第11波60 → 第41波120；第64波停止收入。",
		"气厂免费，每座将基础收入的10%等额转为瓦斯；拆除后恢复矿物收入。",
		"气厂上限初始3座，第32波扩至6座；分流只影响基础收入。",
		"中央井：%s；2.5格内可占领，控制方每3秒额外+3矿。" % center_status,
		"无人靠近时保留归属；摧毁敌方宝库获得1灵核，击杀单位不加钱。",
		"瓦斯可购买需气兵种，也可按1:1换矿；灵核独立记录。"]
	for i in range(lines.size()):
		_text(Vector2(320,250+i*40),lines[i],18,INK)
	_text(Vector2(320,565),"气厂 %d / %d" % [int(sim.economy.gasworks[0]),sim.economy.gasworks_limit(sim.wave)],24,MINT)
	_button(Rect2(530,530,110,48),"拆除一座","gas_remove")
	_button(Rect2(655,530,110,48),"建造一座","gas_add",true)
	_button(Rect2(800,530,300,48),"兑换全部瓦斯 %d" % int(sim.economy.gas[0]),"exchange_gas")
	_text(Vector2(320,620),"矿物 %d   瓦斯 %d   灵核 %d" % [int(sim.minerals[0]),int(sim.economy.gas[0]),int(sim.economy.cores[0])],24)
	_text(Vector2(320,660),messages[0].left(42),17,MUTED)
	_button(Rect2(320,685,180,44),"返回战场","economy",true)

## 绘制说明弹层，并清空底层点击区域，防止误操作兵营。
func _draw_help() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(0,0,0,0.8))
	_panel(Rect2(290,130,860,640))
	buttons.clear()
	_text(Vector2(335,188),"指挥官手册",32,MINT)
	var lines := ["1. 选兵种，再点下方空格购买。右侧是前排，左侧是后排。",
		"2. 买下的单位永久留在兵营，每 %d 秒全部出场一次。" % int(sim.rules.wave_seconds),
		"3. 开局 %d 矿；每3秒获得30/60/120矿，第11/41波提升。" % int(sim.rules.start_minerals),
		"4. 本轮新买、未出场的单位取消可全额退回；出场过的取消不退款。",
		"5. 部队一直战斗到阵亡；移动兵营里的单位免费。",
		"6. 观察敌方上一波，选择克制组合。AI 不偷看你的新阵容。",
		"   宝库被摧毁奖励对方1灵核；中央井第10波开放，控制方每3秒+3矿。",
		"   花 %d 矿点选己方半场建塔；不能重叠建筑，被摧毁不能重建。" % int(sim.catalog[sim.tower_kind(0)].cost),
		"7. 摧毁基地获胜；第 %d 波后先没有可攻击部队的一方失败。" % int(sim.rules.wave_limit),
		"8. 空格键暂停，Esc 打开说明；手机切后台会自动暂停。",
		"   双方种族在开局选择、整局固定；首次交战后才看到敌方种族与阵容。",
		"提示：点击兵营下方「经济」管理气厂分流与瓦斯兑换。"]
	for i in range(lines.size()):
		_text(Vector2(335,236+i*35),lines[i],20,INK if i<lines.size()-1 else MINT)
	_button(Rect2(335,675,170,52),"明白了，返回","help",true)
	_text(Vector2(540,708),"查看手册时，对局计时暂停。",18,MUTED)

## 根据 sim.winner 显示结算结果及重开按钮；不在界面里重新决定胜负。
func _draw_result() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(0,0,0,0.75))
	_panel(Rect2(420,210,600,440))
	buttons.clear()
	_text(Vector2(465,275),"战线突破 · 胜利" if sim.winner==0 else ("基地失守 · 失败" if sim.winner==1 else "势均力敌 · 平局"),34,MINT if sim.winner!=1 else CORAL)
	_text(Vector2(465,330),"完成 %d 波出兵   ·   战斗 %d 秒" % [sim.wave,sim.tick/int(sim.rules.tick_rate)],22)
	_text(Vector2(465,380),"基地剩余    我方 %d  /  敌方 %d" % [sim.bases[0],sim.bases[1]],22)
	_text(Vector2(465,425),"击破 %d    损失 %d" % [sim.kills[0],sim.kills[1]],22)
	_text(Vector2(465,472),"战报保存失败，请检查磁盘空间。" if journal_error else "战报已保存，可用于复现配兵与战斗过程。",18,MUTED)
	_button(Rect2(465,535,210,60),"调整阵容，再来一局","restart",true)
	_button(Rect2(700,535,210,60),"查看玩法说明","help")

## 开局设置弹层：先选双方种族（可随机，允许同族），再选数值字段。
## 每个数值字段三个预设（★ 推荐）加自定义；自定义用 −/+ 按 step 调整。
func _draw_setup() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(0,0,0,0.82))
	_panel(Rect2(290,40,860,770),PANEL,MINT)
	buttons.clear()
	_text(Vector2(335,96),"开局设置",32,MINT)
	_text(Vector2(500,94),"种族整局固定，首次交战后公开  ·  ★ 为推荐",18,MUTED)
	var race_setup: Dictionary = sim.rules.race_setup
	var row := 0
	for index in range(2):
		var y: float = 112 + row * 106
		_text(Vector2(335,y+30),str(race_setup.labels[index]),22)
		var column := 0
		for choice in Catalog.RACES + ["random"]:
			var label: String = _race_name(choice)
			if choice == str(race_setup.recommended[index]):
				label += " ★"
			_button(Rect2(335+column*158,y+44,146,50),label,"setup_race:%d:%s" % [index,choice],race_choices[index] == choice)
			column += 1
		row += 1
	var options: Dictionary = sim.rules.setup_options
	for field in options:
		var option: Dictionary = options[field]
		var y: float = 112 + row * 106
		var value: int = int(match_settings[field])
		var custom: bool = custom_fields.has(field)
		_text(Vector2(335,y+30),str(option.label),22)
		var column := 0
		for choice in option.choices:
			var label: String = "%d %s" % [int(choice), option.unit]
			if int(choice) == int(option.recommended):
				label += " ★"
			_button(Rect2(335+column*158,y+44,146,50),label,"setup_pick:%s:%d" % [field,int(choice)],not custom and value == int(choice))
			column += 1
		_button(Rect2(335+column*158,y+44,146,50),"自定义","setup_custom:"+field,custom)
		if custom:
			_button(Rect2(985,y+44,48,50),"−","setup_step:%s:-1" % field)
			_text(Vector2(1040,y+78),"%d" % value,22,MINT)
			_button(Rect2(1090,y+44,48,50),"+","setup_step:%s:1" % field)
		row += 1
	var minutes: float = (float(sim.rules.first_wave_seconds)+(float(sim.rules.wave_limit)-1.0)*float(match_settings.wave_seconds)) / 60.0
	_text(Vector2(335,700),"共 %d 波，出满约 %d 分钟；之后先没有可攻击部队的一方失败。" % [int(sim.rules.wave_limit),int(round(minutes))],17,MUTED)
	_button(Rect2(335,728,180,56),"恢复推荐","setup_reset")
	_button(Rect2(880,728,224,56),"确认，开始布阵","setup_confirm",true)

## 处理开局设置弹层的按钮；确认后按新设置重建对局。
func _handle_setup(action: String) -> void:
	var options: Dictionary = sim.rules.setup_options
	var parts: PackedStringArray = action.split(":")
	if parts[0] == "setup_reset":
		match_settings = _recommended_settings()
		custom_fields.clear()
		race_choices = sim.rules.race_setup.recommended.duplicate()
	elif parts[0] == "setup_race" and parts.size() == 3:
		if int(parts[1]) in [0, 1] and (Catalog.RACES.has(parts[2]) or parts[2] == "random"):
			race_choices[int(parts[1])] = parts[2]
	elif parts[0] == "setup_confirm":
		_new_match()
		setup_open = false
		_save_settings()
	elif parts.size() >= 2 and options.has(parts[1]):
		var field: String = parts[1]
		var option: Dictionary = options[field]
		if parts[0] == "setup_pick" and parts.size() == 3:
			match_settings[field] = int(parts[2])
			custom_fields.erase(field)
		elif parts[0] == "setup_custom":
			custom_fields[field] = true
		elif parts[0] == "setup_step" and parts.size() == 3:
			custom_fields[field] = true
			match_settings[field] = clampi(int(match_settings[field]) + int(parts[2]) * int(option.step), int(option.min), int(option.max))

## 取消已出场单位的二次确认弹层；清空底层点击区域，只保留确认与取消。
func _draw_confirm() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(0,0,0,0.7))
	_panel(Rect2(420,300,600,220),PANEL,CORAL)
	buttons.clear()
	_text(Vector2(460,360),pending_message,22,INK)
	_text(Vector2(460,398),"该单位从下一波起不再出场；战场上已有的不受影响。",17,MUTED)
	_button(Rect2(460,430,200,56),"确定取消","confirm_yes",true)
	_button(Rect2(690,430,200,56),"保留单位","confirm_no")

## 处理左键/模拟鼠标的触摸点击：先还原设计坐标，再寻找命中的按钮矩形。
func _battle_point(design_position: Vector2) -> Vector2:
	var view := _camera_rect()
	return view.position+(design_position-BATTLE_RECT.position)*view.size/BATTLE_RECT.size

func _cancel_tower_placement() -> void:
	placing_tower=false
	tower_preview_visible=false
	battle_dragging=false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var p: Vector2 = event.position*Vector2(1440,900)/size
		if event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
			battle_dragging=false
		if event.pressed:
			if placing_tower and event.button_index==MOUSE_BUTTON_RIGHT:
				_cancel_tower_placement()
				queue_redraw()
				accept_event()
				return
			# 只有左键/触摸会触发按钮，滚轮仍能在选址时缩放。
			if event.button_index==MOUSE_BUTTON_LEFT:
				for button in buttons:
					if button.rect.has_point(p):
						handle_action(button.action)
						accept_event()
						return
			if BATTLE_RECT.has_point(p) and not setup_open and not help_open and not economy_open and pending_message=="":
				if placing_tower and event.button_index==MOUSE_BUTTON_LEFT and p.y<BATTLE_RECT.position.y+38:
					accept_event()
					return
				if event.button_index==MOUSE_BUTTON_WHEEL_UP:camera_zoom=clampf(camera_zoom*1.25,1,MAX_ZOOM)
				elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:camera_zoom=clampf(camera_zoom/1.25,1,MAX_ZOOM)
				elif event.button_index==MOUSE_BUTTON_LEFT:
					if placing_tower:
						tower_preview=_battle_point(p)
						tower_preview_visible=true
						var error: String = sim.build_tower(0,tower_preview)
						if error.is_empty():
							_cancel_tower_placement()
							_note("防御塔已建成，一局只能建造一座。")
							_save_journal()
						else:_note(error)
					else:battle_dragging=true
				queue_redraw()
				accept_event()
	elif event is InputEventMouseMotion and not setup_open and not help_open and not economy_open and pending_message=="":
		var p: Vector2 = event.position*Vector2(1440,900)/size
		if placing_tower:
			tower_preview_visible=BATTLE_RECT.has_point(p)
			if tower_preview_visible:tower_preview=_battle_point(p)
			queue_redraw()
		elif battle_dragging:
			var motion: Vector2 = event.relative*Vector2(1440,900)/size
			camera_center=_camera_rect().get_center()-motion*_camera_rect().size/BATTLE_RECT.size
			queue_redraw()
			accept_event()

## 处理快捷键：空格开始/暂停，Esc 打开或关闭说明；忽略长按产生的重复事件。
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE and not help_open and not economy_open and not setup_open and not sim.finished:
			handle_action("start")
		elif event.keycode == KEY_ESCAPE:
			handle_action("cancel_tower" if placing_tower else ("economy" if economy_open else "help"))

## 把动作字符串分发到具体操作；例如 select:rifle 选择特战队员，cell:5 编辑第 5 格。
## 绘制按钮和处理操作通过动作名连接，添加按钮时要在这里增加对应逻辑。
func handle_action(action: String) -> void:
	if action=="cancel_tower":
		_cancel_tower_placement()
		queue_redraw()
		return
	if action in ["help","economy","clear","erase","move"] or action.begins_with("select:") or action.begins_with("cell:"):
		_cancel_tower_placement()
	if setup_open:
		if action.begins_with("setup"):
			_handle_setup(action)
		queue_redraw()
		return
	if action == "economy":
		economy_open = not economy_open
		queue_redraw()
		return
	if economy_open:
		var error := ""
		if action=="gas_add" or action=="gas_remove":
			error=sim.apply_action({"type":"gasworks","team":0,"count":int(sim.economy.gasworks[0])+(1 if action=="gas_add" else -1)})
		elif action=="exchange_gas":
			error=sim.apply_action({"type":"exchange_gas","team":0})
		if not error.is_empty(): _note(error)
		_save_journal()
		queue_redraw()
		return
	if action.begins_with("camera_"):
		if action=="camera_all":
			camera_zoom=1.0
			camera_center=Vector2(float(sim.rules.world_width)*.5,float(sim.rules.world_height)*.5)
		elif action=="camera_close":camera_zoom=CLOSE_ZOOM
		elif action=="camera_in":camera_zoom=clampf(camera_zoom*1.5,1,MAX_ZOOM)
		elif action=="camera_out":camera_zoom=clampf(camera_zoom/1.5,1,MAX_ZOOM)
		elif action=="camera_home":
			camera_center=sim.layout_pos(0,"spawn")
			camera_zoom=CLOSE_ZOOM
		elif action=="camera_enemy":
			camera_center=sim.layout_pos(1,"spawn")
			camera_zoom=CLOSE_ZOOM
		elif action=="camera_middle":camera_center=Vector2(float(sim.rules.world_width)*.5,float(sim.rules.world_height)*.5)
	elif action == "help":
		help_open = not help_open
	elif action == "volume":
		volume = 0.0 if volume >= 0.99 else minf(1.0, volume + 0.2)
		speaker.volume_db = linear_to_db(maxf(volume,0.001))
		_save_settings()
	elif action == "start":
		if not started:
			started=true
		else:
			paused=not paused
	elif action == "restart":
		_new_match()
		setup_open = true
	elif action == "confirm_yes" or action == "confirm_no":
		var formation: Array = pending_formation
		pending_formation = []
		pending_message = ""
		if action == "confirm_yes":
			_commit(formation, true)
	elif not sim.finished:
		if action == "units_prev" or action == "units_next":
			var page_count := ceili(float(_shop_kinds().size()) / UNITS_PER_PAGE)
			unit_page = posmod(unit_page + (1 if action == "units_next" else -1),page_count)
		elif action.begins_with("select:"):
			selected = action.get_slice(":",1)
			var index: int = _shop_kinds().find(selected)
			if index >= 0:
				unit_page = index / UNITS_PER_PAGE
			move_source = -1
		elif action == "erase" or action == "move":
			selected=action
			move_source=-1
		elif action == "clear":
			_commit([])
		elif action == "build_tower":
			if placing_tower:_cancel_tower_placement()
			else:
				var error: String = sim.tower_error(0)
				if not error.is_empty():_note(error)
				else:
					placing_tower=true
					battle_dragging=false
					tower_preview_visible=false
					_note("请在己方半场选择防御塔落点；可以取消重新选。")
		elif action.begins_with("cell:"):
			_edit_cell(int(action.get_slice(":",1)))
	queue_redraw()

## 将编辑后的阵容送入统一校验入口。合法才保存，不合法则保留旧阵容并提示。
## 会丢弃已出场过的单位时（不退款），先弹出确认，confirmed 为 true 才真正执行。
func _commit(formation: Array, confirmed: bool = false) -> void:
	var wanted: Dictionary = {}
	for slot in formation:
		wanted[int(slot.cell)] = slot.kind
	var lost: Array = []
	for slot in sim.formations[0]:
		if bool(slot.deployed) and wanted.get(int(slot.cell), "") != slot.kind:
			lost.append(sim.catalog[slot.kind].name)
	if not lost.is_empty() and not confirmed:
		pending_formation = formation
		pending_message = "取消 %d 个已出场的单位不退款，确定吗？" % lost.size() if lost.size() > 1 else "取消已出场的%s不退款，确定吗？" % lost[0]
		return
	var error: String = sim.submit_formation(0, formation)
	if error != "":
		_note(error)
	else:
		_save_settings()

## 在阵容副本上执行放置、替换、删除或移动，再提交校验。
## 移动分两次点击：第一次记住来源格，第二次移到空格或与已有单位交换。
func _edit_cell(cell: int) -> void:
	# 先改副本；若最后超预算被拒绝，原阵容仍然保持完整。
	var formation: Array = sim.formations[0].duplicate(true)
	var index := -1
	for i in range(formation.size()):
		if int(formation[i].cell) == cell:
			index=i
	if selected=="move":
		if move_source<0:
			if index>=0:
				move_source=cell
		else:
			var error: String = sim.move(0, move_source, cell)
			move_source=-1
			if error != "":
				_note(error)
			else:
				_save_settings()
		return
	if index>=0:
		formation.remove_at(index)
	if selected!="erase":
		formation.append({"kind":selected,"cell":cell})
	_commit(formation)
