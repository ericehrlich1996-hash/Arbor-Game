## A loose piece of the tree: the felled stem, a round, a cookie, a limb, a notch wedge, a barber slab.
## The body's origin is the tree's wood frame, so all geometry (and every cut) is in wood-frame coordinates.
class_name WoodPiece
extends RigidBody3D

var T: Dictionary
var kind := "trunk"              # trunk | limb | wedge | slab
var ops: Array = []              # clip / kerf / prism / keep / cutbox (see Wood)
var y0 := 0.0
var y1 := 0.0
var limbs: Array = []            # limb ids still on a trunk piece
var lt := {}                     # limb id -> how far along (0..1) the limb still reaches
var stubs: Array = []            # limb ids cut off at the collar (a short stub stays)
var limb := -1                   # for a limb piece
var t0 := 0.0
var t1 := 1.0
var wedge_pts: Array = []        # for a notch wedge
var volume := 0.0
var csg: CSGCombiner3D
var mode := "dyn"                # dyn | held | feed | gone
var span := Vector2.ZERO
var still_t := 0.0

func _init() -> void:
	collision_layer = 8
	collision_mask = 1 | 4 | 8 | 32 | 64
	continuous_cd = true
	can_sleep = true
	var pm := PhysicsMaterial.new(); pm.friction = 0.85; pm.bounce = 0.05
	physics_material_override = pm
	linear_damp = 0.05
	angular_damp = 0.3

func is_round() -> bool:
	return kind == "trunk" and limbs.is_empty()

func is_brush() -> bool:
	return kind == "limb"

## anything the chipper will take: brush, notch wedges, a liftable top still wearing its branches,
## and any little round under ten pounds
const CHIP_MAX := 4.54          # kg (10 lb)
func chippable() -> bool:
	if kind == "limb" or kind == "wedge": return true
	if kind == "trunk" and not limbs.is_empty() and mass <= Wood.LIFT_MAX: return true
	return mass < CHIP_MAX

## carried under the arm like brush (rather than a round on the shoulder)
func brushy() -> bool:
	return kind == "limb" or kind == "wedge" or (kind == "trunk" and not limbs.is_empty())

func label() -> String:
	if kind == "limb" or (kind == "trunk" and not limbs.is_empty()): return "brush"
	if kind == "wedge": return "wedge"
	if kind == "slab": return "slab"
	return "round" if limbs.is_empty() else "stem"

## (re)build mesh, CSG and collision from the definition
func build() -> void:
	for c in get_children(): c.queue_free()
	csg = null
	volume = 0.0
	match kind:
		"trunk": _build_trunk()
		"limb": _build_limb_piece()
		"wedge": _build_wedge()
		"slab": _build_slab()
	for id in limbs: _add_limb(T.limbs[id], 0.0, lt.get(id, 1.0), true)
	if not stubs.is_empty():
		var mb := MeshBuilder.new()
		for id in stubs:
			var L: Dictionary = T.limbs[id]
			if L.y < span.x or L.y > span.y: continue
			mb.tube(L.base, L.base + L.dir * 0.06, L.r0 * 1.05, L.r0, Color.WHITE, 7, false)
		if not mb.is_empty():
			var mi := mb.instance(Mats.bark); add_child(mi)
	mass = maxf(0.3, volume * Wood.RHO * Wood.GAME_MASS)
	collision_layer = 64 if kind == "limb" else 8     # you walk through brush, not over logs

func _build_trunk() -> void:
	span = Wood.y_span(T, ops, y0, y1)
	var ya := maxf(-0.45, span.x - 0.15); var yb := minf(T.H, span.y + 0.15)
	csg = CSGCombiner3D.new()
	var tm := CSGMesh3D.new(); tm.mesh = Wood.trunk_mesh(T, ya, yb); tm.material = Mats.bark
	csg.add_child(tm)
	for op in ops:
		var n := Wood.op_node(op)
		if n:
			csg.add_child(n)
			if op.type == "kerf": op.node = n
	add_child(csg)
	# collision: the convex shell of what the clips leave (rings of points between the cut planes)
	var pts := PackedVector3Array()
	var seg := 16
	var nr := maxi(2, int(ceil((span.y - span.x) / 0.25)) + 1)
	for s in range(seg):
		var a := TAU * s / seg
		var dx := cos(a); var dz := sin(a)
		var lo := span.x; var hi := span.y
		var r_lo := Wood.r_at(T, maxf(lo, 0.0)); var r_hi := Wood.r_at(T, maxf(hi, 0.0))
		for it in range(2):   # the end heights depend on the radius there; settle in two passes
			var x0 := dx * r_lo; var z0 := dz * r_lo; var x1 := dx * r_hi; var z1 := dz * r_hi
			lo = span.x; hi = span.y
			var lo2 := _y_bound(x0, z0, true); var hi2 := _y_bound(x1, z1, false)
			lo = clampf(lo2, span.x - 1, span.y); hi = clampf(hi2, lo + 0.01, span.y + 1)
			r_lo = Wood.r_at(T, maxf(lo, 0.0)); r_hi = Wood.r_at(T, maxf(hi, 0.0))
		for i in range(nr):
			var yy := lerpf(lo, hi, float(i) / (nr - 1))
			var r := Wood.r_at(T, maxf(yy, 0.0))
			pts.append(Vector3(dx * r, yy, dz * r))
	var cs := CollisionShape3D.new()
	var cv := ConvexPolygonShape3D.new(); cv.points = pts
	cs.shape = cv; cs.set_meta("part", {trunk = true})
	add_child(cs)
	# volume: slices along the axis
	var n := 24
	for i in range(n):
		var yy := lerpf(span.x, span.y, (i + 0.5) / n)
		var r := Wood.r_at(T, maxf(yy, 0.0))
		volume += PI * r * r * (span.y - span.x) / n

