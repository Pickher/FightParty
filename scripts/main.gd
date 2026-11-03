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
# 界面颜色常量。修改这里可以调整主题；不会改变兵种伤害或阵营规则。
const INK := Color("e4edf8")
const MUTED := Color("8e9fb5")
const MINT := Color("70e2b4")
const CORAL := Color("ff927f")
const PANEL := Color("101e30")
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

## 节点进入场景后初始化：接管点击、准备音效、读取设置、建立对局、开启每帧更新。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(speaker)
	_make_sound()
	_load_settings()
	_new_match()
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

## 新建模拟器与 AI，尝试恢复上次阵容；若超出首波预算则用默认阵容。
## 重置开始、暂停和特效状态。进入游戏后仍要点击“开始准备”才会计时。
func _new_match() -> void:
	var prior: Array = Catalog.starter()
	sim = Sim.new(42)
	ai = AI.new(42)
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		var saved = config.get_value("player", "formation", Catalog.starter())
		if saved is Array:
			prior = saved
	if sim.validate_formation(prior, sim.budget()) != "":
		prior = Catalog.starter()
	sim.submit_formation(0, prior)
	sim.submit_formation(1, ai.choose([], sim.budget()))
	started = false
	paused = false
	accumulator = 0.0
	effects.clear()
	messages = ["双方同额预算。击杀不加钱，下一波可自由重配。"]
	move_source = -1
	journal_error = false
	queue_redraw()

## 从 user://settings.cfg 读取音量；user:// 是玩家数据目录，不是源码目录。
func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		volume = clampf(float(config.get_value("audio","volume",0.4)), 0.0, 1.0)
	speaker.volume_db = linear_to_db(maxf(volume, 0.001))

## 保存当前音量和下一波阵容。失败只给提示，不影响继续战斗。
func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio","volume",volume)
	config.set_value("player","formation",sim.formations[0])
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
		if event.type == "attack" or event.type == "heal" or event.type == "line_attack":
			event.ttl = 0.24 if event.type == "line_attack" else 0.16
			effects.append(event)
		elif event.type == "wave":
			_note("第 %d 波出兵 · 我方 %d / 敌方 %d" % [sim.wave,sim.last_formations[0].size(),sim.last_formations[1].size()])
			sim.submit_formation(1, ai.choose(sim.last_formations[0], sim.budget()))
			_save_journal()
			if volume > 0:
				speaker.play()
		elif event.type == "ended":
			_save_journal()
			speaker.play()

## 将最新提示放在消息列表最前面，最多保留五条；界面显示最新一条。
func _note(message: String) -> void:
	messages.push_front(message)
	if messages.size() > 5:
		messages.pop_back()

