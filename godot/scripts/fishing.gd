## Fishing, in the spirit of the old console reel-fishing games. Gus's spinning rod (key 6) by any water:
## hold to fill the cast meter and let go to cast where you're facing. Watch the float: a fish's shadow
## drifts in, nibbles (the float bobs), then takes it (the float goes under) - strike then, not on a
## nibble. Hold right mouse to reel the lure in slowly, tap it to twitch the lure and draw fish in.
## Hooked: hold left mouse to reel. Watch the line tension (red: it'll snap) and the fish's stamina.
## When it runs, turn the rod against the run (look the other way) to turn it and tire it out; ease off
## the reel. Let the line go slack too long and it shakes the hook. Land it, then keep it or let it go.
class_name Fishing
extends Node3D

# where they live, how common, how big (cm), how hard they fight, how fast, what they're worth a pound
const SPECIES := {
	"Brook trout": {where = "creek", w = 1.0, len = [18.0, 38.0], str = 0.55, spd = 1.25, price = 4.0, top = Color("#5a6a3e"), belly = Color("#e07a3a")},
	"Creek chub": {where = "creek", w = 1.3, len = [10.0, 24.0], str = 0.3, spd = 0.9, price = 1.0, top = Color("#6a6a5a"), belly = Color("#d8d4c4")},
	"Rock bass": {where = "creek", w = 0.9, len = [15.0, 28.0], str = 0.45, spd = 0.95, price = 2.0, top = Color("#4e4428"), belly = Color("#c8b088")},
	"Smallmouth bass": {where = "creek", w = 0.45, len = [25.0, 52.0], str = 0.85, spd = 1.35, price = 6.0, top = Color("#6e5e30"), belly = Color("#d8c890")},
	"Bluegill": {where = "lake", w = 1.4, len = [12.0, 24.0], str = 0.35, spd = 1.0, price = 2.0, top = Color("#3e5032"), belly = Color("#e0903a")},
	"Yellow perch": {where = "lake", w = 1.1, len = [15.0, 32.0], str = 0.4, spd = 1.0, price = 3.0, top = Color("#9a8a30"), belly = Color("#e8e0b0")},
	"Black crappie": {where = "lake", w = 0.8, len = [18.0, 36.0], str = 0.42, spd = 1.0, price = 3.0, top = Color("#4e4e46"), belly = Color("#d8d8c8")},
	"Largemouth bass": {where = "lake", w = 0.8, len = [28.0, 60.0], str = 0.9, spd = 1.2, price = 6.0, top = Color("#3e5e32"), belly = Color("#e0e0c0")},
	"Walleye": {where = "lake", w = 0.35, len = [35.0, 72.0], str = 0.8, spd = 1.1, price = 8.0, top = Color("#7e6e40"), belly = Color("#e8e8d8")},
	"Northern pike": {where = "lake", w = 0.28, len = [50.0, 100.0], str = 1.05, spd = 1.5, price = 5.0, top = Color("#3e5e38"), belly = Color("#e8e8c8")},
	"Muskellunge": {where = "lake", w = 0.05, len = [90.0, 135.0], str = 1.35, spd = 1.6, price = 10.0, top = Color("#5e6e50"), belly = Color("#e0e0d0")},
}
const MAX_CAST := 24.0
const CAST_T := 1.1               # seconds for the meter to fill
const REEL_SPEED := 1.7           # m/s, reeling a fish
const RETRIEVE := 1.1             # m/s, reeling the lure in

var game
var state := "off"                # off | aim | fly | wait | fight | landed | snag
var t := 0.0
var meter := -1.0                 # cast meter, 0..1 (counts up and back), <0 not holding
var meter_t := 0.0
var lure := Vector3.ZERO          # the float / lure in the world
var water_y := 0.0
var fly_from := Vector3.ZERO; var fly_to := Vector3.ZERO; var fly_t := 0.0
var reel_held := false; var alt_held := false; var alt_t := 0.0
var interest := 0.0               # how keen the fish around here are on the lure right now
# the fish that's coming / on
var fish := {}                    # {name, len, kg, str, spd, pos, phase, nibbles, next, stamina, dist, ang, run, run_t, slack_t, over_t}
var tension := 0.0
var msg := ""; var msg_t := 0.0
var rng := RandomNumberGenerator.new()
# visuals
var rod: Node3D
var rod_tip := Vector3(0.02, 1.32, -0.62)        # in the rod's own frame
var line_im: ImmediateMesh
var bobber: MeshInstance3D
var shadow: MeshInstance3D
var caught: Node3D
var ui: CanvasLayer
var gauge: Control
var lbl: Label
var card: PanelContainer
var card_lbl: RichTextLabel
var _click_t := 0.0
# the fishing song: fades in slowly when you take the rod out, fades away when you put it up
const MUSIC := "res://audio/fishing_theme.mp3"
const MUSIC_VOL := 0.55
const FADE_IN := 9.0
const FADE_OUT := 3.0
var music: AudioStreamPlayer
var music_k := 0.0

