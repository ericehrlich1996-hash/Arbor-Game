## The chainsaw. The bar is a real segment in the world: wherever it enters wood, at whatever angle
## you hold it, a cut plane is started there and eaten deeper while you hold the throttle.
## The mouse wheel rolls the saw, which turns the plane. Also: the gloved hands, and sawdust.
class_name Saw
extends Node3D

const BAR_L := 0.61
const BAR_BASE := -0.22

var game
var player: Player
var model: MeshInstance3D
var fist_r: MeshInstance3D
var fist_l: MeshInstance3D
var arm_r: MeshInstance3D
var arm_l: MeshInstance3D
var on := false
var rpm := 0.0
var eng := 0.0
var k := 0.0
var roll := PI / 2
var pull := 0.0
var pulls := 0
var cut = null
var cutting := false
var bind := false
var racked := false
var engine_snd = null
var B := Vector3.ZERO          # bar base, world
var T_ := Vector3.ZERO         # bar tip, world
var f := Vector3.FORWARD       # along the bar, world
var n := Vector3.RIGHT         # kerf normal (saw's +X), world
var _kerf_t := 0.0
var _t := 0.0
# sawdust
var chips: Array = []
var chip_mm: MultiMeshInstance3D
var piles := {}
var pile_mm: MultiMeshInstance3D
var _pile_dirty := false
var _pile_t := 0.0

func setup(g, p: Player) -> void:
	game = g; player = p
	model = Models.chainsaw().instance(); add_child(model)
	fist_r = Models.fist(1).instance(); fist_l = Models.fist(-1).instance()
	arm_r = Models.arm().instance(); arm_l = Models.arm().instance()
	for m in [model, fist_r, fist_l, arm_r, arm_l]:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for m in [fist_r, fist_l, arm_r, arm_l]:
		add_child(m)
	# chips in the air and the piles they make
	chip_mm = MultiMeshInstance3D.new()
	var cm := MultiMesh.new(); cm.transform_format = MultiMesh.TRANSFORM_3D; cm.use_colors = true
	var bm := BoxMesh.new(); bm.size = Vector3(1, 0.6, 1); cm.mesh = bm
	chip_mm.multimesh = cm; chip_mm.material_override = Mats.vcol
	chip_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chip_mm.top_level = true
	add_child(chip_mm)
	pile_mm = MultiMeshInstance3D.new()
	var pm := MultiMesh.new(); pm.transform_format = MultiMesh.TRANSFORM_3D; pm.use_colors = true
	var sm := SphereMesh.new(); sm.radius = 1; sm.height = 2; sm.radial_segments = 8; sm.rings = 4; pm.mesh = sm
	pile_mm.multimesh = pm; pile_mm.material_override = Mats.vcol
	pile_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pile_mm.top_level = true
	add_child(pile_mm)

func set_visible_tool(v: bool) -> void:
	for m in [model, fist_r, fist_l, arm_r, arm_l]: m.visible = v

