# 只做表现：观察单位与事件，不写模拟状态。规格与特战队员（rifle_visual.gd）同一套：
# 精灵图横向是时间帧，帧尺寸/锚点/每格像素见 assets/units/battlecruiser/manifest.json。
# 原画是朝右的侧视图，只有一个方向；朝左时整幅水平镜像。
extends RefCounted
const TEXTURES := {
	"idle": preload("res://assets/units/battlecruiser/idle.png"),
	"move": preload("res://assets/units/battlecruiser/move.png"),
	"fire": preload("res://assets/units/battlecruiser/fire.png"),
	"yamato": preload("res://assets/units/battlecruiser/yamato.png"),
	"death": preload("res://assets/units/battlecruiser/death.png")
}
const FRAME := Vector2(320, 180)
const ANCHOR := Vector2(173.5, 80.5)
const PIXELS_PER_CELL := 80.0
const COUNTS := {"idle":8, "move":2, "fire":2, "yamato":4, "death":4}
const FPS := {"idle":8.0/2.4, "move":4.0, "fire":10.0}
# yamato：0～2.0 秒引导（蓄能→锁定），2.0 秒开炮，2.45 秒光束收尾，3.2 秒恢复巡航亮度。
const STARTS := {"yamato":[0.0, 1.2, 2.0, 2.45], "death":[0.0, 0.25, 0.56, 0.9]}
const ENDS := {"yamato":3.2, "death":1.4}
const YAMATO_FIRE_AGE := 2.0
const FIRE_HOLD := 0.3
const MUZZLES := {
	"wing_barrel": Vector2(176.75, 132.0),
	"prow_low": Vector2(290.0, 131.0),
	"prow_high": Vector2(295.5, 123.0),
	"round_muzzle": Vector2(261.25, 93.0)
}
# 对地激光轮流从侧臂长炮管和舰首下炮口射出；对空激光从舰首上炮口射出；大和炮从圆形炮口射出。
const GROUND_MUZZLES := ["wing_barrel", "prow_low"]
const AIR_MUZZLES := ["prow_high"]
var clock := 0.0
var poses: Dictionary = {}
var corpses: Array = []

func reset() -> void:
	clock = 0.0
	poses.clear()
	corpses.clear()

func update(delta: float) -> void:
	clock += delta
	corpses = corpses.filter(func(c): return clock - c.at < float(ENDS.death))

func observe(units: Array, prune_missing: bool = true) -> void:
	var living: Dictionary = {}
	for unit in units:
		if unit.kind != "battlecruiser":
			continue
		living[unit.id] = true
		if not poses.has(unit.id):
			poses[unit.id] = {"left":unit.team == 1,"fire_at":-10.0,"yamato_since":-10.0,"state":"idle","since":clock,"shots":0}
		var pose: Dictionary = poses[unit.id]
		var motion: Vector2 = unit.pos - unit.prev
		var moving := motion.length_squared() > 0.0001
		if moving and absf(motion.x) > 0.001 and clock - float(pose.fire_at) >= FIRE_HOLD:
			pose.left = motion.x < 0
		var next_state := "move" if moving else "idle"
		if clock - float(pose.fire_at) < FIRE_HOLD:
			next_state = "fire"
		# 引导开始时计时；引导中断（目标死亡）就取消。真正开炮由 yamato 事件把计时拨到 2.0 秒。
		var channeling: bool = unit.has("yamato_target")
		if channeling and not bool(pose.get("channel",false)):
			pose.yamato_since = clock
		elif not channeling and bool(pose.get("channel",false)):
			pose.yamato_since = -10.0
		pose.channel = channeling
		if channeling or clock - float(pose.yamato_since) < float(ENDS.yamato):
			next_state = "yamato"
		if pose.state != next_state:
			pose.state = next_state
			pose.since = pose.yamato_since if next_state == "yamato" else clock
	if prune_missing:
		for id in poses.keys():
			if not living.has(id):
				poses.erase(id)