func setup(g) -> void:
	game = g
	rng.randomize()
	rod = _rod_mb().instance(); rod.visible = false
	(rod as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.player.hands.add_child(rod)
	line_im = ImmediateMesh.new()
	var lm := MeshInstance3D.new(); lm.mesh = line_im; lm.top_level = true
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.92, 0.94, 0.9, 0.85); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	lm.material_override = mat; lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lm)
	var bm := MeshBuilder.new()
	bm.sphere(0, 0.03, 0, 0.035, 0.035, 0.035, Color("#d8261c"), 10, 6)
	bm.sphere(0, -0.01, 0, 0.034, 0.03, 0.034, Color("#f2f0ea"), 10, 6)
	bm.tube(Vector3(0, 0.06, 0), Vector3(0, 0.11, 0), 0.006, 0.004, Color("#d8261c"), 5)
	bobber = bm.instance(); bobber.top_level = true; bobber.visible = false; add_child(bobber)
	var sm := MeshBuilder.new()
	var c := Color(0.02, 0.04, 0.03, 0.55)
	var ids := [sm.v(Vector3.ZERO, Vector3.UP, c)]
	for k in range(13):
		var a := TAU * k / 12.0
		ids.append(sm.v(Vector3(sin(a) * 0.32, 0, cos(a)) * Vector3(1, 1, 1), Vector3.UP, Color(c.r, c.g, c.b, 0.0)))
	for k in range(12): sm.tri(ids[0], ids[k + 2], ids[k + 1])
	var smat := StandardMaterial3D.new(); smat.vertex_color_use_as_albedo = true; smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shadow = sm.instance(smat); shadow.top_level = true; shadow.visible = false; add_child(shadow)
	_build_ui()
	music = AudioStreamPlayer.new(); music.name = "Music"
	var st = load(MUSIC)
	if st is AudioStreamMP3: (st as AudioStreamMP3).loop = true
	music.stream = st
	music.volume_db = -80.0
	add_child(music)

static func owned() -> bool:
	return bool(Career.load().get("rod", false))

# ---------------------------------------------------------------- where the water is
## the water surface under this spot, or INF if it's dry land
func water_at(p: Vector3) -> float:
	var w: WorldGen = game.world
	if not w.lake.is_empty():
		return float(w.lake.y) if w.lake_d(p.x, p.z) < -0.4 else INF
	var cz := w.creek_z(p.x)
	if absf(p.z - cz) < 2.9: return w.H(p.x, cz) + 0.55
	return INF

func _where() -> String:
	return "lake" if not game.world.lake.is_empty() else "creek"

## any water within a cast of here?
func water_near() -> bool:
	var p: Vector3 = game.player.global_position
	for k in range(16):
		var a := TAU * k / 16.0
		for d: float in [4.0, 9.0, 15.0, 22.0]:
			if water_at(p + Vector3(cos(a), 0, sin(a)) * d) != INF: return true
	return false

# ---------------------------------------------------------------- input
func equip(on: bool) -> void:
	rod.visible = on
	if on:
		state = "aim"; meter = -1.0
		gauge.queue_redraw()
		ui.visible = true
		_say("Hold left mouse to cast. Let go when the meter's where you want it." if water_near() else "No water in reach. Head for the creek or the lake.", 4.0)
	else:
		_reset()
		ui.visible = false

func _reset() -> void:
	state = "aim"; meter = -1.0; fish = {}; tension = 0.0; reel_held = false; alt_held = false
	bobber.visible = false; shadow.visible = false
	if caught: caught.queue_free(); caught = null
	card.visible = false
	game.player.speed_mult = 1.0
	line_im.clear_surfaces()

