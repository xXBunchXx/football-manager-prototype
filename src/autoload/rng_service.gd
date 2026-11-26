extends Node

## One seeded RNG so batch simulations and live matches are reproducible.

var seed_value: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_seed(GameData.config.seed)


func set_seed(value: int) -> void:
	seed_value = value
	_rng.seed = value


func randf() -> float:
	return _rng.randf()


func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func randfn(mean: float, deviation: float) -> float:
	return _rng.randfn(mean, deviation)


func chance(probability: float) -> bool:
	# Godot's global randf() shadows this wrapper when called unqualified inside
	# the autoload, which would draw from a different, unseeded stream.
	return self.randf() < probability
