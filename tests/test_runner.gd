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
	await _test_style_play()
	await _test_rules()
	_test_league()
	_test_stats()
	_test_stats_detail()
	_test_history_and_analysis()
	_test_fast_simulation()
	await _test_physics()
	await _test_match_scene()
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
	_check(is_equal_approx(cfg.get_match_duration_seconds(), 5400.0), "match clock runs 90 real minutes")
	var pitch_script: Script = load("res://src/match/pitch.gd")
	_check(is_equal_approx(pitch_script.penalty_area_boundary_x(-1.0, cfg), -36.0), "penalty-area line sits at the box's far edge")
	_check(is_equal_approx(pitch_script.goal_area_boundary_x(1.0, cfg), 47.0), "six-yard line sits at the box's far edge")
	_check(pitch_script.penalty_arc_span(-1.0, cfg).y > 0.0, "penalty arc faces midfield")
	_check(pitch_script.corner_arc_span(-1.0, 1.0).x < 0.0, "corner arc bends inside the touchline")


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

	RngService.set_seed(31337)
	RngService.chance(0.5)
	var after_chance := RngService.randf()
	RngService.set_seed(31337)
	RngService.randf()
	var after_roll := RngService.randf()
	_check(is_equal_approx(after_chance, after_roll), "RngService.chance consumes the seeded stream")


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


func _make_view(player: PlayerData, club: ClubData, is_home: bool, position: Vector3, ctx: MatchContext, slot_index: int = -1) -> RigidBody3D:
	var packed: PackedScene = load("res://scenes/player_view.tscn")
	var view := packed.instantiate() as RigidBody3D
	add_child(view)
	view.setup(player, club, is_home)
	if slot_index >= 0:
		view.formation_slot = Formation.slot(slot_index)
	view.global_position = position
	ctx.add_view(view)
	return view


