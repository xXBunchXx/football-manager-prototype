class_name DecisionBrain
extends RefCounted

## Utility scoring brain. Every candidate action is scored from attributes,
## instructions, physical state and context; the highest score wins.

const ACTION_TO_ENUM := {
	"shoot": FMEnums.Action.SHOOT,
	"pass": FMEnums.Action.PASS,
	"dribble": FMEnums.Action.DRIBBLE,
	"press": FMEnums.Action.PRESS,
	"tackle": FMEnums.Action.TACKLE,
	"support": FMEnums.Action.SUPPORT,
	"chase": FMEnums.Action.CHASE,
	"mark": FMEnums.Action.MARK,
}
const EXERTION_KEYS := ["press", "chase", "dribble", "tackle"]

var effects: StatEffects


func _init(stat_effects: StatEffects) -> void:
	effects = stat_effects


func decide(view: RigidBody3D, ctx: MatchContext) -> DecisionResult:
	var profile: StatProfile = view.player_data.attributes
	var instructions: PlayerInstructions = view.instructions
	var state: PlayerState = view.match_state

	var scores := {}
	for key in StatEffects.ACTION_KEYS:
		var score := effects.base_score(key)
		score += effects.attribute_score(key, profile)
		score += _instruction_score(key, instructions)
		score += _stamina_score(key, state)
		score += _context_score(key, view, ctx, instructions)
		scores[key] = score

	var best_key := ""
	var best_score := -INF
	for key in scores:
		var value := float(scores[key])
		if value > best_score:
			best_score = value
			best_key = String(key)

	# A pass with no receiver is a kick into nowhere. Reject it and fall back to
	# the next useful action (usually a dribble) instead of launching the ball.
	var pass_mate: RigidBody3D = null
	if best_key == "pass":
		pass_mate = ctx.best_pass_target(view, effects.context)
		if pass_mate == null:
			scores["pass"] = -INF
			best_key = ""
			best_score = -INF
			for fallback_key in scores:
				var fallback_value := float(scores[fallback_key])
				if fallback_value > best_score:
					best_score = fallback_value
					best_key = String(fallback_key)

	var target := _target_for(best_key, view, ctx, instructions)
	var pass_to := ""
	if best_key == "pass" and pass_mate != null:
		pass_to = pass_mate.player_id
		target = pass_mate.global_position
	return DecisionResult.create(ACTION_TO_ENUM[best_key], target, scores, pass_to)


func _instruction_score(key: String, instructions: PlayerInstructions) -> float:
	var score := 0.0
	match instructions.duty:
		FMEnums.Duty.ATTACK:
			score += effects.modifier("duty_attack", key)
		FMEnums.Duty.DEFEND:
			score += effects.modifier("duty_defend", key)
	match instructions.passing_risk:
		FMEnums.PassingRisk.RISKY:
			score += effects.modifier("passing_risk_risky", key)
		FMEnums.PassingRisk.SAFE:
			score += effects.modifier("passing_risk_safe", key)
	match instructions.pressing:
		FMEnums.Pressing.HIGH:
			score += effects.modifier("pressing_high", key)
		FMEnums.Pressing.LOW:
			score += effects.modifier("pressing_low", key)
	match instructions.tackle_aggression:
		FMEnums.TackleAggression.AGGRESSIVE:
			score += effects.modifier("tackle_aggressive", key)
		FMEnums.TackleAggression.CAUTIOUS:
			score += effects.modifier("tackle_cautious", key)
	# Dribble appetite is applied in _context_score only when the ball is at
	# the player's feet; otherwise attackers would walk to the goal without it.
	if key != "dribble":
		match instructions.runs:
			FMEnums.Runs.FORWARD:
				score += effects.modifier("runs_forward", key)
			FMEnums.Runs.HOLD:
				score += effects.modifier("runs_hold", key)
	if instructions.man_mark:
		score += effects.modifier("man_mark", key)
	return score


func _stamina_score(key: String, state: PlayerState) -> float:
	var floor_value := effects.context_value("stamina_floor")
	if state.stamina >= floor_value:
		return 0.0
	var deficit := floor_value - state.stamina
	var scale := effects.context_value("stamina_penalty_active_scale") if EXERTION_KEYS.has(key) else effects.context_value("stamina_penalty_passive_scale")
	return -deficit * effects.context_value("stamina_penalty_per_point") * scale


