## Achievements: the list, unlocking (saved in the career file with the date), running tallies for the
## count-based ones, and the little "Achievement unlocked" card that slides in at the top of the screen.
## The tracker on the cabin computer reads list() and tally().
class_name Ach
extends RefCounted

const CATS := ["Getting started", "Felling", "Climbing", "Hauling & cleanup", "Firewood stand", "Fishing", "Weather & cabin", "Money", "Speedruns", "Odd jobs"]

## id: [category, title, how to get it, tally name (for progress) or "", target, hidden until earned]
const LIST := {
	first_day = ["Getting started", "First Day on the Job", "Finish Earl's dead ash.", "", 0, false],
	widows_peace = ["Getting started", "Widow's Peace", "Finish Mrs. Hale's leaning maple.", "", 0, false],
	clear_water = ["Getting started", "Clear Water", "Pull all of Gus's logs out of the lake.", "", 0, false],
	revival = ["Getting started", "Square-Body Revival", "Fix up the rusty truck.", "", 0, false],
	fully_rigged = ["Getting started", "Fully Rigged", "Own the wedges, the bull rope, the trailer and the fishing rod.", "", 0, false],

	on_the_line = ["Felling", "Right on the Line", "Fell a tree within 5° of where your notch aims.", "", 0, false],
	textbook_notch = ["Felling", "Textbook Notch", "Cut a proper open-face notch: deep enough, open enough.", "", 0, false],
	hinge_master = ["Felling", "Hinge Master", "Leave a hinge between 5% and 18% of the diameter.", "", 0, false],
	wedge_whisperer = ["Felling", "Wedge Whisperer", "Tip a back-leaning tree over with wedges alone, no rope.", "", 0, false],
	not_on_my_watch = ["Felling", "Not on My Watch", "Finish Mrs. Hale's job without a scratch on the garage or the house.", "", 0, false],
	gentle_giant = ["Felling", "Gentle Giant", "Drop Mrs. Hale's big maple with a textbook notch, hinge and aim.", "", 0, false],

	spurs_on = ["Climbing", "Spurs On", "Spike into a tree for the first time.", "", 0, false],
	fifty_feet = ["Climbing", "Fifty Feet Up", "Get your saddle fifty feet up a tree.", "", 0, false],
	top_out = ["Climbing", "Topped Out", "Top a tree from up in it.", "tops", 1, false],
	easy_does_it = ["Climbing", "Easy Does It", "Lower 25 pieces on the rope.", "lowered", 25, false],
	backyard_surgeon = ["Climbing", "Backyard Surgeon", "Finish the Kowalskis' oak.", "", 0, false],
	not_a_scratch = ["Climbing", "Not a Scratch", "Finish the Kowalskis' oak without touching the house, the deck, the swing set or the fence.", "", 0, false],
	rest_in_peace = ["Climbing", "Rest in Peace", "Finish the cemetery spruce.", "", 0, false],
	grave_respect = ["Climbing", "Grave Respect", "Finish the cemetery spruce without disturbing a single stone.", "", 0, false],
	dont_look_down = ["Climbing", "Don't Look Down", "Cut through your own line and fall out of a tree.", "", 0, true],

	full_load = ["Hauling & cleanup", "Full Load", "Get paid with 16 or more rounds in the trailer.", "", 0, false],
	tarp_life = ["Hauling & cleanup", "Tarp Life", "Tarp down a trailer of 12 or more rounds.", "", 0, false],
	grind_it_out = ["Hauling & cleanup", "Grind It Out", "Chip 100 branches.", "chipped", 100, false],
	one_kick = ["Hauling & cleanup", "One Kick Wonder", "Snap a log apart with a single kick.", "", 0, false],
	stuck_in_mud = ["Hauling & cleanup", "Stuck in the Mud", "Unstick the truck 10 times.", "unstuck", 10, false],
	road_train = ["Hauling & cleanup", "Road Train", "Tow the trailer and chipper together at 12 mph or more.", "", 0, false],

	honest_work = ["Firewood stand", "Honest Work", "Sell your first bundle on the honour box.", "", 0, false],
	cord_king = ["Firewood stand", "Cord King", "Sell 100 bundles.", "bundles", 100, false],
	green_zone = ["Firewood stand", "Green Zone", "Land 10 green-zone splits in a row.", "", 0, false],
	sweet_spot = ["Firewood stand", "Sweet Spot Streak", "Split a whole round down to sticks without a single miss or stuck axe.", "", 0, false],

	first_bite = ["Fishing", "First Bite", "Catch a fish.", "", 0, false],
	mixed_bag = ["Fishing", "Mixed Bag", "Catch every creek species.", "", 0, false],
	lake_life = ["Fishing", "Lake Life", "Catch every lake species.", "", 0, false],
	gone_fishin = ["Fishing", "Gone Fishin'", "Catch every species in the game.", "", 0, false],
	lunker = ["Fishing", "Lunker", "Land a largemouth bass of 5 lb or more.", "", 0, false],
	muskie = ["Fishing", "Fish of 10,000 Casts", "Land a muskellunge.", "", 0, false],
	release = ["Fishing", "Catch and Release", "Let 25 fish go.", "released", 25, false],
	line_dancer = ["Fishing", "Line Dancer", "Land a fish without the line tension ever going into the red.", "", 0, false],
	patience = ["Fishing", "Patience", "Land 5 fish in a row without striking early on a nibble.", "", 0, false],
	lucky_jig = ["Fishing", "Lucky Jig", "Set the hook within 5 seconds of jigging the lure.", "", 0, false],
	golden_hour = ["Fishing", "Golden Hour", "Catch a fish on Mrs. Hale's lake at sunset.", "", 0, false],
	gerald = ["Fishing", "Gerald", "Catch the giant old bass that lives off Gus's shore.", "", 0, true],

	rain_or_shine = ["Weather & cabin", "Rain or Shine", "Finish a job in the rain or a storm.", "", 0, false],
	lost_in_fog = ["Weather & cabin", "Lost in the Fog", "Fell a tree in heavy fog.", "", 0, false],
	smoke_signals = ["Weather & cabin", "Smoke Signals", "Warm up by the cabin fireplace.", "", 0, false],

	pocket_change = ["Money", "Pocket Change", "Earn $1,000 in total.", "earned", 1000, false],
	small_business = ["Money", "Small Business", "Earn $10,000 in total.", "earned", 10000, false],
	debt_free = ["Money", "Debt Free", "Buy every upgrade on the computer.", "", 0, false],

	speed_earl = ["Speedruns", "Ash in a Flash", "Finish Earl's dead ash in under 10 minutes.", "", 0, false],
	speed_hale = ["Speedruns", "Maple Minute", "Finish Mrs. Hale's leaning maple in under 15 minutes.", "", 0, false],
	speed_dock = ["Speedruns", "Dock Dash", "Finish Gus's dock logs in under 12 minutes.", "", 0, false],
	speed_oak = ["Speedruns", "Acorn Express", "Finish the Kowalskis' oak in under 20 minutes.", "", 0, false],
	speed_cemetery = ["Speedruns", "Quiet Hours", "Finish the cemetery spruce in under 25 minutes.", "", 0, false],

	ow = ["Odd jobs", "Ow", "Drop a tree on your own truck.", "", 0, true],
	earl_approved = ["Odd jobs", "Earl Approved", "Talk to Earl 20 times.", "earl_talks", 20, false],
}