func _test_decisions() -> void:
	var cfg := GameData.config
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
	var striker := _make_view(strong_club.get_starters()[9], strong_club, true, Vector3(42, 1, 0), ctx)
	var striker_spot := Vector3(striker.global_position.x - 1.0, cfg.ball_radius_m, 0.0)
	ball.reset_to(striker_spot)
	ball.set_control(striker, striker_spot)
	var striker_decision := brain.decide(striker, ctx)
	_check(striker_decision.action == FMEnums.Action.SHOOT, "carrier striker in range chooses shoot")
	ball.release_control()
	var pressure_marker := _make_view(weak_club.get_starters()[2], weak_club, false, Vector3(41, 1, 1), ctx)
	ball.set_control(striker, striker_spot)
	var pressured_decision := brain.decide(striker, ctx)
	_check(pressured_decision.action != FMEnums.Action.SHOOT, "pressured striker looks for a pass instead of forcing a shot")
	ball.release_control()
	ctx.views.erase(pressure_marker)
	pressure_marker.free()
	var near_dribble_target: Vector3 = brain.call("_target_for", "dribble", striker, ctx, striker.instructions)
	_check(near_dribble_target.x > striker.global_position.x, "dribble with the ball advances toward goal")
	ball.reset_to(Vector3(30.0, 1.0, 0.0))
	var distant_decision := brain.decide(striker, ctx)
	_check(distant_decision.action != FMEnums.Action.SHOOT, "shoot-on-sight does not fire from the other end")
	var far_dribble_target: Vector3 = brain.call("_target_for", "dribble", striker, ctx, striker.instructions)
	_check(absf(far_dribble_target.x - ball.global_position.x) < 0.01, "dribble without the ball targets the ball")

	var midfielder := _make_view(strong_club.get_starters()[6], strong_club, true, Vector3(-8, 1, 0), ctx)
	ball.reset_to(Vector3(midfielder.global_position.x + 1.0, cfg.ball_radius_m, 0.0))
	var base_scores: Dictionary = brain.decide(midfielder, ctx).scores
	midfielder.instructions = midfielder.instructions.with_overrides({"shoot_on_sight": true})
	var boosted_scores: Dictionary = brain.decide(midfielder, ctx).scores
	_check(boosted_scores["shoot"] > base_scores["shoot"], "shoot-on-sight lifts shoot utility when the ball is in reach")
	ball.reset_to(Vector3(30.0, 1.0, 0.0))

	var fresh := _make_view(strong_club.get_starters()[2], strong_club, true, Vector3(-30, 1, 8), ctx)
	var tired := _make_view(strong_club.get_starters()[2], strong_club, true, Vector3(-30, 1, -8), ctx)
	tired.match_state.stamina = 10.0
	_check(float(brain.decide(tired, ctx).scores["press"]) < float(brain.decide(fresh, ctx).scores["press"]), "low stamina reduces pressing utility")

	var strong_st := _make_view(strong_club.get_starters()[9], strong_club, true, Vector3(20, 1, 20), ctx)
	var weak_st := _make_view(weak_club.get_starters()[9], weak_club, false, Vector3(20, 1, -20), ctx)
	_check(float(brain.decide(strong_st, ctx).scores["shoot"]) > float(brain.decide(weak_st, ctx).scores["shoot"]), "stronger attributes raise shoot utility")

	var deep_cb := _make_view(strong_club.get_starters()[1], strong_club, true, Vector3(-25, 1, 15), ctx, 1)
	deep_cb.instructions = deep_cb.instructions.with_overrides({"support_depth": "DEEP"})
	var deep_target: Vector3 = brain.decide(deep_cb, ctx).target
	deep_cb.instructions = deep_cb.instructions.with_overrides({"support_depth": "ADVANCED"})
	var high_target: Vector3 = brain.decide(deep_cb, ctx).target
	_check(deep_target.x < high_target.x, "support depth shifts the target up or down pitch")

	var home_gk := _make_view(strong_club.get_starters()[0], strong_club, true, Vector3(-48, 1, 0), ctx, 0)
	var away_gk := _make_view(strong_club.get_starters()[0], strong_club, false, Vector3(48, 1, 0), ctx, 0)
	var home_gk_target: Vector3 = brain.call("_target_for", "support", home_gk, ctx, home_gk.instructions)
	var away_gk_target: Vector3 = brain.call("_target_for", "support", away_gk, ctx, away_gk.instructions)
	_check(home_gk_target.x < -45.0 and away_gk_target.x > 45.0, "goalkeepers anchor near their own goal")

	ball.reset_to(Vector3(-60.0, 1.0, 0.0))
	var deep_out := _make_view(strong_club.get_starters()[1], strong_club, true, Vector3(-40, 1, 0), ctx, 1)
	deep_out.instructions = deep_out.instructions.with_overrides({"support_depth": "DEEP"})
	var clamped_target: Vector3 = brain.call("_target_for", "support", deep_out, ctx, deep_out.instructions)
	_check(clamped_target.x >= -cfg.pitch_length_m * 0.5, "support targets stay on the pitch")
	ball.reset_to(Vector3(30.0, 1.0, 0.0))

	var wide_lanes: Array[float] = []
	var starters: Array = strong_club.get_starters()
	for slot_index in starters.size():
		var wide_view := _make_view(starters[slot_index], strong_club, true, Vector3(-8, 1, 0), ctx, slot_index)
		wide_view.instructions = wide_view.instructions.with_overrides({"width": "WIDE"})
		var lane_target: Vector3 = brain.call("_target_for", "support", wide_view, ctx, wide_view.instructions)
		wide_lanes.append(lane_target.z)
	var unique_lanes: Dictionary = {}
	for z in wide_lanes:
		unique_lanes[snappedf(z, 0.01)] = true
	_check(unique_lanes.size() >= 3, "wide support spreads team-mates into distinct lanes (%d lanes)" % unique_lanes.size())

	ball.reset_to(Vector3(30.0, 1.0, 0.0))
	var shaped_cb := _make_view(strong_club.get_starters()[1], strong_club, true, Vector3(-30, 1, -12), ctx, 1)
	var shape_target: Vector3 = brain.call("_target_for", "support", shaped_cb, ctx, shaped_cb.instructions)
	_check(shape_target.x < 0.0, "support stays in the team's half when the ball is upfield")
	_check(MatchContext.flat_distance(shape_target, ball.global_position) > 20.0, "support does not collapse onto the ball")

	# Only the nearest outfielder should chase a loose ball; the rest hold shape.
	var chaser := _make_view(starters[6], strong_club, true, Vector3(30, 1, 0), ctx, 6)
	var decoy := _make_view(starters[3], strong_club, true, Vector3(10, 1, 0), ctx, 3)
	ball.reset_to(Vector3(12.0, 1.0, 0.0))
	_check(ctx.ball_chaser_rank(decoy) == 0, "nearest outfielder is first chaser")
	_check(ctx.ball_chaser_rank(chaser) > 0, "distant team-mate is not the first chaser")
	var far_chase_score := float(brain.decide(chaser, ctx).scores["chase"])
	ball.reset_to(Vector3(30.0, 1.0, 0.0))
	_check(ctx.ball_chaser_rank(chaser) == 0, "chaser rank follows the ball")
	var near_chase_score := float(brain.decide(chaser, ctx).scores["chase"])
	_check(near_chase_score > far_chase_score, "chase utility favours the closest player")

	# On-ball actions beat passive control once the carrier has the ball.
	ball.reset_to(Vector3(31.0, 1.0, 0.0))
	ball.set_control(chaser, Vector3(31.0, cfg.ball_radius_m, 0.0))
	var carrier_scores: Dictionary = brain.decide(chaser, ctx).scores
	ball.release_control()
	var free_scores: Dictionary = brain.decide(chaser, ctx).scores
	_check(float(carrier_scores["pass"]) > float(free_scores["pass"]), "carrier prefers passing")
	_check(float(carrier_scores["dribble"]) > float(free_scores["dribble"]), "carrier prefers dribbling")
	_check(float(carrier_scores["support"]) < float(free_scores["support"]), "carrier stops holding a support shape")
	_check(float(carrier_scores["tackle"]) < -100.0, "carrier never tackles himself")

	var marker := _make_view(starters[2], strong_club, true, Vector3(-35, 1, 10), ctx, 2)
	var marked_opponent := _make_view(weak_club.get_starters()[2], weak_club, false, Vector3(-34, 1, 12), ctx, 2)
	_check(not marker.instructions.man_mark, "default centre-back is not assigned a mark")
	var unassigned_mark := float(brain.decide(marker, ctx).scores["mark"])
	marker.instructions = marker.instructions.with_overrides({"man_mark": true})
	var assigned_mark := float(brain.decide(marker, ctx).scores["mark"])
	_check(assigned_mark > unassigned_mark + 9.0, "only assigned markers get the mark bonus")
	var mark_target: Vector3 = brain.call("_target_for", "mark", marker, ctx, marker.instructions)
	_check(MatchContext.flat_distance(mark_target, marked_opponent.global_position) >= effects.context_value("mark_stand_off_m") - 0.01, "assigned marking keeps a stand-off distance")
	_check(mark_target.x < marked_opponent.global_position.x, "marker stays goal-side of the opponent")
	marked_opponent.global_position = Vector3(40, 1, 25)
	var distant_mark := float(brain.decide(marker, ctx).scores["mark"])
	_check(distant_mark < assigned_mark, "assigned marker stops following an opponent out of his zone")
	marked_opponent.global_position = Vector3(-34, 1, 12)

	# A nearby but farther player cannot steal control from the true owner.
	var rival := _make_view(starters[9], strong_club, true, Vector3(31.0, 1, 0), ctx, 9)
	ball.global_position = Vector3(30.2, cfg.ball_radius_m, 0.0)
	ball.set_control(chaser, ball.global_position)
	var rival_agent := PlayerAgent.new(rival, brain, ctx, effects)
	rival_agent.decision_timer = 10.0
	rival.last_decision = DecisionResult.create(FMEnums.Action.SUPPORT, rival.global_position, {}, "")
	rival_agent.physics_tick(1.0 / 60.0)
	_check(ball.control_owner == chaser, "farther player does not steal ball control")
	ball.release_control()

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

	# Passes scale to the receiver's distance instead of launching every ball
	# at the same speed.
	var pass_agent := PlayerAgent.new(striker, brain, ctx, effects)
	pass_agent.decision_timer = 10.0
	var pass_target := Vector3(striker.global_position.x + 12.0, 0.0, striker.global_position.z)
	striker.last_decision = DecisionResult.create(FMEnums.Action.PASS, pass_target, {}, "")
	ball.reset_to(Vector3(striker.global_position.x + 0.8, cfg.ball_radius_m, striker.global_position.z))
	ball.set_control(striker, ball.global_position)
	pass_agent.physics_tick(1.0 / 60.0)
	await get_tree().physics_frame
	var pass_speed := ball.linear_velocity.length()
	_check(ball.last_kick_was_pass, "agent records the strike as a pass")
	_check(pass_speed >= cfg.pass_min_speed_mps - 0.1 and pass_speed <= cfg.pass_speed_mps + 0.1, "pass speed is scaled within the tuned bounds (%.1f m/s)" % pass_speed)

	# A defender who closes onto the carrier can actually win the tackle, but
	# only the closest one challenges; a second defender must not glue on too.
	ball.reset_to(chaser.global_position + Vector3(0.2, 0.0, 0.0))
	ball.set_control(chaser, ball.global_position)
	var tackler := _make_view(weak_club.get_starters()[6], weak_club, false, chaser.global_position + Vector3(0.0, 0.0, 0.6), ctx)
	var shadow := _make_view(weak_club.get_starters()[6], weak_club, false, chaser.global_position + Vector3(0.0, 0.0, 2.2), ctx)
	var close_tackle := float(brain.decide(tackler, ctx).scores["tackle"])
	var distant_tackle := float(brain.decide(shadow, ctx).scores["tackle"])
	_check(close_tackle > distant_tackle + effects.context_value("tackle_rank_penalty_per_place") * 0.5, "only the nearest defender gets the tackle bonus")
	ctx.views.erase(shadow)
	shadow.free()
	var original_tackle_chance := float(effects.context["tackle_success_chance"])
	effects.context["tackle_success_chance"] = 1.0
	var tackle_agent := PlayerAgent.new(tackler, brain, ctx, effects)
	tackle_agent.decision_timer = 10.0
	tackler.last_decision = DecisionResult.create(FMEnums.Action.TACKLE, chaser.global_position, {}, "")
	tackle_agent.physics_tick(1.0 / 60.0)
	_check(ball.control_owner == tackler, "nearby defender wins the ball with a tackle")
	ball.release_control()

	# A lost challenge must not hand the ball straight back a frame later.
	var challenger := _make_view(weak_club.get_starters()[8], weak_club, false, chaser.global_position + Vector3(0.0, 0.0, 0.9), ctx)
	ball.reset_to(chaser.global_position + Vector3(0.2, 0.0, 0.0))
	ball.set_control(chaser, ball.global_position)
	effects.context["tackle_success_chance"] = 0.0
	var failed_agent := PlayerAgent.new(challenger, brain, ctx, effects)
	failed_agent.decision_timer = 10.0
	challenger.last_decision = DecisionResult.create(FMEnums.Action.TACKLE, chaser.global_position, {}, "")
	failed_agent.physics_tick(1.0 / 60.0)
	_check(ball.control_owner == chaser, "failed tackle leaves the carrier in control")
	_check(failed_agent.tackle_backoff_timer > 0.0, "failed tackler backs off")
	challenger.last_decision = DecisionResult.create(FMEnums.Action.TACKLE, chaser.global_position, {}, "")
	failed_agent.physics_tick(1.0 / 60.0)
	_check(ball.control_owner == chaser, "failed tackler cannot instantly retry")
	effects.context["tackle_success_chance"] = original_tackle_chance
	ball.release_control()
	ctx.views.erase(tackler)
	ctx.views.erase(challenger)
	tackler.free()
	challenger.free()

	# Pass selection favours an open forward team-mate over a crowded or
	# overlapping one.
	var pass_ctx := MatchContext.new()
	var passer := _make_view(starters[6], strong_club, true, Vector3(0, 1, 0), pass_ctx, 6)
	var open_mate := _make_view(starters[9], strong_club, true, Vector3(14, 1, 4), pass_ctx, 9)
	_make_view(starters[8], strong_club, true, Vector3(1.5, 1, 0), pass_ctx, 8)
	var covered_mate := _make_view(starters[7], strong_club, true, Vector3(24, 1, -6), pass_ctx, 7)
	_make_view(weak_club.get_starters()[7], weak_club, false, Vector3(24, 1, -4), pass_ctx, 7)
	var chosen_pass := pass_ctx.best_pass_target(passer, effects.context)
	_check(chosen_pass == open_mate and chosen_pass != covered_mate, "pass target is the open forward option, not the covered or overlapping one")

	# With every team-mate too close, PASS must fall back instead of kicking
	# the ball toward goal with no receiver.
	open_mate.global_position = passer.global_position + Vector3(2.0, 0.0, 0.0)
	covered_mate.global_position = passer.global_position + Vector3(3.0, 0.0, 1.0)
	pass_ctx.ball = ball
	ball.reset_to(passer.global_position + Vector3(0.8, 0.0, 0.0))
	ball.set_control(passer, ball.global_position)
	var boxed_decision := brain.decide(passer, pass_ctx)
	_check(boxed_decision.action != FMEnums.Action.PASS, "carrier does not pass when no team-mate is eligible")
	_check(boxed_decision.pass_to_id == "", "pass with no receiver has no target id")
	ball.release_control()
	for view in pass_ctx.views:
		view.free()

	for view in ctx.views:
		view.free()
	ball.free()