func _context_score(key: String, view: RigidBody3D, ctx: MatchContext, instructions: PlayerInstructions) -> float:
	var score := 0.0
	var ball_position := ctx.ball.global_position if ctx.ball != null else view.global_position
	var ball_distance := MatchContext.flat_distance(view.global_position, ball_position)
	var in_control_range := ball_distance <= effects.context_value("ball_control_radius_m")
	var is_carrier := ctx.ball_carrier() == view
	match key:
		"shoot":
			# Shooting is only relevant when the ball is actually at the player's
			# feet. Without this gate, shoot_on_sight makes attackers run to the
			# opponent goal from the other end of the pitch and stay there.
			var reach := effects.context_value("ball_control_radius_m")
			if MatchContext.flat_distance(view.global_position, ball_position) <= reach:
				if instructions.shoot_on_sight:
					score += effects.modifier("shoot_on_sight", "shoot")
				var distance := MatchContext.flat_distance(view.global_position, ctx.goal_for(view))
				var radius := effects.context_value("shoot_range_m")
				if distance < radius:
					score += effects.context_value("shoot_near_goal_bonus") * (1.0 - distance / radius)
					# An unmarked striker in range should shoot rather than keep
					# recycling the ball; a pressured one should still pass.
					if ctx.is_pressured(view, effects.context_value("pressure_radius_m")):
						score -= effects.context_value("shoot_pressure_penalty")
					else:
						score += effects.context_value("shoot_unpressured_bonus")
		"dribble":
			var reach := effects.context_value("ball_control_radius_m")
			if MatchContext.flat_distance(view.global_position, ball_position) <= reach:
				match instructions.runs:
					FMEnums.Runs.FORWARD:
						score += effects.modifier("runs_forward", "dribble")
					FMEnums.Runs.HOLD:
						score += effects.modifier("runs_hold", "dribble")
		"press", "chase":
			var distance := MatchContext.flat_distance(view.global_position, ball_position)
			var radius := effects.context_value("press_radius_m")
			# Only the closest team-mate should chase; the rest hold shape or
			# pass. This stops the whole side converging on the ball.
			var rank := ctx.ball_chaser_rank(view)
			if distance < radius:
				score += effects.context_value("press_proximity_bonus") * (1.0 - distance / radius)
				if rank == 0:
					score += effects.context_value("chase_nearest_bonus")
				else:
					score -= float(rank) * effects.context_value("chase_rank_penalty_per_place")
			elif rank != 0:
				score -= effects.context_value("chase_out_of_range_penalty")
		"tackle":
			var carrier := ctx.ball_carrier()
			if carrier != null and carrier != view and carrier.side != view.side:
				var distance := MatchContext.flat_distance(view.global_position, carrier.global_position)
				if distance < effects.context_value("tackle_radius_m"):
					# Only the closest defender on each side challenges. Without
					# this, every nearby pill picks TACKLE and the carrier ends up
					# pinned by a scrum of two or three markers.
					var rank := ctx.ball_chaser_rank(view)
					if rank == 0:
						score += effects.context_value("tackle_proximity_bonus")
					else:
						score -= float(rank) * effects.context_value("tackle_rank_penalty_per_place")
		"pass":
			if ctx.is_pressured(view, effects.context_value("pressure_radius_m")):
				score += effects.context_value("pressure_pass_bonus")
		"mark":
			if instructions.man_mark:
				# A delegated marker only follows an opponent inside his own
				# defensive zone. Chasing one all over the pitch produced the
				# tight, constant pairing the whole back line got pulled into.
				var opponent := ctx.nearest_opponent(view, 100.0)
				var sign := ctx.attack_sign(view)
				var anchor := Vector3(sign * view.formation_slot.x, 0.0, view.formation_slot.y)
				if opponent == null or MatchContext.flat_distance(opponent.global_position, anchor) > effects.context_value("mark_zone_radius_m"):
					score -= effects.context_value("mark_out_of_zone_penalty")
				else:
					score += effects.context_value("mark_proximity_bonus")
	if key == "mark" and not instructions.man_mark:
		# Marking is a delegated job, not a generic fallback for every defender.
		score -= effects.context_value("mark_unassigned_penalty")
	if key == "pass" or key == "dribble" or key == "shoot":
		if not in_control_range:
			# Without this, dribble scores highly from 30 m away and every
			# outfielder "dribbles" toward a loose ball as one mob.
			score -= effects.context_value("skill_action_out_of_range_penalty")
	if is_carrier:
		# A player who owns the ball cannot tackle himself. This was the real
		# cause of the kick-off scrum: an aggressive carrier kept choosing
		# TACKLE, snapped the ball to his own feet and stood still for 15s.
		if key == "tackle":
			return -INF
		# Once the ball is at a player's feet, reward an on-ball action instead
		# of passive control: without this, support/chase win and play stalls.
		if key == "pass" or key == "dribble":
			score += effects.context_value("controlled_skill_action_bonus")
			if key == "pass":
				score += effects.context_value("controlled_pass_bonus")
		elif key == "support" or key == "chase" or key == "press" or key == "mark":
			score += effects.context_value("controlled_other_action_penalty")
	return score


