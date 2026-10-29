## The dead ash: standing, going over, and its stump afterwards.
## Cuts in the standing tree are planes in the wood frame. Two cuts that meet from the same side free
## a wedge (an open face). The wood still holding the stem is found by testing a grid of fibre columns;
## when little is left the tree goes over that hinge, a straight drop, or splits up the back.
class_name AshTree
extends Node3D

signal fell(kind: String)
signal down

var game
var T: Dictionary
var def: Dictionary
var state := "stand"           # stand | hinge | down
var cuts: Array = []           # standing-tree cuts
var freed := {}                # "i-j" -> wedge
var go_kind := ""
var go_acc := 0.0
var dirty := false
var last_build := 0.0
var A = null                   # last analysis
var grade := {}
var lean_dir := Vector3.FORWARD
# a heavy leaner (Mrs. Hale's maple) sits back on its hinge unless something tips it toward the face
var push := Vector3.ZERO        # world, horizontal, in radians of tilt: wedges and the pull rope
var net := Vector3.ZERO         # the tilt it actually has right now (lean + push, eased)
var base_pos := Vector3.ZERO
var sat_told := false
var sat_back := false
# standing visuals
var stand_csg: CSGCombiner3D
var stand_upper: Node3D
var stand_body: StaticBody3D
# after the fall
var stem: WoodPiece
var hinge := {}
var stump: Node3D
var stump_csg: CSGCombiner3D
var stump_body: StaticBody3D
var stump_ops: Array = []
var stump_cuts: Array = []
var stump_top := 0.0
var stump_y0 := 0.0
var barber_dir = null          # Vector3 (wood frame) when a barber slab is standing
var slab_xf := Transform3D()
var slab_size := Vector3.ONE
var down_t := 0.0
var t := 0.0
var _net_holes := 0            # on a crew member's game: notches the host's tree has already opened here

const CSG_TOP := 3.2           # cuts happen below this; above it the standing trunk is a plain mesh

func setup(g, w: WorldGen) -> void:
	game = g
	def = w.tree
	T = Wood.make_tree_def(def)
	lean_dir = Vector3(cos(def.lean_dir), 0, sin(def.lean_dir))
	var axis := Vector3.UP.cross(lean_dir).normalized()
	base_pos = Vector3(def.x, w.H(def.x, def.z), def.z)
	transform = Transform3D(Basis(axis, def.lean), base_pos)
	net = lean_dir * def.lean
	_build_standing()

func sits_back() -> bool:
	return def.get("sits_back", false)

## the tilt in the wood's own frame, flat (which way the weight hangs, and how hard)
func net_wood() -> Vector3:
	var v := global_transform.basis.inverse() * net; v.y = 0
	return v

func _apply_tilt() -> void:
	var a := net.length()
	var b := Basis()
	if a > 1e-4: b = Basis(Vector3.UP.cross(net / a).normalized(), a)
	transform = Transform3D(b, base_pos)

## the open face (deepest notch), in the wood frame, or null
func _face():
	var face = null; var depth := -1.0
	for w in freed.values():
		if w.depth > depth: depth = w.depth; face = w.face
	return face

## a heavy leaner: does it go over the hinge, sit back on it, or break the hinge and go with the lean?
func _sit_decision(an: Dictionary) -> String:
	if an.held == 0: return "drop"
	if not freed.is_empty():
		if an.frac > 0.13: return ""
		var face: Vector3 = _face()
		var nw := net_wood()
		var toward: float = nw.x * face.x + nw.z * face.z
		if toward > 0.008: return "hinge"
		sat_back = true
		if an.frac <= 0.035: return "back"          # cut the hinge away and it goes where it leans
		if not sat_told:
			sat_told = true
			Sfx.play("creak", 0.7)
			game.hud.toast("It's sitting back on the hinge. The weight leans the wrong way. Hammer wedges into the back cut, or take up the pull rope with the truck, to tip it toward your notch.", 7.0)
			if game.has_method("customer_sits_back"): game.customer_sits_back()
		return ""
	if an.frac <= 0.3 and _leans_over_hold(an): return "barber"
	if an.frac <= 0.08: return "drop"
	return ""

