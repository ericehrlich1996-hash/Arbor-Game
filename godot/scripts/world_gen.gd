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
		tree = {x = x, z = z, h = ht, dbh = _range(0.5, 0.6), lean = _range(0.015, 0.1), lean_dir = _range(0, TAU), seed = rng.randi_range(1, 1000000)}
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

var _edge := FastNoiseLite.new()
## 0 on the mown lawn, 1 deep in the woods; the edge of the woods wanders
func forestness(x: float, z: float) -> float:
	if _edge.seed != seed + 5: _edge.seed = seed + 5; _edge.frequency = 0.035
	var dx := maxf(maxf(-46.0 - x, x - 46.0), 0.0)
	var dz := maxf(maxf(-48.0 - z, z - 52.0), 0.0)
	var d := Vector2(dx, dz).length()
	if d == 0.0: d = -minf(minf(x + 46.0, 46.0 - x), minf(z + 48.0, 52.0 - z))     # inside the lawn: how far in
	d += _edge.get_noise_2d(x, z) * 9.0
	return clampf((d + 2.0) / 10.0, 0.0, 1.0)

func _box_dist(x: float, z: float, b: Dictionary) -> float:
	return Vector2(maxf(absf(x - b.x) - b.w / 2, 0), maxf(absf(z - b.z) - b.d / 2, 0)).length()

func _raw(x: float, z: float) -> float:
	return (_noise(_nA, x / 38, z / 38) - 0.5) * 2.4 + (_noise(_nB, x / 11, z / 11) - 0.5) * 0.5

## a creek winds through the woods behind the property
func creek_z(x: float) -> float:
	return 72.0 + 8.0 * sin(x / 31.0 + float(seed % 7)) + 4.0 * sin(x / 13.0 + 2.0)

func creek_d(x: float, z: float) -> float:
	return absf(z - creek_z(x)) * 0.85

func _smooth_h(x: float, z: float) -> float:
	var h := _raw(x, z)
	var cd := creek_d(x, z)
	if cd < 8.0: h -= 1.35 * (1.0 - smoothstep(1.4, 8.0, cd))
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
	_build_creek(root)
	_build_house(root)
	var forest := Forest.new(); forest.build(self, root)
	_build_grass(root)

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
	var lawn := Color.html("#5d7f3b"); var lawn2 := Color.html("#6b8c43"); var meadow := Color.html("#7c854a")
	var floor_dirt := Color.html("#76603e"); var floor_moss := Color.html("#6b7c3a"); var floor_leaf := Color.html("#a26c35")
	var ids := []
	for j in range(N + 1):
		var row := []
		for i in range(N + 1):
			var x := -S / 2 + i * st; var z := -S / 2 + j * st; var y := _grid[j * (N + 1) + i]
			var n := _noise(_nC, x / 6, z / 6)
			var fo := forestness(x, z)
			var c := lawn.lerp(lawn2, n)
			if fo < 0.05: c = MeshBuilder.shade(c, 1.025 if int(floor((x + z * 0.15) / 2.2)) % 2 != 0 else 0.975)
			# the forest floor: needles and leaf litter, with mossy patches
			var floor_c := floor_dirt.lerp(floor_moss, smoothstep(0.35, 0.75, _noise(_nB, x / 9, z / 9)))
			floor_c = floor_c.lerp(floor_leaf, smoothstep(0.55, 0.85, _noise(_nA, x / 5, z / 5)) * 0.7)
			c = c.lerp(meadow, clampf(fo * 3.0, 0, 1) * 0.5).lerp(floor_c, smoothstep(0.2, 0.7, fo))
			var cdist := creek_d(x, z)
			if cdist < 9.0:
				c = c.lerp(Color.html("#4f6a2c"), (1.0 - smoothstep(3.5, 9.0, cdist)) * 0.7)      # moss on the banks
				c = c.lerp(Color.html("#5a4a36"), 1.0 - smoothstep(1.5, 4.0, cdist))             # wet mud and stones at the water
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
		# wind every quad so it faces up (a back-facing quad gets lit from below and goes dark)
		var up := (mb.verts[R[k]] - mb.verts[L[k]]).cross(mb.verts[L[k + 1]] - mb.verts[L[k]]).y
		if up > 0: mb.quad(L[k], R[k], R[k + 1], L[k + 1])
		else: mb.quad(L[k], L[k + 1], R[k + 1], R[k])

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
	# power poles along the far side of the road, wires sagging between them
	var pm := MeshBuilder.new()
	var wood := Color.html("#6a5440"); var wire := Color.html("#1e1e1e")
	var pz := road_z - 6.5
	var tops: Array = []
	var px := -150.0 + float(seed % 17)
	while px < 150.0:
		var gy := H(px, pz)
		pm.cyl(px, gy - 0.3, pz, 0.15, 0.11, 9.3, wood, 8, true)
		pm.box(px, gy + 8.3, pz, 0.12, 0.14, 2.2, wood)
		for k: float in [-0.9, 0.0, 0.9]:
			pm.cyl(px, gy + 8.37, pz + k, 0.04, 0.03, 0.14, Color.html("#7aa0a8"), 6, true)
		pm.cyl(px + 0.25, gy + 6.9, pz, 0.22, 0.22, 0.6, Color.html("#8a8e92"), 10, true)     # transformer can
		tops.append(Vector3(px, gy + 8.52, pz))
		px += 38.0
	for i in range(tops.size() - 1):
		for k: float in [-0.9, 0.0, 0.9]:
			var a: Vector3 = tops[i] + Vector3(0, 0, k); var b: Vector3 = tops[i + 1] + Vector3(0, 0, k)
			var prev := a
			for j in range(1, 9):
				var t := j / 8.0
				var q := a.lerp(b, t) - Vector3(0, sin(t * PI) * 0.9, 0)
				pm.tube(prev, q, 0.012, 0.012, wire, 3); prev = q
	var pmi := pm.instance(); pmi.name = "PowerLine"
	root.add_child(pmi)

