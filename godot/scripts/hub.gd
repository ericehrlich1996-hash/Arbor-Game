## Home: a beat-down log cabin in a clearing in the woods. Not much in it yet: a table and chair, a
## fireplace, a bed, a little kitchen and a tiny bathroom, and the old computer on a desk in the corner
## where the work comes in. The rusty truck's parked out front. This is the main menu: walk up to the
## computer and pick a job.
class_name Hub
extends Node3D

static var come_home := false          # set when you head home after a job: skip the title screen

const HX := 4.0                        # half the cabin's length (x) and depth (z), on the log centrelines
const HZ := 3.25
const F := 0.45                        # floor height above the ground
const COURSE := 0.3
const NC := 8
const LOG_R := 0.165
const TOP := F + NC * COURSE           # top of the walls
const RIDGE := TOP + 1.65

var game
var world: HubGen
var y0 := 0.0
var player: Player
var truck: Truck
var title_cam: Camera3D
var fire_light: OmniLight3D
var lamp_light: OmniLight3D
var flames: Node3D
var spots := {}                        # name -> [world point, reach]
var aim := ""
var busy := false
var t := 0.0
var flame_mat: StandardMaterial3D
var screen_mat: StandardMaterial3D

func build(g) -> void:
	game = g
	world = HubGen.new(); world.setup(31337); world.build(self)
	y0 = world.H(0, 0)
	flame_mat = StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.vertex_color_use_as_albedo = true
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	screen_mat = StandardMaterial3D.new()
	screen_mat.vertex_color_use_as_albedo = true
	screen_mat.emission_enabled = true; screen_mat.emission = Color(0.12, 0.45, 0.16); screen_mat.roughness = 0.15
	_build_cabin()
	_build_yard()
	# the truck, nose in by the cabin
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	truck = Truck.new(); truck.name = "Truck"; add_child(truck)
	truck.setup(rng)
	var tp := world.park
	var hf := world.H(tp.x, tp.z + 1.6); var hb := world.H(tp.x, tp.z - 1.6)
	truck.global_transform = Transform3D(Basis(Vector3.RIGHT, -atan2(hf - hb, 3.2)) * Basis(Vector3.UP, 0.25), Vector3(tp.x, (hf + hb) * 0.5 + 0.02, tp.z))
	truck.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC; truck.freeze = true
	spots.truck = [truck.global_transform * Vector3(1.2, 1.1, 0.3), 2.6]
	# you, out by the truck, looking at home
	player = Player.new(); player.name = "Player"; add_child(player)
	var sp := Vector3(3.2, 0, -9.0)
	var to := Vector3(0.6, 0, 0) - sp
	player.teleport(Vector3(sp.x, world.H(sp.x, sp.z) + 0.05, sp.z), atan2(-to.x, -to.z))
	title_cam = Camera3D.new(); title_cam.fov = 55; add_child(title_cam)

## a cabin-local point in the world
func W(p: Vector3) -> Vector3:
	return Vector3(p.x, p.y + y0, p.z)

# ================================================================ the cabin
func _build_cabin() -> void:
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new(); r.seed = 99
	mb.push(Transform3D(Basis(), Vector3(0, y0, 0)))
	# stone piers and a plank floor
	for px: float in [-HX, -HX / 3, HX / 3, HX]:
		for pz: float in [-HZ, 0.0, HZ]:
			mb.bevel_box(px, (F - 0.6) / 2 - 0.05, pz, 0.45, F + 0.5, 0.45, Color("#7a776e").lerp(Color("#5d5a52"), r.randf()), 0.05)
	var pw := 0.19
	var x := -HX - 0.05
	while x < HX + 0.05:
		mb.box(x + pw / 2, F - 0.05, 0, pw - 0.008, 0.1, 2 * HZ + 0.1, Color("#6b5640").lerp(Color("#857058"), r.randf()))
		x += pw
	# log walls with their openings: [from, to, bottom, top] along the wall, measured up from the floor
	var front := [[0.8, 1.8, 0.0, 2.05], [-1.6, -0.4, 0.85, 1.8]]
	var back := [[-1.0, 0.2, 0.9, 1.8], [2.7, 3.4, 1.3, 1.8]]
	var left := [[-2.9, -1.9, 0.95, 1.75]]
	var right := [[-1.8, -0.6, 1.1, 1.8]]
	_log_wall(mb, r, "x", -HZ, HX, front, 0.0)
	_log_wall(mb, r, "x", HZ, HX, back, 0.0)
	_log_wall(mb, r, "z", -HX, HZ, left, COURSE * 0.5)
	_log_wall(mb, r, "z", HX, HZ, right, COURSE * 0.5)
	for o in front.slice(1): _window(mb, "x", -HZ, o)
	for o in back: _window(mb, "x", HZ, o)
	for o in left: _window(mb, "z", -HX, o)
	for o in right: _window(mb, "z", HX, o)
	# the door: a plank door standing open inside, in a rough frame
	var trim := Color("#5a4632")
	mb.box(0.75, F + 1.04, -HZ, 0.1, 2.1, 0.36, trim); mb.box(1.85, F + 1.04, -HZ, 0.1, 2.1, 0.36, trim)
	mb.box(1.3, F + 2.1, -HZ, 1.2, 0.12, 0.36, trim)
	mb.push(Transform3D(Basis(Vector3.UP, -1.75), Vector3(1.8, F, -HZ + 0.12)))
	for k in range(5): mb.box(-0.1 - k * 0.19, 1.0, 0, 0.18, 2.0, 0.05, Color("#6a5238").lerp(Color("#7d6448"), r.randf()))
	for yy: float in [0.35, 1.65]: mb.box(-0.5, yy, 0.04, 0.95, 0.12, 0.03, Color("#5a4430"))
	mb.box(-0.85, 1.0, -0.05, 0.05, 0.05, 0.05, Color("#2a2a28"))
	mb.pop()
	_roof(mb, r)
	_chimney_and_fire(mb, r)
	_porch(mb, r)
	_furniture(mb, r)
	mb.pop()
	var mi := mb.instance(); mi.name = "Cabin"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED     # no sunlight through the tin
	add_child(mi)
	_cabin_collision()