func to_wood(p: Vector3) -> Vector3:
	return global_transform.affine_inverse() * p

func to_world(p: Vector3) -> Vector3:
	return global_transform * p

# ---------------------------------------------------------------- standing tree
func _build_standing() -> void:
	stand_csg = CSGCombiner3D.new()
	var tm := CSGMesh3D.new(); tm.mesh = Wood.trunk_mesh(T, -0.45, CSG_TOP, 24); tm.material = Mats.bark
	stand_csg.add_child(tm)
	add_child(stand_csg)
	stand_upper = Node3D.new(); add_child(stand_upper)
	var up := MeshInstance3D.new(); up.mesh = Wood.trunk_mesh(T, CSG_TOP - 0.01, T.H, 24); up.material_override = Mats.bark
	stand_upper.add_child(up)
	# limbs (no collision while standing)
	var tmp := WoodPiece.new(); tmp.T = T
	for L in T.limbs: tmp._add_limb(L, 0.0, 1.0, true)
	for c in tmp.get_children():
		if c is MeshInstance3D:
			tmp.remove_child(c); stand_upper.add_child(c)
	tmp.free()
	stand_body = StaticBody3D.new(); stand_body.collision_layer = 32; stand_body.collision_mask = 0
	var cs := CollisionShape3D.new(); var cy := CylinderShape3D.new()
	cy.radius = Wood.r_at(T, 0.6); cy.height = T.cb
	cs.shape = cy; cs.position = Vector3(0, T.cb / 2 - 0.3, 0)
	stand_body.add_child(cs)
	add_child(stand_body)

func standing_inside(p: Vector3) -> bool:
	return p.y > -0.4 and p.y < T.H and Vector2(p.x, p.z).length() <= Wood.r_at(T, maxf(p.y, 0.0))

## march along a line in the wood frame: (first distance inside, where it leaves) or null
static func chord(inside: Callable, e: Vector3, f: Vector3, t0: float, t1: float):
	var tin = null; var tout = null
	var tt := t0
	while tt <= t1:
		var i: bool = inside.call(e + f * tt)
		if i and tin == null: tin = tt
		if not i and tin != null: tout = tt; break
		tt += 0.004
	if tin != null and tout == null: tout = t1
	if tin == null: return null
	return Vector2(tin, tout)

## start (or pick back up) a cut in the standing tree at wood-frame entry e
func start_cut(e: Vector3, f: Vector3, n: Vector3) -> Dictionary:
	for c in cuts:
		if absf(c.n.dot(n)) > 0.97 and absf(c.n.dot(e - c.e)) < 0.04 and c.f.dot(f) > 0.9: return c
	var ch = chord(standing_inside, e, f, -0.03, 1.6)
	var ex := 0.02
	if ch != null: ex = maxf(0.02, ch.y - maxf(0.0, ch.x))
	var c := {kind = "tree", e = e, f = f, n = n, s = 0.0, exit = ex, type = "kerf"}
	c.node = Wood.op_node(c)
	stand_csg.add_child(c.node)
	cuts.append(c)
	return c

func cut_progress(c: Dictionary) -> void:
	if state != "stand" or not is_instance_valid(c.get("node")): return
	Wood.update_kerf(c.node, c)
	dirty = true
	if Net.is_guest() and Net.job: Net.job.tree_cut(c)

# ---------------------------------------------------------------- analysis
func _cut_y_at(c: Dictionary, x: float, z: float):
	if absf(c.n.y) < 0.05: return null
	return c.e.y - (c.n.x * (x - c.e.x) + c.n.z * (z - c.e.z)) / c.n.y

