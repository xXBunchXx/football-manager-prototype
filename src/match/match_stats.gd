class_name MatchStats
extends RefCounted

## Team and per-player counters for calibration. The HUD shows a compact subset;
## the full record is saved with the match and can be analysed in bulk.

const SIDES := ["home", "away"]


var data: Dictionary = {}


func _init() -> void:
	reset()


func reset() -> void:
	data = {
		"home": _blank_side(),
		"away": _blank_side(),
		"players": {},
	}


## is_pass covers PASS, CROSS and SWITCH. action_key is the DecisionResult name
## so the analysis can separate ordinary passes from wide play and switches.
func record_kick(side_value: int, is_pass: bool, action_key: String = "", player_id: String = "", target_id: String = "") -> void:
	var side: Dictionary = data[side_key(side_value)]
	if is_pass:
		side["passes"] = int(side["passes"]) + 1
		side["passes_attempted"] = int(side["passes_attempted"]) + 1
		if action_key == "cross":
			side["crosses"] = int(side["crosses"]) + 1
		elif action_key == "switch":
			side["switches"] = int(side["switches"]) + 1
	else:
		side["shots"] = int(side["shots"]) + 1
	if player_id.is_empty():
		return
	var player := _ensure_player(player_id, side_value)
	if is_pass:
		player["passes_attempted"] = int(player["passes_attempted"]) + 1
		if action_key == "cross":
			player["crosses"] = int(player["crosses"]) + 1
		elif action_key == "switch":
			player["switches"] = int(player["switches"]) + 1
		if not target_id.is_empty():
			player["pass_targets"].append(target_id)
	else:
		player["shots_taken"] = int(player["shots_taken"]) + 1


## Legacy two-argument form is kept for tests. Passing a player id also builds
## the per-player possession record used by the analysis screen.
func record_control(side_value: int, delta: float, player_id: String = "") -> void:
	var side: Dictionary = data[side_key(side_value)]
	side["control_seconds"] = float(side["control_seconds"]) + delta
	if player_id.is_empty():
		return
	var player := _ensure_player(player_id, side_value)
	player["control_seconds"] = float(player["control_seconds"]) + delta


## Scale synthetic possession seconds so both sides together account for one
## match. Live matches do not call this: their control is measured in real time.
func normalize_control(total_seconds: float) -> void:
	var current := float((data["home"] as Dictionary)["control_seconds"]) + float((data["away"] as Dictionary)["control_seconds"])
	if current <= 0.0 or total_seconds <= 0.0:
		return
	var factor := total_seconds / current
	for side_value: int in [FMEnums.Side.HOME, FMEnums.Side.AWAY]:
		var side: Dictionary = data[side_key(side_value)]
		side["control_seconds"] = float(side["control_seconds"]) * factor
	for player_id in (data["players"] as Dictionary):
		var player: Dictionary = data["players"][player_id]
		player["control_seconds"] = float(player["control_seconds"]) * factor


func record_touch(player_id: String, side_value: int) -> void:
	var side: Dictionary = data[side_key(side_value)]
	side["touches"] = int(side["touches"]) + 1
	if player_id.is_empty():
		return
	_ensure_player(player_id, side_value)["touches"] = int(_ensure_player(player_id, side_value)["touches"]) + 1


func record_pass_completion(kicker_id: String, receiver_id: String, side_value: int, intended_target_id: String = "") -> void:
	var side: Dictionary = data[side_key(side_value)]
	side["passes_completed"] = int(side["passes_completed"]) + 1
	if not intended_target_id.is_empty() and intended_target_id == receiver_id:
		side["passes_to_target"] = int(side["passes_to_target"]) + 1
	# A pass is completed by the kicker, not by both players: crediting the
	# receiver as well doubled per-player completions and produced >100% rates.
	if not kicker_id.is_empty():
		var kicker := _ensure_player(kicker_id, side_value)
		kicker["passes_completed"] = int(kicker["passes_completed"]) + 1
	if not receiver_id.is_empty() and not intended_target_id.is_empty() and intended_target_id == receiver_id:
		var receiver := _ensure_player(receiver_id, side_value)
		receiver["passes_to_target"] = int(receiver["passes_to_target"]) + 1


func record_tackle_attempt(player_id: String, side_value: int) -> void:
	var side: Dictionary = data[side_key(side_value)]
	side["tackles"] = int(side["tackles"]) + 1
	if player_id.is_empty():
		return
	_ensure_player(player_id, side_value)["tackles"] = int(_ensure_player(player_id, side_value)["tackles"]) + 1


