## Money and jobs done, saved between sessions.
class_name Career
extends RefCounted

const PATH := "user://career.json"

static func load() -> Dictionary:
	if not FileAccess.file_exists(PATH): return {money = 0, jobs = 0, truck_rust = 1.0}
	var f := FileAccess.open(PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY: return {money = 0, jobs = 0, truck_rust = 1.0}
	return {money = int(d.get("money", 0)), jobs = int(d.get("jobs", 0)), truck_rust = float(d.get("truck_rust", 1.0))}

static func save(c: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(c))
