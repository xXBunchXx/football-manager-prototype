class_name RestartRule
extends RefCounted

## Computes the ball placement for each restart type. Pure geometry so it can
## be asserted headlessly without a scene.

var config: RulesConfig = null


func configure(rules_config: RulesConfig) -> void:
	config = rules_config


func position_for(restart_type: int, ball_pos: Vector3, cfg: MatchConfig) -> Vector3:
	var half_l := cfg.pitch_length_m * 0.5
	var half_w := cfg.pitch_width_m * 0.5
	var y := cfg.ball_radius_m
	var inset := config.value("restart", "boundary_inset_m")
	var goal_sign := 1.0 if ball_pos.x >= 0.0 else -1.0
	var side_z := 1.0 if ball_pos.z >= 0.0 else -1.0

	match restart_type:
		FMEnums.RestartType.KICKOFF:
			return Vector3(0.0, y, 0.0)
		FMEnums.RestartType.THROW_IN:
			var z := (half_w - config.value("restart", "throw_in_offset_m")) * side_z
			return Vector3(clampf(ball_pos.x, -half_l + inset, half_l - inset), y, z)
		FMEnums.RestartType.GOAL_KICK:
			var x := goal_sign * (half_l - config.value("restart", "goal_kick_depth_m"))
			var z_gk := clampf(ball_pos.z, -cfg.goal_width_m * 0.5, cfg.goal_width_m * 0.5)
			return Vector3(x, y, z_gk)
		FMEnums.RestartType.CORNER:
			var x_c := goal_sign * (half_l - config.value("restart", "corner_offset_m"))
			var z_c := (half_w - config.value("restart", "corner_offset_m")) * side_z
			return Vector3(x_c, y, z_c)
		FMEnums.RestartType.PENALTY:
			return Vector3(goal_sign * (half_l - config.value("restart", "penalty_spot_m")), y, 0.0)
		FMEnums.RestartType.FREE_KICK:
			return Vector3(
				clampf(ball_pos.x, -half_l + inset, half_l - inset),
				y,
				clampf(ball_pos.z, -half_w + inset, half_w - inset)
			)
		_:
			return Vector3(0.0, y, 0.0)


func apply(ball: Ball, restart_type: int, ball_pos: Vector3, cfg: MatchConfig) -> Vector3:
	var spot := position_for(restart_type, ball_pos, cfg)
	ball.reset_to(spot)
	return spot
