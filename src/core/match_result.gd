class_name MatchResult
extends Resource

## Final score handed from the match engine to the league layer.

@export var fixture_id: String = ""
@export var home_club_id: String = ""
@export var away_club_id: String = ""
@export var home_goals: int = 0
@export var away_goals: int = 0


static func create(fixture: Fixture, home_goals_value: int, away_goals_value: int) -> MatchResult:
	var result := MatchResult.new()
	result.fixture_id = fixture.id
	result.home_club_id = fixture.home_club_id
	result.away_club_id = fixture.away_club_id
	result.home_goals = home_goals_value
	result.away_goals = away_goals_value
	return result
