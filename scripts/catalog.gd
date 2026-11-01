extends RefCounted

static func rules() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))

static func units() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/units.json"))["units"]

static func starter() -> Array:
	return [{"kind":"guard","cell":5},{"kind":"guard","cell":23},
		{"kind":"rifle","cell":9},{"kind":"rifle","cell":15},
		{"kind":"breaker","cell":3},{"kind":"swarm","cell":11},{"kind":"rifle","cell":21}]
