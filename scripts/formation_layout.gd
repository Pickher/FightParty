extends RefCounted
## 纯布阵几何：购买的组不拆分计费，只为 cell/member 指定下一波出生位置。
## 坐标均为我方视角、相对出兵中心的格数；不引用节点或修改模拟器。
const GAP := 0.1
const EPSILON := 0.0001
const BUCKET_SIZE := 2.0

static func key(cell: int, member: int) -> String:
	return "%d:%d" % [cell,member]

static func _integer(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value))

static func valid_position(value) -> bool:
	if not value is Array or value.size()!=2:return false
	for coordinate in value:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):return false
	return true

static func _inside(point: Vector2, radius: float, bounds: Rect2) -> bool:
	return point.x-radius>=bounds.position.x-EPSILON and point.y-radius>=bounds.position.y-EPSILON and point.x+radius<=bounds.end.x+EPSILON and point.y+radius<=bounds.end.y+EPSILON

static func _occupy(buckets: Dictionary, point: Vector2, radius: float, id: String) -> void:
	var bucket := Vector2i(floori(point.x/BUCKET_SIZE),floori(point.y/BUCKET_SIZE))
	if not buckets.has(bucket):buckets[bucket]=[]
	buckets[bucket].append({"id":id,"position":point,"radius":radius})

static func _overlaps(buckets: Dictionary, point: Vector2, radius: float, maximum_radius: float, ignore_id: String = "") -> bool:
	var reach := radius+maximum_radius+GAP
	for x in range(floori((point.x-reach)/BUCKET_SIZE),floori((point.x+reach)/BUCKET_SIZE)+1):
		for y in range(floori((point.y-reach)/BUCKET_SIZE),floori((point.y+reach)/BUCKET_SIZE)+1):
			for other in buckets.get(Vector2i(x,y),[]):
				if other.id==ignore_id:continue
				var minimum := radius+float(other.radius)+GAP-EPSILON
				if point.distance_squared_to(other.position)<minimum*minimum:return true
	return false

## 只检查被移动者的碰撞；旧格位队形原有的重叠不能阻止别处合法重排。
static func placement_error(members: Array, placements: Array, bounds: Rect2, check_collisions: bool = true) -> String:
	if placements.size()>members.size():return "排布数量超出现有兵力"
	var indexed: Dictionary = {}
	for unit in members:indexed[key(int(unit.cell),int(unit.member))]=unit
	var changes: Dictionary = {}
	for placement in placements:
		if not placement is Dictionary or not _integer(placement.get("cell")) or not _integer(placement.get("member")):
			return "部队编号无效"
		var id := key(int(placement.cell),int(placement.member))
		if not indexed.has(id):return "所选部队已不存在，请重新选择"
		if changes.has(id):return "同一名单位不能重复排布"
		if not valid_position(placement.get("position")):return "排布位置无效"
		var point := Vector2(float(placement.position[0]),float(placement.position[1]))
		var radius: float = float(indexed[id].radius)
		if not _inside(point,radius,bounds):return "队形超出部署区域，请缩短或移动排布线"
		changes[id]=point
	# 开局恢复保存的队形允许保留旧格阵的重叠；引用、坐标与边界仍全部校验。
	if not check_collisions:return ""
	# 拖线预览会反复调用；按最终位置建空间桶，避免每个候选扫遍全军。
	var buckets: Dictionary = {}
	var maximum_radius := 0.0
	for unit in members:
		var id := key(int(unit.cell),int(unit.member))
		var point: Vector2 = changes.get(id,unit.position)
		var layer := str(unit.layer)
		if not buckets.has(layer):buckets[layer]={}
		_occupy(buckets[layer],point,float(unit.radius),id)
		maximum_radius=maxf(maximum_radius,float(unit.radius))
	for id in changes:
		var unit: Dictionary = indexed[id]
		var point: Vector2 = changes[id]
		# 批次可包含原位成员；允许它们保留旧格阵已有的重叠。
		if point.distance_squared_to(unit.position)<=EPSILON*EPSILON:continue
		var radius := float(unit.radius)
		if _overlaps(buckets[str(unit.layer)],point,radius,maximum_radius,id):
			return "队形与同层部队重叠，请移到空处或先自动排布"
	return ""

static func _placement(unit: Dictionary, point: Vector2) -> Dictionary:
	return {"cell":int(unit.cell),"member":int(unit.member),"position":[point.x,point.y]}

