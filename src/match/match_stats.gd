class_name MatchStats
extends RefCounted

## Per-match counters for calibration. The HUD shows only a compact subset;
## the full record is appended to the playtest log at full time.

const SIDES := ["home", "away"]


var data: Dictionary = {}


func _init() -> void:
	reset()


func reset() -> void:
	data = {
		"home": _blank_side(),
		"away": _blank_side(),
	}


func record_kick(side_value: int, is_pass: bool) -> void:
	var key := side_key(side_value)
	var side: Dictionary = data[key]
	if is_pass:
		side["passes"] = int(side["passes"]) + 1
	else:
		side["shots"] = int(side["shots"]) + 1


func record_control(side_value: int, delta: float) -> void:
	var side: Dictionary = data[side_key(side_value)]
	side["control_seconds"] = float(side["control_seconds"]) + delta


func record_event(event: RuleEvent) -> void:
	match event.type:
		RuleEvent.Type.GOAL:
			var side: Dictionary = data[side_key(event.side)]
			side["goals"] = int(side["goals"]) + 1
		RuleEvent.Type.FOUL:
			var offender := 1 - event.side if event.side >= 0 else -1
			if offender < 0:
				return
			var side: Dictionary = data[side_key(offender)]
			side["fouls"] = int(side["fouls"]) + 1
			if event.severity == FMEnums.FoulSeverity.YELLOW:
				side["yellow_cards"] = int(side["yellow_cards"]) + 1
			elif event.severity == FMEnums.FoulSeverity.RED:
				side["red_cards"] = int(side["red_cards"]) + 1


func to_dict() -> Dictionary:
	return {
		"home": (data["home"] as Dictionary).duplicate(),
		"away": (data["away"] as Dictionary).duplicate(),
	}


func summary() -> String:
	return JSON.stringify(to_dict())


static func side_key(side_value: int) -> String:
	return "home" if side_value == FMEnums.Side.HOME else "away"


static func _blank_side() -> Dictionary:
	return {
		"shots": 0,
		"passes": 0,
		"fouls": 0,
		"yellow_cards": 0,
		"red_cards": 0,
		"goals": 0,
		"control_seconds": 0.0,
	}
