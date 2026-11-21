extends RefCounted
## 折叠式部队面板。只编辑下一波已有士兵的位置，购买仍交给 BattleSim。
const Catalog = preload("res://scripts/catalog.gd")
const DesktopInput = preload("res://scripts/input/desktop/formation_input.gd")
const Layout = preload("res://scripts/formation_layout.gd")
const PANEL := Rect2(32,98,1376,762)
const BOARD_AREA := Rect2(446,244,930,530)
const ROWS_PER_PAGE := 8
const LINE_HOLD_MS := 300
const LINE_MIN_DISTANCE := 24.0
const MEMBER_TAP_SLOP := 8.0
var desktop_input=DesktopInput.new()
var explicit_selection := false
var selection_keys: Dictionary={}
var line_active := false
var pressed_at_ms := 0
var pointer_point := Vector2.ZERO
var preview_point := Vector2.ZERO
var game
var opened := false
var tab := "owned"
var selected_kind := ""
var batch_count := 1
var selection_offset := 0
var list_page := 0
var dragging := false
var drag_start := Vector2.ZERO
var drag_end := Vector2.ZERO
var pressed_point := Vector2.ZERO
var pressed_member := false
var placement_touch := false
var preview: Dictionary = {"placements":[],"error":""}
var drag_selection: Array = []
var notice := "电脑：左键选择，右键放置；触屏：点放或长按拖线。仅影响下一波。"
var notice_bad := false

func reset() -> void:
	opened=false
	explicit_selection=false
	selection_keys.clear()
	tab="owned"
	selected_kind=""
	batch_count=1
	selection_offset=0
	list_page=0
	cancel_drag()
	notice="电脑：左键选择，右键放置；触屏：点放或长按拖线。仅影响下一波。"
	notice_bad=false

func clear_explicit_selection() -> void:
	explicit_selection=false
	selection_keys.clear()

func open_panel() -> void:
	clear_explicit_selection()
	opened=true
	cancel_drag()
	_ensure_selection()
	game.queue_redraw()

func close_panel() -> void:
	clear_explicit_selection()
	opened=false
	cancel_drag()
	game.queue_redraw()

func cancel_drag() -> void:
	desktop_input.cancel()
	cancel_placement()

func cancel_placement() -> void:
	line_active=false
	dragging=false
	pressed_member=false
	drag_selection=[]
	preview={"placements":[],"error":""}

func _bounds() -> Rect2:
	return game.sim.deployment_bounds()

func _field() -> Rect2:
	var bounds: Rect2 = _bounds()
	var scale: float = minf(BOARD_AREA.size.x/bounds.size.x,BOARD_AREA.size.y/bounds.size.y)
	return Rect2(BOARD_AREA.get_center()-bounds.size*scale*0.5,bounds.size*scale)

func _to_screen(position: Vector2) -> Vector2:
	var bounds: Rect2 = _bounds()
	var field: Rect2 = _field()
	return field.position+(position-bounds.position)*field.size/bounds.size

func _to_local(position: Vector2) -> Vector2:
	var bounds: Rect2 = _bounds()
	var field: Rect2 = _field()
	return bounds.position+(position-field.position)*bounds.size/field.size

func _key(member: Dictionary) -> String:
	return "%d:%d" % [int(member.cell),int(member.member)]

func _counts() -> Dictionary:
	var result: Dictionary = {}
	for slot in game.sim.formations[0]:
		var kind: String = str(slot.kind)
		result[kind]=int(result.get(kind,0))+1
	return result

func _kinds() -> Array:
	var available: Array = Catalog.race_units(game.sim.catalog,str(game.sim.races[0]))
	if tab=="recruit":return available
	var counts: Dictionary = _counts()
	var result: Array = []
	for kind in available:
		if counts.has(kind):result.append(kind)
	return result

func _ensure_selection() -> void:
	var kinds: Array = _kinds()
	list_page=clampi(list_page,0,maxi(0,ceili(float(kinds.size())/ROWS_PER_PAGE)-1))
	if not kinds.has(selected_kind):
		selected_kind=str(kinds[0]) if not kinds.is_empty() else ""
		selection_offset=0
		batch_count=1

func _pool(members: Array) -> Array:
	var result: Array = []
	for member in members:
		if str(member.kind)==selected_kind:result.append(member)
	return result

