## Random property: terrain, road, gravel driveway, house, shed, woodpile spot, mailbox, woods,
## and where the problem tree stands. Road runs along X on the south edge (−Z); the house sits north.
class_name WorldGen
extends RefCounted

const SIDING := ["#e9e4d6", "#f0e2b0", "#b9cbd6", "#b8c4a6", "#d9c3a0", "#cfd2cf", "#e6d2c4"]
const ROOFS := ["#3d3f42", "#4a3a30", "#2f3b33", "#5a4a3f", "#3a3d4a"]
const DOORS := ["#8a2a22", "#2f4a3a", "#1f2326", "#3a4a6a", "#7a5a2a"]
const N := 150          # terrain grid cells per side
const S := 300.0        # terrain size (m)

var seed := 0
var s := 1.0            # mirrors the layout left/right
var rng := RandomNumberGenerator.new()
var road_z := -56.0
var park := Vector3.ZERO
var drive: Array = []          # driveway control points (Vector2 x,z)
var drive_path: Array = []     # smoothed
var house := {}
var shed := {}
var pile := {}
var tree := {}
var old_man := Vector2.ZERO
var mailbox := Vector2.ZERO
var bg_trees: Array = []
var yard_trees: Array = []
var flat: Array = []
var _nA := FastNoiseLite.new()
var _nB := FastNoiseLite.new()
var _nC := FastNoiseLite.new()
var _grid := PackedFloat32Array()
var _base := 0.0

func _pick(a: Array):
	return a[rng.randi_range(0, a.size() - 1)]

func _range(a: float, b: float) -> float:
	return rng.randf_range(a, b)

func _noise(n: FastNoiseLite, x: float, z: float) -> float:
	return n.get_noise_2d(x, z) * 0.5 + 0.5

func setup(sd: int) -> void:
	seed = sd
	rng.seed = sd
	s = -1.0 if rng.randf() < 0.5 else 1.0
	for n in [_nA, _nB, _nC]:
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 1.0
	_nA.seed = sd; _nB.seed = sd + 7; _nC.seed = sd + 3
	park = Vector3(s * 4.5, 0, -1)
	drive = [Vector2(s * 15, -56), Vector2(s * 11, -44), Vector2(s * 7, -28), Vector2(s * 5, -12), Vector2(s * 4.5, -1), Vector2(s * 4.5, 3)]
	house = {x = s * -9, z = 12.0, w = _range(12, 14), d = _range(8.5, 9.5), wall = 2.7,
		siding = Color.html(_pick(SIDING)), roof = Color.html(_pick(ROOFS)), door = Color.html(_pick(DOORS))}
	shed = {x = s * -21, z = _range(16, 24), w = 3.2, d = 2.6}
	pile = {x = shed.x, z = shed.z + shed.d / 2 + 2.1, w = 3.6, d = 2.6}
	flat = [{x = house.x, z = house.z, r = 13.0}, {x = shed.x, z = shed.z, r = 6.0}, {x = pile.x, z = pile.z, r = 3.5}, {x = park.x, z = park.z, r = 9.0}]
	_base = _raw(house.x, house.z)
	# the problem tree: open lawn, clear of everything by more than its height
	tree = {}
	for k in range(400):
		var x := _range(-38, 38); var z := _range(-24, 40); var ht := _range(17, 20)
		var clear := ht + 3.5
		var d_drive := 1e9
		for p in drive: d_drive = minf(d_drive, Vector2(x, z).distance_to(p))
		if _box_dist(x, z, house) < clear or _box_dist(x, z, shed) < clear or Vector2(x, z).distance_to(Vector2(pile.x, pile.z)) < clear - 1: continue
		if Vector2(x, z).distance_to(Vector2(park.x, park.z)) < clear + 4 or d_drive < clear - 2 or z - road_z < clear + 4: continue
		tree = {x = x, z = z, h = ht, dbh = _range(0.5, 0.6), lean = _range(0.02, 0.06), lean_dir = _range(0, TAU), seed = rng.randi_range(1, 1000000)}
		break
	if tree.is_empty():
		tree = {x = s * 24, z = 30.0, h = 16.0, dbh = 0.5, lean = 0.04, lean_dir = 1.0, seed = 5}
	old_man = Vector2(park.x - s * 3.2, park.z + 4.5)
	mailbox = Vector2(drive[0].x + s * 2.4, road_z + 3.2)
	# background woods
	for k in range(900):
		var x := _range(-150, 150); var z := _range(-140, 150)
		if (absf(x) < 48 and z > -46 and z < 54) or absf(z - road_z) < 10 or Vector2(x, z).length() > 175: continue
		bg_trees.push_back({x = x, z = z, h = _range(11, 22), pine = rng.randf() < 0.35, r = _range(2.4, 4.2), c = rng.randf()})
	for k in range(60):
		if yard_trees.size() >= 5: break
		var x := _range(-44, 44); var z := _range(-40, 50)
		var d_drive := 1e9
		for p in drive: d_drive = minf(d_drive, Vector2(x, z).distance_to(p))
		if Vector2(x, z).distance_to(Vector2(tree.x, tree.z)) < tree.h + 8 or _box_dist(x, z, house) < 5 or _box_dist(x, z, shed) < 5: continue
		if Vector2(x, z).distance_to(Vector2(park.x, park.z)) < 12 or d_drive < 6 or z - road_z < 8: continue
		yard_trees.push_back({x = x, z = z, h = _range(6, 10), pine = rng.randf() < 0.5, r = _range(1.6, 2.6), c = rng.randf()})
	# the ground is exactly the triangles that get drawn (and collided with)
	var st := S / N
	_grid.resize((N + 1) * (N + 1))
	for j in range(N + 1):
		for i in range(N + 1):
			_grid[j * (N + 1) + i] = _smooth_h(-S / 2 + i * st, -S / 2 + j * st)
	drive_path = _spline(drive, 6)

