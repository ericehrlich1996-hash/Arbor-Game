## Climbing the job tree with spurs and a lanyard, the way a removal climber does it.
##   From the ground, with the climbing kit (7): hold left mouse and let go to throw a line up into the
##   crown. If it drops over a good crotch, that's your tie-in: the climbing line runs from there to your
##   saddle. Then walk up to the trunk and press E to spike in.
##   In the tree: W / S climb up and down (Shift + S rappels on the line), A / D work round the trunk.
##   Your lanyard goes round the stem at your waist: a limb stops it. To get past one you hold F, which
##   flips the lanyard over while the climbing line holds you, so you're never clipped to nothing. You
##   can't climb higher than your tie-in. At the bottom, E steps you off.
##   Cut through your own lanyard, or the limb or top your line's tied over, and you fall: it costs you
##   at payday (and some pride).
class_name Climb
extends Node

const HARNESS := 1.0          # your saddle, above your spurs
const UP_SPEED := 0.55
const DOWN_SPEED := 0.7
const RAPPEL := 1.6
const ROUND_SPEED := 0.6
const STAND_OFF := 0.38       # your feet sit this far off the bark
const FALL_COST := 150
const THROW_T := 1.4          # seconds for the throw meter to fill

var game
var tree: AshTree
var climbing := false
var h := 0.0                  # how high your spurs are, up the trunk (wood frame)
var th := 0.0                 # where round the trunk you are (radians, wood frame)
var line := {}                # the climbing line's tie-in: {y, id} (a limb's crotch)
var falls := 0
var falling := false
var block_y := -1.0           # a limb that's stopping the lanyard, or -1
var flip_t := 0.0
var meter := -1.0             # the throw meter, 0..1 while you hold the button; -1 not throwing
var meter_t := 0.0
var max_ft := 0.0             # the highest your saddle's been, in feet
var _face := 0.0              # the yaw that faces the trunk where you are
var _step_acc := 0.0
var _told := {}
var line_im: ImmediateMesh
var line_mi: MeshInstance3D
var bar: ProgressBar

func setup(g) -> void:
	game = g
	tree = g.tree
	line_im = ImmediateMesh.new()
	line_mi = MeshInstance3D.new(); line_mi.mesh = line_im; line_mi.top_level = true
	line_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new(); m.albedo_color = Color("#d8b440"); m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	line_mi.material_override = m
	add_child(line_mi)
	bar = ProgressBar.new()
	bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(16, 140)
	bar.set_anchors_preset(Control.PRESET_CENTER)
	bar.position = Vector2(46, -70)
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0, 0, 0, 0.55); bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new(); fg.bg_color = Color("#d8b440"); fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg); bar.add_theme_stylebox_override("fill", fg)
	bar.max_value = 1.0
	bar.visible = false
	game.hud.root.add_child(bar)

func _exit_tree() -> void:
	if bar and is_instance_valid(bar): bar.queue_free()

static func owned() -> bool:
	return Rigging.owned("climb")

func _tell(key: String, msg: String, secs := 4.0) -> void:
	if _told.has(key) and game.clock - float(_told[key]) < secs + 2.0: return
	_told[key] = game.clock
	game.hud.toast(msg, secs)

# ---------------------------------------------------------------- the throw line
func equip(on: bool) -> void:
	meter = -1.0
	if on and not climbing:
		if line.is_empty(): game.hud.toast("Climbing kit. Look up into the crown, hold left mouse and let go to throw a line over a crotch.", 4.5)
		else: game.hud.toast("Your line's set. Walk up to the trunk and press E to spike in.", 3.0)

## left mouse with the kit in hand, on the ground
func press(down: bool) -> void:
	if climbing or tree.state != "stand": return
	if down:
		meter = 0.0; meter_t = 0.0
		Sfx.play("pull", 0.3, 1.6)
	elif meter >= 0.0:
		_throw(meter)
		meter = -1.0

