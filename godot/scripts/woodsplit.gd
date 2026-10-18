## Splitting firewood at the cabin. Pull a round out of Walter's trailer, set it on the chopping block,
## and split it with the axe: hold the left mouse to raise the axe (a ring fills round the crosshair,
## brightest in the sweet spot), let go to bring it down where you're looking. A good hit pops the
## round open; the halves fall apart on the block, you split those, and the finished sticks tumble onto
## the pile. Every eight sticks get tied into a bundle for the honour-box rack down the road: $5 each.
class_name WoodSplit
extends Node3D

const PILE_PER_BUNDLE := 8
const BUNDLE_PRICE := 5
const SWEET_A := 0.55            # seconds of wind-up where the swing is at its best
const SWEET_B := 0.9

var hub
var game
var block_c := Vector3.ZERO      # centre of the chopping block's top
var stand_p := Vector3.ZERO
var pile_c := Vector3.ZERO
var rack_p := Vector3.ZERO
var rack_yaw := 0.0
var rng := RandomNumberGenerator.new()
var active := false              # standing at the block, axe in hand
var carrying := false            # a round in your arms
var carry_round := {}
var carry_node: Node3D
var pieces: Array = []           # what's standing on the block
var pile: Array = []             # finished sticks waiting to be bundled
var bundles_node: Node3D
var axe: Node3D
var axe_stuck: Node3D            # the axe left in the block when you're not using it
var trailer_rounds: Node3D
var hold := -1.0                 # seconds the button's been held (-1 = not winding)
var swing := -1.0                # 0..1 through the downswing
var swing_hit := {}
var recoil := 0.0
var shake := 0.0
var streak := 0
var ui: CanvasLayer
var ring: Control
var lbl_main: Label
var lbl_pop: Label
var pop_t := 0.0
var t := 0.0

func setup(h, block_top: Vector3, rack_at: Vector3, rack_turn: float) -> void:
	hub = h; game = h.game
	rng.randomize()
	block_c = block_top
	pile_c = block_top + Vector3(1.25, 0, 0.9); pile_c.y = hub.world.H(pile_c.x, pile_c.z)
	rack_p = rack_at; rack_yaw = rack_turn
	_build_axe()
	_build_rack()
	_build_ui()
	refresh_trailer()

# ---------------------------------------------------------------- the round supply (saved)
static func rounds_left() -> int:
	return int(Career.load().get("rounds", 0))

static func bundles_sold() -> int:
	return int(Career.load().get("bundles", 0))

## the trailer shows what's left in it: rounds stood up in the bed, tarp off
func refresh_trailer() -> void:
	var tr: Trailer = hub.get_node_or_null("Trailer")
	if tr == null: return
	if trailer_rounds: trailer_rounds.queue_free()
	var n := rounds_left()
	tr.tarp.visible = n == 0
	trailer_rounds = Node3D.new(); tr.add_child(trailer_rounds)
	trailer_rounds.position = Vector3(0, -Trailer.SINK, 0)
	var r := RandomNumberGenerator.new(); r.seed = 17
	var k := 0
	for iz in range(3):
		for ix in range(3):
			if k >= mini(n, 9): break
			var rr := r.randf_range(0.17, 0.24)
			var mi := _slice_mesh(0.0, TAU, rr, 0.4, false, -1.0).instance()
			mi.position = Vector3(-0.55 + ix * 0.55 + r.randf_range(-0.05, 0.05), 0.8, Trailer.Z1 - 0.6 - iz * 0.6)
			trailer_rounds.add_child(mi)
			k += 1

## a random round: size, a knot now and then, maybe a seasoning check already running across it
func _new_round() -> Dictionary:
	var R := rng.randf_range(0.14, 0.27)
	var knot := rng.randf() < 0.22
	var check := rng.randf() * PI if rng.randf() < 0.55 else -1.0
	return {R = R, h = rng.randf_range(0.36, 0.46), knot = knot, check = check, shade = rng.randf_range(0.88, 1.08)}

