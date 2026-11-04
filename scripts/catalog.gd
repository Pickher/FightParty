# 中文导读：配置入口。先读这个文件，再读 commander_ai.gd，最后研究 battle_sim.gd。
# RefCounted 是不需要挂在画面上的逻辑对象；引用不用后由 Godot 管理释放。
# res:// 指 project.godot 所在的项目目录；static 函数不用先创建对象即可调用。
extends RefCounted

const RACES := ["terran","zerg","protoss","blight"]
## 仅供测试脚本注入额外兵种（例如训练假人）；游戏运行时始终为空。
static var extra_units: Dictionary = {}

## 读取 data/rules.json，把 JSON 文本转换成 Dictionary（键值对字典）。
static func rules() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))

## 读取兵种配置里的 units 字典；例如返回值["rifle"]["hp"] 是步枪兵生命值。
static func units() -> Dictionary:
	var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/units.json"))["units"]
	result.merge(extra_units.duplicate(true), true)
	return result

## 读取 data/races.json 的种族表：中文名、主题色、开局阵容与电脑配兵参数。
static func races() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/races.json"))["races"]

## 已实装（status 为 ready）的兵种才能购买和被电脑选择；stub 只是预留数据。
static func is_ready(stats: Dictionary) -> bool:
	return str(stats.get("status", "")) == "ready" and not bool(stats.get("structure", false))

## 某种族的兵种 ID，顺序与 units.json 一致；include_stubs 为 true 时包含未实装兵种。
static func race_units(catalog: Dictionary, race: String, include_stubs: bool = false) -> Array:
	return catalog.keys().filter(func(kind): return str(catalog[kind].get("race", "")) == race and not bool(catalog[kind].get("structure", false)) and str(catalog[kind].get("status","")) != "summoned" and (include_stubs or is_ready(catalog[kind])))

## 首次进入或保存的阵容不合法时使用的默认军队，总费用不超过 600。
## kind 为兵种内部 ID，cell 为格子编号：18 列时第 0 行是 0～17，第 1 行是 18～35，以此类推。
## 同一行越靠右越接近前线。若修改兵种价格或起始预算，也要检查此阵容是否合法。
static func starter(race: String = "terran") -> Array:
	return races()[race].starter.duplicate(true)
