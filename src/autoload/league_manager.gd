extends Node

## Scene-facing singleton for season progress. RngService and GameData are
## loaded before this autoload, so fixtures can be built on ready.

signal changed

var manager := SeasonManager.new()
var selected_fixture_id: String = ""


func _ready() -> void:
	manager.changed.connect(_on_manager_changed)
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
	return manager.new_season(league, GameData.clubs)


func save() -> bool:
	return manager.save()
