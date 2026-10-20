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
	# the legend off Gus's shore: an enormous old largemouth. Only at Gus's lake, and rarely
	"Gerald": {where = "legend", w = 0.0, len = [66.0, 72.0], str = 1.7, spd = 1.5, price = 20.0, top = Color("#2e4a26"), belly = Color("#e8e4c8")},
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
var jig_t := 0.0                  # the lure hops when you jig it
var bend := 0.0                   # how far the rod's pulled off the line (0 pointing at the fish, 1 hauled right back)
# the fishing song: fades in slowly when you take the rod out, fades away when you put it up
const MUSIC := "res://audio/fishing_theme.mp3"
const MUSIC_VOL := 0.55
const FADE_IN := 9.0
const FADE_OUT := 3.0
var music: AudioStreamPlayer
var music_k := 0.0
var under: Underwater
var reel_snd: AudioStreamPlayer
var strain_snd: AudioStreamPlayer
var drag_snd: AudioStreamPlayer
var line_out := 0.0               # how fast the fish is taking line (m/s), for the drag
var _creak_t := 0.0

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
	reel_snd = AudioStreamPlayer.new(); reel_snd.stream = Sfx.sounds.get("reel"); reel_snd.volume_db = -80; add_child(reel_snd)
	drag_snd = AudioStreamPlayer.new(); drag_snd.stream = Sfx.sounds.get("drag"); drag_snd.volume_db = -80; add_child(drag_snd)
	strain_snd = AudioStreamPlayer.new(); strain_snd.stream = Sfx.sounds.get("strain"); strain_snd.volume_db = -80; add_child(strain_snd)
	under = Underwater.new(); under.name = "Underwater"; add_child(under)
	under.setup(self)
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
		"wait", "fight", "snag":
			reel_held = down
		"landed":
			if down: _keep(true)

## right mouse: jig the lure
func alt(down: bool) -> void:
	alt_held = down
	match state:
		"wait":
			if down: _twitch()
		"landed":
			if down: _keep(false)

## mouse wheel down: set the hook
func wheel_down() -> void:
	if state == "wait": _strike()

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
		_say("That's in the grass. Hold left mouse to reel it in and try again.", 3.0)
		return
	state = "wait"
	interest = 0.15
	fish = {}
	Sfx.play("drop", 0.45, 1.8)
	game.saw._emit(lure, Vector3(0, 1.4, 0), 8, Color(0.85, 0.9, 0.92), 1.0, 0.025)
	_say("Watch the float. When it goes under, scroll the wheel down to set the hook. Right mouse jigs.", 4.0)

func _retrieve(why: String) -> void:
	state = "aim"; fish = {}; reel_held = false
	bobber.visible = false; shadow.visible = false
	if why != "": _say(why, 2.0)

var last_jig := -100.0

func _twitch() -> void:
	last_jig = t
	interest = minf(1.0, interest + 0.18)
	var nxt: Vector3 = lure + (game.player.global_position - lure).normalized() * 0.25 * Vector3(1, 0, 1)
	if water_at(nxt) != INF: lure = nxt
	jig_t = 0.3
	Sfx.play("drop", 0.15, 2.4)

# ---------------------------------------------------------------- waiting for a bite
func _spot_fish() -> Dictionary:
	var where := _where()
	if not game.in_hub and game.job.id == "dock" and rng.randf() < 0.035:
		var gl := rng.randf_range(66.0, 72.0)
		return {name = "Gerald", len = gl, kg = 0.0000118 * pow(gl, 3.0) * 1.15, str = 1.7, spd = 1.5}
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
	var kg := 0.0000118 * pow(L, 3.0) * (0.85 if name == "Northern pike" or name == "Muskellunge" else (1.6 if name == "Bluegill" or name == "Black crappie" or name == "Rock bass" else 1.0))
	return {name = name, len = L, kg = kg, str = float(sp.str) * (0.7 + 0.6 * k), spd = float(sp.spd)}