static var game                   # for the pop-up card
static var _queue: Array = []
static var _card: PanelContainer
static var _busy := false

static var _have := {}
static var _have_loaded := false

static func has(id: String) -> bool:
	if not _have_loaded:
		_have = (Career.load().get("ach", {}) as Dictionary).duplicate(); _have_loaded = true
	return _have.has(id)

## (call after any Career.save of your own, or that save would drop the new unlock)
static func unlock(id: String) -> void:
	if not LIST.has(id) or has(id): return
	var c := Career.load()
	var a: Dictionary = c.get("ach", {})
	if a.has(id): return
	a[id] = Time.get_date_string_from_system()
	_have[id] = a[id]
	c.ach = a
	Career.save(c)
	_queue.append(id)
	_show_next()

static func tally(name: String) -> int:
	if name == "bundles": return int(Career.load().get("bundles", 0))
	return int((Career.load().get("stats", {}) as Dictionary).get(name, 0))

## add to a running tally, and unlock whatever it completes
static func add(name: String, n := 1) -> int:
	var c := Career.load()
	var s: Dictionary = c.get("stats", {})
	s[name] = int(s.get(name, 0)) + n
	c.stats = s
	Career.save(c)
	_check_tally(name, int(s[name]))
	return int(s[name])

static func set_stat(name: String, v: int) -> void:
	var c := Career.load()
	var s: Dictionary = c.get("stats", {})
	s[name] = v
	c.stats = s
	Career.save(c)

