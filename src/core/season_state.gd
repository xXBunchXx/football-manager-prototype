class_name SeasonState
extends Resource

## Mutable season progress. The fixture list is the single source of truth;
## standings are rebuilt from it so saves cannot disagree with results.

const SAVE_VERSION := 1
const REQUIRED_KEYS := ["version", "league_id", "fixtures"]

@export var league_id: String = ""
@export var fixtures: Array[Fixture] = []


func to_dict() -> Dictionary:
	var fixture_data: Array = []
	for fixture in fixtures:
		fixture_data.append(fixture.to_dict())
	return {
		"version": SAVE_VERSION,
		"league_id": league_id,
		"fixtures": fixture_data,
	}


static func from_dict(data: Dictionary) -> SeasonState:
	if not FixtureLoader.has_keys(data, REQUIRED_KEYS):
		push_error("SeasonState: missing required keys")
		return null
	if int(data["version"]) != SAVE_VERSION or not (data["fixtures"] is Array):
		push_error("SeasonState: unsupported version or invalid fixtures")
		return null
	var season := SeasonState.new()
	season.league_id = String(data["league_id"])
	var seen: Dictionary = {}
	for entry in data["fixtures"]:
		if not (entry is Dictionary):
			push_error("SeasonState: fixture entry is not an object")
			return null
		var fixture := Fixture.from_dict(entry)
		if fixture == null or seen.has(fixture.id):
			push_error("SeasonState: invalid or duplicate fixture")
			return null
		seen[fixture.id] = true
		season.fixtures.append(fixture)
	return season


func fixture_by_id(fixture_id: String) -> Fixture:
	for fixture in fixtures:
		if fixture.id == fixture_id:
			return fixture
	return null


func unplayed_fixtures() -> Array[Fixture]:
	var result: Array[Fixture] = []
	for fixture in fixtures:
		if not fixture.played:
			result.append(fixture)
	return result


func next_round() -> int:
	var best := -1
	for fixture in fixtures:
		if not fixture.played and (best < 0 or fixture.round < best):
			best = fixture.round
	return best


func played_count() -> int:
	var count := 0
	for fixture in fixtures:
		if fixture.played:
			count += 1
	return count