func press(down: bool) -> void:
	match state:
		"aim":
			if down: meter = 0.0; meter_t = 0.0; Sfx.play("pull", 0.15, 1.8)
			elif meter >= 0.0: _cast(meter)
		"wait":
			if down: _strike()
		"fight":
			reel_held = down
		"landed":
			if down: _keep(true)
		"snag":
			if down: _say("Snagged. Hold right mouse to reel it in.", 2.0)

func alt(down: bool) -> void:
	alt_held = down
	if down: alt_t = 0.0
	match state:
		"wait":
			if not down and alt_t < 0.22: _twitch()
		"landed":
			if down: _keep(false)
		"snag":
			if down: _retrieve("Reeled in.")

# ---------------------------------------------------------------- casting
func _cast(power: float) -> void:
	meter = -1.0
	var p: Player = game.player
	var fw := p.fwd()
	var dist := 2.5 + power * (MAX_CAST - 2.5)
	fly_from = _tip()
	fly_to = p.global_position + fw * dist
	var wy := water_at(fly_to)
	if wy == INF:
		fly_to.y = game.world.H(fly_to.x, fly_to.z) + 0.03
	else:
		fly_to.y = wy
	water_y = wy
	fly_t = 0.0
	state = "fly"
	bobber.visible = true
	Sfx.play("whoosh", 0.4, 1.4 + power * 0.3)

func _land() -> void:
	lure = fly_to
	if water_y == INF:
		state = "snag"
		Sfx.play("drop", 0.3, 1.6)
		_say("That's in the grass. Hold right mouse to reel it in and try again.", 3.0)
		return
	state = "wait"
	interest = 0.15
	fish = {}
	Sfx.play("drop", 0.45, 1.8)
	game.saw._emit(lure, Vector3(0, 1.4, 0), 8, Color(0.85, 0.9, 0.92), 1.0, 0.025)
	_say("Watch the float. Strike when it goes under. Right mouse: reel slow, tap to twitch.", 4.0)

func _retrieve(why: String) -> void:
	state = "aim"; fish = {}
	bobber.visible = false; shadow.visible = false
	if why != "": _say(why, 2.0)

func _twitch() -> void:
	interest = minf(1.0, interest + 0.18)
	lure += (game.player.global_position - lure).normalized() * 0.25 * Vector3(1, 0, 1)
	Sfx.play("drop", 0.15, 2.4)

# ---------------------------------------------------------------- waiting for a bite
func _spot_fish() -> Dictionary:
	var where := _where()
	var pool := []; var total := 0.0
	for n in SPECIES:
		var sp: Dictionary = SPECIES[n]
		if sp.where != where: continue
		pool.append(n); total += float(sp.w)
	var r := rng.randf() * total
	var name: String = pool[0]
	for n in pool:
		r -= float(SPECIES[n].w)
		if r <= 0.0: name = n; break
	var sp: Dictionary = SPECIES[name]
	# sizes skew small, with the odd big one
	var k := pow(rng.randf(), 1.8)
	var L := lerpf(float(sp.len[0]), float(sp.len[1]), k)
	var kg := 0.0000118 * pow(L, 3.0) * (0.85 if name == "Northern pike" or name == "Muskellunge" else 1.0)
	return {name = name, len = L, kg = kg, str = float(sp.str) * (0.7 + 0.6 * k), spd = float(sp.spd)}

