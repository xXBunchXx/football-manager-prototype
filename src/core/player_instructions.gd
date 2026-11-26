class_name PlayerInstructions
extends Resource

## Deep, typed individual tactical instructions. Values are authored once as a
## role baseline (see InstructionDefaults) and optionally overridden per player.

const ENUM_FIELDS := {
	"duty": 3,
	"support_depth": 3,
	"width": 3,
	"runs": 3,
	"pressing": 3,
	"tackle_aggression": 3,
	"passing_risk": 3,
}
const ENUM_NAMES := {
	"duty": ["DEFEND", "SUPPORT", "ATTACK"],
	"support_depth": ["DEEP", "STANDARD", "ADVANCED"],
	"width": ["NARROW", "STANDARD", "WIDE"],
	"runs": ["HOLD", "BALANCED", "FORWARD"],
	"pressing": ["LOW", "STANDARD", "HIGH"],
	"tackle_aggression": ["CAUTIOUS", "BALANCED", "AGGRESSIVE"],
	"passing_risk": ["SAFE", "BALANCED", "RISKY"],
}
const BOOL_FIELDS := ["shoot_on_sight", "man_mark"]

@export var duty: int = FMEnums.Duty.SUPPORT
@export var support_depth: int = FMEnums.SupportDepth.STANDARD
@export var width: int = FMEnums.WidthMode.STANDARD
@export var runs: int = FMEnums.Runs.BALANCED
@export var pressing: int = FMEnums.Pressing.STANDARD
@export var tackle_aggression: int = FMEnums.TackleAggression.BALANCED
@export var passing_risk: int = FMEnums.PassingRisk.BALANCED
@export var shoot_on_sight: bool = false
@export var man_mark: bool = false


func to_dict() -> Dictionary:
	var result := {}
	for key in ENUM_FIELDS:
		result[key] = int(get(key))
	for key in BOOL_FIELDS:
		result[key] = bool(get(key))
	return result


static func is_valid_dict(data: Dictionary, allow_partial: bool = false) -> bool:
	for key in data:
		if ENUM_FIELDS.has(key):
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
		elif BOOL_FIELDS.has(key):
			if not (data[key] is bool):
				return false
		else:
			return false  # Unknown key: almost always a typo.
	if allow_partial:
		return true
	return data.size() == ENUM_FIELDS.size() + BOOL_FIELDS.size()


static func from_dict(data: Dictionary) -> PlayerInstructions:
	if not is_valid_dict(data):
		push_error("PlayerInstructions: invalid instruction dictionary")
		return null
	var result := PlayerInstructions.new()
	_apply(result, data)
	return result


## Returns a copy with only the given keys changed. Partial dictionaries are
## expected here; unknown keys are rejected so JSON typo's cannot slip through.
func with_overrides(overrides: Dictionary) -> PlayerInstructions:
	if not is_valid_dict(overrides, true):
		push_error("PlayerInstructions: invalid override dictionary")
		return self
	var copy := duplicate() as PlayerInstructions
	_apply(copy, overrides)
	return copy


static func _apply(target: PlayerInstructions, data: Dictionary) -> void:
	for key in data:
		if ENUM_FIELDS.has(key):
			var raw: Variant = data[key]
			if raw is String:
				target.set(key, ENUM_NAMES[key].find(String(raw).to_upper()))
			else:
				target.set(key, int(raw))
		else:
			target.set(key, data[key])
