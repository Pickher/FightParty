## Optional render-state smoke, never run automatically by this change.
## Requires Godot resource import; does not validate actual GPU output or execute a battle.
extends SceneTree
const Visual = preload("res://scripts/visuals/medivac_3d.gd")
var failures := 0
class FakeGame:
	extends RefCounted
	var started := true
	var paused := false
	var backgrounded := false
	var help_open := false
	var economy_open := false
	var setup_open := false
	var formation_panel := {"opened":false}
	var accumulator := 0.025
	var CORAL := Color("ff7777")
	var hidden := true
	var sim := {"units":[],"active_beams":[],"by_id":{},"rules":{"tick_rate":20},"catalog":{"medivac":{"size":[1.6,1.6]}}}
	func _hidden_team(team: int) -> bool:return team==1 and hidden
	func _camera_rect() -> Rect2:return Rect2(0,0,100,50)
class FakeView:
	extends RefCounted
	func viewport_size() -> Vector2:return Vector2(800,400)
	func point(p: Vector2) -> Vector2:return p*8
	func pixels(value: float) -> float:return value*8
func check(ok: bool, label: String) -> void:
	if not ok:
		failures+=1
		printerr("FAIL: "+label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=FakeGame.new()
	var view=FakeView.new()
	var visual=Visual.new()
	visual.game=game
	root.add_child(visual)
	if not visual.ready_model:
		printerr("3D resource unavailable; fallback active, model assertions not verified")
		quit(1)
		return
	var craft: Dictionary={"id":1,"kind":"medivac","team":0,"prev":Vector2(20,20),"pos":Vector2(21,20)}
	var secret: Dictionary={"id":2,"kind":"medivac","team":1,"prev":Vector2(30,20),"pos":Vector2(30,20)}
	game.sim.units=[craft,secret]
	visual.sync(view,0.016)
	check(visual.has_model(1) and not visual.has_model(2),"hidden enemy never instanced")
	check(is_equal_approx(visual.entries[1].root.position.x,164),"model uses same interpolation and viewport coordinates")
	check(visual.viewport.size==Vector2i(800,400),"one shared target tracks battle dimensions")
	var old_clock: float=visual.clock
	game.paused=true
	visual.sync(view,0.08)
	check(visual.clock==old_clock,"pause freezes animation clock")
	game.paused=false
	game.formation_panel.opened=true
	visual.sync(view,0.08)
	check(visual.clock>old_clock,"formation panel leaves animation clock running")
	game.formation_panel.opened=false
	var beam: Dictionary={"source_id":1,"target_id":3,"healing":true,"team":0,"from":craft.pos,"to":Vector2(25,20)}
	game.sim.active_beams=[beam]
	visual.sync(view,0.016)
	check(visual.entries[1].lamp.visible and visual.owns_heal(beam),"healing lamp/ownership follows real active beam list")
	game.sim.active_beams=[]
	visual.sync(view,0.016)
	check(not visual.entries[1].lamp.visible,"no independent healing timer")
	var before: Dictionary=visual.before_tick()
	game.sim.units=[]
	visual.events([{"type":"death","id":1,"pos":craft.pos,"team":0}],before)
	check(visual.entries[1].dead and visual.bursts.size()==1,"death event uses kind snapshot and begins bounded wreck")
	visual.reset()
	check(visual.entries.is_empty() and visual.bursts.is_empty() and visual.clock==0,"restart clears all cached IDs and effects")
	game.sim.units=[craft]
	visual.sync(view,0.016)
	check(visual.has_model(1) and not visual.entries[1].dead,"reused unit ID has fresh live pose")
	game.sim.units=[]
	for i in range(40):game.sim.units.append({"id":i+10,"kind":"medivac","team":0,"prev":Vector2(20,20),"pos":Vector2(20,20)})
	visual.sync(view,0.016)
	check(visual.entries.size()<=Visual.MAX_LIVE and not visual.has_model(49),"3D overflow remains available to 2D fallback")
	visual.reset()
	visual.queue_free()
	quit(1 if failures>0 else 0)