## logs stacked up a wall, cut round the openings; the ends run past the corners like saddle-notched logs
func _log_wall(mb: MeshBuilder, r: RandomNumberGenerator, axis: String, fixed: float, half: float, openings: Array, y_off: float) -> void:
	for k in range(NC):
		var yc := F + COURSE * 0.5 + k * COURSE + y_off
		var h := yc - F
		if yc > TOP + 0.05: continue
		var segs := [[-half - 0.32, half + 0.32]]
		var chink := [[-half, half]]
		for o in openings:
			if h > o[2] - 0.13 and h < o[3] + 0.13:
				segs = _cut(segs, o[0], o[1]); chink = _cut(chink, o[0], o[1])
		var col := Color("#87725a").lerp(Color("#6e675d"), r.randf()) * r.randf_range(0.85, 1.05)
		var rr := LOG_R * r.randf_range(0.92, 1.06)
		for sg in segs:
			var a: Vector3; var b: Vector3
			if axis == "x": a = Vector3(sg[0], yc, fixed); b = Vector3(sg[1], yc, fixed)
			else: a = Vector3(fixed, yc, sg[0]); b = Vector3(fixed, yc, sg[1])
			if a.distance_to(b) < 0.05: continue
			mb.tube(a, b, rr, rr * 0.97, col, 9, true, Color("#b49a72"))
		if k < NC - 1:
			for sg in chink:
				var len: float = sg[1] - sg[0]
				if len < 0.05: continue
				var mid: float = (sg[0] + sg[1]) / 2
				if axis == "x": mb.box(mid, yc + COURSE / 2, fixed, len, 0.07, 0.22, Color("#aaa294"))
				else: mb.box(fixed, yc + COURSE / 2, mid, 0.22, 0.07, len, Color("#aaa294"))

static func _cut(segs: Array, a: float, b: float) -> Array:
	var out := []
	for sg in segs:
		if b <= sg[0] or a >= sg[1]: out.append(sg); continue
		if a > sg[0]: out.append([sg[0], a])
		if b < sg[1]: out.append([b, sg[1]])
	return out

## a small four-pane window, grimy, in a weathered frame (both faces of the wall)
func _window(mb: MeshBuilder, axis: String, fixed: float, o: Array) -> void:
	var a: float = o[0]; var b: float = o[1]; var lo: float = F + o[2]; var hi: float = F + o[3]
	var c: float = (a + b) / 2; var w := b - a; var hgt := hi - lo
	var fr := Color("#5f4c38")
	var bx := func(u: float, y: float, sw: float, sh: float, d: float, col: Color) -> void:
		if axis == "x": mb.box(u, y, fixed, sw, sh, d, col)
		else: mb.box(fixed, y, u, d, sh, sw, col)
	bx.call(c, lo, w + 0.12, 0.08, 0.4, fr); bx.call(c, hi, w + 0.12, 0.08, 0.36, fr)
	bx.call(a, (lo + hi) / 2, 0.08, hgt, 0.36, fr); bx.call(b, (lo + hi) / 2, 0.08, hgt, 0.36, fr)
	bx.call(c, (lo + hi) / 2, 0.04, hgt, 0.06, fr); bx.call(c, (lo + hi) / 2, w, 0.04, 0.06, fr)
	var gm := MeshBuilder.new()
	if axis == "x": gm.box(c, y0 + (lo + hi) / 2, fixed, w, hgt, 0.01, Color(0.75, 0.72, 0.6))
	else: gm.box(fixed, y0 + (lo + hi) / 2, c, 0.01, hgt, w, Color(0.75, 0.72, 0.6))
	var gi := gm.instance(Mats.truck_glass); gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gi)

