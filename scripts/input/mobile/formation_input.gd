extends RefCounted
## Raw touch -> existing tap/held-line intent. Synthetic mouse is rejected by main.
var fingers: Dictionary={}
var active := -1
var blocked := false

func cancel() -> void:
	fingers.clear()
	active=-1
	blocked=false

func adapt(game, event: InputEvent) -> InputEvent:
	if event is InputEventScreenTouch:
		if event.is_canceled():
			game._reset_pointer()
			return null
		if event.pressed:
			fingers[event.index]=true
			if active!=-1:
				blocked=true
				game.formation_panel.cancel_placement()
				game.battle_dragging=false
				game.minimap_dragging=false
				return null
			active=event.index
		else:fingers.erase(event.index)
		if blocked:
			if fingers.is_empty():cancel()
			return null
		if event.index!=active:return null
		var mouse=InputEventMouseButton.new()
		mouse.position=event.position
		mouse.button_index=MOUSE_BUTTON_LEFT
		mouse.pressed=event.pressed
		mouse.set_meta("touch_origin",true)
		if not event.pressed:active=-1
		return mouse
	if event is InputEventScreenDrag and not blocked and event.index==active:
		var mouse=InputEventMouseMotion.new()
		mouse.position=event.position
		mouse.relative=event.relative
		mouse.set_meta("touch_origin",true)
		return mouse
	return null

func pointer(panel, event: InputEvent, point: Vector2) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:panel.begin_placement(point,true)
		else:panel.finish_placement(point,true)
	elif event is InputEventMouseMotion:panel.move_placement(point)