func _wait_step(dt: float) -> void:
	var p: Player = game.player
	# reeling the lure in slowly (holding right mouse)
	if alt_held:
		alt_t += dt
		if alt_t > 0.22:
			var to := p.global_position - lure; to.y = 0
			if to.length() < 2.6: _retrieve("Lure's in."); return
			lure += to.normalized() * RETRIEVE * dt
			interest = minf(1.0, interest + dt * 0.08)
			if water_at(lure) == INF: _retrieve("Lure's in."); return
			_click(dt)
	if fish.is_empty():
		interest = maxf(0.1, interest - dt * 0.01)
		# something takes an interest
		if rng.randf() < dt * (0.12 + interest * 0.35):
			fish = _spot_fish()
			var a := rng.randf() * TAU
			fish.pos = lure + Vector3(cos(a), 0, sin(a)) * rng.randf_range(4.0, 8.0)
			fish.pos.y = lure.y
			fish.phase = "come"; fish.nibbles = rng.randi_range(1, 3); fish.next = 0.0
		return
	# the shadow drifts in, then nibbles, then takes it
	match fish.phase:
		"come":
			var to: Vector3 = lure - fish.pos; to.y = 0
			if to.length() < 0.35:
				fish.phase = "nibble"; fish.next = rng.randf_range(0.6, 1.8)
			else:
				fish.pos += to.normalized() * minf(to.length(), (0.8 + 0.6 * float(fish.spd)) * dt)
		"nibble":
			fish.next -= dt
			if fish.next <= 0.0:
				if fish.nibbles > 0:
					fish.nibbles -= 1; fish.dip = 0.35; fish.next = rng.randf_range(0.7, 1.9)
					Sfx.play("drop", 0.12, 2.6)
				else:
					fish.phase = "bite"; fish.next = 0.85      # the strike window
					Sfx.play("drop", 0.4, 1.3)
		"bite":
			fish.next -= dt
			if fish.next <= 0.0:
				fish = {}
				_say("Too slow! It stole the bait. Re-baited, still in the water.", 2.5)
				interest = 0.1
		"spooked":
			var away: Vector3 = fish.pos - lure; away.y = 0
			fish.pos += away.normalized() * 4.0 * dt
			fish.next -= dt
			if fish.next <= 0.0: fish = {}

func _strike() -> void:
	Sfx.play("whoosh", 0.4, 1.8)
	if fish.is_empty() or fish.phase == "come" or fish.phase == "spooked":
		_say("Nothing there. Wait for the float to go under.", 1.8)
		return
	if fish.phase == "nibble":
		fish.phase = "spooked"; fish.next = 1.2
		_say("Too early! That was a nibble. It spooked.", 2.2)
		interest = 0.05
		return
	# hooked!
	state = "fight"
	var d := Vector3(lure.x - game.player.global_position.x, 0, lure.z - game.player.global_position.z)
	fish.dist = d.length(); fish.ang = atan2(d.x, d.z)
	fish.stamina = 1.0; fish.run = 0.0; fish.run_t = rng.randf_range(0.6, 1.4); fish.slack_t = 0.0; fish.over_t = 0.0; fish.jump_t = rng.randf_range(3.0, 7.0)
	tension = 0.4
	game.player.speed_mult = 0.0
	Sfx.play("crunch", 0.4, 1.8)
	_say("FISH ON! Hold left mouse to reel. Turn the rod against its runs.", 3.0)

# ---------------------------------------------------------------- the fight
func _fight_step(dt: float) -> void:
	var p: Player = game.player
	var f := fish
	# the fish decides: a run (left, right or straight out) or a rest
	f.run_t -= dt
	if f.run_t <= 0.0:
		if f.run != 0.0 or rng.randf() < 0.35:
			f.run = 0.0; f.run_t = rng.randf_range(0.8, 2.0) * (1.4 - f.stamina * 0.6)
		else:
			f.run = [-1.0, 1.0, 0.001][rng.randi() % 3]; f.run_t = rng.randf_range(1.2, 3.0) * (0.5 + f.stamina * 0.6)
	var running: bool = f.run != 0.0
	var pull: float = f.str * (1.0 if running else 0.3) * (0.4 + 0.6 * f.stamina)
	# where your rod points against where the fish is: side pressure the other way turns it and tires it
	var to_fish := Vector3(sin(f.ang), 0, cos(f.ang))
	var fw := p.fwd()
	var rod_side := signf(fw.cross(to_fish).y) * minf(1.0, absf(asin(clampf(fw.cross(to_fish).y, -1.0, 1.0))) / 0.7)
	var against := 0.0
	if running and absf(f.run) > 0.5: against = -rod_side * signf(f.run)      # rod pulled the other way from the run
	var want := pull * 0.75 + (0.38 if reel_held else 0.02) - against * 0.22 + (0.15 if reel_held and running else 0.0)
	tension = lerpf(tension, clampf(want, 0.0, 1.3), minf(1.0, dt * 3.0))
	# the line: running fish take line (less if the drag's fighting them), reeling takes it back
	var take: float = (f.spd * 1.8 if running else 0.0) * (1.0 - clampf(against, 0.0, 1.0) * 0.6)
	if reel_held: take -= REEL_SPEED * (0.45 if running else 1.0)
	f.dist = clampf(f.dist + take * dt, 0.5, 60.0)
	if running and absf(f.run) > 0.5: f.ang += f.run * (0.35 - against * 0.25) * dt * f.spd
	# tiring: worn down by tension, faster with good side pressure
	f.stamina = maxf(0.0, f.stamina - dt * (0.018 + tension * 0.05 + maxf(against, 0.0) * 0.05) / maxf(0.4, f.str))
	if reel_held: _click(dt)
	# a jump now and then while it's still fresh
	f.jump_t -= dt
	if f.jump_t <= 0.0 and f.stamina > 0.4:
		f.jump_t = rng.randf_range(4.0, 9.0)
		var jp := _fish_world()
		game.saw._emit(jp, Vector3(0, 2.5, 0), 14, Color(0.85, 0.9, 0.92), 1.6, 0.03)
		Sfx.play("drop", 0.6, 1.0)
	# snapped / thrown / landed
	if tension > 1.0: f.over_t += dt
	else: f.over_t = maxf(0.0, f.over_t - dt * 2.0)
	if f.over_t > 0.55:
		Sfx.play("crack", 0.6, 1.8)
		_lost("SNAP! Too much tension. The line broke and it's gone.")
		return
	if tension < 0.08: f.slack_t += dt
	else: f.slack_t = 0.0
	if f.slack_t > 2.6:
		_lost("Slack line... it shook the hook.")
		return
	if f.dist < 2.2:
		if f.stamina < 0.3: _landed(); return
		f.run = [-1.0, 1.0][rng.randi() % 2]; f.run_t = 1.5; f.dist = 3.0      # not done yet: one more run at your feet