func _cut_severs(c: Dictionary, x: float, z: float):
	var y = _cut_y_at(c, x, z)
	if y == null: return null
	if x * x + z * z > pow(Wood.r_at(T, clampf(y, 0, T.H)), 2): return null
	var p: Vector3 = Vector3(x, y, z) - c.e
	var d: float = p.dot(c.f)
	var g: Vector3 = c.n.cross(c.f).normalized()
	if absf(p.dot(g)) > float(c.get("w", Wood.kerf_half_width(c.s))): return null
	return y if d <= c.s and d >= -0.03 else null

func analyze():
	var live := cuts.filter(func(c): return c.s > 0.004)
	if live.is_empty(): return null
	var yb := 0.0
	for c in live: yb += c.e.y
	yb = clampf(yb / live.size(), 0, T.H)
	var R := Wood.r_at(T, yb)
	var N := 26; var cols := []; var total := 0; var held := 0
	for i in range(N):
		for j in range(N):
			var x := (i + 0.5) / N * 2 * R - R; var z := (j + 0.5) / N * 2 * R - R
			if x * x + z * z > R * R: continue
			total += 1
			var lo = null; var hi = null
			for c in live:
				var y = _cut_severs(c, x, z)
				if y != null:
					lo = y if lo == null else minf(lo, y)
					hi = y if hi == null else maxf(hi, y)
			if lo == null: held += 1
			cols.append({x = x, z = z, lo = lo, hi = hi})
	var wedges := []
	for a in range(live.size()):
		for b in range(a + 1, live.size()):
			var w = _wedge_of(live[a], live[b])
			if w != null: wedges.append(w)
	return {R = R, yb = yb, cols = cols, total = total, held = held, frac = float(held) / maxi(total, 1), wedges = wedges}

func _wedge_of(c1: Dictionary, c2: Dictionary):
	var h1 := Vector3(c1.f.x, 0, c1.f.z).normalized(); var h2 := Vector3(c2.f.x, 0, c2.f.z).normalized()
	if h1.dot(h2) < 0.5: return null
	var nd := absf(c1.n.dot(c2.n))
	if nd > 0.985: return null
	var l: Vector3 = c1.n.cross(c2.n).normalized()
	var d1: float = c1.n.dot(c1.e); var d2: float = c2.n.dot(c2.e)
	var n1: Vector3 = c1.n; var n2: Vector3 = c2.n
	var p0: Vector3 = (n2.cross(l) * d1 + l.cross(n1) * d2) / n1.cross(n2).dot(l)
	var inside := 0; var ok := 0
	var tt := -0.6
	while tt <= 0.6:
		var q := p0 + l * tt
		tt += 0.02
		if q.y < 0 or q.y > T.H or Vector2(q.x, q.z).length() > Wood.r_at(T, q.y) * 0.97: continue
		inside += 1
		if (q - c1.e).dot(c1.f) <= c1.s + 0.004 and (q - c2.e).dot(c2.f) <= c2.s + 0.004: ok += 1
	if inside < 3 or float(ok) / inside < 0.85: return null
	var face := (-(h1 + h2)).normalized()
	var R := Wood.r_at(T, clampf(p0.y, 0, T.H))
	var sp := p0.x * face.x + p0.z * face.z
	var depth := R - sp
	var w: Vector3 = (c1.e + c2.e) * 0.5 + face * -0.01
	return {c1 = c1, c2 = c2, l = l, p0 = p0, face = face, depth = depth, angle = rad_to_deg(acos(clampf(nd, -1, 1))),
		s1 = signf(n1.dot(w - p0)), s2 = signf(n2.dot(w - p0))}

