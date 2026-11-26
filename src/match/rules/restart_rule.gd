class_name RestartRule
extends RefCounted

## Computes the ball placement for each restart type and puts the bodies in a
## legal shape around it. Geometry is pure; body placement is still headless
## because it only reads MatchContext and MatchConfig.

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
			# A goal kick is taken from anywhere in the six-yard box, not just
			# between the posts.
			var goal_half := cfg.goal_area_width_m * 0.5 - inset
			var z_gk := clampf(ball_pos.z, -goal_half, goal_half)
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


## Put every player in a legal shape for the restart. The taker stands just
## behind the ball; opponents stay outside the exclusion circle, and at goal
## kicks and penalties everybody but the taker clears the penalty area.
func position_players(ctx: MatchContext, restart_type: int, spot: Vector3, restart_side: int, cfg: MatchConfig) -> void:
	if ctx == null or restart_side < 0:
		return
	var exclusion := config.value("restart", "restart_exclusion_radius_m")
	var taker_offset := config.value("restart", "taker_offset_m")
	var inset := config.value("restart", "boundary_inset_m")
	var taker := _taker(ctx, restart_type, restart_side, spot)

	for view in ctx.views:
		var position := Vector3.ZERO
		if restart_type == FMEnums.RestartType.KICKOFF:
			position = _kickoff_position(view, ctx, taker_offset)
			if view == taker:
				position = Vector3(-ctx.attack_sign(view) * taker_offset, 1.0, 0.0)
		elif view == taker:
			var direction := Vector3(ctx.attack_sign(view), 0.0, 0.0)
			position = spot - direction * taker_offset
			position.y = 1.0
		else:
			position = _formation_position(view, ctx)
			if restart_type == FMEnums.RestartType.GOAL_KICK or restart_type == FMEnums.RestartType.PENALTY:
				position = _outside_penalty_area(position, spot, cfg, inset)
			var radius := exclusion if view.side != restart_side else taker_offset * 2.0
			position = _outside_circle(position, spot, radius, cfg, inset)
		_place(view, position)


func _taker(ctx: MatchContext, restart_type: int, restart_side: int, spot: Vector3) -> RigidBody3D:
	if restart_type == FMEnums.RestartType.GOAL_KICK:
		for view in ctx.views:
			if view.side == restart_side and _is_keeper(view):
				return view
	var best: RigidBody3D = null
	var best_distance := INF
	for view in ctx.views:
		if view.side != restart_side or _is_keeper(view):
			continue
		var distance := MatchContext.flat_distance(view.global_position, spot)
		if distance < best_distance:
			best_distance = distance
			best = view
	return best


func _kickoff_position(view: RigidBody3D, ctx: MatchContext, taker_offset: float) -> Vector3:
	var slot: Vector2 = view.formation_slot
	var sign := ctx.attack_sign(view)
	var x := sign * slot.x
	# Attacking slots are mirrored back into the team's own half at kick-off.
	if sign * x > -taker_offset:
		x = -x
	return Vector3(x, 1.0, slot.y)


func _formation_position(view: RigidBody3D, ctx: MatchContext) -> Vector3:
	var slot: Vector2 = view.formation_slot
	return Vector3(ctx.attack_sign(view) * slot.x, 1.0, slot.y)


func _outside_penalty_area(position: Vector3, spot: Vector3, cfg: MatchConfig, inset: float) -> Vector3:
	var goal_sign := 1.0 if spot.x >= 0.0 else -1.0
	var boundary := goal_sign * (cfg.pitch_length_m * 0.5 - cfg.penalty_area_depth_m)
	# Inside means between the goal line and the far edge of the box; exit
	# toward midfield, which is the opposite side of the boundary.
	if goal_sign * position.x > goal_sign * boundary:
		position.x = goal_sign * (absf(boundary) - inset)
	return position


func _outside_circle(position: Vector3, spot: Vector3, radius: float, cfg: MatchConfig, inset: float) -> Vector3:
	var away := position - spot
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = Vector3(1.0, 0.0, 0.0)
	if away.length() < radius:
		position = spot + away.normalized() * radius
	var half_l := cfg.pitch_length_m * 0.5 - inset
	var half_w := cfg.pitch_width_m * 0.5 - inset
	position.x = clampf(position.x, -half_l, half_l)
	position.z = clampf(position.z, -half_w, half_w)
	position.y = 1.0
	return position


func _is_keeper(view: RigidBody3D) -> bool:
	return view.player_data != null and view.player_data.role_id == "gk"


func _place(view: RigidBody3D, position: Vector3) -> void:
	view.global_position = position
	view.linear_velocity = Vector3.ZERO
	view.angular_velocity = Vector3.ZERO
	view.last_decision = null