func _fish_world() -> Vector3:
	var p: Vector3 = game.player.global_position
	var q := p + Vector3(sin(fish.ang), 0, cos(fish.ang)) * float(fish.dist)
	var wy := water_at(q)
	q.y = wy if wy != INF else game.world.H(q.x, q.z) + 0.05
	return q

func _lost(why: String) -> void:
	game.player.speed_mult = 1.0
	_retrieve(why)
	tension = 0.0

# ---------------------------------------------------------------- landed
func _landed() -> void:
	state = "landed"
	game.player.speed_mult = 1.0
	Sfx.play("thud", 0.4, 1.6); Sfx.play("ding", 0.4, 1.3)
	shadow.visible = false; bobber.visible = false
	var sp: Dictionary = SPECIES[fish.name]
	caught = _fish_model(fish.name, float(fish.len)).instance()
	game.player.cam.add_child(caught)
	caught.position = Vector3(0.05, -0.18, -0.55)
	caught.rotation = Vector3(0.15, PI / 2 + 0.2, 0.25)
	var cm: float = fish.len; var kg: float = fish.kg
	var inch := cm / 2.54; var lb := kg * 2.2046
	var c := Career.load()
	var log: Dictionary = c.get("fish", {})
	var best: float = float((log.get(fish.name, {}) as Dictionary).get("best", 0.0))
	var record := cm > best
	var value := maxi(1, roundi(lb * float(sp.price)))
	fish.value = value
	card_lbl.text = "[font_size=26][b]%s[/b][/font_size]\n%.1f cm  (%.1f in)\n%.2f kg  (%d lb %d oz)%s\n\n[b]Left click[/b] keep it (+$%d)    [b]Right click[/b] let it go" % [
		fish.name, cm, inch, kg, int(lb), int(fmod(lb, 1.0) * 16.0), "\n[color=#ffd36a]New personal best![/color]" if record else "", value]
	card.visible = true
	_say("", 0.0)

func _keep(keep: bool) -> void:
	var c := Career.load()
	var log: Dictionary = c.get("fish", {})
	var e: Dictionary = log.get(fish.name, {count = 0, best = 0.0})
	e.count = int(e.get("count", 0)) + 1
	e.best = maxf(float(e.get("best", 0.0)), float(fish.len))
	log[fish.name] = e
	c.fish = log
	if keep:
		c.money = int(c.money) + int(fish.value)
		game.money = int(c.money)
		Sfx.play("cash", 0.6)
	else:
		Sfx.play("drop", 0.5, 1.2)
	Career.save(c)
	var what: String = ("Kept it. +$%d" % int(fish.value)) if keep else "Back it goes. Grow bigger."
	card.visible = false
	if caught: caught.queue_free(); caught = null
	_retrieve(what)

