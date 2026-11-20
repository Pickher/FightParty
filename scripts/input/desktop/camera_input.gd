extends RefCounted
## Frame-time camera velocity, in design pixels/second. No unit commands.
const SPEED := 620.0
const ACCEL := 10.0
const DECEL := 8.0
var held: Dictionary={}
var velocity := Vector2.ZERO

func cancel() -> void:
	held.clear()
	velocity=Vector2.ZERO

func key(event: InputEventKey, allowed: bool) -> bool:
	var code: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
	if code not in [KEY_W,KEY_A,KEY_S,KEY_D]:return false
	if not allowed or event.is_canceled() or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		cancel()
		return true
	if event.pressed:
		if not event.echo:held[code]=true
	else:held.erase(code)
	return true

func update(game, delta: float, allowed: bool) -> void:
	if not allowed:
		cancel()
		return
	var direction:=Vector2(float(held.has(KEY_D))-float(held.has(KEY_A)),float(held.has(KEY_S))-float(held.has(KEY_W))).normalized()
	var desired: Vector2=direction*SPEED
	var dt: float=clampf(delta,0,0.1)
	var rate: float=DECEL if direction==Vector2.ZERO else ACCEL
	# Exact exponential integral keeps travel consistent across different frame rates.
	var decay: float=exp(-rate*dt)
	var travel: Vector2=desired*dt+(velocity-desired)*(1.0-decay)/rate
	velocity=desired+(velocity-desired)*decay
	if desired==Vector2.ZERO and velocity.length()<0.5:velocity=Vector2.ZERO
	if travel.length_squared()<0.000001:return
	game.camera_follow=false
	var before: Vector2=game._camera_rect().get_center()
	game.camera_center=before+travel/maxf(game._camera_scale(),0.001)
	var actual: Vector2=game._camera_rect().get_center()
	game.camera_center=actual
	for axis in range(2):
		if absf(actual[axis]-before[axis])<0.00001 and absf(travel[axis])>0.00001:velocity[axis]=0