func _throw(power: float) -> void:
	var p: Player = game.player
	var base := tree.global_position
	var d := Vector2(p.global_position.x - base.x, p.global_position.z - base.z).length()
	if d > 14.0:
		game.hud.toast("Too far off. Get within forty feet or so of the trunk.", 2.5); return
	if p.aim_dir().y < 0.2:
		game.hud.toast("Look up into the crown to throw.", 2.0); return
	Sfx.play("pick", 0.6, 1.3)
	# how high it goes; it drops over the highest crotch below that (a limb's joint with the stem)
	var reach := lerpf(3.5, tree.top_y * 0.95, power)
	var best := -1; var by := -1.0
	for id in tree.on_limbs:
		var L: Dictionary = tree.T.limbs[id]
		var y := float(L.y)
		if y <= reach and y >= reach - 3.2 and y > by and float(tree.on_limbs[id]) > 0.3: best = id; by = y
	if best < 0:
		if reach > tree.top_y * 0.8: game.hud.toast("Clean over the top and down at your feet. Throw a little softer.", 3.0)
		else: game.hud.toast("Fell short, nothing to catch on. Throw harder.", 3.0)
		return
	line = {y = by, id = best}
	Sfx.play("clank", 0.4, 1.4)
	game.hud.toast("It's over a good crotch, about %d ft up. That's your tie-in. Walk up to the trunk and press E to spike in." % roundi(by * 3.28), 5.0)

# ---------------------------------------------------------------- getting on and off
## near the trunk with the kit: spike in. At the bottom: step off. Returns true if it did something.
func interact() -> bool:
	if climbing:
		if h <= 0.12:
			_get_off(); return true
		_tell("off", "Climb all the way down to step off (or Shift + S to rappel).", 2.5)
		return true
	if game.player.tool != "climb" or tree.state != "stand": return false
	if not near_trunk(): return false
	_get_on()
	return true

func near_trunk() -> bool:
	var p: Player = game.player
	var w := tree.to_wood(p.global_position)
	var r := Wood.r_at(tree.T, 1.0)
	return Vector2(w.x, w.z).length() < r + 1.3 and absf(w.y) < 1.5

func _get_on() -> void:
	var p: Player = game.player
	var w := tree.to_wood(p.global_position)
	th = atan2(w.z, w.x)
	h = 0.0
	climbing = true
	falling = false
	block_y = -1.0
	p.climbing = true
	p.col_shape.disabled = true
	p.velocity = Vector3.ZERO
	if game.haul.carrying(): game.haul.drop_all()
	if p.tool == "climb": p.tool = "hands"; game.hud.set_tool("hands", game.muffs)
	Sfx.play("thud", 0.5, 1.4); Sfx.play("clank", 0.4, 1.2)
	_place(0.0)
	p.yaw = _face
	Ach.unlock("spurs_on")
	if line.is_empty(): game.hud.toast("Spiked in on your lanyard. With no climbing line set you won't get past the first limb.", 4.5)
	else: game.hud.toast("Spiked in and tied in. W climbs, A/D works round the trunk, F flips your lanyard past a limb.", 5.0)

func _get_off() -> void:
	var p: Player = game.player
	climbing = false
	p.climbing = false
	var out := tree.to_world(Vector3(cos(th) * (Wood.r_at(tree.T, 0.5) + 0.7), 0.0, sin(th) * (Wood.r_at(tree.T, 0.5) + 0.7)))
	p.teleport(Vector3(out.x, game.world.H(out.x, out.z) + 0.05, out.z))
	p.col_shape.disabled = false
	Sfx.play("thud", 0.5, 1.2)
	game.hud.toast("Feet on the ground.", 1.6)

## off the tree the hard way
func fall(why: String) -> void:
	if not climbing: return
	var p: Player = game.player
	climbing = false
	p.climbing = false
	falling = true
	falls += 1
	p.col_shape.disabled = false
	p.collision_mask = 1 | 4 | 8 | 16            # nothing in the crown to catch on
	p.velocity = Vector3(cos(th), 0, sin(th)) * 0.5
	Sfx.play("crack", 0.8, 1.3)
	game.hud.shout("WHOA!")
	game.hud.toast(why, 5.0)
	Ach.unlock("dont_look_down")

func _landed() -> void:
	falling = false
	var p: Player = game.player
	p.collision_mask = 1 | 4 | 8 | 16 | 32
	Sfx.play("thud", 1.0, 0.7)
	game.hud.toast("That'll leave a mark. $%d comes out of the pay for the doctor." % FALL_COST, 4.0)

# ---------------------------------------------------------------- in the tree
func harness() -> float:
	return h + HARNESS

func _place(_dt: float) -> void:
	var p: Player = game.player
	var r := Wood.r_at(tree.T, clampf(harness(), 0.0, tree.T.H))
	var off := r + STAND_OFF
	var wp := tree.to_world(Vector3(cos(th) * off, h, sin(th) * off))
	p.global_position = wp
	var axis := tree.to_world(Vector3(0, h, 0))
	var to := axis - wp; to.y = 0
	var face := atan2(-to.x, -to.z)
	# keep how far you'd turned from the trunk as you work your way round it, within a comfortable twist
	var rel := clampf(angle_difference(_face, p.yaw), -1.9, 1.9)
	_face = face
	p.yaw = face + rel