func _box_dist(x: float, z: float, b: Dictionary) -> float:
	return Vector2(maxf(absf(x - b.x) - b.w / 2, 0), maxf(absf(z - b.z) - b.d / 2, 0)).length()

func _raw(x: float, z: float) -> float:
	return (_noise(_nA, x / 38, z / 38) - 0.5) * 2.4 + (_noise(_nB, x / 11, z / 11) - 0.5) * 0.5

func _smooth_h(x: float, z: float) -> float:
	var h := _raw(x, z)
	for f in flat:
		var d := Vector2(x - f.x, z - f.z).length()
		if d < f.r * 1.6:
			h = lerpf(h, _base, smoothstep(0, 1, clampf((f.r * 1.6 - d) / (f.r * 0.6), 0, 1)))
	var dr := absf(z - road_z)
	if dr < 9: h = lerpf(h, _base - 0.15, smoothstep(0, 1, clampf((9 - dr) / 5, 0, 1)))
	return h

## ground height, matching the drawn triangles exactly
func H(x: float, z: float) -> float:
	var st := S / N
	var gx := clampf((x + S / 2) / st, 0, N - 1e-4); var gz := clampf((z + S / 2) / st, 0, N - 1e-4)
	var i := int(gx); var j := int(gz); var fx := gx - i; var fz := gz - j
	var A := _grid[j * (N + 1) + i]; var B := _grid[(j + 1) * (N + 1) + i]; var C := _grid[(j + 1) * (N + 1) + i + 1]; var D := _grid[j * (N + 1) + i + 1]
	if fz > fx: return A + (C - B) * fx + (B - A) * fz
	return A + (D - A) * fx + (C - D) * fz

func normal_at(x: float, z: float) -> Vector3:
	var e := 0.5
	return Vector3(H(x - e, z) - H(x + e, z), 2 * e, H(x, z - e) - H(x, z + e)).normalized()

