extends Node

## Scene-facing singleton for season progress. RngService and GameData are
## loaded before this autoload, so fixtures can be built on ready.

signal changed

var manager := SeasonManager.new()
var history := MatchHistory.new()
var selected_fixture_id: String = ""
var effects: StatEffects = null
var rules_config: RulesConfig = null


func _ready() -> void:
	manager.changed.connect(_on_manager_changed)
	effects = StatEffects.load()
	rules_config = RulesConfig.load()
	if effects == null or rules_config == null:
		push_error("LeagueManager: statistics or rules tuning failed to load")
	history.load()
	if GameData.leagues.is_empty():
		push_error("LeagueManager: no league fixture loaded")
		return
	var league: LeagueData = GameData.leagues[0]
	if not manager.load_or_new(league, GameData.clubs):
		push_error("LeagueManager: %s" % manager.last_error)


func _on_manager_changed() -> void:
	changed.emit()


func get_season() -> SeasonState:
	return manager.season


func get_fixtures() -> Array[Fixture]:
	return manager.fixtures()


func get_standings() -> Array[LeagueTableRow]:
	return manager.table.standings()


func get_fixture(fixture_id: String) -> Fixture:
	var season: SeasonState = manager.season
	return season.fixture_by_id(fixture_id) if season != null else null


func select_fixture(fixture_id: String) -> bool:
	var fixture := get_fixture(fixture_id)
	if fixture == null or fixture.played:
		return false
	selected_fixture_id = fixture_id
	return true


func get_selected_fixture() -> Fixture:
	if selected_fixture_id.is_empty():
		return null
	return get_fixture(selected_fixture_id)


func record_result(result: MatchResult) -> bool:
	var accepted := manager.record_result(result)
	if accepted and result.fixture_id == selected_fixture_id:
		selected_fixture_id = ""
	return accepted


func reset_season() -> bool:
	if GameData.leagues.is_empty():
		return false
	var league: LeagueData = GameData.leagues[0]
	selected_fixture_id = ""
	var accepted := manager.new_season(league, GameData.clubs)
	if accepted:
		history.clear()
		history.save()
	return accepted


func save() -> bool:
	return manager.save()


func record_match(record: MatchRecord) -> bool:
	if record == null:
		return false
	history.add(record)
	history.save()
	changed.emit()
	return true


## Bulk-simulates fixtures without rendering and records both the score and the
## full player/team statistics. Results go through SeasonManager so the table,
## fixture state and save file stay consistent with live matches.
func simulate_fixtures(fixtures: Array) -> Array[MatchRecord]:
	var result: Array[MatchRecord] = []
	if effects == null or rules_config == null:
		return result
	var simulator := FastMatchSimulator.new(effects, rules_config)
	for fixture in fixtures:
		if fixture == null or fixture.played:
			continue
		var record := simulator.simulate(fixture, "fast")
		if record == null:
			continue
		var match_result := MatchResult.create(fixture, record.home_goals, record.away_goals)
		if manager.record_result(match_result):
			history.add(record)
			result.append(record)
	history.save()
	changed.emit()
	return result


func simulate_round() -> Array[MatchRecord]:
	var season := get_season()
	if season == null:
		return []
	var round_number := season.next_round()
	var fixtures: Array = []
	for fixture in season.fixtures:
		if fixture.round == round_number and not fixture.played:
			fixtures.append(fixture)
	return simulate_fixtures(fixtures)


func simulate_season() -> Array[MatchRecord]:
	var season := get_season()
	if season == null:
		return []
	return simulate_fixtures(season.unplayed_fixtures())


func get_match_record(fixture_id: String) -> MatchRecord:
	return history.find_fixture(fixture_id)


func get_latest_match_record() -> MatchRecord:
	return history.latest()


func format_match(record: MatchRecord) -> String:
	return history.format_match(record)


func get_analysis() -> Dictionary:
	return history.analysis(effects)


func get_analysis_text() -> String:
	return history.analysis_text(effects)