func record_tackle_win(player_id: String, side_value: int) -> void:
	var side: Dictionary = data[side_key(side_value)]
	side["tackle_wins"] = int(side["tackle_wins"]) + 1
	if player_id.is_empty():
		return
	_ensure_player(player_id, side_value)["tackle_wins"] = int(_ensure_player(player_id, side_value)["tackle_wins"]) + 1


func record_dribble(player_id: String, side_value: int, succeeded: bool) -> void:
	var side: Dictionary = data[side_key(side_value)]
	side["dribbles"] = int(side["dribbles"]) + 1
	if succeeded:
		side["dribbles_succeeded"] = int(side["dribbles_succeeded"]) + 1
	if player_id.is_empty():
		return
	var player := _ensure_player(player_id, side_value)
	player["dribbles"] = int(player["dribbles"]) + 1
	if succeeded:
		player["dribbles_succeeded"] = int(player["dribbles_succeeded"]) + 1


func record_shot_on_target(player_id: String, side_value: int) -> void:
	data[side_key(side_value)]["shots_on_target"] = int(data[side_key(side_value)]["shots_on_target"]) + 1
	if not player_id.is_empty():
		_ensure_player(player_id, side_value)["shots_on_target"] = int(_ensure_player(player_id, side_value)["shots_on_target"]) + 1


func record_event(event: RuleEvent) -> void:
	match event.type:
		RuleEvent.Type.GOAL:
			var side: Dictionary = data[side_key(event.side)]
			side["goals"] = int(side["goals"]) + 1
			if not event.offender_id.is_empty():
				_ensure_player(event.offender_id, event.side)["goals"] = int(_ensure_player(event.offender_id, event.side)["goals"]) + 1
		RuleEvent.Type.SAVE:
			var side: Dictionary = data[side_key(event.side)]
			side["saves"] = int(side["saves"]) + 1
			if not event.offender_id.is_empty():
				_ensure_player(event.offender_id, event.side)["saves"] = int(_ensure_player(event.offender_id, event.side)["saves"]) + 1
		RuleEvent.Type.FOUL:
			var offender := 1 - event.side if event.side >= 0 else -1
			if offender < 0:
				return
			var side: Dictionary = data[side_key(offender)]
			side["fouls"] = int(side["fouls"]) + 1
			var player: Dictionary = {}
			if not event.offender_id.is_empty():
				player = _ensure_player(event.offender_id, offender)
				player["fouls"] = int(player["fouls"]) + 1
			if event.severity == FMEnums.FoulSeverity.YELLOW:
				side["yellow_cards"] = int(side["yellow_cards"]) + 1
				if not player.is_empty():
					player["yellow_cards"] = int(player["yellow_cards"]) + 1
			elif event.severity == FMEnums.FoulSeverity.RED:
				side["red_cards"] = int(side["red_cards"]) + 1
				if not player.is_empty():
					player["red_cards"] = int(player["red_cards"]) + 1


func to_dict() -> Dictionary:
	var players: Dictionary = {}
	for player_id in (data["players"] as Dictionary):
		players[player_id] = (data["players"][player_id] as Dictionary).duplicate()
	return {
		"home": (data["home"] as Dictionary).duplicate(),
		"away": (data["away"] as Dictionary).duplicate(),
		"players": players,
	}


func summary() -> String:
	return JSON.stringify(to_dict())


func get_side(side_value: int) -> Dictionary:
	return data[side_key(side_value)]


func get_player(player_id: String) -> Dictionary:
	return (data["players"] as Dictionary).get(player_id, {})


static func side_key(side_value: int) -> String:
	return "home" if side_value == FMEnums.Side.HOME else "away"


func _ensure_player(player_id: String, side_value: int) -> Dictionary:
	var players: Dictionary = data["players"]
	if not players.has(player_id):
		players[player_id] = _blank_player(player_id, side_key(side_value))
	return players[player_id]


static func _blank_side() -> Dictionary:
	return {
		"shots": 0,
		"shots_on_target": 0,
		"passes": 0,
		"passes_attempted": 0,
		"passes_completed": 0,
		"passes_to_target": 0,
		"crosses": 0,
		"switches": 0,
		"dribbles": 0,
		"dribbles_succeeded": 0,
		"touches": 0,
		"saves": 0,
		"tackles": 0,
		"tackle_wins": 0,
		"fouls": 0,
		"yellow_cards": 0,
		"red_cards": 0,
		"goals": 0,
		"control_seconds": 0.0,
	}


static func _blank_player(player_id: String, side: String) -> Dictionary:
	var result := _blank_side()
	result.erase("shots")
	result["shots_taken"] = 0
	result["goals"] = 0
	result["pass_targets"] = []
	result["player_id"] = player_id
	result["side"] = side
	return result