func _selection(members: Array) -> Array:
	if explicit_selection:return members.filter(func(m):return selection_keys.has(_key(m)))
	var pool: Array = _pool(members)
	if pool.is_empty():return []
	selection_offset=clampi(selection_offset,0,pool.size()-1)
	var count: int = mini(maxi(1,batch_count),pool.size()-selection_offset)
	return pool.slice(selection_offset,selection_offset+count)

func _select_kind(kind: String) -> void:
	explicit_selection=false
	selection_keys.clear()
	if kind!=selected_kind:
		selected_kind=kind
		batch_count=1
		selection_offset=0
	var index: int = _kinds().find(kind)
	if index>=0:list_page=index/ROWS_PER_PAGE
	cancel_drag()

func _next_batch(members: Array) -> void:
	clear_explicit_selection()
	var pool: Array = _pool(members)
	if pool.is_empty():return
	selection_offset=(selection_offset+_selection(members).size())%pool.size()

func _message(text: String, bad: bool = false) -> void:
	notice=text
	notice_bad=bad
	game._note(text)
	game.queue_redraw()

func draw() -> void:
	if not opened:return
	_ensure_selection()
	var members: Array = game.sim.deployment_members(0)
	var selected: Array = drag_selection if dragging else _selection(members)
	game.draw_rect(Rect2(0,98,1440,762),Color("091321"))
	game._panel(PANEL,game.PANEL,game.MINT)
	# 此面板独占输入，不留下被遮住的布阵格和战场工具栏按钮。
	game.buttons.clear()
	game._text(Vector2(56,137),"部队配置",27,game.MINT)
	if selected_kind == "adept":
		var tactic: String = game.sim.adept_tactics[0]
		game._text(Vector2(222,135),"下一波使徒战术",18,game.MUTED)
		game._button(Rect2(426,109,160,42),"后撤传送","formation:adept_tactic:retreat",tactic=="retreat")
		game._button(Rect2(600,109,160,42),"支援传送","formation:adept_tactic:support",tactic=="support")
	else:
		game._text(Vector2(222,135),"已暂停 · 调整下一波，不指挥场上部队",18,game.MUTED)
	game._button(Rect2(1024,109,152,42),"格阵管理","formation:legacy")
	game._button(Rect2(1190,109,186,42),"收起，返回战场","formation:close",true)
	game._button(Rect2(56,166,170,46),"现有部队","formation:tab:owned",tab=="owned")
	game._button(Rect2(238,166,170,46),"招募部队","formation:tab:recruit",tab=="recruit")
	_draw_list()
	_draw_tools(selected,members)
	_draw_board(members,selected)
	desktop_input.draw(self)
	var info: String = str(preview.get("error","")) if dragging and not str(preview.get("error","")).is_empty() else notice
	var bad: bool = not str(preview.get("error","")).is_empty() if dragging else notice_bad
	if dragging and str(preview.get("error","")).is_empty():info="松手布置 %d 名；拖出方框或 Esc 取消。" % drag_selection.size()
	game.draw_multiline_string(game.FONT,Vector2(446,803),info,HORIZONTAL_ALIGNMENT_LEFT,930,18,2,game.CORAL if bad else game.MINT)
	game._text(Vector2(446,846),"电脑：左键单选/双击同类/框选，右键点放或长按拖线；触屏沿用点放/拖线",16,game.MUTED)

