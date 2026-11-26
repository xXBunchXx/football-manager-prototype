extends Node

## Headless entry point. Run with:
##   Godot_v4.7.2-stable_linux.x86_64 --headless --path <project> res://tests/test_scene.tscn

var _passed: int = 0
var _failed: int = 0
var _received_events: Array[String] = []


func _ready() -> void:
	MatchEvents.event_logged.connect(_on_event_logged)
	_test_config()
	_test_data()
	_test_instructions()
	await _test_decisions()
	await _test_rules()
	_test_league()
	_test_match_scene()
	await _test_ball()
	_test_rng()
	_test_events()
	_test_save()
	_test_fixture_loader()
	print("[tests] passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("[PASS] ", label)
	else:
		_failed += 1
		push_error("[FAIL] " + label)


func _on_event_logged(text: String) -> void:
	_received_events.append(text)


func _test_config() -> void:
	var cfg := MatchConfig.new()
	_check(cfg.pitch_length_m == 105.0 and cfg.pitch_width_m == 68.0, "MatchConfig pitch dimensions")
	_check(absf(cfg.get_decision_interval() - (1.0 / 6.0)) < 0.0001, "MatchConfig decision interval")
	_check(cfg.speed_steps.size() == 4, "MatchConfig speed steps")


func _test_rng() -> void:
	RngService.set_seed(4242)
	var first: Array[float] = []
	for i in 5:
		first.append(RngService.randf())
	RngService.set_seed(4242)
	var second: Array[float] = []
	for i in 5:
		second.append(RngService.randf())

	var reproducible := first.size() == second.size()
	for i in first.size():
		if absf(first[i] - second[i]) > 0.000001:
			reproducible = false
	_check(reproducible, "RngService reproduces a seeded sequence")

	var in_range := true
	for value in second:
		if value < 0.0 or value >= 1.0:
			in_range = false
	_check(in_range, "RngService.randf stays in [0,1)")


func _test_events() -> void:
	MatchEvents.log_event("phase1-test")
	var last := _received_events[_received_events.size() - 1] if _received_events.size() > 0 else ""
	_check(_received_events.size() >= 1 and last == "phase1-test", "MatchEvents signal bus")


func _test_save() -> void:
	var test_path := "user://fm_phase1_test.json"
	SaveGame.set_path(test_path)
	var ok := SaveGame.save_state({"alpha": 7})
	var loaded := SaveGame.load_state()
	_check(ok and loaded.get("alpha", -1) == 7, "SaveGame round trip")

	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("fm_phase1_test.json")
	SaveGame.set_path("user://fm_save.json")


func _test_fixture_loader() -> void:
	var path := "user://fm_phase1_fixture.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("{\"name\": \"Test FC\", \"tier\": 1}")
		file.close()

	var data: Variant = FixtureLoader.load_json(path)
	var parsed_ok := data is Dictionary
	if parsed_ok:
		parsed_ok = FixtureLoader.has_keys(data, ["name", "tier"])
	_check(parsed_ok, "FixtureLoader parses JSON and checks keys")

	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("fm_phase1_fixture.json")


func _test_data() -> void:
	var loaded := GameData.load_fixtures()
	_check(loaded, "fixtures load from res://data/")
	_check(GameData.clubs.size() == 6, "six clubs loaded")
	_check(GameData.leagues.size() == 1, "one league loaded")
	_check(GameData.players_by_id.size() == 108, "108 unique players loaded")

	var structure_ok := true
	var attributes_ok := true
	var seen_ids := {}
	var cfg := MatchConfig.new()
	for club in GameData.clubs:
		if club.squad.size() != cfg.squad_size:
			structure_ok = false
		if club.get_starters().size() != cfg.starters_per_club:
			structure_ok = false
		if club.get_bench().size() != cfg.squad_size - cfg.starters_per_club:
			structure_ok = false
		for player in club.squad:
			if seen_ids.has(player.id):
				structure_ok = false
			seen_ids[player.id] = true
			for key in StatProfile.ATTRIBUTE_NAMES:
				var value := player.attributes.get_attribute(key)
				if value < StatProfile.MIN_VALUE or value > StatProfile.MAX_VALUE:
					attributes_ok = false
	_check(structure_ok, "squad sizes, starter counts and unique ids")
	_check(attributes_ok, "all attributes within 1..20")

	var weak := _average_tier(FMEnums.TeamTier.WEAK)
	var mid := _average_tier(FMEnums.TeamTier.MID)
	var strong := _average_tier(FMEnums.TeamTier.STRONG)
	_check(weak < mid and mid < strong, "tier averages ordered weak < mid < strong")
	print("[data] tier averages: weak=%.2f mid=%.2f strong=%.2f" % [weak, mid, strong])

	var bad_attributes := StatProfile.new().to_dict()
	bad_attributes["pace"] = 99
	_check(not StatProfile.is_valid_dict(bad_attributes), "StatProfile rejects out-of-range values")

	var sample: PlayerData = GameData.clubs[0].squad[0]
	var rebuilt := PlayerData.from_dict(sample.to_dict())
	_check(rebuilt != null and rebuilt.display_name() == sample.display_name(), "PlayerData round trip")


func _test_instructions() -> void:
	var all_valid := true
	for player_id in GameData.players_by_id:
		var inst: PlayerInstructions = GameData.player_instructions.get(player_id)
		if inst == null or not PlayerInstructions.is_valid_dict(inst.to_dict()):
			all_valid = false
	_check(all_valid, "every player has valid typed instructions")
	_check(GameData.player_instructions.size() == 108, "instructions built for all players")

	var teams_valid := true
	for club_id in GameData.team_instructions:
		var ti: TeamInstructions = GameData.team_instructions[club_id]
		if not TeamInstructions.is_valid_dict(ti.to_dict()):
			teams_valid = false
	_check(teams_valid and GameData.team_instructions.size() == 6, "every club has valid team instructions")

	var st := InstructionDefaults.for_role("st")
	var cb := InstructionDefaults.for_role("cb")
	_check(st.duty == FMEnums.Duty.ATTACK and st.shoot_on_sight, "ST baseline is attacking and shoots on sight")
	_check(cb.duty == FMEnums.Duty.DEFEND and not cb.shoot_on_sight, "CB baseline is defensive and holds shots")

	var overridden: PlayerInstructions = GameData.player_instructions["ashford-city-10"]
	_check(not overridden.shoot_on_sight and overridden.passing_risk == FMEnums.PassingRisk.BALANCED, "JSON player overrides win over role baseline")
	var untouched: PlayerInstructions = GameData.player_instructions["kingsport-rovers-10"]
	_check(untouched.shoot_on_sight, "players without overrides keep role baseline")
	_check(not PlayerInstructions.is_valid_dict({"duty": "DEFEND", "bogus": 1}), "instruction validation rejects unknown keys")
	_check(PlayerInstructions.is_valid_dict({"duty": "DEFEND"}, true), "instruction validation accepts named partial overrides")

	var ashford_team: TeamInstructions = GameData.team_instructions["ashford-city"]
	var kingsport_team: TeamInstructions = GameData.team_instructions["kingsport-rovers"]
	_check(ashford_team.mentality == FMEnums.Mentality.ATTACKING, "JSON team override wins")
	_check(kingsport_team.mentality == FMEnums.Mentality.BALANCED, "team default applies without override")

	var sample: PlayerData = GameData.clubs[0].squad[0]
	var before := sample.to_dict()
	var state := PlayerState.for_player(sample)
	state.player_id = "hacked"
	state.spend_stamina(1000.0)
	state.adjust_morale(-10.0)
	state.apply_card(FMEnums.CardColor.YELLOW)
	state.apply_card(FMEnums.CardColor.YELLOW)
	_check(sample.to_dict() == before, "PlayerState never mutates PlayerData")
	_check(state.stamina == 0.0 and state.morale == 0.0, "PlayerState clamps physical and mental values")
	_check(state.red_cards == 1 and state.is_suspended(), "two yellows produce a suspension")
	_check(state.is_valid(), "mutated PlayerState remains valid")

	var with_duty := PlayerState.for_player(sample)
	with_duty.duty_override = FMEnums.Duty.ATTACK
	_check(with_duty.effective_duty(cb) == FMEnums.Duty.ATTACK, "duty override beats instruction duty")


func _make_view(player: PlayerData, club: ClubData, is_home: bool, position: Vector3, ctx: MatchContext) -> RigidBody3D:
	var packed: PackedScene = load("res://scenes/player_view.tscn")
	var view := packed.instantiate() as RigidBody3D
	add_child(view)
	view.setup(player, club, is_home)
	view.global_position = position
	ctx.add_view(view)
	return view


func _test_decisions() -> void:
	var effects := StatEffects.load()
	_check(effects != null, "stat effects load and validate")
	if effects == null:
		return
	_check(effects.action_attribute_weights.size() == StatEffects.ACTION_KEYS.size(), "all action weight tables present")
	_check(effects.modifier("shoot_on_sight", "shoot") > 0.0, "shoot-on-sight modifier is positive")

	var brain := DecisionBrain.new(effects)
	var ctx := MatchContext.new()
	var ball_scene: PackedScene = load("res://scenes/ball.tscn")
	var ball := ball_scene.instantiate() as Ball
	add_child(ball)
	await get_tree().physics_frame
	ctx.ball = ball
	ball.reset_to(Vector3(30, 1, 0))

	var strong_club: ClubData = GameData.clubs[1]
	var weak_club: ClubData = GameData.clubs[4]
	var striker := _make_view(strong_club.get_starters()[9], strong_club, true, Vector3(38, 1, 0), ctx)
	var striker_decision := brain.decide(striker, ctx)
	_check(striker_decision.action == FMEnums.Action.SHOOT, "striker inside shooting range chooses shoot")

	var midfielder := _make_view(strong_club.get_starters()[6], strong_club, true, Vector3(-8, 1, 0), ctx)
	var base_scores: Dictionary = brain.decide(midfielder, ctx).scores
	midfielder.instructions = midfielder.instructions.with_overrides({"shoot_on_sight": true})
	var boosted_scores: Dictionary = brain.decide(midfielder, ctx).scores
	_check(boosted_scores["shoot"] > base_scores["shoot"], "shoot-on-sight lifts shoot utility")

	var fresh := _make_view(strong_club.get_starters()[2], strong_club, true, Vector3(-30, 1, 8), ctx)
	var tired := _make_view(strong_club.get_starters()[2], strong_club, true, Vector3(-30, 1, -8), ctx)
	tired.match_state.stamina = 10.0
	_check(float(brain.decide(tired, ctx).scores["press"]) < float(brain.decide(fresh, ctx).scores["press"]), "low stamina reduces pressing utility")

	var strong_st := _make_view(strong_club.get_starters()[9], strong_club, true, Vector3(20, 1, 20), ctx)
	var weak_st := _make_view(weak_club.get_starters()[9], weak_club, false, Vector3(20, 1, -20), ctx)
	_check(float(brain.decide(strong_st, ctx).scores["shoot"]) > float(brain.decide(weak_st, ctx).scores["shoot"]), "stronger attributes raise shoot utility")

	var deep_cb := _make_view(strong_club.get_starters()[1], strong_club, true, Vector3(-25, 1, 15), ctx)
	deep_cb.instructions = deep_cb.instructions.with_overrides({"support_depth": "DEEP"})
	var deep_target: Vector3 = brain.decide(deep_cb, ctx).target
	deep_cb.instructions = deep_cb.instructions.with_overrides({"support_depth": "ADVANCED"})
	var high_target: Vector3 = brain.decide(deep_cb, ctx).target
	_check(deep_target.x < high_target.x, "support depth shifts the target up or down pitch")

	var agent := PlayerAgent.new(striker, brain, ctx, effects)
	agent.decision_timer = 10.0
	striker.last_decision = DecisionResult.create(FMEnums.Action.SUPPORT, Vector3(60, 0, 0), {}, "")
	var start_velocity := Vector3(striker.linear_velocity.x, 0.0, striker.linear_velocity.z)
	for i in 5:
		agent.physics_tick(1.0 / 60.0)
		await get_tree().physics_frame
	var end_velocity := Vector3(striker.linear_velocity.x, 0.0, striker.linear_velocity.z)
	_check(end_velocity.x > start_velocity.x, "steering accelerates the player toward its target")

	ball.reset_to(Vector3(striker.global_position.x + 1.0, GameData.config.ball_radius_m, striker.global_position.z))
	striker.last_decision = DecisionResult.create(FMEnums.Action.SHOOT, ctx.goal_for(striker), {}, "")
	agent.physics_tick(1.0 / 60.0)
	await get_tree().physics_frame
	_check(ball.linear_velocity.length() > 5.0, "agent shoots when the ball is in control range")

	for view in ctx.views:
		view.free()
	ball.free()


func _test_rules() -> void:
	var rules_config := RulesConfig.load()
	_check(rules_config != null, "rules config loads and validates")
	if rules_config == null:
		return
	var effects := StatEffects.load()
	if effects == null:
		return

	var ctx := MatchContext.new()
	var ball_scene: PackedScene = load("res://scenes/ball.tscn")
	var ball := ball_scene.instantiate() as Ball
	add_child(ball)
	await get_tree().physics_frame
	ctx.ball = ball

	var strong_club: ClubData = GameData.clubs[1]
	var weak_club: ClubData = GameData.clubs[4]

	# Offside is judged at the pass, not at the first touch.
	var offside := OffsideRule.new()
	offside.configure(rules_config)
	var passer := _make_view(strong_club.get_starters()[5], strong_club, true, Vector3(-10, 1, 0), ctx)
	_make_view(weak_club.get_starters()[1], weak_club, false, Vector3(0, 1, 2), ctx)
	_make_view(weak_club.get_starters()[2], weak_club, false, Vector3(20, 1, -2), ctx)
	offside.record_pass(passer, ctx)
	var offside_runner := _make_view(strong_club.get_starters()[9], strong_club, true, Vector3(30, 1, 0), ctx)
	_check(offside.check_first_touch(offside_runner, ctx), "offside pass is flagged on first touch")
	offside.record_pass(passer, ctx)
	var onside_runner := _make_view(strong_club.get_starters()[8], strong_club, true, Vector3(-5, 1, 0), ctx)
	_check(not offside.check_first_touch(onside_runner, ctx), "onside pass is not flagged")

	# A fast, aggressive tackle on the carrier is a foul and yields a card.
	var foul_values: Dictionary = rules_config.foul
	foul_values["closing_speed_threshold_mps"] = 0.0
	foul_values["base_chance"] = 1.0
	foul_values["red_chance"] = 1.0
	foul_values["tackle_cooldown_seconds"] = 0.0
	var foul := FoulRule.new()
	foul.configure(rules_config, effects)
	var carrier := _make_view(strong_club.get_starters()[2], strong_club, true, Vector3(0, 1, 0), ctx)
	ball.set_control(carrier, carrier.global_position + Vector3(0.8, 0.0, 0.0))
	var tackler := _make_view(weak_club.get_starters()[6], weak_club, false, Vector3(-2, 1, 0), ctx)
	tackler.linear_velocity = Vector3(5.0, 0.0, 0.0)
	tackler.last_decision = DecisionResult.create(FMEnums.Action.TACKLE, carrier.global_position, {}, "")
	var foul_event: RuleEvent = foul.tick(1.0 / 60.0, ctx)
	_check(foul_event != null, "high-speed mistimed tackle is detected")
	if foul_event != null:
		_check(foul_event.type == RuleEvent.Type.FOUL, "foul event has the right type")
		_check(foul_event.severity == FMEnums.FoulSeverity.RED, "foul severity rolls a card")
		_check(tackler.match_state.red_cards == 1, "card is recorded on the offender state")
		_check(foul_event.restart_type == FMEnums.RestartType.FREE_KICK, "foul awards a free kick")

	foul_values["red_chance"] = 0.0
	foul_values["yellow_chance"] = 1.0
	tackler.last_decision = DecisionResult.create(FMEnums.Action.SUPPORT, carrier.global_position, {}, "")
	var second_tackler := _make_view(weak_club.get_starters()[7], weak_club, false, Vector3(-2, 1, 0), ctx)
	second_tackler.linear_velocity = Vector3(5.0, 0.0, 0.0)
	second_tackler.last_decision = DecisionResult.create(FMEnums.Action.TACKLE, carrier.global_position, {}, "")
	foul.tick(1.0 / 60.0, ctx)
	foul.tick(1.0 / 60.0, ctx)
	_check(second_tackler.match_state.yellow_cards == 2, "two cautions are recorded")
	_check(second_tackler.match_state.is_suspended(), "two yellows send the player off")

	# Each restart type puts the ball in its regulation area.
	var restart := RestartRule.new()
	restart.configure(rules_config)
	var cfg := GameData.config
	var kickoff := restart.apply(ball, FMEnums.RestartType.KICKOFF, Vector3(40, 1, 20), cfg)
	_check(kickoff.distance_to(Vector3(0.0, cfg.ball_radius_m, 0.0)) < 0.01, "kickoff resets to centre spot")
	var throw_in := restart.apply(ball, FMEnums.RestartType.THROW_IN, Vector3(20, 1, 30), cfg)
	_check(absf(throw_in.z - (cfg.pitch_width_m * 0.5 - 1.0)) < 0.01, "throw-in is placed on the touchline")
	var goal_kick := restart.apply(ball, FMEnums.RestartType.GOAL_KICK, Vector3(52, 1, 10), cfg)
	_check(goal_kick.x > 40.0 and absf(goal_kick.z) <= cfg.goal_width_m * 0.5 + 0.01, "goal kick stays in the six-yard box lane")
	var corner := restart.apply(ball, FMEnums.RestartType.CORNER, Vector3(52, 1, 30), cfg)
	_check(corner.x > 45.0 and absf(corner.z) > 30.0, "corner is placed in the corner arc")
	var penalty := restart.apply(ball, FMEnums.RestartType.PENALTY, Vector3(52, 1, 0), cfg)
	_check(absf(penalty.x - (cfg.pitch_length_m * 0.5 - 11.0)) < 0.01, "penalty is placed on the spot")
	var free_kick := restart.apply(ball, FMEnums.RestartType.FREE_KICK, Vector3(60, 1, 50), cfg)
	_check(absf(free_kick.x) <= cfg.pitch_length_m * 0.5 and absf(free_kick.z) <= cfg.pitch_width_m * 0.5, "free kick is brought back in play")

	# Substitutions are capped per club and refuse duplicate ids.
	var substitution := SubstitutionRule.new()
	substitution.configure(rules_config)
	_check(substitution.can_substitute(strong_club.id), "substitution is allowed before the cap")
	for i in 5:
		var outgoing: String = String(strong_club.get_starters()[i].id)
		var incoming: String = String(strong_club.get_bench()[i].id)
		_check(substitution.request(strong_club.id, outgoing, incoming), "substitution %d is accepted" % (i + 1))
	_check(substitution.used_count(strong_club.id) == 5, "five substitutions are counted")
	_check(not substitution.can_substitute(strong_club.id), "substitution cap is enforced")
	_check(not substitution.request(strong_club.id, "same-id", "same-id"), "invalid substitution is rejected")

	# Stoppage time is banked and extends the match clock.
	var clock := ClockRule.new()
	clock.tick(10.0, true)
	clock.tick(2.0, false)
	_check(is_equal_approx(clock.elapsed_seconds, 10.0), "clock advances only during play")
	_check(is_equal_approx(clock.stoppage_seconds, 2.0), "stopped play accumulates stoppage")
	clock.register_stoppage(30.0)
	_check(is_equal_approx(clock.finalize_period(), 32.0), "stoppage is banked as added time")
	clock.elapsed_seconds = cfg.half_length_seconds * float(cfg.halves) - 1.0
	_check(not clock.full_time_reached(cfg), "full time is not reached before regulation plus added time")
	clock.tick(1.0, true)
	_check(not clock.full_time_reached(cfg), "added time keeps the match alive")
	clock.tick(32.0, true)
	_check(clock.full_time_reached(cfg), "added time eventually ends the match")
	_check(clock.half_time_reached(cfg), "half time threshold is reached")
	_check(clock.formatted().contains("+32"), "clock display includes added time")

	# The engine wires goals, restarts and score together.
	var engine_ctx := MatchContext.new()
	var engine_ball := ball_scene.instantiate() as Ball
	add_child(engine_ball)
	await get_tree().physics_frame
	engine_ctx.ball = engine_ball
	var engine := RulesEngine.new()
	engine.setup(engine_ctx, effects, rules_config)
	_check(engine.state == FMEnums.MatchState.PLAYING, "rules engine starts in play")
	var rule_events: Array = []
	engine.event_raised.connect(func(event): rule_events.append(event))
	engine_ball.reset_to(Vector3(cfg.pitch_length_m * 0.5 + 1.0, 1.0, 0.0))
	engine.tick(1.0 / 60.0)
	_check(engine.score_home == 1, "goal inside the frame increments the score")
	_check(engine.state == FMEnums.MatchState.RESTART, "goal starts a restart")
	_check(rule_events.size() > 0 and rule_events[0].type == RuleEvent.Type.GOAL, "goal raises a rule event")

	# A defender playing the ball over their own goal line concedes a corner;
	# an attacker doing so concedes a goal kick.
	var home_kicker := _make_view(strong_club.get_starters()[9], strong_club, true, Vector3(40, 1, 0), engine_ctx)
	var away_kicker := _make_view(weak_club.get_starters()[9], weak_club, false, Vector3(-40, 1, 0), engine_ctx)
	var out_of_play := Vector3(cfg.pitch_length_m * 0.5 + 1.0, 1.0, 15.0)

	engine.state = FMEnums.MatchState.PLAYING
	engine_ball.reset_to(out_of_play)
	engine_ball.last_kicker = away_kicker
	engine.tick(1.0 / 60.0)
	var corner_event: RuleEvent = rule_events[rule_events.size() - 1]
	_check(corner_event.restart_type == FMEnums.RestartType.CORNER, "defender's goal-line exit awards a corner")

	engine.state = FMEnums.MatchState.PLAYING
	engine_ball.reset_to(out_of_play)
	engine_ball.last_kicker = home_kicker
	engine.tick(1.0 / 60.0)
	var goal_kick_event: RuleEvent = rule_events[rule_events.size() - 1]
	_check(goal_kick_event.restart_type == FMEnums.RestartType.GOAL_KICK, "attacker's goal-line exit awards a goal kick")

	for view in ctx.views:
		view.free()
	for view in engine_ctx.views:
		view.free()
	ball.free()
	engine_ball.free()


func _test_league() -> void:
	var league: LeagueData = GameData.leagues[0]
	var fixtures := FixtureGenerator.generate(league)
	_check(fixtures.size() == 30, "double round-robin creates 30 fixtures")
	var rounds: Dictionary = {}
	for fixture in fixtures:
		rounds[fixture.round] = true
	_check(rounds.size() == 10, "fixtures are spread over ten rounds")

	var home_counts: Dictionary = {}
	var away_counts: Dictionary = {}
	var pair_counts: Dictionary = {}
	for fixture in fixtures:
		home_counts[fixture.home_club_id] = int(home_counts.get(fixture.home_club_id, 0)) + 1
		away_counts[fixture.away_club_id] = int(away_counts.get(fixture.away_club_id, 0)) + 1
		var key := "%s|%s" % [fixture.home_club_id, fixture.away_club_id]
		pair_counts[key] = int(pair_counts.get(key, 0)) + 1
	var balanced := true
	var all_pairs := true
	for club_id in league.club_ids:
		if int(home_counts.get(club_id, 0)) != 5 or int(away_counts.get(club_id, 0)) != 5:
			balanced = false
	for i in league.club_ids.size():
		for j in league.club_ids.size():
			if i == j:
				continue
			var key := "%s|%s" % [league.club_ids[i], league.club_ids[j]]
			if int(pair_counts.get(key, 0)) != 1:
				all_pairs = false
	_check(balanced, "each club has five home and five away fixtures")
	_check(all_pairs, "each ordered club pairing appears once")

	var season := SeasonState.new()
	season.league_id = league.id
	season.fixtures = fixtures
	_check(season.next_round() == 1 and season.played_count() == 0, "new season starts at round one")
	season.fixtures[0].played = true
	season.fixtures[0].home_goals = 2
	season.fixtures[0].away_goals = 0
	_check(season.next_round() == 1 and season.played_count() == 1, "played count ignores other round-one games")

	var manager := SeasonManager.new()
	_check(manager.new_season(league, GameData.clubs), "season manager builds a season")
	var result := MatchResult.create(fixtures[0], 3, 1)
	_check(manager.record_result(result), "final score is recorded")
	_check(not manager.record_result(result), "duplicate result is rejected")
	var home_row: LeagueTableRow = manager.table.row_for(result.home_club_id)
	_check(home_row.points == 3 and home_row.goals_for == 3 and home_row.goals_against == 1, "table awards three points for a win")
	var away_row: LeagueTableRow = manager.table.row_for(result.away_club_id)
	_check(away_row.points == 0 and away_row.form[0] == "L", "loser gets no points and an L in form")
	var standings: Array[LeagueTableRow] = manager.table.standings()
	_check(standings.size() == 6 and standings[0].club_id == result.home_club_id, "standings sort the winner to the top")

	var previous_path: String = SaveGame.save_path
	SaveGame.set_path("user://fm-league-test.json")
	_check(manager.save(), "season saves through SaveGame")
	var loaded := SeasonManager.new()
	_check(loaded.load_or_new(league, GameData.clubs), "season reloads from JSON")
	var loaded_fixture: Fixture = loaded.season.fixture_by_id(fixtures[0].id)
	_check(loaded_fixture != null and loaded_fixture.played and loaded_fixture.home_goals == 3, "saved result survives reload")
	var loaded_row: LeagueTableRow = loaded.table.row_for(result.home_club_id)
	_check(loaded_row != null and loaded_row.points == 3, "standings rebuild from saved fixtures")
	SaveGame.set_path(previous_path)

	_check(LeagueManager.get_fixtures().size() == 30, "league autoload exposes the fixtures")
	_check(LeagueManager.get_standings().size() == 6, "league autoload exposes six table rows")
	var league_ui: PackedScene = load("res://scenes/ui/league_scene.tscn")
	_check(league_ui != null, "league scene resource loads")
	if league_ui != null:
		var ui_instance: Node = league_ui.instantiate()
		add_child(ui_instance)
		var fixture_buttons: Node = ui_instance.find_child("FixtureList", true, false)
		_check(fixture_buttons != null, "league scene builds a fixture list")
		if fixture_buttons != null:
			_check(fixture_buttons.get_child_count() == 30, "league scene lists all 30 fixtures")
		ui_instance.free()
	var playable: Fixture = fixtures[0]
	for fixture in LeagueManager.get_fixtures():
		if not fixture.played:
			playable = fixture
			break
	_check(LeagueManager.select_fixture(playable.id), "a fixture can be selected for live play")
	var packed: PackedScene = load("res://scenes/match_scene.tscn")
	var instance: Node = packed.instantiate()
	add_child(instance)
	var views: Array = instance.call("get_player_views")
	var home_view: RigidBody3D = views[0]
	var away_view: RigidBody3D = views[11]
	_check(String(instance.call("get_fixture_id")) == playable.id, "match scene reads the selected fixture")
	_check(home_view.club_id == playable.home_club_id, "home side uses the fixture's home club")
	_check(away_view.club_id == playable.away_club_id, "away side uses the fixture's away club")
	instance.free()
	LeagueManager.selected_fixture_id = ""


func _test_match_scene() -> void:
	var packed: PackedScene = load("res://scenes/match_scene.tscn")
	_check(packed != null, "match scene resource loads")
	if packed == null:
		return
	var instance: Node = packed.instantiate()
	add_child(instance)
	var views: Array = instance.call("get_player_views")
	_check(views.size() == 22, "match scene spawns 22 players")
	var tactical_ready := true
	for view in views:
		if view.call("get_instructions") == null or view.call("get_match_state") == null:
			tactical_ready = false
	_check(tactical_ready, "all 22 starters carry instructions and match state")
	var agents: Array = instance.call("get_agents")
	_check(agents.size() == 22, "match scene builds 22 decision agents")
	var camera := instance.find_child("MatchCamera", true, false)
	_check(camera != null, "match scene has a match camera")
	instance.free()


func _test_ball() -> void:
	var cfg := GameData.config
	_check(PitchBounds.classify(Vector3.ZERO, cfg) == PitchBounds.Result.IN_PLAY, "bounds: centre in play")
	_check(PitchBounds.classify(Vector3(cfg.pitch_length_m * 0.5 + 1.0, 1.0, 0.0), cfg) == PitchBounds.Result.GOAL_HOME, "bounds: home goal")
	_check(PitchBounds.classify(Vector3(-cfg.pitch_length_m * 0.5 - 1.0, 1.0, 0.0), cfg) == PitchBounds.Result.GOAL_AWAY, "bounds: away goal")
	_check(PitchBounds.classify(Vector3(0.0, 1.0, cfg.pitch_width_m * 0.5 + 1.0), cfg) == PitchBounds.Result.OUT_TOUCHLINE, "bounds: touchline")
	_check(PitchBounds.classify(Vector3(cfg.pitch_length_m * 0.5 + 1.0, 1.0, cfg.goal_width_m), cfg) == PitchBounds.Result.OUT_GOAL_LINE, "bounds: goal line outside posts")

	var packed: PackedScene = load("res://scenes/ball.tscn")
	var ball := packed.instantiate() as Ball
	_check(ball != null, "ball scene resource loads")
	if ball == null:
		return
	add_child(ball)
	# The first physics frame after adding a body initialises it; impulses
	# applied before that are not integrated until the following step.
	await get_tree().physics_frame
	ball.reset_to(Vector3(0, 1, 0))

	ball.apply_kick(Vector3(1, 0, 0), 10.0, 0.0, 0.0, 0.0)
	await get_tree().physics_frame
	_check(ball.linear_velocity.x > 5.0 and absf(ball.linear_velocity.z) < 0.01, "kick impulse travels along +X")
	var first_speed := ball.linear_velocity.length()

	ball.reset_to(Vector3(0, 1, 0))
	ball.apply_kick(Vector3(1, 0, 0), 20.0, 0.0, 0.0, 0.0)
	await get_tree().physics_frame
	_check(ball.linear_velocity.length() > first_speed, "higher kick speed raises ball velocity")

	ball.reset_to(Vector3(0, 1, 0))
	ball.apply_kick(Vector3(1, 0, 0), 15.0, 0.0, 0.0, 80.0)
	_check(absf(ball.spin.y - 80.0) < 0.01, "kick sets side spin")
	var start_z := ball.global_position.z
	for i in 5:
		await get_tree().physics_frame
	_check(absf(ball.global_position.z - start_z) > 0.001, "Magnus force curves the ball")

	ball.reset_to(Vector3(0, 1, 0))
	var dummy := RigidBody3D.new()
	add_child(dummy)
	ball.set_control(dummy, Vector3(4, 1, 0))
	for i in 10:
		await get_tree().physics_frame
	_check(ball.global_position.x > 0.05, "control steering moves ball toward target")
	ball.release_control()
	dummy.free()
	ball.free()


func _average_tier(tier: int) -> float:
	var total := 0.0
	var count := 0
	for club in GameData.clubs:
		if club.tier != tier:
			continue
		for player in club.squad:
			total += player.attributes.average()
			count += 1
	return total / float(count) if count > 0 else 0.0
