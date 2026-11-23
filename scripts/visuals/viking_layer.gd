extends "res://scripts/visuals/tracked_projectile_layer.gd"

const Actor = preload("res://scripts/visuals/viking_actor.gd")
const Ordnance = preload("res://scripts/visuals/viking_ordnance.gd")
const MODEL_PATH := Actor.RIG_PATH
const MODE := "anti_air_missile"
const GROUND_LEAD := 0.30
const TAKEOFF_TIME := 1.20

func _init() -> void:
	super("viking", MODE, "air", Actor, Ordnance, 2.5)

func _sample_form(entry: Dictionary, unit: Dictionary, sim, time: float) -> void:
	# Birth is the native spawn tick. Older snapshots may omit it; those are already airborne.
	var flight := 1.0
	if unit.has("born"):
		var tick_rate := float(sim.rules.tick_rate)
		var age := minf(time, float(sim.tick) / tick_rate) - float(unit.born) / tick_rate
		flight = clampf((age - GROUND_LEAD) / TAKEOFF_TIME, 0.0, 1.0)
	if not is_equal_approx(entry.actor.flight_progress, flight):
		entry.actor.set_flight_progress(flight)
	entry.height = lerpf(-100.0, 0.0, flight)

func _socket(actor: Node3D, side: int) -> Transform2D:
	var bore: Vector3 = actor.muzzle_direction_world(MODE, side)
	return Transform2D(Vector2(bore.x, bore.z).angle(), actor.muzzle_screen_offset(MODE, side))

func _fire_actor(actor: Node3D, offset: Vector2, age: float, side: int) -> void:
	actor.fire_at(MODE, offset, age, side)
