extends RefCounted
## Mouse selection is separate from placement. Never issues live-unit orders.
const BOX_SLOP := 8.0
var button := 0
var start := Vector2.ZERO
var current := Vector2.ZERO
var double_click := false
var boxing := false

func cancel() -> void:
	button=0
	boxing=false
	double_click=false

func pointer(panel, event: InputEvent, point: Vector2) -> void:
	if event.is_canceled():
		panel.cancel_drag()
		return
	if event is InputEventMouseButton:
		if event.pressed:
			if button!=0:
				panel.cancel_drag()
				return
			if event.button_index not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT] or not panel._field().has_point(point):return
			start=point
			current=point
			double_click=event.double_click
			button=event.button_index
			if button==MOUSE_BUTTON_RIGHT:panel.begin_placement(point,false)
		elif event.button_index==button:
			if not panel._field().has_point(point):
				panel.cancel_drag()
				return
			if button==MOUSE_BUTTON_RIGHT:panel.finish_placement(point,false)
			else:
				var members: Array=panel.game.sim.deployment_members(0)
				var chosen: Array=[]
				if boxing or start.distance_to(point)>=BOX_SLOP:
					var area:=Rect2(start,point-start).abs()
					chosen=members.filter(func(m):return area.has_point(panel._to_screen(m.position)))
					var troops: Array=chosen.filter(func(m):return not bool(panel.game.sim.catalog[m.kind].get("structure",false)))
					if not troops.is_empty():chosen=troops
				else:
					var hit: Dictionary=panel._hit_member(point,members)
					if not hit.is_empty():
						chosen=members.filter(func(m):return str(m.kind)==str(hit.kind)) if double_click else [hit]
				panel.select_members(chosen)
			cancel()
	elif event is InputEventMouseMotion and button!=0:
		current=point
		if button==MOUSE_BUTTON_LEFT:boxing=boxing or start.distance_to(point)>=BOX_SLOP
		else:panel.move_placement(point)

func draw(panel) -> void:
	if button!=MOUSE_BUTTON_LEFT or not boxing:return
	var rect:=Rect2(start,current-start).abs().intersection(panel._field())
	panel.game.draw_rect(rect,Color(panel.game.MINT,0.12))
	panel.game.draw_rect(rect,panel.game.MINT,false,1.5)