# ---------------------------------------------------------------- models
## a piece of a round: a slice of a cylinder from angle a0 to a1 (the whole round is 0..TAU), end grain
## with growth rings on top and bottom, bark round the outside, fresh pale wood on the split faces
static func _slice_mesh(a0: float, a1: float, R: float, h: float, knot: bool, check: float, shade := 1.0) -> MeshBuilder:
	var mb := MeshBuilder.new()
	var full := a1 - a0 > TAU - 0.01
	var seg := maxi(4, int(ceil((a1 - a0) / TAU * 22.0)))
	var bark := Color("#5a4a3c") * shade; var bark2 := Color("#4a3c30") * shade
	var fresh := Color("#e3c592") * shade; var fresh2 := Color("#d4b07a") * shade
	var rings := 5
	for side: float in [1.0, -1.0]:
		var y := h if side > 0 else 0.0
		var prev := []
		for ri in range(rings + 1):
			var rr := R * float(ri) / rings
			var row := []
			for k in range(seg + 1):
				var a := lerpf(a0, a1, float(k) / seg)
				var c := Color("#d8b47e").lerp(Color("#b88a56"), float(ri % 2) * 0.55 + float(ri) / rings * 0.3) * shade
				if ri == rings: c = bark2
				if knot and Vector2(cos(a) * rr - R * 0.35, sin(a) * rr).length() < R * 0.13: c = Color("#5a3a22")
				row.append(mb.v(Vector3(cos(a) * rr, y, sin(a) * rr), Vector3(0, side, 0), c))
			if ri > 0:
				for k in range(seg):
					if side > 0: mb.quad(prev[k], prev[k + 1], row[k + 1], row[k])
					else: mb.quad(prev[k], row[k], row[k + 1], prev[k + 1])
			prev = row
	# bark round the outside
	for k in range(seg):
		var a := lerpf(a0, a1, float(k) / seg); var b := lerpf(a0, a1, float(k + 1) / seg)
		var na := Vector3(cos(a), 0, sin(a)); var nb := Vector3(cos(b), 0, sin(b))
		var c := bark if k % 2 else bark2
		var i0 := mb.v(na * R * 1.02, na, c); var i1 := mb.v(nb * R * 1.02, nb, c)
		var i2 := mb.v(nb * R * 1.02 + Vector3(0, h, 0), nb, c); var i3 := mb.v(na * R * 1.02 + Vector3(0, h, 0), na, c)
		mb.quad(i0, i3, i2, i1)
	# the split faces
	if not full:
		for e in [[a0, 1.0], [a1, -1.0]]:
			var a: float = e[0]
			var d := Vector3(cos(a), 0, sin(a))
			var n := Vector3(-sin(a), 0, cos(a)) * -float(e[1])
			var i0 := mb.v(Vector3.ZERO, n, fresh2); var i1 := mb.v(d * R, n, fresh)
			var i2 := mb.v(d * R + Vector3(0, h, 0), n, fresh); var i3 := mb.v(Vector3(0, h, 0), n, fresh2)
			if e[1] > 0: mb.quad(i0, i1, i2, i3)
			else: mb.quad(i0, i3, i2, i1)
	# a seasoning check: a dark crack across the top
	if full and check >= 0.0:
		var d := Vector3(cos(check), 0, sin(check))
		var w := Vector3(-d.z, 0, d.x) * 0.006
		var p0 := -d * R * 0.75 + Vector3(0, h + 0.003, 0); var p1 := d * R * 0.9 + Vector3(0, h + 0.003, 0)
		var dc := Color("#2a1e14")
		var i0 := mb.v(p0 - w, Vector3.UP, dc); var i1 := mb.v(p1 - w, Vector3.UP, dc); var i2 := mb.v(p1 + w, Vector3.UP, dc); var i3 := mb.v(p0 + w, Vector3.UP, dc)
		mb.quad(i0, i3, i2, i1)
	return mb

func _build_axe() -> void:
	var mb := MeshBuilder.new()
	var hick := Color("#c09a62"); var steel := Color("#5c6168"); var edge := Color("#c8ccd2")
	# handle along -Z, slight curve and a swell at the end
	mb.tube(Vector3(0, 0, 0.02), Vector3(0, 0.0, -0.42), 0.019, 0.016, hick, 7, true)
	mb.tube(Vector3(0, 0, -0.42), Vector3(0, -0.015, -0.8), 0.016, 0.018, hick, 7, true)
	mb.sphere(0, 0, 0.03, 0.024, 0.026, 0.03, hick * 0.9, 8, 5)
	# the head: poll behind (+Y), the bit and its bright edge forward (-Y)
	mb.bevel_box(0, 0.02, -0.8, 0.045, 0.07, 0.07, steel, 0.012)
	var p := [Vector3(0, -0.02, -0.765), Vector3(0, -0.02, -0.835), Vector3(0, -0.15, -0.87), Vector3(0, -0.15, -0.73)]
	for sx: float in [-1.0, 1.0]:
		var q: Array = []
		for v: Vector3 in p: q.append(v + Vector3(sx * (0.02 if v.y > -0.05 else 0.004), 0, 0))
		WorldGen._face_out(mb, q, Vector3(sx, 0, 0), steel)
	mb.box(0, -0.152, -0.8, 0.008, 0.012, 0.15, edge)
	mb.box(0, -0.09, -0.8, 0.012, 0.11, 0.075, steel * 0.9)
	axe = mb.instance()
	axe.visible = false
	axe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hub.player.hands.add_child(axe)
	axe_stuck = mb.instance()
	hub.add_child(axe_stuck)
	_stick_axe_in_block()

func _stick_axe_in_block() -> void:
	axe_stuck.visible = true
	# the bit buried in the block top, the handle sloping up and out toward you
	var zb := Vector3(0.35, 0.85, -0.38).normalized()
	var yb := -(Vector3.DOWN - zb * zb.dot(Vector3.DOWN)).normalized()
	var xb := yb.cross(zb).normalized()
	var B := Basis(xb, yb, zb)
	var target := block_c + Vector3(0.05, 0.03, 0.04)
	axe_stuck.global_transform = Transform3D(B, target - B * Vector3(0, -0.15, -0.8))

