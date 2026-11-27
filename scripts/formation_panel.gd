extends RefCounted
## 折叠式部队面板。只编辑下一波已有士兵的位置，购买仍交给 BattleSim。
const Catalog = preload("res://scripts/catalog.gd")
const DesktopInput = preload("res://scripts/input/desktop/formation_input.gd")
const Layout = preload("res://scripts/formation_layout.gd")
const Portrait = preload("res://scripts/recruit_portrait.gd")
const UnitSummary = preload("res://scripts/unit_summary.gd")
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
var recruit_page := 0
var recruit_kind := ""
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
	recruit_page=0
	recruit_kind=""
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
	var area := BOARD_AREA
	if tab == "recruit":
		area.size.x -= 300.0
	var scale: float = minf(area.size.x/bounds.size.x,area.size.y/bounds.size.y)
	return Rect2(area.get_center()-bounds.size*scale*0.5,bounds.size*scale)

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

func _recruit_kinds() -> Array:
	return Catalog.race_units(game.sim.catalog,str(game.sim.races[0]))

func _kinds() -> Array:
	var available: Array = _recruit_kinds()
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

func _page_count(kinds: Array) -> int:
	return maxi(1,ceili(float(kinds.size())/ROWS_PER_PAGE))

func _visible_recruits(kinds: Array) -> Array:
	var first: int=recruit_page*ROWS_PER_PAGE
	return kinds.slice(first,first+ROWS_PER_PAGE)

## 不因每帧刷新钱包而跳选。仅首次打开、选项不可见或翻页时选择本页候选。
func _ensure_recruit_selection(kinds: Array, balance: Dictionary) -> void:
	recruit_page=clampi(recruit_page,0,_page_count(kinds)-1)
	var visible: Array=_visible_recruits(kinds)
	if visible.has(recruit_kind):return
	recruit_kind=str(visible[0]) if not visible.is_empty() else ""
	for kind in visible:
		if game.sim.resource_error(game.sim.unit_price(kind),balance).is_empty():
			recruit_kind=str(kind)
			return

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

func _adept_tactic_visible() -> bool:
	if tab=="recruit":
		return recruit_kind=="adept" and _visible_recruits(_recruit_kinds()).has("adept")
	return selected_kind=="adept"

func draw() -> void:
	if not opened:return
	_ensure_selection()
	if tab=="recruit":_ensure_recruit_selection(_recruit_kinds(),game.sim.wallet(0))
	var members: Array = game.sim.deployment_members(0)
	var selected: Array = drag_selection if dragging else _selection(members)
	game.draw_rect(Rect2(0,98,1440,762),Color("091321"))
	game._panel(PANEL,game.PANEL,game.MINT)
	# 此面板独占输入，不留下被遮住的布阵格和战场工具栏按钮。
	game.buttons.clear()
	game._text(Vector2(56,137),"部队配置",27,game.MINT)
	if _adept_tactic_visible():
		var tactic: String = game.sim.adept_tactics[0]
		game._text(Vector2(222,135),"下一波使徒战术",18,game.MUTED)
		game._button(Rect2(388,109,118,42),"后撤传送","formation:adept_tactic:retreat",tactic=="retreat")
		game._button(Rect2(518,109,118,42),"支援传送","formation:adept_tactic:support",tactic=="support")
	else:
		game._text(Vector2(222,135),"调整下一波 · 不指挥场上部队",18,game.MUTED)
	if game._can_load_formation_preset():
		game._button(Rect2(648,109,152,42),"载入已存阵容","formation:load_preset")
	if not members.is_empty():
		game._button(Rect2(824,109,176,42),"保存当前布阵","formation:save_preset")
	game._button(Rect2(1024,109,152,42),"格阵管理","formation:legacy")
	game._button(Rect2(1190,109,186,42),"收起，返回战场","formation:close",true)
	game._button(Rect2(56,166,170,46),"现有部队","formation:tab:owned",tab=="owned")
	game._button(Rect2(238,166,170,46),"招募部队","formation:tab:recruit",tab=="recruit")
	_draw_list()
	_draw_tools(selected,members)
	_draw_board(members,selected)
	_draw_recruit_summary()
	desktop_input.draw(self)
	var info: String = str(preview.get("error","")) if dragging and not str(preview.get("error","")).is_empty() else notice
	var bad: bool = not str(preview.get("error","")).is_empty() if dragging else notice_bad
	if dragging and str(preview.get("error","")).is_empty():info="松手布置 %d 名；拖出方框或 Esc 取消。" % drag_selection.size()
	game.draw_multiline_string(game.FONT,Vector2(446,803),info,HORIZONTAL_ALIGNMENT_LEFT,710,18,2,game.CORAL if bad else game.MINT)
	game._text(Vector2(446,846),"电脑：左键单选/双击同类/框选，右键点放或长按拖线；触屏沿用点放/拖线",16,game.MUTED)
	game._draw_tower_button(Rect2(1174,802,202,44))