## 绘制一行文字。pos 是文字基线位置，font_size 是字号，color 是颜色。
func _text(pos: Vector2, message: String, font_size: int = 20, color: Color = INK) -> void:
	draw_string(FONT, pos, message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## 绘制圆角面板；StyleBoxFlat 指定背景、边框和圆角。
func _panel(rect: Rect2, color: Color = PANEL, border: Color = Color("26384e")) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
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
	_text(Vector2(400,37),"下一波  %02d" % (sim.wave+1),18,MUTED)
	var countdown: int = int(ceil(float(int(sim.rules.wave_seconds * sim.rules.tick_rate) - sim.tick % int(sim.rules.wave_seconds * sim.rules.tick_rate)) / float(sim.rules.tick_rate)))
	_text(Vector2(400,74),"%02d 秒" % countdown,30,INK)
	_text(Vector2(577,37),"双方本波预算",18,MUTED)
	_text(Vector2(577,74),str(sim.budget()),30,MINT)
	_text(Vector2(762,37),"战局时间",18,MUTED)
	var seconds: int = sim.tick / int(sim.rules.tick_rate)
	_text(Vector2(762,74),"%02d:%02d / 08:00" % [seconds/60,seconds%60],24)
	_button(Rect2(1000,24,120,48),"音量 %d" % int(volume*100),"volume")
	_button(Rect2(1132,24,120,48),"玩法说明","help")
	_button(Rect2(1264,24,144,48),"开始准备" if not started else ("继续战斗" if paused else "暂停战斗"),"start",true)
	_draw_battle()
	_draw_editor()
	_text(Vector2(34,882),"离线原型 v0.1.7  /  无击杀收入  /  残兵最多保留 90 秒",16,MUTED)
	_text(Vector2(1000,882),"%d FPS   ·   %d 个战场单位" % [Engine.get_frames_per_second(),sim.units.size()],16,MUTED)
	if not started:
		_panel(Rect2(440,263,560,130), Color("102d32"), MINT)
		_text(Vector2(475,308),"先布阵，再让军队替你战斗。",28,MINT)
		_text(Vector2(475,346),"点击右上角「开始准备」，30 秒后双方同时出兵。",18)
		_text(Vector2(475,373),"战斗期间随时修改下一波；不能直接指挥场上单位。",18,MUTED)
	if paused and not sim.finished:
		_panel(Rect2(525,284,390,90))
		_text(Vector2(580,338),"已暂停 · 阵容仍可调整",25,MINT)
	if sim.finished:
		_draw_result()
	if help_open:
		_draw_help()

## 把 1200×400 的逻辑战场坐标转换成屏幕战场区域坐标。
## 未来改 3D 时，这种位置映射应交给独立的 3D 战场表现层。
func _world(pos: Vector2) -> Vector2:
	return Vector2(70,157) + pos * Vector2(1300.0/1200.0,0.88)

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
	for team in range(2):
		var p := _world(Vector2(30 if team == 0 else 1170,200))
		var color: Color = MINT if team == 0 else CORAL
		draw_circle(p,40,Color(color,0.07))
		draw_arc(p,34,0,TAU,32,Color(color,0.5),2)
		draw_rect(Rect2(p-Vector2(17,26),Vector2(34,52)),Color(color,0.2))
		draw_rect(Rect2(p-Vector2(17,26),Vector2(34,52)),color,false,2)
		_text(p+Vector2(-7,7),"F" if team == 0 else "P",22,color)
	for effect in effects:
		if effect.type == "line_attack":
			var start := _world(effect.from)
			var finish := _world(effect.to)
			var direction := (finish-start).normalized()
			var normal := Vector2(-direction.y,direction.x)
			var attack_color := Color(Color(sim.catalog[effect.kind].color),clampf(effect.ttl/0.24,0,1))
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
		_draw_unit(p,unit.kind,Color(sim.catalog[unit.kind].color),11)
		if sim.tick < int(unit.get("stim_until_tick",0)):
			draw_arc(p,18,0,TAU,20,Color("ffbe65"),2)
		if sim.tick < int(unit.get("slow_until_tick",0)):
			draw_line(p+Vector2(-10,17),p+Vector2(0,22),Color("77cfff"),2)
			draw_line(p+Vector2(0,22),p+Vector2(10,17),Color("77cfff"),2)
		if unit.has("siege_state"):
			var state: String = unit.siege_state
			var deployment: Dictionary = sim.catalog[unit.kind].skills.deployment
			var burrowing: bool = deployment.mode == "burrow"
			if burrowing and state == "deployed":
				draw_circle(p,12,Color("3d294b"))
				draw_arc(p,13,0,PI,10,Color(sim.catalog[unit.kind].color),3)
			if not burrowing and state != "mobile":
				# 展开支架与状态进度条，区分架设/收起和可开火状态。
				for side in [-1,1]:
					draw_line(p+Vector2(side*8,6),p+Vector2(side*19,16),color,3)
			if state == "deploying" or state == "packing":
				var duration: float = deployment.deploy_seconds if state == "deploying" else deployment.pack_seconds
				var progress: float = 1.0 - float(unit.siege_until_tick-sim.tick)/(duration*float(sim.rules.tick_rate))
				_bar(Rect2(p+Vector2(-16,21),Vector2(32,3)),progress,Color("f5b66e"))
				_text(p+Vector2(-18,38),("埋地" if burrowing else "架设") if state == "deploying" else ("出土" if burrowing else "收起"),12,color)
			elif state == "deployed":
				_text(p+Vector2(-18,32),"已埋地" if burrowing else "炮击",12,color)
		draw_arc(p,14,0,TAU,16,color,1.8)
		_bar(Rect2(p+Vector2(-13,-22),Vector2(26,3)),float(unit.hp)/float(sim.catalog[unit.kind].hp),color)
	_text(Vector2(56,539),"自动交战区域  /  不能手动移动或施法",16,MUTED)
	_text(Vector2(1050,539),"绿色：我方    橙色：敌方",16,MUTED)

## 用不同几何形状区分各个兵种。这里只画外形，不包含移动或攻击逻辑。
func _draw_unit(p: Vector2, kind: String, color: Color, radius: float) -> void:
	match kind:
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
		"guard":
			draw_colored_polygon(PackedVector2Array([p+Vector2(-radius,-radius),p+Vector2(radius,-radius),p+Vector2(radius,radius*0.4),p+Vector2(0,radius*1.3),p+Vector2(-radius,radius*0.4)]),color)
		"swarm":
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius),p+Vector2(radius,radius),p+Vector2(-radius,radius)]),color)
		"mortar":
			draw_rect(Rect2(p-Vector2.ONE*radius,Vector2.ONE*radius*2),color)
			draw_circle(p,radius*0.5,Color("162334"))
		"sniper":
			draw_line(p-Vector2(radius,0),p+Vector2(radius,0),color,4)
			draw_line(p-Vector2(0,radius),p+Vector2(0,radius),color,4)
		"breaker":
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius),p+Vector2(radius,0),p+Vector2(0,radius),p+Vector2(-radius,0)]),color)
		_:
			draw_circle(p,radius,color)

