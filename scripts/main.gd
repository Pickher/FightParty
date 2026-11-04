# 中文导读：游戏入口，负责界面、输入、本地对局调度和存档。战斗规则在 battle_sim.gd。
# Control 是 2D 界面节点。_ready / _process / _draw 等以下划线开头的回调由 Godot 自动调用。
# 初学时先找到 handle_action（按钮做什么）和 _draw_editor（配兵界面长什么样）。
# 当前 UI 是代码直接绘制的，编辑器里不会出现每张卡片的独立 Button 节点。
# 将来升级 3D 时可替换战场表现，继续使用 sim 计算出的状态和事件。
extends Control
# preload 在脚本加载时引入其他脚本；Sim.new() 会创建独立的战斗实例。
const Sim = preload("res://scripts/battle_sim.gd")
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
func _ready() -> void:
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
	messages = ["兵营永久保留，每波全部出场；每轮收入 +%d。" % int(sim.rules.wave_income)]
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
		var value = config.get_value("match", field, match_settings[field])
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
	if started and not paused and not backgrounded and not help_open and not sim.finished:
		# 每帧最多积累 0.25 秒，防止卡顿后瞬间补算过多步。当前节拍固定 20 Hz。
		# 如果修改 rules.json 的 tick_rate，必须同步这里的 0.05 和下面插值、时间显示等计算。
		accumulator += minf(delta, 0.25)
		while accumulator >= 0.05:
			accumulator -= 0.05
			advance_tick()
	for effect in effects:
		effect.ttl -= delta
	effects = effects.filter(func(e): return e.ttl > 0)
	queue_redraw()

## 推进战斗一步并消费事件；显示攻击、更新波次战报，以及让 AI 计划下一波。
## AI 只拿到玩家刚刚出兵的公开阵容，不拿到玩家正在修改的下一波。
func advance_tick() -> void:
	for event in sim.step():
		if event.type == "attack" or event.type == "heal" or event.type == "line_attack" or event.type == "yamato":
			event.ttl = 0.5 if event.type == "yamato" else (0.24 if event.type == "line_attack" else 0.16)
			effects.append(event)
		elif event.type == "wave":
			_note("第 %d 波出兵 · 我方 %d / 敌方 %d" % [sim.wave,sim.last_formations[0].size(),sim.last_formations[1].size()])
			_ai_shop()
			_save_journal()
			if volume > 0:
				speaker.play()
		elif event.type == "structure_destroyed":
			var names := {"treasury":"宝库","gate_tower":"门口防御塔","tower":"防御塔"}
			var side: String = "我方" if event.team == 0 else "敌方"
			if event.kind == "treasury":
				_note("%s宝库被摧毁 · %s +%d 矿" % [side,"敌方" if event.team == 0 else "我方",int(sim.rules.treasury_reward)])
			elif event.kind == "gate_tower":
				_note("%s门口防御塔失守 · 基地已无防御" % side)
			else:
				_note("%s%s被摧毁" % [side,names[event.kind]])
		elif event.type == "revealed":
			_note("首次交战 · 敌方种族：%s" % _race_name(str(sim.races[1])))
		elif event.type == "tower_built" and event.team == 1:
			_note("敌方建造了防御塔")
		elif event.type == "ended":
			_save_journal()
			speaker.play()

