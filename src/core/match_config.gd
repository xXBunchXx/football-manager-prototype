class_name MatchConfig
extends Resource

## All global tuning lives here or in data/stat_effects.json.
## Logic scripts must not contain bare tuning numbers.

@export var pitch_length_m: float = 105.0
@export var pitch_width_m: float = 68.0
@export var goal_width_m: float = 7.32
@export var goal_height_m: float = 2.44
@export var ground_thickness_m: float = 0.1
@export var ground_margin_m: float = 5.0

@export var ball_radius_m: float = 0.11
@export var ball_mass_kg: float = 0.43
@export var ball_linear_damp: float = 0.12
@export var ball_angular_damp: float = 0.3
@export var ball_bounce: float = 0.35
@export var ball_friction: float = 0.4
@export var max_ball_speed_mps: float = 35.0

@export var possession_radius_m: float = 1.2
@export var control_acceleration: float = 45.0
@export var control_damping: float = 7.0

@export var magnus_coefficient: float = 0.0008
@export var spin_decay_per_second: float = 0.8

@export var physics_ticks_per_second: int = 60
@export var decision_ticks_per_second: float = 6.0

@export var player_max_speed_mps: float = 7.5
@export var player_acceleration: float = 30.0
@export var player_linear_damp: float = 4.0
@export var player_separation_radius_m: float = 2.5
@export var player_separation_acceleration: float = 55.0
@export var player_separation_team_scale: float = 0.5
@export var shot_speed_mps: float = 24.0
@export var pass_speed_mps: float = 16.0
@export var shot_loft_degrees: float = 10.0
@export var pass_loft_degrees: float = 4.0
@export var control_offset_m: float = 0.9

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
