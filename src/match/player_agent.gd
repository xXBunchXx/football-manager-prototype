class_name PlayerAgent
extends RefCounted

## Steers one pill toward its current decision target and executes ball actions
## when the ball is within control range. Decisions are refreshed at the config
## interval; steering runs every physics frame for smooth motion.

signal tackle_attempted(player: RigidBody3D)
signal tackle_won(player: RigidBody3D)

var view: RigidBody3D
var brain: DecisionBrain
var ctx: MatchContext
var effects: StatEffects
var decision_timer: float = 0.0
var kick_timer: float = 0.0
var tackle_timer: float = 0.0
var tackle_backoff_timer: float = 0.0


func _init(target_view: RigidBody3D, decision_brain: DecisionBrain, match_ctx: MatchContext, stat_effects: StatEffects) -> void:
	view = target_view
	brain = decision_brain
	ctx = match_ctx
	effects = stat_effects


func physics_tick(delta: float) -> void:
	kick_timer = maxf(0.0, kick_timer - delta)
	tackle_timer = maxf(0.0, tackle_timer - delta)
	tackle_backoff_timer = maxf(0.0, tackle_backoff_timer - delta)
	if view.match_state != null:
		var flat_velocity := Vector3(view.linear_velocity.x, 0.0, view.linear_velocity.z)
		view.match_state.add_distance(flat_velocity.length() * delta)
	# Dead-ball phases are placed by RestartRule; agents must not run off to an
	# old target while the restart is being taken.
	if ctx != null and ctx.match_state != FMEnums.MatchState.PLAYING:
		return
	decision_timer -= delta
	if decision_timer <= 0.0:
		var tempo := ctx.tempo_pulse(view, effects.context)
		var interval := GameData.config.get_decision_interval()
		interval *= 1.0 - tempo * effects.context_value("tempo_decision_scale")
		decision_timer = maxf(interval, delta)
		view.last_decision = brain.decide(view, ctx)
	# A beaten tackler must step off for a moment. Otherwise he keeps choosing
	# TACKLE every decision and instantly steals the ball back, pinning the
	# carrier in place.
	if tackle_backoff_timer > 0.0:
		var carrier := ctx.ball_carrier()
		if carrier != null and carrier != view:
			view.last_decision = DecisionResult.create(
				FMEnums.Action.SUPPORT, _tackle_backoff_target(carrier), view.last_decision.scores, ""
			)
	_steer()
	_execute_ball_action()


func _steer() -> void:
	var decision: DecisionResult = view.last_decision
	if decision == null:
		return
	var cfg := GameData.config
	var target := decision.target
	if ctx != null and not ctx.can_play_ball(view):
		var radius := ctx.restart_exclusion_radius_m
		var away := target - ctx.restart_spot
		away.y = 0.0
		if away.length() < radius:
			if away.length_squared() < 0.001:
				away = Vector3(ctx.attack_sign(view), 0.0, 0.0)
			target = ctx.restart_spot + away.normalized() * radius
	var to_target := target - view.global_position
	to_target.y = 0.0
	var desired := Vector3.ZERO
	if to_target.length() > 0.5:
		desired = to_target.normalized() * _move_speed()
	var current := Vector3(view.linear_velocity.x, 0.0, view.linear_velocity.z)
	var steer := (desired - current) * cfg.player_acceleration * view.mass

	# Without separation every player steers to the same ball/support point and
	# the capsules pile into one another. Push away from nearby bodies; push
	# harder off opponents than teammates so marking still works.
	var separation := Vector3.ZERO
	for other in ctx.views:
		if other == view:
			continue
		var away := view.global_position - other.global_position
		away.y = 0.0
		var distance := away.length()
		if distance <= 0.001 or distance >= cfg.player_separation_radius_m:
			continue
		var strength := 1.0 - distance / cfg.player_separation_radius_m
		if other.side == view.side:
			strength *= cfg.player_separation_team_scale
		separation += away / distance * strength
	var strength_magnitude := separation.length()
	if strength_magnitude > 0.0:
		# Keep the accumulated strength (team-mates push half as hard) but cap
		# the total when several nearby bodies all contribute.
		steer += separation / maxf(strength_magnitude, 1.0) * cfg.player_separation_acceleration * view.mass

	view.apply_central_force(steer)