## the firewood stand at the end of the track, like the ones you see along back roads: a cedar box on
## skids with slatted sides and back, a shelf, a little shed roof with green trim, "$5.00 BUNDLE" painted
## across the header, a black honour box on the post, and a cleared gravel pad out front. The bundles
## you've tied sit on it in red mesh bags, beside a neat stack of loose splits.
const STAND_W := 1.5
const STAND_D := 0.72
func _build_rack() -> void:
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new(); r.seed = 77
	var cedar := Color("#c08a56"); var cedar2 := Color("#a9743f"); var trim := Color("#3d7f72")
	var hw := STAND_W / 2; var hd := STAND_D / 2
	mb.push(Transform3D(Basis(Vector3.UP, rack_yaw), rack_p))
	# the gravel pad: a flat grey bed, and plenty of little stones scattered over it
	mb.cyl(0, -0.02, -0.6, 1.9, 1.95, 0.05, Color("#8e8c86"), 22, true)
	for k in range(140):
		var a := r.randf() * TAU; var d := sqrt(r.randf()) * 1.85
		var g := Color("#b8b6ae").lerp(Color("#6e6c66"), r.randf())
		mb.box(cos(a) * d, 0.035, -0.6 + sin(a) * d, r.randf_range(0.03, 0.06), 0.02, r.randf_range(0.03, 0.06), g)
	# skids, deck and corner posts
	for sx: float in [-1.0, 1.0]: mb.box(sx * (hw - 0.1), 0.08, 0, 0.1, 0.12, STAND_D + 0.1, cedar2)
	for k in range(5): mb.box(0, 0.19, -hd + 0.07 + k * (STAND_D - 0.14) / 4.0, STAND_W, 0.035, 0.13, cedar.lerp(cedar2, r.randf() * 0.5))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]: mb.box(sx * (hw - 0.04), 0.95, sz * (hd - 0.04), 0.08, 1.6, 0.08, cedar2)
	# slatted back and sides: boards with a finger's gap between them
	var y := 0.24
	while y < 1.55:
		var c := cedar.lerp(cedar2, r.randf() * 0.6)
		mb.box(0, y + 0.06, hd - 0.02, STAND_W - 0.04, 0.12, 0.025, c)
		for sx: float in [-1.0, 1.0]: mb.box(sx * (hw - 0.02), y + 0.06, 0, 0.025, 0.12, STAND_D - 0.04, c)
		y += 0.155
	# the shelf, on cleats
	mb.box(0, 0.86, 0.02, STAND_W - 0.08, 0.035, STAND_D - 0.1, cedar)
	for sx: float in [-1.0, 1.0]: mb.box(sx * (hw - 0.07), 0.83, 0.02, 0.04, 0.04, STAND_D - 0.12, cedar2)
	# the header board across the front, and the shed roof sloping to the back with green trim
	mb.box(0, 1.5, -hd - 0.01, STAND_W + 0.06, 0.3, 0.04, cedar)
	var rf := 0.22                                       # roof fall, high at the front down to the back
	var roof_b := Basis(Vector3.RIGHT, atan2(rf, STAND_D + 0.3))
	mb.push(Transform3D(roof_b, Vector3(0, 1.78 - rf / 2, 0)))
	for k in range(7): mb.box(-hw - 0.08 + (k + 0.5) * (STAND_W + 0.16) / 7.0, 0, 0, (STAND_W + 0.16) / 7.0 - 0.01, 0.03, STAND_D + 0.32, cedar.lerp(cedar2, r.randf()))
	mb.box(0, 0.03, -(STAND_D + 0.32) / 2, STAND_W + 0.2, 0.05, 0.05, trim)
	mb.box(0, 0.03, (STAND_D + 0.32) / 2, STAND_W + 0.2, 0.05, 0.05, trim)
	for sx: float in [-1.0, 1.0]: mb.box(sx * (hw + 0.1), 0.03, 0, 0.05, 0.05, STAND_D + 0.36, trim)
	mb.pop()
	# the honour box on the left front post: black steel, a slot, a padlock
	mb.box(-hw - 0.14, 0.45, -hd + 0.12, 0.08, 0.9, 0.08, cedar2)                   # its post
	mb.box(-hw - 0.08, 0.86, -hd + 0.02, 0.18, 0.06, 0.05, cedar2)                  # a cleat to the stand
	mb.box(-hw - 0.14, 1.0, -hd + 0.02, 0.2, 0.26, 0.18, Color("#1c1d1f"))
	mb.box(-hw - 0.14, 1.14, -hd + 0.02, 0.22, 0.03, 0.2, Color("#26282a"))
	mb.box(-hw - 0.14, 1.11, -hd - 0.075, 0.1, 0.012, 0.01, Color("#050505"))
	mb.box(-hw - 0.14, 0.92, -hd - 0.08, 0.035, 0.045, 0.02, Color("#b89a40"))
	# a little "HONOR SYSTEM" sign on a stake out front
	mb.box(hw + 0.35, 0.35, -hd - 0.45, 0.04, 0.7, 0.04, cedar2)
	mb.box(hw + 0.35, 0.72, -hd - 0.47, 0.42, 0.28, 0.02, Color("#f2efe6"))
	# loose splits stacked neatly on the deck, right-hand side: triangular pie pieces, bark side out
	for row in range(5):
		for k in range(4 - (row / 2)):
			var px := hw - 0.16 - k * 0.15 - (row % 2) * 0.07
			var py := 0.27 + row * 0.12
			mb.push(Transform3D(Basis(Vector3.RIGHT, PI / 2) * Basis(Vector3.UP, (row + k) * 1.7), Vector3(px, py, 0.02)))
			_split_piece(mb, r)
			mb.pop()
	mb.pop()
	var mi := mb.instance(); mi.name = "Rack"; hub.add_child(mi)
	var B := Basis(Vector3.UP, rack_yaw)
	var lbl := Label3D.new(); lbl.text = "$5.00 BUNDLE"; lbl.font_size = 40; lbl.pixel_size = 0.0042
	lbl.modulate = Color("#b8261c"); lbl.outline_size = 0
	lbl.global_transform = Transform3D(B * Basis(Vector3.UP, PI), rack_p + B * Vector3(0, 1.5, -hd - 0.04))
	hub.add_child(lbl)
	var lb2 := Label3D.new(); lb2.text = "HONOR\nSYSTEM\nTHANK YOU"; lb2.font_size = 26; lb2.pixel_size = 0.0035
	lb2.modulate = Color("#2a2a2a"); lb2.outline_size = 0
	lb2.global_transform = Transform3D(B * Basis(Vector3.UP, PI), rack_p + B * Vector3(hw + 0.35, 0.72, -hd - 0.485))
	hub.add_child(lb2)
	bundles_node = Node3D.new(); hub.add_child(bundles_node)
	_refresh_rack()

