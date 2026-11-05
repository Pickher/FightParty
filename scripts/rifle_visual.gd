# Presentation only: observes units/events, never writes simulation state.
extends RefCounted
const TEXTURES := {
	"idle": preload("res://assets/units/rifle/idle.png"),
	"move": preload("res://assets/units/rifle/move.png"),
	"fire": preload("res://assets/units/rifle/fire.png"),
	"death": preload("res://assets/units/rifle/death.png")
}
const COUNTS := {"idle":6, "move":8, "fire":8, "death":16}
const FPS := {"idle":6.0, "move":12.0, "fire":24.0, "death":16.0}
var clock := 0.0
var poses: Dictionary = {}
var corpses: Array = []

func reset() -> void:
	clock = 0.0
	poses.clear()
	corpses.clear()

func update(delta: float) -> void:
	clock += delta
	corpses = corpses.filter(func(c): return clock - c.at < 1.4)

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
		if motion.length_squared() > 0.0001 and clock - float(pose.fire_at) >= 0.66:
			pose.direction = direction(motion)
		var next_state := "move" if motion.length_squared() > 0.0001 else "idle"
		if clock - float(pose.fire_at) < 0.66 and motion.length_squared() <= 0.0001:
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
	if event_data.type == "attack":
		for victim in before.values():
			if victim.team != event_data.team and victim.pos.distance_to(event_data.to) < 8.0 and poses.has(victim.id):
				poses[victim.id]["impact"] = (event_data.to-event_data.from).normalized()
	if event_data.type == "death" and before.has(event_data.id):
		var unit: Dictionary = before[event_data.id]
		if unit.team != 0 and not revealed:
			return
		var pose: Dictionary = poses.get(unit.id,{})
		var facing := int(pose.get("direction",0 if unit.team == 0 else 4))
		var impulse: Vector2 = pose.get("impact",-Vector2.from_angle(facing*PI/4.0))
		corpses.append({"pos":event_data.pos,"direction":poses.get(unit.id,{}).get("direction",0 if unit.team == 0 else 4),"at":clock,"impulse":impulse})
	if event_data.type == "attack" and event_data.kind == "rifle":
		# Existing attack events have no attacker ID. Match same-team source position.
		for unit in units:
			if unit.kind == "rifle" and unit.team == event_data.team and unit.pos.is_equal_approx(event_data.from) and poses.has(unit.id):
				var pose: Dictionary = poses[unit.id]
				pose.direction = direction(event_data.to - event_data.from)
				pose.fire_at = clock
				if pose.state != "fire":
					pose.since = clock
				pose.state = "fire"
				break

func draw_frame(canvas: CanvasItem, point: Vector2, state: String, facing: int, age: float, size := 36.0) -> void:
	var frame := int(maxf(0,age) * float(FPS[state]))
	if state == "idle" or state == "move" or state == "fire":
		frame = frame % int(COUNTS[state])
	else:
		frame = mini(frame,int(COUNTS[state])-1)
	canvas.draw_texture_rect_region(TEXTURES[state],Rect2(point-Vector2.ONE*size*0.5,Vector2.ONE*size),Rect2(frame*64,facing*64,64,64))

func draw_unit(canvas: CanvasItem, point: Vector2, unit: Dictionary) -> void:
	var pose: Dictionary = poses.get(unit.id,{"state":"idle","direction":0 if unit.team == 0 else 4,"since":clock})
	draw_frame(canvas,point,pose.state,pose.direction,clock-float(pose.since))

func draw_corpse(canvas: CanvasItem, point: Vector2, corpse: Dictionary) -> void:
	var age: float = clock-float(corpse.at)
	var progress := clampf(age/0.72,0.0,1.0)
	var offset: Vector2 = corpse.impulse * 32.0 * (1.0-pow(1.0-progress,2))
	canvas.draw_circle(point+offset+Vector2(0,4),7.0,Color(0.02,0.03,0.04,0.3))
	draw_frame(canvas,point+offset,"death",corpse.direction,age)