## 电脑在开局和每次出兵后用当前矿物增量购买；首次交战后才看到玩家刚出场的阵容，之前当作一无所知。
## 落后时先建防御塔，买不起就本轮攒矿不买兵。
func _ai_shop() -> void:
	var seen: Array = sim.visible_enemy_formation(1)
	var plan: String = ai.tower_plan(seen, sim.formations[1], int(sim.minerals[1]), int(sim.tower_builds[1]))
	if plan == "build":
		sim.build_tower(1)
	elif plan == "save":
		return
	for slot in ai.buy_list(seen, sim.formations[1], int(sim.minerals[1])):
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
		var countdown: int = int(ceil(float(sim.wave_ticks() - sim.tick % sim.wave_ticks()) / float(sim.rules.tick_rate)))
		_text(Vector2(400,74),"%02d 秒" % countdown,30,INK)
	else:
		_text(Vector2(400,37),"已出满 %d 波" % limit,18,MUTED)
		_text(Vector2(400,74),"最终决战",30,CORAL)
	_text(Vector2(577,37),"矿物 · 每轮 +%d" % int(sim.rules.wave_income),18,MUTED)
	_text(Vector2(577,74),str(int(sim.minerals[0])),30,MINT)
	_text(Vector2(800,37),"战局时间",18,MUTED)
	var seconds: int = sim.tick / int(sim.rules.tick_rate)
	_text(Vector2(800,74),"%02d:%02d" % [seconds/60,seconds%60],24)
	_button(Rect2(1000,24,120,48),"音量 %d" % int(volume*100),"volume")
	_button(Rect2(1132,24,120,48),"玩法说明","help")
	_button(Rect2(1264,24,144,48),"开始准备" if not started else ("继续战斗" if paused else "暂停战斗"),"start",true)
	_draw_battle()
	_draw_editor()
	_text(Vector2(34,882),"离线原型 v0.3.2  /  兵营永久保留  /  无击杀收入",16,MUTED)
	_text(Vector2(1000,882),"%d FPS   ·   %d 个战场单位" % [Engine.get_frames_per_second(),sim.units.size()],16,MUTED)
	if not started:
		_panel(Rect2(440,263,560,130), Color("102d32"), MINT)
		_text(Vector2(475,308),"先布阵，再让军队替你战斗。",28,MINT)
		_text(Vector2(475,346),"点击右上角「开始准备」，%d 秒后双方同时出兵。" % int(sim.rules.wave_seconds),18)
		_text(Vector2(475,373),"买下的单位每波都会出场；不能直接指挥场上单位。",18,MUTED)
	if paused and not sim.finished:
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

## 把逻辑战场坐标（rules.world_width × world_height）转换成 1300×352 的屏幕战场区域坐标。
## 未来改 3D 时，这种位置映射应交给独立的 3D 战场表现层。
func _world(pos: Vector2) -> Vector2:
	return Vector2(70,157) + pos * Vector2(1300.0/float(sim.rules.world_width),352.0/float(sim.rules.world_height))

