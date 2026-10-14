## The problem tree's shape and the solid geometry for every piece of wood.
## Everything is described in the tree's "wood frame": origin at the base of the trunk on the ground,
## +Y up the stem. Pieces keep wood-frame coordinates (a piece's body origin IS the wood frame),
## so cutting one just adds another operation to its list:
##   clip   — remove everything on the +n side of a plane      (a finished cut, an end)
##   kerf   — remove the slab the chain has eaten so far          (a cut in progress)
##   prism  — remove a convex wedge                              (an open notch)
##   keep   — keep only the inside of a box                       (a barber-chair slab)
## The trunk is a real solid (Godot CSG), so cut faces are exact at any angle.
class_name Wood
extends RefCounted

const RHO := 640.0          # dead ash, kg/m³
const LIFT_MAX := 60.0      # kg you can shoulder
const DRAG_MAX := 200.0 / 2.205
const CUT_SPEED := 0.32     # m/s of bar travel through wood at full throttle (a sharp chain)
const GAME_MASS := 0.2      # pieces weigh a fifth of real ash, so a sensible number of rounds gets you a liftable pile
const KERF := 0.0075        # half the width of the slot the chain removes

## ---------------------------------------------------------------- tree definition
static func make_tree_def(t: Dictionary) -> Dictionary:
	var R := RandomNumberGenerator.new(); R.seed = t.seed
	var H: float = t.h
	var T := {H = H, dbh = t.dbh, seed = t.seed, limbs = []}
	T.k = (t.dbh / 2.0) / _shape(1.37, H)
	T.cb = H * R.randf_range(0.38, 0.46)
	var n := R.randi_range(9, 12)
	for i in range(n):
		var f := (i + R.randf_range(0.1, 0.9)) / n
		var y: float = T.cb + f * (H * 0.9 - T.cb)
		var az := i * 2.39996 + R.randf_range(-0.4, 0.4)
		var el := lerpf(0.42, 1.05, f) + R.randf_range(-0.15, 0.15)
		var dir := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el)).normalized()
		var len := clampf((H - y) * 0.5 + R.randf_range(1.2, 2.4), 1.6, 5.6)
		var r0 := minf(0.085, r_at(T, y) * R.randf_range(0.45, 0.6))
		var base := Vector3(0, y, 0) + Vector3(dir.x, 0, dir.z) * r_at(T, y) * 0.6
		var subs := []
		for s in range(R.randi_range(2, 3)):
			var tt := R.randf_range(0.3, 0.78)
			var side := 1.0 if R.randf_range(-1, 1) > 0 else -1.0
			var ax := dir.cross(Vector3.UP).normalized()
			var sd := (dir + ax * side * R.randf_range(0.5, 0.9) + Vector3(0, R.randf_range(0.2, 0.6), 0)).normalized()
			var sb := {t = tt, dir = sd, len = len * R.randf_range(0.3, 0.48), r0 = r0 * (1 - 0.7 * tt) * 0.75, twigs = []}
			for k in range(3):
				sb.twigs.append({tt = R.randf_range(0.4, 1), dir = (sd + Vector3(R.randf_range(-0.8, 0.8), R.randf_range(0, 0.6), R.randf_range(-0.8, 0.8))).normalized(), len = R.randf_range(0.3, 0.7)})
			subs.append(sb)
		var tips := []
		for k in range(4):
			tips.append({dir = (dir + Vector3(R.randf_range(-0.9, 0.9), R.randf_range(-0.2, 0.7), R.randf_range(-0.9, 0.9))).normalized(), len = R.randf_range(0.4, 0.9)})
		T.limbs.append({id = i, y = y, dir = dir, len = len, r0 = r0, base = base, subs = subs, tips = tips})
	return T

static func _shape(y: float, H: float) -> float:
	return pow(maxf(0, 1 - y / H), 0.85) * (1 + 0.38 * exp(-maxf(y, 0) / 0.35))

static func r_at(T: Dictionary, y: float) -> float:
	return maxf(0.018, T.k * _shape(clampf(y, 0, T.H), T.H))

static func limb_pt(L: Dictionary, t: float) -> Vector3:
	return L.base + L.dir * L.len * t

static func limb_r(L: Dictionary, t: float) -> float:
	return L.r0 * (1 - 0.72 * t)

