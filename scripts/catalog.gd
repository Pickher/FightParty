# 中文导读：配置入口。先读这个文件，再读 commander_ai.gd，最后研究 battle_sim.gd。
# RefCounted 是不需要挂在画面上的逻辑对象；引用不用后由 Godot 管理释放。
# res:// 指 project.godot 所在的项目目录；static 函数不用先创建对象即可调用。
extends RefCounted

## 读取 data/rules.json，把 JSON 文本转换成 Dictionary（键值对字典）。
static func rules() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))

## 读取兵种配置里的 units 字典；例如返回值["guard"]["hp"] 是盾卫生命值。
static func units() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/units.json"))["units"]

## 首次进入或保存的阵容超出首波预算时使用的默认军队，总费用 600。
## kind 为兵种内部 ID，cell 为格子编号：第 0 行是 0～5，第 1 行是 6～11，以此类推。
## 同一行越靠右越接近前线。若修改兵种价格或起始预算，也要检查此阵容是否合法。
static func starter() -> Array:
	return [{"kind":"guard","cell":5},{"kind":"guard","cell":23},
		{"kind":"rifle","cell":9},{"kind":"rifle","cell":15},
		{"kind":"breaker","cell":3},{"kind":"swarm","cell":11},{"kind":"rifle","cell":21}]