# ---------------------------------------------------------------- pose
func pose(dt: float, rev: bool, carrying: bool) -> void:
	_t += dt
	var want := 1.0 if (on and rev and not carrying) else 0.0
	eng = lerpf(eng, want, minf(1, dt * 9))
	var bobx := sin(player.bob) * 0.012; var boby := -absf(cos(player.bob)) * 0.012
	var pull_y := 0.0; var pull_r := 0.0
	if pull > 0:
		var kk := sin((1 - pull / 0.5) * PI); pull_y = -0.06 * kk; pull_r = 0.25 * kk
	# idle at the hip
	var iq := Quaternion(Vector3.UP, 0.55) * Quaternion(Vector3.RIGHT, 0.1 + pull_r) * Quaternion(Vector3.BACK, -0.22) * Quaternion(Vector3.BACK, roll)
	var ip := Vector3(0.3 + bobx, -0.36 + pull_y + boby, -0.42)
	# engaged: the bar runs out along the line of sight with the tip just under the crosshair
	var reach := 1.0 + clampf(-player.pitch, 0, 1.2) * 0.5
	var tip := Vector3(0, -0.03, -1.12 * reach)
	var ff := (tip - Vector3(0.065, -0.17, -0.5 * reach)).normalized()
	var rgt := ff.cross(Vector3.UP).normalized(); var upp := rgt.cross(ff)
	var ax := rgt * cos(roll) + upp * sin(roll)
	var z := -ff; var x := ax; var y := z.cross(x)
	var eq := Quaternion(Basis(x, y, z).orthonormalized())
	var ep := tip - ff * (-BAR_BASE + BAR_L)
	k = smoothstep(0, 1, clampf(eng, 0, 1))
	var pos := ip.lerp(ep, k)
	var q := iq.slerp(eq, k)
	# the bar can't pass through wood: back the saw off to the bark, or to the cut front
	var cw := player.cam.global_transform
	var fc := q * Vector3(0, 0, -1)
	var bw := cw * (pos + q * Vector3(0, 0, BAR_BASE))
	var fw := (cw.basis * fc).normalized()
	if k > 0.5 and cut == null: _magnet(dt, cw)
	if k > 0.5:
		var lim = null
		if cut != null:
			var W := cut_world(cut)
			if not W.is_empty(): lim = (W.e - bw).dot(fw) + cut.s
		if lim == null:
			var h := wood_hit(bw, fw, BAR_L + 0.3)
			if not h.is_empty(): lim = h.t
		if lim != null and lim < BAR_L:
			pos -= fc * minf(0.45, BAR_L - lim)
	var vib := (0.005 if cutting else 0.0022) if on else 0.0
	pos += Vector3((randf() - 0.5) * vib, (randf() - 0.5) * vib, 0)
	model.transform = Transform3D(Basis(q), pos)
	var mw := cw * model.transform
	B = mw * Vector3(0, 0, BAR_BASE)
	T_ = mw * Vector3(0, 0, BAR_BASE - BAR_L)
	f = (T_ - B).normalized()
	n = (mw.basis * Vector3.RIGHT).normalized()
	# hands on the handles, sleeves back to the shoulders
	var rh := model.transform * Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, 0.098, 0.035))
	var lh := model.transform * Transform3D(Basis(Vector3.UP, -0.3), Vector3(-0.05, 0.172, -0.233))
	fist_r.transform = rh; fist_l.transform = lh
	_arm(arm_r, rh * Vector3(0, 0.02, 0.06), Vector3(0.26, -0.55, 0.12))
	_arm(arm_l, lh * Vector3(0, 0.02, 0.06), Vector3(-0.42, -0.5, 0.08))

## a bar held close to a cut you've already made wants to drop back into it: the roll eases toward
## that kerf's angle (gently: you can still turn it away with the wheel)
func _nearest_open_cut() -> Dictionary:
	var p := B + f * 0.35
	var best := {}; var best_d := 0.07
	for c in _open_cuts():
		var W := cut_world(c)
		if W.is_empty(): continue
		var d := absf(W.n.dot(p - W.e))
		if d < best_d and absf(n.dot(W.n)) > 0.85 and f.dot(W.f) > 0.75:
			best_d = d; best = W; best.d = d
	return best

func _magnet(dt: float, cw: Transform3D) -> void:
	var best := _nearest_open_cut()
	if best.is_empty(): return
	var best_d: float = best.d
	var nc: Vector3 = cw.basis.inverse() * best.n
	var reach := 1.0 + clampf(-player.pitch, 0, 1.2) * 0.5
	var tip := Vector3(0, -0.03, -1.12 * reach)
	var ff := (tip - Vector3(0.065, -0.17, -0.5 * reach)).normalized()
	var rgt := ff.cross(Vector3.UP).normalized(); var upp := rgt.cross(ff)
	var want := atan2(nc.dot(upp), nc.dot(rgt))
	if absf(angle_difference(roll, want + PI)) < absf(angle_difference(roll, want)): want += PI   # either face of the kerf will do
	var pull := (1.0 - best_d / 0.07) * 2.5
	roll = lerp_angle(roll, want, minf(1.0, dt * pull))

func _open_cuts() -> Array:
	var out := []
	var tree: AshTree = game.tree
	if tree.state == "stand": out.append_array(tree.cuts)
	elif tree.stump: out.append_array(tree.stump_cuts.filter(func(c): return not c.get("done", false)))
	for pc in game.pieces():
		if pc.global_position.distance_to(player.global_position) > 30 and pc.center_world().distance_to(player.global_position) > 3: continue
		for op in pc.ops:
			if op.type == "kerf" and not op.get("done", false):
				op.piece = pc
				if not op.has("part"): op.part = {trunk = true}
				out.append(op)
	return out

