class_name StatProfile
extends Resource

## Immutable set of player attributes. Values are 1-20 on the FM-style scale.

const MIN_VALUE := 1
const MAX_VALUE := 20

const ATTRIBUTE_NAMES := [
	"pace", "acceleration", "finishing", "passing", "first_touch", "heading",
	"tackling", "strength", "stamina", "anticipation", "positioning",
	"composure", "decisions", "vision", "work_rate", "technique",
]

@export var pace: int = 10
@export var acceleration: int = 10
@export var finishing: int = 10
@export var passing: int = 10
@export var first_touch: int = 10
@export var heading: int = 10
@export var tackling: int = 10
@export var strength: int = 10
@export var stamina: int = 10
@export var anticipation: int = 10
@export var positioning: int = 10
@export var composure: int = 10
@export var decisions: int = 10
@export var vision: int = 10
@export var work_rate: int = 10
@export var technique: int = 10


func get_attribute(attribute_name: String) -> int:
	if not ATTRIBUTE_NAMES.has(attribute_name):
		push_error("StatProfile: unknown attribute '%s'" % attribute_name)
		return 0
	return int(get(attribute_name))


func average() -> float:
	var total := 0
	for key in ATTRIBUTE_NAMES:
		total += get_attribute(key)
	return float(total) / float(ATTRIBUTE_NAMES.size())


func to_dict() -> Dictionary:
	var result := {}
	for key in ATTRIBUTE_NAMES:
		result[key] = get_attribute(key)
	return result


static func is_valid_dict(data: Dictionary) -> bool:
	for key in ATTRIBUTE_NAMES:
		if not data.has(key):
			return false
		var raw: Variant = data[key]
		if not (raw is int or raw is float):
			return false
		var value := int(raw)
		if value < MIN_VALUE or value > MAX_VALUE:
			return false
	return true


static func from_dict(data: Dictionary) -> StatProfile:
	if not is_valid_dict(data):
		push_error("StatProfile: invalid attribute dictionary")
		return null
	var profile := StatProfile.new()
	for key in ATTRIBUTE_NAMES:
		profile.set(key, int(data[key]))
	return profile