## one split: a pie-shaped wedge of a round, 0.32 long along y, bark on the curved side
static func _split_piece(mb: MeshBuilder, r: RandomNumberGenerator) -> void:
	var L := 0.32; var R := r.randf_range(0.075, 0.095); var a := r.randf_range(0.85, 1.15)
	var wood := Color("#d8b884").lerp(Color("#c49a62"), r.randf()); var bark := Color("#5e4a38").lerp(Color("#4a3a2c"), r.randf())
	var pts := [Vector3.ZERO]
	for k in range(4):
		var t := -a / 2 + a * k / 3.0
		pts.append(Vector3(sin(t) * R, 0, cos(t) * R))
	for yy: float in [-L / 2, L / 2]:
		var ring := []
		for p in pts: ring.append((p as Vector3) + Vector3(0, yy, 0))
		var f := ring.duplicate()
		if yy > 0: f.reverse()
		mb.face(f, wood.lerp(Color("#e8d0a0"), 0.3))
	for k in range(pts.size()):
		var p0: Vector3 = pts[k]; var p1: Vector3 = pts[(k + 1) % pts.size()]
		var c := bark if k >= 1 and k < pts.size() - 1 else wood
		mb.face([p0 + Vector3(0, -L / 2, 0), p1 + Vector3(0, -L / 2, 0), p1 + Vector3(0, L / 2, 0), p0 + Vector3(0, L / 2, 0)], c)

## a bundle: a red mesh firewood bag stuffed with splits, the top gathered and tied, a paper tag
static func _bundle_mesh() -> MeshBuilder:
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new(); r.seed = 3
	var red := Color("#c0362c"); var dark := Color("#7a1c16")
	# the sack, lying on its side along x, slightly flattened where it sits
	mb.sphere(0, 0.13, 0, 0.22, 0.13, 0.15, red, 16, 9)
	# a couple of split ends pressing the mesh out at the bottom end
	for k in range(3):
		var a := -0.6 + k * 0.6
		mb.box(-0.205, 0.13 + sin(a) * 0.05, cos(a) * 0.06 - 0.03, 0.012, 0.045, 0.045, Color("#c49a62"))
	# the mesh: a diamond weave of dark strands wrapped round it
	for k in range(10):
		var ph := TAU * k / 10.0
		var prev := Vector3.ZERO
		for i in range(9):
			var t := -1.0 + 2.0 * i / 8.0
			var ang := ph + t * 1.1
			var rr := sqrt(maxf(0.0, 1.0 - t * t))
			var q := Vector3(t * 0.222, 0.13 + sin(ang) * 0.132 * rr, cos(ang) * 0.152 * rr)
			if i > 0: mb.tube(prev, q, 0.0045, 0.0045, dark, 3)
			prev = q
	# the gathered neck, the twine tie, and a paper price tag
	mb.tube(Vector3(0.2, 0.14, 0), Vector3(0.3, 0.16, 0.0), 0.035, 0.016, dark.lerp(red, 0.5), 6)
	mb.cyl(0.25, 0.105, 0, 0.026, 0.026, 0.035, Color("#e8d890"), 8, false)
	mb.box(0.31, 0.12, 0.03, 0.005, 0.06, 0.04, Color("#efe6cc"))
	return mb

func _refresh_rack() -> void:
	for c in bundles_node.get_children(): c.queue_free()
	var n := mini(bundles_sold(), 12)
	var bm := _bundle_mesh().commit()
	var B := Basis(Vector3.UP, rack_yaw)
	for k in range(n):
		var mi := MeshInstance3D.new(); mi.mesh = bm; mi.material_override = Mats.vcol
		# the shelf first (four across, two deep), then the deck to the left of the loose splits
		var local: Vector3
		if k < 8: local = Vector3(-0.5 + (k % 4) * 0.33, 0.875, -0.12 + (k / 4) * 0.26)
		else: local = Vector3(-0.5 + (k - 8) % 2 * 0.36, 0.21, -0.12 + ((k - 8) / 2) * 0.28)
		mi.global_transform = Transform3D(B * Basis(Vector3.UP, 0.12 * ((k % 3) - 1)), rack_p + B * local)
		bundles_node.add_child(mi)

func _build_ui() -> void:
	ui = CanvasLayer.new(); ui.layer = 6; add_child(ui)
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	ring = PowerRing.new(); ring.split = self
	ring.set_anchors_preset(Control.PRESET_CENTER); ring.size = Vector2(120, 120); ring.position = Vector2(-60, -60)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ring)
	lbl_main = Label.new(); lbl_main.add_theme_font_size_override("font_size", 17)
	lbl_main.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85)); lbl_main.add_theme_constant_override("outline_size", 6)
	lbl_main.set_anchors_preset(Control.PRESET_CENTER_BOTTOM); lbl_main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_main.offset_left = -360; lbl_main.offset_right = 360; lbl_main.offset_top = -120; lbl_main.offset_bottom = -70
	root.add_child(lbl_main)
	lbl_pop = Label.new(); lbl_pop.add_theme_font_size_override("font_size", 30)
	lbl_pop.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85)); lbl_pop.add_theme_constant_override("outline_size", 8)
	lbl_pop.set_anchors_preset(Control.PRESET_CENTER); lbl_pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_pop.offset_left = -300; lbl_pop.offset_right = 300; lbl_pop.offset_top = -150; lbl_pop.offset_bottom = -110
	root.add_child(lbl_pop)
	ui.visible = false