## 绘制地面网格、基地、血条、攻击线和场上单位；所有位置来自模拟器。
func _draw_battle() -> void:
	_panel(Rect2(32,98,1376,458),Color("0d1c2b"))
	for i in range(25):
		var x: float = 70+i*54.1667
		draw_line(Vector2(x,155),Vector2(x,509),Color("172a3a"))
	for i in range(9):
		draw_line(Vector2(70,157+i*44),Vector2(1370,157+i*44),Color("172a3a"))
	draw_line(Vector2(720,154),Vector2(720,510),Color("3c4d60"),2)
	_text(Vector2(56,130),"我方基地",18,MINT)
	_bar(Rect2(160,116,250,10),float(sim.bases[0])/float(sim.rules.base_hp),MINT)
	_text(Vector2(420,130),"%d" % sim.bases[0],18)
	_text(Vector2(1000,130),"敌方基地",18,CORAL)
	_bar(Rect2(1100,116,230,10),float(sim.bases[1])/float(sim.rules.base_hp),CORAL)
	_text(Vector2(1340,130),"%d" % sim.bases[1],16)
	_text(Vector2(470,130),_race_name(str(sim.races[0])),16,_race_color(str(sim.races[0])))
	var enemy_race: String = sim.visible_race(0, 1)
	_text(Vector2(900,130),_race_name(enemy_race) if enemy_race != "" else "种族未知",16,_race_color(enemy_race) if enemy_race != "" else MUTED)
	for team in range(2):
		var p := _world(sim.base_pos(team))
		var color: Color = MINT if team == 0 else CORAL
		draw_circle(p,40,Color(color,0.07))
		draw_arc(p,34,0,TAU,32,Color(color,0.5),2)
		draw_rect(Rect2(p-Vector2(17,26),Vector2(34,52)),Color(color,0.2))
		draw_rect(Rect2(p-Vector2(17,26),Vector2(34,52)),color,false,2)
		_text(p+Vector2(-7,7),"F" if team == 0 else "P",22,color)
	# 防卫圈是真正的攻击许可区域；按战场缩放绘制椭圆，不能误画成爆炸范围。
	for unit in sim.units:
		if unit.has("defender_center") and unit.get("siege_state","mobile") != "mobile":
			var zone_points := PackedVector2Array()
			var zone_radius: float = sim.catalog[unit.kind].skills.defender_zone.radius
			for segment in range(64):
				var angle: float = TAU * segment / 64.0
				zone_points.append(_world(unit.defender_center+Vector2(cos(angle),sin(angle))*zone_radius))
			var zone_color: Color = MINT if unit.team == 0 else CORAL
			draw_colored_polygon(zone_points,Color(zone_color,0.07))
			zone_points.append(zone_points[0])
			draw_polyline(zone_points,Color(zone_color,0.7),2)
	for effect in effects:
		if effect.type == "line_attack":
			var start := _world(effect.from)
			var finish := _world(effect.to)
			var direction := (finish-start).normalized()
			var normal := Vector2(-direction.y,direction.x)
			var base_color: Color = CORAL if _hidden_team(int(effect.team)) else Color(sim.catalog[effect.kind].color)
			var attack_color := Color(base_color,clampf(effect.ttl/0.24,0,1))
			if effect.effect == "beam":
				# 双束光束分别连接各自推进到的落点，不提前命中整条横线。
				draw_line(_world(effect.source),finish,Color(attack_color,attack_color.a*0.35),1.5)
				draw_line(start,finish,attack_color,5)
				draw_circle(finish,3,Color(INK,attack_color.a))
			else:
				draw_line(start,finish,attack_color,3)
				for fraction in [0.3,0.8]:
					var point: Vector2 = start.lerp(finish,fraction)
					draw_colored_polygon(PackedVector2Array([point+normal*6,point-normal*6,point+direction*9]),attack_color)
			continue
		if effect.type == "yamato":
			# 大和炮：粗光束加命中闪光，持续 0.5 秒逐渐消退。
			var fade: float = clampf(effect.ttl/0.5,0,1)
			draw_line(_world(effect.from),_world(effect.to),Color(Color("ffb347"),fade),7)
			draw_line(_world(effect.from),_world(effect.to),Color(INK,fade),2)
			draw_circle(_world(effect.to),16*fade+4,Color(Color("ffb347"),0.5*fade))
			continue
		var color := Color(MINT if effect.team == 0 else CORAL,clampf(effect.ttl/0.16,0,1))
		if effect.type == "heal":
			color = Color(Color("85efd9"), clampf(effect.ttl/0.16,0,1))
			draw_arc(_world(effect.to),18,0,TAU,20,color,2)
		draw_line(_world(effect.from),_world(effect.to),color,2)
		if effect.kind == "mortar":
			draw_arc(_world(effect.to),38,0,TAU,24,color,2)
	# 在上一模拟位置 prev 与当前位置 pos 之间插值，让 20 Hz 的计算看起来更平滑。
	var alpha := clampf(accumulator/0.05,0,1)
	for unit in sim.units:
		var p := _world(unit.prev.lerp(unit.pos,alpha))
		var color: Color = MINT if unit.team == 0 else CORAL
		if sim.is_structure(unit):
			_draw_structure(unit,p,color)
			continue
		if _hidden_team(int(unit.team)):
			# 首次交战前只看到有敌军在移动，看不出兵种与种族。
			draw_circle(p,9,Color("4a5a6c"))
			_text(p+Vector2(-4,5),"?",13,INK)
			draw_arc(p,14,0,TAU,16,color,1.8)
			continue
		_draw_unit(p,unit.kind,Color(sim.catalog[unit.kind].color),11)
		var charge: float = Yamato.charge(sim,unit) if sim.catalog[unit.kind].get("skills",{}).has("yamato") else -1.0
		if charge >= 0.0:
			# 大和炮引导：橙色光圈随进度变大，细线指向锁定目标。
			draw_circle(p,6+10*charge,Color(Color("ffb347"),0.25+0.4*charge))
			draw_arc(p,20,-PI*0.5,-PI*0.5+TAU*charge,24,Color("ffb347"),2)
			var locked = sim.by_id.get(int(unit.yamato_target))
			if locked != null:
				draw_line(p,_world(locked.pos),Color(Color("ffb347"),0.35),1)
		if sim.tick < int(unit.get("stim_until_tick",0)):
			draw_arc(p,18,0,TAU,20,Color("ffbe65"),2)
		if sim.tick < int(unit.get("slow_until_tick",0)):
			draw_line(p+Vector2(-10,17),p+Vector2(0,22),Color("77cfff"),2)
			draw_line(p+Vector2(0,22),p+Vector2(10,17),Color("77cfff"),2)
		if unit.has("siege_state"):
			var state: String = unit.siege_state
			var unit_skills: Dictionary = sim.catalog[unit.kind].skills
			var defending: bool = unit_skills.has("defender_zone")
			var deployment: Dictionary = unit_skills.defender_zone if defending else unit_skills.deployment
			var burrowing: bool = deployment.mode == "burrow"
			if burrowing and state == "deployed":
				draw_circle(p,12,Color("3d294b"))
				draw_arc(p,13,0,PI,10,Color(sim.catalog[unit.kind].color),3)
			if not burrowing and not defending and state != "mobile":
				# 展开支架与状态进度条，区分架设/收起和可开火状态。
				for side in [-1,1]:
					draw_line(p+Vector2(side*8,6),p+Vector2(side*19,16),color,3)
			if state == "deploying" or state == "packing":
				var duration: float = deployment.deploy_seconds if state == "deploying" else deployment.pack_seconds
				var progress: float = 1.0 - float(unit.siege_until_tick-sim.tick)/(duration*float(sim.rules.tick_rate))
				_bar(Rect2(p+Vector2(-16,21),Vector2(32,3)),progress,Color("f5b66e"))
				var deploying_text: String = "防卫展开" if defending else ("埋地" if burrowing else "架设")
				var packing_text: String = "恢复飞行" if defending else ("出土" if burrowing else "收起")
				_text(p+Vector2(-18,38),deploying_text if state == "deploying" else packing_text,12,color)
			elif state == "deployed":
				_text(p+Vector2(-18,32),"防卫对地" if defending else ("已埋地" if burrowing else "炮击"),12,color)
		draw_arc(p,14,0,TAU,16,color,1.8)
		_bar(Rect2(p+Vector2(-13,-22),Vector2(26,3)),float(unit.hp)/float(sim.catalog[unit.kind].hp),color)
		var max_shield: float = float(sim.catalog[unit.kind].get("shield",0))
		if max_shield > 0:
			# 护盾条画在血条上方；有盾时外圈再加一道蓝色弧线。
			_bar(Rect2(p+Vector2(-13,-26),Vector2(26,2)),float(unit.shield)/max_shield,SHIELD)
			if float(unit.shield) > 0:
				draw_arc(p,16,0,TAU,20,Color(SHIELD,0.6),1.5)
	_text(Vector2(56,539),"自动交战区域  /  不能手动移动或施法",16,MUTED)
	_text(Vector2(1050,539),"绿色：我方    橙色：敌方",16,MUTED)