func _test_style_play() -> void:
	var effects := StatEffects.load()
	_check(effects != null, "style tuning loads with the expanded action set")
	if effects == null:
		return
	_check(effects.action_base.has("cross") and effects.action_base.has("switch") and effects.action_base.has("overlap"), "cross, switch and overlap have base scores")
	var brain := DecisionBrain.new(effects)
	var cfg := GameData.config
	var strong_club: ClubData = GameData.clubs[1]
	var weak_club: ClubData = GameData.clubs[4]
	var starters: Array = strong_club.get_starters()

	# An open lane should make the carrier drive at goal; a marker in that lane
	# should push him toward a pass instead.
	var ctx := MatchContext.new()
	var ball := load("res://scenes/ball.tscn").instantiate() as Ball
	add_child(ball)
	await get_tree().physics_frame
	ctx.ball = ball
	var carrier := _make_view(starters[6], strong_club, true, Vector3(0, 1, 0), ctx, 6)
	ball.reset_to(Vector3(0.8, cfg.ball_radius_m, 0.0))
	ball.set_control(carrier, ball.global_position)
	var open_space: float = ctx.space_ahead(carrier, effects.context)
	_check(is_equal_approx(open_space, effects.context_value("dribble_space_radius_m")), "space ahead is measured to the tuned radius")
	var open_dribble := float(brain.decide(carrier, ctx).scores["dribble"])
	var marker := _make_view(weak_club.get_starters()[6], weak_club, false, Vector3(3, 1, 0), ctx, 6)
	var tight_dribble := float(brain.decide(carrier, ctx).scores["dribble"])
	_check(tight_dribble < open_dribble, "a crowded lane lowers dribble utility")

	# A central carrier with a far-side team-mate should switch play, not hit
	# the covered short option beside him.
	_make_view(starters[9], strong_club, true, Vector3(12, 1, 28), ctx, 9)
	_make_view(starters[8], strong_club, true, Vector3(10, 1, 4), ctx, 8)
	var switch_decision := brain.decide(carrier, ctx)
	_check(switch_decision.action == FMEnums.Action.SWITCH, "central carrier switches play to the far wing (%s)" % switch_decision.best_action_name())
	_check(switch_decision.pass_to_id == ctx.views[2].player_id, "switch targets the far-side team-mate")
	ball.release_control()
	for view in ctx.views:
		view.free()
	ball.free()

	# A wide carrier in crossing range finds a central runner and strikes a
	# lofted cross rather than recycling possession.
	var cross_ctx := MatchContext.new()
	var cross_ball := load("res://scenes/ball.tscn").instantiate() as Ball
	add_child(cross_ball)
	await get_tree().physics_frame
	cross_ctx.ball = cross_ball
	var wide_carrier := _make_view(starters[10], strong_club, true, Vector3(32, 1, -22), cross_ctx, 10)
	wide_carrier.instructions = wide_carrier.instructions.with_overrides({"width": "WIDE", "passing_risk": "SAFE"})
	var box_runner := _make_view(starters[9], strong_club, true, Vector3(45, 1, -4), cross_ctx, 9)
	# A defender in the dribble lane makes the cross the progressive option even
	# though the runner himself is still free.
	_make_view(weak_club.get_starters()[7], weak_club, false, Vector3(34, 1, -22), cross_ctx, 7)
	cross_ctx.team_instructions[strong_club.id] = TeamInstructions.new().with_overrides({"width": "WIDE", "passing_style": "DIRECT"})
	cross_ball.reset_to(Vector3(32.8, cfg.ball_radius_m, -22.0))
	cross_ball.set_control(wide_carrier, cross_ball.global_position)
	_check(cross_ctx.best_cross_target(wide_carrier, effects.context) == box_runner, "wide carrier finds a central crossing target")
	var cross_decision := brain.decide(wide_carrier, cross_ctx)
	_check(cross_decision.action == FMEnums.Action.CROSS, "wide carrier crosses instead of passing backwards (%s)" % cross_decision.best_action_name())
	_check(cross_decision.pass_to_id == box_runner.player_id, "cross targets the arriving striker")
	var cross_agent := PlayerAgent.new(wide_carrier, brain, cross_ctx, effects)
	cross_agent.decision_timer = 10.0
	wide_carrier.last_decision = cross_decision
	cross_agent.physics_tick(1.0 / 60.0)
	await get_tree().physics_frame
	_check(cross_ball.last_kick_was_pass, "cross is logged as a passing strike")
	_check(cross_ball.linear_velocity.length() > 8.0, "cross leaves the foot at a useful speed (%.2f m/s)" % cross_ball.linear_velocity.length())
	cross_ball.release_control()
	for view in cross_ctx.views:
		view.free()
	cross_ball.free()

	# A fullback behind the carrier on the same flank makes an overlapping run
	# without stealing the ball, and his pace actually changes his top speed.
	var run_ctx := MatchContext.new()
	var run_ball := load("res://scenes/ball.tscn").instantiate() as Ball
	add_child(run_ball)
	await get_tree().physics_frame
	run_ctx.ball = run_ball
	var run_carrier := _make_view(starters[6], strong_club, true, Vector3(10, 1, -20), run_ctx, 6)
	run_ball.reset_to(Vector3(10.8, cfg.ball_radius_m, -20.0))
	run_ball.set_control(run_carrier, run_ball.global_position)
	var fullback := _make_view(starters[3], strong_club, true, Vector3(4, 1, -25), run_ctx, 3)
	_check(run_ctx.can_overlap(fullback, effects.context), "wide player behind the carrier can overlap")
	var overlap_decision := brain.decide(fullback, run_ctx)
	_check(overlap_decision.action == FMEnums.Action.OVERLAP, "overlapping fullback chooses the run (%s)" % overlap_decision.best_action_name())
	var overlap_target: Vector3 = run_ctx.overlap_target(fullback, effects.context)
	_check(overlap_target.x > fullback.global_position.x and overlap_target.z < fullback.global_position.z, "overlap target advances beyond and outside the carrier")
	var overlap_agent := PlayerAgent.new(fullback, brain, run_ctx, effects)
	overlap_agent.decision_timer = 10.0
	fullback.last_decision = overlap_decision
	overlap_agent.physics_tick(1.0 / 60.0)
	_check(run_ball.control_owner == run_carrier, "overlapping runner does not take control from the carrier")

	var normal_speed := float(overlap_agent.call("_move_speed"))
	var original_pace: int = fullback.player_data.attributes.pace
	fullback.player_data.attributes.pace = 20
	var quick_speed := float(overlap_agent.call("_move_speed"))
	fullback.player_data.attributes.pace = 1
	var slow_speed := float(overlap_agent.call("_move_speed"))
	fullback.player_data.attributes.pace = original_pace
	_check(quick_speed > slow_speed + 0.5, "pace attribute varies top speed (%.2f vs %.2f)" % [quick_speed, slow_speed])
	var original_stamina: float = fullback.match_state.stamina
	fullback.match_state.stamina = 5.0
	var tired_speed := float(overlap_agent.call("_move_speed"))
	fullback.match_state.stamina = original_stamina
	_check(tired_speed < normal_speed, "low stamina slows a player further")

	run_ctx.team_instructions[strong_club.id] = TeamInstructions.new().with_overrides({"tempo": "FAST"})
	var fast_pulse := run_ctx.tempo_pulse(fullback, effects.context)
	run_ctx.team_instructions[strong_club.id] = TeamInstructions.new().with_overrides({"tempo": "SLOW"})
	var slow_pulse := run_ctx.tempo_pulse(fullback, effects.context)
	_check(fast_pulse > slow_pulse + 0.5, "team tempo biases the shared match pulse")
	run_ball.release_control()
	for view in run_ctx.views:
		view.free()
	run_ball.free()


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
	_check(goal_kick.x > 40.0 and absf(goal_kick.z) <= cfg.goal_area_width_m * 0.5 + 0.01, "goal kick stays inside the six-yard box")
	_check(absf(goal_kick.z) > cfg.goal_width_m * 0.5, "goal kick may be wider than the goal")
	var corner := restart.apply(ball, FMEnums.RestartType.CORNER, Vector3(52, 1, 30), cfg)
	_check(corner.x > 45.0 and absf(corner.z) > 30.0, "corner is placed in the corner arc")
	var penalty := restart.apply(ball, FMEnums.RestartType.PENALTY, Vector3(52, 1, 0), cfg)
	_check(absf(penalty.x - (cfg.pitch_length_m * 0.5 - 11.0)) < 0.01, "penalty is placed on the spot")
	var free_kick := restart.apply(ball, FMEnums.RestartType.FREE_KICK, Vector3(60, 1, 50), cfg)
	_check(absf(free_kick.x) <= cfg.pitch_length_m * 0.5 and absf(free_kick.z) <= cfg.pitch_width_m * 0.5, "free kick is brought back in play")

	# Restart bodies are placed legally, and the opposition cannot play a goal
	# kick before the ball has left the penalty area.
	var restart_gk := _make_view(weak_club.get_starters()[0], weak_club, false, Vector3(48, 1, 0), ctx, 0)
	var restart_attacker := _make_view(strong_club.get_starters()[9], strong_club, true, Vector3(40, 1, 0), ctx, 9)
	var gk_spot := restart.apply(ball, FMEnums.RestartType.GOAL_KICK, Vector3(52, 1, 8), cfg)
	restart.position_players(ctx, FMEnums.RestartType.GOAL_KICK, gk_spot, FMEnums.Side.AWAY, cfg)
	_check(MatchContext.flat_distance(restart_gk.global_position, gk_spot) < 2.5, "goal-kick taker stands behind the ball")
	_check(restart_attacker.global_position.x <= cfg.pitch_length_m * 0.5 - cfg.penalty_area_depth_m + 0.01, "opponents clear the penalty area at goal kicks")
	var restart_brain := DecisionBrain.new(effects)
	var restart_agent := PlayerAgent.new(restart_attacker, restart_brain, ctx, effects)
	restart_agent.decision_timer = 10.0
	restart_attacker.last_decision = DecisionResult.create(FMEnums.Action.SUPPORT, gk_spot, {}, "")
	restart_attacker.global_position = gk_spot + Vector3(-0.5, 1.0, 0.0)
	ctx.match_state = FMEnums.MatchState.PLAYING
	ctx.restart_type = FMEnums.RestartType.GOAL_KICK
	ctx.restart_side = FMEnums.Side.AWAY
	ctx.restart_spot = gk_spot
	restart_agent.physics_tick(1.0 / 60.0)
	_check(ball.control_owner == null, "opposition cannot take the goal kick early")
	ctx.restart_type = -1
	ctx.restart_side = -1
	restart_agent.physics_tick(1.0 / 60.0)
	_check(ball.control_owner == restart_attacker, "opposition can play once the goal kick is released")
	ball.release_control()
	restart_attacker.global_position = Vector3(40, 1, 0)
	ctx.match_state = FMEnums.MatchState.PLAYING

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

	# A shot heading into the goal is parried by a keeper in reach.
	engine.state = FMEnums.MatchState.PLAYING
	engine_ctx.match_state = FMEnums.MatchState.PLAYING
	var keeper := _make_view(strong_club.get_starters()[0], strong_club, true, Vector3(-48, 1, 0), engine_ctx, 0)
	engine_ball.reset_to(Vector3(-47, cfg.ball_radius_m, 0))
	engine_ball.linear_velocity = Vector3(-15.0, 0.0, 0.0)
	var save_event: RuleEvent = engine.keeper_rule.tick(1.0 / 60.0, engine_ctx)
	_check(save_event != null and save_event.type == RuleEvent.Type.SAVE, "keeper in reach parries a shot")
	_check(engine_ball.linear_velocity.x > 0.0, "parry clears the ball away from the keeper's goal")
	engine_ctx.views.erase(keeper)
	keeper.free()

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


