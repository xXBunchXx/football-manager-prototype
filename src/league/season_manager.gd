class_name SeasonManager
extends RefCounted

## Owns season progress and persistence. Pure logic lives here; the autoload
## wrapper only exposes it to scenes.

signal changed

var season: SeasonState = null
var table := LeagueTable.new()
var last_error: String = ""


func new_season(league: LeagueData, clubs: Array[ClubData]) -> bool:
	var fixtures := FixtureGenerator.generate(league)
	if fixtures.is_empty():
		last_error = "fixture generation failed"
		return false
	season = SeasonState.new()
	season.league_id = league.id
	season.fixtures = fixtures
	table.build(_club_ids(clubs), season.fixtures)
	last_error = ""
	changed.emit()
	return true


func load_or_new(league: LeagueData, clubs: Array[ClubData]) -> bool:
	var stored: Variant = SaveGame.load_state().get("season", null)
	if stored is Dictionary:
		var loaded := SeasonState.from_dict(stored)
		if loaded != null and loaded.league_id == league.id and loaded.fixtures.size() == FixtureGenerator.generate(league).size():
			season = loaded
			table.build(_club_ids(clubs), season.fixtures)
			last_error = ""
			changed.emit()
			return true
		last_error = "saved season did not match the league; starting a new one"
	return new_season(league, clubs)


func save() -> bool:
	if season == null:
		return false
	# Preserve the analysis history and any future save keys; a season write is
	# an update to the save file, not a replacement of the whole file.
	var state := SaveGame.load_state()
	state["season"] = season.to_dict()
	return SaveGame.save_state(state)


func record_result(result: MatchResult) -> bool:
	if season == null or result == null:
		return false
	var fixture := season.fixture_by_id(result.fixture_id)
	if fixture == null or fixture.played:
		return false
	if fixture.home_club_id != result.home_club_id or fixture.away_club_id != result.away_club_id:
		return false
	fixture.played = true
	fixture.home_goals = result.home_goals
	fixture.away_goals = result.away_goals
	if not table.apply_result(result):
		return false
	save()
	changed.emit()
	return true


func fixtures() -> Array[Fixture]:
	return season.fixtures if season != null else []


static func _club_ids(clubs: Array[ClubData]) -> Array[String]:
	var result: Array[String] = []
	for club in clubs:
		result.append(club.id)
	return result
