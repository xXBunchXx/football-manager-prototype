class_name MatchHistory
extends RefCounted

## Persisted match records plus bulk aggregation. This is deliberately separate
## from SeasonState: the fixture list owns results, history owns explanations.

const SAVE_VERSION := 1
const MAX_RECORDS := 300
const TEAM_KEYS := [
	"shots", "shots_on_target", "passes", "passes_attempted", "passes_completed",
	"passes_to_target", "crosses", "switches", "dribbles", "dribbles_succeeded",
	"touches", "saves", "tackles", "tackle_wins", "fouls", "yellow_cards",
	"red_cards", "control_seconds",
]
const PLAYER_KEYS := [
	"shots_taken", "shots_on_target", "passes", "passes_attempted", "passes_completed",
	"passes_to_target", "crosses", "switches", "dribbles", "dribbles_succeeded",
	"touches", "saves", "tackles", "tackle_wins", "fouls", "yellow_cards",
	"red_cards", "control_seconds", "goals",
]


var records: Array[MatchRecord] = []


func add(record: MatchRecord) -> void:
	if record == null:
		return
	records.append(record)
	if records.size() > MAX_RECORDS:
		records.remove_at(0)


func clear() -> void:
	records.clear()


func find_fixture(fixture_id: String) -> MatchRecord:
	for i in range(records.size() - 1, -1, -1):
		if records[i].fixture_id == fixture_id:
			return records[i]
	return null


func latest() -> MatchRecord:
	return records[records.size() - 1] if not records.is_empty() else null


func to_dict() -> Dictionary:
	var entries: Array = []
	for record in records:
		entries.append(record.to_dict())
	return {"version": SAVE_VERSION, "matches": entries}


static func from_dict(data: Dictionary) -> MatchHistory:
	if int(data.get("version", -1)) != SAVE_VERSION or not (data.get("matches", null) is Array):
		push_error("MatchHistory: unsupported version or invalid matches")
		return null
	var history := MatchHistory.new()
	for entry in (data["matches"] as Array):
		if not (entry is Dictionary):
			push_error("MatchHistory: match entry is not an object")
			return null
		var record := MatchRecord.from_dict(entry)
		if record == null:
			return null
		history.records.append(record)
	return history


func save() -> bool:
	var state := SaveGame.load_state()
	state["match_history"] = to_dict()
	return SaveGame.save_state(state)


func load() -> bool:
	var stored: Variant = SaveGame.load_state().get("match_history", null)
	if not (stored is Dictionary):
		return false
	var loaded := MatchHistory.from_dict(stored)
	if loaded == null:
		return false
	records = loaded.records
	return true


## Aggregates by club and player, then flags the patterns that actually matter
## for balance: unproductive tackling, passing accuracy, shot quality and
## possession starvation. Thresholds come from stat_effects.json.
func analysis(effects: StatEffects) -> Dictionary:
	var clubs: Dictionary = {}
	var players: Dictionary = {}
	var total_control := 0.0

	for record in records:
		var home: Dictionary = record.stats.get("home", {})
		var away: Dictionary = record.stats.get("away", {})
		_add_club(clubs, record.home_club_id, home, record.home_goals, record.away_goals)
		_add_club(clubs, record.away_club_id, away, record.away_goals, record.home_goals)
		total_control += _num(home, "control_seconds") + _num(away, "control_seconds")

		var player_stats: Dictionary = record.stats.get("players", {})
		for player_id in player_stats:
			var player_data: Dictionary = player_stats[player_id]
			var side := String(player_data.get("side", "home"))
			var club_id := record.home_club_id if side == "home" else record.away_club_id
			_add_player(players, String(player_id), club_id, side, player_data)

	for club_id in clubs:
		_finalise_club(clubs[club_id], total_control)
	for player_id in players:
		_finalise_player(players[player_id])

	return {
		"matches": records.size(),
		"clubs": clubs,
		"players": players,
		"issues": _build_issues(clubs, effects),
	}


