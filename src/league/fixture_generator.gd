class_name FixtureGenerator
extends RefCounted

## Deterministic double round-robin for an even number of clubs. Every club
## meets every other club once at home and once away.

static func generate(league: LeagueData) -> Array[Fixture]:
	var result: Array[Fixture] = []
	var club_ids: Array[String] = league.club_ids.duplicate()
	var count := club_ids.size()
	if count < 2 or count % 2 != 0:
		push_error("FixtureGenerator: need an even number of clubs")
		return result

	var order: Array[String] = club_ids.duplicate()
	var half := count / 2
	var rounds_per_leg := count - 1
	for round_index in rounds_per_leg:
		for pair_index in half:
			var first: String = order[pair_index]
			var second: String = order[count - 1 - pair_index]
			var home: String = first
			var away: String = second
			if round_index % 2 == 1:
				home = second
				away = first
			result.append(_make_fixture(round_index + 1, home, away))
		var tail: String = order[count - 1]
		order.remove_at(count - 1)
		order.insert(1, tail)

	var return_leg: Array[Fixture] = []
	for fixture in result:
		return_leg.append(_make_fixture(
			fixture.round + rounds_per_leg,
			fixture.away_club_id,
			fixture.home_club_id
		))
	result.append_array(return_leg)
	return result


static func _make_fixture(round_number: int, home: String, away: String) -> Fixture:
	var fixture := Fixture.new()
	fixture.id = "r%02d-%s-vs-%s" % [round_number, home, away]
	fixture.round = round_number
	fixture.home_club_id = home
	fixture.away_club_id = away
	return fixture
