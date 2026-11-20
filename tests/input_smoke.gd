## Optional input regression fixture. Added but NOT executed with this patch.
extends SceneTree
const Mouse = preload("res://scripts/input/desktop/formation_input.gd")
const Touch = preload("res://scripts/input/mobile/formation_input.gd")
const Camera = preload("res://scripts/input/desktop/camera_input.gd")
var failures := 0
class FakeSim:
	extends RefCounted
	var catalog := {"a":{"structure":false},"b":{"structure":false},"tower":{"structure":true}}
	var members: Array=[{"cell":0,"member":0,"kind":"a","position":Vector2(20,20)}, {"cell":1,"member":0,"kind":"a","position":Vector2(40,20)}, {"cell":2,"member":0,"kind":"b","position":Vector2(60,20)}, {"cell":3,"member":0,"kind":"tower","position":Vector2(80,20)}]
	func deployment_members(_team: int) -> Array:return members
class FakeGame:
	extends RefCounted
	var sim=FakeSim.new()
	var camera_follow := true
	var camera_center := Vector2(5000,5000)
	func _camera_scale() -> float:return 1.0
	func _camera_rect() -> Rect2:return Rect2(camera_center.clamp(Vector2(50,50),Vector2(9950,9950))-Vector2(50,50),Vector2(100,100))
class TouchGame:
	extends RefCounted
	var formation_panel=FakePanel.new()
	var mobile_input=Touch.new()
	var battle_dragging := true
	var minimap_dragging := true
	func _reset_pointer() -> void:mobile_input.cancel()
class FakePanel:
	extends RefCounted
	var game=FakeGame.new()
	var input=Mouse.new()
	var chosen: Array=[]
	var begins := 0
	var commits := 0
	func _field() -> Rect2:return Rect2(0,0,100,100)
	func _to_screen(p: Vector2) -> Vector2:return p
	func _hit_member(p: Vector2, members: Array) -> Dictionary:
		for m in members:
			if m.position.distance_to(p)<5:return m
		return {}
	func cancel_placement() -> void:pass
	func cancel_drag() -> void:input.cancel()
	func select_members(value: Array) -> void:chosen=value
	func begin_placement(_p: Vector2, _touch: bool) -> void:begins+=1
	func move_placement(_p: Vector2) -> void:pass
	func finish_placement(_p: Vector2, _touch: bool) -> void:commits+=1
func check(ok: bool, label: String) -> void:
	if not ok:
		failures+=1
		printerr("FAIL: "+label)
func button(panel, which: int, down: bool, p: Vector2, double: bool=false) -> void:
	var e=InputEventMouseButton.new()
	e.button_index=which
	e.pressed=down
	e.double_click=double
	panel.input.pointer(panel,e,p)
func touch(index: int, down: bool) -> InputEventScreenTouch:
	var e=InputEventScreenTouch.new()
	e.index=index
	e.pressed=down
	return e
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var p=FakePanel.new()
	button(p,MOUSE_BUTTON_LEFT,true,Vector2(20,20))
	button(p,MOUSE_BUTTON_LEFT,false,Vector2(20,20))
	check(p.chosen.size()==1 and p.begins==0 and p.commits==0,"single selects exactly one without placement")
	button(p,MOUSE_BUTTON_LEFT,true,Vector2(20,20),true)
	button(p,MOUSE_BUTTON_LEFT,false,Vector2(20,20))
	check(p.chosen.size()==2,"double selects same kind across purchased cells")
	button(p,MOUSE_BUTTON_LEFT,true,Vector2(5,5))
	button(p,MOUSE_BUTTON_LEFT,false,Vector2(95,40))
	check(p.chosen.size()==3,"box release without motion events; mixed structures excluded")
	button(p,MOUSE_BUTTON_LEFT,true,Vector2(70,5))
	button(p,MOUSE_BUTTON_LEFT,false,Vector2(95,40))
	check(p.chosen.size()==1 and p.chosen[0].kind=="tower","structure-only remains visually selectable")
	button(p,MOUSE_BUTTON_RIGHT,false,Vector2(30,40))
	check(p.commits==0,"unmatched release ignored")
	button(p,MOUSE_BUTTON_RIGHT,true,Vector2(30,40))
	button(p,MOUSE_BUTTON_RIGHT,false,Vector2(30,40))
	check(p.begins==1 and p.commits==1,"right press/release shared placement exactly once")
	button(p,MOUSE_BUTTON_RIGHT,true,Vector2(30,40))
	p.cancel_drag()
	button(p,MOUSE_BUTTON_RIGHT,false,Vector2(30,40))
	check(p.commits==1,"cancel drops stale release")
	button(p,MOUSE_BUTTON_RIGHT,true,Vector2(30,40))
	button(p,MOUSE_BUTTON_RIGHT,false,Vector2(120,40))
	check(p.commits==1,"outside release cancels")
	var tg=TouchGame.new()
	check(tg.mobile_input.adapt(tg,touch(0,true))!=null,"first finger owns touch")
	check(tg.mobile_input.adapt(tg,touch(1,true))==null and not tg.minimap_dragging,"second finger cancels navigation")
	check(tg.mobile_input.adapt(tg,touch(0,false))==null,"first lift after multi-touch cannot submit")
	check(tg.mobile_input.adapt(tg,touch(1,false))==null and tg.mobile_input.active==-1,"all fingers up clears blocked state")
	check(tg.mobile_input.adapt(tg,touch(2,true))!=null,"fresh touch works after cancellation")
	tg._reset_pointer()
	check(tg.mobile_input.adapt(tg,touch(2,false))==null,"lifecycle drops stale touch release")
	var c30=Camera.new()
	var c60=Camera.new()
	var g30=FakeGame.new()
	var g60=FakeGame.new()
	c30.held[KEY_D]=true
	c60.held[KEY_D]=true
	for i in range(30):c30.update(g30,1.0/30.0,true)
	for i in range(60):c60.update(g60,1.0/60.0,true)
	check(g30.camera_center.distance_to(g60.camera_center)<0.01,"time-integrated camera travel independent of frame rate")
	var speed: float=c30.velocity.length()
	c30.held.clear()
	c30.update(g30,0.05,true)
	check(c30.velocity.length()<speed and c30.velocity.length()>0,"keyup eases down")
	c30.update(g30,0.05,false)
	check(c30.velocity==Vector2.ZERO and c30.held.is_empty(),"modal cancels velocity and keys")
	g60.camera_center=Vector2(9950,5000)
	c60.update(g60,0.05,true)
	check(g60.camera_center.x==9950 and c60.velocity.x==0,"boundary clamps and stops outward inertia")
	quit(1 if failures else 0)
