class_name MatchContext
extends RefCounted

## Read-only snapshot of the match world that the decision brain scores against.
## Kept separate from scenes so decisions can be unit-tested headlessly.

var ball: Ball = null
var views: Array[RigidBody3D] = []
var team_instructions: Dictionary = {}

## Mirrors RulesEngine.state so agents know when play is dead. Starts in play
## so headless agent tests keep steering without an explicit setup call.
var match_state: int = FMEnums.MatchState.PLAYING
var restart_type: int = -1
var restart_side: int = -1
var restart_spot: Vector3 = Vector3.ZERO
var restart_exclusion_radius_m: float = 9.15


func add_view(view: RigidBody3D) -> void:
	views.append(view)


func teammates_of(view: RigidBody3D) -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	for other in views:
		if other != view and other.side == view.side:
			result.append(other)
	return result


func opponents_of(view: RigidBody3D) -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	for other in views:
		if other.side != view.side:
			result.append(other)
	return result


func attack_sign(view: RigidBody3D) -> float:
	return 1.0 if view.side == FMEnums.Side.HOME else -1.0


func goal_for(view: RigidBody3D) -> Vector3:
	var cfg := GameData.config
	return Vector3(attack_sign(view) * cfg.pitch_length_m * 0.5, cfg.goal_height_m * 0.5, 0.0)


func own_goal_for(view: RigidBody3D) -> Vector3:
	var cfg := GameData.config
	return Vector3(-attack_sign(view) * cfg.pitch_length_m * 0.5, cfg.goal_height_m * 0.5, 0.0)


## A player may not touch the ball during a dead-ball restart. A goal kick stays
## restricted for the opposition until the ball clears the penalty area, which
## stops the old "run straight at the spot and shoot" behaviour.
func can_play_ball(view: RigidBody3D) -> bool:
	if match_state == FMEnums.MatchState.RESTART:
		return false
	if restart_type == FMEnums.RestartType.GOAL_KICK and restart_side >= 0 and view.side != restart_side:
		return false
	return true


func ball_carrier() -> RigidBody3D:
	if ball == null:
		return null
	return ball.control_owner


## Closest outfield player to the ball. Used to decide who is allowed to chase
## and who steals control, so the whole team does not converge on one spot.
func nearest_to_ball() -> RigidBody3D:
	if ball == null:
		return null
	var best: RigidBody3D = null
	var best_distance := INF
	for view in views:
		if _is_keeper(view):
			continue
		var distance := flat_distance(view.global_position, ball.global_position)
		if distance < best_distance:
			best_distance = distance
			best = view
	return best


## 0 for the closest team-mate to the ball, 1 for the next closest, and so on.
func ball_chaser_rank(view: RigidBody3D) -> int:
	if ball == null or _is_keeper(view):
		return views.size() + 1
	var my_distance := flat_distance(view.global_position, ball.global_position)
	var rank := 0
	for mate in teammates_of(view):
		if mate == view or _is_keeper(mate):
			continue
		if flat_distance(mate.global_position, ball.global_position) < my_distance:
			rank += 1
	return rank


func _is_keeper(view: RigidBody3D) -> bool:
	return view.player_data != null and view.player_data.role_id == "gk"


func nearest_opponent(view: RigidBody3D, max_distance: float) -> RigidBody3D:
	var nearest: RigidBody3D = null
	var best := max_distance
	for other in opponents_of(view):
		var distance := flat_distance(view.global_position, other.global_position)
		if distance < best:
			best = distance
			nearest = other
	return nearest


func is_pressured(view: RigidBody3D, radius: float) -> bool:
	return nearest_opponent(view, radius) != null


func team_instructions_for(view: RigidBody3D) -> TeamInstructions:
	return team_instructions.get(view.club_id) as TeamInstructions


## A slow oscillation between -1 and 1, biased by the team's tempo instruction.
## Both movement speed and strike pace read this, so matches breathe without
## changing the real-time match clock.
func tempo_pulse(view: RigidBody3D, tuning: Dictionary) -> float:
	var team := team_instructions_for(view)
	var bias := 0.0
	if team != null:
		match team.tempo:
			FMEnums.Tempo.SLOW:
				bias = -1.0
			FMEnums.Tempo.FAST:
				bias = 1.0
	var elapsed := ball.match_time if ball != null else 0.0
	var cycle := maxf(float(tuning.get("tempo_cycle_seconds", 24.0)), 0.1)
	var phase := float(absf(view.club_id.hash() % 1000)) / 1000.0 * TAU
	var wave := sin(elapsed * TAU / cycle + phase)
	return clampf(
		bias * float(tuning.get("tempo_bias_scale", 0.6)) + wave * float(tuning.get("tempo_wave_scale", 0.45)),
		-1.0, 1.0
	)