## Pace actually matters now, and a shared tempo pulse makes the match breathe
## between patient spells and quicker transitions without touching the clock.
func _move_speed() -> float:
	var cfg := GameData.config
	var profile: StatProfile = view.player_data.attributes
	var floor_fraction := effects.context_value("speed_floor_fraction")
	var pace_fraction := clampf(float(profile.pace) / 20.0, 0.0, 1.0)
	var factor := floor_fraction + (1.0 - floor_fraction) * pace_fraction
	if ctx != null:
		factor += ctx.tempo_pulse(view, effects.context) * effects.context_value("speed_tempo_scale")
		var elapsed := ctx.ball.match_time if ctx.ball != null else 0.0
		var period := maxf(effects.context_value("speed_variation_period_seconds"), 0.1)
		var phase := float(absf(view.player_id.hash() % 1000)) / 1000.0 * TAU
		factor += sin(elapsed * TAU / period + phase) * effects.context_value("speed_variation_amplitude")
	if view.match_state != null:
		var deficit := maxf(0.0, effects.context_value("stamina_floor") - view.match_state.stamina)
		factor -= deficit * effects.context_value("speed_stamina_penalty_per_point")
	factor = clampf(factor, effects.context_value("speed_min_fraction"), effects.context_value("speed_max_fraction"))
	return cfg.player_max_speed_mps * factor


func _execute_ball_action() -> void:
	var cfg := GameData.config
	var ball := ctx.ball
	var decision: DecisionResult = view.last_decision
	if ball == null or decision == null:
		return
	if ctx != null and not ctx.can_play_ball(view):
		return
	if tackle_backoff_timer > 0.0:
		return
	var distance := MatchContext.flat_distance(view.global_position, ball.global_position)
	if distance > effects.context_value("ball_control_radius_m"):
		if ball.control_owner == view:
			ball.release_control()
		return
	# A defender who has closed onto the carrier may tackle even though the
	# ball is still at the attacker's feet. Without this exception tackles were
	# chosen by the brain but could never actually win the ball.
	var carrier := ctx.ball_carrier()
	# An overlapping run is off the ball by definition; taking control here would
	# collapse the run back into the carrier and recreate the old scrum.
	if decision.action == FMEnums.Action.OVERLAP and carrier != null and carrier.side == view.side:
		return
	var tackling_carrier: bool = decision.action == FMEnums.Action.TACKLE and carrier != null and carrier != view and carrier.side != view.side and MatchContext.flat_distance(view.global_position, carrier.global_position) <= effects.context_value("tackle_radius_m")

	# Only the closest outfield player may take control. Otherwise several
	# nearby pills fight over the ball each frame and it looks like a scrum.
	if ball.control_owner != view and not tackling_carrier:
		var nearest := ctx.nearest_to_ball()
		if nearest != null and nearest != view:
			return

	# One decision must not fire 60 kicks a second while the ball is still in
	# reach. A short JSON-tuned cooldown gives each pass/shot one clean strike.
	var is_kick := decision.action == FMEnums.Action.SHOOT or decision.action == FMEnums.Action.PASS or decision.action == FMEnums.Action.CROSS or decision.action == FMEnums.Action.SWITCH
	if is_kick and kick_timer > 0.0:
		return
	if is_kick:
		var tempo := ctx.tempo_pulse(view, effects.context) if ctx != null else 0.0
		kick_timer = effects.context_value("kick_cooldown_seconds") * (1.0 - tempo * effects.context_value("tempo_kick_scale"))

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
			ball.apply_player_kick(view, false, forward, _scaled_speed(GameData.config.shot_speed_mps), GameData.config.shot_loft_degrees, _scatter(), 0.0)
			if view.match_state != null:
				view.match_state.shots_taken += 1
			MatchEvents.log_event("%s shoots" % view.player_id)
		FMEnums.Action.PASS:
			ball.release_control()
			var pass_direction := _strike_direction(decision, forward)
			# Scale the strike to the distance so a five-metre pass is not
			# launched at the same speed as a thirty-metre switch.
			var pass_distance := MatchContext.flat_distance(view.global_position, decision.target)
			var tempo := ctx.tempo_pulse(view, effects.context) if ctx != null else 0.0
			var pass_speed := clampf(
				pass_distance / cfg.pass_travel_seconds * (1.0 + tempo * effects.context_value("tempo_pass_scale")),
				cfg.pass_min_speed_mps,
				cfg.pass_speed_mps
			)
			var scatter := _scatter() * effects.context_value("pass_scatter_scale")
			ball.apply_player_kick(view, true, pass_direction, pass_speed, cfg.pass_loft_degrees, scatter, 0.0)
			if view.match_state != null:
				view.match_state.passes_attempted += 1
			MatchEvents.log_event("%s passes to %s" % [view.player_id, decision.pass_to_id])
		FMEnums.Action.CROSS, FMEnums.Action.SWITCH:
			ball.release_control()
			var is_cross := decision.action == FMEnums.Action.CROSS
			var strike_speed := cfg.cross_speed_mps if is_cross else cfg.switch_speed_mps
			var loft := cfg.cross_loft_degrees if is_cross else cfg.switch_loft_degrees
			var tempo := ctx.tempo_pulse(view, effects.context) if ctx != null else 0.0
			strike_speed *= 1.0 + tempo * effects.context_value("tempo_pass_scale")
			# A cross leads the runner, so aim at the decision target rather
			# than snapping back to his current position.
			var cross_direction := decision.target - view.global_position
			cross_direction.y = 0.0
			if cross_direction.length_squared() > 0.001:
				cross_direction = cross_direction.normalized()
			else:
				cross_direction = forward
			ball.apply_player_kick(
				view, true, cross_direction, strike_speed, loft,
				_scatter() * effects.context_value("pass_scatter_scale"), 0.0
			)
			if view.match_state != null:
				view.match_state.passes_attempted += 1
			MatchEvents.log_event("%s %s to %s" % [
				view.player_id, "crosses" if is_cross else "switches play", decision.pass_to_id,
			])
		FMEnums.Action.TACKLE:
			# One challenge, one roll. A lost challenge has a recovery period,
			# so two defenders cannot take turns snapping the ball to their own
			# feet every few frames while the carrier stands still.
			if tackle_timer > 0.0:
				return
			tackle_timer = effects.context_value("tackle_challenge_cooldown_seconds")
			if view.match_state != null:
				view.match_state.tackles_attempted += 1
			tackle_attempted.emit(view)
			if tackling_carrier:
				if not RngService.chance(effects.context_value("tackle_success_chance")):
					tackle_backoff_timer = effects.context_value("tackle_backoff_seconds")
					MatchEvents.log_event("%s is beaten by the carrier" % view.player_id)
					return
			ball.set_control(view, feet)
			tackle_won.emit(view)
			MatchEvents.log_event("%s tackles" % view.player_id)
		FMEnums.Action.DRIBBLE, FMEnums.Action.SUPPORT, FMEnums.Action.CHASE, FMEnums.Action.PRESS, FMEnums.Action.MARK:
			ball.set_control(view, feet)
		FMEnums.Action.OVERLAP:
			return
		_:
			ball.set_control(view, feet)