## a gable roof of rusty corrugated tin over rough boards, gable ends boarded
func _roof(mb: MeshBuilder, r: RandomNumberGenerator) -> void:
	var ov := 0.6
	var slope := (RIDGE - TOP) / HZ
	var eave := TOP - slope * ov
	var x0 := -HX - 0.55; var x1 := HX + 0.55
	for side: float in [-1.0, 1.0]:
		var ez := side * (HZ + ov)
		var n := Vector3(0, 1, side * slope).normalized()
		# underside boards
		WorldGen._face_out(mb, [Vector3(x0, eave - 0.06, ez), Vector3(x1, eave - 0.06, ez), Vector3(x1, RIDGE - 0.06, 0), Vector3(x0, RIDGE - 0.06, 0)], -n, Color("#4a3a2c"))
		# the tin: strips running down the slope, every other one standing proud (the corrugation)
		var x := x0; var i := 0
		var patch := r.randf()
		while x < x1:
			var xb := minf(x + 0.11, x1)
			var lift := 0.03 if i % 2 == 0 else 0.0
			var rust := Color("#8a4a28").lerp(Color("#6b3a22"), r.randf())
			if fmod(x * 0.37 + patch, 1.0) < 0.22: rust = Color("#7e7f80").lerp(Color("#8a5a3a"), r.randf() * 0.6)     # a newer, galvanised sheet
			rust = rust * (0.92 if i % 2 else 1.04)
			var A := Vector3(x, eave, ez) + n * lift; var B := Vector3(xb, eave, ez) + n * lift
			var C := Vector3(xb, RIDGE, 0) + n * lift; var D := Vector3(x, RIDGE, 0) + n * lift
			WorldGen._face_out(mb, [A, B, C, D], n, rust)
			x = xb; i += 1
		mb.box(0, eave - 0.05, ez, x1 - x0, 0.12, 0.05, Color("#4a3a2c"))         # fascia
	mb.box(0, RIDGE + 0.04, 0, x1 - x0 + 0.04, 0.06, 0.32, Color("#6b3a22"))  # ridge cap
	# gable ends: weathered vertical boards
	for sx: float in [-1.0, 1.0]:
		var gx := sx * (HX + 0.05)
		var z := -HZ
		while z < HZ:
			var zb := minf(z + 0.22, HZ)
			var ya := TOP + (HZ - absf(z)) * slope; var yb := TOP + (HZ - absf(zb)) * slope
			var col := Color("#6d5f4e").lerp(Color("#5a5048"), r.randf())
			WorldGen._face_out(mb, [Vector3(gx, TOP - 0.1, z), Vector3(gx, TOP - 0.1, zb), Vector3(gx, yb, zb), Vector3(gx, ya, z)], Vector3(sx, 0, 0), col)
			WorldGen._face_out(mb, [Vector3(gx - sx * 0.04, TOP - 0.1, z), Vector3(gx - sx * 0.04, TOP - 0.1, zb), Vector3(gx - sx * 0.04, yb, zb), Vector3(gx - sx * 0.04, ya, z)], Vector3(-sx, 0, 0), col * 0.8)
			z = zb
	# inside: a ridge beam and two tie beams
	mb.box(0, RIDGE - 0.2, 0, 2 * HX, 0.18, 0.16, Color("#5a4632"))
	for bx: float in [-1.6, 1.4]: mb.box(bx, TOP + 0.05, 0, 0.16, 0.18, 2 * HZ, Color("#5a4632"))

func _stone(r: RandomNumberGenerator) -> Color:
	return Color("#7d786e").lerp(Color("#5e5a52"), r.randf()).lerp(Color("#8a7a62"), r.randf() * 0.4)

## a fieldstone chimney up the outside of the left wall, and the fireplace inside with a fire going
func _chimney_and_fire(mb: MeshBuilder, r: RandomNumberGenerator) -> void:
	var cz0 := -1.2; var cz1 := 0.2; var cx0 := -HX - 1.0; var cx1 := -HX - 0.1
	var y := -0.3
	while y < RIDGE + 0.7:
		var narrow := 0.0 if y < TOP - 0.4 else 0.2
		var z := cz0 + narrow + (0.12 if int(y / 0.22) % 2 else 0.0)
		while z < cz1 - narrow:
			var zb := minf(z + r.randf_range(0.25, 0.4), cz1 - narrow)
			mb.bevel_box(cx0 + narrow * 0.5 + 0.0, y + 0.11, (z + zb) / 2, 0.08, 0.2, zb - z - 0.02, _stone(r), 0.02)
			mb.bevel_box(cx1, y + 0.11, (z + zb) / 2, 0.08, 0.2, zb - z - 0.02, _stone(r), 0.02)
			z = zb
		mb.box((cx0 + narrow * 0.5 + cx1) / 2, y + 0.11, (cz0 + cz1) / 2, cx1 - cx0 - narrow * 0.5 - 0.06, 0.2, cz1 - cz0 - 2 * narrow - 0.04, Color("#5c574f"))
		y += 0.22
	mb.box((cx0 + 0.1 + cx1) / 2, RIDGE + 0.82, (cz0 + cz1) / 2, cx1 - cx0 - 0.1, 0.08, cz1 - cz0 - 0.3, Color("#4e4a44"))
	# inside: the firebox, built of stone round a dark opening, a hearth, a mantel
	var fx0 := -HX + 0.12; var fx1 := -HX + 0.78
	var fz0 := -1.3; var fz1 := 0.3; var oz0 := -0.85; var oz1 := -0.15
	var stone_box := func(xa: float, xb: float, ya: float, yb: float, za: float, zb: float) -> void:
		var yy := ya
		while yy < yb - 0.01:
			var y2 := minf(yy + 0.2, yb)
			var zz := za
			while zz < zb - 0.01:
				var z2 := minf(zz + r.randf_range(0.18, 0.32), zb)
				mb.bevel_box((xa + xb) / 2, (yy + y2) / 2, (zz + z2) / 2, xb - xa, y2 - yy - 0.015, z2 - zz - 0.015, _stone(r), 0.025)
				zz = z2
			yy = y2
	stone_box.call(fx0, fx1, F, F + 0.85, fz0, oz0)
	stone_box.call(fx0, fx1, F, F + 0.85, oz1, fz1)
	stone_box.call(fx0, fx1, F + 0.85, F + 1.4, fz0, fz1)
	stone_box.call(fx0 + 0.1, fx1 - 0.15, F + 1.55, TOP + 0.4, fz0 + 0.25, fz1 - 0.25)
	mb.box(fx0 + 0.06, F + 0.45, (oz0 + oz1) / 2, 0.12, 0.85, oz1 - oz0, Color("#120c08"))      # sooty back
	mb.box((fx0 + fx1) / 2, F + 0.85, (oz0 + oz1) / 2, fx1 - fx0, 0.02, oz1 - oz0, Color("#1a120c"))
	mb.box(fx1 + 0.22, F + 0.03, (fz0 + fz1) / 2, 0.55, 0.06, fz1 - fz0 + 0.2, Color("#6a655c"))   # hearth
	mb.box(fx1 + 0.04, F + 1.46, (fz0 + fz1) / 2, 0.3, 0.1, fz1 - fz0 + 0.3, Color("#5a4230"))     # mantel
	# on the mantel: a tin can of matches, a photo, a candle stub
	mb.cyl(fx1 + 0.05, F + 1.51, -1.1, 0.04, 0.04, 0.12, Color("#8a8e92"), 10, true)
	mb.box(fx1 + 0.02, F + 1.62, -0.4, 0.04, 0.2, 0.16, Color("#3a3028")); mb.box(fx1 + 0.045, F + 1.62, -0.4, 0.01, 0.15, 0.11, Color("#b0a890"))
	mb.cyl(fx1 + 0.05, F + 1.51, 0.15, 0.025, 0.025, 0.08, Color("#e8e0c8"), 8, true)
	# andirons and logs, and the fire (its own node so it can flicker)
	for z: float in [-0.75, -0.25]: mb.box(fx0 + 0.3, F + 0.1, z, 0.42, 0.06, 0.05, Color("#1e1e1e"))
	mb.tube(Vector3(fx0 + 0.3, F + 0.17, -0.8), Vector3(fx0 + 0.35, F + 0.17, -0.2), 0.06, 0.055, Color("#4a3a2a"), 7, true, Color("#2a1a10"))
	mb.tube(Vector3(fx0 + 0.42, F + 0.17, -0.78), Vector3(fx0 + 0.27, F + 0.26, -0.25), 0.05, 0.05, Color("#3a2c20"), 7, true, Color("#ff7a20"))
	flames = Node3D.new(); flames.position = W(Vector3(fx0 + 0.33, F + 0.2, -0.5)); add_child(flames)
	var fm := MeshBuilder.new()
	for k in range(5):
		var a := k * 0.7
		var hgt := 0.28 + 0.08 * (k % 3)
		var c0 := Color(1.0, 0.85, 0.35, 0.95); var c1 := Color(1.0, 0.35, 0.05, 0.0)
		var ax := Vector3(cos(a), 0, sin(a)) * 0.09
		var i0 := fm.v(-ax + Vector3(0, 0, (k - 2) * 0.07), Vector3.UP, c0); var i1 := fm.v(ax + Vector3(0, 0, (k - 2) * 0.07), Vector3.UP, c0)
		var i2 := fm.v(Vector3(0, hgt, (k - 2) * 0.07), Vector3.UP, c1)
		fm.tri(i0, i1, i2)
	var fmi := fm.instance(flame_mat); fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flames.add_child(fmi)
	fire_light = OmniLight3D.new(); fire_light.light_color = Color(1.0, 0.58, 0.25); fire_light.omni_range = 7.5
	fire_light.light_energy = 1.6; fire_light.position = Vector3(0.5, 0.35, 0)
	flames.add_child(fire_light)
	spots.fire = [W(Vector3(fx1 + 0.3, F + 0.6, -0.5)), 2.2]