func _wait_step(dt: float) -> void:
	var p: Player = game.player
	# reeling the lure in slowly (holding left mouse)
	if reel_held:
		var to := p.global_position - lure; to.y = 0
		if to.length() < 2.6: _retrieve("Lure's in."); return
		var nxt := lure + to.normalized() * RETRIEVE * dt
		if water_at(nxt) == INF: _retrieve("Lure's in."); return
		lure = nxt
		interest = minf(1.0, interest + dt * 0.08)
	if fish.is_empty():
		interest = maxf(0.1, interest - dt * 0.01)
		# something takes an interest
		if rng.randf() < dt * (0.12 + interest * 0.35):
			fish = _spot_fish(); fish.uid = rng.randi()
			# from somewhere out in the water, never up the bank
			fish.pos = lure
			for tries in range(12):
				var a := rng.randf() * TAU
				var q := lure + Vector3(cos(a), 0, sin(a)) * rng.randf_range(2.5, 7.0)
				if water_at(q) != INF: fish.pos = q; break
			fish.pos.y = lure.y
			fish.phase = "come"; fish.nibbles = rng.randi_range(1, 3); fish.next = 0.0
		return
	# the shadow drifts in, then nibbles, then takes it
	match fish.phase:
		"come":
			var to: Vector3 = lure - fish.pos; to.y = 0
			if to.length() < 0.9:
				# it doesn't just take it: it has a look first, circling round the lure
				fish.phase = "circle"; fish.next = rng.randf_range(1.6, 3.6)
				fish.ca = atan2(fish.pos.z - lure.z, fish.pos.x - lure.x); fish.cdir = [-1.0, 1.0][rng.randi() % 2]
			else:
				fish.pos += to.normalized() * minf(to.length(), (0.8 + 0.6 * float(fish.spd)) * dt)
		"circle":
			fish.next -= dt
			var na: float = fish.ca + fish.cdir * 1.1 * dt
			var q: Vector3 = lure + Vector3(cos(na), 0, sin(na)) * 0.8
			if water_at(q) != INF:
				fish.ca = na
				fish.pos = fish.pos.lerp(Vector3(q.x, lure.y, q.z), minf(1.0, dt * 3.0))
			else:
				fish.cdir = -fish.cdir
			if fish.next <= 0.0: fish.phase = "approach"
		"approach":
			var to: Vector3 = lure - fish.pos; to.y = 0
			if to.length() < 0.35:
				fish.phase = "nibble"; fish.next = rng.randf_range(0.6, 1.8)
			else:
				fish.pos += to.normalized() * minf(to.length(), 0.6 * dt)
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
	if fish.is_empty() or fish.phase == "come" or fish.phase == "spooked" or fish.phase == "circle" or fish.phase == "approach":
		_say("Nothing there. Wait for the float to go under.", 1.8)
		return
	if fish.phase == "nibble":
		fish.phase = "spooked"; fish.next = 1.2
		Ach.set_stat("clean_catches", 0)
		_say("Too early! That was a nibble. It spooked.", 2.2)
		interest = 0.05
		return
	# hooked!
	state = "fight"
	var d := Vector3(lure.x - game.player.global_position.x, 0, lure.z - game.player.global_position.z)
	fish.dist = d.length(); fish.ang = atan2(d.x, d.z)
	fish.max_t = 0.0
	if t - last_jig < 5.0: Ach.unlock("lucky_jig")
	fish.stamina = 1.0; fish.run = 0.0; fish.run_t = rng.randf_range(0.6, 1.4); fish.slack_t = 0.0; fish.over_t = 0.0; fish.jump_t = rng.randf_range(3.0, 7.0)
	tension = 0.4
	game.player.speed_mult = 0.0
	Sfx.play("crunch", 0.4, 1.8)
	_say("FISH ON! Hold left mouse to reel. Aim the rod at the fish to ease the tension, pull away to put pressure on.", 3.5)

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
	# tension follows the rod, and the rod follows your look: point it at the fish and the line eases off,
	# pull it away (up or to the side) and the rod bends and loads the line
	var eye: Vector3 = p.cam.global_position
	var fpos := _fish_world()
	var to_fish3 := (fpos - eye).normalized()
	var look := -p.cam.global_transform.basis.z
	bend = clampf(look.angle_to(to_fish3) / 1.1, 0.0, 1.0)
	var to_fish := Vector3(to_fish3.x, 0, to_fish3.z).normalized()
	var fw := Vector3(look.x, 0, look.z).normalized()
	var side := clampf(fw.signed_angle_to(to_fish, Vector3.UP) / 0.8, -1.0, 1.0)     # + rod off to the right of the fish
	var against := 0.0
	if running and absf(f.run) > 0.5: against = clampf(side * signf(f.run), 0.0, 1.0)  # rod swung the opposite way to the run
	var want := pull * (0.25 + 0.6 * bend) + bend * 0.45 + (0.28 if reel_held else 0.0)
	tension = lerpf(tension, clampf(want, 0.0, 1.4), minf(1.0, dt * 4.0))
	f.max_t = maxf(float(f.get("max_t", 0.0)), tension)
	# the line: a running fish takes line against a light drag; reeling takes it back, faster with the rod loaded
	var take: float = (f.spd * 1.8 if running else 0.0) * (1.0 - clampf(tension, 0.0, 1.0) * 0.7) * (1.0 - against * 0.5)
	if reel_held: take -= REEL_SPEED * (0.5 if running else 1.0) * (0.6 + 0.6 * bend)
	var old_d: float = f.dist; var old_a: float = f.ang
	line_out = maxf(0.0, take)
	f.dist = clampf(f.dist + take * dt, 0.5, 60.0)
	if running and absf(f.run) > 0.5: f.ang += f.run * (0.35 - against * 0.25) * dt * f.spd
	# fish stay in the water: a run that would take it up the bank turns it back
	if water_at(_fish_world()) == INF:
		if reel_held and f.stamina < 0.3 and f.dist < old_d: _landed(); return     # tired out: drag it up onto the bank
		f.dist = old_d; f.ang = old_a
		if running: f.run = -f.run
	# tiring: worn down by tension, faster with good side pressure
	f.stamina = maxf(0.0, f.stamina - dt * (0.018 + tension * 0.06 + against * 0.06) / maxf(0.4, f.str))
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
	caught = fish_mesh(fish.name, float(fish.len))
	game.player.cam.add_child(caught)
	# held up in the middle of the screen, side on, far enough off that the whole fish fits
	var d := clampf(float(fish.len) / 100.0 * 1.3, 0.38, 1.7)
	caught.position = Vector3(0.0, d * 0.12, -d)
	caught.rotation = Vector3.ZERO
	var cm: float = fish.len; var kg: float = fish.kg
	var inch := cm / 2.54; var lb := kg * 2.2046
	var c := Career.load()
	var log: Dictionary = c.get("fish", {})
	var best: float = float((log.get(fish.name, {}) as Dictionary).get("best", 0.0))
	var record := cm > best
	var value := maxi(1, roundi(lb * float(sp.price)))
	fish.value = value
	card_lbl.text = "[center][font_size=30][b]%s[/b][/font_size]\n[font_size=20]Length  [b]%.1f in[/b]  (%.1f cm)\nWeight  [b]%d lb %d oz[/b]  (%.2f kg)[/font_size]%s\n\n[b]Left click[/b] keep it (+$%d)    [b]Right click[/b] let it go[/center]" % [
		fish.name, inch, cm, int(lb), int(fmod(lb, 1.0) * 16.0), kg, "\n[color=#ffd36a]New personal best![/color]" if record else "", value]
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
	_catch_achievements(keep)
	var what: String = ("Kept it. +$%d" % int(fish.value)) if keep else "Back it goes. Grow bigger."
	card.visible = false
	if caught: caught.queue_free(); caught = null
	_retrieve(what)

