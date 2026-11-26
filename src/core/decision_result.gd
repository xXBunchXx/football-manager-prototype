class_name DecisionResult
extends RefCounted

## One decision tick's output. Scores are retained so behaviour can be logged
## and calibrated headlessly.

var action: int = FMEnums.Action.NONE
var target: Vector3 = Vector3.ZERO
var pass_to_id: String = ""
var scores: Dictionary = {}


static func create(action_value: int, target_position: Vector3, score_table: Dictionary, pass_target: String = "") -> DecisionResult:
	var result := DecisionResult.new()
	result.action = action_value
	result.target = target_position
	result.scores = score_table
	result.pass_to_id = pass_target
	return result


func best_action_name() -> String:
	match action:
		FMEnums.Action.SUPPORT: return "support"
		FMEnums.Action.PRESS: return "press"
		FMEnums.Action.CHASE: return "chase"
		FMEnums.Action.DRIBBLE: return "dribble"
		FMEnums.Action.PASS: return "pass"
		FMEnums.Action.SHOOT: return "shoot"
		FMEnums.Action.HEADER: return "header"
		FMEnums.Action.TACKLE: return "tackle"
		FMEnums.Action.MARK: return "mark"
		FMEnums.Action.CLEAR: return "clear"
		FMEnums.Action.CROSS: return "cross"
		FMEnums.Action.SWITCH: return "switch"
		FMEnums.Action.OVERLAP: return "overlap"
		_: return "none"
