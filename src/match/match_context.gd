class_name MatchContext
extends RefCounted

## Read-only snapshot of the match world that the decision brain scores against.
## Kept separate from scenes so decisions can be unit-tested headlessly.

var ball: Ball = null
var views: Array[RigidBody3D] = []
var team_instructions: Dictionary = {}


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


func ball_carrier() -> RigidBody3D:
	if ball == null:
		return null
	return ball.control_owner


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


func best_pass_target(view: RigidBody3D) -> RigidBody3D:
	var best: RigidBody3D = null
	var best_score := -INF
	var sign := attack_sign(view)
	for mate in teammates_of(view):
		if mate.player_data != null and mate.player_data.role_id == "gk":
			continue
		var forward := (mate.global_position.x - view.global_position.x) * sign
		var space := 20.0
		var marker := nearest_opponent(mate, 100.0)
		if marker != null:
			space = flat_distance(mate.global_position, marker.global_position)
		var score := forward * 0.1 + minf(space, 20.0) * 0.05
		if score > best_score:
			best_score = score
			best = mate
	return best


static func flat_distance(a: Vector3, b: Vector3) -> float:
	var delta := b - a
	delta.y = 0.0
	return delta.length()