## (after the catch is saved, so the log already has it)
func _catch_achievements(keep: bool) -> void:
	var n: String = fish.name
	var lb := float(fish.kg) * 2.2046
	Ach.unlock("first_bite")
	if (n == "Largemouth bass" or n == "Gerald") and lb >= 5.0: Ach.unlock("lunker")
	if n == "Muskellunge": Ach.unlock("muskie")
	if n == "Gerald": Ach.unlock("gerald")
	if float(fish.get("max_t", 2.0)) < 1.0: Ach.unlock("line_dancer")
	if Ach.add("clean_catches") >= 5: Ach.unlock("patience")
	if not game.in_hub and game.job.id == "hale": Ach.unlock("golden_hour")
	if keep: Ach.earn(int(fish.value))
	else: Ach.add("released")
	var log: Dictionary = Career.load().get("fish", {})
	var all_creek := true; var all_lake := true; var all := true
	for s in SPECIES:
		var w: String = SPECIES[s].where
		var got := log.has(s)
		if not got: all = false
		if w == "creek" and not got: all_creek = false
		if w == "lake" and not got: all_lake = false
	if all_creek: Ach.unlock("mixed_bag")
	if all_lake: Ach.unlock("lake_life")
	if all: Ach.unlock("gone_fishin")

# ---------------------------------------------------------------- every frame
func step(dt: float) -> void:
	t += dt
	if msg_t > 0.0:
		msg_t -= dt
		if msg_t <= 0.0: msg = ""
	_music_step(dt)
	_reel_sounds(dt)
	under.step(dt)
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
			if reel_held:
				var to: Vector3 = game.player.global_position - lure; to.y = 0
				if to.length() < 2.0: _retrieve("Reeled in.")
				else: lure += to.normalized() * 3.0 * dt; lure.y = game.world.H(lure.x, lure.z) + 0.03
	_pose(dt)
	_draw()
	gauge.queue_redraw()
	lbl.text = msg if msg != "" else prompt()