func _draw_list() -> void:
	var kinds: Array = _kinds()
	var counts: Dictionary = _counts()
	var pages: int = maxi(1,ceili(float(kinds.size())/ROWS_PER_PAGE))
	for row in range(ROWS_PER_PAGE):
		var index: int = list_page*ROWS_PER_PAGE+row
		if index>=kinds.size():break
		var kind: String = str(kinds[index])
		var stats: Dictionary = game.sim.catalog[kind]
		var groups: int = int(counts.get(kind,0))
		var count: int = groups*maxi(1,int(stats.get("spawn_count",1)))
		var rect := Rect2(56,226+row*60,352,54)
		game._panel(rect,Color("204b43") if selected_kind==kind else Color("17293c"),game.MINT if selected_kind==kind else Color("304358"),6)
		game._draw_unit(rect.position+Vector2(24,26),kind,Color(stats.color),10)
		game._text(rect.position+Vector2(46,23),str(stats.name),19,game.INK)
		game._text(rect.position+Vector2(46,44),"已有 %d 组 · %d 名" % [groups,count],15,game.MUTED)
		if tab=="recruit":
			game._text(rect.position+Vector2(233,23),"%d矿/组" % int(stats.cost),15,game.MINT)
			var gas: int = int(stats.get("gas_cost",0))
			var cores: int = int(stats.get("core_cost",0))
			if gas>0 or cores>0:game._text(rect.position+Vector2(233,44),"%d气 %d核" % [gas,cores],14,game.MUTED)
		game.buttons.append({"rect":rect,"action":"formation:kind:"+kind})
	if kinds.is_empty():
		game._text(Vector2(74,268),"还没有已购买的部队",20,game.MUTED)
		game._text(Vector2(74,305),"点击「招募部队」购买一组。",17,game.MINT)
	game._button(Rect2(56,718,96,40),"上一页","formation:page:-1")
	game._text(Vector2(174,746),"%d / %d" % [list_page+1,pages],18,game.MUTED)
	game._button(Rect2(312,718,96,40),"下一页","formation:page:1")
	if tab=="recruit" and not selected_kind.is_empty():
		var stats: Dictionary = game.sim.catalog[selected_kind]
		game._button(Rect2(56,774,352,50),"招募一组（%d 名）" % maxi(1,int(stats.get("spawn_count",1))),"formation:buy",true)
		game._text(Vector2(56,848),"按组购买；单兵排布不会另行扣费。",16,game.MUTED)
	else:
		game._text(Vector2(56,797),"组数与人数按当前兵种配置显示。",16,game.MUTED)
		game._text(Vector2(56,823),"删除/退款请进入「格阵管理」。",16,game.MUTED)

func _draw_tools(selected: Array, members: Array) -> void:
	var pool: Array = _pool(members)
	game._button(Rect2(446,166,70,44),"1名","formation:count:one",selected.size()==1)
	game._button(Rect2(526,166,90,44),"一组","formation:count:group")
	game._button(Rect2(626,166,90,44),"全部","formation:count:all")
	game._button(Rect2(730,166,44,44),"−","formation:count:minus")
	game._text(Vector2(786,195),str(selected.size()),21,game.INK)
	game._button(Rect2(852,166,44,44),"+","formation:count:plus")
	game._button(Rect2(910,166,104,44),"下一批","formation:next")
	game._button(Rect2(1028,166,170,44),"一键自动排布","formation:auto",true)
	game._button(Rect2(1212,166,164,44),"取消本次拖线","formation:cancel")
	var label: String = str(game.sim.catalog[selected_kind].name) if game.sim.catalog.has(selected_kind) else "未选兵种"
	if explicit_selection:label="已选部队"
	game._text(Vector2(446,233),"%s · 本批 %d 名 / 共 %d 名 · 按住拖线可排成多列" % [label,selected.size(),members.size() if explicit_selection else pool.size()],17,game.MUTED)

func _draw_board(members: Array, selected: Array) -> void:
	var field: Rect2 = _field()
	var bounds: Rect2 = _bounds()
	var scale: float = field.size.x/bounds.size.x
	game.draw_rect(BOARD_AREA,Color("091725"))
	game.draw_rect(field,Color("102c32"))
	game.draw_rect(field,Color("47726f"),false,2)
	for x in range(ceili(bounds.position.x),floori(bounds.end.x)+1,2):
		var point: Vector2 = _to_screen(Vector2(float(x),bounds.position.y))
		game.draw_line(point,point+Vector2(0,field.size.y),Color("1d4047"),1)
	for y in range(ceili(bounds.position.y),floori(bounds.end.y)+1,2):
		var point: Vector2 = _to_screen(Vector2(bounds.position.x,float(y)))
		game.draw_line(point,point+Vector2(field.size.x,0),Color("1d4047"),1)
	game._text(Vector2(458,280),"后方",19,game.MUTED)
	game._text(Vector2(1275,280),"前线 →",19,game.MINT)
	var chosen: Dictionary = {}
	for member in selected:chosen[_key(member)]=true
	for member in members:
		var point: Vector2 = _to_screen(member.position)
		var kind: String = str(member.kind)
		var radius: float = maxf(3,float(member.radius)*scale)
		var color: Color = Color(game.sim.catalog[kind].color)
		game.draw_circle(point,radius,Color(color,0.17))
		game._draw_unit(point,kind,color,maxf(3,radius*0.6))
		game.draw_arc(point,radius+2,0,TAU,16,game.MINT if chosen.has(_key(member)) else Color(color,0.5),2 if chosen.has(_key(member)) else 1)
	if line_active:
		var tint: Color = game.MINT if str(preview.get("error","")).is_empty() else game.CORAL
		var end_point: Vector2 = _to_screen(drag_end).clamp(field.position,field.end)
		game.draw_line(_to_screen(drag_start),end_point,tint,2)
		game.draw_circle(_to_screen(drag_start),4,tint)
		game.draw_circle(end_point,4,tint)
		for placement in preview.get("placements",[]):
			var value: Array = placement.position
			var point: Vector2 = _to_screen(Vector2(float(value[0]),float(value[1])))
			if field.has_point(point):game.draw_circle(point,5,tint)

