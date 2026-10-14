## Low-poly mesh builder with vertex colours and a transform stack.
## Every model in the game (truck, house, Earl, the saw...) is built from these primitives in code.
class_name MeshBuilder
extends RefCounted

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var idx := PackedInt32Array()
var uvs := PackedVector2Array()
var has_uv := false
var _stack: Array[Transform3D] = []
var xf := Transform3D.IDENTITY

static func hex(s: String) -> Color:
	return Color.html(s)

static func shade(c: Color, k: float) -> Color:
	return Color(clampf(c.r * k, 0, 1), clampf(c.g * k, 0, 1), clampf(c.b * k, 0, 1), c.a)

func push(t: Transform3D) -> void:
	_stack.push_back(xf)
	xf = xf * t

func pop() -> void:
	xf = _stack.pop_back()

func v(p: Vector3, n: Vector3, c: Color, uv := Vector2.ZERO) -> int:
	if uv != Vector2.ZERO: has_uv = true
	uvs.push_back(uv)
	verts.push_back(xf * p)
	norms.push_back((xf.basis * n).normalized())
	cols.push_back(c)
	return verts.size() - 1

## primitives are written counter-clockwise with right-hand normals; Godot's front faces are clockwise, so flip here
## (a mirrored transform flips the winding back)
func tri(a: int, b: int, c: int) -> void:
	if xf.basis.determinant() < 0:
		idx.push_back(a); idx.push_back(b); idx.push_back(c)
	else:
		idx.push_back(a); idx.push_back(c); idx.push_back(b)

func quad(a: int, b: int, c: int, d: int) -> void:
	tri(a, b, c); tri(a, c, d)

## axis-aligned box centred at (x,y,z) with full sizes w,h,d
func box(x: float, y: float, z: float, w: float, h: float, d: float, c: Color) -> void:
	var hx := w * 0.5; var hy := h * 0.5; var hz := d * 0.5
	var faces := [
		[Vector3(1, 0, 0), [Vector3(hx, -hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(hx, -hy, hz)]],
		[Vector3(-1, 0, 0), [Vector3(-hx, -hy, hz), Vector3(-hx, hy, hz), Vector3(-hx, hy, -hz), Vector3(-hx, -hy, -hz)]],
		[Vector3(0, 1, 0), [Vector3(-hx, hy, -hz), Vector3(-hx, hy, hz), Vector3(hx, hy, hz), Vector3(hx, hy, -hz)]],
		[Vector3(0, -1, 0), [Vector3(-hx, -hy, hz), Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz)]],
		[Vector3(0, 0, 1), [Vector3(hx, -hy, hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz), Vector3(-hx, -hy, hz)]],
		[Vector3(0, 0, -1), [Vector3(-hx, -hy, -hz), Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, -hy, -hz)]],
	]
	var o := Vector3(x, y, z)
	for f in faces:
		var n: Vector3 = f[0]
		var q: Array = f[1]
		var i0 := v(o + q[0], n, c); var i1 := v(o + q[1], n, c); var i2 := v(o + q[2], n, c); var i3 := v(o + q[3], n, c)
		quad(i0, i1, i2, i3)

## cylinder / cone along +Y starting at (x,y,z)
func cyl(x: float, y: float, z: float, r0: float, r1: float, h: float, c: Color, seg := 10, caps := true, cap_col = null) -> void:
	var o := Vector3(x, y, z)
	var ring0 := []; var ring1 := []
	var slope := (r0 - r1) / maxf(h, 1e-4)
	for s in range(seg + 1):
		var a := TAU * s / seg
		var n := Vector3(cos(a), slope, sin(a)).normalized()
		ring0.push_back(v(o + Vector3(cos(a) * r0, 0, sin(a) * r0), n, c))
		ring1.push_back(v(o + Vector3(cos(a) * r1, h, sin(a) * r1), n, c))
	for s in range(seg):
		quad(ring0[s], ring1[s], ring1[s + 1], ring0[s + 1])
	if caps:
		var cc: Color = c if cap_col == null else cap_col
		_disk(o, r0, -1.0, cc, seg)
		if r1 > 1e-4:
			_disk(o + Vector3(0, h, 0), r1, 1.0, cc, seg)

func _disk(o: Vector3, r: float, up: float, c: Color, seg: int) -> void:
	var n := Vector3(0, up, 0)
	var ci := v(o, n, c)
	var ring := []
	for s in range(seg + 1):
		var a := TAU * s / seg
		ring.push_back(v(o + Vector3(cos(a) * r, 0, sin(a) * r), n, c))
	for s in range(seg):
		if up > 0: tri(ci, ring[s + 1], ring[s])
		else: tri(ci, ring[s], ring[s + 1])

## tapered tube from a to b
func tube(a: Vector3, b: Vector3, r0: float, r1: float, c: Color, seg := 8, caps := false, cap_col = null) -> void:
	var d := b - a
	var L := d.length()
	if L < 1e-6: return
	var q := Quaternion(Vector3.UP, d / L) if not (d / L).is_equal_approx(Vector3.DOWN) else Quaternion(Vector3.RIGHT, PI)
	push(Transform3D(Basis(q), a))
	cyl(0, 0, 0, r0, r1, L, c, seg, caps, cap_col)
	pop()

## ellipsoid
func sphere(x: float, y: float, z: float, rx: float, ry: float, rz: float, c: Color, seg := 10, rings := 6) -> void:
	var o := Vector3(x, y, z)
	var grid := []
	for j in range(rings + 1):
		var t := PI * j / rings
		var row := []
		for s in range(seg + 1):
			var a := TAU * s / seg
			var u := Vector3(sin(t) * cos(a), cos(t), sin(t) * sin(a))
			row.push_back(v(o + Vector3(u.x * rx, u.y * ry, u.z * rz), Vector3(u.x / rx, u.y / ry, u.z / rz).normalized(), c))
		grid.push_back(row)
	for j in range(rings):
		for s in range(seg):
			quad(grid[j][s], grid[j][s + 1], grid[j + 1][s + 1], grid[j + 1][s])