## the wind-up ring round the crosshair: fills as you raise the axe, the sweet spot marked in gold
class PowerRing extends Control:
	var split
	func _draw() -> void:
		var c := size / 2.0
		var r := 40.0
		var full := TAU
		var a0 := -PI / 2
		draw_arc(c, r, 0, TAU, 48, Color(0, 0, 0, 0.35), 7.0, true)
		var sa: float = split.SWEET_A / 1.2 * full; var sb: float = split.SWEET_B / 1.2 * full
		draw_arc(c, r, a0 + sa, a0 + sb, 24, Color(1.0, 0.82, 0.3, 0.55), 7.0, true)
		if split.hold >= 0.0:
			var k := clampf(split.hold / 1.2, 0.0, 1.0)
			var col := Color(1.0, 0.85, 0.3) if split.in_sweet() else Color(1, 1, 1, 0.9)
			if split.hold > split.SWEET_B: col = Color(1.0, 0.5, 0.35)
			draw_arc(c, r, a0, a0 + k * full, 48, col, 5.0, true)

func in_sweet() -> bool:
	return hold >= SWEET_A and hold <= SWEET_B

# ---------------------------------------------------------------- what you can do
func can_take_round() -> bool:
	return not carrying and not active and rounds_left() > 0 and pieces.is_empty()

func take_round() -> void:
	var c := Career.load()
	if int(c.get("rounds", 0)) <= 0: game.hud.toast("The trailer's empty. More wood comes with the next big job.", 3.0); return
	c.rounds = int(c.rounds) - 1; Career.save(c)
	carry_round = _new_round()
	carrying = true
	carry_node = _slice_mesh(0.0, TAU, carry_round.R, carry_round.h, carry_round.knot, carry_round.check, carry_round.shade).instance()
	carry_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.player.hands.add_child(carry_node)
	carry_node.position = Vector3(0, -0.66, -0.62)
	Sfx.play("pick"); Sfx.play("drop", 0.5, 0.7)
	refresh_trailer()
	game.hud.toast("A %s round%s. Carry it to the chopping block." % ["big" if carry_round.R > 0.23 else ("small" if carry_round.R < 0.17 else "good"), ", knotty" if carry_round.knot else ""], 2.5)

## E at the block: set your round on it (and pick up the axe), or pick the axe back up
func use_block() -> void:
	if carrying:
		carrying = false
		carry_node.queue_free(); carry_node = null
		var rd := carry_round
		_add_piece({a0 = 0.0, a1 = TAU, R = rd.R, h = rd.h, knot = rd.knot, check = rd.check, shade = rd.shade, dmg = 0.0, crack = -1.0, off = Vector2.ZERO, lean = 0.0})
		Sfx.play("thud", 0.6, 1.2)
	if pieces.is_empty():
		game.hud.toast("Grab a round from the trailer first.", 2.0); return
	_start_chopping()

func _start_chopping() -> void:
	active = true
	ui.visible = true
	axe_stuck.visible = false
	axe.visible = true
	hold = -1.0; swing = -1.0
	var p: Player = game.player
	var to := p.global_position - block_c; to.y = 0
	if to.length() < 0.1: to = Vector3(0, 0, -1)
	to = to.normalized()
	stand_p = block_c + to * 0.95
	p.teleport(Vector3(stand_p.x, hub.world.H(stand_p.x, stand_p.z) + 0.05, stand_p.z))
	p.yaw = atan2(to.x, to.z)
	p.pitch = -0.62
	p.speed_mult = 0.0
	Sfx.play("pick", 0.6, 0.8)

func stop_chopping() -> void:
	active = false
	ui.visible = false
	axe.visible = false
	_stick_axe_in_block()
	game.player.speed_mult = 1.0
	hold = -1.0; swing = -1.0
	game.player.cam.h_offset = 0.0; game.player.cam.v_offset = 0.0

func press() -> void:
	if not active or swing >= 0.0 or recoil > 0.0: return
	hold = 0.0
	Sfx.play("pull", 0.25, 1.6)

func release() -> void:
	if not active or hold < 0.0: return
	var power := _power(hold)
	var perfect := in_sweet()
	hold = -1.0
	swing = 0.0
	swing_hit = _aim_hit()
	swing_hit.power = power; swing_hit.perfect = perfect
	Sfx.play("whoosh", 0.5 + power * 0.4, 0.9 + power * 0.3)

func _power(hld: float) -> float:
	if hld < SWEET_A: return lerpf(0.25, 0.85, hld / SWEET_A)
	if hld <= SWEET_B: return 1.0
	return maxf(0.55, 1.0 - (hld - SWEET_B) * 0.6)        # held too long: the arms tire

# ---------------------------------------------------------------- pieces on the block
func _add_piece(pc: Dictionary) -> void:
	var node := Node3D.new()
	hub.add_child(node)
	var mi := _slice_mesh(pc.a0, pc.a1, pc.R, pc.h, pc.knot, pc.check if pc.a1 - pc.a0 > TAU - 0.01 else -1.0, pc.shade).instance()
	node.add_child(mi)
	pc.node = node
	pc.crack_node = null
	pieces.append(pc)
	_place(pc, 0.0)

func _place(pc: Dictionary, k: float) -> void:
	var mid: float = (pc.a0 + pc.a1) / 2.0
	var out := Vector3(cos(mid), 0, sin(mid))
	var axis := Vector3.UP.cross(out).normalized() if out.length() > 0.01 else Vector3.RIGHT
	var off: Vector2 = pc.off
	var b := Basis(axis, -pc.lean * k) if pc.lean != 0.0 else Basis()
	pc.node.global_transform = Transform3D(b, block_c + Vector3(off.x, 0, off.y) * k)