## the porch along the front: plank deck, two posts, a tin lean-to roof, steps, a bench
func _porch(mb: MeshBuilder, r: RandomNumberGenerator) -> void:
	var px0 := -1.2; var px1 := HX + 0.3; var pz1 := -HZ - 1.8
	var dy := F - 0.04
	var z := -HZ - 0.15
	while z > pz1:
		mb.box((px0 + px1) / 2, dy, z - 0.09, px1 - px0, 0.08, 0.17, Color("#6a5640").lerp(Color("#7e6a50"), r.randf()))
		z -= 0.19
	for px: float in [px0 + 0.1, px1 - 0.1]:
		mb.box(px, dy / 2 - 0.1, pz1 + 0.15, 0.25, dy + 0.3, 0.25, _stone(r))
		mb.box(px, (dy + TOP - 0.45) / 2, pz1 + 0.12, 0.14, TOP - 0.45 - dy, 0.14, Color("#6e5a44"))
	mb.box((px0 + px1) / 2, TOP - 0.45, pz1 + 0.12, px1 - px0, 0.14, 0.14, Color("#6e5a44"))
	var slope := (RIDGE - TOP) / HZ
	var ry := TOP - slope * 0.55 - 0.04
	var n := Vector3(0, 1, -0.3).normalized()
	var xx := px0 - 0.15; var i := 0
	while xx < px1 + 0.15:
		var xb := minf(xx + 0.11, px1 + 0.15)
		var l := 0.03 if i % 2 == 0 else 0.0
		WorldGen._face_out(mb, [Vector3(xx, TOP - 0.38, pz1 - 0.2) + n * l, Vector3(xb, TOP - 0.38, pz1 - 0.2) + n * l, Vector3(xb, ry, -HZ - 0.55) + n * l, Vector3(xx, ry, -HZ - 0.55) + n * l], n, Color("#8a4a28").lerp(Color("#6b3a22"), r.randf()))
		xx = xb; i += 1
	WorldGen._face_out(mb, [Vector3(px0 - 0.15, TOP - 0.42, pz1 - 0.2), Vector3(px1 + 0.15, TOP - 0.42, pz1 - 0.2), Vector3(px1 + 0.15, ry - 0.04, -HZ - 0.55), Vector3(px0 - 0.15, ry - 0.04, -HZ - 0.55)], -n, Color("#4a3a2c"))
	for k in range(2):
		mb.box(1.3, dy - 0.15 - k * 0.17, pz1 - 0.15 - k * 0.3, 1.1, 0.07, 0.3, Color("#6a5640"))
		mb.box(1.3, (dy - 0.15 - k * 0.17) / 2 - 0.1, pz1 - 0.15 - k * 0.3, 1.06, dy - 0.1 - k * 0.17, 0.27, Color("#4e3e2e"))
	# a bench and a bucket on the porch
	mb.box(3.0, dy + 0.42, -HZ - 0.35, 1.3, 0.06, 0.32, Color("#6e5a44"))
	for bx: float in [2.45, 3.55]: mb.box(bx, dy + 0.2, -HZ - 0.35, 0.06, 0.42, 0.28, Color("#5a4632"))
	mb.cyl(-0.6, dy + 0.04, -HZ - 0.5, 0.15, 0.17, 0.3, Color("#7e8286"), 12, false)