## 对方种族尚未公开时，界面不能画出对方的兵种外形。
func _hidden_team(team: int) -> bool:
	return team != 0 and not sim.revealed

func _race_color(race: String) -> Color:
	return Color(str(race_info[race].color)) if race_info.has(race) else MUTED

## 结构体：淡色射程圈（按战场缩放）、按种族区分的外形（数值相同）、阵营圈与较宽血条。
func _draw_structure(unit: Dictionary, p: Vector2, color: Color) -> void:
	var stats: Dictionary = sim.catalog[unit.kind]
	var ring := PackedVector2Array()
	for segment in range(49):
		var angle: float = TAU * segment / 48.0
		var point: Vector2 = unit.pos+Vector2(cos(angle),sin(angle))*float(stats.range)
		ring.append(_world(point.clamp(Vector2.ZERO,Vector2(float(sim.rules.world_width),float(sim.rules.world_height)))))
	draw_polyline(ring,Color(color,0.18),1.5)
	_draw_structure_shape(p,unit.kind,sim.visible_race(0,int(unit.team)),15)
	draw_arc(p,22,0,TAU,24,color,2)
	_bar(Rect2(p+Vector2(-22,-32),Vector2(44,4)),float(unit.hp)/float(stats.hp),color)

## 结构体外形按种族区分：人族方正砖石、虫族有机肉瘤、神族晶体、腐族破烂尖刺；种族未知时画灰色八边形。
func _draw_structure_shape(p: Vector2, kind: String, race: String, radius: float) -> void:
	var tint: Color = _race_color(race)
	var dark := Color("162334")
	match race:
		"terran":
			_draw_unit(p,kind,Color(sim.catalog[kind].color),radius)
		"zerg":
			draw_circle(p,radius*0.95,tint)
			var spikes: int = 3 if kind == "treasury" else 5
			for i in range(spikes):
				var angle: float = -PI*0.5 + TAU*i/spikes
				var dir := Vector2(cos(angle),sin(angle))
				var side := Vector2(-dir.y,dir.x)
				draw_colored_polygon(PackedVector2Array([p+dir*radius*0.7+side*radius*0.25,p+dir*radius*1.45,p+dir*radius*0.7-side*radius*0.25]),tint)
			draw_circle(p,radius*0.4,dark)
			if kind == "tower":
				draw_circle(p,radius*0.2,tint)
		"protoss":
			if kind == "treasury":
				var hexagon := PackedVector2Array()
				for i in range(6):
					hexagon.append(p+Vector2(cos(TAU*i/6.0),sin(TAU*i/6.0))*radius)
				draw_colored_polygon(hexagon,tint)
			else:
				draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*1.35),p+Vector2(radius*0.7,0),p+Vector2(0,radius*1.1),p+Vector2(-radius*0.7,0)]),tint)
			draw_arc(p,radius*0.55,0,TAU,20,INK,2)
			if kind != "treasury":
				draw_circle(p,radius*0.25,INK)
		"blight":
			var blob := PackedVector2Array()
			for i in range(10):
				var length: float = radius*(1.25 if i % 2 == 0 else 0.75)
				blob.append(p+Vector2(cos(TAU*i/10.0),sin(TAU*i/10.0))*length)
			draw_colored_polygon(blob,tint)
			draw_circle(p,radius*0.45,dark)
			for x in [-0.35,0.15]:
				draw_line(p+Vector2(x*radius,radius*0.6),p+Vector2(x*radius,radius*1.3),tint,2)
		_:
			var octagon := PackedVector2Array()
			for i in range(8):
				octagon.append(p+Vector2(cos(TAU*(i+0.5)/8.0),sin(TAU*(i+0.5)/8.0))*radius)
			draw_colored_polygon(octagon,Color("4a5a6c"))
			_text(p+Vector2(-5,6),"?",16,INK)