# ---------------------------------------------------------------- every frame
func step(dt: float) -> void:
	t += dt
	if msg_t > 0.0:
		msg_t -= dt
		if msg_t <= 0.0: msg = ""
	_music_step(dt)
	if not rod.visible: return
	if meter >= 0.0:
		meter_t += dt
		var ph := fmod(meter_t / CAST_T, 2.0)
		meter = ph if ph <= 1.0 else 2.0 - ph
	match state:
		"fly":
			fly_t += dt / 0.9
			var k := minf(1.0, fly_t)
			lure = fly_from.lerp(fly_to, k) + Vector3(0, sin(k * PI) * (1.5 + fly_from.distance_to(fly_to) * 0.18), 0)
			if fly_t >= 1.0: _land()
		"wait": _wait_step(dt)
		"fight": _fight_step(dt)
		"snag":
			if alt_held:
				var to: Vector3 = game.player.global_position - lure; to.y = 0
				if to.length() < 2.0: _retrieve("Reeled in.")
				else: lure += to.normalized() * 3.0 * dt; lure.y = game.world.H(lure.x, lure.z) + 0.03
	_pose(dt)
	_draw()
	gauge.queue_redraw()
	lbl.text = msg if msg != "" else prompt()

func _music_step(dt: float) -> void:
	if music == null or music.stream == null: return
	if rod.visible:
		if not music.playing: music.play()
		music_k = minf(1.0, music_k + dt / FADE_IN)
	elif music.playing:
		music_k = maxf(0.0, music_k - dt / FADE_OUT)
		if music_k <= 0.0: music.stop()
	# ease in on a curve so the first few seconds creep up from silence
	music.volume_db = linear_to_db(maxf(MUSIC_VOL * music_k * music_k, 0.0001))

func _pose(dt: float) -> void:
	# the rod in your hands: out in front, tip up; it bends down toward a fish on and dips as you reel
	var bend := 0.0
	var side := 0.0
	if state == "fight":
		bend = tension * 0.35
		var to_fish := Vector3(sin(fish.ang), 0, cos(fish.ang))
		var local: Vector3 = game.player.global_transform.basis.inverse() * to_fish
		side = clampf(-local.x, -1.0, 1.0) * 0.3
	if state == "aim" and meter >= 0.0: bend = -0.5 * meter        # cocked back over your shoulder for the cast
	rod.transform = Transform3D(Basis(Vector3.UP, side) * Basis(Vector3.RIGHT, -0.35 - bend), Vector3(0.22, -0.32, -0.4))
	# the float on the water (dips on a nibble, under on the bite), the shadow below
	if state == "wait" or state == "fly" or state == "snag":
		var dip := 0.0
		if not fish.is_empty():
			if fish.get("dip", 0.0) > 0.0:
				fish.dip = maxf(0.0, fish.dip - dt); dip = sin(fish.dip / 0.35 * PI) * 0.05
			if fish.phase == "bite": dip = 0.22
		var bob := sin(t * 2.3) * 0.008 if state == "wait" else 0.0
		bobber.global_position = lure + Vector3(0, bob - dip, 0)
		bobber.visible = true
	elif state == "fight":
		bobber.global_position = _fish_world() + Vector3(0, -0.15, 0)
		bobber.visible = false
	shadow.visible = (state == "wait" and not fish.is_empty()) or state == "fight"
	if shadow.visible:
		var sp: Vector3 = fish.pos if state == "wait" else _fish_world()
		var dir: Vector3 = lure - sp if state == "wait" else Vector3(cos(fish.ang + PI / 2), 0, sin(fish.ang + PI / 2)) * signf(fish.run + 0.001)
		dir.y = 0
		var s := clampf(float(fish.len) / 40.0, 0.45, 2.6)
		var yaw := atan2(dir.x, dir.z) if dir.length() > 0.01 else 0.0
		shadow.global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, 1, s * 2.2)), Vector3(sp.x, sp.y - 0.04, sp.z))

func _tip() -> Vector3:
	return rod.global_transform * rod_tip

