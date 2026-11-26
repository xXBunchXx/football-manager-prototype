class_name MatchConfig
extends Resource

## All global tuning lives here or in data/stat_effects.json.
## Logic scripts must not contain bare tuning numbers.

@export var pitch_length_m: float = 105.0
@export var pitch_width_m: float = 68.0
@export var goal_width_m: float = 7.32
@export var goal_height_m: float = 2.44

@export var ball_radius_m: float = 0.11
@export var ball_mass_kg: float = 0.43

@export var physics_ticks_per_second: int = 60
@export var decision_ticks_per_second: float = 6.0

@export var half_length_seconds: float = 120.0
@export var halves: int = 2
@export var added_time_seconds: float = 0.0

@export var speed_steps: Array = [0.0, 1.0, 2.0, 4.0]

@export var starters_per_club: int = 11
@export var squad_size: int = 18

@export var seed: int = 20261126


func configure_engine() -> void:
	Engine.physics_ticks_per_second = physics_ticks_per_second


func get_decision_interval() -> float:
	if decision_ticks_per_second <= 0.0:
		return 0.0
	return 1.0 / decision_ticks_per_second


func get_match_duration_seconds() -> float:
	return half_length_seconds * float(halves) + added_time_seconds