func _target_for(key: String, view: RigidBody3D, ctx: MatchContext, instructions: PlayerInstructions) -> Vector3:
	var cfg := GameData.config
	var ball_position := ctx.ball.global_position if ctx.ball != null else view.global_position
	match key:
		"shoot":
			return ctx.goal_for(view)
		"chase", "press", "tackle":
			var carrier := ctx.ball_carrier()
			return carrier.global_position if carrier != null else ball_position
		"dribble":
			if MatchContext.flat_distance(view.global_position, ball_position) > effects.context_value("ball_control_radius_m"):
				return ball_position
			return ctx.goal_for(view).lerp(view.global_position, 1.0 - effects.context_value("dribble_advance_m") / cfg.pitch_length_m)
		"mark":
			var opponent := ctx.nearest_opponent(view, 100.0)
			if opponent == null:
				return ball_position
			# Stand goal-side rather than on top of the opponent, so a marker
			# stays between the ball and his goal instead of glued to a pill.
			var to_own_goal := ctx.own_goal_for(view) - opponent.global_position
			to_own_goal.y = 0.0
			if to_own_goal.length_squared() < 0.001:
				to_own_goal = Vector3(-ctx.attack_sign(view), 0.0, 0.0)
			var target := opponent.global_position + to_own_goal.normalized() * effects.context_value("mark_stand_off_m")
			target.y = 0.0
			return target
		"support":
			var sign := ctx.attack_sign(view)
			if view.player_data != null and view.player_data.role_id == "gk":
				var own_goal := ctx.own_goal_for(view)
				var line_x := own_goal.x + sign * effects.context_value("gk_line_depth_m")
				var lateral := clampf(
					ball_position.z * effects.context_value("gk_lateral_follow_scale"),
					-cfg.goal_width_m * 0.5, cfg.goal_width_m * 0.5
				)
				# Track a shot's projected crossing point instead of just the
				# ball's current z; otherwise every shot at the corners is free.
				if ctx.ball != null:
					var velocity := ctx.ball.linear_velocity
					var goal_direction := signf(own_goal.x - ball_position.x)
					var to_goal := absf(own_goal.x - ball_position.x)
					if to_goal < effects.context_value("gk_intercept_max_distance_m") and absf(velocity.x) > 0.1 and signf(velocity.x) == goal_direction:
						var time_to_line := to_goal / absf(velocity.x)
						var predicted_z := clampf(
							ball_position.z + velocity.z * time_to_line,
							-cfg.goal_width_m * 0.5, cfg.goal_width_m * 0.5
						)
						return Vector3(line_x, 0.0, predicted_z)
				return Vector3(line_x, 0.0, lateral)
			# Support is anchored to the player's 4-3-3 slot. The ball only
			# shifts the whole shape a little, so the team keeps its structure
			# instead of every player collapsing onto the ball.
			var slot: Vector2 = view.formation_slot
			var follow := effects.context_value("formation_ball_follow_scale")
			var max_shift := effects.context_value("formation_max_shift_m")
			var shift_x := clampf(ball_position.x * follow, -max_shift, max_shift)
			var shift_z := clampf(ball_position.z * follow, -max_shift, max_shift)

			var depth := 0.0
			match instructions.support_depth:
				FMEnums.SupportDepth.DEEP:
					depth = -effects.context_value("support_deep_m")
				FMEnums.SupportDepth.ADVANCED:
					depth = effects.context_value("support_advanced_m")
			var width := 0.0
			match instructions.width:
				FMEnums.WidthMode.NARROW:
					width = -effects.context_value("support_narrow_m")
				FMEnums.WidthMode.WIDE:
					width = effects.context_value("support_wide_m")

			var half_l := cfg.pitch_length_m * 0.5
			var half_w := cfg.pitch_width_m * 0.5
			var edge := cfg.support_edge_inset_m
			var x := clampf(sign * slot.x + shift_x + sign * depth, -half_l + edge, half_l - edge)
			var z := clampf(slot.y + shift_z + signf(slot.y) * width, -half_w + edge, half_w - edge)
			return Vector3(x, 0.0, z)
		_:
			return ball_position
