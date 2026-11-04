extends RefCounted
const INK := Color("e4edf8")

static func structure(canvas: CanvasItem, p: Vector2, kind: String, race: String, radius: float, tint: Color) -> void:
	var dark := Color("162334")
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
				canvas.draw_colored_polygon(PackedVector2Array([p+dir*radius*0.7+side*radius*0.25,p+dir*radius*1.45,p+dir*radius*0.7-side*radius*0.25]),tint)
			canvas.draw_circle(p,radius*0.4,dark)
			if kind == "tower":
				canvas.draw_circle(p,radius*0.2,tint)
		"protoss":
			if kind == "treasury":
				var hexagon := PackedVector2Array()
				for i in range(6):
					hexagon.append(p+Vector2(cos(TAU*i/6.0),sin(TAU*i/6.0))*radius)
				canvas.draw_colored_polygon(hexagon,tint)
			else:
				canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*1.35),p+Vector2(radius*0.7,0),p+Vector2(0,radius*1.1),p+Vector2(-radius*0.7,0)]),tint)
			canvas.draw_arc(p,radius*0.55,0,TAU,20,INK,2)
			if kind != "treasury":
				canvas.draw_circle(p,radius*0.25,INK)
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
		"tower":
			canvas.draw_rect(Rect2(p-Vector2(radius*0.8,radius*0.3),Vector2(radius*1.6,radius*1.1)),color)
			canvas.draw_circle(p+Vector2(0,-radius*0.3),radius*0.55,color)
			canvas.draw_line(p+Vector2(0,-radius*0.3),p+Vector2(0,-radius*1.2),INK,3)
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
		"medic":
			canvas.draw_circle(p,radius,color)
			canvas.draw_rect(Rect2(p-Vector2(radius*0.65,radius*0.2),Vector2(radius*1.3,radius*0.4)),Color("162334"))
			canvas.draw_rect(Rect2(p-Vector2(radius*0.2,radius*0.65),Vector2(radius*0.4,radius*1.3)),Color("162334"))
		"vanguard":
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(-radius,-radius),p+Vector2(radius,-radius),p+Vector2(radius,radius*0.4),p+Vector2(0,radius*1.3),p+Vector2(-radius,radius*0.4)]),color)
		"swarm":
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius),p+Vector2(radius,radius),p+Vector2(-radius,radius)]),color)
		"mortar":
			canvas.draw_rect(Rect2(p-Vector2.ONE*radius,Vector2.ONE*radius*2),color)
			canvas.draw_circle(p,radius*0.5,Color("162334"))
		"agent":
			# 十字准星叠菱形：远程狙击与穿甲两种弹药。
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*0.7),p+Vector2(radius*0.7,0),p+Vector2(0,radius*0.7),p+Vector2(-radius*0.7,0)]),color)
			canvas.draw_line(p-Vector2(radius*1.2,0),p+Vector2(radius*1.2,0),color,2)
			canvas.draw_line(p-Vector2(0,radius*1.2),p+Vector2(0,radius*1.2),color,2)
		"zergling", "hellbat":
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(radius,0),p+Vector2(-radius*0.8,-radius),p+Vector2(-radius*0.3,0),p+Vector2(-radius*0.8,radius)]),color)
		"viking", "fly_swarm", "spore_drifter":
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*1.2),p+Vector2(radius*1.3,radius*0.7),p+Vector2(-radius*1.3,radius*0.7)]),color)
			canvas.draw_circle(p,radius*0.3,Color("223751"))
		"void_ray":
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-radius*1.3),p+Vector2(radius*1.1,0),p+Vector2(0,radius*1.3),p+Vector2(-radius*1.1,0)]),color)
			canvas.draw_circle(p,radius*0.4,INK)
		"battlecruiser":
			# 长舰体、前伸双叉与舰桥；空中旗舰。
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(-radius*1.5,-radius*0.6),p+Vector2(radius*0.9,-radius*0.6),p+Vector2(radius*1.6,-radius*0.25),p+Vector2(radius*1.6,radius*0.25),p+Vector2(radius*0.9,radius*0.6),p+Vector2(-radius*1.5,radius*0.6),p+Vector2(-radius*1.2,0)]),color)
			canvas.draw_line(p+Vector2(radius*0.9,-radius*0.6),p+Vector2(radius*1.8,-radius*0.75),color,2)
			canvas.draw_line(p+Vector2(radius*0.9,radius*0.6),p+Vector2(radius*1.8,radius*0.75),color,2)
			canvas.draw_rect(Rect2(p+Vector2(-radius*0.5,-radius*0.3),Vector2(radius*0.6,radius*0.6)),Color("223751"))
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
		_:
			# 尚无专属外形的兵种：圆形加兵种字母。
			canvas.draw_circle(p,radius,color)
			canvas.draw_string(ThemeDB.fallback_font,p+Vector2(-radius*0.45,radius*0.5),symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,int(maxf(radius*1.2,8)),Color("162334"))

