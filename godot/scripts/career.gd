## Money, jobs done and the gear you've bought, saved between sessions.
class_name Career
extends RefCounted

const PATH := "user://career.json"

static func load() -> Dictionary:
	if not FileAccess.file_exists(PATH): return {money = 0, jobs = 0, truck_rust = 1.0}
	var f := FileAccess.open(PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY: return {money = 0, jobs = 0, truck_rust = 1.0}
	# everything that's saved comes back (achievements, tallies, catch log...), with the core fields typed
	var out: Dictionary = d.duplicate(true)
	out.money = int(d.get("money", 0)); out.jobs = int(d.get("jobs", 0)); out.truck_rust = float(d.get("truck_rust", 1.0))
	for k in ["wedges", "rope", "trailer", "firewood", "rod"]: out[k] = bool(d.get(k, false))
	out.rounds = int(d.get("rounds", 18 if bool(d.get("trailer", false)) else 0)); out.bundles = int(d.get("bundles", 0))
	for k in ["fish", "ach", "stats"]:
		if typeof(d.get(k, {})) != TYPE_DICTIONARY: out[k] = {}
		elif not out.has(k): out[k] = {}
	return out

static func save(c: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(c))
