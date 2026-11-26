class_name TeamInstructions
extends Resource

## Typed team-wide tactical instructions. A flat default applies until a club
## gets an override from data/instructions.json.

const ENUM_FIELDS := {
	"mentality": 3,
	"tempo": 3,
	"pressing": 3,
	"defensive_line": 3,
	"width": 3,
	"passing_style": 3,
}
const ENUM_NAMES := {
	"mentality": ["DEFENSIVE", "BALANCED", "ATTACKING"],
	"tempo": ["SLOW", "STANDARD", "FAST"],
	"pressing": ["LOW", "STANDARD", "HIGH"],
	"defensive_line": ["DEEP", "STANDARD", "HIGH"],
	"width": ["NARROW", "STANDARD", "WIDE"],
	"passing_style": ["SHORT", "MIXED", "DIRECT"],
}

@export var mentality: int = FMEnums.Mentality.BALANCED
@export var tempo: int = FMEnums.Tempo.STANDARD
@export var pressing: int = FMEnums.Pressing.STANDARD
@export var defensive_line: int = FMEnums.DefensiveLine.STANDARD
@export var width: int = FMEnums.WidthMode.STANDARD
@export var passing_style: int = FMEnums.PassingStyle.MIXED


func to_dict() -> Dictionary:
	var result := {}
	for key in ENUM_FIELDS:
		result[key] = int(get(key))
	return result


static func is_valid_dict(data: Dictionary, allow_partial: bool = false) -> bool:
	for key in data:
		if not ENUM_FIELDS.has(key):
			return false
		var raw: Variant = data[key]
		if raw is String:
			if not ENUM_NAMES[key].has(String(raw).to_upper()):
				return false
		elif raw is int or raw is float:
			var value := int(raw)
			if value < 0 or value >= int(ENUM_FIELDS[key]):
				return false
		else:
			return false
	if allow_partial:
		return true
	return data.size() == ENUM_FIELDS.size()


static func from_dict(data: Dictionary) -> TeamInstructions:
	if not is_valid_dict(data):
		push_error("TeamInstructions: invalid instruction dictionary")
		return null
	var result := TeamInstructions.new()
	_apply(result, data)
	return result


func with_overrides(overrides: Dictionary) -> TeamInstructions:
	if not is_valid_dict(overrides, true):
		push_error("TeamInstructions: invalid override dictionary")
		return self
	var copy := duplicate() as TeamInstructions
	_apply(copy, overrides)
	return copy


static func _apply(target: TeamInstructions, data: Dictionary) -> void:
	for key in data:
		var raw: Variant = data[key]
		if raw is String:
			target.set(key, ENUM_NAMES[key].find(String(raw).to_upper()))
		else:
			target.set(key, int(raw))
