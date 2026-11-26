class_name ClockRule
extends RefCounted

## Match clock with stoppage accumulation. Time spent with play stopped is
## banked and added on at the period boundary.

var elapsed_seconds: float = 0.0
var added_seconds: float = 0.0
var stoppage_seconds: float = 0.0


func tick(delta: float, is_playing: bool) -> void:
	if is_playing:
		elapsed_seconds += delta
	else:
		stoppage_seconds += delta


func register_stoppage(seconds: float) -> void:
	stoppage_seconds += maxf(0.0, seconds)


## Banks accumulated stoppage into added time and clears the running tally.
func finalize_period() -> float:
	added_seconds += stoppage_seconds
	stoppage_seconds = 0.0
	return added_seconds


func half_time_reached(config: MatchConfig) -> bool:
	return elapsed_seconds >= config.half_length_seconds + added_seconds * 0.5


func full_time_reached(config: MatchConfig) -> bool:
	return elapsed_seconds >= config.half_length_seconds * float(config.halves) + added_seconds


func formatted() -> String:
	var total := int(elapsed_seconds)
	return "%02d:%02d (+%d)" % [total / 60, total % 60, int(added_seconds)]