## a roof plane covered in rows of shingle tabs: lower edge at height e (z = ze), upper edge at rg (z = zr), from x0 to x1
static func _shingles(mb: MeshBuilder, x0: float, x1: float, e: float, ze: float, rg: float, zr: float, col: Color, r: RandomNumberGenerator, tab := 0.8) -> void:
	var span := Vector3(0, rg - e, zr - ze)
	var L := span.length(); var u := span / L
	var n := Vector3(0, absf(u.z), -signf(u.z) * u.y)
	var rows := maxi(2, ceili(L / 0.3))
	var ds := L / rows
	var lift := 0.035
	for i in range(rows):
		var s0 := i * ds; var s1 := s0 + ds
		var x := x0 - (tab * 0.5 if i % 2 else 0.0)
		while x < x1:
			var xa := maxf(x, x0); var xb := minf(x + tab, x1)
			x += tab
			if xb - xa < 0.05: continue
			var c := MeshBuilder.shade(col, r.randf_range(0.82, 1.08))
			var base := Vector3(0, e, ze)
			var A := base + Vector3(xa + 0.01, 0, 0) + u * s0 + n * lift; var B := base + Vector3(xb - 0.01, 0, 0) + u * s0 + n * lift
			var C := base + Vector3(xb - 0.01, 0, 0) + u * s1 + n * 0.006; var D := base + Vector3(xa + 0.01, 0, 0) + u * s1 + n * 0.006
			_face_out(mb, [A, B, C, D], n, c)
			_face_out(mb, [A - n * lift, B - n * lift, B, A], -u, MeshBuilder.shade(c, 0.55))

static func _face_out(mb: MeshBuilder, pts: Array, out: Vector3, c: Color) -> void:
	var nn: Vector3 = (pts[2] - pts[0]).cross(pts[1] - pts[0])
	if nn.dot(out) < 0: pts.reverse()
	mb.face(pts, c)

## a window set into a wall facing f (±1 along z, or along x when on_x): casing, sill, head cap, four panes, shutters
static func _window(mb: MeshBuilder, wx: float, wy: float, wz: float, f: float, trim: Color, glass: Color, shutter: Color, on_x := false, ww := 1.1, wh := 1.15) -> void:
	if on_x:
		mb.push(Transform3D(Basis(Vector3.UP, PI / 2 * f), Vector3(wz, 0, wx)))
		_window(mb, 0.0, wy, 0.0, 1.0, trim, glass, shutter, false, ww, wh)
		mb.pop(); return
	var o := wz
	mb.box(wx, wy, o + f * 0.01, ww + 0.04, wh + 0.04, 0.06, MeshBuilder.shade(glass, 0.7))          # the dark reveal
	mb.box(wx, wy - wh * 0.25, o + f * 0.005, ww - 0.06, wh * 0.5, 0.05, glass)
	mb.box(wx, wy + wh * 0.25, o + f * 0.005, ww - 0.06, wh * 0.5, 0.05, MeshBuilder.shade(glass, 1.35))  # sky caught in the top sash
	mb.box(wx, wy, o + f * 0.035, 0.04, wh, 0.03, trim); mb.box(wx, wy, o + f * 0.035, ww, 0.05, 0.03, trim)
	for sx: float in [-1.0, 1.0]: mb.box(wx + sx * (ww / 2 + 0.05), wy, o + f * 0.04, 0.12, wh + 0.1, 0.05, trim)
	mb.box(wx, wy + wh / 2 + 0.1, o + f * 0.045, ww + 0.34, 0.14, 0.06, trim)
	mb.box(wx, wy + wh / 2 + 0.18, o + f * 0.06, ww + 0.42, 0.03, 0.1, MeshBuilder.shade(trim, 0.92))
	mb.box(wx, wy - wh / 2 - 0.06, o + f * 0.07, ww + 0.3, 0.05, 0.14, trim)                 # sill
	for sx: float in [-1.0, 1.0]:
		var shx := wx + sx * (ww / 2 + 0.32)
		mb.box(shx, wy, o + f * 0.03, 0.36, wh + 0.08, 0.04, shutter)
		for k in range(5): mb.box(shx, wy - wh / 2 + 0.12 + k * (wh - 0.16) / 4.0, o + f * 0.055, 0.3, 0.025, 0.012, MeshBuilder.shade(shutter, 0.75))

