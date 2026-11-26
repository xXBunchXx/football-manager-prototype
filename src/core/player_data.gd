class_name PlayerData
extends Resource

## Immutable player definition. Per-match mutable values belong in PlayerState.

const MIN_AGE := 15
const MAX_AGE := 40
const POSITION_COUNT := 10

const REQUIRED_KEYS := [
	"id", "first_name", "last_name", "age", "preferred_foot", "positions", "attributes",
]

@export var id: String = ""
@export var first_name: String = ""
@export var last_name: String = ""
@export var known_as: String = ""
@export var age: int = 20
@export var nationality: String = ""
@export var preferred_foot: int = FMEnums.Foot.RIGHT
@export var positions: Array[int] = []
@export var role_id: String = ""
@export var attributes: StatProfile = StatProfile.new()


func display_name() -> String:
	if known_as != "":
		return known_as
	return "%s %s" % [first_name, last_name]


func to_dict() -> Dictionary:
	return {
		"id": id,
		"first_name": first_name,
		"last_name": last_name,
		"known_as": known_as,
		"age": age,
		"nationality": nationality,
		"preferred_foot": preferred_foot,
		"positions": positions.duplicate(),
		"role_id": role_id,
		"attributes": attributes.to_dict(),
	}


static func from_dict(data: Dictionary) -> PlayerData:
	if not FixtureLoader.has_keys(data, REQUIRED_KEYS):
		push_error("PlayerData: missing required keys")
		return null
	if age_invalid(data):
		return null
	var profile := StatProfile.from_dict(data["attributes"])
	if profile == null:
		return null
	var parsed_positions := parse_positions(data["positions"])
	if parsed_positions.is_empty():
		return null

	var player := PlayerData.new()
	player.id = String(data["id"])
	player.first_name = String(data["first_name"])
	player.last_name = String(data["last_name"])
	player.known_as = String(data.get("known_as", ""))
	player.age = int(data["age"])
	player.nationality = String(data.get("nationality", ""))
	player.preferred_foot = int(data["preferred_foot"])
	player.positions = parsed_positions
	player.role_id = String(data.get("role_id", ""))
	player.attributes = profile
	return player


static func age_invalid(data: Dictionary) -> bool:
	var raw: Variant = data["age"]
	if not (raw is int or raw is float):
		push_error("PlayerData: age must be numeric")
		return true
	var value := int(raw)
	if value < MIN_AGE or value > MAX_AGE:
		push_error("PlayerData: age %d outside %d..%d" % [value, MIN_AGE, MAX_AGE])
		return true
	return false


static func parse_positions(raw: Variant) -> Array[int]:
	var result: Array[int] = []
	if not (raw is Array):
		push_error("PlayerData: positions must be an array")
		return result
	for item in raw:
		if not (item is int or item is float):
			push_error("PlayerData: position value must be numeric")
			return []
		var value := int(item)
		if value < 0 or value >= POSITION_COUNT:
			push_error("PlayerData: position %d out of range" % value)
			return []
		result.append(value)
	if result.is_empty():
		push_error("PlayerData: at least one position is required")
	return result