## 绘制 6×4 布阵格子、兵种卡片、预算与敌情；敌情只使用上一波公开阵容。
func _draw_editor() -> void:
	_panel(Rect2(32,573,406,277))
	_text(Vector2(52,606),"下一波布阵",23)
	_text(Vector2(235,604),"后排  →  前线",18,MINT)
	# 把阵容转为“格子编号 → 兵种”的字典，方便逐格绘制。
	var occupied := {}
	for slot in sim.formations[0]:
		occupied[int(slot.cell)] = slot.kind
	for cell in range(24):
		var rect := Rect2(52+(cell%6)*61,623+(cell/6)*43,55,37)
		_panel(rect,Color("1c3445") if occupied.has(cell) else Color("102335"),MINT if cell == move_source else Color("30475a"))
		if occupied.has(cell):
			_draw_unit(rect.get_center(),occupied[cell],Color(sim.catalog[occupied[cell]].color),11)
		buttons.append({"rect":rect,"action":"cell:%d" % cell})
	_button(Rect2(52,805,110,32),"移除单位","erase",selected=="erase")
	_button(Rect2(174,805,110,32),"移动位置","move",selected=="move")
	_button(Rect2(296,805,122,32),"清空阵容","clear")
	_panel(Rect2(453,573,644,277))
	_text(Vector2(475,605),"选择兵种",23)
	var page_count := ceili(float(sim.catalog.size()) / UNITS_PER_PAGE)
	if page_count > 1:
		_button(Rect2(577,579,30,32),"<","units_prev")
		_text(Vector2(611,602),"%d/%d" % [unit_page+1,page_count],15,MUTED)
		_button(Rect2(644,579,30,32),">","units_next")
	var cost: int = sim.formation_cost(sim.formations[0])
	_text(Vector2(675,605),"已配置 %d / %d   ·   剩余 %d" % [cost,sim.budget(),sim.budget()-cost],20,MINT)
	var i := 0
	var kinds: Array = sim.catalog.keys()
	for kind in kinds.slice(unit_page*UNITS_PER_PAGE,(unit_page+1)*UNITS_PER_PAGE):
		var stats: Dictionary = sim.catalog[kind]
		var rect := Rect2(475+(i%3)*203,619+(i/3)*55,191,50)
		_panel(rect,Color("233e41") if selected==kind else Color("17293c"),MINT if selected==kind else Color("304358"))
		_draw_unit(rect.position+Vector2(22,20),kind,Color(stats.color),10)
		_text(rect.position+Vector2(43,25),stats.name,21)
		_text(rect.position+Vector2(135,24),str(int(stats.cost)),18,MINT)
		_text(rect.position+Vector2(12,44),str(stats.role),13,MUTED)
		buttons.append({"rect":rect,"action":"select:"+kind})
		i += 1
	if sim.catalog.has(selected):
		_text(Vector2(475,809),sim.catalog[selected].counter,18,Color("e6c28e"))
		_text(Vector2(475,836),"点格放置 / 替换  ·  合法调整自动保存",16,MUTED)
	else:
		_text(Vector2(475,809),"点击要移除的单位" if selected=="erase" else "先点单位，再点目标格；占用格会交换。",18,MINT)
	_panel(Rect2(1112,573,296,277))
	_text(Vector2(1132,605),"敌情 / 上一波",22,CORAL)
	var counts: Dictionary = {}
	for slot in sim.last_formations[1]:
		counts[slot.kind] = int(counts.get(slot.kind,0))+1
	if counts.is_empty():
		_text(Vector2(1132,640),"尚未出兵",18,MUTED)
	else:
		var n := 0
		for kind in counts:
			_text(Vector2(1132+(n%2)*130,631+(n/2)*21),"%s ×%d" % [sim.catalog[kind].name,counts[kind]],17)
			n+=1
	_text(Vector2(1132,732),"下一波敌方配置保密",16,MUTED)
	_text(Vector2(1132,765),"击破 %d   /   损失 %d" % [sim.kills[0],sim.kills[1]],18,MINT)
	_text(Vector2(1132,795),"最新战报",16,MUTED)
	var message: String = messages[0]
	_text(Vector2(1132,824),message.left(16),16,Color("e6c28e"))
	if message.length()>16:
		_text(Vector2(1132,844),message.substr(16,16),16,Color("e6c28e"))