func _draw_list() -> void:
	var recruiting: bool=tab=="recruit"
	var kinds: Array = _recruit_kinds() if recruiting else _kinds()
	var counts: Dictionary = _counts()
	var balance: Dictionary=game.sim.wallet(0) if recruiting else {}
	var active_kind: String=recruit_kind if recruiting else selected_kind
	var page: int=recruit_page if recruiting else list_page
	var pages: int = _page_count(kinds)
	for row in range(ROWS_PER_PAGE):
		var index: int = page*ROWS_PER_PAGE+row
		if index>=kinds.size():break
		var kind: String = str(kinds[index])
		var stats: Dictionary = game.sim.catalog[kind]
		var groups: int = int(counts.get(kind,0))
		var count: int = groups*maxi(1,int(stats.get("spawn_count",1)))
		var rect := Rect2(56,226+row*60,352,54)
		game._panel(rect,Color("204b43") if active_kind==kind else Color("17293c"),game.MINT if active_kind==kind else Color("304358"),6)
		Portrait.draw(game,Rect2(rect.position + Vector2(2,1),Vector2(52,52)),kind,active_kind==kind)
		var secondary: Color = Portrait.SELECTED_SECONDARY if active_kind == kind else game.MUTED
		game._text(rect.position+Vector2(68,23),str(stats.name),19,game.INK)
		game._text(rect.position+Vector2(68,44),"已有 %d 组 · %d 名" % [groups,count],15,secondary)
		if recruiting:
			var price: Dictionary=game.sim.unit_price(kind)
			var affordable: bool=game.sim.resource_error(price,balance).is_empty()
			game._text(rect.position+Vector2(221,23),"%d矿 / 组" % int(price.minerals),15,game.MINT if affordable else secondary)
			if int(price.gas)>0 or int(price.cores)>0:
				game._text(rect.position+Vector2(221,44),"%d气 %d核" % [int(price.gas),int(price.cores)],14,secondary)
		var action_prefix: String="formation:recruit_kind:" if recruiting else "formation:kind:"
		game.buttons.append({"rect":rect,"action":action_prefix+kind})
	if kinds.is_empty():
		game._text(Vector2(74,268),"当前没有可招募的兵种" if recruiting else "还没有已购买的部队",20,game.MUTED)
		if not recruiting:game._text(Vector2(74,305),"点击「招募部队」购买一组。",17,game.MINT)
	game._button(Rect2(56,718,96,40),"上一页","formation:page:-1")
	game._text(Vector2(174,746),"%d / %d" % [page+1,pages],18,game.MUTED)
	game._button(Rect2(312,718,96,40),"下一页","formation:page:1")
	if recruiting:
		if not recruit_kind.is_empty():_draw_buy_button(recruit_kind,balance)
	else:
		game._text(Vector2(56,797),"组数与人数按当前兵种配置显示。",16,game.MUTED)
		game._text(Vector2(56,823),"删除/退款请进入「格阵管理」。",16,game.MUTED)

func _resource_text(price: Dictionary, balance: Dictionary = {}) -> String:
	var names := {"minerals":"矿","gas":"气","cores":"灵核"}
	var parts := PackedStringArray()
	for key in names:
		var amount: int=int(price.get(key,0))-int(balance.get(key,0))
		if amount>0:parts.append("%d%s" % [amount,names[key]])
	return " ".join(parts) if not parts.is_empty() else "0矿"

func _draw_buy_button(kind: String, balance: Dictionary) -> void:
	var stats: Dictionary=game.sim.catalog[kind]
	var price: Dictionary=game.sim.unit_price(kind)
	var full: bool=game.sim.formations[0].size()>=int(game.sim.rules.columns)*int(game.sim.rules.rows)
	var can_buy: bool=not full and game.sim.resource_error(price,balance).is_empty()
	var rect:=Rect2(56,774,352,50)
	game._panel(rect,Color("204b43") if can_buy else Color("17293c"),game.MINT if can_buy else game.MUTED)
	game._text(rect.position+Vector2(14,22),"招募%s ×%d" % [stats.name,maxi(1,int(stats.get("spawn_count",1)))],19,game.MINT if can_buy else game.MUTED)
	game._text(rect.position+Vector2(14,44),"每组 %s" % _resource_text(price),16,game.INK if can_buy else game.MUTED)
	if can_buy:
		game.buttons.append({"rect":rect,"action":"formation:buy:"+kind})
	elif full:
		game._text(Vector2(56,848),"兵营已满，可在格阵管理中移除部队",16,game.CORAL)
	else:
		game._text(Vector2(56,848),"还缺 %s" % _resource_text(price,balance),16,game.CORAL)

func _target_label(stats: Dictionary) -> String:
	var ground := false
	var air := false
	var modes: Array=UnitSummary.weapons(stats)
	var summoned_kind: String=str(stats.get("skills",{}).get("summon",{}).get("kind",""))
	if game.sim.catalog.has(summoned_kind):modes.append_array(UnitSummary.weapons(game.sim.catalog[summoned_kind]))
	for mode in modes:
		var weapon: Dictionary=mode.data
		if float(weapon.get("damage",0))<=0:continue
		var layers: Array=weapon.get("target_layers",["ground"])
		ground=ground or layers.has("ground")
		air=air or layers.has("air")
	if ground and air:return "对空对地"
	if ground:return "仅对地"
	if air:return "仅对空"
	return str(stats.get("role","支援"))