## the limbs your lanyard can't slide past: their heights on the trunk
func _limb_heights() -> Array:
	var out := []
	for id in tree.on_limbs: out.append(float(tree.T.limbs[id].y))
	return out

func top_limit() -> float:
	var lim := tree.top_y - 0.5
	if not line.is_empty(): lim = minf(lim, float(line.y) - 0.25)
	return lim

func physics_step(dt: float) -> void:
	var p: Player = game.player
	if falling:
		if p.is_on_floor(): _landed()
		return
	if not climbing: return
	# the tree came out from under you, or your line went
	if tree.state != "stand":
		fall("The tree went over with you on it."); return
	if not line.is_empty():
		var id := int(line.id)
		if not tree.on_limbs.has(id) or float(tree.on_limbs[id]) < 0.25 or tree.top_y < float(line.y) + 0.15:
			line = {}
			fall("Your climbing line came down out of the tree."); return
	var cap: bool = game.cap() or game.tests != null
	var up := 0.0; var side := 0.0
	if cap and not Player.input_off:
		up = Input.get_axis("move_back", "move_fwd")
		side = Input.get_axis("move_left", "move_right")
	var rappel := up < 0 and Input.is_action_pressed("run") and not line.is_empty()
	var sp := (UP_SPEED if up > 0 else (RAPPEL if rappel else DOWN_SPEED)) * absf(up)
	var hz := harness()
	var want := hz + signf(up) * sp * dt
	# a limb in the way of the lanyard
	block_y = -1.0
	if up > 0:
		for y in _limb_heights():
			if y > hz + 0.001 and y <= want + 0.03: want = minf(want, y - 0.03); block_y = y
		want = minf(want, top_limit())
	elif up < 0:
		for y in _limb_heights():
			if y < hz - 0.001 and y >= want - 0.03: want = maxf(want, y + 0.03); block_y = y
		want = maxf(want, HARNESS)
	if rappel: block_y = -1.0                          # on the line you're off the lanyard: straight down
	if rappel:
		want = maxf(hz - sp * dt, HARNESS)
	var moved := absf(want - hz)
	h = want - HARNESS
	# flipping the lanyard past the limb that's stopping it
	if block_y >= 0.0 and cap and Input.is_action_pressed("kick"):
		if line.is_empty():
			_tell("noline", "No second tie-in: you'd be clipped to nothing while you flip it. Set a climbing line first.", 4.0)
		else:
			flip_t += dt
			if flip_t > 0.9:
				flip_t = 0.0
				var dir := 1.0 if up >= 0 else -1.0
				if up == 0: dir = 1.0 if block_y > hz else -1.0
				h = block_y + dir * 0.05 - HARNESS
				block_y = -1.0
				Sfx.play("clank", 0.6, 1.1)
				Ach.add("flips")
	else:
		flip_t = 0.0
	th += side * ROUND_SPEED / maxf(0.25, Wood.r_at(tree.T, harness()) + STAND_OFF) * dt
	_place(dt)
	# spurs biting in on the way up and down
	_step_acc += moved
	if _step_acc > 0.32:
		_step_acc = 0.0
		Sfx.play("thud", 0.25, randf_range(1.5, 1.8))
	max_ft = maxf(max_ft, harness() * 3.28)
	if max_ft >= 50.0: Ach.unlock("fifty_feet")

func step(dt: float) -> void:
	if meter >= 0.0:
		meter_t += dt
		var u := fposmod(meter_t / THROW_T, 2.0)
		meter = u if u <= 1.0 else 2.0 - u
	bar.visible = meter >= 0.0 and not climbing
	bar.value = maxf(meter, 0.0)
	_draw_line()