## inside: desk and computer, table and chair, bed, rug, firewood, kitchen and bathroom
func _furniture(mb: MeshBuilder, r: RandomNumberGenerator) -> void:
	var wood := Color("#7a5c3e"); var dkwood := Color("#5a4230")
	# --- the desk in the front-left corner, with the old computer
	var dx := -3.15; var dz := -2.82; var dt := F + 0.76
	mb.box(dx, dt, dz, 1.4, 0.05, 0.66, wood)
	for lx: float in [-0.65, 0.65]:
		for lz: float in [-0.28, 0.28]: mb.box(dx + lx, F + 0.37, dz + lz, 0.05, 0.74, 0.05, dkwood)
	mb.box(dx - 0.4, dt - 0.12, dz, 0.5, 0.18, 0.6, wood)                                       # a drawer
	mb.box(dx - 0.4, dt - 0.12, dz + 0.305, 0.08, 0.025, 0.01, Color("#2a2a28"))
	var beige := Color("#cfc5a8"); var beige2 := Color("#b8ad90")
	mb.bevel_box(dx + 0.1, dt + 0.21, dz - 0.05, 0.44, 0.38, 0.42, beige, 0.03)                 # the CRT
	mb.bevel_box(dx + 0.1, dt + 0.2, dz - 0.25, 0.3, 0.26, 0.2, beige2, 0.04)
	mb.box(dx + 0.1, dt + 0.025, dz, 0.3, 0.05, 0.3, beige2)
	mb.box(dx + 0.1, dt + 0.07, dz + 0.17, 0.22, 0.04, 0.02, Color("#3a3a36"))
	mb.box(dx + 0.07, dt + 0.04, dz + 0.24, 0.42, 0.025, 0.14, beige2)                          # keyboard
	for kx in range(10):
		for ky in range(3): mb.box(dx - 0.1 + kx * 0.035, dt + 0.056, dz + 0.2 + ky * 0.035, 0.028, 0.008, 0.028, beige)
	mb.bevel_box(dx + 0.5, F + 0.24, dz - 0.05, 0.2, 0.46, 0.44, beige, 0.02)                     # the tower
	mb.box(dx + 0.5, F + 0.38, dz + 0.175, 0.14, 0.03, 0.01, Color("#3a3a36"))
	mb.cyl(dx - 0.45, dt + 0.025, dz + 0.12, 0.045, 0.045, 0.1, Color("#c8462c"), 10, true)       # coffee mug
	mb.box(dx - 0.5, dt + 0.03, dz - 0.12, 0.22, 0.02, 0.3, Color("#e8e2cc"))                     # notepad
	var sm := MeshBuilder.new()
	sm.box(dx + 0.1, y0 + dt + 0.22, dz + 0.165, 0.34, 0.27, 0.01, Color("#103a18"))
	var smi := sm.instance(screen_mat); smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(smi)
	var glow := OmniLight3D.new(); glow.light_color = Color(0.4, 1.0, 0.45); glow.light_energy = 0.35; glow.omni_range = 1.6
	glow.position = W(Vector3(dx + 0.1, dt + 0.25, dz + 0.4)); add_child(glow)
	_chair(mb, Vector3(dx + 0.05, F, -2.15), PI, wood, dkwood)
	spots.computer = [W(Vector3(dx + 0.1, dt + 0.22, dz + 0.17)), 2.0]
	# --- the table and chair, with an oil lamp
	var tx := -0.7; var tz := 0.45
	mb.box(tx, F + 0.76, tz, 1.2, 0.06, 0.8, wood)
	for lx: float in [-0.53, 0.53]:
		for lz: float in [-0.33, 0.33]: mb.box(tx + lx, F + 0.37, tz + lz, 0.07, 0.74, 0.07, dkwood)
	_chair(mb, Vector3(tx + 0.1, F, tz + 0.75), 0.15, wood, dkwood)
	mb.cyl(tx + 0.3, F + 0.79, tz - 0.1, 0.07, 0.06, 0.03, Color("#6a5a3a"), 10, true)
	mb.sphere(tx + 0.3, F + 0.9, tz - 0.1, 0.06, 0.08, 0.06, Color("#d8d0b0"), 10, 6)
	mb.cyl(tx + 0.3, F + 0.97, tz - 0.1, 0.025, 0.03, 0.07, Color("#3a3a36"), 8, true)
	mb.cyl(tx - 0.2, F + 0.79, tz + 0.1, 0.12, 0.12, 0.015, Color("#c8c4b8"), 14, true)          # a tin plate
	mb.cyl(tx - 0.35, F + 0.79, tz - 0.15, 0.04, 0.035, 0.09, Color("#8a8e92"), 10, true)        # tin cup
	lamp_light = OmniLight3D.new(); lamp_light.light_color = Color(1.0, 0.78, 0.45); lamp_light.light_energy = 0.7
	lamp_light.omni_range = 4.0; lamp_light.position = W(Vector3(tx + 0.3, F + 0.92, tz - 0.1)); add_child(lamp_light)
	# --- the bed in the back-left corner
	var bx := -3.33; var bz := 2.2
	mb.box(bx, F + 0.2, bz, 1.0, 0.12, 1.95, dkwood)
	for lx: float in [-0.46, 0.46]:
		for lz: float in [-0.93, 0.93]: mb.box(bx + lx, F + 0.12, bz + lz, 0.08, 0.24, 0.08, dkwood)
	mb.box(bx, F + 0.55, bz + 0.98, 1.04, 0.7, 0.07, dkwood)                                    # headboard
	mb.bevel_box(bx, F + 0.33, bz, 0.92, 0.16, 1.88, Color("#d8cfb8"), 0.05)                     # mattress
	mb.bevel_box(bx, F + 0.43, bz - 0.2, 0.96, 0.06, 1.4, Color("#7a3a30"), 0.03)                 # wool blanket
	for k in range(4): mb.box(bx, F + 0.465, bz - 0.75 + k * 0.38, 0.97, 0.008, 0.06, Color("#2e2a26"))
	mb.bevel_box(bx, F + 0.47, bz + 0.72, 0.6, 0.12, 0.34, Color("#e8e2d0"), 0.05)               # pillow
	spots.bed = [W(Vector3(bx, F + 0.5, bz)), 2.0]
	# --- a rug before the fire, and a little stack of firewood by it
	mb.box(-2.0, F + 0.005, -0.5, 1.8, 0.01, 1.3, Color("#7a4a3a"))
	mb.box(-2.0, F + 0.007, -0.5, 1.6, 0.01, 1.1, Color("#9a6a4a"))
	for row in range(3):
		for k in range(3 - row):
			mb.push(Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(-3.55, F + 0.08 + row * 0.13, 0.55 + k * 0.15 + row * 0.07)))
			mb.cyl(0, -0.22, 0, 0.065, 0.065, 0.44, Color("#6a5a46"), 7, true, Color("#c8a070"))
			mb.pop()
	# --- the kitchen, along the right wall: an old fridge, a counter with a sink, a stove, a shelf
	var kx := HX - 0.47
	mb.bevel_box(kx, F + 0.78, -2.82, 0.62, 1.56, 0.62, Color("#e2ddc8"), 0.08)                    # fridge
	mb.box(kx - 0.315, F + 1.05, -2.6, 0.03, 0.3, 0.04, Color("#b0b0a8"))
	mb.box(kx - 0.312, F + 1.12, -2.82, 0.005, 0.01, 0.6, Color("#9a968a"))
	mb.box(kx, F + 0.44, -1.1, 0.6, 0.86, 2.6, dkwood)                                           # cabinets
	for k in range(4): mb.box(kx - 0.305, F + 0.44, -2.15 + k * 0.65, 0.01, 0.7, 0.58, wood)
	mb.box(kx - 0.02, F + 0.9, -1.1, 0.66, 0.05, 2.62, Color("#9a8e78"))                          # worn top
	mb.box(kx, F + 0.83, -1.2, 0.45, 0.12, 0.5, Color("#c8c6bc")); mb.box(kx, F + 0.88, -1.2, 0.4, 0.04, 0.44, Color("#5a5a56"))
	mb.tube(Vector3(HX - 0.2, F + 0.92, -1.2), Vector3(HX - 0.2, F + 1.12, -1.2), 0.015, 0.015, Color("#a8acb0"), 6)
	mb.tube(Vector3(HX - 0.2, F + 1.12, -1.2), Vector3(HX - 0.38, F + 1.1, -1.2), 0.013, 0.013, Color("#a8acb0"), 6)
	mb.bevel_box(kx, F + 0.46, 0.55, 0.62, 0.92, 0.62, Color("#e8e4d4"), 0.04)                    # the stove
	for bz2: float in [0.4, 0.7]:
		for bx2: float in [-0.12, 0.12]: mb.cyl(kx + bx2, F + 0.925, bz2, 0.08, 0.08, 0.015, Color("#1e1e1e"), 12, true)
	mb.box(kx - 0.31, F + 0.4, 0.55, 0.01, 0.45, 0.48, Color("#2a2a28"))
	mb.box(kx + 0.25, F + 1.05, 0.55, 0.1, 0.25, 0.62, Color("#e8e4d4"))
	mb.box(HX - 0.3, F + 1.65, -1.1, 0.25, 0.03, 1.6, wood)                                      # shelf
	for k in range(6):
		var cc: Color = [Color("#b83a2a"), Color("#d8b040"), Color("#4a7a4a"), Color("#c8c4b8")][k % 4]
		mb.cyl(HX - 0.3, F + 1.665, -1.75 + k * 0.25, 0.04, 0.04, 0.11, cc, 8, true, Color("#a8acb0"))
	mb.cyl(HX - 0.48, F + 0.925, -0.3, 0.12, 0.1, 0.15, Color("#2a2a28"), 12, true)               # a cast-iron pot
	# --- the bathroom in the back-right corner: board walls, a door ajar, a toilet, a sink, a mirror
	var bwx := 2.0; var bwz := 1.25
	var board := Color("#7a6a54")
	var z := bwz
	while z < HZ - 0.1:
		mb.box(bwx, F + 1.15, z + 0.1, 0.05, 2.3, 0.19, board.lerp(Color("#6a5c48"), r.randf()))
		z += 0.2
	var xx := bwx
	while xx < HX - 0.1:
		if xx < 2.2 or xx > 3.0: mb.box(xx + 0.1, F + 1.15, bwz, 0.19, 2.3, 0.05, board.lerp(Color("#6a5c48"), r.randf()))
		xx += 0.2
	mb.box(2.6, F + 2.25, bwz, 0.8, 0.1, 0.06, board)
	mb.push(Transform3D(Basis(Vector3.UP, 1.2), Vector3(2.22, F, bwz + 0.03)))
	for k in range(4): mb.box(0.1 + k * 0.19, 1.0, 0, 0.18, 2.0, 0.04, board.lerp(Color("#8a7a62"), r.randf()))
	mb.pop()
	mb.bevel_box(3.55, F + 0.2, 2.85, 0.38, 0.4, 0.5, Color("#ece8dc"), 0.08)                      # toilet
	mb.bevel_box(3.55, F + 0.41, 2.78, 0.42, 0.05, 0.5, Color("#f2efe6"), 0.03)
	mb.bevel_box(3.55, F + 0.62, 3.08, 0.44, 0.42, 0.18, Color("#ece8dc"), 0.04)
	mb.cyl(2.45, F, 2.98, 0.07, 0.06, 0.72, Color("#ece8dc"), 10, false)                        # sink
	mb.bevel_box(2.45, F + 0.78, 2.95, 0.46, 0.14, 0.36, Color("#ece8dc"), 0.05)
	mb.box(2.45, F + 0.84, 2.93, 0.32, 0.03, 0.24, Color("#6a6a66"))
	mb.box(2.45, F + 1.45, HZ - 0.19, 0.4, 0.5, 0.02, Color("#5a5a52")); mb.box(2.45, F + 1.45, HZ - 0.2, 0.34, 0.44, 0.01, Color("#9aa6aa"))
	mb.box(3.95 - 0.2, F + 1.2, 2.2, 0.02, 0.5, 0.3, Color("#4a6a8a"))                           # a towel

