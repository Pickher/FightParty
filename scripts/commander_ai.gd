extends RefCounted
const Catalog = preload("res://scripts/catalog.gd")
var catalog: Dictionary = Catalog.units()
var rng := RandomNumberGenerator.new()

func _init(seed_value: int = 42) -> void:
	rng.seed = seed_value

## Accepts public, previous-wave information only; never receives a BattleSim.
func choose(last_enemy: Array, budget: int) -> Array:
	var counters := {"guard":"breaker","rifle":"mortar","breaker":"swarm","swarm":"mortar","mortar":"sniper","sniper":"swarm"}
	var choices: Array = ["rifle","rifle","swarm"]
	for slot in last_enemy:
		choices.append(counters.get(slot.kind,"rifle"))
	var result: Array = []
	var left := budget
	var cells: Array = [5,23,11,17,4,22,10,16,3,21,9,15,2,20,8,14,1,19,7,13,0,18,6,12]
	for i in range(24):
		var kind: String = "guard" if i < 2 else str(choices[rng.randi_range(0, choices.size()-1)])
		if int(catalog[kind].cost) > left:
			kind = "swarm"
		if int(catalog[kind].cost) > left:
			break
		result.append({"kind":kind,"cell":cells[i]})
		left -= int(catalog[kind].cost)
	return result