func _wedge_points(w: Dictionary) -> Array:
	var R := Wood.r_at(T, clampf(w.p0.y, 0, T.H))
	var sp: float = w.p0.x * w.face.x + w.p0.z * w.face.z
	var half := sqrt(maxf(0.0004, R * R - sp * sp)) * 1.05 + 0.05
	var out := func(n: Vector3) -> Vector3:
		var d: Vector3 = w.l.cross(n).normalized()
		if d.dot(w.face) < 0: d = -d
		var hz := maxf(Vector2(d.x, d.z).length(), 0.05)
		return w.p0 + d * minf(0.8, (w.depth + 0.1) / hz)
	var A0: Vector3 = w.p0; var B0: Vector3 = out.call(w.c1.n); var C0: Vector3 = out.call(w.c2.n)
	var P := []
	for s in [-1.0, 1.0]:
		for p in [A0, B0, C0]: P.append(p + w.l * s * half)
	return P

func _leans_over_hold(an: Dictionary) -> bool:
	if def.lean < 0.035: return false
	var sx := 0.0; var sz := 0.0; var n := 0
	for c in an.cols:
		if c.lo == null: sx += c.x; sz += c.z; n += 1
	if n == 0: return false
	var h := Vector3(sx / n, 0, sz / n).normalized()
	var lw := global_transform.basis.inverse() * lean_dir
	return h.x * lw.x + h.z * lw.z > 0.45

func step(dt: float) -> void:
	t += dt
	# a crew member's copy: the host's tree decides when it goes, and how; the cuts and lean come from there
	if Net.is_guest(): return
	if state == "stand" and sits_back():
		# wedges and the rope lift it back toward upright, a little at a time
		var want: Vector3 = lean_dir * def.lean + push
		var before := net
		net = net.move_toward(want, dt * 0.06)
		if not net.is_equal_approx(before): _apply_tilt()
	if state == "stand":
		if dirty and t - last_build > 0.05:
			dirty = false; last_build = t
			A = analyze()
			if A != null:
				for w in A.wedges:
					var key := "%d-%d" % [cuts.find(w.c1), cuts.find(w.c2)]
					if not freed.has(key):
						freed[key] = w
						_free_wedge(w)
				var open := not freed.is_empty()
				if sits_back(): go_kind = _sit_decision(A)
				elif A.held == 0: go_kind = "drop"
				elif open and A.frac <= 0.13: go_kind = "hinge"
				elif not open and A.frac <= 0.3 and _leans_over_hold(A): go_kind = "barber"
				elif not open and A.frac <= 0.08: go_kind = "drop"
				else: go_kind = ""
		if sits_back() and A != null and not dirty: go_kind = _sit_decision(A)
		if go_kind != "":
			go_acc += dt
			if go_acc > 0.05: start_fall(go_kind)
		else: go_acc = 0
	elif state == "hinge":
		_hinge_step(dt)
	elif state == "down" or (stem and is_instance_valid(stem)):
		pass

## the notch wedge pops out as its own little piece, and the hole it leaves is cut from the standing trunk
func _free_wedge(w: Dictionary) -> void:
	var P := _wedge_points(w)
	w.pts = P
	w.mesh = Wood.prism_mesh(P)
	var hole := CSGMesh3D.new(); hole.mesh = w.mesh; hole.operation = CSGShape3D.OPERATION_SUBTRACTION; hole.material = Mats.sap
	stand_csg.add_child(hole)
	var lo := 1e9; var hi := -1e9
	for p in P: lo = minf(lo, p.y); hi = maxf(hi, p.y)
	var wp := WoodPiece.new(); wp.T = T; wp.kind = "wedge"; wp.wedge_pts = P; wp.y0 = maxf(-0.4, lo - 0.1); wp.y1 = hi + 0.1
	game.level_root.add_child(wp)
	wp.global_transform = global_transform
	wp.build()
	wp.linear_velocity = global_transform.basis * w.face * 0.6 + Vector3(0, 0.3, 0)
	Sfx.play("crunch")