func _test_stats() -> void:
	var stats := MatchStats.new()
	stats.record_kick(FMEnums.Side.HOME, false)
	stats.record_kick(FMEnums.Side.HOME, true)
	stats.record_control(FMEnums.Side.HOME, 12.5)
	stats.record_control(FMEnums.Side.AWAY, 7.5)
	stats.record_event(RuleEvent.create(RuleEvent.Type.GOAL, "home goal", "", FMEnums.Side.HOME))
	stats.record_event(RuleEvent.create(
		RuleEvent.Type.FOUL, "foul", "", FMEnums.Side.AWAY,
		FMEnums.FoulSeverity.YELLOW, FMEnums.RestartType.FREE_KICK
	))
	var data: Dictionary = stats.to_dict()
	var home: Dictionary = data["home"]
	var away: Dictionary = data["away"]
	_check(int(home["shots"]) == 1 and int(home["passes"]) == 1, "match stats count shots and passes by side")
	_check(is_equal_approx(float(home["control_seconds"]), 12.5), "match stats accumulate possession time")
	_check(int(home["goals"]) == 1, "goal events credit the scoring side")
	_check(int(home["fouls"]) == 1 and int(home["yellow_cards"]) == 1, "foul events credit the offender, not the victim")
	_check(int(away["fouls"]) == 0, "fouls are not charged to the fouled side")
	var parsed: Variant = JSON.parse_string(stats.summary())
	_check(parsed is Dictionary, "stats summary is valid JSON")