func analysis_text(effects: StatEffects) -> String:
	var report := analysis(effects)
	var lines: Array[String] = []
	lines.append("Matches analysed: %d" % int(report["matches"]))
	lines.append("Club                 P  Pass%  Tack  Win%  Fou/T  Shots  Conv%  Poss%")
	var clubs: Dictionary = report["clubs"]
	var ordered: Array = clubs.keys()
	ordered.sort_custom(func(a, b): return _num(clubs[b], "points_for") > _num(clubs[a], "points_for"))
	for club_id in ordered:
		var club: Dictionary = clubs[club_id]
		lines.append("%-20s %2d  %5.1f  %4d  %5.1f  %5.2f  %5.1f  %5.1f  %5.1f" % [
			_club_name(club_id),
			int(club["matches"]),
			_num(club, "pass_completion_rate") * 100.0,
			int(club["tackles"]),
			_num(club, "tackle_win_rate") * 100.0,
			_num(club, "fouls_per_tackle"),
			_num(club, "shots_per_match"),
			_num(club, "shot_conversion") * 100.0,
			_num(club, "possession_share") * 100.0,
		])
	lines.append("")
	lines.append("Player leaders (matches  attempts  success)")
	var players: Dictionary = report["players"]
	for label in ["passes_attempted", "tackles", "shots_taken"]:
		var ranked: Array = players.keys()
		ranked.sort_custom(func(a, b): return _num(players[b], label) > _num(players[a], label))
		var count := 0
		for player_id in ranked:
			if _num(players[player_id], label) <= 0.0:
				continue
			var rate_label: String
			if label == "passes_attempted":
				rate_label = "pass %.0f%%" % (_num(players[player_id], "pass_completion_rate") * 100.0)
			elif label == "tackles":
				rate_label = "win %.0f%%" % (_num(players[player_id], "tackle_win_rate") * 100.0)
			else:
				rate_label = "conv %.0f%%" % (_num(players[player_id], "shot_conversion") * 100.0)
			lines.append("  %-18s %-18s %2d  %3d  %s" % [
				_player_name(String(player_id)), label, int(_num(players[player_id], "matches")),
				int(_num(players[player_id], label)), rate_label,
			])
			count += 1
			if count >= 3:
				break
	lines.append("")
	var issues: Array = report["issues"]
	if issues.is_empty():
		lines.append("No club balance flags raised.")
	else:
		for issue in issues:
			lines.append("[%s] %s" % [String((issue as Dictionary)["severity"]).to_upper(), String((issue as Dictionary)["text"])])
	if effects != null:
		var flagged: Array = []
		for player_id in players:
			var player: Dictionary = players[player_id]
			if _num(player, "tackles") >= 10.0 and _num(player, "tackle_win_rate") < effects.analysis_value("min_tackle_win_rate"):
				flagged.append("  %s challenges %.0f times but wins only %.0f%%" % [
					_player_name(String(player_id)), _num(player, "tackles"), _num(player, "tackle_win_rate") * 100.0,
				])
		if not flagged.is_empty():
			lines.append("Player tackle flags:")
			lines.append_array(flagged)
	return "\n".join(lines)


func _add_club(clubs: Dictionary, club_id: String, side: Dictionary, goals_for: int, goals_against: int) -> void:
	if not clubs.has(club_id):
		var blank := {"club_id": club_id, "matches": 0, "goals_for": 0, "goals_against": 0, "points_for": 0}
		for key in TEAM_KEYS:
			blank[key] = 0.0 if key == "control_seconds" else 0
		clubs[club_id] = blank
	var club: Dictionary = clubs[club_id]
	club["matches"] = int(club["matches"]) + 1
	club["goals_for"] = int(club["goals_for"]) + goals_for
	club["goals_against"] = int(club["goals_against"]) + goals_against
	club["points_for"] = int(club["points_for"]) + (3 if goals_for > goals_against else (1 if goals_for == goals_against else 0))
	for key in TEAM_KEYS:
		club[key] = _num(club, key) + _num(side, key)


func _add_player(players: Dictionary, player_id: String, club_id: String, side: String, source: Dictionary) -> void:
	if not players.has(player_id):
		var blank := {"player_id": player_id, "club_id": club_id, "side": side, "matches": 0}
		for key in PLAYER_KEYS:
			blank[key] = 0.0 if key == "control_seconds" else 0
		players[player_id] = blank
	var player: Dictionary = players[player_id]
	player["matches"] = int(player["matches"]) + 1
	player["club_id"] = club_id
	player["side"] = side
	for key in PLAYER_KEYS:
		player[key] = _num(player, key) + _num(source, key)


func _finalise_club(club: Dictionary, total_control: float) -> void:
	var matches: float = maxf(float(club["matches"]), 1.0)
	club["pass_completion_rate"] = _rate(_num(club, "passes_completed"), _num(club, "passes_attempted"))
	club["target_completion_rate"] = _rate(_num(club, "passes_to_target"), _num(club, "passes_attempted"))
	club["tackle_win_rate"] = _rate(_num(club, "tackle_wins"), _num(club, "tackles"))
	club["shot_conversion"] = _rate(_num(club, "goals_for"), _num(club, "shots"))
	club["fouls_per_tackle"] = _rate(_num(club, "fouls"), _num(club, "tackles"))
	club["tackles_per_match"] = _num(club, "tackles") / matches
	club["shots_per_match"] = _num(club, "shots") / matches
	club["possession_share"] = _rate(_num(club, "control_seconds"), total_control)


func _finalise_player(player: Dictionary) -> void:
	player["pass_completion_rate"] = _rate(_num(player, "passes_completed"), _num(player, "passes_attempted"))
	player["tackle_win_rate"] = _rate(_num(player, "tackle_wins"), _num(player, "tackles"))
	player["shot_conversion"] = _rate(_num(player, "goals"), _num(player, "shots_taken"))
	player["dribble_success_rate"] = _rate(_num(player, "dribbles_succeeded"), _num(player, "dribbles"))