static func _spline(pts: Array, n: int) -> Array:
	var out := []
	for i in range(pts.size() - 1):
		var p0: Vector2 = pts[maxi(0, i - 1)]; var p1: Vector2 = pts[i]; var p2: Vector2 = pts[i + 1]; var p3: Vector2 = pts[mini(pts.size() - 1, i + 2)]
		for k in range(n):
			var t := float(k) / n; var t2 := t * t; var t3 := t2 * t
			out.push_back(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
	out.push_back(pts[pts.size() - 1])
	return out

# ------------------------------------------------------------------ building the scene
func build(root: Node3D) -> void:
	_build_terrain(root)
	_build_roads(root)
	_build_house(root)
	_build_woods(root)

func _static_box(root: Node3D, center: Vector3, size: Vector3, yaw := 0.0) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.transform = Transform3D(Basis(Vector3.UP, yaw), center)
	root.add_child(sb)

func _build_terrain(root: Node3D) -> void:
	var mb := MeshBuilder.new()
	var st := S / N
	var lawn := Color.html("#5f8a3a"); var lawn2 := Color.html("#6f9a44"); var meadow := Color.html("#7d8a45"); var forest := Color.html("#4a5a30")
	var ids := []
	for j in range(N + 1):
		var row := []
		for i in range(N + 1):
			var x := -S / 2 + i * st; var z := -S / 2 + j * st; var y := _grid[j * (N + 1) + i]
			var inside := absf(x) < 46 and z > -48 and z < 52
			var n := _noise(_nC, x / 6, z / 6)
			var c: Color
			if inside:
				c = lawn.lerp(lawn2, n)
				c = MeshBuilder.shade(c, 1.04 if int(floor((x + z * 0.15) / 2.2)) % 2 != 0 else 0.96)
			else:
				c = meadow.lerp(forest, clampf((absf(x) - 46) / 14, 0, 1) * 0.7 + n * 0.3)
				if absf(x) > 60 or z > 66: c = c.lerp(forest, 0.6)
			row.push_back(mb.v(Vector3(x, y, z), normal_at(x, z), c))
		ids.push_back(row)
	for j in range(N):
		for i in range(N):
			# A=(i,j) B=(i,j+1) C=(i+1,j+1) D=(i+1,j): split along A–C, same as H()
			mb.tri(ids[j][i], ids[j + 1][i], ids[j + 1][i + 1])
			mb.tri(ids[j][i], ids[j + 1][i + 1], ids[j][i + 1])
	var mi := mb.instance(Mats.terrain)
	mi.name = "Terrain"
	root.add_child(mi)
	var sb := StaticBody3D.new(); sb.name = "Ground"
	var cs := CollisionShape3D.new()
	cs.shape = mi.mesh.create_trimesh_shape()
	sb.add_child(cs)
	root.add_child(sb)

func _ribbon(mb: MeshBuilder, path: Array, width: float, col: Color, lift: float, jitter := true) -> void:
	var L := []; var R := []
	for k in range(path.size()):
		var a: Vector2 = path[maxi(0, k - 1)]; var b: Vector2 = path[mini(path.size() - 1, k + 1)]
		var d := (b - a).normalized(); var nrm := Vector2(-d.y, d.x)
		var p: Vector2 = path[k]
		var lp := p + nrm * width / 2; var rp := p - nrm * width / 2
		var c := MeshBuilder.shade(col, 0.94 + ((k * 7) % 5) * 0.025) if jitter else col
		L.push_back(mb.v(Vector3(lp.x, H(lp.x, lp.y) + lift, lp.y), Vector3.UP, c))
		R.push_back(mb.v(Vector3(rp.x, H(rp.x, rp.y) + lift, rp.y), Vector3.UP, c))
	for k in range(path.size() - 1):
		mb.quad(L[k], R[k], R[k + 1], L[k + 1])

func _build_roads(root: Node3D) -> void:
	var mb := MeshBuilder.new()
	var road := []
	var x := -150.0
	while x <= 150.0:
		road.push_back(Vector2(x, road_z)); x += 3.0
	_ribbon(mb, road, 7, Color.html("#3b3d40"), 0.05)
	x = -150.0
	while x < 150.0:
		_ribbon(mb, [Vector2(x, road_z), Vector2(x + 3, road_z)], 0.14, Color.html("#c9a640"), 0.07, false); x += 6.0
	_ribbon(mb, drive_path, 3.4, Color.html("#8f8676"), 0.06)
	var r := RandomNumberGenerator.new(); r.seed = seed + 11
	var gravel := Color.html("#8f8676")
	for k in range(drive_path.size() - 1):
		for m in range(6):
			var t := r.randf(); var a: Vector2 = drive_path[k]; var b: Vector2 = drive_path[k + 1]
			var gx := lerpf(a.x, b.x, t) + r.randf_range(-1.5, 1.5); var gz := lerpf(a.y, b.y, t) + r.randf_range(-1.5, 1.5)
			mb.box(gx, H(gx, gz) + 0.07, gz, r.randf_range(0.08, 0.18), 0.02, r.randf_range(0.08, 0.18), MeshBuilder.shade(gravel, r.randf_range(0.75, 1.2)))
	var mi := mb.instance(); mi.name = "Roads"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

func _build_house(root: Node3D) -> void:
	var mb := MeshBuilder.new()
	var h := house
	var y0 := H(h.x, h.z)
	var r := RandomNumberGenerator.new(); r.seed = seed + 21
	var trim := Color.html("#f2f0ea"); var glass := Color.html("#2c3a46"); var found := Color.html("#8b8a86"); var sid: Color = h.siding
	mb.push(Transform3D(Basis(), Vector3(h.x, y0, h.z)))
	mb.box(0, -0.2, 0, h.w + 0.1, 1.3, h.d + 0.1, found)          # foundation, sunk into the slope
	var boards := 14
	for b in range(boards):
		var yy: float = 0.45 + b * (h.wall / boards)
		var grow := 0.02 if b % 2 else 0.0
		mb.box(0, yy + h.wall / boards / 2, 0, h.w + grow, h.wall / boards, h.d + grow, MeshBuilder.shade(sid, 0.96 if b % 2 else 1.02))
	var top: float = 0.45 + h.wall
	# gable roof: the roof planes pass through the wall tops and run on as the overhang
	var ov := 0.5; var ridge := top + 2.1; var hw: float = h.w / 2 + ov; var hd: float = h.d / 2 + ov
	var slope: float = (ridge - top) / (h.d / 2); var eave: float = top - slope * ov
	var roof: Color = h.roof
	mb.face([Vector3(-hw, eave, -hd), Vector3(hw, eave, -hd), Vector3(hw, ridge, 0), Vector3(-hw, ridge, 0)], roof)
	mb.face([Vector3(hw, eave, hd), Vector3(-hw, eave, hd), Vector3(-hw, ridge, 0), Vector3(hw, ridge, 0)], MeshBuilder.shade(roof, 0.92))
	mb.box(0, ridge + 0.02, 0, 2 * hw, 0.08, 0.16, MeshBuilder.shade(roof, 0.8))
	for sx in [-1.0, 1.0]:
		var gx: float = sx * h.w / 2
		mb.face([Vector3(gx, top, -h.d / 2), Vector3(gx, top, h.d / 2), Vector3(gx, ridge - 0.02, 0)], sid)
		for sz in [-1.0, 1.0]:
			mb.tube(Vector3(sx * (hw - 0.03), eave, sz * hd), Vector3(sx * (hw - 0.03), ridge, 0), 0.06, 0.06, trim, 4)
	for sz in [-1.0, 1.0]:
		mb.box(0, eave - 0.03, sz * (h.d / 2 + ov / 2), h.w + 2 * ov, 0.05, ov, trim)
		mb.box(0, eave - 0.06, sz * hd, h.w + 2 * ov, 0.2, 0.06, trim)
	var fz: float = -h.d / 2 - 0.04; var bz: float = h.d / 2 + 0.04
	var shutter := MeshBuilder.shade(h.door, 0.9)
	for w in [[-h.w * 0.32, fz, -1.0], [h.w * 0.36, fz, -1.0], [-h.w * 0.3, bz, 1.0], [h.w * 0.05, bz, 1.0], [h.w * 0.35, bz, 1.0]]:
		var wx: float = w[0]; var wz: float = w[1]; var f: float = w[2]
		mb.box(wx, 1.75, wz, 1.3, 1.2, 0.08, trim); mb.box(wx, 1.75, wz + f * 0.03, 1.1, 1.0, 0.06, glass)
		mb.box(wx, 1.75, wz + f * 0.05, 0.05, 1.0, 0.02, trim); mb.box(wx, 1.75, wz + f * 0.05, 1.1, 0.05, 0.02, trim)
		mb.box(wx - 0.85, 1.75, wz, 0.35, 1.2, 0.05, shutter); mb.box(wx + 0.85, 1.75, wz, 0.35, 1.2, 0.05, shutter)
	for sx in [-1.0, 1.0]:
		mb.box(sx * (h.w / 2 + 0.04), 1.75, 0, 0.08, 1.1, 1.1, trim); mb.box(sx * (h.w / 2 + 0.07), 1.75, 0, 0.06, 0.92, 0.92, glass)
	# front door + porch with its roof hung under the eave
	var dx: float = h.w * 0.18
	mb.box(dx, 1.5, fz - 0.02, 1.1, 2.25, 0.1, trim); mb.box(dx, 1.47, fz - 0.06, 0.92, 2.1, 0.06, h.door); mb.box(dx + 0.32, 1.45, fz - 0.11, 0.07, 0.07, 0.07, Color.html("#c9a640"))
	var conc := Color.html("#9a958c")
	mb.box(dx, 0.1, fz - 1.3, 3.2, 0.68, 2.4, conc)
	mb.box(dx, -0.05, fz - 2.8, 1.4, 0.38, 0.6, conc)
	var p_in := eave - 0.12; var p_out := p_in - 0.5; var pz0 := fz; var pz1 := fz - 2.6; var post_z := fz - 2.35
	var post_top := p_in + (p_out - p_in) * ((post_z - pz0) / (pz1 - pz0))
	for px in [-1.4, 1.4]:
		mb.box(dx + px, (0.44 + post_top) / 2, post_z, 0.14, post_top - 0.44, 0.14, trim)
	mb.box(dx, post_top - 0.06, post_z, 3.0, 0.14, 0.14, trim)
	mb.face([Vector3(dx - 1.8, p_out, pz1), Vector3(dx + 1.8, p_out, pz1), Vector3(dx + 1.8, p_in, pz0), Vector3(dx - 1.8, p_in, pz0)], roof)
	mb.box(dx, p_in - 0.04, pz0 - 0.04, 3.6, 0.1, 0.08, trim); mb.box(dx, p_out - 0.05, pz1, 3.6, 0.14, 0.05, trim)
	# chimney
	var cx: float = -h.w * 0.3
	for k in range(12):
		mb.box(cx, top + 0.2 + k * 0.25, h.d * 0.18, 0.8, 0.25, 0.8, MeshBuilder.shade(Color.html("#8a4a36"), 0.92 if k % 2 else 1.05))
	mb.box(cx, top + 3.25, h.d * 0.18, 0.9, 0.1, 0.9, Color.html("#5a5a5a"))
	for k in range(5):
		var sxp: float = -h.w / 2 + 1 + k * (h.w - 2) / 4
		if absf(sxp - dx) < 2: continue
		mb.blob(sxp, 0.55, fz - 0.8, 0.65, Color.html("#3f6a2e"), r, 0.8)
	mb.pop()
	_static_box(root, Vector3(h.x, y0 + 1.6, h.z), Vector3(h.w, 3.6, h.d))
	_static_box(root, Vector3(h.x + dx, y0 + 0.1, h.z + fz - 1.3), Vector3(3.2, 0.68, 2.4))
	for px in [-1.4, 1.4]:
		_static_box(root, Vector3(h.x + dx + px, y0 + 1.6, h.z + post_z), Vector3(0.16, 3.0, 0.16))
	# shed
	var sh := shed
	var sy := H(sh.x, sh.z)
	var sc := MeshBuilder.shade(sid, 0.9)
	mb.push(Transform3D(Basis(), Vector3(sh.x, sy, sh.z)))
	mb.box(0, 1.0, 0, sh.w, 2.4, sh.d, sc)
	for k in range(7):
		mb.box(-sh.w / 2 + 0.25 + k * (sh.w - 0.5) / 6, 1.1, -sh.d / 2 - 0.02, 0.04, 2.2, 0.03, MeshBuilder.shade(sc, 0.8))
	var srw: float = sh.w / 2 + 0.3; var srd: float = sh.d / 2 + 0.3
	var s_slope: float = 0.9 / (sh.d / 2); var s_eave: float = 2.2 - s_slope * 0.3
	mb.face([Vector3(-srw, s_eave, -srd), Vector3(srw, s_eave, -srd), Vector3(srw, 3.1, 0), Vector3(-srw, 3.1, 0)], roof)
	mb.face([Vector3(srw, s_eave, srd), Vector3(-srw, s_eave, srd), Vector3(-srw, 3.1, 0), Vector3(srw, 3.1, 0)], roof)
	for sx in [-1.0, 1.0]:
		mb.face([Vector3(sx * sh.w / 2, 2.2, -sh.d / 2), Vector3(sx * sh.w / 2, 2.2, sh.d / 2), Vector3(sx * sh.w / 2, 3.08, 0)], sc)
	mb.box(0, 1, -sh.d / 2 - 0.06, 1.1, 1.9, 0.04, MeshBuilder.shade(sc, 0.7))
	mb.pop()
	_static_box(root, Vector3(sh.x, sy + 1.2, sh.z), Vector3(sh.w, 2.6, sh.d))
	# woodpile spot: four stakes with orange flagging
	var py := H(pile.x, pile.z)
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var px2: float = pile.x + c.x * pile.w / 2; var pz2: float = pile.z + c.y * pile.d / 2
		var gy := H(px2, pz2)
		mb.box(px2, gy + 0.45, pz2, 0.05, 1.0, 0.05, Color.html("#c9a878")); mb.box(px2, gy + 0.82, pz2, 0.07, 0.14, 0.02, Color.html("#ff6a1a"))
	# mailbox
	var my := H(mailbox.x, mailbox.y)
	mb.box(mailbox.x, my + 0.55, mailbox.y, 0.08, 1.1, 0.08, Color.html("#6a5a44"))
	mb.push(Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(mailbox.x, my + 1.18, mailbox.y)))
	mb.cyl(0, -0.25, 0, 0.12, 0.12, 0.5, Color.html("#2a2d30"), 10, true)
	mb.pop()
	mb.box(mailbox.x + 0.14, my + 1.28, mailbox.y - 0.1, 0.02, 0.2, 0.06, Color.html("#c03a2a"))
	_static_box(root, Vector3(mailbox.x, my + 0.7, mailbox.y), Vector3(0.3, 1.4, 0.55))
	var mi := mb.instance(); mi.name = "Buildings"
	root.add_child(mi)