## 攻击/大和炮事件没有攻击者 ID，按同队同兵种、发射位置匹配（与特战队员相同）。
## 匹配到后在事件里写入 muzzle 与 left，供特效从炮口画起。
func event(event_data: Dictionary, before: Dictionary, units: Array, revealed: bool) -> void:
	if event_data.type == "death" and before.has(event_data.id) and before[event_data.id].kind == "battlecruiser":
		var unit: Dictionary = before[event_data.id]
		if unit.team != 0 and not revealed:
			return
		corpses.append({"pos":event_data.pos,"left":bool(poses.get(unit.id,{}).get("left",unit.team == 1)),"at":clock})
		return
	if (event_data.type != "attack" and event_data.type != "yamato") or event_data.kind != "battlecruiser":
		return
	for unit in before.values():
		if unit.kind != "battlecruiser" or unit.team != event_data.team or not unit.pos.is_equal_approx(event_data.from) or not poses.has(unit.id):
			continue
		var pose: Dictionary = poses[unit.id]
		var dx: float = event_data.to.x - event_data.from.x
		if absf(dx) > 0.001:
			pose.left = dx < 0
		if event_data.type == "yamato":
			pose.yamato_since = clock - YAMATO_FIRE_AGE
			pose.state = "yamato"
			pose.since = pose.yamato_since
			event_data["muzzle"] = "round_muzzle"
		else:
			pose.fire_at = clock
			if pose.state != "fire" and pose.state != "yamato":
				pose.state = "fire"
				pose.since = clock
			# 换武器发生在同一步内，快照里的 weapon_index 可能是旧值，读步后的单位。
			var weapon_index := int(unit.get("weapon_index",0))
			for live in units:
				if live.id == unit.id:
					weapon_index = int(live.get("weapon_index",0))
					break
			var choices: Array = AIR_MUZZLES if weapon_index == 1 else GROUND_MUZZLES
			event_data["muzzle"] = choices[int(pose.shots) % choices.size()]
			pose.shots = int(pose.shots) + 1
		event_data["left"] = pose.left
		return

## 炮口相对单位中心的屏幕偏移；cell 是每格的屏幕像素。
func muzzle_offset(muzzle: String, left: bool, cell: float) -> Vector2:
	var offset: Vector2 = (MUZZLES[muzzle] - ANCHOR) * cell / PIXELS_PER_CELL
	return Vector2(-offset.x, offset.y) if left else offset

func frame_index(state: String, age: float) -> int:
	if STARTS.has(state):
		var frame := 0
		for i in range(STARTS[state].size()):
			if age >= float(STARTS[state][i]):
				frame = i
		return frame
	return int(maxf(0,age) * float(FPS[state])) % int(COUNTS[state])

func draw_frame(canvas: CanvasItem, point: Vector2, state: String, left: bool, age: float, cell: float, modulate := Color.WHITE) -> void:
	var scale := cell / PIXELS_PER_CELL
	var size := FRAME * scale
	var origin := point - ANCHOR * scale
	if left:
		# 负宽度让 Godot 水平翻转纹理，但矩形仍从 position 向右铺开；锚点按镜像位置计算。
		origin.x = point.x - (FRAME.x - ANCHOR.x) * scale
		size.x = -size.x
	var frame := frame_index(state, age)
	canvas.draw_texture_rect_region(TEXTURES[state],Rect2(origin,size),Rect2(frame*FRAME.x,0,FRAME.x,FRAME.y),modulate)

func draw_unit(canvas: CanvasItem, point: Vector2, unit: Dictionary, cell: float) -> void:
	var pose: Dictionary = poses.get(unit.id,{"state":"idle","left":unit.team == 1,"since":clock})
	var age: float = clock-float(pose.since)
	if bool(pose.get("channel",false)):
		age = minf(age,YAMATO_FIRE_AGE-0.01)
	draw_frame(canvas,point,pose.state,pose.left,age,cell)

## 残骸：4 帧约 1.1 秒播完，最后 0.3 秒淡出，1.4 秒消失。
func draw_corpse(canvas: CanvasItem, point: Vector2, corpse: Dictionary, cell: float) -> void:
	var age: float = clock-float(corpse.at)
	var fade := clampf((float(ENDS.death)-age)/0.3,0.0,1.0)
	draw_frame(canvas,point,"death",corpse.left,age,cell,Color(1,1,1,fade))