## where the crosshair meets the top of what's on the block
func _aim_hit() -> Dictionary:
	var cam: Camera3D = game.player.cam
	var o := cam.global_position; var d := -cam.global_transform.basis.z
	var best := {}
	for pc in pieces:
		var top: float = block_c.y + pc.h
		if absf(d.y) < 0.05: continue
		var tt := (top - o.y) / d.y
		if tt < 0: continue
		var P := o + d * tt
		var off: Vector2 = pc.off
		var l := Vector2(P.x - block_c.x - off.x, P.z - block_c.z - off.y)
		var r := l.length()
		if r > pc.R * 1.08 + 0.03: continue
		var a := atan2(l.y, l.x)
		var full: bool = pc.a1 - pc.a0 > TAU - 0.01
		if not full:
			var span: float = pc.a1 - pc.a0
			var rel := fposmod(a - pc.a0, TAU)
			if rel > span + 0.15 and rel < TAU - 0.15: continue
			a = pc.a0 + clampf(rel if rel <= span + 0.15 else rel - TAU, 0.0, span)
		var score: float = r / pc.R
		if best.is_empty() or score < best.score: best = {pc = pc, p = P, l = l, a = a, r = r, score = score}
	if best.is_empty():
		var tt2 := (block_c.y - o.y) / minf(d.y, -0.05)
		best = {p = o + d * tt2}
	return best

func _toughness(pc: Dictionary) -> float:
	var frac: float = (pc.a1 - pc.a0) / TAU
	return pow(pc.R / 0.2, 1.3) * (1.7 if pc.knot else 1.0) * (0.45 + 0.55 * sqrt(frac))

func _finished(pc: Dictionary) -> bool:
	var span: float = pc.a1 - pc.a0
	return span < TAU - 0.01 and (0.5 * span * pc.R * pc.R <= 0.026 or span < 0.75)

## the axe arrives
func _impact() -> void:
	var h := swing_hit
	if not h.has("pc"):
		# missed the wood: the blade bites the block
		Sfx.play("thud", 0.7, 1.4); Sfx.play("clank", 0.25, 0.7)
		game.saw._emit(h.p, Vector3(0, 1.2, 0), 4, Color("#8a7458"), 1.4, 0.02)
		_shake(0.5); _popup("Missed!", Color(1, 0.6, 0.5)); streak = 0
		recoil = 0.35
		return
	var pc: Dictionary = h.pc
	var full: bool = pc.a1 - pc.a0 > TAU - 0.01
	# along the grain: on a whole round the axe drives a split across it in line with your swing (or
	# into an existing check if you hit it); on a piece it splits from the heart out through where you hit
	var cam_f: Vector3 = -game.player.cam.global_transform.basis.z; cam_f.y = 0; cam_f = cam_f.normalized()
	var split_a: float
	if pc.crack >= 0.0: split_a = pc.crack
	elif full:
		split_a = atan2(cam_f.z, cam_f.x)
		if pc.check >= 0.0:
			var dline := absf(h.l.dot(Vector2(-sin(pc.check), cos(pc.check))))
			if dline < 0.06: split_a = pc.check
	else:
		var span: float = pc.a1 - pc.a0
		split_a = clampf(h.a, pc.a0 + span * 0.3, pc.a1 - span * 0.3)
	# how good a hit: power, how central (on a round) or how close to the crack, a knot fights back
	var acc := 1.0
	if full: acc = lerpf(1.0, 0.55, clampf((h.r / pc.R - 0.3) / 0.7, 0.0, 1.0))
	if pc.crack >= 0.0:
		var dir := Vector2(cos(pc.crack), sin(pc.crack))
		acc *= 1.15 if absf(h.l.dot(Vector2(-dir.y, dir.x))) < 0.05 else 0.7
	elif full and pc.check >= 0.0 and split_a == pc.check: acc *= 1.4
	var dmg: float = h.power * acc * (1.35 if h.perfect else 1.0)
	pc.dmg += dmg
	pc.crack = split_a
	var chips_c := Color("#e0c48e")
	game.saw._emit(h.p + Vector3(0, 0.02, 0), Vector3(0, 1.6, 0) - cam_f * 0.8, int(4 + dmg * 5), chips_c, 2.2, 0.022)
	if pc.dmg >= _toughness(pc):
		_split(pc, split_a, h)
	else:
		# stuck: the axe bites in and a crack opens across the top
		Sfx.play("thud", 0.55 + dmg * 0.3, 1.5); Sfx.play("crunch", 0.35, 1.3)
		_draw_crack(pc, clampf(pc.dmg / _toughness(pc), 0.15, 0.95))
		_shake(0.35 + dmg * 0.3)
		_popup("Stuck!" if dmg < 0.6 else "Almost...", Color(1, 0.85, 0.55))
		recoil = 0.32
		streak = 0

func _draw_crack(pc: Dictionary, k: float) -> void:
	if pc.crack_node: pc.crack_node.queue_free()
	var mb := MeshBuilder.new()
	var d := Vector3(cos(pc.crack), 0, sin(pc.crack))
	var full: bool = pc.a1 - pc.a0 > TAU - 0.01
	var w := Vector3(-d.z, 0, d.x) * (0.004 + 0.01 * k)
	var a: Vector3 = -d * pc.R * k if full else Vector3.ZERO
	var b: Vector3 = d * pc.R * (k if full else 1.0) * (1.0 if full else k)
	var y: float = pc.h + 0.004
	var c := Color("#1e140c")
	var i0 := mb.v(a - w + Vector3(0, y, 0), Vector3.UP, c); var i1 := mb.v(b - w + Vector3(0, y, 0), Vector3.UP, c)
	var i2 := mb.v(b + w + Vector3(0, y, 0), Vector3.UP, c); var i3 := mb.v(a + w + Vector3(0, y, 0), Vector3.UP, c)
	mb.quad(i0, i3, i2, i1)
	var mi := mb.instance(); pc.node.add_child(mi); pc.crack_node = mi