## 用不同几何形状区分各个兵种。这里只画外形，不包含移动或攻击逻辑。
func _draw_unit(p: Vector2, kind: String, color: Color, radius: float) -> void:
	match kind:
		"gate_tower":
			draw_rect(Rect2(p-Vector2(radius*0.9,radius*0.6),Vector2(radius*1.8,radius*1.5)),color)
			for x in [-0.9,-0.15,0.6]:
				draw_rect(Rect2(p+Vector2(x*radius,-radius),Vector2(radius*0.3,radius*0.4)),color)
			draw_rect(Rect2(p+Vector2(-radius*0.25,radius*0.2),Vector2(radius*0.5,radius*0.7)),Color("162334"))
		"treasury":
			draw_circle(p,radius,color)
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*0.6),p+Vector2(radius*0.6,0),p+Vector2(0,radius*0.6),p+Vector2(-radius*0.6,0)]),Color("6b4f10"))
		"tower":
			draw_rect(Rect2(p-Vector2(radius*0.8,radius*0.3),Vector2(radius*1.6,radius*1.1)),color)
			draw_circle(p+Vector2(0,-radius*0.3),radius*0.55,color)
			draw_line(p+Vector2(0,-radius*0.3),p+Vector2(0,-radius*1.2),INK,3)
		"liberator":
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*1.4),p+Vector2(radius*1.5,radius*0.8),p+Vector2(0,radius*0.35),p+Vector2(-radius*1.5,radius*0.8)]),color)
			for side in [-1,1]:
				draw_circle(p+Vector2(side*radius*0.8,radius*0.4),radius*0.3,Color("223751"))
			draw_line(p+Vector2(0,-radius*0.65),p+Vector2(0,radius*0.25),INK,2)
		"marauder":
			# 重装躯干和双侧榴弹发射器；外观不改变单次攻击次数。
			draw_rect(Rect2(p-Vector2(radius*0.65,radius*0.8),Vector2(radius*1.3,radius*1.6)),color)
			for side in [-1,1]:
				draw_rect(Rect2(p+Vector2(side*radius-radius*0.3,-radius*0.55),Vector2(radius*0.6,radius*1.1)),color)
			draw_line(p+Vector2(-radius*0.35,-radius*0.3),p+Vector2(radius*0.35,-radius*0.3),INK,2)
		"colossus":
			for side in [-1,1]:
				for vertical in [-1,1]:
					draw_line(p+Vector2(side*radius*0.4,vertical*radius*0.4),p+Vector2(side*radius*1.3,vertical*radius*1.2),color,2)
				draw_circle(p+Vector2(side*radius*0.9,0),radius*0.25,INK)
			draw_rect(Rect2(p-Vector2(radius*0.55,radius*0.75),Vector2(radius*1.1,radius*1.5)),color)
		"piercer":
			for side in [-1,1]:
				for offset in [-0.6,0.6]:
					draw_line(p+Vector2(side*radius*0.4,offset*radius),p+Vector2(side*radius*1.3,offset*radius*1.3),color,2)
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius),p+Vector2(radius*0.7,0),p+Vector2(0,radius),p-Vector2(radius*0.7,0)]),color)
		"medic":
			draw_circle(p,radius,color)
			draw_rect(Rect2(p-Vector2(radius*0.65,radius*0.2),Vector2(radius*1.3,radius*0.4)),Color("162334"))
			draw_rect(Rect2(p-Vector2(radius*0.2,radius*0.65),Vector2(radius*0.4,radius*1.3)),Color("162334"))
		"vanguard":
			draw_colored_polygon(PackedVector2Array([p+Vector2(-radius,-radius),p+Vector2(radius,-radius),p+Vector2(radius,radius*0.4),p+Vector2(0,radius*1.3),p+Vector2(-radius,radius*0.4)]),color)
		"swarm":
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius),p+Vector2(radius,radius),p+Vector2(-radius,radius)]),color)
		"mortar":
			draw_rect(Rect2(p-Vector2.ONE*radius,Vector2.ONE*radius*2),color)
			draw_circle(p,radius*0.5,Color("162334"))
		"agent":
			# 十字准星叠菱形：远程狙击与穿甲两种弹药。
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*0.7),p+Vector2(radius*0.7,0),p+Vector2(0,radius*0.7),p+Vector2(-radius*0.7,0)]),color)
			draw_line(p-Vector2(radius*1.2,0),p+Vector2(radius*1.2,0),color,2)
			draw_line(p-Vector2(0,radius*1.2),p+Vector2(0,radius*1.2),color,2)
		"zergling", "hellbat":
			draw_colored_polygon(PackedVector2Array([p+Vector2(radius,0),p+Vector2(-radius*0.8,-radius),p+Vector2(-radius*0.3,0),p+Vector2(-radius*0.8,radius)]),color)
		"viking", "fly_swarm", "spore_drifter":
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*1.2),p+Vector2(radius*1.3,radius*0.7),p+Vector2(-radius*1.3,radius*0.7)]),color)
			draw_circle(p,radius*0.3,Color("223751"))
		"void_ray":
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*1.3),p+Vector2(radius*1.1,0),p+Vector2(0,radius*1.3),p+Vector2(-radius*1.1,0)]),color)
			draw_circle(p,radius*0.4,INK)
		"battlecruiser":
			# 长舰体、前伸双叉与舰桥；空中旗舰。
			draw_colored_polygon(PackedVector2Array([p+Vector2(-radius*1.5,-radius*0.6),p+Vector2(radius*0.9,-radius*0.6),p+Vector2(radius*1.6,-radius*0.25),p+Vector2(radius*1.6,radius*0.25),p+Vector2(radius*0.9,radius*0.6),p+Vector2(-radius*1.5,radius*0.6),p+Vector2(-radius*1.2,0)]),color)
			draw_line(p+Vector2(radius*0.9,-radius*0.6),p+Vector2(radius*1.8,-radius*0.75),color,2)
			draw_line(p+Vector2(radius*0.9,radius*0.6),p+Vector2(radius*1.8,radius*0.75),color,2)
			draw_rect(Rect2(p+Vector2(-radius*0.5,-radius*0.3),Vector2(radius*0.6,radius*0.6)),Color("223751"))
		"rifle":
			draw_circle(p,radius*0.8,color)
			draw_rect(Rect2(p+Vector2(radius*0.3,-radius*0.2),Vector2(radius*0.9,radius*0.4)),color)
		"widow_mine":
			for angle in [PI*0.25,PI*0.75,PI*1.25,PI*1.75]:
				draw_line(p,p+Vector2(cos(angle),sin(angle))*radius*1.2,color,2)
			draw_circle(p,radius*0.55,color)
			draw_circle(p,radius*0.2,Color("ff6f5e"))
		"thor":
			draw_rect(Rect2(p-Vector2(radius*0.75,radius*0.6),Vector2(radius*1.5,radius*1.5)),color)
			for side in [-1,1]:
				draw_circle(p+Vector2(side*radius*0.95,-radius*0.55),radius*0.45,color)
			draw_rect(Rect2(p+Vector2(-radius*0.3,-radius*0.25),Vector2(radius*0.6,radius*0.3)),Color("162334"))
		"roach":
			var shell := PackedVector2Array()
			for i in range(12):
				shell.append(p+Vector2(cos(TAU*i/12.0)*radius*1.1,sin(TAU*i/12.0)*radius*0.75))
			draw_colored_polygon(shell,color)
			draw_line(p+Vector2(-radius*0.7,0),p+Vector2(radius*0.7,0),Color("162334"),2)
		"hydralisk":
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*1.2),p+Vector2(radius*0.45,radius),p+Vector2(-radius*0.45,radius)]),color)
			for side in [-1,1]:
				draw_colored_polygon(PackedVector2Array([p+Vector2(side*radius*0.2,-radius*0.7),p+Vector2(side*radius*1.1,-radius*0.2),p+Vector2(side*radius*0.3,0)]),color)
		"ultralisk":
			draw_circle(p,radius,color)
			for side in [-1,1]:
				draw_line(p+Vector2(radius*0.6,side*radius*0.4),p+Vector2(radius*1.4,side*radius*0.9),INK,2)
		"stalker":
			for side in [-1,1]:
				for vertical in [-1,1]:
					draw_line(p,p+Vector2(side*radius*1.2,vertical*radius*1.1),color,2)
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*0.8),p+Vector2(radius*0.6,0),p+Vector2(0,radius*0.6),p+Vector2(-radius*0.6,0)]),color)
			draw_circle(p+Vector2(0,-radius*0.1),radius*0.2,INK)
		"immortal":
			var hull := PackedVector2Array()
			for i in range(6):
				hull.append(p+Vector2(cos(TAU*i/6.0+PI/6.0),sin(TAU*i/6.0+PI/6.0))*radius)
			draw_colored_polygon(hull,color)
			draw_rect(Rect2(p-Vector2(radius*0.35,radius*0.35),Vector2(radius*0.7,radius*0.7)),Color("162334"))
		"archon":
			draw_circle(p,radius*0.75,color)
			draw_arc(p,radius*1.15,0,TAU,20,Color(color,0.6),2)
			draw_circle(p,radius*0.3,INK)
		"spitter":
			draw_circle(p,radius*0.85,color)
			draw_circle(p+Vector2(radius*0.45,0),radius*0.3,Color("162334"))
		"abomination":
			for offset in [Vector2(-0.45,-0.25),Vector2(0.4,-0.3),Vector2(0,0.4)]:
				draw_circle(p+offset*radius,radius*0.7,color)
			draw_line(p+Vector2(-radius*0.5,0),p+Vector2(radius*0.5,radius*0.1),Color("162334"),2)
		_:
			# 尚无专属外形的兵种：圆形加兵种字母。
			draw_circle(p,radius,color)
			_text(p+Vector2(-radius*0.45,radius*0.5),str(sim.catalog[kind].get("symbol","?")),int(maxf(radius*1.2,8)),Color("162334"))

