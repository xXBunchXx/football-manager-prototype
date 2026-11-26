extends Control

## Minimal competition screen: standings plus one button per unplayed fixture.
## Every fixture is playable in the live match scene; nothing is auto-simmed.

@onready var title_label: Label = $Layout/Title
@onready var table_label: Label = $Layout/TableLabel
@onready var fixture_list: VBoxContainer = $Layout/FixtureScroll/FixtureList
@onready var play_next_button: Button = $Layout/Buttons/PlayNextButton
@onready var reset_button: Button = $Layout/Buttons/ResetButton


func _ready() -> void:
	LeagueManager.changed.connect(_refresh)
	play_next_button.pressed.connect(_on_play_next_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	_refresh()


func _refresh() -> void:
	var season: SeasonState = LeagueManager.get_season()
	if season == null:
		title_label.text = "No season loaded"
		table_label.text = ""
		return
	var league_name := GameData.leagues[0].name if not GameData.leagues.is_empty() else season.league_id
	title_label.text = "%s — round %d, %d/%d played" % [
		league_name,
		maxf(1.0, float(season.next_round())),
		season.played_count(),
		season.fixtures.size(),
	]
	table_label.text = _table_text()
	_clear_fixtures()
	for fixture in LeagueManager.get_fixtures():
		var button := Button.new()
		var score := "" if not fixture.played else "  (%d-%d)" % [fixture.home_goals, fixture.away_goals]
		button.text = "R%d  %s  vs  %s%s" % [
			fixture.round,
			_short_name(fixture.home_club_id),
			_short_name(fixture.away_club_id),
			score,
		]
		button.disabled = fixture.played
		if not fixture.played:
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


func _on_play_next_pressed() -> void:
	var season: SeasonState = LeagueManager.get_season()
	if season == null:
		return
	var unplayed := season.unplayed_fixtures()
	if not unplayed.is_empty():
		_play(unplayed[0].id)


func _on_reset_pressed() -> void:
	LeagueManager.reset_season()
	_refresh()
