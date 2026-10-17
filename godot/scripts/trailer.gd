## Walter's old utility trailer: a single-axle steel trailer with oak stake sides and a drop gate,
## parked on its tongue jack. Mrs. Hale gives it to you along with the wood. The bed uses the same
## local frame as the truck's (floor top at y 0.8, walls to 1.36, z from -2.62 to -0.73), so loading
## and throwing work the same; the whole thing sits 0.2 lower so the floor is 0.6 off the ground.
## When it's loaded you tarp it: a blue tarp unrolls over the top and bungees down.
class_name Trailer
extends StaticBody3D

const SINK := 0.2
var tarp: Node3D
var tarped := false
var _tarp_t := -1.0

func build() -> void:
	collision_layer = 1; collision_mask = 0
	var mb := MeshBuilder.new()
	var steel := Color("#3a4a3e"); var dk := Color("#1e2420"); var oak := Color("#8a6a48"); var deck := Color("#7a6a52")
	var rust := Color("#6b3a22")
	var z0 := -2.62; var z1 := -0.73; var zc := (z0 + z1) / 2; var L := z1 - z0
	# frame and floor
	for sx: float in [-1.0, 1.0]: mb.box(sx * 0.82, 0.66, zc, 0.08, 0.12, L + 0.1, steel)
	for k in range(5): mb.box(0, 0.64, z0 + 0.1 + k * (L - 0.2) / 4.0, 1.7, 0.08, 0.06, steel)
	var x := -0.88
	var r := RandomNumberGenerator.new(); r.seed = 41
	while x < 0.88:
		mb.box(x + 0.09, 0.76, zc, 0.175, 0.07, L, deck.lerp(Color("#8e7c60"), r.randf()))
		x += 0.18
	# stake sides: steel pockets with oak boards, and the drop gate at the back
	for sx: float in [-1.0, 1.0]:
		for k in range(4):
			var zz := z0 + 0.12 + k * (L - 0.24) / 3.0
			mb.box(sx * 0.93, 1.06, zz, 0.06, 0.62, 0.06, steel)
		for k in range(3): mb.box(sx * 0.93, 0.92 + k * 0.17, zc, 0.04, 0.13, L, oak.lerp(Color("#9a7a56"), r.randf()))
		mb.box(sx * 0.93, 1.36, zc, 0.07, 0.04, L + 0.06, steel)
	for k in range(3): mb.box(0, 0.92 + k * 0.17, z1 + 0.02, 1.86, 0.13, 0.04, oak.lerp(Color("#9a7a56"), r.randf()))   # front board
	for k in range(3): mb.box(0, 0.92 + k * 0.17, z0 - 0.02, 1.86, 0.13, 0.04, oak.lerp(Color("#9a7a56"), r.randf()))   # drop gate
	for sx: float in [-1.0, 1.0]:
		mb.box(sx * 0.5, 1.06, z0 - 0.05, 0.05, 0.5, 0.03, steel)
		mb.box(sx * 0.78, 0.7, z0 - 0.08, 0.12, 0.07, 0.03, Color("#c22a1e"))           # tail lights
	# axle, fenders and wheels
	var ax := zc + 0.05
	mb.push(Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(0, 0.5, ax)))
	mb.cyl(0, -1.0, 0, 0.04, 0.04, 2.0, dk, 8, true)
	mb.pop()
	for sx: float in [-1.0, 1.0]:
		var prev := Vector3.ZERO
		for k in range(9):
			var a := PI * k / 8.0
			var q := Vector3(sx * 1.08, 0.52 + sin(a) * 0.36, ax - cos(a) * 0.4)
			if k > 0:
				var dir := (q - prev).normalized(); var mid := (prev + q) / 2
				mb.push(Transform3D(Basis(Vector3.RIGHT, atan2(-dir.y, dir.z)), mid))
				mb.box(0, 0, 0, 0.26, 0.025, prev.distance_to(q) + 0.01, steel.lerp(rust, 0.3))
				mb.pop()
			prev = q
		mb.push(Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(sx * 1.08, 0.5, ax)))
		mb.cyl(0, -0.1, 0, 0.29, 0.29, 0.2, Color("#1a1a1a"), 18, true, Color("#222222"))
		mb.cyl(0, sx * 0.1 - (0.01 if sx < 0 else 0.0), 0, 0.17, 0.17, 0.012, Color("#c8ccd0"), 14, true)
		mb.pop()
	# the tongue, coupler and jack stand
	mb.tube(Vector3(-0.8, 0.66, z1), Vector3(0, 0.62, z1 + 1.3), 0.04, 0.04, steel, 6)
	mb.tube(Vector3(0.8, 0.66, z1), Vector3(0, 0.62, z1 + 1.3), 0.04, 0.04, steel, 6)
	mb.bevel_box(0, 0.62, z1 + 1.42, 0.1, 0.09, 0.24, dk, 0.02)
	mb.cyl(0.15, 0.2, z1 + 0.95, 0.04, 0.04, 0.55, dk, 8, true)
	mb.box(0.15, 0.2, z1 + 0.95, 0.18, 0.03, 0.18, dk)
	mb.cyl(0.15, 0.75, z1 + 0.95, 0.015, 0.015, 0.12, dk, 6, true)
	var mi := mb.instance(); mi.position.y = -SINK; add_child(mi)
	# collision: floor and the four sides (same as the truck's bed)
	_col(Vector3(0, 0.55, zc), Vector3(1.9, 0.5, L))
	for sx: float in [-1.0, 1.0]: _col(Vector3(sx * 0.93, 1.06, zc), Vector3(0.1, 0.62, L + 0.1))
	_col(Vector3(0, 1.06, z1 + 0.02), Vector3(1.9, 0.62, 0.08))
	_col(Vector3(0, 1.06, z0 - 0.02), Vector3(1.9, 0.62, 0.08))
	_col(Vector3(0, 0.62, z1 + 0.7), Vector3(0.3, 0.2, 1.4))
	_build_tarp()