## it pops open: two halves fall apart, and any that are small enough fly off onto the pile
func _split(pc: Dictionary, sa: float, h: Dictionary) -> void:
	streak += 1
	Sfx.play("crack", 0.9, randf_range(1.05, 1.25)); Sfx.play("thud", 0.8, 1.15); Sfx.play("crunch", 0.6, 0.9)
	if h.perfect: Sfx.play("ding", 0.35, 1.5)
	_hitstop(0.09 if h.perfect else 0.06)
	_shake(0.9 if h.perfect else 0.65)
	var msgs := ["Clean split!", "Beautiful!", "Like butter!", "Textbook!"] if h.perfect else ["Split!", "Nice!", "Got it!"]
	if streak >= 3: msgs = ["%d in a row!" % streak]
	_popup(msgs[randi() % msgs.size()], Color(1.0, 0.86, 0.35) if h.perfect else Color(0.85, 1.0, 0.7))
	pieces.erase(pc)
	pc.node.queue_free()
	var full: bool = pc.a1 - pc.a0 > TAU - 0.01
	var halves: Array
	if full: halves = [[sa, sa + PI], [sa + PI, sa + TAU]]
	else: halves = [[pc.a0, sa], [sa, pc.a1]]
	game.saw._emit(h.p + Vector3(0, 0.05, 0), Vector3(0, 2.4, 0), 9, Color("#ead2a0"), 3.0, 0.02)
	for hv in halves:
		var mid: float = (hv[0] + hv[1]) / 2.0
		var out := Vector2(cos(mid), sin(mid))
		var np := {a0 = hv[0], a1 = hv[1], R = pc.R, h = pc.h, knot = pc.knot and randf() < 0.5, check = -1.0, shade = pc.shade,
			dmg = 0.0, crack = -1.0, off = pc.off + out * randf_range(0.04, 0.07), lean = randf_range(0.08, 0.2)}
		if _finished(np): _fly_to_pile(np, out)
		else:
			_add_piece(np)
			# fall open: slide apart and lean outward
			var tw := create_tween()
			tw.tween_method(func(k: float): if is_instance_valid(np.node): _place(np, k), 0.0, 1.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if pieces.is_empty():
		get_tree().create_timer(0.9).timeout.connect(func():
			if active and pieces.is_empty():
				lbl_main.text = "That round's done. E to step away, then grab another from the trailer (%d left)." % rounds_left())

## a finished stick tumbles off the block onto the pile beside it
func _fly_to_pile(np: Dictionary, out: Vector2) -> void:
	var node := Node3D.new(); hub.add_child(node)
	var mi := _slice_mesh(np.a0, np.a1, np.R, np.h, np.knot, -1.0, np.shade).instance()
	node.add_child(mi)
	var start := block_c + Vector3(out.x, 0, out.y) * 0.05
	var k := pile.size()
	var spot := pile_c + Vector3(randf_range(-0.35, 0.35), 0.06 + (k % 4) * 0.05, randf_range(-0.3, 0.3))
	spot.y = hub.world.H(spot.x, spot.z) + 0.03 + (k % 4) * 0.06
	var lay := Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, PI / 2)
	var spin := Vector3(randf_range(-9, 9), randf_range(-4, 4), randf_range(-9, 9))
	var dur := randf_range(0.45, 0.6)
	var tw := create_tween()
	tw.tween_method(func(u: float):
		if not is_instance_valid(node): return
		var p := start.lerp(spot, u) + Vector3(0, sin(u * PI) * 0.55, 0)
		var b := Basis(Quaternion(Basis()).slerp(Quaternion(lay), u)) * Basis.from_euler(spin * (1.0 - u) * u * 0.6)
		node.global_transform = Transform3D(b, p), 0.0, 1.0, dur)
	tw.tween_callback(func(): Sfx.play("drop", 0.45, randf_range(1.2, 1.5)))
	pile.append(node)
	if pile.size() >= PILE_PER_BUNDLE: get_tree().create_timer(dur + 0.25).timeout.connect(_tie_bundle)

## eight sticks: tie them up with twine, off to the rack by the road, five bucks in the honour box
func _tie_bundle() -> void:
	if pile.size() < PILE_PER_BUNDLE: return
	var take := pile.slice(0, PILE_PER_BUNDLE)
	pile = pile.slice(PILE_PER_BUNDLE)
	for k in range(take.size()):
		var n: Node3D = take[k]
		var tw := create_tween()
		tw.tween_interval(k * 0.04)
		tw.tween_property(n, "global_position", pile_c + Vector3(0, 0.35, 0), 0.25).set_ease(Tween.EASE_IN)
		tw.tween_property(n, "scale", Vector3.ONE * 0.05, 0.12)
		tw.tween_callback(n.queue_free)
	var c := Career.load()
	c.money = int(c.money) + BUNDLE_PRICE
	c.bundles = int(c.get("bundles", 0)) + 1
	Career.save(c)
	game.money = int(c.money)
	Sfx.play("cash", 0.8)
	_popup("Bundle tied! +$%d" % BUNDLE_PRICE, Color(0.55, 1.0, 0.55))
	game.hud.toast("Bundle #%d is out on the rack by the road. +$%d" % [int(c.bundles), BUNDLE_PRICE], 2.5)
	_refresh_rack()

