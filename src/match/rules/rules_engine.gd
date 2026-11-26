class_name RulesEngine
extends RefCounted

## Thin orchestrator over the isolated rule classes. Owns match state, score,
## the clock and restart timing; never touches presentation.

signal event_raised(event: RuleEvent)

var state: int = FMEnums.MatchState.IDLE
var score_home: int = 0
var score_away: int = 0

var ctx: MatchContext = null
var config: RulesConfig = null
var effects: StatEffects = null
var offside_rule := OffsideRule.new()
var foul_rule := FoulRule.new()
var restart_rule := RestartRule.new()
var substitution_rule := SubstitutionRule.new()
var clock_rule := ClockRule.new()

var resume_timer: float = 0.0
var restart_count: int = 0
var period_events: Dictionary = {}


func setup(match_ctx: MatchContext, stat_effects: StatEffects, rules_config: RulesConfig) -> void:
	ctx = match_ctx
	effects = stat_effects
	config = rules_config
	offside_rule.configure(config)
	foul_rule.configure(config, effects)
	restart_rule.configure(config)
	substitution_rule.configure(config)
	if ctx.ball != null:
		ctx.ball.kick_performed.connect(_on_ball_kicked)
		ctx.ball.control_changed.connect(_on_control_changed)
	state = FMEnums.MatchState.PLAYING


func tick(delta: float) -> void:
	if ctx == null or ctx.ball == null:
		return
	ctx.ball.match_time = clock_rule.elapsed_seconds

	if state == FMEnums.MatchState.RESTART:
		resume_timer -= delta
		if resume_timer <= 0.0:
			state = FMEnums.MatchState.PLAYING
		return
	clock_rule.tick(delta, state == FMEnums.MatchState.PLAYING)
	if state != FMEnums.MatchState.PLAYING:
		return
	_check_ball_bounds()
	var foul_event := foul_rule.tick(delta, ctx)
	if foul_event != null:
		_emit(foul_event)
	_check_periods()


func _check_ball_bounds() -> void:
	var cfg := GameData.config
	var result := PitchBounds.classify(ctx.ball.global_position, cfg)
	match result:
		PitchBounds.Result.GOAL_HOME:
			score_home += 1
			_emit(RuleEvent.create(RuleEvent.Type.GOAL, "goal for home", "", FMEnums.Side.HOME, FMEnums.FoulSeverity.NONE, FMEnums.RestartType.KICKOFF, ctx.ball.global_position))
			_bank("stoppage_per_goal_seconds")
			_begin_restart(FMEnums.RestartType.KICKOFF, Vector3.ZERO)
		PitchBounds.Result.GOAL_AWAY:
			score_away += 1
			_emit(RuleEvent.create(RuleEvent.Type.GOAL, "goal for away", "", FMEnums.Side.AWAY, FMEnums.FoulSeverity.NONE, FMEnums.RestartType.KICKOFF, ctx.ball.global_position))
			_bank("stoppage_per_goal_seconds")
			_begin_restart(FMEnums.RestartType.KICKOFF, Vector3.ZERO)
		PitchBounds.Result.OUT_TOUCHLINE:
			var side := 1 - _last_side()
			_begin_restart(FMEnums.RestartType.THROW_IN, ctx.ball.global_position, side)
		PitchBounds.Result.OUT_GOAL_LINE:
			var goal_sign := 1.0 if ctx.ball.global_position.x >= 0.0 else -1.0
			var last := ctx.ball.last_kicker
			var restart_type := FMEnums.RestartType.GOAL_KICK
			if last != null and ctx.attack_sign(last) != goal_sign:
				restart_type = FMEnums.RestartType.CORNER
			_begin_restart(restart_type, ctx.ball.global_position)


func _on_ball_kicked(kicker: RigidBody3D, is_pass: bool) -> void:
	if not is_pass:
		offside_rule.clear()
		return
	offside_rule.record_pass(kicker, ctx)


func _on_control_changed(player: RigidBody3D) -> void:
	if player == null or state != FMEnums.MatchState.PLAYING:
		return
	if offside_rule.check_first_touch(player, ctx):
		var opponent_side: int = 1 - player.side
		_emit(RuleEvent.create(RuleEvent.Type.OFFSIDE, "offside by %s" % player.player_id, player.player_id, opponent_side, FMEnums.FoulSeverity.NONE, FMEnums.RestartType.FREE_KICK, player.global_position))
		_bank("stoppage_per_foul_seconds")
		_begin_restart(FMEnums.RestartType.FREE_KICK, player.global_position, opponent_side)


func _begin_restart(restart_type: int, position: Vector3, advantage_side: int = -1) -> void:
	var spot := restart_rule.apply(ctx.ball, restart_type, position, GameData.config)
	state = FMEnums.MatchState.RESTART
	resume_timer = config.value("clock", "restart_delay_seconds")
	restart_count += 1
	var label := "restart %d" % restart_type
	_emit(RuleEvent.create(RuleEvent.Type.RESTART, label, "", advantage_side, FMEnums.FoulSeverity.NONE, restart_type, spot))


func request_substitution(club_id: String, outgoing_id: String, incoming_id: String) -> bool:
	if state != FMEnums.MatchState.PLAYING and state != FMEnums.MatchState.RESTART:
		return false
	if not substitution_rule.request(club_id, outgoing_id, incoming_id):
		return false
	var club := SubstitutionRule._club(club_id)
	var incoming := club.get_player(incoming_id)
	for view in ctx.views:
		if view.player_id == outgoing_id:
			substitution_rule.apply_to_view(view, incoming, club)
			break
	_bank("stoppage_per_substitution_seconds")
	_emit(RuleEvent.create(RuleEvent.Type.SUBSTITUTION, "%s replaces %s" % [incoming_id, outgoing_id], outgoing_id))
	state = FMEnums.MatchState.RESTART
	resume_timer = config.value("clock", "restart_delay_seconds")
	return true


func _check_periods() -> void:
	var cfg := GameData.config
	if not period_events.has("half") and clock_rule.half_time_reached(cfg):
		period_events["half"] = true
		var added := clock_rule.finalize_period()
		state = FMEnums.MatchState.HALF_TIME
		_emit(RuleEvent.create(RuleEvent.Type.HALF_TIME, "half time (+%ds)" % int(added)))
	if not period_events.has("full") and clock_rule.full_time_reached(cfg):
		period_events["full"] = true
		state = FMEnums.MatchState.FULL_TIME
		_emit(RuleEvent.create(RuleEvent.Type.FULL_TIME, "full time"))


func _last_side() -> int:
	var last := ctx.ball.last_kicker
	return last.side if last != null else FMEnums.Side.HOME


func _bank(key: String) -> void:
	clock_rule.register_stoppage(config.value("clock", key))


func _emit(event: RuleEvent) -> void:
	event_raised.emit(event)
