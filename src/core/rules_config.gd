class_name RulesConfig
extends RefCounted

## Typed view of data/rules.json: thresholds for fouls, offside, restarts,
## substitutions and added time.

const FILE := "res://data/rules.json"
const SECTIONS := ["foul", "offside", "restart", "substitution", "clock"]

var foul: Dictionary = {}
var offside: Dictionary = {}
var restart: Dictionary = {}
var substitution: Dictionary = {}
var clock: Dictionary = {}


static func load(path: String = FILE) -> RulesConfig:
	var raw: Variant = FixtureLoader.load_json(path)
	if not (raw is Dictionary):
		push_error("RulesConfig: %s must contain a JSON object" % path)
		return null
	var result := RulesConfig.new()
	for section in SECTIONS:
		var values: Variant = raw.get(section, {})
		if not (values is Dictionary) or not _numbers_only(values):
			push_error("RulesConfig: invalid section '%s'" % section)
			return null
		result.set(section, values)
	return result


static func _numbers_only(data: Dictionary) -> bool:
	for key in data:
		var value: Variant = data[key]
		if not (value is int or value is float):
			return false
	return true


func value(section: String, key: String) -> float:
	var data: Dictionary = get(section) as Dictionary
	return float(data.get(key, 0.0))
