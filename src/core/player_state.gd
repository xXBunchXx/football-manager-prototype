class_name PlayerState
extends Resource

## Mutable per-match state. Holds only a player_id string, never a reference to
## the immutable PlayerData, so a match can never edit a player definition.

const MIN_MENTAL := 0.0
const MAX_MENTAL := 1.0

@export var player_id: String = ""
@export var stamina: float = 100.0
@export var fatigue: float = 0.0
@export var morale: float = 0.5
@export var form: float = 0.5
@export var injury_risk: float = 0.0
@export var yellow_cards: int = 0
@export var red_cards: int = 0
@export var mark_target_id: String = ""
@export var duty_override: int = -1  # -1 means "use PlayerInstructions.duty"
@export var passes_attempted: int = 0
@export var tackles_attempted: int = 0
@export var shots_taken: int = 0
@export var distance_covered_m: float = 0.0


static func for_player(player: PlayerData) -> PlayerState:
	var state := PlayerState.new()
	state.player_id = player.id
	# Slightly varied starting condition without touching the immutable profile.
	state.stamina = clampf(100.0 - float(player.age - 20) * 0.4, 60.0, 100.0)
	state.injury_risk = clampf(float(player.age - 20) * 0.004, 0.0, 0.2)
	return state


static func for_squad(club: ClubData) -> Dictionary:
	var result := {}
	for player in club.squad:
		result[player.id] = for_player(player)
	return result


func effective_duty(instructions: PlayerInstructions) -> int:
	if duty_override >= 0 and duty_override < 3:
		return duty_override
	return instructions.duty


func spend_stamina(amount: float) -> void:
	stamina = clampf(stamina - amount, 0.0, 100.0)
	fatigue = clampf(fatigue + amount * 0.01, 0.0, 1.0)


func recover_stamina(amount: float) -> void:
	stamina = clampf(stamina + amount, 0.0, 100.0)
	fatigue = clampf(fatigue - amount * 0.01, 0.0, 1.0)


func add_distance(metres: float) -> void:
	distance_covered_m = maxf(0.0, distance_covered_m + metres)


func adjust_morale(delta: float) -> void:
	morale = clampf(morale + delta, MIN_MENTAL, MAX_MENTAL)


func adjust_form(delta: float) -> void:
	form = clampf(form + delta, MIN_MENTAL, MAX_MENTAL)


func apply_card(color: int) -> void:
	if color == FMEnums.CardColor.YELLOW:
		yellow_cards += 1
		if yellow_cards >= 2:
			red_cards += 1
	elif color == FMEnums.CardColor.RED:
		red_cards += 1


func is_suspended() -> bool:
	return red_cards > 0


func is_valid() -> bool:
	var mental_ok := morale >= MIN_MENTAL and morale <= MAX_MENTAL
	mental_ok = mental_ok and form >= MIN_MENTAL and form <= MAX_MENTAL
	mental_ok = mental_ok and injury_risk >= MIN_MENTAL and injury_risk <= MAX_MENTAL
	var physical_ok := stamina >= 0.0 and stamina <= 100.0 and fatigue >= 0.0 and fatigue <= 1.0
	var counters_ok := yellow_cards >= 0 and red_cards >= 0 and passes_attempted >= 0
	counters_ok = counters_ok and tackles_attempted >= 0 and shots_taken >= 0 and distance_covered_m >= 0.0
	var duty_ok := duty_override >= -1 and duty_override < 3
	return mental_ok and physical_ok and counters_ok and duty_ok