## lowest (or highest) kept height on the vertical line through (x,z)
func _y_bound(x: float, z: float, low: bool) -> float:
	var b := span.x if low else span.y
	for op in ops:
		if op.type != "clip": continue
		var nn: Vector3 = op.n
		if absf(nn.y) < 0.05: continue
		var yc: float = op.p.y - (nn.x * (x - op.p.x) + nn.z * (z - op.p.z)) / nn.y
		if low and nn.y < 0: b = maxf(b, yc)
		elif not low and nn.y > 0: b = minf(b, yc)
	return b

func _add_limb(L: Dictionary, ta: float, tb: float, on_trunk: bool) -> void:
	var mb := MeshBuilder.new(); var caps := MeshBuilder.new()
	var segs := maxi(1, int(round((tb - ta) * 4)))
	for i in range(segs):
		var a := ta + (tb - ta) * i / segs; var b := ta + (tb - ta) * (i + 1) / segs
		mb.tube(Wood.limb_pt(L, a), Wood.limb_pt(L, b), Wood.limb_r(L, a), Wood.limb_r(L, b), Color.WHITE, 7, false)
	var sap := Color("#e6d3a6")
	var cap_at := func(t: float, sgn: float) -> void:
		var p := Wood.limb_pt(L, t); var r := Wood.limb_r(L, t) * 0.99
		caps.push(Transform3D(Basis(Quaternion(Vector3.UP, L.dir * sgn)), p))
		caps.cyl(0, 0, 0, r, r, 0.002, sap, 7, true, sap)
		caps.pop()
	if not on_trunk or ta > 0: cap_at.call(ta, -1.0)
	if tb < 1: cap_at.call(tb, 1.0)
	var li := 0
	for sb in L.subs:
		if sb.t < ta or sb.t > tb: li += 1; continue
		var o := Wood.limb_pt(L, sb.t); var e: Vector3 = o + sb.dir * sb.len
		mb.tube(o, e, sb.r0, sb.r0 * 0.35, Color.WHITE, 5)
		for tw in sb.twigs:
			var tp := o.lerp(e, tw.tt)
			mb.tube(tp, tp + tw.dir * tw.len, sb.r0 * 0.35, 0.006, Color(1.08, 1.08, 1.08), 4)
		_capsule(o, e, sb.r0 * 0.9, {limb = L.id, sub = li})
		volume += PI * sb.r0 * sb.r0 * 0.4 * sb.len
		li += 1
	if tb >= 1:
		var tip := Wood.limb_pt(L, 1)
		for tw in L.tips:
			mb.tube(tip, tip + tw.dir * tw.len, Wood.limb_r(L, 1) * 0.8, 0.006, Color(1.06, 1.06, 1.06), 4)
			_capsule(tip, tip + tw.dir * tw.len, 0.012, {limb = L.id, tip = true})
	_capsule(Wood.limb_pt(L, ta), Wood.limb_pt(L, tb), Wood.limb_r(L, (ta + tb) / 2) * 1.05, {limb = L.id})
	var rm := Wood.limb_r(L, (ta + tb) / 2)
	volume += PI * rm * rm * L.len * (tb - ta)
	var mi := mb.instance(Mats.bark); add_child(mi)
	if not caps.is_empty(): add_child(caps.instance(Mats.sap_v))

func _capsule(a: Vector3, b: Vector3, r: float, part: Dictionary) -> void:
	var d := b - a; var L := d.length()
	if L < 1e-4: return
	var cs := CollisionShape3D.new()
	var c := CapsuleShape3D.new(); c.radius = maxf(r, 0.01); c.height = maxf(L + 2 * c.radius, 2 * c.radius + 0.001)
	cs.shape = c
	cs.transform = Transform3D(Basis(Quaternion(Vector3.UP, d / L)), (a + b) * 0.5)
	cs.set_meta("part", part)
	add_child(cs)

