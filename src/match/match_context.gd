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


func best_pass_target(view: RigidBody3D, forward_weight: float, space_weight: float) -> RigidBody3D:
	var best: RigidBody3D = null
	var best_score := -INF
	var sign := attack_sign(view)
	for mate in teammates_of(view):
		if _is_keeper(mate):
			continue
		var forward := (mate.global_position.x - view.global_position.x) * sign
		var space := 20.0
		var marker := nearest_opponent(mate, 100.0)
		if marker != null:
			space = flat_distance(mate.global_position, marker.global_position)
		var score := forward * forward_weight + minf(space, 20.0) * space_weight
		if score > best_score:
			best_score = score
			best = mate
	return best


static func flat_distance(a: Vector3, b: Vector3) -> float:
	var delta := b - a
	delta.y = 0.0
	return delta.length()