func _col(c: Vector3, s: Vector3) -> void:
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = s
	cs.shape = bs; cs.position = c - Vector3(0, SINK, 0); add_child(cs)

## the bed's frame, matching the truck's local bed coordinates (for throwing, loading and counting)
func bed_xf() -> Transform3D:
	return global_transform * Transform3D(Basis(), Vector3(0, -SINK, 0))

func in_bed(p: Vector3) -> bool:
	var l := bed_xf().affine_inverse() * p
	return absf(l.x) < 1.0 and l.z > -2.7 and l.z < -0.65 and l.y > 0.6 and l.y < 3.0

## a blue poly tarp: across the top with a little sag over the load, draped down the sides, grommets
## and bungees to the stake pockets. Hinged at the front board so it can unroll toward the back.
func _build_tarp() -> void:
	var mb := MeshBuilder.new()
	var blue := Color("#2f63b8"); var blue2 := Color("#264f96")
	var z0 := -2.62; var z1 := -0.73; var L := z1 - z0
	var nx := 8; var nz := 8
	var top := 1.48
	var ids := []
	for j in range(nz + 1):
		var row := []
		for i in range(nx + 1):
			var u := float(i) / nx * 2.0 - 1.0; var v := float(j) / nz
			var px := u * 1.0
			var sag := 0.08 * sin(v * PI) * (1.0 - u * u) + 0.05 * sin(v * 9.0 + u * 5.0)
			var py := top - sag * 0.6 + 0.04 * (1.0 - u * u)
			if absf(u) > 0.85: py = lerpf(py, 1.12, (absf(u) - 0.85) / 0.15); px = u * 1.0 + signf(u) * 0.0
			var pz := -v * (L + 0.06)
			var c := blue if (i + j) % 3 else blue2
			row.append(mb.v(Vector3(px, py, pz), Vector3.UP, c))
		ids.append(row)
	for j in range(nz):
		for i in range(nx):
			mb.quad(ids[j][i], ids[j + 1][i], ids[j + 1][i + 1], ids[j][i + 1])
			mb.quad(ids[j][i], ids[j][i + 1], ids[j + 1][i + 1], ids[j + 1][i])
	# down over the front and back boards
	for zz: float in [0.03, -(L + 0.09)]:
		mb.box(0, 1.3, zz, 2.0, 0.34, 0.01, blue2)
	# grommets and bungees down to the stake pockets
	for sx: float in [-1.0, 1.0]:
		for k in range(4):
			var zz := -0.12 - k * (L - 0.24) / 3.0
			mb.sphere(sx * 1.0, 1.13, zz, 0.025, 0.025, 0.025, Color("#c8ccd0"), 6, 4)
			mb.tube(Vector3(sx * 1.0, 1.13, zz), Vector3(sx * 0.97, 0.88, zz), 0.012, 0.012, Color("#d84020") if k % 2 else Color("#202020"), 4)
	tarp = Node3D.new(); tarp.position = Vector3(0, -SINK, z1)
	var ti := mb.instance(); ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	tarp.add_child(ti)
	tarp.visible = false
	add_child(tarp)

## pull the tarp over: it unrolls from the front to the back
func tarp_it(on_done: Callable = Callable()) -> void:
	if tarped: return
	tarped = true
	tarp.visible = true
	tarp.scale = Vector3(1, 1, 0.02)
	var tw := create_tween()
	tw.tween_property(tarp, "scale", Vector3(1, 1, 1), 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if on_done.is_valid(): tw.tween_callback(on_done)

## already tarped (at home, or the moment you load in)
func set_tarped() -> void:
	tarped = true; tarp.visible = true; tarp.scale = Vector3.ONE