## Retained positions may already overlap. Only newly added pack members must clear final occupancy.
static func added_preset_members(members: Array, retained: Array, added: Array, bounds: Rect2) -> Dictionary:
	var error := placement_error(members,retained,bounds,false)
	if not error.is_empty():return {"placements":[],"error":error}
	if added.is_empty():return {"placements":retained,"error":""}
	var changes: Dictionary = {}
	for slot in retained:
		changes[key(int(slot.cell),int(slot.member))]=Vector2(float(slot.position[0]),float(slot.position[1]))
	var pending: Dictionary = {}
	for unit in added:
		pending[key(int(unit.cell),int(unit.member))]=true
	var buckets: Dictionary = {}
	var maximum_radius := 0.0
	for unit in members:
		var layer := str(unit.layer)
		if not buckets.has(layer):buckets[layer]={}
		maximum_radius=maxf(maximum_radius,float(unit.radius))
		var id := key(int(unit.cell),int(unit.member))
		if not pending.has(id):
			_occupy(buckets[layer],changes.get(id,unit.position),float(unit.radius),id)
	var placements: Array = retained.duplicate()
	var ordered: Array = added.duplicate()
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return int(a.cell)<int(b.cell) if int(a.cell)!=int(b.cell) else int(a.member)<int(b.member))
	var rng := RandomNumberGenerator.new()
	for unit in ordered:
		var layer := str(unit.layer)
		var radius := float(unit.radius)
		var point: Vector2 = unit.position
		var id := key(int(unit.cell),int(unit.member))
		if _inside(point,radius,bounds) and not _overlaps(buckets[layer],point,radius,maximum_radius):
			placements.append(_placement(unit,point))
			_occupy(buckets[layer],point,radius,id)
		else:
			rng.seed=hash([int(unit.cell),int(unit.member)])
			var found := _scatter_group([unit],point,bounds,buckets[layer],maximum_radius,rng)
			if found.is_empty():return {"placements":[],"error":"旧阵容新增成员无可用空位"}
			placements.append_array(found)
	return {"placements":placements,"error":""}

## 优先使用落点附近的空位。外圈错开角度，给每个候选位置加少量抖动，
## 由近及远逐圈扩展；同层同尺寸的一批共用一次搜索。
static func _scatter_group(group: Array, center: Vector2, bounds: Rect2, buckets: Dictionary, maximum_radius: float, rng: RandomNumberGenerator) -> Array:
	var radius := float(group[0].radius)
	var room := bounds.grow(-radius)
	if room.size.x<0 or room.size.y<0:return []
	var origin := center.clamp(room.position,room.end)
	var spacing := radius*2.0+GAP
	var pitch := spacing*1.08
	var placements: Array = []
	for ring in range(ceili(room.size.length()/pitch)+2):
		var slots := 1
		if ring>0:slots=maxi(1,floori(PI/asin(0.5/ring)+EPSILON))
		var rotation := rng.randf_range(0,TAU)
		for index in range(slots):
			var point := origin
			if ring>0:
				# 在三个方向之间轮换，三名士兵也能展开成三角形。
				var sector := index%3
				var slot: int = ceili(float(sector*slots)/3.0)+index/3
				var direction := Vector2.from_angle(rotation+TAU*slot/slots)
				point+=direction*(ring*pitch+spacing*rng.randf_range(-0.035,0.035))
			if not _inside(point,radius,bounds) or _overlaps(buckets,point,radius,maximum_radius):continue
			var unit: Dictionary = group[placements.size()]
			placements.append(_placement(unit,point))
			_occupy(buckets,point,radius,key(int(unit.cell),int(unit.member)))
			if placements.size()==group.size():return placements
	return []

static func scatter_placements(members: Array, selected: Array, center: Vector2, bounds: Rect2) -> Dictionary:
	if selected.is_empty():return {"placements":[],"error":"请先选择要排布的部队"}
	if not center.is_finite():return {"placements":[],"error":"排布位置无效"}
	var moving: Dictionary = {}
	var groups: Dictionary = {}
	for unit in selected:
		moving[key(int(unit.cell),int(unit.member))]=true
		var layer := str(unit.layer)
		var radius := float(unit.radius)
		if not groups.has(layer):groups[layer]={}
		if not groups[layer].has(radius):groups[layer][radius]=[]
		groups[layer][radius].append(unit)
	var buckets: Dictionary = {}
	var maximum_radius := 0.0
	for unit in members:
		var layer := str(unit.layer)
		if not buckets.has(layer):buckets[layer]={}
		maximum_radius=maxf(maximum_radius,float(unit.radius))
		var id := key(int(unit.cell),int(unit.member))
		if not moving.has(id):_occupy(buckets[layer],unit.position,float(unit.radius),id)
	var placements: Array = []
	var rng := RandomNumberGenerator.new()
	# 不消耗战斗随机数；同一手势预览与提交一致。存档和重放仍记录最终坐标。
	rng.seed=hash([center,moving.keys()])
	for layer in groups:
		if not buckets.has(layer):return {"placements":[],"error":"所选部队已不存在，请重新选择"}
		var radii: Array = groups[layer].keys()
		radii.sort()
		radii.reverse()
		for radius in radii:
			var placed := _scatter_group(groups[layer][radius],center,bounds,buckets[layer],maximum_radius,rng)
			if placed.is_empty():return {"placements":[],"error":"空位不足，请换个位置或减少本批人数"}
			placements.append_array(placed)
	return {"placements":placements,"error":placement_error(members,placements,bounds)}

