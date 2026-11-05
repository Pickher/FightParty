# Presentation only: observes units/events, never writes simulation state.
extends RefCounted
const TEXTURES := {
	"idle": preload("res://assets/units/rifle/idle.png"),
	"move": preload("res://assets/units/rifle/move.png"),
	"fire": preload("res://assets/units/rifle/fire.png"),
	"death": preload("res://assets/units/rifle/death.png")
}
const COUNTS := {"idle":6, "move":8, "fire":4, "death":8}
const FPS := {"idle":6.0, "move":12.0, "fire":16.0, "death":10.0}
var clock := 0.0
var poses: Dictionary = {}
var corpses: Array = []

func reset() -> void:
	clock = 0.0
	poses.clear()
	corpses.clear()

func update(delta: float) -> void:
	clock += delta
	corpses = corpses.filter(func(c): return clock - c.at < 0.8)

func observe(units: Array) -> void:
	var living: Dictionary = {}
	for unit in units:
		if unit.kind != "rifle":
			continue
		living[unit.id] = true
		if not poses.has(unit.id):
			poses[unit.id] = {"direction":0 if unit.team == 0 else 4,"fire_at":-10.0,"state":"idle","since":clock}
		var pose: Dictionary = poses[unit.id]
		var motion: Vector2 = unit.pos - unit.prev
		if motion.length_squared() > 0.0001 and clock - float(pose.fire_at) >= 0.25:
			pose.direction = direction(motion)
		var next_state := "move" if motion.length_squared() > 0.0001 else "idle"
		if clock - float(pose.fire_at) < 0.25:
			next_state = "fire"
		if pose.state != next_state:
			pose.state = next_state
			pose.since = clock
	for id in poses.keys():
		if not living.has(id):
			poses.erase(id)

func direction(vector: Vector2) -> int:
	return posmod(roundi(vector.angle() / (PI / 4.0)),8)

func event(event_data: Dictionary, before: Dictionary, units: Array, revealed: bool) -> void:
	if event_data.type == "death" and before.has(event_data.id):
		var unit: Dictionary = before[event_data.id]
		if unit.team != 0 and not revealed:
			return
		corpses.append({"pos":event_data.pos,"direction":poses.get(unit.id,{}).get("direction",0 if unit.team == 0 else 4),"at":clock})
	if event_data.type == "attack" and event_data.kind == "rifle":
		# Existing attack events have no attacker ID. Match same-team source position.
		for unit in units:
			if unit.kind == "rifle" and unit.team == event_data.team and unit.pos.is_equal_approx(event_data.from) and poses.has(unit.id):
				var pose: Dictionary = poses[unit.id]
				pose.direction = direction(event_data.to - event_data.from)
				pose.fire_at = clock
				pose.state = "fire"
				pose.since = clock
				break

func draw_frame(canvas: CanvasItem, point: Vector2, state: String, facing: int, age: float, size := 36.0) -> void:
	var frame := int(maxf(0,age) * float(FPS[state]))
	if state == "idle" or state == "move":
		frame = frame % int(COUNTS[state])
	else:
		frame = mini(frame,int(COUNTS[state])-1)
	canvas.draw_texture_rect_region(TEXTURES[state],Rect2(point-Vector2.ONE*size*0.5,Vector2.ONE*size),Rect2(frame*64,facing*64,64,64))

func draw_unit(canvas: CanvasItem, point: Vector2, unit: Dictionary) -> void:
	var pose: Dictionary = poses.get(unit.id,{"state":"idle","direction":0 if unit.team == 0 else 4,"since":clock})
	draw_frame(canvas,point,pose.state,pose.direction,clock-float(pose.since))
