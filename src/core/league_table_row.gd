class_name LeagueTableRow
extends Resource

## Accumulated record for one club. Form is stored newest-last, capped at five.

@export var club_id: String = ""
@export var played: int = 0
@export var won: int = 0
@export var drawn: int = 0
@export var lost: int = 0
@export var goals_for: int = 0
@export var goals_against: int = 0
@export var points: int = 0
@export var form: Array[String] = []


func goal_difference() -> int:
	return goals_for - goals_against


func record(goals_scored: int, goals_conceded: int) -> void:
	played += 1
	goals_for += goals_scored
	goals_against += goals_conceded
	if goals_scored > goals_conceded:
		won += 1
		points += 3
		form.append("W")
	elif goals_scored == goals_conceded:
		drawn += 1
		points += 1
		form.append("D")
	else:
		lost += 1
		form.append("L")
	if form.size() > 5:
		form.remove_at(0)


func to_dict() -> Dictionary:
	return {
		"club_id": club_id,
		"played": played,
		"won": won,
		"drawn": drawn,
		"lost": lost,
		"goals_for": goals_for,
		"goals_against": goals_against,
		"points": points,
		"form": form.duplicate(),
	}


static func from_dict(data: Dictionary) -> LeagueTableRow:
	var required := [
		"club_id", "played", "won", "drawn", "lost", "goals_for", "goals_against", "points", "form",
	]
	if not FixtureLoader.has_keys(data, required) or not (data["form"] is Array):
		push_error("LeagueTableRow: invalid saved row")
		return null
	var row := LeagueTableRow.new()
	row.club_id = String(data["club_id"])
	row.played = int(data["played"])
	row.won = int(data["won"])
	row.drawn = int(data["drawn"])
	row.lost = int(data["lost"])
	row.goals_for = int(data["goals_for"])
	row.goals_against = int(data["goals_against"])
	row.points = int(data["points"])
	for entry in data["form"]:
		row.form.append(String(entry))
	return row
