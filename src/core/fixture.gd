class_name Fixture
extends Resource

## One scheduled league match. Played fixtures retain their score so the table
## can be rebuilt from the fixture list alone.

const REQUIRED_KEYS := [
	"id", "round", "home_club_id", "away_club_id", "played", "home_goals", "away_goals",
]

@export var id: String = ""
@export var round: int = 0
@export var home_club_id: String = ""
@export var away_club_id: String = ""
@export var played: bool = false
@export var home_goals: int = 0
@export var away_goals: int = 0


func to_dict() -> Dictionary:
	return {
		"id": id,
		"round": round,
		"home_club_id": home_club_id,
		"away_club_id": away_club_id,
		"played": played,
		"home_goals": home_goals,
		"away_goals": away_goals,
	}


static func from_dict(data: Dictionary) -> Fixture:
	if not FixtureLoader.has_keys(data, REQUIRED_KEYS):
		push_error("Fixture: missing required keys")
		return null
	for key in ["round", "home_goals", "away_goals"]:
		if not (data[key] is int or data[key] is float):
			push_error("Fixture: numeric fields must be numbers")
			return null
	if not (data["played"] is bool):
		push_error("Fixture: played must be a boolean")
		return null
	var fixture := Fixture.new()
	fixture.id = String(data["id"])
	fixture.round = int(data["round"])
	fixture.home_club_id = String(data["home_club_id"])
	fixture.away_club_id = String(data["away_club_id"])
	fixture.played = bool(data["played"])
	fixture.home_goals = int(data["home_goals"])
	fixture.away_goals = int(data["away_goals"])
	if fixture.id.is_empty() or fixture.home_club_id.is_empty() or fixture.away_club_id.is_empty():
		push_error("Fixture: ids must not be empty")
		return null
	return fixture