## 绘制说明弹层，并清空底层点击区域，防止点说明时误操作后面的配兵格。
func _draw_help() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(0,0,0,0.8))
	_panel(Rect2(290,130,860,640))
	buttons.clear()
	_text(Vector2(335,188),"指挥官手册",32,MINT)
	var lines := ["1. 选兵种，再点下方网格。右侧是前排，左侧是后排。",
		"2. 每 30 秒双方同时出兵；战斗不停，阵容修改用于下一波。",
		"3. 每波预算相同：600 起步，每波 +100，最多 1200。",
		"4. 剩余预算不结转；击杀不加钱。可随时免费换阵容。",
		"5. 残兵保留位置与血量继续推进，90 秒后自动撤离。",
		"6. 观察敌方上一波，选择克制组合。AI 不偷看你的新阵容。",
		"7. 摧毁基地获胜；8 分钟后比较基地血量，相同则平局。",
		"8. 空格键暂停，Esc 打开说明；手机切后台会自动暂停。",
		"提示：盾卫保护后排；分散站位可以降低迫击炮的收益。"]
	for i in range(lines.size()):
		_text(Vector2(335,247+i*43),lines[i],21,INK if i<8 else MINT)
	_button(Rect2(335,675,170,52),"明白了，返回","help",true)
	_text(Vector2(540,708),"查看手册时，对局计时暂停。",18,MUTED)

## 根据 sim.winner 显示结算结果及重开按钮；不在界面里重新决定胜负。
func _draw_result() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(0,0,0,0.75))
	_panel(Rect2(420,210,600,440))
	buttons.clear()
	_text(Vector2(465,275),"战线突破 · 胜利" if sim.winner==0 else ("基地失守 · 失败" if sim.winner==1 else "势均力敌 · 平局"),34,MINT if sim.winner!=1 else CORAL)
	_text(Vector2(465,330),"完成 %d 波出兵   ·   战斗 %d 秒" % [sim.wave,sim.tick/20],22)
	_text(Vector2(465,380),"基地剩余    我方 %d  /  敌方 %d" % [sim.bases[0],sim.bases[1]],22)
	_text(Vector2(465,425),"击破 %d    损失 %d" % [sim.kills[0],sim.kills[1]],22)
	_text(Vector2(465,472),"战报保存失败，请检查磁盘空间。" if journal_error else "战报已保存，可用于复现配兵与战斗过程。",18,MUTED)
	_button(Rect2(465,535,210,60),"调整阵容，再来一局","restart",true)
	_button(Rect2(700,535,210,60),"查看玩法说明","help")

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
		if event.keycode == KEY_SPACE and not help_open and not sim.finished:
			handle_action("start")
		elif event.keycode == KEY_ESCAPE:
			handle_action("help")

## 把动作字符串分发到具体操作；例如 select:guard 选择盾卫，cell:5 编辑第 5 格。
## 绘制按钮和处理操作通过动作名连接，添加按钮时要在这里增加对应逻辑。
func handle_action(action: String) -> void:
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
	elif not sim.finished:
		if action == "units_prev" or action == "units_next":
			var page_count := ceili(float(sim.catalog.size()) / UNITS_PER_PAGE)
			unit_page = posmod(unit_page + (1 if action == "units_next" else -1),page_count)
		elif action.begins_with("select:"):
			selected = action.get_slice(":",1)
			var index: int = sim.catalog.keys().find(selected)
			if index >= 0:
				unit_page = index / UNITS_PER_PAGE
			move_source = -1
		elif action == "erase" or action == "move":
			selected=action
			move_source=-1
		elif action == "clear":
			_commit([])
		elif action.begins_with("cell:"):
			_edit_cell(int(action.get_slice(":",1)))
	queue_redraw()

## 将编辑后的阵容送入统一校验入口。合法才保存，不合法则保留旧阵容并提示。
func _commit(formation: Array) -> void:
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
			for slot in formation:
				if int(slot.cell)==move_source:
					slot.cell=cell
				elif int(slot.cell)==cell:
					slot.cell=move_source
			move_source=-1
			_commit(formation)
		return
	if index>=0:
		formation.remove_at(index)
	if selected!="erase":
		formation.append({"kind":selected,"cell":cell})
	_commit(formation)