## Distance to the nearest opponent in the forward lane. Used to reward a
## carrier who has genuine space to dribble into instead of always passing.
func space_ahead(view: RigidBody3D, tuning: Dictionary) -> float:
	var radius := float(tuning.get("dribble_space_radius_m", 14.0))
	var half_width := float(tuning.get("dribble_space_lane_half_width_m", 4.0))
	var sign := attack_sign(view)
	var nearest := radius
	for other in opponents_of(view):
		var forward := (other.global_position.x - view.global_position.x) * sign
		if forward < 0.0 or forward >= radius:
			continue
		if absf(other.global_position.z - view.global_position.z) > half_width:
			continue
		nearest = minf(nearest, forward)
	return nearest


## Pick a team-mate for a pass. The tuning dictionary is StatEffects.context so
## all weights stay in data/stat_effects.json. Short sideways passes to a
## overlapping foot are rejected; the ball should go forward into space.
func best_pass_target(view: RigidBody3D, tuning: Dictionary) -> RigidBody3D:
	var best: RigidBody3D = null
	var best_score := -INF
	var sign := attack_sign(view)
	var forward_weight := float(tuning.get("pass_forward_weight", 0.1))
	var space_weight := float(tuning.get("pass_space_weight", 0.05))
	var distance_penalty := float(tuning.get("pass_distance_penalty_per_m", 0.15))
	var pressure_penalty := float(tuning.get("pass_pressure_penalty", 4.0))
	var pressure_radius := float(tuning.get("pressure_radius_m", 3.0))
	var min_distance := float(tuning.get("pass_min_distance_m", 5.0))
	var too_close_penalty := float(tuning.get("pass_too_close_penalty", 8.0))
	var backward_penalty := float(tuning.get("pass_backward_penalty_per_m", 0.25))
	var lane_radius := float(tuning.get("pass_lane_radius_m", 2.0))
	var lane_penalty := float(tuning.get("pass_lane_penalty", 4.0))
	var wide_weight := float(tuning.get("pass_wide_weight", 0.12))
	var wing_channel := float(tuning.get("wing_channel_m", 18.0))

	for mate in teammates_of(view):
		if _is_keeper(mate):
			continue
		var forward := (mate.global_position.x - view.global_position.x) * sign
		var distance := flat_distance(view.global_position, mate.global_position)
		if distance < min_distance:
			continue
		var space := 20.0
		var marker := nearest_opponent(mate, 100.0)
		if marker != null:
			space = flat_distance(mate.global_position, marker.global_position)
		var score := forward * forward_weight + minf(space, 20.0) * space_weight
		score -= distance * distance_penalty
		if absf(mate.global_position.z) >= wing_channel:
			score += wide_weight * minf(absf(mate.global_position.z), 30.0)
		if forward < 0.0:
			score += forward * backward_penalty
		if nearest_opponent(mate, pressure_radius) != null:
			score -= pressure_penalty
		if _pass_lane_blocked(view, mate, lane_radius):
			score -= lane_penalty
		if score > best_score:
			best_score = score
			best = mate
	return best


## Is an opponent standing in the passing lane? Sampling the segment is enough
## for this prototype and avoids passes straight through the nearest marker.
func _pass_lane_blocked(view: RigidBody3D, mate: RigidBody3D, lane_radius: float) -> bool:
	var start := view.global_position
	start.y = 0.0
	var end := mate.global_position
	end.y = 0.0
	for step in range(1, 5):
		var point := start.lerp(end, float(step) / 5.0)
		for other in views:
			if other == view or other == mate or other.side == view.side:
				continue
			if flat_distance(other.global_position, point) < lane_radius:
				return true
	return false


## A diagonal ball to the far flank. Only genuine lateral switches qualify, so
## the carrier cannot farm SWITCH by hitting the nearest team-mate.
func best_switch_target(view: RigidBody3D, tuning: Dictionary) -> RigidBody3D:
	var best: RigidBody3D = null
	var best_score := -INF
	var sign := attack_sign(view)
	var min_lateral := float(tuning.get("switch_min_lateral_m", 22.0))
	var min_distance := float(tuning.get("switch_min_distance_m", 18.0))
	var max_backward := float(tuning.get("switch_max_backward_m", 8.0))
	var lane_radius := float(tuning.get("pass_lane_radius_m", 2.0))
	for mate in teammates_of(view):
		if _is_keeper(mate):
			continue
		var lateral := mate.global_position.z - view.global_position.z
		if absf(lateral) < min_lateral:
			continue
		var forward := (mate.global_position.x - view.global_position.x) * sign
		if forward < -max_backward:
			continue
		var distance := flat_distance(view.global_position, mate.global_position)
		if distance < min_distance:
			continue
		var space := 20.0
		var marker := nearest_opponent(mate, 100.0)
		if marker != null:
			space = flat_distance(mate.global_position, marker.global_position)
		var score := absf(lateral) * float(tuning.get("switch_lateral_weight", 0.25))
		score += forward * float(tuning.get("switch_forward_weight", 0.1))
		score += minf(space, 20.0) * float(tuning.get("switch_space_weight", 0.08))
		score -= distance * float(tuning.get("switch_distance_penalty_per_m", 0.08))
		if _pass_lane_blocked(view, mate, lane_radius):
			score -= float(tuning.get("pass_lane_penalty", 4.0))
		if score > best_score:
			best_score = score
			best = mate
	return best