func _arm(m: MeshInstance3D, a: Vector3, b: Vector3, r := 0.042) -> void:
	var d := b - a; var L := d.length()
	if L < 1e-3: return
	m.transform = Transform3D(Basis(Quaternion(Vector3.UP, d / L)) * Basis.from_scale(Vector3(r, L, r)), a)

## idle gloved hands when not holding the saw (also used while carrying)
func pose_hands(carrying: bool) -> void:
	var bobx := sin(player.bob) * 0.012; var boby := -absf(cos(player.bob)) * 0.012
	for side in [1.0, -1.0]:
		var fist: MeshInstance3D = fist_r if side > 0 else fist_l
		var arm: MeshInstance3D = arm_r if side > 0 else arm_l
		var p := Vector3(side * 0.24, -0.3 + boby, -0.55) if carrying else Vector3(side * (0.25 + bobx), -0.3 + boby, -0.5)
		var rx := -0.5 if carrying else -0.3
		fist.transform = Transform3D(Basis(Vector3.RIGHT, rx) * Basis(Vector3.UP, PI / 2), p)
		_arm(arm, fist.transform * Vector3(0, 0.02, 0.06), Vector3(side * 0.3, -0.6, 0.12))

# ---------------------------------------------------------------- what does the bar touch?
func wood_hit(from: Vector3, dir: Vector3, max_t: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_t)
	q.collision_mask = 8 | 32 | 64
	q.exclude = [player.get_rid()]
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty(): return {}
	var col = hit.collider
	var tree: AshTree = game.tree
	var out := {t = from.distance_to(hit.position), p = hit.position}
	if tree.stand_body and is_instance_valid(tree.stand_body) and col == tree.stand_body:
		out.kind = "tree"
		# the physics cylinder is a little fat; step in to the real bark
		var e := tree.to_wood(hit.position); var fl := tree.global_transform.basis.inverse() * dir
		var ch = AshTree.chord(tree.standing_inside, e, fl, -0.1, 0.6)
		if ch == null: return {}
		out.t += ch.x; out.p = hit.position + dir * ch.x
		return out
	if tree.stump_body and is_instance_valid(tree.stump_body) and col == tree.stump_body:
		out.kind = "stump"
		var e := tree.to_wood(hit.position); var fl := tree.global_transform.basis.inverse() * dir
		var ch = AshTree.chord(tree.stump_inside, e, fl, -0.1, 0.6)
		if ch == null: return {}
		out.t += ch.x; out.p = hit.position + dir * ch.x
		return out
	if col is WoodPiece and col.mode == "dyn":
		var owner = col.shape_owner_get_owner(col.shape_find_owner(hit.shape))
		out.kind = "piece"; out.piece = col
		out.part = owner.get_meta("part", {trunk = true}) if owner else {trunk = true}
		if out.part.has("tip") or out.part.has("wedge"): return {}
		return out
	return {}

func cut_world(c: Dictionary) -> Dictionary:
	var xf: Transform3D
	if c.kind == "tree" or c.kind == "stump": xf = game.tree.global_transform
	else:
		if not is_instance_valid(c.piece) or c.piece.mode != "dyn": return {}
		xf = c.piece.global_transform
	return {e = xf * c.e, f = (xf.basis * c.f).normalized(), n = (xf.basis * c.n).normalized()}