# ---------------------------------------------------------------- the fall
func start_fall(kind: String) -> void:
	go_kind = ""
	var an = A if A != null else analyze()
	var wedges: Array = freed.values()
	var face = null; var depth := 0.0; var angle := 0.0
	if not wedges.is_empty():
		var wb: Dictionary = wedges[0]
		for w in wedges:
			if w.depth > wb.depth: wb = w
		face = wb.face; depth = wb.depth; angle = wb.angle
	var Hc: Array = an.cols.filter(func(c): return c.lo == null)
	var cx := 0.0; var cz := 0.0
	for c in Hc: cx += c.x; cz += c.z
	if not Hc.is_empty(): cx /= Hc.size(); cz /= Hc.size()
	var lean_w: Vector3 = global_transform.basis.inverse() * lean_dir
	lean_w.y = 0; lean_w = lean_w.normalized()
	var fd: Vector3
	if sits_back():
		# the hinge steers it, but the lean that's left pulls it off to the side
		var nw := net_wood()
		if kind == "hinge" and face != null:
			var s: float = nw.dot(face)
			fd = ((face as Vector3) + (nw - (face as Vector3) * s) * 3.5).normalized()
		elif nw.length() > 0.001: fd = nw.normalized()
		else: fd = lean_w
	elif kind == "hinge" and face != null:
		var dir: Vector3 = face
		if Hc.size() > 3:
			var xx := 0.0; var zz := 0.0; var xz := 0.0
			for c in Hc:
				var dx: float = c.x - cx; var dz: float = c.z - cz
				xx += dx * dx; zz += dz * dz; xz += dx * dz
			var th := 0.5 * atan2(2 * xz, xx - zz)
			var a := Vector3(cos(th), 0, sin(th))
			var l1 := (xx + zz) / 2 + sqrt(pow((xx - zz) / 2, 2) + xz * xz); var l2 := (xx + zz) / 2 - sqrt(pow((xx - zz) / 2, 2) + xz * xz)
			if l1 > 2.5 * maxf(l2, 1e-9):
				var perp := dir - a * dir.dot(a)
				if perp.length() > 0.2: dir = perp.normalized()
		fd = (dir * 0.6 + lean_w).normalized() if an.frac < 0.025 else dir
	else:
		fd = lean_w
	# hinge thickness along the fall direction, and the grade
	var hmin := 1e9; var hmax := -1e9
	for c in Hc:
		var s: float = c.x * fd.x + c.z * fd.z
		hmin = minf(hmin, s); hmax = maxf(hmax, s)
	var hinge_t: float = (hmax - hmin + 2 * an.R / 26) if not Hc.is_empty() else 0.0
	var D: float = 2 * an.R
	var err := rad_to_deg(acos(clampf(fd.dot(face), -1, 1))) if face != null else 180.0
	grade = {notch_pct = depth / D, notch_angle = angle, hinge_pct = hinge_t / D, hinge_in = hinge_t * 39.37, dir_err = err, barber = kind == "barber", open = face != null}
	# the plane that separates stem from stump: the deepest cut that isn't part of an open face
	var notch_cuts := []
	for w in wedges: notch_cuts.append(w.c1); notch_cuts.append(w.c2)
	var split = null
	for c in cuts:
		if c.s < 0.004 or notch_cuts.has(c): continue
		if split == null or c.s / c.exit > split.s / split.exit: split = c
	if split == null and not cuts.is_empty(): split = cuts[cuts.size() - 1]
	var sp: Vector3; var sn: Vector3
	var yh: float = an.yb
	if split != null:
		sp = split.e; sn = split.n
		if sn.y < 0: sn = -sn
		if sn.y < 0.5: sn = Vector3.UP        # a wildly angled cut still leaves a stump top that's mostly flat
	else:
		sp = Vector3(0, yh, 0); sn = Vector3.UP
	var yc: float = sp.y + (sn.x * sp.x + sn.z * sp.z) / sn.y
	stump_y0 = yc
	# stem: everything above that plane, minus the kerfs and the notch
	var sops := [{type = "clip", p = sp, n = -sn}]
	var kops := []
	for c in cuts:
		if c.s > 0.004:
			var ko := {type = "kerf", e = c.e, f = c.f, n = c.n, s = c.s, done = true}
			if c.has("w"): ko.w = c.w
			kops.append(ko)
	for w in wedges: kops.append({type = "prism", mesh = w.mesh, pts = w.get("pts", [])})
	barber_dir = null
	if kind == "barber":
		barber_dir = fd
		var r := Wood.r_at(T, yc)
		var across := Vector3.UP.cross(fd).normalized()
		slab_size = Vector3(r * 2.4, 1.5, r * 0.55)
		slab_xf = Transform3D(Basis(across, Vector3.UP, fd), Vector3(0, yc + 0.75, 0) - fd * r * 0.6)
		sops.append({type = "cutbox", xf = slab_xf, size = slab_size})
	stem = WoodPiece.new(); stem.T = T; stem.kind = "trunk"; stem.y0 = yc - 0.5; stem.y1 = T.H
	stem.ops = sops + kops
	for L in T.limbs: stem.limbs.append(L.id)
	stem.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	stem.freeze = true
	game.level_root.add_child(stem)
	stem.global_transform = global_transform
	stem.build()
	# stump
	stump_ops = [{type = "clip", p = sp, n = sn}] + kops
	stump_top = yc
	_rebuild_stump()
	stand_csg.queue_free(); stand_upper.queue_free(); stand_body.queue_free()
	# hinge pivot: the middle of the wood still holding
	var piv_w := Vector3(cx, yc, cz) if not Hc.is_empty() else Vector3(0, yc, 0)
	var piv := to_world(piv_w)
	var fdw := (global_transform.basis * fd); fdw.y = 0; fdw = fdw.normalized()
	var axis := Vector3.UP.cross(fdw).normalized()
	var com_h: float = yc + (T.H - yc) * 0.36
	var Lst: float = T.H - yc
	hinge = {axis = axis, P = piv, th = 0.0, td = 0.12 if kind == "hinge" else 0.35, x0 = stem.global_transform,
		com = to_world(Vector3(0, com_h, 0)), I = stem.mass * (pow(com_h - yc, 2) + Lst * Lst / 12.0), brk = 1.2 if kind == "hinge" else 0.45, t = 0.0, kind = kind, fd = fdw}
	state = "hinge"
	Sfx.play("creak")
	get_tree().create_timer(0.6).timeout.connect(func(): Sfx.play("crack"))
	fell.emit(kind)
	if Net.is_host() and Net.job: Net.job.tree_fell(kind)