func _strike_direction(decision: DecisionResult, fallback: Vector3) -> Vector3:
	if ctx == null or decision.pass_to_id.is_empty():
		return fallback
	for mate in ctx.views:
		if mate.player_id == decision.pass_to_id:
			var direction := mate.global_position - view.global_position
			direction.y = 0.0
			if direction.length_squared() > 0.001:
				return direction.normalized()
			break
	return fallback


func _scaled_speed(base_speed: float) -> float:
	var profile: StatProfile = view.player_data.attributes
	var finishing: int = profile.finishing
	var floor_fraction := effects.context_value("speed_floor_fraction")
	return base_speed * (floor_fraction + (1.0 - floor_fraction) * float(finishing) / 20.0)


func _scatter() -> float:
	var profile: StatProfile = view.player_data.attributes
	var composure: int = profile.composure
	return float(20 - composure) * effects.context_value("scatter_degrees_per_missing_composure")


func _tackle_backoff_target(carrier: RigidBody3D) -> Vector3:
	var away := view.global_position - carrier.global_position
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = ctx.own_goal_for(view) - carrier.global_position
		away.y = 0.0
	if away.length_squared() < 0.001:
		away = Vector3(ctx.attack_sign(view), 0.0, 0.0)
	var distance := effects.context_value("tackle_backoff_distance_m")
	var target := carrier.global_position + away.normalized() * distance
	target.y = 0.0
	return target