## 线长决定一排人数；短线展开多排。法线尽量朝己方(-X)，水平线向-Y展开。
## 失败仍返回候选坐标，供界面画红色预览；调用方必须检查 error 才能提交。
static func line_placements(members: Array, selected: Array, start: Vector2, end: Vector2, bounds: Rect2) -> Dictionary:
	if selected.is_empty():return {"placements":[],"error":"请先选择要排布的部队"}
	if not start.is_finite() or not end.is_finite():return {"placements":[],"error":"排布位置无效"}
	var radius := 0.0
	for unit in selected:radius=maxf(radius,float(unit.radius))
	var spacing := radius*2.0+GAP
	var length := start.distance_to(end)
	var direction := (end-start)/length if length>EPSILON else Vector2(0,1)
	var back := Vector2(-direction.y,direction.x)
	if back.x>EPSILON or (absf(back.x)<=EPSILON and back.y>0):back=-back
	var capacity := mini(selected.size(),maxi(1,floori(length/spacing)+1))
	var placements: Array = []
	var offset := 0
	var row := 0
	while offset<selected.size():
		var count := mini(capacity,selected.size()-offset)
		for index in range(count):
			var fraction := float(index)/float(count-1) if count>1 else 0.5
			var point: Vector2 = start.lerp(end,fraction)+back*float(row)*spacing
			if selected.size()==1:point=end
			placements.append(_placement(selected[offset+index],point))
		offset+=count
		row+=1
	return {"placements":placements,"error":placement_error(members,placements,bounds)}

## 0近战前排，1普通火力，2远射程/部署/召唤，3治疗与辅助；不是战斗AI。
static func _role(stats: Dictionary) -> int:
	var skills: Dictionary = stats.get("skills",{})
	if skills.has("healing") or skills.has("medivac_healing") or skills.has("aura"):return 3
	if skills.has("deployment") or skills.has("defender_zone") or skills.has("summon"):return 2
	var reach := float(stats.get("range",0))
	if stats.has("attack_modes"):
		for weapon in stats.attack_modes:
			if float(weapon.get("damage",0))>0:reach=maxf(reach,float(weapon.get("range",0)))
	if reach<=2.2:return 0
	return 2 if reach>=8.0 else 1

## 按职责从右向左排纵列，同层保留体积间距，空地各自排布。
## 使用确定性货架式排法，不承诺任意混合体积都能获得最密堆积。
static func auto_placements(members: Array, catalog: Dictionary, bounds: Rect2) -> Dictionary:
	if members.is_empty():return {"placements":[],"error":"还没有可排布的部队"}
	var ordered: Array = members.duplicate()
	ordered.sort_custom(func(a,b):
		if str(a.layer)!=str(b.layer):return str(a.layer)<str(b.layer)
		var a_role: int = _role(catalog[a.kind])
		var b_role: int = _role(catalog[b.kind])
		if a_role!=b_role:return a_role<b_role
		if not is_equal_approx(float(a.radius),float(b.radius)):return float(a.radius)>float(b.radius)
		return int(a.cell)<int(b.cell) if int(a.cell)!=int(b.cell) else int(a.member)<int(b.member))
	var placements: Array = []
	var layer := ""
	var role := -1
	var right := bounds.end.x
	var top := bounds.position.y
	var column_width := 0.0
	for unit in ordered:
		var next_role := _role(catalog[unit.kind])
		if str(unit.layer)!=layer:
			layer=str(unit.layer)
			right=bounds.end.x
			top=bounds.position.y
			column_width=0.0
			role=next_role
		elif next_role!=role:
			right-=column_width+GAP
			top=bounds.position.y
			column_width=0.0
			role=next_role
		var radius := float(unit.radius)
		if top+radius*2.0>bounds.end.y+EPSILON:
			right-=column_width+GAP
			top=bounds.position.y
			column_width=0.0
		var point := Vector2(right-radius,top+radius)
		if not _inside(point,radius,bounds):
			return {"placements":[],"error":"现有兵力无法按此队形全部放入，请分批手动排布"}
		placements.append(_placement(unit,point))
		column_width=maxf(column_width,radius*2.0)
		top+=radius*2.0+GAP
	# 将队形整体居中：保留职责前后关系，少量部队也不会挤在出生区角落。
	var minimum := Vector2(INF,INF)
	var maximum := Vector2(-INF,-INF)
	for i in range(placements.size()):
		var point := Vector2(float(placements[i].position[0]),float(placements[i].position[1]))
		var radius := float(ordered[i].radius)
		minimum=minimum.min(point-Vector2.ONE*radius)
		maximum=maximum.max(point+Vector2.ONE*radius)
	var shift := bounds.get_center()-(minimum+maximum)*0.5
	for placement in placements:
		placement.position[0]+=shift.x
		placement.position[1]+=shift.y
	return {"placements":placements,"error":placement_error(members,placements,bounds)}