func _hit_member(point: Vector2, members: Array) -> Dictionary:
	var best: Dictionary = {}
	var nearest: float = INF
	var scale: float = _field().size.x/_bounds().size.x
	for member in members:
		var distance: float = point.distance_to(_to_screen(member.position))
		if distance<=maxf(11,float(member.radius)*scale+3) and distance<nearest:
			nearest=distance
			best=member
	return best

## Explicit desktop selection uses deployment cell/member keys, never live unit IDs.
func select_members(chosen: Array) -> void:
	cancel_drag()
	explicit_selection=true
	selection_keys.clear()
	for member in chosen:selection_keys[_key(member)]=true
	if not chosen.is_empty():selected_kind=str(chosen[0].kind)
	game.queue_redraw()

func update_line_preview() -> void:
	if not dragging or drag_selection.is_empty():return
	if pressed_point.distance_to(pointer_point)<LINE_MIN_DISTANCE or Time.get_ticks_msec()-pressed_at_ms<LINE_HOLD_MS:
		line_active=false
		preview={"placements":[],"error":""}
		return
	if line_active and pointer_point==preview_point:return
	line_active=true
	preview_point=pointer_point
	drag_end=_to_local(pointer_point)
	if not _field().has_point(pointer_point):
		preview={"placements":[],"error":"已移出布阵区，松手取消本次布置。"}
		return
	preview=Layout.line_placements(game.sim.deployment_members(0),drag_selection,drag_start,drag_end,_bounds())

func begin_placement(point: Vector2, touch: bool) -> void:
	cancel_placement()
	if not _field().has_point(point):return
	var members: Array=game.sim.deployment_members(0)
	if touch and batch_count==1:
		var hit: Dictionary=_hit_member(point,members)
		if not hit.is_empty():
			_select_kind(str(hit.kind))
			var pool: Array=_pool(members)
			for index in range(pool.size()):
				if _key(pool[index])==_key(hit):selection_offset=index
			pressed_member=true
	# Structure-only selection can be inspected, never rearranged.
	drag_selection=_selection(members).filter(func(m):return not bool(game.sim.catalog[m.kind].get("structure",false)))
	placement_touch=touch
	if drag_selection.is_empty():return
	dragging=true
	pressed_point=point
	pointer_point=point
	drag_start=_to_local(point)
	drag_end=drag_start
	pressed_at_ms=Time.get_ticks_msec()

func move_placement(point: Vector2) -> void:
	if not dragging:return
	pointer_point=point
	update_line_preview()
	game.queue_redraw()

func finish_placement(point: Vector2, touch: bool) -> void:
	if touch!=placement_touch:return
	if not dragging:return
	if not _field().has_point(point):
		cancel_placement()
		_message("已取消本次布置。")
		return
	pointer_point=point
	update_line_preview()
	if touch and pressed_member and point.distance_to(pressed_point)<MEMBER_TAP_SLOP:
		cancel_placement()
		_message("已选中士兵，点空处放置或长按拉线。")
		return
	var members: Array=game.sim.deployment_members(0)
	var result: Dictionary=preview if line_active else Layout.scatter_placements(members,drag_selection,_to_local(point),_bounds())
	var error: String=str(result.error)
	var amount: int=drag_selection.size()
	if error.is_empty():error=game.sim.arrange_members(0,result.placements)
	cancel_placement()
	if not error.is_empty():
		_message(error,true)
		return
	if touch and not explicit_selection:_next_batch(members)
	game._save_settings()
	game._save_journal()
	_message("已排布 %d 名，下波生效。" % amount)