func _build_woods(root: Node3D) -> void:
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new(); r.seed = seed + 31
	var bark := Color.html("#4a3e34")
	var leaf := [Color.html("#3c6a2a"), Color.html("#4f7a32"), Color.html("#5c7f36"), Color.html("#46682c")]
	var pine := [Color.html("#2c4a2c"), Color.html("#355434"), Color.html("#2a4430")]
	var one := func(t: Dictionary, lod: bool) -> void:
		var y := H(t.x, t.z) - 0.1
		if t.pine:
			mb.cyl(t.x, y, t.z, 0.22, 0.12, t.h * 0.35, bark, 5, false)
			var tiers := 3 if lod else 4
			for k in range(tiers):
				var f := float(k) / tiers
				mb.cyl(t.x, y + t.h * (0.2 + f * 0.62), t.z, t.r * (1 - f * 0.72), 0.02, t.h * (0.42 - f * 0.06), pine[k % 3], 6 if lod else 8, false)
		else:
			mb.cyl(t.x, y, t.z, 0.26, 0.14, t.h * 0.6, bark, 5, false)
			var c: Color = leaf[int(t.c * 4) % 4]
			for k in range(2 if lod else 4):
				mb.blob(t.x + r.randf_range(-1, 1) * t.r * 0.5, y + t.h * r.randf_range(0.62, 0.84), t.z + r.randf_range(-1, 1) * t.r * 0.5, t.r * r.randf_range(0.7, 1), c, r, 0.85)
	for t in bg_trees: one.call(t, Vector2(t.x, t.z).length() > 90)
	for t in yard_trees:
		one.call(t, false)
		var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var cy := CylinderShape3D.new()
		cy.radius = 0.3; cy.height = 4.0; cs.shape = cy; sb.add_child(cs)
		sb.position = Vector3(t.x, H(t.x, t.z) + 2, t.z); root.add_child(sb)
	var mi := mb.instance(); mi.name = "Woods"
	root.add_child(mi)