func _draw_recruit_summary() -> void:
	if tab != "recruit" or not game.sim.catalog.has(recruit_kind):
		return
	var field := _field()
	var card := Rect2(field.end.x + 14.0, BOARD_AREA.position.y + 10.0,
		BOARD_AREA.end.x - field.end.x - 24.0, BOARD_AREA.size.y - 20.0)
	game._panel(card, Color("121b2b"), Color("384252"), 6)
	var width := card.size.x - 32.0
	var left := card.position.x + 16.0
	var side := minf(224.0, width)
	var image := Rect2(roundf(card.get_center().x - side * 0.5), card.position.y + 16.0, side, side)
	Portrait.draw(game, image, recruit_kind)
	var stats: Dictionary = game.sim.catalog[recruit_kind]
	var title_y := image.end.y + 36.0
	game._text(Vector2(left, title_y), str(stats.name), 25, game.INK)
	var role := str(stats.get("role", ""))
	var target := _target_label(stats)
	if target != role:
		game.draw_string(game.FONT, Vector2(left, title_y-1.0), target, HORIZONTAL_ALIGNMENT_RIGHT, width, 15, game.MINT)
	game._text(Vector2(left, title_y+28.0), role, 16, game.MUTED)
	game.draw_line(Vector2(left, title_y+44.0), Vector2(left+width, title_y+44.0), Color("364353"))
	game.draw_multiline_string(game.FONT, Vector2(left, title_y+70.0), UnitSummary.text(stats),
		HORIZONTAL_ALIGNMENT_LEFT, width, 17, -1, game.INK)

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
	if tab == "recruit":
		game._text(field.position + Vector2(12,30),"后方",17,game.MUTED)
		game._text(Vector2(field.end.x-78,field.position.y+30),"前线 →",17,game.MINT)
	else:
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
	elif verb=="tab" and parts.size()==3 and parts[2] in ["owned","recruit"]:
		tab=parts[2]
		_ensure_selection()
	elif verb=="kind" and parts.size()==3 and tab=="owned" and _kinds().has(parts[2]):
		_select_kind(parts[2])
	elif verb=="recruit_kind" and parts.size()==3 and tab=="recruit":
		if _visible_recruits(_recruit_kinds()).has(parts[2]):recruit_kind=parts[2]
	elif verb=="adept_tactic" and parts.size()==3 and _adept_tactic_visible():
		var error: String = game.sim.set_adept_tactic(0,parts[2])
		if not error.is_empty():_message(error,true)
		else:
			game._save_settings()
			game._save_journal()
			_message("下波使徒将向前投射阴影，遇地面敌人后传送。" if parts[2]=="support" else "下波使徒将在低盾受击时向后传送。")
	elif verb=="page" and parts.size()==3:
		if tab=="recruit":
			var kinds: Array=_recruit_kinds()
			recruit_page=posmod(recruit_page+int(parts[2]),_page_count(kinds))
			_ensure_recruit_selection(kinds,game.sim.wallet(0))
		else:
			list_page=posmod(list_page+int(parts[2]),_page_count(_kinds()))
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
			game._save_journal()
			_message("已按兵种定位自动排布；可以继续选兵和拖线微调。")
		else:_message(error,true)
	elif verb=="load_preset":
		var error: String=game._load_formation_preset()
		if error.is_empty():
			game._save_journal()
			tab="owned"
			_ensure_selection()
			_message("已按当前价格购入并载入阵容。")
		else:_message(error,true)
	elif verb=="save_preset":
		var error: String=game._save_formation_preset()
		_message("已保存本种族布阵；新局仍从空兵营开始。" if error.is_empty() else error,not error.is_empty())
	elif verb=="buy" and parts.size()==3:_buy_group(parts[2])
	game.queue_redraw()

func _buy_group(kind: String) -> void:
	# 旧点击区域可能在翻页后一帧仍存活。拒绝非当前选中、非当前页、非招募标签的动作。
	if tab!="recruit" or kind!=recruit_kind or not _visible_recruits(_recruit_kinds()).has(kind):return
	var budget_error: String=game.sim.resource_error(game.sim.unit_price(kind),game.sim.wallet(0))
	if not budget_error.is_empty():
		_message(budget_error,true)
		return
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
	var error: String = game.sim.buy(0,kind,cell)
	if not error.is_empty():
		_message(error,true)
		return
	_select_kind(kind)
	var stats: Dictionary = game.sim.catalog[kind]
	batch_count=maxi(1,int(stats.get("spawn_count",1)))
	var pool: Array = _pool(game.sim.deployment_members(0))
	for index in range(pool.size()):
		if int(pool[index].cell)==cell:
			selection_offset=index
			break
	game._save_journal()
	_message("已招募一组%s（%d 名）；已选中新兵，可在右侧重新排布。" % [str(stats.name),batch_count])