static func _check_tally(name: String, v: int) -> void:
	for id in LIST:
		var e: Array = LIST[id]
		if e[3] == name and v >= int(e[4]): unlock(id)

## money in: counts toward the earnings achievements
static func earn(n: int) -> void:
	if n > 0: add("earned", n)

## gear: the full set, and the computer's upgrades
static func check_gear() -> void:
	var c := Career.load()
	if bool(c.get("wedges", false)) and bool(c.get("rope", false)) and bool(c.get("trailer", false)) and bool(c.get("rod", false)): unlock("fully_rigged")
	if bool(c.get("wedges", false)) and bool(c.get("rope", false)) and float(c.get("truck_rust", 1.0)) <= 0.0: unlock("debt_free")
	if float(c.get("truck_rust", 1.0)) <= 0.0: unlock("revival")
	if int(c.get("bundles", 0)) >= 1: unlock("honest_work")
	_check_tally("bundles", int(c.get("bundles", 0)))

## credit what was done before achievements existed: jobs finished, gear owned, fish in the log
static func retro() -> void:
	var c := Career.load()
	var j := int(c.get("jobs", 0))
	if j >= 1: unlock("first_day")
	if j >= 2: unlock("widows_peace")
	if j >= 3: unlock("clear_water")
	var log: Dictionary = c.get("fish", {})
	if not log.is_empty(): unlock("first_bite")
	if log.has("Muskellunge"): unlock("muskie")
	if log.has("Gerald"): unlock("gerald")
	var all_creek := true; var all_lake := true; var all := true
	for s in Fishing.SPECIES:
		var w: String = Fishing.SPECIES[s].where
		if not log.has(s):
			all = false
			if w == "creek": all_creek = false
			if w == "lake": all_lake = false
	if all_creek: unlock("mixed_bag")
	if all_lake: unlock("lake_life")
	if all: unlock("gone_fishin")
	check_gear()

static func count() -> Vector2i:
	return Vector2i((Career.load().get("ach", {}) as Dictionary).size(), LIST.size())

# ---------------------------------------------------------------- the pop-up
static func _show_next() -> void:
	if _busy or _queue.is_empty() or game == null or not is_instance_valid(game) or game.hud == null: return
	_busy = true
	var id: String = _queue.pop_front()
	var e: Array = LIST[id]
	if _card == null or not is_instance_valid(_card):
		_card = PanelContainer.new()
		var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.09, 0.08, 0.06, 0.92); sb.set_corner_radius_all(10)
		sb.border_color = Color("#e8b84a"); sb.set_border_width_all(2)
		sb.content_margin_left = 16; sb.content_margin_right = 18; sb.content_margin_top = 10; sb.content_margin_bottom = 10
		_card.add_theme_stylebox_override("panel", sb)
		_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := RichTextLabel.new(); l.bbcode_enabled = true; l.fit_content = true; l.scroll_active = false
		l.custom_minimum_size = Vector2(380, 0); l.name = "L"; l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override("normal_font_size", 15); l.add_theme_font_size_override("bold_font_size", 19)
		_card.add_child(l)
		game.hud.root.add_child(_card)
	(_card.get_node("L") as RichTextLabel).text = "[color=#e8b84a]★  ACHIEVEMENT UNLOCKED[/color]\n[b]%s[/b]\n[color=#cfc7b4]%s[/color]" % [e[1], e[2]]
	_card.offset_left = -200; _card.offset_right = 200
	_card.offset_top = -120; _card.visible = true
	Sfx.play("ding", 0.7, 1.2); Sfx.play("cash", 0.25, 1.6)
	var tw: Tween = game.create_tween()
	tw.tween_property(_card, "offset_top", 14.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.4)
	tw.tween_property(_card, "offset_top", -140.0, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		_card.visible = false
		_busy = false
		_show_next())