## soft foliage clump: a once-subdivided icosphere, lumpy, smooth-shaded, darker underneath and sunlit on top
func blob(x: float, y: float, z: float, r: float, c: Color, rng: RandomNumberGenerator, rough := 0.8) -> void:
	var o := Vector3(x, y, z)
	var t := (1.0 + sqrt(5.0)) / 2.0
	var P: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var F := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for i in range(P.size()): P[i] = (P[i] as Vector3).normalized()
	var mid := {}
	var midpoint := func(i: int, j: int) -> int:
		var key := Vector2i(mini(i, j), maxi(i, j))
		if mid.has(key): return mid[key]
		P.append(((P[i] as Vector3) + (P[j] as Vector3)).normalized())
		mid[key] = P.size() - 1
		return P.size() - 1
	var F2 := []
	for f in F:
		var a: int = midpoint.call(f[0], f[1]); var b: int = midpoint.call(f[1], f[2]); var cc: int = midpoint.call(f[2], f[0])
		F2.append_array([[f[0], a, cc], [f[1], b, a], [f[2], cc, b], [a, b, cc]])
	var ids := []
	for p in P:
		var k := 1.0 + (rng.randf() - 0.5) * 0.3 * rough
		var q: Vector3 = p * r * k * Vector3(1, 0.82, 1)
		var lit := 0.72 + 0.36 * clampf(p.y * 0.5 + 0.5, 0, 1) + (rng.randf() - 0.5) * 0.08
		ids.append(v(o + q, p, shade(c, lit)))
	for f in F2:
		tri(ids[f[0]], ids[f[2]], ids[f[1]])

## flat polygon (fan), winding sets the normal
func face(p: Array, c: Color) -> void:
	var n: Vector3 = (p[2] - p[0]).cross(p[1] - p[0]).normalized()
	var ids := []
	for q in p: ids.push_back(v(q, n, c))
	for i in range(1, p.size() - 1):
		tri(ids[0], ids[i + 1], ids[i])

## a textured card: centre c, half-extent vectors ax (u) and ay (v), uv rect [u0,v0,u1,v1].
## nrm is the lighting normal (foliage uses soft "round" normals rather than the card's own)
func card(c: Vector3, ax: Vector3, ay: Vector3, col: Color, nrm: Vector3, uvr := Vector4(0, 0, 1, 1), sway_lo := 0.0, sway_hi := 1.0) -> void:
	var c0 := Color(col.r, col.g, col.b, sway_lo); var c1 := Color(col.r, col.g, col.b, sway_hi)
	var a := v(c - ax - ay, nrm, c0, Vector2(uvr.x, uvr.w))
	var b := v(c + ax - ay, nrm, c0, Vector2(uvr.z, uvr.w))
	var d := v(c + ax + ay, nrm, c1, Vector2(uvr.z, uvr.y))
	var e := v(c - ax + ay, nrm, c1, Vector2(uvr.x, uvr.y))
	quad(a, b, d, e)

## a box with its edges chamfered by r (reads as a rounder, less blocky shape)
func bevel_box(x: float, y: float, z: float, w: float, h: float, d: float, c: Color, r := 0.03) -> void:
	r = minf(r, minf(w, minf(h, d)) * 0.45)
	var hx := w * 0.5; var hy := h * 0.5; var hz := d * 0.5
	var o := Vector3(x, y, z)
	# the 6 faces, each inset by r
	box(x, y, z, w - 2 * r, h, d - 2 * r, c)
	box(x, y, z, w, h - 2 * r, d - 2 * r, c)
	box(x, y, z, w - 2 * r, h - 2 * r, d, c)
	# chamfer strips along the 12 edges
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			_chamfer(o + Vector3(sx * (hx - r), sy * (hy - r), 0), Vector3(sx, 0, 0), Vector3(0, sy, 0), Vector3(0, 0, hz - r), r, c)
		for sz in [-1.0, 1.0]:
			_chamfer(o + Vector3(sx * (hx - r), 0, sz * (hz - r)), Vector3(sx, 0, 0), Vector3(0, 0, sz), Vector3(0, hy - r, 0), r, c)
	for sy in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_chamfer(o + Vector3(0, sy * (hy - r), sz * (hz - r)), Vector3(0, sy, 0), Vector3(0, 0, sz), Vector3(hx - r, 0, 0), r, c)

func _chamfer(edge: Vector3, a: Vector3, b: Vector3, half_len: Vector3, r: float, c: Color) -> void:
	var p0 := edge + a * r; var p1 := edge + b * r
	var nn := (a + b).normalized()
	var i0 := v(p0 - half_len, nn, c); var i1 := v(p1 - half_len, nn, c); var i2 := v(p1 + half_len, nn, c); var i3 := v(p0 + half_len, nn, c)
	var face_n := (p1 - p0).cross(half_len)
	if face_n.dot(nn) > 0: quad(i0, i1, i2, i3)
	else: quad(i0, i3, i2, i1)

func is_empty() -> bool:
	return idx.is_empty()

func commit(mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null: mesh = ArrayMesh.new()
	if idx.is_empty(): return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	if has_uv: arr[Mesh.ARRAY_TEX_UV] = uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

## a MeshInstance3D with the shared vertex-colour material
func instance(mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = commit()
	mi.material_override = mat if mat != null else Mats.vcol
	return mi
