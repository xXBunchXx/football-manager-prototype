class_name FixtureLoader
extends RefCounted

## The single place that reads JSON fixtures. Phase 2 will add Resource
## construction and validation on top of these primitives.

static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("FixtureLoader: missing file %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("FixtureLoader: could not open %s" % path)
		return null
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("FixtureLoader: invalid JSON in %s" % path)
	return parsed


static func has_keys(data: Dictionary, keys: Array) -> bool:
	for key in keys:
		if not data.has(key):
			return false
	return true