# ---------------------------------------------------------------- cutting
func step(dt: float, rev: bool, carrying: bool) -> void:
	cutting = false; bind = false
	if pull > 0: pull = maxf(0, pull - dt)
	if on: rpm = lerpf(rpm, 1.0 if rev else 0.05, minf(1, dt * (6 if rev else 3)))
	if engine_snd: engine_snd.setv(rpm * (0.82 if cutting else 1.0), 0.0, 0.42)
	if player.tool != "saw" or not on or carrying: cut = null; return
	if not rev or k < 0.96: cut = null; return
	if cut == null:
		# easing into an old kerf: wait until the bar has settled into it rather than starting a new one beside it
		var mg := _nearest_open_cut()
		if not mg.is_empty() and absf(n.dot(mg.n)) < 0.97: return
		var h := wood_hit(B, f, BAR_L + 0.02)
		if h.is_empty() or h.t > BAR_L + 0.01: return
		cut = _start_cut(h)
		if cut == null: return
	var W := cut_world(cut)
	if W.is_empty(): cut = null; return
	var aligned: bool = f.dot(W.f) > 0.93 and absf(n.dot(W.n)) > 0.97
	var grain: Vector3
	if cut.kind == "tree" or cut.kind == "stump": grain = game.tree.global_transform.basis.y
	else: grain = cut.piece.grain_world(cut.part)
	var crosses: bool = absf(W.n.dot(grain)) > 0.34
	cutting = true
	if engine_snd: engine_snd.setv(rpm * 0.82, 1.0, 0.42)
	if not aligned or not crosses: bind = true; return
	var rate := Wood.CUT_SPEED * (0.35 + 0.65 * rpm) * (1.5 if cut.part.has("limb") else 1.0)
	var max_s: float = cut.exit + 0.004
	if cut.s < max_s: cut.s = minf(max_s, cut.s + rate * dt)
	_emit(W.e, -W.f * 1.6 + Vector3(0, 0.9, 0), 3, Color("#e2cfa0"), 1.4, 0.026)
	if randf() < 0.5: _emit(W.e, -W.f + Vector3(0, 0.3, 0), 1, Color("#b89a6a"), 0.8, 0.045)
	match cut.kind:
		"tree":
			if game.tree.state != "stand": cut = null; return
			game.tree.cut_progress(cut)
		"stump":
			if cut.s >= cut.exit:
				game.tree.finish_stump_cut(cut); cut = null; game.update_objectives()
			elif _t - _kerf_t > 0.08 and is_instance_valid(cut.get("node")):
				_kerf_t = _t; Wood.update_kerf(cut.node, cut)
		"piece":
			if cut.s >= cut.exit:
				_finish_piece_cut(cut); cut = null
			elif not cut.part.has("limb") and _t - _kerf_t > 0.08:
				_kerf_t = _t
				if cut.has("node") and is_instance_valid(cut.node): Wood.update_kerf(cut.node, cut)

func _start_cut(h: Dictionary):
	var tree: AshTree = game.tree
	if h.kind == "tree" or h.kind == "stump":
		var inv := tree.global_transform.basis.inverse()
		var e := tree.to_wood(h.p); var fl := (inv * f).normalized(); var nl := (inv * n).normalized()
		var c: Dictionary = tree.start_cut(e, fl, nl) if h.kind == "tree" else tree.stump_start_cut(e, fl, nl)
		c.part = {trunk = true}
		return c
	var pc: WoodPiece = h.piece
	var inv := pc.global_transform.basis.inverse()
	var e := pc.to_wood(h.p); var fl := (inv * f).normalized(); var nl := (inv * n).normalized()
	var part: Dictionary = h.part
	# a cut already started in this piece at the same place picks up where it left off
	if not part.has("limb"):
		for op in pc.ops:
			if op.type == "kerf" and not op.get("done", false) and absf(op.n.dot(nl)) > 0.97 and absf(op.n.dot(e - op.e)) < 0.04 and op.f.dot(fl) > 0.9:
				op.piece = pc; op.part = part
				return op
	var inside := func(p: Vector3) -> bool: return pc.inside_limb(p, part) if part.has("limb") else pc.inside_trunk(p)
	var ch = AshTree.chord(inside, e, fl, -0.05, 1.4)
	var c := {kind = "piece", type = "kerf", piece = pc, part = part, e = e, f = fl, n = nl, s = 0.0, exit = 0.05}
	if ch != null:
		c.e = e + fl * ch.x
		c.exit = maxf(0.02, ch.y - ch.x)
	if not part.has("limb") and pc.csg:
		pc.ops.append(c)
		c.node = Wood.op_node(c)
		pc.csg.add_child(c.node)
	return c