## the creek: a ribbon of moving water down the carved channel, stones along it, and its sound
func _build_creek(root: Node3D) -> void:
	var mb := MeshBuilder.new()
	var x := -150.0
	var prev_l := -1; var prev_r := -1
	while x <= 150.0:
		var zc := creek_z(x)
		var dz := (creek_z(x + 0.5) - creek_z(x - 0.5))
		var side := Vector2(-dz, 1.0).normalized() * 3.4
		var y := H(x, zc) + 0.55
		var l := mb.v(Vector3(x - side.x, y, zc - side.y), Vector3.UP, Color(1, 1, 1), Vector2(x * 0.12, 0.0))
		var rr := mb.v(Vector3(x + side.x, y, zc + side.y), Vector3.UP, Color(1, 1, 1), Vector2(x * 0.12, 1.0))
		if prev_l >= 0: mb.quad(prev_l, l, rr, prev_r)
		prev_l = l; prev_r = rr
		x += 2.0
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_always, specular_schlick_ggx;
uniform vec3 deep : source_color = vec3(0.07, 0.13, 0.12);
uniform vec3 shallow : source_color = vec3(0.22, 0.28, 0.2);
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 uv = UV * vec2(1.0, 3.0);
	float t = TIME * 0.35;
	float a = n(uv * 3.0 + vec2(t * 2.0, 0.0)); float b = n(uv * 5.0 - vec2(t * 2.6, t * 0.4));
	vec2 slope = vec2(a - 0.5, b - 0.5);
	NORMAL_MAP = normalize(vec3(slope * 0.5, 1.0)) * 0.5 + 0.5;
	float edge = smoothstep(0.0, 0.25, UV.y) * smoothstep(0.0, 0.25, 1.0 - UV.y);
	ALBEDO = mix(shallow, deep, edge);
	float foam = smoothstep(0.72, 0.9, n(uv * vec2(1.5, 4.0) + vec2(t * 3.0, 0.0))) * (1.0 - edge * 0.6);
	ALBEDO = mix(ALBEDO, vec3(0.75, 0.78, 0.74), foam * 0.35);
	ROUGHNESS = 0.14; METALLIC = 0.0; SPECULAR = 0.35;
	ALPHA = mix(0.6, 0.9, edge);
}
"""
	mat.shader = sh
	var mi := mb.instance(mat); mi.name = "Creek"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# the sound of running water, at a few spots along it
	var r := RandomNumberGenerator.new(); r.seed = seed + 61
	var gx := -140.0
	while gx <= 140.0:
		var ap := AudioStreamPlayer3D.new()
		ap.stream = Sfx.sounds.get("creek")
		ap.position = Vector3(gx, H(gx, creek_z(gx)) + 0.5, creek_z(gx))
		ap.unit_size = 6.0; ap.max_distance = 45.0; ap.volume_db = -6.0
		ap.autoplay = ap.stream != null
		root.add_child(ap)
		gx += 35.0

func _build_house(root: Node3D) -> void:
	var mb := MeshBuilder.new()
	var h := house
	var y0 := H(h.x, h.z)
	var r := RandomNumberGenerator.new(); r.seed = seed + 21
	var trim := Color.html("#f2f0ea"); var glass := Color.html("#34495a"); var found := Color.html("#8e8a82"); var sid: Color = h.siding
	var wood := Color.html("#9a7a56"); var deck := Color.html("#8a6c4a")
	var W: float = h.w; var D: float = h.d
	mb.push(Transform3D(Basis(), Vector3(h.x, y0, h.z)))
	# foundation: block courses sunk into the slope
	mb.box(0, -0.2, 0, W + 0.14, 1.3, D + 0.14, found)
	for k in range(3): mb.box(0, -0.1 + k * 0.2, 0, W + 0.15, 0.015, D + 0.15, MeshBuilder.shade(found, 0.78))
	# lap siding: each board with a shadow line under its lower edge
	var boards := 16
	var bh: float = h.wall / boards
	for b in range(boards):
		var yy: float = 0.45 + b * bh
		mb.box(0, yy + bh / 2, 0, W, bh, D, MeshBuilder.shade(sid, r.randf_range(0.97, 1.03)))
		mb.box(0, yy + 0.01, 0, W + 0.024, 0.02, D + 0.024, MeshBuilder.shade(sid, 0.72))
	var top: float = 0.45 + h.wall
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			mb.box(sx * W / 2, 0.45 + h.wall / 2, sz * D / 2, 0.17, h.wall, 0.17, trim)        # corner boards
	mb.box(0, top - 0.11, 0, W + 0.05, 0.22, D + 0.05, trim)                                    # frieze
	# gable roof: shingled, with soffits, fascia, rake boards and gutters
	var ov := 0.5; var ridge := top + 2.1; var hw: float = W / 2 + ov; var hd: float = D / 2 + ov
	var slope: float = (ridge - top) / (D / 2); var eave: float = top - slope * ov
	var roof: Color = h.roof
	var under := MeshBuilder.shade(roof, 0.5)
	mb.face([Vector3(-hw, eave, -hd), Vector3(hw, eave, -hd), Vector3(hw, ridge, 0), Vector3(-hw, ridge, 0)], under)
	mb.face([Vector3(hw, eave, hd), Vector3(-hw, eave, hd), Vector3(-hw, ridge, 0), Vector3(hw, ridge, 0)], under)
	_shingles(mb, -hw, hw, eave, -hd, ridge, 0.0, roof, r)
	_shingles(mb, -hw, hw, eave, hd, ridge, 0.0, roof, r)
	for k in range(int(2 * hw / 0.5)):
		var rx := -hw + 0.25 + k * 0.5
		mb.push(Transform3D(Basis(Vector3.RIGHT, 0.0), Vector3(rx, ridge + 0.03, 0)))
		mb.face([Vector3(-0.25, 0, -0.2), Vector3(0.25, 0, -0.2), Vector3(0.25, 0.06, 0), Vector3(-0.25, 0.06, 0)], MeshBuilder.shade(roof, r.randf_range(0.7, 0.85)))
		mb.face([Vector3(0.25, 0, 0.2), Vector3(-0.25, 0, 0.2), Vector3(-0.25, 0.06, 0), Vector3(0.25, 0.06, 0)], MeshBuilder.shade(roof, r.randf_range(0.65, 0.8)))
		mb.pop()
	for sx: float in [-1.0, 1.0]:
		var gx: float = sx * W / 2
		mb.face([Vector3(gx, top, -D / 2), Vector3(gx, top, D / 2), Vector3(gx, ridge - 0.02, 0)], sid)
		# gable siding lines and a louvred vent
		for k in range(1, 8):
			var gy := top + k * (ridge - top) / 8.0
			var half := (ridge - gy) / slope
			mb.box(gx + sx * 0.005, gy, 0, 0.012, 0.02, half * 2, MeshBuilder.shade(sid, 0.75))
		mb.box(gx + sx * 0.03, top + 1.15, 0, 0.05, 0.6, 0.5, trim)
		for k in range(5): mb.box(gx + sx * 0.06, top + 0.93 + k * 0.1, 0, 0.03, 0.03, 0.4, MeshBuilder.shade(trim, 0.7))
		# rake boards along the gable edges
		for sz: float in [-1.0, 1.0]:
			var a0 := Vector3(sx * (hw - 0.03), eave - 0.06, sz * hd); var a1 := Vector3(sx * (hw - 0.03), ridge - 0.04, 0)
			mb.tube(a0, a1, 0.07, 0.07, trim, 4)
	for sz: float in [-1.0, 1.0]:
		mb.box(0, eave - 0.03, sz * (D / 2 + ov / 2), W + 2 * ov, 0.05, ov, trim)            # soffit
		mb.box(0, eave - 0.06, sz * hd, W + 2 * ov, 0.22, 0.06, trim)                          # fascia
		# gutter and downspouts
		mb.box(0, eave - 0.06, sz * (hd + 0.08), W + 2 * ov, 0.12, 0.12, Color.html("#d8d6d0"))
		mb.box(0, eave - 0.0, sz * (hd + 0.08), W + 2 * ov, 0.02, 0.1, Color.html("#3a3a38"))
		for sx: float in [-1.0, 1.0]:
			var dx2 := sx * (W / 2 - 0.25)
			mb.box(dx2, (eave + 0.25) / 2, sz * (D / 2 + 0.08), 0.08, eave - 0.25, 0.08, Color.html("#d8d6d0"))
			mb.box(dx2, 0.22, sz * (D / 2 + 0.25), 0.08, 0.08, 0.35, Color.html("#d8d6d0"))
			mb.box(dx2, 0.16, sz * (D / 2 + 0.55), 0.3, 0.05, 0.4, Color.html("#9a958c"))      # splash block
	var fz: float = -D / 2 - 0.02; var bz: float = D / 2 + 0.02
	var shutter := MeshBuilder.shade(h.door, 0.9)
	for w in [[-W * 0.32, fz, -1.0], [W * 0.38, fz, -1.0], [-W * 0.3, bz, 1.0], [W * 0.05, bz, 1.0], [W * 0.35, bz, 1.0]]:
		_window(mb, w[0], 1.75, w[1], w[2], trim, glass, shutter)
	for sx: float in [-1.0, 1.0]:
		_window(mb, 0.0, 1.75, sx * (W / 2 + 0.02), sx, trim, glass, shutter, true, 0.9, 1.0)
	# front door: panelled, with a storm-door frame, knob and a light beside it
	var dx: float = W * 0.18
	mb.box(dx, 1.5, fz - 0.02, 1.16, 2.3, 0.1, trim)
	mb.box(dx, 1.47, fz - 0.06, 0.92, 2.1, 0.06, h.door)
	for py: float in [0.85, 1.55]:
		for px: float in [-0.2, 0.2]:
			mb.box(dx + px, py, fz - 0.095, 0.3, 0.5, 0.02, MeshBuilder.shade(h.door, 0.82))
	mb.box(dx, 2.25, fz - 0.095, 0.7, 0.28, 0.02, MeshBuilder.shade(glass, 1.2))
	mb.sphere(dx + 0.34, 1.45, fz - 0.13, 0.035, 0.035, 0.035, Color.html("#c9a640"), 8, 5)
	mb.box(dx + 0.8, 2.15, fz - 0.08, 0.14, 0.22, 0.1, Color.html("#2a2a28"))
	mb.box(dx + 0.8, 2.12, fz - 0.14, 0.09, 0.14, 0.05, Color.html("#ffe6a0"))
	# porch: a plank deck on posts, steps, railings with balusters, a shingled roof under the eave
	var pz0 := fz; var pz1 := fz - 2.5
	var deck_y := 0.44
	mb.box(dx, deck_y - 0.25, (pz0 + pz1) / 2, 3.2, 0.42, 2.4, MeshBuilder.shade(found, 0.9))
	for k in range(14):
		var bz2 := pz0 - 0.1 - k * 0.17
		mb.box(dx, deck_y - 0.02, bz2, 3.24, 0.05, 0.155, MeshBuilder.shade(deck, r.randf_range(0.88, 1.08)))
	for k in range(3):
		var sy := deck_y - 0.12 - k * 0.14
		mb.box(dx, sy - 0.03, pz1 - 0.1 - k * 0.3, 1.4, 0.06 + k * 0.0, 0.3, MeshBuilder.shade(deck, 0.95))
		mb.box(dx, (sy - 0.06) / 2 - 0.1, pz1 - 0.1 - k * 0.3, 1.36, sy, 0.27, MeshBuilder.shade(deck, 0.7))
	var p_in := eave - 0.12; var p_out := p_in - 0.5; var post_z := fz - 2.35
	var post_top := p_in + (p_out - p_in) * ((post_z - pz0) / (pz1 - pz0))
	for px: float in [-1.45, 1.45]:
		mb.box(dx + px, (deck_y + post_top) / 2, post_z, 0.15, post_top - deck_y, 0.15, trim)
		mb.box(dx + px, deck_y + 0.1, post_z, 0.22, 0.2, 0.22, trim)
		mb.box(dx + px, post_top - 0.1, post_z, 0.2, 0.08, 0.2, trim)
		# side railings back to the house
		mb.box(dx + px, deck_y + 0.9, (post_z + pz0) / 2, 0.08, 0.06, absf(post_z - pz0), trim)
		mb.box(dx + px, deck_y + 0.12, (post_z + pz0) / 2, 0.06, 0.05, absf(post_z - pz0), trim)
		for k in range(12):
			mb.box(dx + px, deck_y + 0.5, post_z + 0.15 + k * 0.17, 0.035, 0.76, 0.035, trim)
	# front railings either side of the steps
	for sx: float in [-1.0, 1.0]:
		var rx0 := dx + sx * 0.75; var rx1 := dx + sx * 1.45
		mb.box((rx0 + rx1) / 2, deck_y + 0.9, post_z, absf(rx1 - rx0), 0.06, 0.08, trim)
		mb.box((rx0 + rx1) / 2, deck_y + 0.12, post_z, absf(rx1 - rx0), 0.05, 0.06, trim)
		mb.box(rx0, deck_y + 0.48, post_z, 0.1, 0.96, 0.1, trim)
		for k in range(3): mb.box(rx0 + sx * (0.17 + k * 0.17), deck_y + 0.5, post_z, 0.035, 0.76, 0.035, trim)
	mb.box(dx, post_top - 0.06, post_z, 3.1, 0.16, 0.15, trim)
	var pr := MeshBuilder.shade(roof, 0.5)
	mb.face([Vector3(dx - 1.8, p_out, pz1), Vector3(dx + 1.8, p_out, pz1), Vector3(dx + 1.8, p_in, pz0), Vector3(dx - 1.8, p_in, pz0)], pr)
	_shingles(mb, dx - 1.8, dx + 1.8, p_out, pz1, p_in, pz0, roof, r)
	mb.face([Vector3(dx - 1.8, p_in - 0.02, pz0), Vector3(dx + 1.8, p_in - 0.02, pz0), Vector3(dx + 1.8, p_out - 0.02, pz1), Vector3(dx - 1.8, p_out - 0.02, pz1)], MeshBuilder.shade(trim, 0.9))
	mb.box(dx, p_in - 0.04, pz0 - 0.04, 3.6, 0.1, 0.08, trim); mb.box(dx, p_out - 0.05, pz1, 3.6, 0.16, 0.05, trim)
	# a rocking chair and a doormat
	var chx := dx - 0.95; var chz := pz0 - 0.9
	for sx: float in [-1.0, 1.0]:
		mb.push(Transform3D(Basis(), Vector3(chx + sx * 0.25, deck_y + 0.03, chz)))
		mb.box(0, 0.04, 0, 0.04, 0.05, 0.7, wood)                      # rocker
		mb.box(0, 0.25, 0.15, 0.04, 0.4, 0.04, wood); mb.box(0, 0.25, -0.15, 0.04, 0.4, 0.04, wood)
		mb.box(0, 0.62, 0.0, 0.04, 0.04, 0.42, wood)                    # arm
		mb.pop()
	mb.box(chx, deck_y + 0.45, chz, 0.5, 0.05, 0.45, wood)
	mb.push(Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(chx, deck_y + 0.78, chz + 0.25)))
	for k in range(5): mb.box(-0.2 + k * 0.1, 0, 0, 0.05, 0.62, 0.03, wood)
	mb.box(0, 0.32, 0, 0.5, 0.06, 0.04, wood)
	mb.pop()
	mb.box(dx, deck_y + 0.015, fz - 0.45, 0.8, 0.01, 0.5, Color.html("#6a4a30"))
	# chimney: brick courses with a cap
	var cx: float = -W * 0.3
	for k in range(13):
		var off := 0.02 if k % 2 else 0.0
		mb.box(cx + off, top + 0.15 + k * 0.25, D * 0.18, 0.8, 0.24, 0.8, MeshBuilder.shade(Color.html("#8a4a36"), r.randf_range(0.88, 1.08)))
		mb.box(cx, top + 0.15 + k * 0.25 + 0.125, D * 0.18, 0.81, 0.012, 0.81, Color.html("#b8b0a2"))
	mb.box(cx, top + 3.4, D * 0.18, 0.95, 0.1, 0.95, Color.html("#6a6a66"))
	mb.box(cx, top + 3.5, D * 0.18, 0.3, 0.14, 0.3, Color.html("#3a3a38"))
	# flower beds with shrubs along the front
	var bed_l := -W / 2 + 0.2; var bed_r := W / 2 - 0.2
	for seg: Vector2 in [Vector2(bed_l, dx - 1.75), Vector2(dx + 1.75, bed_r)]:
		if seg.y - seg.x > 0.3: mb.box((seg.x + seg.y) / 2, 0.06, fz - 0.55, seg.y - seg.x, 0.14, 0.9, Color.html("#4a3424"))
	for k in range(6):
		var sxp: float = -W / 2 + 0.7 + k * (W - 1.4) / 5
		if absf(sxp - dx) < 2.2: continue
		mb.blob(sxp, 0.4, fz - 0.55, 0.5, Color.html("#3f6a2e"), r, 0.9)
		mb.blob(sxp + 0.3, 0.25, fz - 0.7, 0.3, Color.html("#5a7a34"), r, 0.9)
	# air conditioner on the side, a hose reel, and a stacked firewood rack against the back wall
	var acx: float = W / 2 + 0.5
	mb.box(acx, 0.75, D * 0.2, 0.7, 0.6, 0.7, Color.html("#c8c6c0")); mb.box(acx, 1.06, D * 0.2, 0.72, 0.03, 0.72, Color.html("#8a8a86"))
	mb.cyl(acx, 1.08, D * 0.2, 0.25, 0.25, 0.01, Color.html("#3a3a38"), 12, true)
	mb.push(Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(-W / 2 - 0.15, 0.85, -D * 0.25)))
	mb.cyl(0, -0.12, 0, 0.22, 0.22, 0.24, Color.html("#3e6a3a"), 12, true, Color.html("#2a4a28"))
	mb.pop()
	var fwx: float = W * 0.1
	mb.box(fwx, 0.5, bz + 0.6, 2.4, 0.06, 0.5, Color.html("#3a3a38"))
	for sx: float in [-1.2, 1.2]: mb.box(fwx + sx, 1.0, bz + 0.6, 0.06, 1.1, 0.5, Color.html("#3a3a38"))
	for row in range(4):
		for k in range(10):
			mb.push(Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(fwx - 1.08 + k * 0.24 + (0.12 if row % 2 else 0.0), 0.65 + row * 0.22, bz + 0.6)))
			mb.cyl(0, -0.24, 0, 0.11, 0.11, 0.48, Color.html("#7a5a3c"), 6, true, Color.html("#c8a070"))
			mb.pop()
	# out back: a picnic table and a birdbath
	var ptx: float = -W * 0.28; var ptz: float = bz + 4.5
	var pw := Color.html("#8a6a48")
	mb.push(Transform3D(Basis(Vector3.UP, 0.25), Vector3(ptx, 0, ptz)))
	for k in range(5): mb.box(0, 0.76, -0.4 + k * 0.2, 1.9, 0.05, 0.18, MeshBuilder.shade(pw, r.randf_range(0.9, 1.08)))
	for sz: float in [-1.0, 1.0]:
		for k in range(2): mb.box(0, 0.45, sz * (0.72 + k * 0.14), 1.9, 0.05, 0.13, MeshBuilder.shade(pw, r.randf_range(0.9, 1.05)))
	for sx: float in [-0.7, 0.7]:
		for sz: float in [-1.0, 1.0]:
			mb.push(Transform3D(Basis(Vector3.RIGHT, sz * 0.5), Vector3(sx, 0.38, sz * 0.25)))
			mb.box(0, 0, 0, 0.08, 0.86, 0.1, MeshBuilder.shade(pw, 0.85))
			mb.pop()
		mb.box(sx, 0.42, 0, 0.08, 0.06, 1.8, MeshBuilder.shade(pw, 0.85))
	mb.pop()
	mb.cyl(W * 0.32, 0.0, bz + 3.0, 0.12, 0.08, 0.7, Color.html("#a8a49a"), 10, true)
	mb.cyl(W * 0.32, 0.7, bz + 3.0, 0.1, 0.38, 0.12, Color.html("#b0aca2"), 14, true)
	mb.cyl(W * 0.32, 0.8, bz + 3.0, 0.33, 0.33, 0.005, Color.html("#5a7a8a"), 14, true)
	mb.pop()
	_static_box(root, Vector3(h.x, y0 + 1.6, h.z), Vector3(h.w, 3.6, h.d))
	_static_box(root, Vector3(h.x + dx, y0 + 0.1, h.z + fz - 1.3), Vector3(3.2, 0.68, 2.4))
	for px in [-1.45, 1.45]:
		_static_box(root, Vector3(h.x + dx + px, y0 + 1.6, h.z + post_z), Vector3(0.16, 3.0, 0.16))
	# shed: board-and-batten walls, a Z-braced door, a little window, a shingled roof
	var sh := shed
	var sy := H(sh.x, sh.z)
	var sc := MeshBuilder.shade(sid, 0.9)
	var SW: float = sh.w; var SD: float = sh.d
	mb.push(Transform3D(Basis(), Vector3(sh.x, sy, sh.z)))
	mb.box(0, -0.05, 0, SW + 0.2, 0.3, SD + 0.2, MeshBuilder.shade(found, 0.95))
	mb.box(0, 1.1, 0, SW, 2.2, SD, sc)
	for k in range(int(SW / 0.3) + 1):
		var bx := -SW / 2 + 0.05 + k * 0.3
		for sz: float in [-1.0, 1.0]: mb.box(bx, 1.1, sz * (SD / 2 + 0.015), 0.05, 2.2, 0.03, MeshBuilder.shade(sc, 0.82))
	for k in range(int(SD / 0.3) + 1):
		var bzs := -SD / 2 + 0.05 + k * 0.3
		for sx: float in [-1.0, 1.0]: mb.box(sx * (SW / 2 + 0.015), 1.1, bzs, 0.03, 2.2, 0.05, MeshBuilder.shade(sc, 0.82))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]: mb.box(sx * SW / 2, 1.1, sz * SD / 2, 0.12, 2.2, 0.12, trim)
	var srw: float = SW / 2 + 0.3; var srd: float = SD / 2 + 0.3
	var s_slope: float = 0.9 / (SD / 2); var s_eave: float = 2.2 - s_slope * 0.3
	var sunder := MeshBuilder.shade(roof, 0.5)
	mb.face([Vector3(-srw, s_eave, -srd), Vector3(srw, s_eave, -srd), Vector3(srw, 3.1, 0), Vector3(-srw, 3.1, 0)], sunder)
	mb.face([Vector3(srw, s_eave, srd), Vector3(-srw, s_eave, srd), Vector3(-srw, 3.1, 0), Vector3(srw, 3.1, 0)], sunder)
	_shingles(mb, -srw, srw, s_eave, -srd, 3.1, 0.0, roof, r, 0.6)
	_shingles(mb, -srw, srw, s_eave, srd, 3.1, 0.0, roof, r, 0.6)
	mb.box(0, 3.13, 0, 2 * srw, 0.06, 0.18, MeshBuilder.shade(roof, 0.7))
	for sx: float in [-1.0, 1.0]:
		mb.face([Vector3(sx * SW / 2, 2.2, -SD / 2), Vector3(sx * SW / 2, 2.2, SD / 2), Vector3(sx * SW / 2, 3.08, 0)], sc)
		for sz: float in [-1.0, 1.0]:
			mb.tube(Vector3(sx * (srw - 0.03), s_eave - 0.04, sz * srd), Vector3(sx * (srw - 0.03), 3.08, 0), 0.05, 0.05, trim, 4)
	for sz: float in [-1.0, 1.0]: mb.box(0, s_eave - 0.04, sz * srd, 2 * srw, 0.14, 0.05, trim)
	var dzf := -SD / 2 - 0.05
	mb.box(0, 1.0, dzf, 1.2, 2.0, 0.05, trim)
	mb.box(0, 0.98, dzf - 0.02, 1.0, 1.9, 0.04, MeshBuilder.shade(sc, 0.75))
	for yy: float in [0.25, 1.0, 1.75]: mb.box(0, yy, dzf - 0.05, 1.0, 0.1, 0.03, trim)
	mb.push(Transform3D(Basis(Vector3.FORWARD, 0.95), Vector3(0, 0.62, dzf - 0.05)))
	mb.box(0, 0, 0, 0.09, 1.05, 0.03, trim)
	mb.pop()
	mb.push(Transform3D(Basis(Vector3.FORWARD, -0.95), Vector3(0, 1.38, dzf - 0.05)))
	mb.box(0, 0, 0, 0.09, 1.05, 0.03, trim)
	mb.pop()
	for yy: float in [0.4, 1.6]: mb.box(-0.48, yy, dzf - 0.07, 0.2, 0.05, 0.02, Color.html("#2a2a28"))
	mb.box(0.4, 1.0, dzf - 0.08, 0.04, 0.12, 0.03, Color.html("#2a2a28"))
	_window(mb, 0.0, 1.5, SW / 2 + 0.02, 1.0, trim, glass, sc, true, 0.6, 0.5)
	mb.face([Vector3(-0.6, 0.18, dzf - 0.05), Vector3(0.6, 0.18, dzf - 0.05), Vector3(0.6, -0.05, dzf - 0.6), Vector3(-0.6, -0.05, dzf - 0.6)], MeshBuilder.shade(deck, 0.85))
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

## grass tufts everywhere you walk (and longer meadow grass out toward the woods), swaying a little
func _build_grass(root: Node3D) -> void:
	var tuft := MeshBuilder.new()
	var r := RandomNumberGenerator.new(); r.seed = seed + 51
	var base := Color.html("#4f7330"); var tip := Color.html("#93b357")
	for i in range(6):
		var a := TAU * i / 6 + r.randf_range(-0.3, 0.3)
		var lean := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.04, 0.1)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.016
		var hgt := r.randf_range(0.12, 0.22)
		var off := Vector3(cos(a), 0, sin(a)) * 0.03
		var i0 := tuft.v(off - side, Vector3.UP, base); var i1 := tuft.v(off + side, Vector3.UP, base)
		var i2 := tuft.v(off + lean + Vector3(0, hgt, 0), Vector3.UP, tip)
		tuft.tri(i0, i1, i2)
	var mesh := tuft.commit()
	var spots: Array = []
	var ok := func(x: float, z: float) -> bool:
		if _box_dist(x, z, house) < 1.2 or _box_dist(x, z, shed) < 0.4: return false
		if absf(z - road_z) < 4.6: return false
		if Vector2(x, z).distance_to(Vector2(tree.x, tree.z)) < 0.9: return false
		for i in range(0, drive_path.size(), 2):
			if Vector2(x, z).distance_to(drive_path[i]) < 2.3: return false
		return true
	var gx := -46.0
	while gx < 46.0:
		var gz := -48.0
		while gz < 52.0:
			var x := gx + r.randf() * 0.42; var z := gz + r.randf() * 0.42
			if ok.call(x, z): spots.append([x, z, r.randf_range(0.8, 1.25)])
			gz += 0.42
		gx += 0.42

	# chunk the lawn into 16 m tiles so only the grass near the camera is drawn
	var chunks := {}
	for sp: Array in spots:
		var key := Vector2i(floori(float(sp[0]) / 16.0), floori(float(sp[1]) / 16.0))
		if not chunks.has(key): chunks[key] = []
		chunks[key].append(sp)
	for key in chunks:
		var list: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in range(list.size()):
			var sp: Array = list[i]
			var x: float = sp[0]; var z: float = sp[1]; var sc: float = sp[2]
			var xf := Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(sc, sc * r.randf_range(0.8, 1.2), sc)), Vector3(x, H(x, z) - 0.01, z))
			mm.set_instance_transform(i, xf)
			var tint := Color(1, 1, 1)
			if r.randf() < 0.15: tint = Color(1.08, 1.04, 0.8)
			mm.set_instance_color(i, MeshBuilder.shade(tint, r.randf_range(0.85, 1.1)))
		var mmi := MultiMeshInstance3D.new(); mmi.name = "Grass"
		mmi.multimesh = mm
		mmi.material_override = Mats.grass
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 38.0
		mmi.visibility_range_end_margin = 6.0
		mmi.set_meta("vr", Vector2(0.0, 38.0))
		mmi.layers = 2
		root.add_child(mmi)