## 按 rules 的列数×行数绘制兵营格子、兵种卡片、矿物与敌情；敌情只使用上一波公开阵容。
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
	var tower_cost: int = int(sim.catalog.tower.cost)
	if int(sim.tower_builds[0]) >= int(sim.rules.tower_max_builds):
		_panel(Rect2(440,816,180,32),Color("142233"),Color("2b3b50"))
		_text(Vector2(454,839),"防御塔已建造",17,MUTED)
	else:
		_button(Rect2(440,816,180,32),"建造防御塔 %d" % tower_cost,"build_tower",int(sim.minerals[0]) >= tower_cost)
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
		_text(rect.position+Vector2(10,44),str(stats.role),12,MUTED)
		buttons.append({"rect":rect,"action":"select:"+kind})
		i += 1
	if sim.catalog.has(selected):
		_text(Vector2(764,806),sim.catalog[selected].counter,17,Color("e6c28e"))
		_text(Vector2(764,834),"点空格购买  ·  本轮新买的单位取消可全额退回",15,MUTED)
	else:
		_text(Vector2(764,806),"点击要取消的单位；已出场过的不退款" if selected=="erase" else "先点单位，再点目标格；占用格会交换，免费。",17,MINT)
	_panel(Rect2(1212,573,196,287))
	_text(Vector2(1226,604),"敌情 / 上一波",20,CORAL)
	var counts: Dictionary = {}
	for slot in sim.visible_enemy_formation(0):
		counts[slot.kind] = int(counts.get(slot.kind,0))+1
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