func _build_issues(clubs: Dictionary, effects: StatEffects) -> Array:
	var issues: Array = []
	if records.is_empty() or effects == null:
		return issues
	# Ignore single-match noise; a pattern needs roughly half a season of data.
	var sample_attempts := effects.simulation_value("possessions_per_team") * float(records.size()) * 0.5
	# Possession is relative to the field size: an even share in a six-club
	# league is 1/6, so a fixed absolute floor would flag every club.
	var even_share := 1.0 / maxf(2.0, float(clubs.size()))
	var possession_floor := even_share * effects.analysis_value("min_possession_share_ratio")
	for club_id in clubs:
		var club: Dictionary = clubs[club_id]
		var name := _club_name(club_id)
		if _num(club, "passes_attempted") >= sample_attempts and _num(club, "pass_completion_rate") < effects.analysis_value("min_pass_completion_rate"):
			issues.append(_issue("low_pass_completion", "high", "%s completes only %.1f%% of passes" % [name, _num(club, "pass_completion_rate") * 100.0], club_id))
		if _num(club, "tackles_per_match") > effects.analysis_value("max_tackles_per_match") and _num(club, "tackle_win_rate") < effects.analysis_value("min_tackle_win_rate"):
			issues.append(_issue("unproductive_tackling", "high", "%s challenges %.1f times per match but wins only %.1f%%" % [
				name, _num(club, "tackles_per_match"), _num(club, "tackle_win_rate") * 100.0,
			], club_id))
		if _num(club, "tackles") >= sample_attempts and _num(club, "fouls_per_tackle") > effects.analysis_value("max_fouls_per_tackle"):
			issues.append(_issue("foul_rate", "medium", "%s fouls on %.1f%% of challenges" % [name, _num(club, "fouls_per_tackle") * 100.0], club_id))
		if records.size() >= 3 and (_num(club, "shots_per_match") < effects.analysis_value("min_shots_per_match") or _num(club, "shot_conversion") < effects.analysis_value("min_shot_conversion")):
			issues.append(_issue("shot_quality", "medium", "%s averages %.1f shots with %.1f%% conversion" % [
				name, _num(club, "shots_per_match"), _num(club, "shot_conversion") * 100.0,
			], club_id))
		if records.size() >= 3 and _num(club, "possession_share") < possession_floor:
			issues.append(_issue("low_possession", "medium", "%s sees only %.1f%% of the ball" % [name, _num(club, "possession_share") * 100.0], club_id))
	return issues


func _issue(code: String, severity: String, text: String, club_id: String) -> Dictionary:
	return {"code": code, "severity": severity, "text": text, "club_id": club_id}


static func _num(source: Dictionary, key: String) -> float:
	var value: Variant = source.get(key, 0)
	if value is int or value is float:
		return float(value)
	return 0.0


static func _rate(numerator: float, denominator: float) -> float:
	return clampf(numerator / maxf(denominator, 0.0001), 0.0, 1.0)


func format_match(record: MatchRecord) -> String:
	if record == null:
		return "No match record available."
	var home: Dictionary = record.stats.get("home", {})
	var away: Dictionary = record.stats.get("away", {})
	var lines: Array[String] = []
	lines.append("%s  %d-%d  %s  [%s, R%d]" % [
		_club_name(record.home_club_id), record.home_goals, record.away_goals,
		_club_name(record.away_club_id), record.source, record.round,
	])
	lines.append("Team                Shots  Passes       Tackles      Fouls  Possession")
	for side in ["home", "away"]:
		var side_stats: Dictionary = record.stats.get(side, {})
		lines.append("%-20s %5d  %3d/%-3d  %3d/%-3d  %5d  %5.1f min" % [
			_club_name(record.home_club_id if side == "home" else record.away_club_id),
			int(_num(side_stats, "shots")),
			int(_num(side_stats, "passes_completed")), int(_num(side_stats, "passes_attempted")),
			int(_num(side_stats, "tackle_wins")), int(_num(side_stats, "tackles")),
			int(_num(side_stats, "fouls")), _num(side_stats, "control_seconds") / 60.0,
		])
	lines.append("")
	lines.append("Player              Min   Passes       Tackles      Shots  Touches")
	var player_stats: Dictionary = record.stats.get("players", {})
	var ids: Array = player_stats.keys()
	ids.sort_custom(func(a, b): return _num(player_stats[b], "control_seconds") > _num(player_stats[a], "control_seconds"))
	for player_id in ids:
		var player: Dictionary = player_stats[player_id]
		lines.append("%-20s %4.1f  %3d/%-3d  %3d/%-3d  %5d  %5d" % [
			_player_name(String(player_id)), _num(player, "control_seconds") / 60.0,
			int(_num(player, "passes_completed")), int(_num(player, "passes_attempted")),
			int(_num(player, "tackle_wins")), int(_num(player, "tackles")),
			int(_num(player, "shots_taken")), int(_num(player, "touches")),
		])
	return "\n".join(lines)


func _club_name(club_id: String) -> String:
	for club in GameData.clubs:
		if club.id == club_id:
			return String(club.short_name)
	return club_id


func _player_name(player_id: String) -> String:
	var player: PlayerData = GameData.players_by_id.get(player_id, null)
	if player != null:
		return player.display_name()
	return player_id