func _hinge_step(dt: float) -> void:
	var h := hinge
	h.t += dt
	var rc: Vector3 = (Basis(h.axis, h.th) * (h.com - h.P))
	var tau: float = rc.cross(Vector3(0, -9.81 * stem.mass, 0)).dot(h.axis)
	if h.t < 5.0 and tau < stem.mass * 9.81 * 0.4:
		tau = stem.mass * 9.81 * 0.4          # wedges and a good push: it goes toward the face
	h.td += (tau / h.I) * dt - h.td * 0.15 * dt
	h.th += h.td * dt
	var rot := Basis(h.axis, h.th)
	var x0: Transform3D = h.x0
	stem.global_transform = Transform3D(rot * x0.basis, h.P + rot * (x0.origin - h.P))
	# let go once it's well over, or as soon as the top or a limb touches the ground
	var touch := false
	if h.th > 0.45:
		for p in [Vector3(0, T.H, 0)] + T.limbs.map(func(L): return Wood.limb_pt(L, 1.0)):
			var w := stem.to_world(p)
			if w.y < game.world.H(w.x, w.z) + 0.05: touch = true; break
	if h.th > h.brk or touch:
		var w: Vector3 = h.axis * h.td
		stem.freeze = false
		stem.angular_velocity = w
		stem.linear_velocity = w.cross(rot * (h.com - h.P))
		state = "down"
		down_t = t
		Sfx.play("crack")