func pointer(event: InputEvent, design_point: Vector2) -> bool:
	if not opened:return false
	if bool(event.get_meta("touch_origin",false)):
		game.mobile_input.pointer(self,event,design_point)
	else:desktop_input.pointer(self,event,design_point)
	return true

func handle_action(action: String) -> void:
	if not opened or not action.begins_with("formation:"):return
	var parts: PackedStringArray = action.split(":")
	var verb: String = parts[1] if parts.size()>1 else ""
	cancel_drag()
	if verb=="close":close_panel()
	elif verb=="legacy":
		close_panel()
		game.handle_action("legacy_editor")
	elif verb=="tab" and parts.size()==3:
		tab=parts[2]
		list_page=0
		_ensure_selection()
	elif verb=="kind" and parts.size()==3:_select_kind(parts[2])
	elif verb=="adept_tactic" and selected_kind=="adept" and parts.size()==3:
		var error: String = game.sim.set_adept_tactic(0,parts[2])
		if not error.is_empty():_message(error,true)
		else:
			game._save_settings()
			game._save_journal()
			_message("下波使徒将向前投射阴影，遇地面敌人后传送。" if parts[2]=="support" else "下波使徒将在低盾受击时向后传送。")
	elif verb=="page" and parts.size()==3:
		var pages: int = maxi(1,ceili(float(_kinds().size())/ROWS_PER_PAGE))
		list_page=posmod(list_page+int(parts[2]),pages)
	elif verb=="count" and parts.size()==3:
		explicit_selection=false
		selection_keys.clear()
		var members: Array = game.sim.deployment_members(0)
		var total: int = _pool(members).size()
		if parts[2]=="one":batch_count=1
		elif parts[2]=="group" and game.sim.catalog.has(selected_kind):batch_count=maxi(1,int(game.sim.catalog[selected_kind].get("spawn_count",1)))
		elif parts[2]=="all":
			batch_count=maxi(1,total)
			selection_offset=0
		elif parts[2]=="plus":batch_count=mini(maxi(1,total),batch_count+1)
		elif parts[2]=="minus":batch_count=maxi(1,batch_count-1)
	elif verb=="next":_next_batch(game.sim.deployment_members(0))
	elif verb=="cancel":_message("已取消本次拖线，原布局保留。")
	elif verb=="auto":
		var members: Array = game.sim.deployment_members(0)
		if members.is_empty():
			_message("还没有部队，请先招募。",true)
			return
		var result: Dictionary = Layout.auto_placements(members,game.sim.catalog,_bounds())
		var error: String = str(result.get("error",""))
		if error.is_empty():error=game.sim.arrange_members(0,result.get("placements",[]))
		if error.is_empty():
			selection_offset=0
			game._save_settings()
			game._save_journal()
			_message("已按兵种定位自动排布；可以继续选兵和拖线微调。")
		else:_message(error,true)
	elif verb=="buy":_buy_group()
	game.queue_redraw()

func _buy_group() -> void:
	if not game.sim.catalog.has(selected_kind):return
	var occupied: Dictionary = {}
	for slot in game.sim.formations[0]:occupied[int(slot.cell)]=true
	var cell := -1
	for candidate in range(int(game.sim.rules.columns)*int(game.sim.rules.rows)):
		if not occupied.has(candidate):
			cell=candidate
			break
	if cell<0:
		_message("兵营组数已满；请在格阵管理中取消不需要的组。",true)
		return
	var error: String = game.sim.buy(0,selected_kind,cell)
	if not error.is_empty():
		_message(error,true)
		return
	clear_explicit_selection()
	var stats: Dictionary = game.sim.catalog[selected_kind]
	batch_count=maxi(1,int(stats.get("spawn_count",1)))
	var pool: Array = _pool(game.sim.deployment_members(0))
	for index in range(pool.size()):
		if int(pool[index].cell)==cell:
			selection_offset=index
			break
	game._save_settings()
	game._save_journal()
	_message("已招募一组%s（%d 名）；已选中新兵，可在右侧重新排布。" % [str(stats.name),batch_count])