func _test_stats_detail() -> void:
	var stats := MatchStats.new()
	stats.record_kick(FMEnums.Side.HOME, true, "pass", "p1", "p2")
	stats.record_pass_completion("p1", "p2", FMEnums.Side.HOME, "p2")
	stats.record_tackle_attempt("p3", FMEnums.Side.HOME)
	stats.record_tackle_win("p3", FMEnums.Side.HOME)
	stats.record_event(RuleEvent.create(
		RuleEvent.Type.FOUL, "foul", "p3", FMEnums.Side.AWAY,
		FMEnums.FoulSeverity.YELLOW, FMEnums.RestartType.FREE_KICK
	))
	var data: Dictionary = stats.to_dict()
	var side: Dictionary = data["home"]
	var players: Dictionary = data["players"]
	var passer: Dictionary = players["p1"]
	var tackler: Dictionary = players["p3"]
	_check(int(side["passes_completed"]) == 1 and int(side["passes_to_target"]) == 1, "team pass completion counts the intended receiver")
	_check(int(passer["passes_attempted"]) == 1 and int(passer["passes_completed"]) == 1, "player pass completion is recorded")
	_check(int(tackler["tackles"]) == 1 and int(tackler["tackle_wins"]) == 1, "player tackle attempts and wins are recorded")
	_check(int(tackler["fouls"]) == 1 and int(tackler["yellow_cards"]) == 1, "foul and card credit the offender's player record")
	_check(not players.has(""), "stats do not create an empty player record")