func _draw() -> void:
	line_im.clear_surfaces()
	if state == "aim" or state == "landed" or state == "off": return
	var a := _tip()
	var b := lure if state != "fight" else _fish_world()
	var sag := 0.0 if state == "fight" and tension > 0.2 else clampf(a.distance_to(b) * 0.06, 0.05, 1.2)
	if state == "fight": sag = (1.0 - clampf(tension, 0.0, 1.0)) * clampf(a.distance_to(b) * 0.05, 0.0, 1.0)
	var cam := get_viewport().get_camera_3d()
	line_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 16
	for i in range(n):
		var t0 := float(i) / n; var t1 := float(i + 1) / n
		var p0 := a.lerp(b, t0) - Vector3(0, sag * 4.0 * t0 * (1.0 - t0), 0)
		var p1 := a.lerp(b, t1) - Vector3(0, sag * 4.0 * t1 * (1.0 - t1), 0)
		var along := (p1 - p0).normalized()
		var w := 0.004 + 0.004 * t0
		var side := along.cross((cam.global_position - p0).normalized() if cam else Vector3.UP).normalized() * w
		for q in [p0 - side, p1 - side, p1 + side, p0 - side, p1 + side, p0 + side]: line_im.surface_add_vertex(q)
	line_im.surface_end()

func _click(dt: float) -> void:
	_click_t -= dt
	if _click_t <= 0.0:
		_click_t = 0.11
		Sfx.play("blip", 0.06, 2.4)

func _say(s: String, secs: float) -> void:
	msg = s; msg_t = secs

func prompt() -> String:
	match state:
		"aim": return "Hold left mouse to cast · let go to throw" if meter < 0.0 else "Cast: %d ft" % roundi((2.5 + meter * (MAX_CAST - 2.5)) * 3.28)
		"wait": return "Strike: left mouse when the float goes under · right mouse: reel slow / tap to twitch"
		"fight": return "Left mouse: reel · turn against the run · %.1f m" % float(fish.dist)
		"snag": return "Hold right mouse to reel in"
	return ""

# ---------------------------------------------------------------- models
func _rod_mb() -> MeshBuilder:
	var mb := MeshBuilder.new()
	mb.tube(Vector3(0, -0.1, 0.05), Vector3(0, 0.12, -0.02), 0.017, 0.015, Color("#b8946a"), 8, true)       # cork grip
	mb.tube(Vector3(0, 0.12, -0.02), rod_tip, 0.008, 0.0025, Color("#2a2a30"), 6, true)                    # the blank
	mb.cyl(0, 0.02, 0.0, 0.035, 0.035, 0.05, Color("#8a8e94"), 12, true)                                      # the reel
	mb.box(0, 0.045, 0.03, 0.01, 0.04, 0.05, Color("#6a6e74"))
	for k in range(5):
		var q := Vector3(0, 0.12, -0.02).lerp(rod_tip, 0.15 + k * 0.2)
		mb.sphere(q.x, q.y - 0.012, q.z, 0.007, 0.007, 0.007, Color("#c8ccd0"), 5, 3)                          # guides
	return mb

## a fish to hold up: body, tail, fins, an eye, coloured dark on top and pale underneath
func _fish_model(name: String, cm: float) -> MeshBuilder:
	var sp: Dictionary = SPECIES[name]
	var L := clampf(cm / 100.0, 0.12, 1.2)
	var long := name == "Northern pike" or name == "Muskellunge" or name == "Walleye" or name == "Brook trout"
	var deep := 0.17 if long else (0.32 if name == "Bluegill" or name == "Black crappie" else 0.24)
	var mb := MeshBuilder.new()
	var top: Color = sp.top; var belly: Color = sp.belly
	mb.sphere(0, 0, 0, L * 0.5, L * deep, L * 0.09, top, 14, 8)
	mb.sphere(0, -L * deep * 0.35, 0, L * 0.44, L * deep * 0.7, L * 0.085, belly, 12, 6)
	for sz: float in [-1.0, 1.0]: mb.sphere(L * 0.36, L * deep * 0.25, sz * L * 0.07, L * 0.03, L * 0.03, L * 0.02, Color("#1a1a1a"), 6, 4)
	mb.face([Vector3(-L * 0.45, 0, 0), Vector3(-L * 0.68, L * deep * 0.95, 0), Vector3(-L * 0.62, 0, 0)], MeshBuilder.shade(top, 0.8))
	mb.face([Vector3(-L * 0.45, 0, 0), Vector3(-L * 0.62, 0, 0), Vector3(-L * 0.68, -L * deep * 0.95, 0)], MeshBuilder.shade(top, 0.8))
	mb.face([Vector3(L * 0.15, L * deep * 0.9, 0), Vector3(-L * 0.25, L * deep * 1.35, 0), Vector3(-L * 0.3, L * deep * 0.8, 0)], MeshBuilder.shade(top, 0.75))
	if name == "Brook trout":
		var r := RandomNumberGenerator.new(); r.seed = 7
		for k in range(14):
			mb.sphere(r.randf_range(-0.35, 0.3) * L, r.randf_range(-0.1, 0.6) * L * deep, 0.085 * L, L * 0.012, L * 0.012, L * 0.01, Color("#e8d070") if k % 3 else Color("#d8402a"), 4, 3)
	return mb

