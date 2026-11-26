extends Control

## Competition screen: standings, fixtures, bulk simulation and match analysis.
## Unplayed fixtures open the live physics match; played fixtures open their
## saved team/player statistics instead of replaying the score.

@onready var title_label: Label = $Layout/Title
@onready var table_label: Label = $Layout/TableLabel
@onready var fixture_list: VBoxContainer = $Layout/FixtureScroll/FixtureList
@onready var play_next_button: Button = $Layout/Buttons/PlayNextButton
@onready var sim_round_button: Button = $Layout/Buttons/SimRoundButton
@onready var sim_season_button: Button = $Layout/Buttons/SimSeasonButton
@onready var analysis_button: Button = $Layout/Buttons/AnalysisButton
@onready var reset_button: Button = $Layout/Buttons/ResetButton
@onready var stats_label: Label = $Layout/StatsScroll/StatsLabel


func _ready() -> void:
	LeagueManager.changed.connect(_refresh)
	play_next_button.pressed.connect(_on_play_next_pressed)
	sim_round_button.pressed.connect(_on_sim_round_pressed)
	sim_season_button.pressed.connect(_on_sim_season_pressed)
	analysis_button.pressed.connect(_on_analysis_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	_refresh()


func _refresh() -> void:
	var season: SeasonState = LeagueManager.get_season()
	if season == null:
		title_label.text = "No season loaded"
		table_label.text = ""
		stats_label.text = ""
		return
	var league_name := GameData.leagues[0].name if not GameData.leagues.is_empty() else season.league_id
	title_label.text = "%s — round %d, %d/%d played" % [
		league_name,
		maxf(1.0, float(season.next_round())),
		season.played_count(),
		season.fixtures.size(),
	]
	table_label.text = _table_text()
	stats_label.text = LeagueManager.format_match(LeagueManager.get_latest_match_record())
	_clear_fixtures()
	for fixture in LeagueManager.get_fixtures():
		var button := Button.new()
		var score := "" if not fixture.played else "  (%d-%d, stats)" % [fixture.home_goals, fixture.away_goals]
		button.text = "R%d  %s  vs  %s%s" % [
			fixture.round,
			_short_name(fixture.home_club_id),
			_short_name(fixture.away_club_id),
			score,
		]
		button.disabled = false
		if fixture.played:
			button.pressed.connect(_show_match.bind(fixture.id))
		else:
			button.pressed.connect(_play.bind(fixture.id))
		fixture_list.add_child(button)


func _table_text() -> String:
	var lines: Array[String] = []
	var position := 1
	for row in LeagueManager.get_standings():
		lines.append("%d. %s  P%d W%d D%d L%d GF%d GA%d GD%d Pts%d  %s" % [
			position,
			_short_name(row.club_id),
			row.played,
			row.won,
			row.drawn,
			row.lost,
			row.goals_for,
			row.goals_against,
			row.goal_difference(),
			row.points,
			" ".join(row.form),
		])
		position += 1
	return "\n".join(lines)


func _short_name(club_id: String) -> String:
	for club in GameData.clubs:
		if club.id == club_id:
			return club.short_name
	return club_id


func _clear_fixtures() -> void:
	for child in fixture_list.get_children():
		fixture_list.remove_child(child)
		child.queue_free()


func _play(fixture_id: String) -> void:
	if LeagueManager.select_fixture(fixture_id):
		get_tree().change_scene_to_file("res://scenes/match_scene.tscn")


func _show_match(fixture_id: String) -> void:
	var record := LeagueManager.get_match_record(fixture_id)
	if record == null:
		var fixture := LeagueManager.get_fixture(fixture_id)
		if fixture != null:
			record = MatchRecord.from_match(
				fixture,
				MatchResult.create(fixture, fixture.home_goals, fixture.away_goals),
				{}, "live"
			)
	stats_label.text = LeagueManager.format_match(record)


func _on_play_next_pressed() -> void:
	var season: SeasonState = LeagueManager.get_season()
	if season == null:
		return
	var unplayed := season.unplayed_fixtures()
	if not unplayed.is_empty():
		_play(unplayed[0].id)


func _on_sim_round_pressed() -> void:
	var simulated := LeagueManager.simulate_round()
	if simulated.is_empty():
		stats_label.text = "No unplayed fixtures in the next round."
		return
	stats_label.text = "Simulated %d matches.\n\n%s" % [
		simulated.size(), LeagueManager.format_match(simulated[simulated.size() - 1])
	]


func _on_sim_season_pressed() -> void:
	var simulated := LeagueManager.simulate_season()
	if simulated.is_empty():
		stats_label.text = "No unplayed fixtures left."
		return
	stats_label.text = "Simulated %d matches.\n\n%s" % [
		simulated.size(), LeagueManager.format_match(simulated[simulated.size() - 1])
	]


func _on_analysis_pressed() -> void:
	stats_label.text = LeagueManager.get_analysis_text()


func _on_reset_pressed() -> void:
	LeagueManager.reset_season()
	_refresh()
