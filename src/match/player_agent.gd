class_name PlayerAgent
extends RefCounted

## Steers one pill toward its current decision target and executes ball actions
## when the ball is within control range. Decisions are refreshed at the config
## interval; steering runs every physics frame for smooth motion.

var view: RigidBody3D
var brain: DecisionBrain
var ctx: MatchContext
var effects: StatEffects
var decision_timer: float = 0.0


func _init(target_view: RigidBody3D, decision_brain: DecisionBrain, match_ctx: MatchContext, stat_effects: StatEffects) -> void:
	view = target_view
	brain = decision_brain
	ctx = match_ctx
	effects = stat_effects


func physics_tick(delta: float) -> void:
	decision_timer -= delta
	if decision_timer <= 0.0:
		decision_timer = GameData.config.get_decision_interval()
		view.last_decision = brain.decide(view, ctx)
	_steer()
	_execute_ball_action()


func _steer() -> void:
	var decision: DecisionResult = view.last_decision
	if decision == null:
		return
	var cfg := GameData.config
	var to_target := decision.target - view.global_position
	to_target.y = 0.0
	var desired := Vector3.ZERO
	if to_target.length() > 0.5:
		desired = to_target.normalized() * cfg.player_max_speed_mps
	var current := Vector3(view.linear_velocity.x, 0.0, view.linear_velocity.z)
	var steer := (desired - current) * cfg.player_acceleration * view.mass
	view.apply_central_force(steer)


func _execute_ball_action() -> void:
	var ball := ctx.ball
	var decision: DecisionResult = view.last_decision
	if ball == null or decision == null:
		return
	var distance := MatchContext.flat_distance(view.global_position, ball.global_position)
	if distance > effects.context_value("ball_control_radius_m"):
		if ball.control_owner == view:
			ball.release_control()
		return

	var forward := decision.target - view.global_position
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = ctx.goal_for(view) - view.global_position
		forward.y = 0.0
	forward = forward.normalized()
	var feet := view.global_position + forward * GameData.config.control_offset_m
	feet.y = GameData.config.ball_radius_m

	match decision.action:
		FMEnums.Action.SHOOT:
			ball.release_control()
			ball.apply_kick(forward, _scaled_speed(GameData.config.shot_speed_mps), GameData.config.shot_loft_degrees, _scatter(), 0.0)
			MatchEvents.log_event("%s shoots" % view.player_id)
		FMEnums.Action.PASS:
			ball.release_control()
			var pass_direction := forward
			if decision.pass_to_id != "":
				for mate in ctx.views:
					if mate.player_id == decision.pass_to_id:
						pass_direction = mate.global_position - view.global_position
						pass_direction.y = 0.0
						pass_direction = pass_direction.normalized()
			ball.apply_kick(pass_direction, GameData.config.pass_speed_mps, GameData.config.pass_loft_degrees, _scatter() * 0.5, 0.0)
			MatchEvents.log_event("%s passes to %s" % [view.player_id, decision.pass_to_id])
		FMEnums.Action.DRIBBLE, FMEnums.Action.SUPPORT, FMEnums.Action.CHASE, FMEnums.Action.PRESS, FMEnums.Action.MARK, FMEnums.Action.TACKLE:
			ball.set_control(view, feet)
		_:
			ball.set_control(view, feet)


func _scaled_speed(base_speed: float) -> float:
	var profile: StatProfile = view.player_data.attributes
	var finishing: int = profile.finishing
	var floor_fraction := effects.context_value("speed_floor_fraction")
	return base_speed * (floor_fraction + (1.0 - floor_fraction) * float(finishing) / 20.0)


func _scatter() -> float:
	var profile: StatProfile = view.player_data.attributes
	var composure: int = profile.composure
	return float(20 - composure) * effects.context_value("scatter_degrees_per_missing_composure")