func _build_limb_piece() -> void:
	var L: Dictionary = T.limbs[limb]
	_add_limb(L, t0, t1, false)
	span = Vector2(L.y, L.y)

func _build_wedge() -> void:
	csg = CSGCombiner3D.new()
	var tm := CSGMesh3D.new(); tm.mesh = Wood.trunk_mesh(T, y0, y1); tm.material = Mats.bark
	csg.add_child(tm)
	var keep := CSGMesh3D.new(); keep.mesh = Wood.prism_mesh(wedge_pts); keep.operation = CSGShape3D.OPERATION_INTERSECTION; keep.material = Mats.sap
	csg.add_child(keep)
	add_child(csg)
	var cs := CollisionShape3D.new(); var cv := ConvexPolygonShape3D.new(); cv.points = PackedVector3Array(wedge_pts)
	cs.shape = cv; cs.set_meta("part", {wedge = true}); add_child(cs)
	var a: Vector3 = wedge_pts[0]; var b: Vector3 = wedge_pts[1]; var c: Vector3 = wedge_pts[2]
	volume = 0.5 * (b - a).cross(c - a).length() * (wedge_pts[3] - wedge_pts[0]).length() * 0.8
	span = Vector2(a.y, a.y)

func _build_slab() -> void:
	span = Wood.y_span(T, ops, y0, y1)
	csg = CSGCombiner3D.new()
	var tm := CSGMesh3D.new(); tm.mesh = Wood.trunk_mesh(T, maxf(-0.4, span.x - 0.1), minf(T.H, span.y + 0.1)); tm.material = Mats.bark
	csg.add_child(tm)
	for op in ops:
		var n := Wood.op_node(op)
		if n: csg.add_child(n)
	add_child(csg)
	for op in ops:
		if op.type == "keep":
			var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = op.size * Vector3(0.95, 1, 0.95)
			cs.shape = bs; cs.transform = op.xf; cs.set_meta("part", {trunk = true})
			add_child(cs)
			volume = op.size.x * op.size.y * op.size.z * 0.7

## wood-frame point -> world
func to_world(p: Vector3) -> Vector3:
	return global_transform * p

func to_wood(p: Vector3) -> Vector3:
	return global_transform.affine_inverse() * p

func grain_world(part: Dictionary) -> Vector3:
	if part.has("limb"):
		var L: Dictionary = T.limbs[part.limb]
		if part.has("sub"): return global_transform.basis * L.subs[part.sub].dir
		return global_transform.basis * L.dir
	return global_transform.basis.y

## is a wood-frame point inside this piece's wood (trunk part)?
func inside_trunk(p: Vector3) -> bool:
	if kind != "trunk" and kind != "slab": return false
	if Vector2(p.x, p.z).length() > Wood.r_at(T, maxf(p.y, 0.0)): return false
	if p.y < span.x - 0.2 or p.y > span.y + 0.2: return false
	return Wood.kept(ops, p)

func inside_limb(p: Vector3, part: Dictionary) -> bool:
	var L: Dictionary = T.limbs[part.limb]
	if part.has("sub"):
		var sb: Dictionary = L.subs[part.sub]
		var o := Wood.limb_pt(L, sb.t)
		var cp := Geometry3D.get_closest_point_to_segment(p, o, o + sb.dir * sb.len)
		return p.distance_to(cp) <= sb.r0
	var ta := t0 if kind == "limb" else 0.0
	var tb: float = t1 if kind == "limb" else lt.get(part.limb, 1.0)
	var a := Wood.limb_pt(L, ta); var b := Wood.limb_pt(L, tb)
	var cp := Geometry3D.get_closest_point_to_segment(p, a, b)
	var t := ta + (tb - ta) * clampf((cp - a).dot(b - a) / maxf((b - a).length_squared(), 1e-9), 0, 1)
	return p.distance_to(cp) <= Wood.limb_r(L, t) * 1.05

## brush axis in the wood frame: butt point and direction (for feeding and carrying)
func brush_axis() -> Dictionary:
	if kind == "limb":
		var L: Dictionary = T.limbs[limb]
		return {butt = Wood.limb_pt(L, t0), ax = L.dir, len = L.len * (t1 - t0)}
	return {butt = Vector3(0, span.x, 0), ax = Vector3.UP, len = span.y - span.x}

func center_wood() -> Vector3:
	if kind == "limb":
		var L: Dictionary = T.limbs[limb]
		return Wood.limb_pt(L, (t0 + t1) / 2)
	if kind == "wedge":
		var c := Vector3.ZERO
		for p in wedge_pts: c += p
		return c / wedge_pts.size()
	return Vector3(0, (span.x + span.y) / 2, 0)

func center_world() -> Vector3:
	return to_world(center_wood())
