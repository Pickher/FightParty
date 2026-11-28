extends RefCounted
const INK := Color("e4edf8")
const MEDIVAC_SPRITE := "res://assets/units/medivac/idle.png"
static var _medivac_texture: Texture2D
static var _medivac_texture_checked := false

## 拦截机朝实际飞行方向绘制，能看出掠过和转向；不旋转血条或改变占地。
static func draw_interceptor(canvas: CanvasItem, p: Vector2, color: Color, size: Vector2, heading: Vector2) -> void:
	var forward := heading.normalized() if heading.length_squared()>0.0001 else Vector2.RIGHT
	var side := Vector2(-forward.y,forward.x)
	canvas.draw_colored_polygon(PackedVector2Array([
		p+forward*size.x*0.5,
		p-forward*size.x*0.4+side*size.y*0.45,
		p-forward*size.x*0.2,
		p-forward*size.x*0.4-side*size.y*0.45]),color)
	canvas.draw_circle(p+forward*size.x*0.12,maxf(0.5,size.x*0.1),Color(INK,color.a))

## Shared battle/shop/formation art. Keep source colors, but honor disabled UI alpha.
## Missing optional sprite falls back to the existing procedural silhouette below.
static func _draw_medivac_model(canvas: CanvasItem, p: Vector2, radius: float, alpha: float) -> bool:
	if not _medivac_texture_checked:
		_medivac_texture_checked=true
		if ResourceLoader.exists(MEDIVAC_SPRITE):
			_medivac_texture=load(MEDIVAC_SPRITE) as Texture2D
	if _medivac_texture==null:return false
	var size: Vector2 = _medivac_texture.get_size()
	if size.x<=0 or size.y<=0:return false
	size*=radius*3.0/maxf(size.x,size.y)
	canvas.draw_texture_rect(_medivac_texture,Rect2(p-size*0.5,size),false,Color(1,1,1,alpha))
	return true

static func structure(canvas: CanvasItem, p: Vector2, kind: String, race: String, radius: float, tint: Color) -> void:
	var dark := Color(Color("162334"), tint.a)
	var detail := Color(INK, tint.a)
	match race:
		"terran":
			draw(canvas,p,kind,tint,radius)
		"zerg":
			canvas.draw_circle(p,radius*0.95,tint)
			var spikes: int = 3 if kind == "treasury" else 5
			for i in range(spikes):
				var angle: float = -PI*0.5 + TAU*i/spikes
				var dir := Vector2(cos(angle),sin(angle))
				var side := Vector2(-dir.y,dir.x)
				canvas.draw_colored_polygon(PackedVector2Array([p+dir*radius*0.7+side*radius*0.25,p+dir*radius*(1.0 if kind=="zerg_tower_cluster" else 1.45),p+dir*radius*0.7-side*radius*0.25]),tint)
			canvas.draw_circle(p,radius*0.4,dark)
			if kind == "zerg_tower_cluster":
				# 四个炮位共用建筑；下方脊针、上方孢子以不同外形区分。
				for side in [-1,1]:
					var spore: Vector2 = p+Vector2(side*radius*0.55,-radius*0.45)
					canvas.draw_circle(spore,radius*0.28,Color(Color("a5ce85"),tint.a))
					var spine: Vector2 = p+Vector2(side*radius*0.55,radius*0.4)
					canvas.draw_colored_polygon(PackedVector2Array([spine+Vector2(-radius*.25,radius*.2),spine+Vector2(0,-radius*.4),spine+Vector2(radius*.25,radius*.2)]),detail)
			elif kind == "tower":
				canvas.draw_circle(p,radius*0.2,tint)
		"protoss":
			if kind == "treasury":
				var hexagon := PackedVector2Array()
				for i in range(6):
					hexagon.append(p+Vector2(cos(TAU*i/6.0),sin(TAU*i/6.0))*radius)
				canvas.draw_colored_polygon(hexagon,tint)
			else:
				canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*(1.0 if kind=="protoss_photon_cannon" else 1.35)),p+Vector2(radius*0.7,0),p+Vector2(0,radius*(1.0 if kind=="protoss_photon_cannon" else 1.1)),p+Vector2(-radius*0.7,0)]),tint)
			canvas.draw_arc(p,radius*0.55,0,TAU,20,detail,2)
			if kind != "treasury":
				canvas.draw_circle(p,radius*0.25,detail)
		"blight":
			var blob := PackedVector2Array()
			for i in range(10):
				var length: float = radius*(1.25 if i % 2 == 0 else 0.75)
				blob.append(p+Vector2(cos(TAU*i/10.0),sin(TAU*i/10.0))*length)
			canvas.draw_colored_polygon(blob,tint)
			canvas.draw_circle(p,radius*0.45,dark)
			for x in [-0.35,0.15]:
				canvas.draw_line(p+Vector2(x*radius,radius*0.6),p+Vector2(x*radius,radius*1.3),tint,2)
		_:
			var octagon := PackedVector2Array()
			for i in range(8):
				octagon.append(p+Vector2(cos(TAU*(i+0.5)/8.0),sin(TAU*(i+0.5)/8.0))*radius)
			canvas.draw_colored_polygon(octagon,Color("4a5a6c"))
			canvas.draw_string(ThemeDB.fallback_font,p+Vector2(-5,6),"?",HORIZONTAL_ALIGNMENT_LEFT,-1,16,INK)


