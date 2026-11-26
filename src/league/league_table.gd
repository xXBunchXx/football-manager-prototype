class_name LeagueTable
extends RefCounted

## Standings derived from played fixtures. Duplicate results are ignored so a
## replayed fixture cannot score twice.

var rows: Dictionary = {}
var applied_fixture_ids: Dictionary = {}


func build(club_ids: Array[String], fixtures: Array[Fixture]) -> void:
	rows.clear()
	applied_fixture_ids.clear()
	for club_id in club_ids:
		var row := LeagueTableRow.new()
		row.club_id = club_id
		rows[club_id] = row
	for fixture in fixtures:
		if fixture.played:
			apply_result(MatchResult.create(fixture, fixture.home_goals, fixture.away_goals))


func apply_result(result: MatchResult) -> bool:
	if applied_fixture_ids.has(result.fixture_id):
		return false
	if not rows.has(result.home_club_id) or not rows.has(result.away_club_id):
		return false
	var home: LeagueTableRow = rows[result.home_club_id]
	var away: LeagueTableRow = rows[result.away_club_id]
	home.record(result.home_goals, result.away_goals)
	away.record(result.away_goals, result.home_goals)
	applied_fixture_ids[result.fixture_id] = true
	return true


func row_for(club_id: String) -> LeagueTableRow:
	return rows.get(club_id) as LeagueTableRow


func standings() -> Array[LeagueTableRow]:
	var sorted: Array[LeagueTableRow] = []
	for club_id in rows:
		sorted.append(rows[club_id])
	sorted.sort_custom(func(a: LeagueTableRow, b: LeagueTableRow) -> bool:
		if a.points != b.points:
			return a.points > b.points
		if a.goal_difference() != b.goal_difference():
			return a.goal_difference() > b.goal_difference()
		if a.goals_for != b.goals_for:
			return a.goals_for > b.goals_for
		return String(a.club_id) < String(b.club_id)
	)
	return sorted