# ---------------------------------------------------------------- stump
func _rebuild_stump() -> void:
	if stump: stump.queue_free()
	stump = Node3D.new(); add_child(stump)
	stump_csg = CSGCombiner3D.new()
	var main := CSGCombiner3D.new()
	var tm := CSGMesh3D.new(); tm.mesh = Wood.trunk_mesh(T, -0.45, stump_top + 0.6, 24); tm.material = Mats.bark
	main.add_child(tm)
	for op in stump_ops:
		var n := Wood.op_node(op)
		if n: main.add_child(n)
	for c in stump_cuts:
		if not c.get("done", false):
			c.node = Wood.op_node(c); main.add_child(c.node)
	stump_csg.add_child(main)
	if barber_dir != null:
		var sl := CSGCombiner3D.new()
		var tm2 := CSGMesh3D.new(); tm2.mesh = Wood.trunk_mesh(T, stump_y0 - 0.1, stump_y0 + 1.6, 24); tm2.material = Mats.bark
		sl.add_child(tm2)
		sl.add_child(Wood.op_node({type = "keep", xf = slab_xf, size = slab_size}))
		sl.add_child(Wood.op_node({type = "clip", p = Vector3(0, stump_y0 - 0.02, 0), n = Vector3.DOWN}))
		stump_csg.add_child(sl)
	stump.add_child(stump_csg)
	stump_body = StaticBody3D.new(); stump_body.collision_layer = 32; stump_body.collision_mask = 0
	var cs := CollisionShape3D.new(); var cy := CylinderShape3D.new()
	var top := stump_top
	cy.radius = Wood.r_at(T, maxf(0.0, top * 0.5)); cy.height = top + 0.4
	cs.shape = cy; cs.position = Vector3(0, (top - 0.4) / 2, 0)
	stump_body.add_child(cs)
	if barber_dir != null:
		var cs2 := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = slab_size * Vector3(0.9, 1, 0.9)
		cs2.shape = bs; cs2.transform = slab_xf; stump_body.add_child(cs2)
	stump.add_child(stump_body)

func stump_inside(p: Vector3) -> bool:
	if Vector2(p.x, p.z).length() > Wood.r_at(T, maxf(p.y, 0.0)): return false
	if p.y < -0.4: return false
	var in_slab := false
	if barber_dir != null:
		var l := slab_xf.affine_inverse() * p
		in_slab = absf(l.x) < slab_size.x / 2 and absf(l.y) < slab_size.y / 2 and absf(l.z) < slab_size.z / 2 and p.y > stump_y0
	return in_slab or Wood.kept(stump_ops, p)

func stump_start_cut(e: Vector3, f: Vector3, n: Vector3) -> Dictionary:
	for c in stump_cuts:
		if not c.get("done", false) and absf(c.n.dot(n)) > 0.97 and absf(c.n.dot(e - c.e)) < 0.04 and c.f.dot(f) > 0.9: return c
	var ch = chord(stump_inside, e, f, -0.03, 1.6)
	var ex := 0.02
	if ch != null: ex = maxf(0.02, ch.y - maxf(0.0, ch.x))
	var c := {kind = "stump", e = e, f = f, n = n, s = 0.0, exit = ex, type = "kerf"}
	c.node = Wood.op_node(c)
	(stump_csg.get_child(0) as CSGCombiner3D).add_child(c.node)
	stump_cuts.append(c)
	return c