## the reel: a ticking whir while you wind in (it labours under load), the drag buzzing as a fish takes
## line - louder and higher the harder it pulls - and the rod creaking when it's close to breaking
func _reel_sounds(dt: float) -> void:
	var winding: bool = rod.visible and reel_held and (state == "wait" or state == "fight" or state == "snag")
	var reel_v := 0.0; var drag_v := 0.0; var strain_v := 0.0
	if winding:
		# soft clicks; they slow as the reel labours against a fish
		reel_v = 0.4
		reel_snd.pitch_scale = clampf(1.1 - tension * 0.3, 0.75, 1.1) if state == "fight" else 1.1
	if rod.visible and state == "fight":
		var buzz := clampf(line_out / 2.0, 0.0, 1.0) * clampf(0.35 + tension, 0.0, 1.2)
		drag_v = buzz
		# in the red: the line itself strains, a whine that climbs and grows as it nears breaking
		if tension >= 1.0:
			strain_v = 0.35 + clampf((tension - 1.0) / 0.3, 0.0, 1.0) * 0.45
			strain_snd.pitch_scale = 0.95 + clampf((tension - 1.0) / 0.3, 0.0, 1.0) * 0.3
		drag_snd.pitch_scale = 0.85 + clampf(tension, 0.0, 1.3) * 0.35
		_creak_t -= dt
		if tension > 0.95 and _creak_t <= 0.0:
			_creak_t = randf_range(0.5, 0.9)
			Sfx.play("creak", 0.35 + (tension - 0.95) * 1.5, randf_range(1.3, 1.6))
	else:
		line_out = 0.0
	for e in [[reel_snd, reel_v], [drag_snd, drag_v], [strain_snd, strain_v]]:
		var p: AudioStreamPlayer = e[0]; var v: float = e[1]
		if p.stream == null: continue
		if v > 0.01 and not p.playing: p.play()
		var cur := db_to_linear(p.volume_db)
		cur = move_toward(cur, v, dt * 4.0)
		p.volume_db = linear_to_db(maxf(cur, 0.0001))
		if cur <= 0.002 and v <= 0.01 and p.playing: p.stop()

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
	var rb := 0.0
	if state == "fight": rb = tension * 0.35
	if state == "aim" and meter >= 0.0: rb = -0.5 * meter        # cocked back over your shoulder for the cast
	jig_t = maxf(0.0, jig_t - dt)
	rb -= sin(jig_t / 0.3 * PI) * 0.25                             # a flick of the tip when you jig
	rod.transform = Transform3D(Basis(Vector3.RIGHT, -0.35 - rb), Vector3(0.22, -0.32, -0.4) + (Vector3(0.25, -0.45, 0.1) if state == "landed" else Vector3.ZERO))
	# the catch, turning a little in your hands
	if state == "landed" and caught:
		caught.rotation = Vector3(0.0, sin(t * 1.1) * 0.18, sin(t * 6.0) * 0.03)
	# the float on the water (dips on a nibble, under on the bite), the shadow below
	if state == "wait" or state == "fly" or state == "snag":
		var dip := 0.0
		if not fish.is_empty():
			if fish.get("dip", 0.0) > 0.0:
				fish.dip = maxf(0.0, fish.dip - dt); dip = sin(fish.dip / 0.35 * PI) * 0.05
			if fish.phase == "bite": dip = 0.22
		var bob := sin(t * 2.3) * 0.008 if state == "wait" else 0.0
		bob += sin(jig_t / 0.3 * PI) * 0.04
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
		"wait": return "Wheel down to set the hook when the float goes under · right mouse: jig · hold left: reel in"
		"fight": return "Left mouse: reel · aim at the fish to ease off, pull away to load the rod · %.1f m" % float(fish.dist)
		"snag": return "Hold left mouse to reel in"
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
## the fish as a ready-to-place mesh, its real length: a modelled one from models/fish/<species>.glb when
## there is one (built 1 m long, nose along +x), otherwise the one put together in code below.
## Its "mouth" meta is where the line goes in, in the mesh's own space
static var _fish_meshes := {}
static var _fish_mouths := {}
static func _find_mouth(m: Mesh) -> Vector3:
	var vs: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var mx := -INF
	for v in vs: mx = maxf(mx, v.x)
	var ys := []
	for v in vs:
		if v.x > mx - 0.02: ys.append(v.y)
	ys.sort()
	return Vector3(mx - 0.015, ys[ys.size() / 2] if not ys.is_empty() else 0.0, 0.0)