func _finish_piece_cut(c: Dictionary) -> void:
	var pc: WoodPiece = c.piece
	var T: Dictionary = pc.T
	var part: Dictionary = c.part
	if part.has("limb"):
		var L: Dictionary = T.limbs[part.limb]
		var ta := pc.t0 if pc.kind == "limb" else 0.0
		var tb: float = pc.t1 if pc.kind == "limb" else pc.lt.get(part.limb, 1.0)
		var tt: float
		if part.has("sub"): tt = L.subs[part.sub].t - 0.02
		else:
			var d: float = c.n.dot(L.dir) * L.len
			tt = c.n.dot(c.e - L.base) / d if absf(d) > 1e-4 else (ta + tb) / 2
		tt = clampf(tt, ta, tb)
		if pc.kind == "trunk":
			if tt - ta < 0.06: Lumber.limb_off(game, pc, part.limb)
			elif tb - tt > 0.04: Lumber.cut_limb_at(game, pc, part.limb, tt)
		elif tt - ta > 0.03 and tb - tt > 0.03:
			Lumber.split_limb(game, pc, tt)
		game.update_objectives()
		return
	if pc.kind == "trunk" or pc.kind == "slab":
		c.done = true
		Lumber.buck(game, pc, c)
		game.update_objectives()

# ---------------------------------------------------------------- start / stop
func pull_start() -> void:
	if on: stop(); return
	if pull > 0: return
	pull = 0.5; pulls += 1
	Sfx.play("pull")
	await get_tree().create_timer(0.38).timeout
	if player.tool != "saw": return
	if (pulls >= 2 and randf() < 0.6) or pulls >= 4:
		on = true; pulls = 0
		engine_snd = Sfx.engine("saw")
		game.hud.toast("Saw running.", 1.8)
	else:
		Sfx.play("sputter")
		game.hud.toast("Choke is on. Pull again." if pulls == 1 else "Sputter… pull again.", 1.4)

func stop() -> void:
	on = false
	cutting = false
	cut = null
	if engine_snd: engine_snd.stop(); engine_snd = null

# ---------------------------------------------------------------- sawdust
func _emit(p: Vector3, v: Vector3, count: int, col: Color, spread: float, size: float) -> void:
	for i in range(count):
		if chips.size() > 500: chips.pop_front()
		chips.append({p = p, v = v + Vector3((randf() - 0.5) * spread, (randf() - 0.2) * spread, (randf() - 0.5) * spread),
			col = MeshBuilder.shade(col, 0.8 + randf() * 0.4), s = size * (0.6 + randf() * 0.8), age = 0.0})

func emit_chips(p: Vector3, v: Vector3, count: int, col: Color, spread: float, size: float) -> void:
	_emit(p, v, count, col, spread, size)

func add_dust(x: float, z: float, amt: float, col: Color) -> void:
	var key := Vector2i(roundi(x / 0.11), roundi(z / 0.11))
	if not piles.has(key):
		if piles.size() > 2500: return
		piles[key] = {x = key.x * 0.11, z = key.y * 0.11, a = 0.0, col = col}
	piles[key].a += amt
	_pile_dirty = true

func step_particles(dt: float) -> void:
	var world: WorldGen = game.world
	var keep := []
	for q in chips:
		q.age += dt
		q.v.y -= 6 * dt
		q.v *= 1 - 1.2 * dt
		q.p += q.v * dt
		var gy := world.H(q.p.x, q.p.z) + 0.01
		if q.p.y < gy:
			add_dust(q.p.x, q.p.z, q.s * q.s * 3.5, q.col)
			continue
		if q.age < 8: keep.append(q)
	chips = keep
	var mm := chip_mm.multimesh
	mm.instance_count = chips.size()
	for i in range(chips.size()):
		var q: Dictionary = chips[i]
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * q.s), q.p))
		mm.set_instance_color(i, q.col)
	_pile_t += dt
	if _pile_dirty and _pile_t > 0.25:
		_pile_dirty = false; _pile_t = 0
		var pm := pile_mm.multimesh
		pm.instance_count = piles.size()
		var i := 0
		for key in piles:
			var c: Dictionary = piles[key]
			var rx := minf(0.17, 0.05 + sqrt(c.a) * 0.55); var ry := minf(0.09, 0.004 + c.a * 2.2)
			var j := fmod(absf(c.x * 31 + c.z * 17), 1.0)
			pm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(rx, ry, rx * (0.85 + j * 0.3))), Vector3(c.x + (j - 0.5) * 0.04, world.H(c.x, c.z) - ry * 0.25, c.z)))
			pm.set_instance_color(i, c.col)
			i += 1