func _chair(mb: MeshBuilder, at: Vector3, yaw: float, wood: Color, dk: Color) -> void:
	mb.push(Transform3D(Basis(Vector3.UP, yaw), at))
	mb.box(0, 0.45, 0, 0.44, 0.05, 0.42, wood)
	for lx: float in [-0.19, 0.19]:
		for lz: float in [-0.18, 0.18]: mb.box(lx, 0.22, lz, 0.045, 0.44, 0.045, dk)
		mb.box(lx, 0.72, 0.19, 0.045, 0.55, 0.045, dk)
	for k in range(3): mb.box(0, 0.62 + k * 0.14, 0.19, 0.4, 0.06, 0.025, wood)
	mb.pop()

func _box_col(c: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var bs := BoxShape3D.new()
	bs.size = size; cs.shape = bs; sb.add_child(cs); sb.position = W(c)
	add_child(sb)

func _cabin_collision() -> void:
	var t2 := (TOP - F)
	_box_col(Vector3(0, F / 2 - 0.25, 0), Vector3(2 * HX + 0.3, F + 0.5, 2 * HZ + 0.3))            # floor
	_box_col(Vector3((-HX - 0.2 + 0.78) / 2, F + t2 / 2, -HZ), Vector3(0.78 + HX + 0.2, t2, 0.34))   # front, left of the door
	_box_col(Vector3((1.82 + HX + 0.2) / 2, F + t2 / 2, -HZ), Vector3(HX + 0.2 - 1.82, t2, 0.34))
	_box_col(Vector3(1.3, F + 2.05 + (t2 - 2.05) / 2, -HZ), Vector3(1.1, t2 - 2.05, 0.34))
	_box_col(Vector3(0, F + t2 / 2, HZ), Vector3(2 * HX + 0.4, t2, 0.34))
	for sx: float in [-1.0, 1.0]: _box_col(Vector3(sx * HX, F + t2 / 2, 0), Vector3(0.34, t2, 2 * HZ + 0.4))
	_box_col(Vector3(-HX - 0.55, 2.0, -0.5), Vector3(0.95, 4.0, 1.45))                              # chimney
	_box_col(Vector3(-HX + 0.45, F + 0.7, -0.5), Vector3(0.7, 1.4, 1.6))                            # fireplace
	_box_col(Vector3(1.4, F / 2 - 0.2, -HZ - 0.95), Vector3(5.6, F + 0.4, 1.7))                      # porch
	_box_col(Vector3(1.3, F / 2 - 0.3, -HZ - 1.95), Vector3(1.1, F * 0.6, 0.3))                       # step
	# furniture
	_box_col(Vector3(-3.15, F + 0.4, -2.82), Vector3(1.4, 0.8, 0.66))
	_box_col(Vector3(-0.7, F + 0.4, 0.45), Vector3(1.2, 0.8, 0.8))
	_box_col(Vector3(-3.33, F + 0.3, 2.2), Vector3(1.0, 0.6, 1.95))
	_box_col(Vector3(HX - 0.47, F + 0.5, -1.25), Vector3(0.62, 1.0, 3.75))
	_box_col(Vector3(HX - 0.47, F + 0.8, -2.82), Vector3(0.62, 1.6, 0.62))
	_box_col(Vector3(2.0, F + 1.15, 2.25), Vector3(0.06, 2.3, 2.0))                                 # bathroom walls
	_box_col(Vector3(2.1, F + 1.15, 1.25), Vector3(0.2, 2.3, 0.06))
	_box_col(Vector3(3.5, F + 1.15, 1.25), Vector3(1.0, 2.3, 0.06))
	_box_col(Vector3(3.55, F + 0.3, 2.9), Vector3(0.45, 0.6, 0.6))

# ================================================================ the yard
func _build_yard() -> void:
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new(); r.seed = 5
	# firewood stacked against the right wall outside, under the eave
	for row in range(5):
		var z := -2.4
		while z < 2.2:
			var rr := r.randf_range(0.1, 0.15)
			var p := Vector3(HX + 0.55, world.H(HX + 0.55, z) + 0.12 + row * 0.24, z)
			mb.push(Transform3D(Basis(Vector3.FORWARD, PI / 2), p))
			mb.cyl(0, -0.25, 0, rr, rr, 0.5, Color("#6e604e").lerp(Color("#5a4e40"), r.randf()), 8, true, Color("#c8a878").lerp(Color("#a8885a"), r.randf()))
			mb.pop()
			z += rr * 2.05
	# a chopping block with the axe stuck in it
	var cb := Vector3(4.2, 0, -6.0); cb.y = world.H(cb.x, cb.z)
	mb.cyl(cb.x, cb.y - 0.05, cb.z, 0.32, 0.3, 0.55, Color("#6e604e"), 12, true, Color("#b89a6a"))
	mb.push(Transform3D(Basis(Vector3.BACK, 0.35), cb + Vector3(0.05, 0.55, 0)))
	mb.box(0, 0.02, 0, 0.04, 0.12, 0.18, Color("#5a5e62"))
	mb.tube(Vector3(0, 0.05, 0), Vector3(0, 0.75, 0), 0.025, 0.022, Color("#a8844e"), 6, true)
	mb.pop()
	for k in range(7):
		var a := r.randf() * TAU; var d := r.randf_range(0.6, 1.4)
		var p := cb + Vector3(cos(a) * d, 0, sin(a) * d); p.y = world.H(p.x, p.z) + 0.04
		mb.push(Transform3D(Basis(Vector3.UP, r.randf() * TAU) * Basis(Vector3.FORWARD, PI / 2), p))
		mb.box(0, 0, 0, 0.09, 0.3, 0.12, Color("#c8a878").lerp(Color("#8a7458"), r.randf()))
		mb.pop()
	# a rain barrel, an old tire, a rusty wheelbarrow tipped over
	var rb := Vector3(HX + 0.6, 0, HZ + 0.6); rb.y = world.H(rb.x, rb.z)
	mb.cyl(rb.x, rb.y, rb.z, 0.32, 0.3, 0.9, Color("#4a5a6a"), 14, true, Color("#1a2a30"))
	for yy: float in [0.2, 0.7]: mb.cyl(rb.x, rb.y + yy, rb.z, 0.335, 0.335, 0.05, Color("#6a4a30"), 14, false)
	var tr := Vector3(-5.5, 0, -6.5); tr.y = world.H(tr.x, tr.z)
	mb.cyl(tr.x, tr.y, tr.z, 0.38, 0.38, 0.22, Color("#1e1e1e"), 16, false)
	mb.cyl(tr.x, tr.y + 0.21, tr.z, 0.24, 0.24, 0.01, Color("#3a3a36"), 16, true)
	var wb := Vector3(-5.0, 0, 3.8); wb.y = world.H(wb.x, wb.z)
	mb.push(Transform3D(Basis(Vector3.BACK, 2.5) * Basis(Vector3.UP, 0.6), wb + Vector3(0, 0.35, 0)))
	mb.box(0, 0, 0, 0.6, 0.25, 0.9, Color("#7a3a20")); mb.cyl(0, -0.3, 0.55, 0.15, 0.15, 0.08, Color("#1e1e1e"), 12, true)
	mb.pop()
	var mi := mb.instance(); mi.name = "Yard"
	add_child(mi)

# ================================================================ play
func begin() -> void:
	player.cam.make_current()

func step(dt: float) -> void:
	t += dt
	# the fire flickers
	var fk := 0.75 + 0.15 * sin(t * 11.0) + 0.1 * sin(t * 23.0 + 1.3) + 0.08 * sin(t * 5.3)
	fire_light.light_energy = 1.5 * fk
	flames.scale = Vector3(1.0, 0.85 + 0.25 * fk, 1.0)
	lamp_light.light_energy = 0.65 + 0.04 * sin(t * 9.0)
	if game.phase == "title":
		var a := t * 0.05
		title_cam.global_position = W(Vector3(sin(a) * 15.0, 7.5, cos(a) * 15.0 - 2.0))
		title_cam.look_at(W(Vector3(0, 1.6, 0)))
		return
	if busy:
		aim = ""
		return
	# what are you looking at?
	aim = ""
	var best := 0.9
	var eye := player.eye(); var fw := player.aim_dir()
	for k in spots:
		var p: Vector3 = spots[k][0]
		var d := eye.distance_to(p)
		if d > spots[k][1]: continue
		var c := fw.dot((p - eye).normalized())
		if c > best: best = c; aim = k
	var txt := ""
	match aim:
		"computer": txt = "[b]E[/b] Use the computer"
		"truck": txt = "Your truck. She's seen better days."
		"bed": txt = "[b]E[/b] Have a nap"
		"fire": txt = "Nice and warm."
	game.hud.set_prompt(txt)
	# bare hands
	var s: Saw = game.saw
	s.model.visible = false
	for m in [s.fist_r, s.fist_l, s.arm_r, s.arm_l]: m.visible = true
	s.pose_hands(false)

func interact() -> void:
	match aim:
		"computer": game.open_computer()
		"bed":
			busy = true
			var tw := create_tween()
			tw.tween_property(game.hud.fade, "color:a", 1.0, 0.8)
			tw.tween_interval(1.2)
			tw.tween_callback(func(): game.hud.toast("You slept like a log.", 2.5))
			tw.tween_property(game.hud.fade, "color:a", 0.0, 1.0)
			tw.tween_callback(func(): busy = false)
		"truck": game.hud.toast("Rust holding it together. Once there's money in the bank, she gets fixed up.", 3.5)