func fish_mesh(name: String, cm: float) -> MeshInstance3D:
	var key := name.to_lower().replace(" ", "_")
	if not _fish_meshes.has(key):
		var m: Mesh = null
		var path := "res://models/fish/%s.glb" % key
		if key == "gerald" and not ResourceLoader.exists(path): path = "res://models/fish/largemouth_bass.glb"   # the old legend is a largemouth
		if ResourceLoader.exists(path):
			var inst: Node = (load(path) as PackedScene).instantiate()
			var found := inst.find_children("*", "MeshInstance3D", true, false)
			if not found.is_empty(): m = (found[0] as MeshInstance3D).mesh
			inst.free()
		_fish_meshes[key] = m
		if m: _fish_mouths[key] = _find_mouth(m)
	var mesh: Mesh = _fish_meshes[key]
	var L := clampf(cm / 100.0, 0.12, 1.3)
	if mesh == null:
		var built := _fish_model(name, cm).instance()
		built.set_meta("mouth", Vector3(0.46 * L, -0.02 * L, 0.0))
		return built
	var mi := MeshInstance3D.new(); mi.mesh = mesh
	mi.scale = Vector3.ONE * L
	mi.set_meta("mouth", _fish_mouths[key])
	return mi

func _fish_model(name: String, cm: float) -> MeshBuilder:
	var sp: Dictionary = SPECIES[name]
	if name == "Gerald": name = "Largemouth bass"
	var L := clampf(cm / 100.0, 0.12, 1.3)
	var long := name == "Northern pike" or name == "Muskellunge"
	var slim := long or name == "Walleye" or name == "Brook trout" or name == "Creek chub" or name == "Yellow perch"
	var disc := name == "Bluegill" or name == "Black crappie" or name == "Rock bass"
	var deep := 0.13 if long else (0.17 if slim else (0.3 if disc else 0.22))
	var wide := L * (0.075 if not disc else 0.06)
	var mb := MeshBuilder.new()
	var top: Color = sp.top; var belly: Color = sp.belly
	var fin := MeshBuilder.shade(top, 0.8).lerp(belly, 0.2)
	# body: a fat front tapering to the tail. Its colouring - dark back, pale belly and the species'
	# markings - is painted straight onto the body's vertices, so nothing sticks out past its outline
	var b0 := mb.verts.size()
	mb.sphere(L * 0.08, 0, 0, L * 0.4, L * deep, wide, top, 22, 12)
	mb.sphere(-L * 0.22, L * deep * 0.05, 0, L * 0.28, L * deep * 0.62, wide * 0.75, top, 16, 10)
	var b1 := mb.verts.size()
	for i in range(b0, b1): mb.cols[i] = _fish_skin(name, mb.verts[i], L, deep, top, belly)
	# head and mouth: bass and pike have a big jaw, sunfish a small one
	var jaw := 0.09 if (name.contains("bass") or long or name == "Walleye") else 0.05
	mb.sphere(L * 0.4, -L * deep * 0.12, 0, L * jaw * 1.2, L * jaw * 0.55, wide * 0.6, MeshBuilder.shade(belly, 0.85), 8, 5)
	var eye := L * (0.04 if name == "Walleye" else 0.03)
	for sz: float in [-1.0, 1.0]:
		mb.sphere(L * 0.36, L * deep * 0.28, sz * wide * 0.8, eye, eye, eye * 0.6, Color("#e8d8a0") if name == "Walleye" else Color("#d8c050"), 6, 4)
		mb.sphere(L * 0.365, L * deep * 0.28, sz * wide * 0.92, eye * 0.6, eye * 0.6, eye * 0.4, Color("#101010"), 6, 4)
		# gill line, pectoral fin
		mb.sphere(L * 0.27, 0, sz * wide * 0.85, L * 0.012, L * deep * 0.7, L * 0.006, MeshBuilder.shade(top, 0.7), 5, 4)
		mb.push(Transform3D(Basis(Vector3.UP, sz * 0.5), Vector3(L * 0.22, -L * deep * 0.3, sz * wide * 0.9)))
		mb.sphere(-L * 0.05, 0, 0, L * 0.07, L * 0.03, L * 0.005, fin, 6, 3)
		mb.pop()
	# tail: a forked fan, flat both ways so it reads from either side
	var tx := -L * 0.48
	for sy: float in [-1.0, 1.0]:
		mb.push(Transform3D(Basis(Vector3.BACK, sy * 0.55), Vector3(tx, 0, 0)))
		mb.sphere(-L * 0.08, 0, 0, L * 0.11, L * deep * 0.32, L * 0.008, fin, 8, 4)
		mb.pop()
	# dorsal fin: spiny front and soft back on bass/perch/sunfish, set far back on a pike
	if long:
		mb.sphere(-L * 0.3, L * deep * 0.95, 0, L * 0.08, L * deep * 0.5, L * 0.007, fin, 8, 4)
		mb.sphere(-L * 0.3, -L * deep * 0.9, 0, L * 0.07, L * deep * 0.4, L * 0.007, fin, 8, 4)
	else:
		mb.sphere(L * 0.05, L * deep * 0.95, 0, L * 0.17, L * deep * 0.45, L * 0.007, fin, 10, 4)
		mb.sphere(-L * 0.18, L * deep * 0.85, 0, L * 0.12, L * deep * 0.5, L * 0.007, fin, 8, 4)
		mb.sphere(-L * 0.2, -L * deep * 0.8, 0, L * 0.08, L * deep * 0.35, L * 0.007, fin, 8, 4)
	return mb