## A cross needs a wide carrier in range and a team-mate arriving centrally.
func best_cross_target(view: RigidBody3D, tuning: Dictionary) -> RigidBody3D:
	if absf(view.global_position.z) < float(tuning.get("wing_channel_m", 18.0)):
		return null
	var goal_distance := flat_distance(view.global_position, goal_for(view))
	if goal_distance < float(tuning.get("cross_min_range_m", 8.0)):
		return null
	if goal_distance > float(tuning.get("cross_max_range_m", 32.0)):
		return null
	var best: RigidBody3D = null
	var best_score := -INF
	var sign := attack_sign(view)
	var box_half_width := float(tuning.get("cross_box_half_width_m", 20.0))
	var lane_radius := float(tuning.get("pass_lane_radius_m", 2.0))
	for mate in teammates_of(view):
		if _is_keeper(mate):
			continue
		var forward := (mate.global_position.x - view.global_position.x) * sign
		if forward < -float(tuning.get("cross_allow_behind_m", 6.0)):
			continue
		if absf(mate.global_position.z) > box_half_width:
			continue
		var distance := flat_distance(view.global_position, mate.global_position)
		var space := 20.0
		var marker := nearest_opponent(mate, 100.0)
		if marker != null:
			space = flat_distance(mate.global_position, marker.global_position)
		var score := minf(space, 20.0) * float(tuning.get("pass_space_weight", 0.05))
		score += forward * float(tuning.get("pass_forward_weight", 0.1))
		score -= distance * float(tuning.get("pass_distance_penalty_per_m", 0.15))
		if _pass_lane_blocked(view, mate, lane_radius):
			score -= float(tuning.get("pass_lane_penalty", 4.0))
		if score > best_score:
			best_score = score
			best = mate
	return best


func cross_target_point(view: RigidBody3D, mate: RigidBody3D, tuning: Dictionary) -> Vector3:
	var sign := attack_sign(view)
	var point := mate.global_position + Vector3(sign * float(tuning.get("cross_target_lead_m", 3.0)), 0.0, 0.0)
	point.y = 0.0
	return _clamp_to_pitch(point)


## A wide player behind the carrier on the same flank can burst beyond him.
func can_overlap(view: RigidBody3D, tuning: Dictionary) -> bool:
	if _is_keeper(view) or absf(view.formation_slot.y) < float(tuning.get("overlap_slot_threshold_m", 20.0)):
		return false
	var carrier := ball_carrier()
	if carrier == null or carrier == view or carrier.side != view.side:
		return false
	var sign := attack_sign(view)
	if (carrier.global_position.x - view.global_position.x) * sign < float(tuning.get("overlap_min_behind_m", 2.0)):
		return false
	var flank := signf(view.formation_slot.y)
	if absf(carrier.global_position.z) > float(tuning.get("overlap_flank_tolerance_m", 6.0)):
		if signf(carrier.global_position.z) != flank:
			return false
	return true


func overlap_target(view: RigidBody3D, tuning: Dictionary) -> Vector3:
	var carrier := ball_carrier()
	if carrier == null:
		return view.global_position
	var sign := attack_sign(view)
	var flank := signf(view.formation_slot.y)
	if flank == 0.0:
		flank = signf(view.global_position.z)
	if flank == 0.0:
		flank = 1.0
	var point := carrier.global_position + Vector3(
		sign * float(tuning.get("overlap_advance_m", 14.0)), 0.0,
		flank * float(tuning.get("overlap_width_m", 6.0))
	)
	point.y = 0.0
	return _clamp_to_pitch(point)


func _clamp_to_pitch(point: Vector3) -> Vector3:
	var cfg := GameData.config
	point.x = clampf(point.x, -cfg.pitch_length_m * 0.5, cfg.pitch_length_m * 0.5)
	point.z = clampf(point.z, -cfg.pitch_width_m * 0.5, cfg.pitch_width_m * 0.5)
	return point


static func flat_distance(a: Vector3, b: Vector3) -> float:
	var delta := b - a
	delta.y = 0.0
	return delta.length()
