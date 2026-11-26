class_name PitchBounds
extends RefCounted

## Pure geometry checks for goals and out-of-play. No scene dependencies so it
## can be asserted directly in headless tests.

enum Result { IN_PLAY, GOAL_HOME, GOAL_AWAY, OUT_TOUCHLINE, OUT_GOAL_LINE }


static func classify(position: Vector3, config: MatchConfig) -> int:
	var half_l := config.pitch_length_m * 0.5
	var half_w := config.pitch_width_m * 0.5

	if absf(position.z) > half_w:
		return Result.OUT_TOUCHLINE

	if absf(position.x) > half_l:
		if absf(position.z) <= config.goal_width_m * 0.5 and position.y <= config.goal_height_m:
			return Result.GOAL_HOME if position.x > 0.0 else Result.GOAL_AWAY
		return Result.OUT_GOAL_LINE

	return Result.IN_PLAY