static func draw(canvas: CanvasItem, p: Vector2, kind: String, color: Color, radius: float, symbol: String = "?") -> void:
	match kind:
		"gate_tower":
			canvas.draw_rect(Rect2(p-Vector2(radius*0.9,radius*0.6),Vector2(radius*1.8,radius*1.5)),color)
			for x in [-0.9,-0.15,0.6]:
				canvas.draw_rect(Rect2(p+Vector2(x*radius,-radius),Vector2(radius*0.3,radius*0.4)),color)
			canvas.draw_rect(Rect2(p+Vector2(-radius*0.25,radius*0.2),Vector2(radius*0.5,radius*0.7)),Color("162334"))
		"treasury":
			canvas.draw_circle(p,radius,color)
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*0.6),p+Vector2(radius*0.6,0),p+Vector2(0,radius*0.6),p+Vector2(-radius*0.6,0)]),Color("6b4f10"))
		"tower", "terran_bunker", "protoss_photon_cannon", "zerg_tower_cluster":
			canvas.draw_rect(Rect2(p-Vector2(radius*0.8,radius*0.3),Vector2(radius*1.6,radius*1.1)),color)
			canvas.draw_circle(p+Vector2(0,-radius*0.3),radius*0.55,color)
			canvas.draw_line(p+Vector2(0,-radius*0.3),p+Vector2(0,-radius*1.2),Color(INK,color.a),3)
		"liberator":
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*1.4),p+Vector2(radius*1.5,radius*0.8),p+Vector2(0,radius*0.35),p+Vector2(-radius*1.5,radius*0.8)]),color)
			for side in [-1,1]:
				canvas.draw_circle(p+Vector2(side*radius*0.8,radius*0.4),radius*0.3,Color("223751"))
			canvas.draw_line(p+Vector2(0,-radius*0.65),p+Vector2(0,radius*0.25),INK,2)
		"marauder":
			# 重装躯干和双侧榴弹发射器；外观不改变单次攻击次数。
			canvas.draw_rect(Rect2(p-Vector2(radius*0.65,radius*0.8),Vector2(radius*1.3,radius*1.6)),color)
			for side in [-1,1]:
				canvas.draw_rect(Rect2(p+Vector2(side*radius-radius*0.3,-radius*0.55),Vector2(radius*0.6,radius*1.1)),color)
			canvas.draw_line(p+Vector2(-radius*0.35,-radius*0.3),p+Vector2(radius*0.35,-radius*0.3),INK,2)
		"hellbat_mech":
			# Distinctive top-mounted torch and broad paired arm shields.
			for side in [-1, 1]:
				var offset := Vector2(float(side) * 0.85, 0.08) * radius
				canvas.draw_circle(p + offset, radius * 0.60, color)
				canvas.draw_rect(Rect2(p + offset + Vector2(-0.24, 0.32) * radius, Vector2(0.48, 0.60) * radius), color)
			canvas.draw_rect(Rect2(p - Vector2(0.53, 0.72) * radius, Vector2(1.06, 1.22) * radius), color)
			canvas.draw_line(p, p + Vector2(0.0, -1.18) * radius, Color(INK, color.a), maxf(1.0, radius * 0.26))
		"colossus":
			for side in [-1,1]:
				for vertical in [-1,1]:
					canvas.draw_line(p+Vector2(side*radius*0.4,vertical*radius*0.4),p+Vector2(side*radius*1.3,vertical*radius*1.2),color,2)
				canvas.draw_circle(p+Vector2(side*radius*0.9,0),radius*0.25,INK)
			canvas.draw_rect(Rect2(p-Vector2(radius*0.55,radius*0.75),Vector2(radius*1.1,radius*1.5)),color)
		"piercer":
			for side in [-1,1]:
				for offset in [-0.6,0.6]:
					canvas.draw_line(p+Vector2(side*radius*0.4,offset*radius),p+Vector2(side*radius*1.3,offset*radius*1.3),color,2)
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius),p+Vector2(radius*0.7,0),p+Vector2(0,radius),p-Vector2(radius*0.7,0)]),color)
		"medivac":
			if _draw_medivac_model(canvas,p,radius,color.a):return
			# Fallback silhouette when the optional model-derived sprite is unavailable.
			canvas.draw_rect(Rect2(p-Vector2(radius*0.9,radius*0.35),Vector2(radius*1.8,radius*0.7)),color)
			for side in [-1,1]:
				canvas.draw_rect(Rect2(p+Vector2(-radius*0.4,side*radius*0.65)-Vector2(radius*0.55,radius*0.2),Vector2(radius*1.1,radius*0.4)),color)
			canvas.draw_line(p-Vector2(radius*0.3,0),p+Vector2(radius*0.3,0),INK,2)
			canvas.draw_line(p-Vector2(0,radius*0.3),p+Vector2(0,radius*0.3),INK,2)
		"medic":
			canvas.draw_circle(p,radius,color)
			canvas.draw_rect(Rect2(p-Vector2(radius*0.65,radius*0.2),Vector2(radius*1.3,radius*0.4)),Color("162334"))
			canvas.draw_rect(Rect2(p-Vector2(radius*0.2,radius*0.65),Vector2(radius*0.4,radius*1.3)),Color("162334"))
		"vanguard":
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(-radius,-radius),p+Vector2(radius,-radius),p+Vector2(radius,radius*0.4),p+Vector2(0,radius*1.3),p+Vector2(-radius,radius*0.4)]),color)
		"adept":
			# 披风、头盔和月牙形共鸣刃；投影沿用本体剪影。
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(-0.45,-0.38)*radius,p+Vector2(0.32,-0.38)*radius,p+Vector2(0.52,0.85)*radius,p+Vector2(-0.81,1)*radius]),color)
			canvas.draw_circle(p+Vector2(-0.12,-0.66)*radius,radius*0.41,color)
			canvas.draw_arc(p+Vector2(0.72,-0.12)*radius,radius*0.51,-1.65,1.95,10,Color(INK,color.a),maxf(1,radius*0.22))
		"swarm":
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius),p+Vector2(radius,radius),p+Vector2(-radius,radius)]),color)
		"mortar":
			canvas.draw_rect(Rect2(p-Vector2.ONE*radius,Vector2.ONE*radius*2),color)
			canvas.draw_circle(p,radius*0.5,Color("162334"))
		"ghost":
			# 幽灵沿用特工的菱形准星剪影。
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*0.7),p+Vector2(radius*0.7,0),p+Vector2(0,radius*0.7),p+Vector2(-radius*0.7,0)]),color)
			canvas.draw_line(p-Vector2(radius*1.2,0),p+Vector2(radius*1.2,0),color,2)
			canvas.draw_line(p-Vector2(0,radius*1.2),p+Vector2(0,radius*1.2),color,2)
		"zergling", "hellbat":
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(radius,0),p+Vector2(-radius*0.8,-radius),p+Vector2(-radius*0.3,0),p+Vector2(-radius*0.8,radius)]),color)
		"viking_assault":
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(radius,0), p+Vector2(0,radius*0.6), p+Vector2(-radius*0.8,radius*0.35), p+Vector2(-radius*0.8,-radius*0.35), p+Vector2(0,-radius*0.6)]),color)
			for side in [-1.0,1.0]:
				var port := p + Vector2(-0.4,side*0.75)*radius
				canvas.draw_line(port,port+Vector2.RIGHT*radius*1.4,color,maxf(1,radius*0.45))
		"viking", "fly_swarm", "spore_drifter":
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*1.2),p+Vector2(radius*1.3,radius*0.7),p+Vector2(-radius*1.3,radius*0.7)]),color)
			canvas.draw_circle(p,radius*0.3,Color("223751"))
		"void_ray":
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*1.3),p+Vector2(radius*1.1,0),p+Vector2(0,radius*1.3),p+Vector2(-radius*1.1,0)]),color)
			canvas.draw_circle(p,radius*0.4,INK)
		"rifle":
			canvas.draw_circle(p,radius*0.8,color)
			canvas.draw_rect(Rect2(p+Vector2(radius*0.3,-radius*0.2),Vector2(radius*0.9,radius*0.4)),color)
		"widow_mine":
			for angle in [PI*0.25,PI*0.75,PI*1.25,PI*1.75]:
				canvas.draw_line(p,p+Vector2(cos(angle),sin(angle))*radius*1.2,color,2)
			canvas.draw_circle(p,radius*0.55,color)
			canvas.draw_circle(p,radius*0.2,Color("ff6f5e"))
		"thor":
			canvas.draw_rect(Rect2(p-Vector2(radius*0.75,radius*0.6),Vector2(radius*1.5,radius*1.5)),color)
			for side in [-1,1]:
				canvas.draw_circle(p+Vector2(side*radius*0.95,-radius*0.55),radius*0.45,color)
			canvas.draw_rect(Rect2(p+Vector2(-radius*0.3,-radius*0.25),Vector2(radius*0.6,radius*0.3)),Color("162334"))
		"roach":
			var shell := PackedVector2Array()
			for i in range(12):
				shell.append(p+Vector2(cos(TAU*i/12.0)*radius*1.1,sin(TAU*i/12.0)*radius*0.75))
			canvas.draw_colored_polygon(shell,color)
			canvas.draw_line(p+Vector2(-radius*0.7,0),p+Vector2(radius*0.7,0),Color("162334"),2)
		"hydralisk":
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*1.2),p+Vector2(radius*0.45,radius),p+Vector2(-radius*0.45,radius)]),color)
			for side in [-1,1]:
				canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(side*radius*0.2,-radius*0.7),p+Vector2(side*radius*1.1,-radius*0.2),p+Vector2(side*radius*0.3,0)]),color)
		"ultralisk":
			canvas.draw_circle(p,radius,color)
			for side in [-1,1]:
				canvas.draw_line(p+Vector2(radius*0.6,side*radius*0.4),p+Vector2(radius*1.4,side*radius*0.9),INK,2)
		"stalker":
			for side in [-1,1]:
				for vertical in [-1,1]:
					canvas.draw_line(p,p+Vector2(side*radius*1.2,vertical*radius*1.1),color,2)
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*0.8),p+Vector2(radius*0.6,0),p+Vector2(0,radius*0.6),p+Vector2(-radius*0.6,0)]),color)
			canvas.draw_circle(p+Vector2(0,-radius*0.1),radius*0.2,INK)
		"immortal":
			var hull := PackedVector2Array()
			for i in range(6):
				hull.append(p+Vector2(cos(TAU*i/6.0+PI/6.0),sin(TAU*i/6.0+PI/6.0))*radius)
			canvas.draw_colored_polygon(hull,color)
			canvas.draw_rect(Rect2(p-Vector2(radius*0.35,radius*0.35),Vector2(radius*0.7,radius*0.7)),Color("162334"))
		"archon":
			canvas.draw_circle(p,radius*0.75,color)
			canvas.draw_arc(p,radius*1.15,0,TAU,20,Color(color,0.6),2)
			canvas.draw_circle(p,radius*0.3,INK)
		"spitter":
			canvas.draw_circle(p,radius*0.85,color)
			canvas.draw_circle(p+Vector2(radius*0.45,0),radius*0.3,Color("162334"))
		"abomination":
			for offset in [Vector2(-0.45,-0.25),Vector2(0.4,-0.3),Vector2(0,0.4)]:
				canvas.draw_circle(p+offset*radius,radius*0.7,color)
			canvas.draw_line(p+Vector2(-radius*0.5,0),p+Vector2(radius*0.5,radius*0.1),Color("162334"),2)
		"baneling":
			canvas.draw_circle(p,radius,color)
			for side in [-1,1]:canvas.draw_circle(p+Vector2(side*radius*.45,-radius*.2),radius*.3,Color("91cf49"))
		"ravager":
			canvas.draw_circle(p,radius*.8,color)
			for i in range(3):
				var x: float = (i-1)*radius*.6
				canvas.draw_line(p+Vector2(x,-radius*.3),p+Vector2(x,-radius*1.25),INK,2)
		"mutalisk":
			for side in [-1,1]:
				canvas.draw_colored_polygon(PackedVector2Array([p,p+Vector2(side*radius*1.4,-radius),p+Vector2(side*radius,radius*.8)]),color)
			canvas.draw_circle(p,radius*.35,INK)
		"infestor", "tunneler":
			canvas.draw_circle(p,radius,color)
			for i in range(3):canvas.draw_circle(p+Vector2((i-1)*radius*.6,0),radius*.25,Color("395b30"))
		"brood_lord", "carrier":
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(-radius*1.3,0),p+Vector2(0,-radius*.8),p+Vector2(radius*1.3,0),p+Vector2(0,radius*.8)]),color)
			for side in [-1,1]:canvas.draw_circle(p+Vector2(side*radius*.65,0),radius*.25,INK)
		"sentry", "high_templar":
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius),p+Vector2(radius,radius),p+Vector2(-radius,radius)]),color)
			canvas.draw_circle(p,radius*.35,INK)
		"disruptor":
			canvas.draw_circle(p,radius*.7,color)
			canvas.draw_arc(p,radius*1.15,0,TAU,16,INK,2)
		"interceptor":
			draw_interceptor(canvas,p,color,Vector2.ONE*radius*3.0,Vector2.RIGHT)
		"broodling":
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(radius,0),p+Vector2(-radius,-radius*.7),p+Vector2(-radius,radius*.7)]),color)
		"rotling", "splitter", "bloater", "plague_herald", "gravedigger", "brood_mother":
			canvas.draw_circle(p,radius,color)
			canvas.draw_line(p+Vector2(-radius*.6,-radius*.4),p+Vector2(radius*.6,radius*.4),INK,2)
			canvas.draw_circle(p+Vector2(radius*.2,-radius*.2),radius*.2,Color("3d5329"))

		_:
			# 尚无专属外形的兵种：圆形加兵种字母。
			canvas.draw_circle(p,radius,color)
			canvas.draw_string(ThemeDB.fallback_font,p+Vector2(-radius*0.45,radius*0.5),symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,int(maxf(radius*1.2,8)),Color("162334"))