# ---------------------------------------------------------------- the meters
func _build_ui() -> void:
	ui = CanvasLayer.new(); ui.layer = 6; add_child(ui)
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	gauge = Gauges.new(); gauge.fishing = self
	gauge.set_anchors_preset(Control.PRESET_FULL_RECT); gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(gauge)
	lbl = Label.new(); lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85)); lbl.add_theme_constant_override("outline_size", 6)
	lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM); lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.offset_left = -420; lbl.offset_right = 420; lbl.offset_top = -132; lbl.offset_bottom = -100
	root.add_child(lbl)
	card = PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.07, 0.08, 0.07, 0.86); sb.set_corner_radius_all(8)
	sb.content_margin_left = 18; sb.content_margin_right = 18; sb.content_margin_top = 12; sb.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", sb)
	card.set_anchors_preset(Control.PRESET_CENTER_TOP); card.offset_left = -230; card.offset_right = 230; card.offset_top = 70
	card_lbl = RichTextLabel.new(); card_lbl.bbcode_enabled = true; card_lbl.fit_content = true; card_lbl.scroll_active = false
	card_lbl.custom_minimum_size = Vector2(420, 0)
	card_lbl.add_theme_font_size_override("normal_font_size", 17); card_lbl.add_theme_font_size_override("bold_font_size", 17)
	card.add_child(card_lbl); card.visible = false
	root.add_child(card)
	ui.visible = false

## cast meter while you wind up; line tension and the fish's stamina in a fight
class Gauges extends Control:
	var fishing
	func _draw() -> void:
		var f = fishing
		var W := size.x; var H := size.y
		if f.state == "aim" and f.meter >= 0.0:
			var w := 320.0; var x0 := (W - w) / 2.0; var y0 := H - 175.0
			draw_rect(Rect2(x0 - 3, y0 - 3, w + 6, 22), Color(0, 0, 0, 0.55))
			var c: Color = Color(0.45, 0.85, 1.0).lerp(Color(1.0, 0.85, 0.35), f.meter)
			draw_rect(Rect2(x0, y0, w * f.meter, 16), c)
			for k in range(1, 4): draw_line(Vector2(x0 + w * k / 4.0, y0), Vector2(x0 + w * k / 4.0, y0 + 16), Color(1, 1, 1, 0.35), 1.0)
		if f.state == "fight":
			var w := 340.0; var x0 := (W - w) / 2.0; var y0 := 96.0
			# tension: green, amber, then the red snap zone
			draw_rect(Rect2(x0 - 3, y0 - 3, w + 6, 24), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(x0 + w * (1.0 / 1.3), y0, w * (0.3 / 1.3), 18), Color(0.55, 0.12, 0.1, 0.8))
			var tk: float = clampf(f.tension / 1.3, 0.0, 1.0)
			var tc := Color(0.4, 0.95, 0.45) if f.tension < 0.7 else (Color(1.0, 0.8, 0.3) if f.tension < 1.0 else Color(1.0, 0.3, 0.25))
			draw_rect(Rect2(x0, y0, w * tk, 18), tc)
			draw_string(ThemeDB.fallback_font, Vector2(x0, y0 - 8), "LINE TENSION", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.9))
			# stamina
			var y1 := y0 + 44.0
			draw_rect(Rect2(x0 - 3, y1 - 3, w + 6, 16), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(x0, y1, w * float(f.fish.stamina), 10), Color(0.4, 0.75, 1.0))
			draw_string(ThemeDB.fallback_font, Vector2(x0, y1 - 6), "FISH", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.9))
			# which way it's running
			if absf(float(f.fish.run)) > 0.5:
				var ax := W / 2.0 + float(f.fish.run) * 220.0
				var ay := y0 + 9.0
				var s := float(f.fish.run)
				draw_colored_polygon(PackedVector2Array([Vector2(ax + s * 18, ay), Vector2(ax - s * 4, ay - 12), Vector2(ax - s * 4, ay + 12)]), Color(1, 0.9, 0.5))