func _test_history_and_analysis() -> void:
	var stats := MatchStats.new()
	var home: Dictionary = stats.get_side(FMEnums.Side.HOME)
	home["passes_attempted"] = 100
	home["passes_completed"] = 10
	home["tackles"] = 30
	home["tackle_wins"] = 3
	home["fouls"] = 6
	home["shots"] = 2
	home["control_seconds"] = 600.0
	home["goals"] = 0
	var club_id := GameData.clubs[0].id
	stats.get_side(FMEnums.Side.AWAY)["control_seconds"] = 1200.0
	stats.get_side(FMEnums.Side.AWAY)["goals"] = 2
	var first := MatchRecord.new()
	first.fixture_id = "analysis-1"
	first.source = "test"
	first.home_club_id = club_id
	first.away_club_id = GameData.clubs[1].id
	first.stats = stats.to_dict()
	var second := MatchRecord.new()
	second.fixture_id = "analysis-2"
	second.source = "test"
	second.home_club_id = GameData.clubs[2].id
	second.away_club_id = club_id
	second.stats = stats.to_dict()

	var history := MatchHistory.new()
	history.add(first)
	history.add(second)
	_check(history.find_fixture("analysis-1") == first and history.latest() == second, "history finds records by fixture and exposes the latest")
	var effects := StatEffects.load()
	var report: Dictionary = history.analysis(effects)
	var clubs: Dictionary = report["clubs"]
	var club: Dictionary = clubs[club_id]
	_check(is_equal_approx(float(club["pass_completion_rate"]), 0.1), "analysis calculates pass completion from attempts and completions")
	_check(is_equal_approx(float(club["tackle_win_rate"]), 0.1), "analysis calculates tackle win rate")
	_check(is_equal_approx(float(club["fouls_per_tackle"]), 0.2), "analysis calculates fouls per tackle")
	var codes: Array[String] = []
	for issue in report["issues"]:
		codes.append(String((issue as Dictionary)["code"]))
	_check(codes.has("low_pass_completion") and codes.has("unproductive_tackling"), "analysis flags low completion and unproductive tackling")
	_check(history.analysis_text(effects).contains("Player leaders"), "analysis text includes player leaders")

	var previous_path: String = SaveGame.save_path
	SaveGame.set_path("user://fm-history-test.json")
	_check(history.save(), "match history saves through SaveGame")
	var loaded := MatchHistory.new()
	_check(loaded.load() and loaded.records.size() == 2, "match history reloads from JSON")
	_check(loaded.records[0].fixture_id == "analysis-1", "saved history keeps fixture identity")
	var manager := SeasonManager.new()
	_check(manager.new_season(GameData.leagues[0], GameData.clubs), "season manager builds a season for the save-preservation check")
	_check(manager.save(), "season saves after history was written")
	_check((SaveGame.load_state() as Dictionary).has("match_history"), "season save preserves non-season keys")
	SaveGame.set_path(previous_path)


