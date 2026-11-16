extends RefCounted
## 折叠式部队面板。只编辑下一波已有士兵的位置，购买仍交给 BattleSim。
const Catalog = preload("res://scripts/catalog.gd")
const Layout = preload("res://scripts/formation_layout.gd")
const PANEL := Rect2(32,98,1376,762)
const BOARD_AREA := Rect2(446,244,930,530)
const ROWS_PER_PAGE := 8
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
var drag_moved := false
var preview: Dictionary = {"placements":[],"error":""}
var drag_selection: Array = []
var notice := "选择已有部队，再点按或按住拖线；修改只影响下一波。"
var notice_bad := false

func reset() -> void:
	opened=false
	tab="owned"
	selected_kind=""
	batch_count=1
	selection_offset=0
	list_page=0
	cancel_drag()
	notice="选择已有部队，再点按或按住拖线；修改只影响下一波。"
	notice_bad=false

func open_panel() -> void:
	opened=true
	cancel_drag()
	_ensure_selection()
	game.queue_redraw()

func close_panel() -> void:
	opened=false
	cancel_drag()
	game.queue_redraw()

func cancel_drag() -> void:
	dragging=false
	drag_moved=false
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
	var pool: Array = _pool(members)
	if pool.is_empty():return []
	selection_offset=clampi(selection_offset,0,pool.size()-1)
	var count: int = mini(maxi(1,batch_count),pool.size()-selection_offset)
	return pool.slice(selection_offset,selection_offset+count)

func _select_kind(kind: String) -> void:
	if kind!=selected_kind:
		selected_kind=kind
		batch_count=1
		selection_offset=0
	var index: int = _kinds().find(kind)
	if index>=0:list_page=index/ROWS_PER_PAGE
	cancel_drag()

func _next_batch(members: Array) -> void:
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
	game._text(Vector2(222,135),"已暂停 · 调整下一波，不指挥场上部队",18,game.MUTED)
	game._button(Rect2(1024,109,152,42),"格阵管理","formation:legacy")
	game._button(Rect2(1190,109,186,42),"收起，返回战场","formation:close",true)
	game._button(Rect2(56,166,170,46),"现有部队","formation:tab:owned",tab=="owned")
	game._button(Rect2(238,166,170,46),"招募部队","formation:tab:recruit",tab=="recruit")
	_draw_list()
	_draw_tools(selected,members)
	_draw_board(members,selected)
	var info: String = str(preview.get("error","")) if dragging and not str(preview.get("error","")).is_empty() else notice
	var bad: bool = not str(preview.get("error","")).is_empty() if dragging else notice_bad
	if dragging and str(preview.get("error","")).is_empty():info="松手布置 %d 名；拖出方框或右键取消。" % drag_selection.size()
	game.draw_multiline_string(game.FONT,Vector2(446,803),info,HORIZONTAL_ALIGNMENT_LEFT,930,18,2,game.CORAL if bad else game.MINT)
	game._text(Vector2(446,846),"亮圈为本批士兵 · 放好后自动选下一批 · 一键排布不花资源",16,game.MUTED)

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
	game._button(Rect2(446,166,70,44),"1名","formation:count:one",batch_count==1)
	game._button(Rect2(526,166,90,44),"一组","formation:count:group")
	game._button(Rect2(626,166,90,44),"全部","formation:count:all")
	game._button(Rect2(730,166,44,44),"−","formation:count:minus")
	game._text(Vector2(786,195),str(batch_count),21,game.INK)
	game._button(Rect2(852,166,44,44),"+","formation:count:plus")
	game._button(Rect2(910,166,104,44),"下一批","formation:next")
	game._button(Rect2(1028,166,170,44),"一键自动排布","formation:auto",true)
	game._button(Rect2(1212,166,164,44),"取消本次拖线","formation:cancel")
	var label: String = str(game.sim.catalog[selected_kind].name) if game.sim.catalog.has(selected_kind) else "未选兵种"
	game._text(Vector2(446,233),"%s · 本批 %d 名 / 共 %d 名 · 按住拖线可排成多列" % [label,selected.size(),pool.size()],17,game.MUTED)

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
	if dragging:
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

func _preview_at(point: Vector2, members: Array) -> void:
	drag_end=_to_local(point)
	if not _field().has_point(point):
		preview={"placements":[],"error":"已移出布阵区；松手取消本次布置。"}
		return
	preview=Layout.line_placements(members,drag_selection,drag_start,drag_end,_bounds())

func pointer(event: InputEvent, design_point: Vector2) -> bool:
	if not opened:return false
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_drag()
			_message("已取消本次拖线，原布局保留。")
			return true
		if event.button_index!=MOUSE_BUTTON_LEFT:return true
		if event.pressed:
			# 宿主先处理本面板按钮，再把剩余事件交给 pointer。
			if not _field().has_point(design_point):return true
			var members: Array = game.sim.deployment_members(0)
			var hit: Dictionary = _hit_member(design_point,members)
			pressed_member=not hit.is_empty()
			if pressed_member:
				_select_kind(str(hit.kind))
				var pool: Array = _pool(members)
				for index in range(pool.size()):
					if _key(pool[index])==_key(hit):
						selection_offset=index
						break
				pressed_member=true
			drag_selection=_selection(members)
			if drag_selection.is_empty():
				_message("先从现有部队选择兵种；没有部队时请先招募。",true)
				return true
			dragging=true
			drag_moved=false
			pressed_point=design_point
			drag_start=_to_local(design_point)
			_preview_at(design_point,members)
			game.queue_redraw()
			return true
		if dragging:
			var members: Array = game.sim.deployment_members(0)
			drag_moved=drag_moved or design_point.distance_to(pressed_point)>=8.0
			_preview_at(design_point,members)
			if pressed_member and not drag_moved:
				cancel_drag()
				_message("已选中本批士兵；点击空白位置或按住拖线来重新排布。")
				return true
			var error: String = str(preview.get("error",""))
			var amount: int = drag_selection.size()
			var wrapped: bool = selection_offset+amount>=_pool(members).size()
			if error.is_empty():error=game.sim.arrange_members(0,preview.get("placements",[]))
			cancel_drag()
			if error.is_empty():
				_next_batch(members)
				game._save_settings()
				game._save_journal()
				_message("已排布 %d 名，本轮已布置完；下一次从第一批开始。" % amount if wrapped else "已排布 %d 名，已选择下一批；再次点选可修改。" % amount)
			else:_message(error,true)
		return true
	if event is InputEventMouseMotion:
		if dragging:
			drag_moved=drag_moved or design_point.distance_to(pressed_point)>=8.0
			var members: Array = game.sim.deployment_members(0)
			_preview_at(design_point,members)
			game.queue_redraw()
		return true
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
	elif verb=="page" and parts.size()==3:
		var pages: int = maxi(1,ceili(float(_kinds().size())/ROWS_PER_PAGE))
		list_page=posmod(list_page+int(parts[2]),pages)
	elif verb=="count" and parts.size()==3:
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