## the climbing line: from the crotch down to your saddle (or hanging to the ground), and the lanyard
## round the stem at your waist
func _draw_line() -> void:
	line_im.clear_surfaces()
	if tree == null or tree.state != "stand": return
	var cam := get_viewport().get_camera_3d()
	var segs := []
	if not line.is_empty():
		var L: Dictionary = tree.T.limbs[int(line.id)]
		var top := tree.to_world(L.base + Vector3(0, 0.04, 0))
		var low: Vector3
		if climbing: low = game.player.global_position + Vector3(0, HARNESS, 0)
		else: low = tree.to_world(Vector3(0.45, 0.05, 0.25))
		segs.append([top, low])
	if climbing:
		var hz := harness()
		var r := Wood.r_at(tree.T, hz) + 0.02
		var prev := Vector3.ZERO
		for i in range(25):
			var a := TAU * i / 24.0
			var q := tree.to_world(Vector3(cos(a) * r, hz + 0.06, sin(a) * r))
			if i > 0: segs.append([prev, q])
			prev = q
	if segs.is_empty(): return
	line_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in segs:
		var a: Vector3 = s[0]; var b: Vector3 = s[1]
		var along := (b - a).normalized()
		var to_cam := ((cam.global_position - a).normalized() if cam else Vector3.UP)
		var side := along.cross(to_cam).normalized() * 0.011
		for q in [a - side, b - side, b + side, a - side, b + side, a + side]:
			line_im.surface_set_normal(Vector3.UP)
			line_im.surface_add_vertex(q)
	line_im.surface_end()

# ---------------------------------------------------------------- what's said, and what's on screen
func prompt() -> String:
	if climbing:
		if block_y >= 0.0:
			if line.is_empty(): return "A limb's stopping your lanyard. No climbing line, no getting past it"
			return "A limb's stopping your lanyard · hold [b]F[/b] to flip it past (you're on the climbing line)" + (" ·%s" % "▮".repeat(int(flip_t / 0.9 * 6)) if flip_t > 0 else "")
		if h <= 0.12: return "[b]E[/b] Step off · [b]W[/b] climb"
		if harness() >= top_limit() - 0.05 and not line.is_empty() and float(line.y) - 0.25 <= tree.top_y - 0.5: return "Up at your tie-in · this is as high as you go"
		return ""
	if game.player.tool == "climb" and tree.state == "stand":
		if near_trunk(): return "[b]E[/b] Spike in and climb" + ("" if not line.is_empty() else " (no climbing line set)")
		if meter >= 0.0: return "Let go to throw"
		return "Hold [b]left mouse[/b] and let go to throw a line into the crown" + (" · line set at %d ft" % roundi(float(line.y) * 3.28) if not line.is_empty() else "")
	return ""

func status() -> String:
	if not climbing: return ""
	return "Up %d ft · lanyard on · %s" % [roundi(harness() * 3.28), ("line tied in at %d ft" % roundi(float(line.y) * 3.28)) if not line.is_empty() else "no climbing line"]

# ---------------------------------------------------------------- cutting from up here
## would this cut take you out of the tree? "" if not, otherwise why
func danger(kind: String, y: float, id: int, t: float) -> String:
	if not climbing: return ""
	var hz := harness()
	if kind == "top":
		if not line.is_empty() and float(line.y) >= y - 0.05: return "Your climbing line was tied in above that cut. It went with the top, and so did you."
		if absf(y - hz) < 0.25: return "You cut through your own lanyard."
		if y < hz - 0.25: return "You cut the stem out from under your own spurs."
	elif kind == "slimb":
		if not line.is_empty() and int(line.id) == id and t < 0.35: return "That limb was carrying your climbing line."
	return ""

func guide_danger(g: Dictionary) -> String:
	match str(g.get("kind", "")):
		"top": return danger("top", float(g.get("y", 0.0)), -1, 0.0)
		"slimb": return danger("slimb", 0.0, int(g.get("id", -1)), float(g.get("t", 1.0)))
	return ""

## a cut through a limb or the stem up here is through: the wood comes off (on the host's game), and
## if it took one of your own lines with it, you come off too
func finish_crown_cut(c: Dictionary) -> void:
	var kind := str(c.kind)
	var why := ""
	if kind == "top": why = danger("top", float(c.y), -1, 0.0)
	else: why = danger("slimb", 0.0, int(c.id), float(c.t))
	var toward: Vector3 = game.player.fwd()
	if Net.is_guest():
		Net.ask("crown", [kind, float(c.get("y", 0.0)), int(c.get("id", -1)), float(c.get("t", 0.0)), toward])
		Sfx.play("crunch")
	else:
		cut_crown(kind, float(c.get("y", 0.0)), int(c.get("id", -1)), float(c.get("t", 0.0)), toward)
	if why != "": fall(why)
	game.update_objectives()

## the host's game takes the wood off (asked by its own climber, or a crew member's)
func cut_crown(kind: String, y: float, id: int, t: float, toward: Vector3) -> void:
	var p: WoodPiece = null
	if kind == "top":
		p = tree.top_out(y, toward)
		if p: Ach.add("tops")
	else:
		p = tree.cut_standing_limb(id, t)
	if p and game.lower: game.lower.on_crown_cut(kind, y, id, t, p)