# ---------------------------------------------------------------- feel
func _hitstop(dur: float) -> void:
	Engine.time_scale = 0.05
	get_tree().create_timer(dur, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)

func _shake(k: float) -> void:
	shake = maxf(shake, k)

func _popup(text: String, col: Color) -> void:
	lbl_pop.text = text
	lbl_pop.add_theme_color_override("font_color", col)
	lbl_pop.modulate.a = 1.0
	lbl_pop.scale = Vector2(1.25, 1.25)
	lbl_pop.pivot_offset = lbl_pop.size / 2.0
	pop_t = 0.9

# ---------------------------------------------------------------- every frame
func step(dt: float) -> void:
	t += dt
	var p: Player = game.player
	if carrying and carry_node:
		carry_node.position = Vector3(0, -0.66 + sin(p.bob) * 0.01, -0.62)
		_hold_round_hands()
	if not active: return
	# step away if you walk off
	if Input.get_vector("move_left", "move_right", "move_fwd", "move_back").length() > 0.5:
		stop_chopping(); return
	if hold >= 0.0: hold += dt
	if recoil > 0.0: recoil = maxf(0.0, recoil - dt)
	if swing >= 0.0:
		var prev := swing
		swing = minf(1.0, swing + dt / 0.11)
		if prev < 1.0 and swing >= 1.0:
			_impact()
			swing = -1.0
			if recoil <= 0.0: recoil = 0.22
	_pose_axe(dt)
	# camera shake
	shake = maxf(0.0, shake - dt * 3.5)
	p.cam.h_offset = (randf() - 0.5) * 0.04 * shake
	p.cam.v_offset = (randf() - 0.5) * 0.04 * shake
	if pop_t > 0.0:
		pop_t -= dt
		lbl_pop.scale = Vector2.ONE * lerpf(1.0, 1.25, clampf((pop_t - 0.6) / 0.3, 0.0, 1.0))
		lbl_pop.modulate.a = clampf(pop_t / 0.35, 0.0, 1.0)
	if not pieces.is_empty():
		lbl_main.text = "Hold left mouse to raise the axe, let go to swing · %d/%d sticks to the next bundle · E to step away" % [pile.size(), PILE_PER_BUNDLE]
	ring.queue_redraw()

## the axe in your hands, camera space: at rest across your body, raised overhead as you wind up,
## then driven down to where you aimed
func _pose_axe(_dt: float) -> void:
	var cam: Camera3D = game.player.cam
	var cw := cam.global_transform
	var rest_hands := Vector3(0.12, -0.42, -0.42); var rest_dir := Vector3(-0.15, 0.55, -0.6).normalized()
	var up_hands := Vector3(0.05, 0.12, -0.05); var up_dir := Vector3(0.0, 0.75, 0.62).normalized()
	var hands: Vector3; var dir: Vector3
	var wind := 0.0
	if hold >= 0.0: wind = smoothstep(0.0, 1.0, clampf(hold / 0.45, 0.0, 1.0))
	if swing >= 0.0:
		# the downswing: from overhead to the hit point
		var hit_c: Vector3 = cw.affine_inverse() * (swing_hit.p as Vector3)
		var imp_dir := (hit_c - Vector3(0.05, -0.2, -0.25)).normalized()
		var imp_hands := hit_c - imp_dir * 0.8
		var u := swing * swing
		hands = up_hands.lerp(imp_hands, u); dir = up_dir.slerp(imp_dir, u)
	elif recoil > 0.0 and swing_hit.has("p"):
		# left in the wood a beat, then lifted back out
		var hit_c: Vector3 = cw.affine_inverse() * (swing_hit.p as Vector3)
		var imp_dir := (hit_c - Vector3(0.05, -0.2, -0.25)).normalized()
		var k := clampf(1.0 - recoil / 0.3, 0.0, 1.0)
		hands = (hit_c - imp_dir * 0.8).lerp(rest_hands, k * k); dir = imp_dir.slerp(rest_dir, k * k)
	else:
		hands = rest_hands.lerp(up_hands, wind); dir = rest_dir.slerp(up_dir, wind)
		# a little tremble when you've held it up too long
		if hold > SWEET_B: hands += Vector3(randf() - 0.5, randf() - 0.5, 0) * 0.006
	var z := -dir
	var x := Vector3.RIGHT - z * z.dot(Vector3.RIGHT); x = x.normalized()
	var y := z.cross(x)
	axe.transform = Transform3D(Basis(x, y, z), hands)
	# hands on the handle: right at the knob, left sliding down from near the head to meet it
	var s: Saw = game.saw
	var left_at := lerpf(-0.42, -0.1, clampf(wind + (1.0 if swing >= 0.0 else 0.0), 0.0, 1.0))
	s._fist_at(s.fist_r, s.arm_r, axe.transform * Vector3(0, 0, -0.03), Vector3(0.26, -0.62, 0.15))
	s._fist_at(s.fist_l, s.arm_l, axe.transform * Vector3(0, 0, left_at), Vector3(-0.3, -0.6, 0.12))
	for m in [s.fist_r, s.fist_l, s.arm_r, s.arm_l]: m.visible = true

func _hold_round_hands() -> void:
	var s: Saw = game.saw
	var R: float = carry_round.R
	s._fist_at(s.fist_r, s.arm_r, Vector3(R + 0.02, -0.5, -0.62), Vector3(0.3, -0.75, 0.1))
	s._fist_at(s.fist_l, s.arm_l, Vector3(-R - 0.02, -0.5, -0.62), Vector3(-0.3, -0.75, 0.1))
	for m in [s.fist_r, s.fist_l, s.arm_r, s.arm_l]: m.visible = true