## a cleanup cut through the stump: the wood above comes off as its own piece
func finish_stump_cut(c: Dictionary) -> void:
	if Net.is_guest():
		# the host makes the cut; what comes off arrives from there
		if Net.job: Net.job.stump_cut(c)
		stump_cuts.erase(c)
		_rebuild_stump()
		Sfx.play("crunch")
		return
	c.done = true
	var n: Vector3 = c.n
	if n.y < 0: n = -n
	var yc: float = c.e.y + (n.x * c.e.x + n.z * c.e.z) / maxf(absf(n.y), 1e-3)
	if barber_dir != null and yc < stump_y0 + 1.4:
		var sp := WoodPiece.new(); sp.T = T; sp.kind = "slab"; sp.y0 = stump_y0; sp.y1 = stump_y0 + 1.5
		sp.ops = [{type = "keep", xf = slab_xf, size = slab_size}, {type = "clip", p = Vector3(0, stump_y0, 0), n = Vector3.DOWN}]
		game.level_root.add_child(sp); sp.global_transform = global_transform; sp.build()
		sp.angular_velocity = global_transform.basis * Vector3.UP.cross(-barber_dir) * 0.8
		barber_dir = null
	if yc < stump_top + 0.05 and yc > -0.3:
		var ck := WoodPiece.new(); ck.T = T; ck.kind = "trunk"; ck.y0 = yc - 0.3; ck.y1 = stump_top + 0.5
		ck.ops = stump_ops.duplicate() + [{type = "clip", p = c.e - n * Wood.KERF, n = -n}]
		game.level_root.add_child(ck); ck.global_transform = global_transform; ck.build()
		ck.linear_velocity = global_transform.basis * (c.f * 0.4) + Vector3(0, 0.3, 0)
		stump_ops.append({type = "clip", p = c.e + n * Wood.KERF, n = n})
		stump_top = minf(stump_top, yc)
	stump_cuts.erase(c)
	_rebuild_stump()
	Sfx.play("crunch")
	if Net.is_host() and Net.job: Net.job.stump_changed()

# ---------------------------------------------------------------- a crew member's copy
## the host's cuts (as deep as they've got), its lean, and any notch that's popped out
func net_apply(list: Array, tilt: Vector3, holes: Array) -> void:
	if state != "stand" or not is_instance_valid(stand_csg): return
	for a in list:
		var c := start_cut(a[0], a[1], a[2])
		c.s = maxf(float(c.s), float(a[3]))
		c.exit = float(a[4])
		if float(a[5]) > 0.0: c.w = float(a[5])
		if is_instance_valid(c.get("node")): Wood.update_kerf(c.node, c)
	if not net.is_equal_approx(tilt):
		net = tilt; _apply_tilt()
	while _net_holes < holes.size():
		var P: Array = holes[_net_holes]
		_net_holes += 1
		var hole := CSGMesh3D.new(); hole.mesh = Wood.prism_mesh(P); hole.operation = CSGShape3D.OPERATION_SUBTRACTION; hole.material = Mats.sap
		stand_csg.add_child(hole)
		Sfx.play("crunch")

func _net_stump_vals(s: Dictionary) -> void:
	var ops := []
	for o in s.ops: ops.append(NetJob.op_in(o))
	stump_ops = ops
	stump_top = float(s.top); stump_y0 = float(s.y0)
	barber_dir = s.bd
	slab_xf = s.sx; slab_size = s.ss

## the host's tree went over (kind "" if it was already down when you got here)
func net_fall(d: Dictionary) -> void:
	if state != "stand": return
	grade = d.grade
	_net_stump_vals(d.stump)
	if is_instance_valid(stand_csg): stand_csg.queue_free()
	if is_instance_valid(stand_upper): stand_upper.queue_free()
	if is_instance_valid(stand_body): stand_body.queue_free()
	_rebuild_stump()
	go_kind = ""
	if str(d.kind) == "":
		state = "down"; down_t = t
		return
	state = "hinge"
	Sfx.play("creak")
	get_tree().create_timer(0.6).timeout.connect(func(): Sfx.play("crack"))
	fell.emit(str(d.kind))

func net_stump(s: Dictionary) -> void:
	_net_stump_vals(s)
	_rebuild_stump()
