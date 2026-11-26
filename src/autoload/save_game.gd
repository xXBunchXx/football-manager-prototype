extends Node

## JSON save/load for user-created content (career progress, tactics).

var save_path: String = "user://fm_save.json"


func set_path(path: String) -> void:
	save_path = path


func save_state(data: Dictionary) -> bool:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: could not open %s for writing" % save_path)
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return true


func load_state() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_error("SaveGame: could not open %s for reading" % save_path)
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("SaveGame: %s did not contain a JSON object" % save_path)
	return {}