## ---------------------------------------------------------------- solid trunk mesh for CSG
## a closed, watertight tapered cylinder from ya to yb (shared ring vertices so CSG sees a manifold)
static func trunk_mesh(T: Dictionary, ya: float, yb: float, seg := 20) -> ArrayMesh:
	var ys := []
	var y := ya
	while y < yb - 0.05:
		ys.append(y); y += 0.3
	ys.append(yb)
	var v := PackedVector3Array(); var nrm := PackedVector3Array(); var idx := PackedInt32Array()
	for yy in ys:
		var r := r_at(T, maxf(yy, 0.0))
		for s in range(seg):
			var a := TAU * s / seg
			v.append(Vector3(cos(a) * r, yy, sin(a) * r)); nrm.append(Vector3(cos(a), 0.1, sin(a)).normalized())
	var rings: int = ys.size()
	# sides (CW seen from outside = Godot front faces)
	for j in range(rings - 1):
		for s in range(seg):
			var a0 := j * seg + s; var a1 := j * seg + (s + 1) % seg
			var b0 := (j + 1) * seg + s; var b1 := (j + 1) * seg + (s + 1) % seg
			idx.append_array([a0, b1, b0, a0, a1, b1])
	var cb := v.size(); v.append(Vector3(0, ys[0], 0)); nrm.append(Vector3.DOWN)
	var ct := v.size(); v.append(Vector3(0, ys[rings - 1], 0)); nrm.append(Vector3.UP)
	for s in range(seg):
		var s1 := (s + 1) % seg
		idx.append_array([cb, s1, s])
		var top := (rings - 1) * seg
		idx.append_array([ct, top + s, top + s1])
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v; arr[Mesh.ARRAY_NORMAL] = nrm; arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new(); m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## closed triangular prism from 6 points [A0,B0,C0, A1,B1,C1] (a notch wedge), wound for CSG
static func prism_mesh(P: Array) -> ArrayMesh:
	var c := Vector3.ZERO
	for p in P: c += p
	c /= 6.0
	var v := PackedVector3Array(P)
	var idx := PackedInt32Array()
	var tri := func(a: int, b: int, d: int) -> void:
		var n: Vector3 = (v[b] - v[a]).cross(v[d] - v[a])
		var fc: Vector3 = (v[a] + v[b] + v[d]) / 3.0
		if n.dot(fc - c) > 0: idx.append_array([a, d, b])   # Godot fronts are clockwise from outside
		else: idx.append_array([a, b, d])
	tri.call(0, 1, 2); tri.call(3, 4, 5)
	for q in [[0, 1, 4, 3], [1, 2, 5, 4], [2, 0, 3, 5]]:
		tri.call(q[0], q[1], q[2]); tri.call(q[0], q[2], q[3])
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v; arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new(); m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## ---------------------------------------------------------------- operations → CSG nodes
static func op_node(op: Dictionary) -> CSGShape3D:
	match op.type:
		"clip":
			var b := CSGBox3D.new(); b.size = Vector3(8, 8, 8)
			b.transform = Transform3D(_basis_y(op.n), op.p + op.n * (4.0 + op.get("gap", 0.0)))
			b.operation = CSGShape3D.OPERATION_SUBTRACTION; b.material = Mats.sap
			return b
		"kerf":
			var b := CSGBox3D.new()
			_place_kerf(b, op)
			b.operation = CSGShape3D.OPERATION_SUBTRACTION; b.material = Mats.sap
			return b
		"prism":
			var m := CSGMesh3D.new(); m.mesh = op.mesh
			m.operation = CSGShape3D.OPERATION_SUBTRACTION; m.material = Mats.sap
			return m
		"keep":
			var b := CSGBox3D.new(); b.size = op.size; b.transform = op.xf
			b.operation = CSGShape3D.OPERATION_INTERSECTION; b.material = Mats.sap
			return b
		"cutbox":
			var b := CSGBox3D.new(); b.size = op.size; b.transform = op.xf
			b.operation = CSGShape3D.OPERATION_SUBTRACTION; b.material = Mats.sap
			return b
	return null

## how far either side of the entry point the kerf reaches: a fresh nick is narrow, a deep cut spans the log
static func kerf_half_width(s: float) -> float:
	return 0.035 + 0.9 * s

## a kerf: the slab the bar has swept, from outside the bark to the cut front s along f
static func _place_kerf(b: CSGBox3D, op: Dictionary) -> void:
	var n: Vector3 = op.n; var f: Vector3 = op.f
	var g := n.cross(f).normalized()
	var back := 0.03      # only wood the bar has actually passed through: nothing behind the entry point
	var len: float = maxf(op.s, 0.001) + back
	b.size = Vector3(kerf_half_width(op.s) * 2.0, KERF * 2.0, len)
	b.transform = Transform3D(Basis(g, n, f), op.e + f * (op.s - len / 2.0))

static func update_kerf(node: CSGShape3D, op: Dictionary) -> void:
	if node is CSGBox3D: _place_kerf(node, op)

static func _basis_y(n: Vector3) -> Basis:
	var a := Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD
	var x := a.cross(n).normalized()
	var z := x.cross(n).normalized()
	return Basis(x, n, z).orthonormalized()

## which side of a clip a wood-frame point is on (true = kept)
static func kept(ops: Array, p: Vector3) -> bool:
	for op in ops:
		if op.type == "clip" and op.n.dot(p - op.p) > 0: return false
		if op.type == "keep":
			var l: Vector3 = op.xf.affine_inverse() * p
			if absf(l.x) > op.size.x / 2 or absf(l.y) > op.size.y / 2 or absf(l.z) > op.size.z / 2: return false
	return true

## the stem height range a set of clips leaves (axis crossings, widened by the slope of each plane)
static func y_span(T: Dictionary, ops: Array, ya: float, yb: float) -> Vector2:
	var lo := ya; var hi := yb
	for op in ops:
		if op.type != "clip": continue
		var n: Vector3 = op.n
		if absf(n.y) < 0.05: continue
		var yc: float = op.p.y + (n.x * op.p.x + n.z * op.p.z) / n.y
		var r := r_at(T, clampf(yc, 0, T.H))
		var ext := r * Vector2(n.x, n.z).length() / absf(n.y)
		if n.y > 0: hi = minf(hi, yc + ext)       # removes above
		else: lo = maxf(lo, yc - ext)              # removes below
	return Vector2(lo, hi)
