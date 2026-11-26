class_name KeeperRule
extends RefCounted

## Goalkeeper intervention. Keepers are physical pills like everyone else, but
## a shot heading into their goal within reach is parried instead of passing
## straight through them. Thresholds live in data/rules.json.

var config: RulesConfig = null
var cooldowns: Dictionary = {}


func configure(rules_config: RulesConfig) -> void:
	config = rules_config


func tick(delta: float, ctx: MatchContext) -> RuleEvent:
	for player_id in cooldowns:
		cooldowns[player_id] = maxf(0.0, float(cooldowns[player_id]) - delta)
	if ctx == null or ctx.ball == null or ctx.match_state != FMEnums.MatchState.PLAYING:
		return null

	var ball := ctx.ball
	for view in ctx.views:
		if view.player_data == null or view.player_data.role_id != "gk":
			continue
		if float(cooldowns.get(view.player_id, 0.0)) > 0.0:
			continue

		var goal := ctx.own_goal_for(view)
		var to_goal := goal - ball.global_position
		to_goal.y = 0.0
		var goal_distance := to_goal.length()
		if goal_distance < 0.001 or goal_distance > config.value("keeper", "engagement_range_m"):
			continue
		if ball.linear_velocity.dot(to_goal.normalized()) < config.value("keeper", "shot_speed_threshold_mps"):
			continue
		if MatchContext.flat_distance(view.global_position, ball.global_position) > config.value("keeper", "save_radius_m"):
			continue

		var away := ball.global_position - view.global_position
		away.y = 0.0
		if away.length_squared() < 0.001:
			away = -to_goal.normalized()
		# Aim clear of the goal rather than just off the keeper's body: the
		# keeper should be between shot and goal, but guard the case where he
		# is beaten and the contact point is goal-side of him.
		var clearance := -to_goal.normalized() + away.normalized() * 0.5
		ball.deflect(clearance.normalized(), config.value("keeper", "save_speed_mps"))
		cooldowns[view.player_id] = config.value("keeper", "save_cooldown_seconds")
		# offender_id carries the acting player here (the keeper), not a foul.
		return RuleEvent.create(RuleEvent.Type.SAVE, "save by %s" % view.player_id, view.player_id, view.side)
	return null