## 绘制说明弹层，并清空底层点击区域，防止点说明时误操作后面的配兵格。
func _draw_help() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(0,0,0,0.8))
	_panel(Rect2(290,130,860,640))
	buttons.clear()
	_text(Vector2(335,188),"指挥官手册",32,MINT)
	var lines := ["1. 选兵种，再点下方空格购买。右侧是前排，左侧是后排。",
		"2. 买下的单位永久留在兵营，每 %d 秒全部出场一次。" % int(sim.rules.wave_seconds),
		"3. 开局 %d 矿，每次出兵后双方各得 %d 矿；击杀不加钱。" % [int(sim.rules.start_minerals),int(sim.rules.wave_income)],
		"4. 本轮新买、未出场的单位取消可全额退回；出场过的取消不退款。",
		"5. 部队一直战斗到阵亡；移动兵营里的单位免费。",
		"6. 观察敌方上一波，选择克制组合。AI 不偷看你的新阵容。",
		"   门口塔守护基地，塔倒后基地无还手；摧毁敌方宝库奖励 %d 矿。" % int(sim.rules.treasury_reward),
		"   可花 %d 矿建造一座防御塔，前期火力强，被摧毁无奖励、不能重建。" % int(sim.catalog.tower.cost),
		"7. 摧毁基地获胜；第 %d 波后先没有可攻击部队的一方失败。" % int(sim.rules.wave_limit),
		"8. 空格键暂停，Esc 打开说明；手机切后台会自动暂停。",
		"   双方种族在开局选择、整局固定；首次交战后才看到敌方种族与阵容。",
		"提示：重甲怕穿甲加成，轻甲怕溅射；神族护盾脱战后会恢复。"]
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
	var minutes: float = float(sim.rules.wave_limit) * float(match_settings.wave_seconds) / 60.0
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
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var p: Vector2 = event.position * Vector2(1440,900) / size
		for button in buttons:
			if button.rect.has_point(p):
				handle_action(button.action)
				accept_event()
				break

## 处理快捷键：空格开始/暂停，Esc 打开或关闭说明；忽略长按产生的重复事件。
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE and not help_open and not setup_open and not sim.finished:
			handle_action("start")
		elif event.keycode == KEY_ESCAPE:
			handle_action("help")

## 把动作字符串分发到具体操作；例如 select:rifle 选择步枪兵，cell:5 编辑第 5 格。
## 绘制按钮和处理操作通过动作名连接，添加按钮时要在这里增加对应逻辑。
func handle_action(action: String) -> void:
	if setup_open:
		if action.begins_with("setup"):
			_handle_setup(action)
		queue_redraw()
		return
	if action == "help":
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
			var error: String = sim.build_tower(0)
			_note(error if error != "" else "防御塔已建成，一局只能建造一座。")
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
