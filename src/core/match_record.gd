class_name MatchRecord
extends RefCounted

## One completed match in the analysis history. The score lives in the season
## fixtures; this record keeps the team and per-player statistics that explain it.

const SAVE_VERSION := 1
const REQUIRED_KEYS := [
	"version", "timestamp", "source", "fixture_id", "round",
	"home_club_id", "away_club_id", "home_goals", "away_goals", "stats",
]

var timestamp: String = ""
var source: String = ""
var fixture_id: String = ""
var round: int = 0
var home_club_id: String = ""
var away_club_id: String = ""
var home_goals: int = 0
var away_goals: int = 0
var stats: Dictionary = {}


static func from_match(fixture: Fixture, result: MatchResult, match_stats: Dictionary, source_value: String = "live") -> MatchRecord:
	var record := MatchRecord.new()
	record.timestamp = Time.get_datetime_string_from_system()
	record.source = source_value
	record.fixture_id = result.fixture_id
	record.round = fixture.round if fixture != null else 0
	record.home_club_id = result.home_club_id
	record.away_club_id = result.away_club_id
	record.home_goals = result.home_goals
	record.away_goals = result.away_goals
	record.stats = match_stats.duplicate(true)
	return record


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"timestamp": timestamp,
		"source": source,
		"fixture_id": fixture_id,
		"round": round,
		"home_club_id": home_club_id,
		"away_club_id": away_club_id,
		"home_goals": home_goals,
		"away_goals": away_goals,
		"stats": stats.duplicate(true),
	}


static func from_dict(data: Dictionary) -> MatchRecord:
	if not FixtureLoader.has_keys(data, REQUIRED_KEYS):
		push_error("MatchRecord: missing required keys")
		return null
	if int(data["version"]) != SAVE_VERSION or not (data["stats"] is Dictionary):
		push_error("MatchRecord: unsupported version or invalid stats")
		return null
	var record := MatchRecord.new()
	record.timestamp = String(data["timestamp"])
	record.source = String(data["source"])
	record.fixture_id = String(data["fixture_id"])
	record.round = int(data["round"])
	record.home_club_id = String(data["home_club_id"])
	record.away_club_id = String(data["away_club_id"])
	record.home_goals = int(data["home_goals"])
	record.away_goals = int(data["away_goals"])
	record.stats = (data["stats"] as Dictionary).duplicate(true)
	return record