func _test_fast_simulation() -> void:
	var effects := StatEffects.load()
	var rules_config := RulesConfig.load()
	_check(effects != null and rules_config != null, "fast simulation tuning loads")
	if effects == null or rules_config == null:
		return
	var fixture: Fixture = FixtureGenerator.generate(GameData.leagues[0])[0]
	var simulator := FastMatchSimulator.new(effects, rules_config)
	RngService.set_seed(9001)
	var first := simulator.simulate(fixture)
	RngService.set_seed(9001)
	var second := simulator.simulate(fixture)
	_check(first != null and second != null, "fast simulator produces a match record")
	if first == null or second == null:
		return
	var first_signature := JSON.stringify({"home_goals": first.home_goals, "away_goals": first.away_goals, "stats": first.stats})
	var second_signature := JSON.stringify({"home_goals": second.home_goals, "away_goals": second.away_goals, "stats": second.stats})
	_check(first_signature == second_signature, "fast simulation is deterministic for a fixed seed")
	_check(first.source == "fast", "fast simulation records its source")
	_check(int((first.stats["home"] as Dictionary)["passes_attempted"]) > 0, "fast simulation records passes")
	_check((first.stats["players"] as Dictionary).size() == 22, "fast simulation records all 22 starters")
	var max_goals: int = int((first.stats["home"] as Dictionary)["goals"]) + int((first.stats["away"] as Dictionary)["goals"])
	_check(max_goals >= 0 and max_goals < 25, "fast simulation produces a plausible score")
	_check(first.home_goals >= 0 and first.away_goals >= 0, "fast simulation result uses the recorded score")


