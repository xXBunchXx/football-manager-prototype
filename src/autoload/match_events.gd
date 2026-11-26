extends Node

## Signal bus plus a bounded log. Systems emit here; UI listens.

signal event_logged(text: String)
signal goal_scored(scorer_id: String, team_id: String, elapsed_seconds: float)
signal ball_kicked(player_id: String, action: int, power: float)
signal foul_called(player_id: String, severity: int)
signal match_state_changed(state: int)

const MAX_RECENT := 50

var recent: Array[String] = []


func log_event(text: String) -> void:
	recent.append(text)
	if recent.size() > MAX_RECENT:
		recent.remove_at(0)
	event_logged.emit(text)


func clear() -> void:
	recent.clear()