## the colour of the fish's skin at this point on its body: back to belly shading plus the markings
func _fish_skin(name: String, p: Vector3, L: float, deep: float, top: Color, belly: Color) -> Color:
	var u := p.x / L                                  # nose +0.48 .. tail -0.48
	var v := p.y / (L * deep)                         # back +1 .. belly -1
	var c := belly.lerp(top, smoothstep(-0.55, 0.15, v))
	var dark := MeshBuilder.shade(top, 0.55)
	if name == "Largemouth bass" or name == "Smallmouth bass":
		if name == "Largemouth bass":
			# the ragged dark stripe nose to tail along the side
			var line := 0.04 + 0.1 * sin(u * 26.0) * 0.6
			if absf(v - line) < 0.26 and u > -0.44 and u < 0.3: c = c.lerp(Color("#22301a"), 0.85)
		else:
			if sin(u * 40.0) > 0.55 and v > -0.35: c = c.lerp(Color("#3e3018"), 0.7)
	elif name == "Yellow perch" or name == "Walleye" or name == "Bluegill" or name == "Rock bass":
		# dark saddles down the flanks
		var k := 0.5 if name == "Walleye" or name == "Rock bass" else 0.75
		if sin(u * 36.0 + 0.6) > 0.35 and v > -0.45 and u < 0.3 and u > -0.42: c = c.lerp(dark, k)
		if name == "Bluegill" and Vector2(u - 0.27, v - 0.15).length() < 0.07: c = Color("#14141c")   # the dark ear flap
	elif name == "Northern pike" or name == "Muskellunge" or name == "Black crappie" or name == "Brook trout" or name == "Creek chub":
		var h := fposmod(sin(p.x * 913.1 + p.y * 471.3 + absf(p.z) * 37.0) * 43758.5, 1.0)
		if v > -0.5 and h > (0.72 if name != "Creek chub" else 0.95):
			if name == "Northern pike": c = Color("#e8e0a0")
			elif name == "Brook trout": c = Color("#d8402a") if h > 0.93 else Color("#e8d070")
			else: c = c.lerp(dark, 0.7)
	if name == "Muskellunge" and sin(u * 30.0) > 0.5 and v > -0.4: c = c.lerp(dark, 0.6)
	return c

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
	# under the fish, which is held up in the middle of the screen
	card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM); card.offset_left = -240; card.offset_right = 240; card.offset_top = -330; card.offset_bottom = -150
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
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
			var w := 340.0; var x0 := (W - w) / 2.0; var y0 := H - 250.0
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