func _test_physics() -> void:
	var pitch_scene: PackedScene = load("res://scenes/pitch.tscn")
	var pitch: Node = pitch_scene.instantiate()
	add_child(pitch)
	var ground: StaticBody3D = pitch.find_child("GroundCollider", true, false) as StaticBody3D
	_check(ground != null, "pitch creates a static ground collider")
	if ground != null:
		var collision: CollisionShape3D = ground.find_child("GroundShape", true, false) as CollisionShape3D
		var box: BoxShape3D = null
		if collision != null:
			box = collision.shape as BoxShape3D
		_check(box != null and box.size.x >= GameData.config.pitch_length_m, "ground collider spans the pitch (size %s)" % [box.size if box != null else Vector3.ZERO])

	var ctx := MatchContext.new()
	var club: ClubData = GameData.clubs[0]
	var falling := _make_view(club.get_starters()[9], club, true, Vector3(0, 3.0, 0), ctx)
	for i in 120:
		await get_tree().physics_frame
	_check(falling.global_position.y > 0.5, "players settle on the pitch instead of falling through it")
	_check(absf(falling.linear_velocity.y) < 0.5, "ground contact stops vertical acceleration (vy %.2f, y %.2f)" % [falling.linear_velocity.y, falling.global_position.y])
	falling.free()

	var effects := StatEffects.load()
	if effects == null:
		pitch.free()
		return
	var brain := DecisionBrain.new(effects)
	var same_delta: float = await _separation_distance(false, club, effects, brain)
	var opponent_delta: float = await _separation_distance(true, club, effects, brain)
	_check(same_delta > 0.05, "nearby players push apart instead of clumping")
	_check(opponent_delta > same_delta, "opponents push apart harder than team-mates (%.6f vs %.6f)" % [opponent_delta, same_delta])
	pitch.free()


func _separation_distance(opponents: bool, club: ClubData, effects: StatEffects, brain: DecisionBrain) -> float:
	var ctx := MatchContext.new()
	var left := _make_view(club.get_starters()[5], club, true, Vector3(0, 0.9, 0), ctx)
	var right := _make_view(club.get_starters()[6], club, not opponents, Vector3(1.0, 0.9, 0), ctx)
	for view in [left, right]:
		view.collision_layer = 0
		view.collision_mask = 0
		view.last_decision = DecisionResult.create(FMEnums.Action.SUPPORT, view.global_position, {}, "")
	var left_agent := PlayerAgent.new(left, brain, ctx, effects)
	var right_agent := PlayerAgent.new(right, brain, ctx, effects)
	left_agent.decision_timer = 10.0
	right_agent.decision_timer = 10.0
	for i in 12:
		left_agent.physics_tick(1.0 / 60.0)
		right_agent.physics_tick(1.0 / 60.0)
		await get_tree().physics_frame
	var delta := absf(left.global_position.x - right.global_position.x) - 1.0
	left.free()
	right.free()
	return delta


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
	var slots_ready := true
	for view in views:
		if view.call("get_instructions") == null or view.call("get_match_state") == null:
			tactical_ready = false
		if (view as RigidBody3D).formation_slot == Vector2.ZERO:
			slots_ready = false
	_check(tactical_ready, "all 22 starters carry instructions and match state")
	_check(slots_ready, "all players carry a formation slot")
	var agents: Array = instance.call("get_agents")
	_check(agents.size() == 22, "match scene builds 22 decision agents")
	var camera := instance.find_child("MatchCamera", true, false)
	_check(camera != null, "match scene has a match camera")
	var scene_ball: Ball = instance.call("get_ball")
	if camera != null:
		_check(int(camera.get("mode")) == CameraRig.Mode.FOLLOW, "camera defaults to follow-ball view")
		_check(camera.get("follow_target") == scene_ball, "camera follows the ball")
		_check(scene_ball.find_child("Marker", true, false) != null, "ball has a visibility marker")
	var match_ground := instance.find_child("GroundCollider", true, false)
	_check(match_ground != null, "match scene pitch has a ground collider")
	var score_label: Label = instance.find_child("ScoreLabel", true, false)
	var clock_label: Label = instance.find_child("ClockLabel", true, false)
	var event_label: Label = instance.find_child("EventLabel", true, false)
	_check(score_label != null and clock_label != null and event_label != null, "match scene has a compact HUD")
	if score_label != null:
		_check(score_label.text.contains("-"), "HUD shows the score")
	var scene_stats: MatchStats = instance.call("get_stats")
	_check(scene_stats != null, "match scene tracks calibration stats")
	scene_ball.apply_player_kick(views[0], false, Vector3(1, 0, 0), 5.0, 0.0, 0.0, 0.0)
	var scene_data: Dictionary = scene_stats.to_dict()
	var home_data: Dictionary = scene_data["home"]
	_check(int(home_data["shots"]) == 1, "match scene records a shot through the kick hook")
	var moved := views[9] as RigidBody3D
	moved.global_position = Vector3(-40.0, 1.0, 0.0)
	var match_rules: RulesEngine = instance.call("get_rules_engine")
	match_rules.call("_begin_restart", FMEnums.RestartType.KICKOFF, Vector3.ZERO, -1)
	_check(moved.global_position.x < 0.0 and moved.global_position.x > -30.0, "kickoff puts players back in their own half")
	_check(absf(scene_ball.global_position.x) < 0.01 and absf(scene_ball.global_position.z) < 0.01, "kickoff resets the ball to centre")
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
