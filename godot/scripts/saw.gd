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
# guided cutting: aim at the trunk or a log and the cut goes exactly there, square across unless you tilt it
var _side := 1.0               # which side of the wood the cut starts from (sticky while you aim near the middle)
var tilt := 0.0                # radians; + slopes down into the wood (a notch's top cut), − slopes up
var guide := {}                # what the crosshair is on: {kind, xf, e, f, n, existing, piece}
var chain_mm: MultiMeshInstance3D
var chain_pos := 0.0           # how far the chain has run round the bar (m)
var guide_mi: MeshInstance3D
var guide_im: ImmediateMesh
const GUIDE_REACH := 1.75
const MAX_REACH := 1.08         # how far from your eyes the saw can be held (arms stay arm-length)
# the chain loop: straight along the top and bottom of the bar, round the nose and the drive sprocket
const CHAIN_Z0 := -0.24        # drive sprocket centre
const CHAIN_Z1 := -0.83        # nose sprocket centre
const CHAIN_R := 0.041
const CHAIN_LINKS := 60
const SHOULDER_R := Vector3(0.24, -0.72, 0.2)
const SHOULDER_L := Vector3(-0.32, -0.7, 0.18)
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
	# the chain: links running round the bar (over the top toward the nose, back along the bottom)
	chain_mm = MultiMeshInstance3D.new()
	var cmm := MultiMesh.new(); cmm.transform_format = MultiMesh.TRANSFORM_3D
	cmm.mesh = Models.chain_link().commit(); cmm.instance_count = CHAIN_LINKS
	chain_mm.multimesh = cmm; chain_mm.material_override = Mats.vcol
	chain_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(chain_mm)
	_place_chain()
	fist_r = Models.fist(1).instance(); fist_l = Models.fist(-1).instance()
	arm_r = Models.arm().instance(); arm_l = Models.arm().instance()
	for m in [model, fist_r, fist_l, arm_r, arm_l]:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for m in [fist_r, fist_l, arm_r, arm_l]:
		add_child(m)
	# the cut guide: a bright line round the wood where the cut will go
	guide_im = ImmediateMesh.new()
	guide_mi = MeshInstance3D.new(); guide_mi.mesh = guide_im; guide_mi.top_level = true
	guide_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.vertex_color_use_as_albedo = true
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.no_depth_test = false
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	guide_mi.material_override = gm
	add_child(guide_mi)
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
	# with the saw running and the line on a trunk or log in reach, the saw sits right on that line
	# (so the ring and the bar always agree); otherwise it rests at your hip until you rev
	var on_guide: bool = not guide.is_empty() and not guide.get("too_far", false)
	var want := 1.0 if (on and not carrying and (rev or on_guide)) else 0.0
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
	var cw0 := player.cam.global_transform
	# guided: lay the bar right on the guide line, square to the cut, and feed it in as the cut deepens
	guide = _find_guide() if (player.tool == "saw" and not carrying) else {}
	if not guide.is_empty():
		var g: Dictionary = guide
		var xf: Transform3D = g.xf
		var ew: Vector3 = xf * g.e
		var fw: Vector3 = (xf.basis * g.f).normalized()
		var nw: Vector3 = (xf.basis * g.n).normalized()
		var depth := 0.0
		if cut != null: depth = cut.s
		elif g.existing != null: depth = g.existing.s
		# the bar points away from you across the wood, in the cut's plane; its chain edge on the cut front
		var gw := nw.cross(fw).normalized()
		var bar_dir := gw if gw.dot(-cw0.basis.z) > 0 else -gw
		var front := ew + fw * (depth - 0.01)
		# centre the bar on the wood: the heart of the trunk, carried onto the cut front line
		var heart: Vector3 = xf * (g.heart if g.has("heart") else Vector3(0, (g.e as Vector3).y, 0))
		var mid := front + bar_dir * bar_dir.dot(heart - front)
		# a thin branch: just the front of the bar across it, the saw held back at a comfortable reach
		if g.has("ring_r"): mid += bar_dir * maxf(0.0, BAR_L * 0.5 - float(g.ring_r) - 0.12)
		var zb := -bar_dir
		var xb := nw
		var yb := zb.cross(xb)
		if yb.dot(fw) > 0: xb = -xb; yb = -yb          # the chain edge (underneath) faces into the cut
		var bw := mid + yb * 0.036 - bar_dir * (BAR_L * 0.5)
		var wxf := Transform3D(Basis(xb, yb, zb), bw - zb * BAR_BASE)
		# only within arm's reach: further off, the line shows where you'd cut but you have to step in
		var reach_d := (wxf * Vector3(0, 0.1, -0.1) - cw0.origin).length()
		var hand_ahead := -(cw0.affine_inverse() * (wxf * Vector3(0, 0.1, -0.05))).z
		g.too_far = reach_d > MAX_REACH
		# the saw would be in your face: stand back from the wood (up a tree you work close in to the stem)
		g.too_close = hand_ahead < (0.1 if player.climbing else 0.36)
		g.hand_ahead = hand_ahead
		if g.too_close: g.too_far = true
		if not g.too_far:
			var lx := cw0.affine_inverse() * wxf
			eq = Quaternion(lx.basis.orthonormalized()); ep = lx.origin
	k = smoothstep(0, 1, clampf(eng, 0, 1))
	var pos := ip.lerp(ep, k)
	var q := iq.slerp(eq, k)
	# the bar can't pass through wood: back the saw off to the bark, or to the cut front
	var cw := player.cam.global_transform
	var fc := q * Vector3(0, 0, -1)
	var bw := cw * (pos + q * Vector3(0, 0, BAR_BASE))
	var fw := (cw.basis * fc).normalized()
	if k > 0.5 and cut == null and guide.is_empty(): _magnet(dt, cw)
	if k > 0.5 and guide.is_empty():
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
	_fist_at(fist_r, arm_r, model.transform * Vector3(0, 0.098, 0.035), SHOULDER_R)
	_fist_at(fist_l, arm_l, model.transform * Vector3(-0.05, 0.172, -0.233), SHOULDER_L)
	_draw_guide()

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

## where a point a distance u round the chain loop sits, in saw space, and which way the chain runs there
func _chain_at(u: float) -> Array:
	var straight := CHAIN_Z0 - CHAIN_Z1
	var arc := PI * CHAIN_R
	var L := 2.0 * straight + 2.0 * arc
	u = fposmod(u, L)
	if u < straight:                       # along the top, out toward the nose
		return [Vector3(0, CHAIN_R, CHAIN_Z0 - u), Vector3(0, 0, -1)]
	u -= straight
	if u < arc:                            # round the nose
		var a := u / CHAIN_R
		return [Vector3(0, CHAIN_R * cos(a), CHAIN_Z1 - CHAIN_R * sin(a)), Vector3(0, -sin(a), -cos(a))]
	u -= arc
	if u < straight:                       # back along the bottom, toward the saw
		return [Vector3(0, -CHAIN_R, CHAIN_Z1 + u), Vector3(0, 0, 1)]
	u -= straight
	var b := u / CHAIN_R                   # round the drive sprocket (inside the body)
	return [Vector3(0, -CHAIN_R * cos(b), CHAIN_Z0 + CHAIN_R * sin(b)), Vector3(0, sin(b), cos(b))]

func _place_chain() -> void:
	var L := 2.0 * (CHAIN_Z0 - CHAIN_Z1) + 2.0 * PI * CHAIN_R
	var mm := chain_mm.multimesh
	for i in range(CHAIN_LINKS):
		var pr := _chain_at(chain_pos + L * i / CHAIN_LINKS)
		var d: Vector3 = pr[1]
		var out: Vector3 = (pr[0] as Vector3) - Vector3(0, 0, clampf((pr[0] as Vector3).z, CHAIN_Z1, CHAIN_Z0))
		var upv := out.normalized() if out.length() > 1e-4 else Vector3.UP
		var zb := -d
		var xb := upv.cross(zb).normalized()
		mm.set_instance_transform(i, Transform3D(Basis(xb, upv, zb), pr[0]))

## a gloved fist at p with its cuff turned toward the shoulder, and the sleeve running from the cuff
func _fist_at(fist: MeshInstance3D, arm: MeshInstance3D, p: Vector3, shoulder: Vector3) -> void:
	var to_sh := shoulder - p
	if to_sh.length() < 0.05: to_sh = Vector3(0, -1, 0.3)
	to_sh = to_sh.normalized()
	var up := Vector3.UP if absf(to_sh.y) < 0.95 else Vector3.BACK
	fist.transform = Transform3D(Basis.looking_at(-to_sh, up), p)
	_arm(arm, p + to_sh * 0.065, shoulder, 0.037)

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
		var p := Vector3(side * 0.24, -0.3 + boby, -0.55) if carrying else Vector3(side * (0.25 + bobx), -0.255 + boby, -0.52)
		# the forearm runs straight back and down from the fist, in line with it (no kink at the wrist)
		_fist_at(fist, arm, p, p + Vector3(side * 0.02, -0.3, 0.55))
		# rounds ride on the right shoulder: that hand's up holding them, out of sight
		var shouldering: bool = carrying and side > 0 and game.haul.carry.any(func(b): return not b.brushy())
		if shouldering: fist.visible = false; arm.visible = false
		# the rod's in the right hand: the rod model has its own grip, so that glove goes away like it does with a log
		if side > 0 and player.tool == "rod" and not carrying: fist.visible = false; arm.visible = false
	guide = {}
	_draw_guide()

# ---------------------------------------------------------------- the cut guide
## what's under the crosshair that can take a guided cut: the standing trunk, the stump, or a log
func _find_guide() -> Dictionary:
	var tree: AshTree = game.tree
	# while a cut is under way, the guide stays locked to it
	if cut != null:
		if cut.kind == "slimb" or cut.kind == "top":
			if tree.state != "stand" or not cut.has("gd"): return {}
			var gk: Dictionary = cut.gd.duplicate()
			gk.xf = tree.global_transform; gk.existing = cut
			return gk
		if cut.has("gd") and is_instance_valid(cut.get("piece")):
			var gd: Dictionary = cut.gd.duplicate()
			gd.xf = cut.piece.global_transform
			gd.existing = cut
			return gd
		var xf_c: Transform3D
		if cut.kind == "tree" or cut.kind == "stump": xf_c = tree.global_transform
		elif is_instance_valid(cut.get("piece")) and not cut.part.has("limb"): xf_c = cut.piece.global_transform
		else: return {}
		if cut.get("guided", false):
			return {kind = cut.kind, xf = xf_c, e = cut.e, f = cut.f, n = cut.n, existing = cut, piece = cut.get("piece"), T = cut.get("T", tree.T)}
		return {}
	var cam := player.cam
	var from := cam.global_position; var dir := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * GUIDE_REACH)
	q.collision_mask = 8 | 32 | 64 | 256
	q.exclude = [player.get_rid()]
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty(): return {}
	var col = hit.collider
	# up in the crown: a ring round a limb, or (climbing) a topping cut across the stem
	if tree.crown_body and is_instance_valid(tree.crown_body) and col == tree.crown_body:
		var cow = col.shape_owner_get_owner(col.shape_find_owner(hit.shape))
		var cpart: Dictionary = cow.get_meta("part", {}) if cow else {}
		if cpart.has("slimb"): return _crown_limb_guide(int(cpart.slimb), hit.position)
		# topping is done from below the cut: aim at the stem above your saddle (never at limb level by accident)
		if cpart.has("upper") and game.climb and game.climb.climbing and game.tree.to_wood(hit.position).y > game.climb.harness() + 0.25: return _top_guide(hit.position)
		return {}
	if col is WoodPiece and col.mode == "dyn":
		var lowner = col.shape_owner_get_owner(col.shape_find_owner(hit.shape))
		var lpart: Dictionary = lowner.get_meta("part", {}) if lowner else {}
		if lpart.has("limb"): return _limb_guide(col, lpart, hit.position)
	var kind := ""; var xf: Transform3D; var inside: Callable; var pc = null; var TT: Dictionary = tree.T
	var list: Array = []
	if tree.stand_body and is_instance_valid(tree.stand_body) and col == tree.stand_body:
		kind = "tree"; xf = tree.global_transform; inside = tree.standing_inside; list = tree.cuts
	elif tree.stump_body and is_instance_valid(tree.stump_body) and col == tree.stump_body:
		kind = "stump"; xf = tree.global_transform; inside = tree.stump_inside
		list = tree.stump_cuts.filter(func(c): return not c.get("done", false))
	elif col is WoodPiece and col.mode == "dyn" and (col.kind == "trunk" or col.kind == "slab"):
		var owner = col.shape_owner_get_owner(col.shape_find_owner(hit.shape))
		var part: Dictionary = owner.get_meta("part", {trunk = true}) if owner else {trunk = true}
		if part.has("limb") or part.has("tip") or part.has("wedge"): return {}
		kind = "piece"; pc = col; xf = col.global_transform; TT = col.T
		inside = func(p: Vector3) -> bool: return pc.inside_trunk(p)
		for op in pc.ops:
			if op.type == "kerf" and not op.get("done", false): list.append(op)
	else:
		return {}
	var inv := xf.affine_inverse()
	var e0 := inv * from; var dl := (inv.basis * dir).normalized()
	var t0 := maxf(0.0, from.distance_to(hit.position) - 0.25)
	var ch = AshTree.chord(inside, e0, dl, t0, t0 + 0.6)
	if ch == null: return {}
	var P: Vector3 = e0 + dl * ch.x
	if kind == "tree" and (P.y > AshTree.CSG_TOP - 0.35 or P.y < -0.25): return {}
	# You stand behind the saw: the bar points away from you, across the wood, and lies in the cut.
	# The chain edge eats in from the side of the trunk (or top of the log) you're aiming at, toward
	# the middle, so the cut advances square to the bar.
	var bh := Vector3(dl.x, 0, dl.z)                       # your line of sight, flattened across the wood
	if bh.length() < 0.05: return {}
	bh = bh.normalized()
	var qa := Vector3.UP.cross(bh).normalized()            # square to the bar, across the wood
	var off := Vector2(P.x, P.z).dot(Vector2(qa.x, qa.z))
	var R_here := Wood.r_at(TT, clampf(P.y, 0.0, TT.H))
	if absf(off) > R_here * 0.22: _side = -signf(off)
	var fh: Vector3 = qa * _side                            # from the aimed-at side toward the heart
	# an old cut right here, cut from this side: carry on with it
	var best = null; var best_d := 0.06
	for c in list:
		var hd := Vector2(c.f.x, c.f.z)
		if hd.length() < 0.2 or hd.normalized().dot(Vector2(fh.x, fh.z)) < 0.45: continue
		var pd := absf((c.n as Vector3).dot(P - c.e))
		if pd < best_d: best_d = pd; best = c
	if best != null:
		return {kind = kind, xf = xf, e = best.e, f = best.f, n = best.n, existing = best, piece = pc, T = TT}
	var fl := (fh * cos(tilt) + Vector3.DOWN * sin(tilt)).normalized()
	var nl := bh.cross(fl).normalized()
	# the cut starts where its plane meets the bark on that side, level with what you're aiming at
	var yc: float = P.y + (nl.x * P.x + nl.z * P.z) / nl.y if absf(nl.y) > 0.05 else P.y
	var C := Vector3(0, yc, 0)
	var back = AshTree.chord(inside, C, -fl, 0.0, 1.5)
	var e: Vector3 = C - fl * ((back.y if back != null else R_here) + 0.01)
	return {kind = kind, xf = xf, e = e, f = fl, n = nl, existing = null, piece = pc, T = TT, aim = P}

## a branch: the ring goes round it where you're looking, square to the branch
func _limb_guide(pc: WoodPiece, part: Dictionary, hitp: Vector3) -> Dictionary:
	var L: Dictionary = pc.T.limbs[part.limb]
	var a: Vector3; var b: Vector3; var r0: float; var r1: float
	if part.has("sub"):
		var sb: Dictionary = L.subs[part.sub]
		a = Wood.limb_pt(L, sb.t); b = a + sb.dir * sb.len; r0 = sb.r0; r1 = sb.r0 * 0.5
	else:
		var ta: float = pc.t0 if pc.kind == "limb" else 0.0
		var tb: float = pc.t1 if pc.kind == "limb" else pc.lt.get(part.limb, 1.0)
		a = Wood.limb_pt(L, ta); b = Wood.limb_pt(L, tb); r0 = Wood.limb_r(L, ta); r1 = Wood.limb_r(L, tb)
	var P := pc.to_wood(hitp)
	var cp := Geometry3D.get_closest_point_to_segment(P, a, b)
	var k := clampf((cp - a).dot(b - a) / maxf((b - a).length_squared(), 1e-9), 0.0, 1.0)
	var r := lerpf(r0, r1, k)
	var u := (b - a).normalized()
	# the bar points away from you, square across the branch; the chain comes down through it from above
	var inv_b := pc.global_transform.basis.inverse()
	var cf := (inv_b * -player.cam.global_transform.basis.z).normalized()
	var bar := cf - u * cf.dot(u)
	if bar.length() < 0.05: bar = u.cross(inv_b * Vector3.UP)
	bar = bar.normalized()
	var fl := u.cross(bar).normalized()
	if fl.dot(inv_b * Vector3.DOWN) < 0: fl = -fl
	var e := cp - fl * r
	return {kind = "piece", xf = pc.global_transform, e = e, f = fl, n = u, existing = null, piece = pc, T = pc.T,
		part = part, ring_c = cp, ring_r = r, heart = cp}

## a limb still on the standing tree: the ring goes round it where you're looking (like _limb_guide)
func _crown_limb_guide(id: int, hitp: Vector3) -> Dictionary:
	var tree: AshTree = game.tree
	var L: Dictionary = tree.T.limbs[id]
	var reach := float(tree.on_limbs.get(id, 1.0))
	var a := Wood.limb_pt(L, 0.0); var b := Wood.limb_pt(L, reach)
	var P := tree.to_wood(hitp)
	var cp := Geometry3D.get_closest_point_to_segment(P, a, b)
	var k := clampf((cp - a).dot(b - a) / maxf((b - a).length_squared(), 1e-9), 0.0, 1.0)
	var tt := reach * k
	var r := Wood.limb_r(L, tt)
	var u := (b - a).normalized()
	var inv_b := tree.global_transform.basis.inverse()
	var cf := (inv_b * -player.cam.global_transform.basis.z).normalized()
	var bar := cf - u * cf.dot(u)
	if bar.length() < 0.05: bar = u.cross(inv_b * Vector3.UP)
	bar = bar.normalized()
	var fl := u.cross(bar).normalized()
	if fl.dot(inv_b * Vector3.DOWN) < 0: fl = -fl
	return {kind = "slimb", id = id, t = tt, xf = tree.global_transform, e = cp - fl * r, f = fl, n = u, existing = null, piece = null,
		T = tree.T, part = {slimb = id}, ring_c = cp, ring_r = r, heart = cp}

## the stem above the cut zone, climbing: a level cut straight across, from your side toward the heart
func _top_guide(hitp: Vector3) -> Dictionary:
	var tree: AshTree = game.tree
	var P := tree.to_wood(hitp)
	var y := P.y
	if y <= AshTree.CSG_TOP + 0.2 or y >= tree.top_y - 0.3: return {}
	var fh := -Vector3(P.x, 0, P.z)
	if fh.length() < 0.01: return {}
	fh = fh.normalized()
	var r := Wood.r_at(tree.T, y)
	return {kind = "top", y = y, xf = tree.global_transform, e = Vector3(0, y, 0) - fh * (r + 0.01), f = fh, n = Vector3.UP,
		existing = null, piece = null, T = tree.T, heart = Vector3(0, y, 0)}

## the line where the cut will meet the bark (green when you'd be carrying on an old cut), and how deep it is
func _draw_guide() -> void:
	guide_im.clear_surfaces()
	if guide.is_empty() or not on and player.tool != "saw": return
	var g: Dictionary = guide
	var xf: Transform3D = g.xf
	var TT: Dictionary = g.T
	var e: Vector3 = g.e; var nn: Vector3 = g.n
	var col := Color(1.0, 0.62, 0.15, 0.9) if g.existing == null else Color(0.45, 1.0, 0.35, 0.9)
	if g.get("too_far", false): col = Color(1, 1, 1, 0.45)
	# up a tree: red when this cut would go through one of your own lines
	if game.climb and (g.kind == "slimb" or g.kind == "top") and game.climb.guide_danger(g) != "": col = Color(1.0, 0.15, 0.1, 0.95)
	if g.has("ring_c"):
		var c0: Vector3 = g.ring_c; var rr: float = g.ring_r * 1.12 + 0.004
		var ax: Vector3 = nn.normalized()
		var p0 := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
		var p1 := ax.cross(p0)
		var nwl := (xf.basis * ax).normalized()
		guide_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in range(33):
			var an := TAU * i / 32.0
			var pw := xf * (c0 + (p0 * cos(an) + p1 * sin(an)) * rr)
			guide_im.surface_set_color(col); guide_im.surface_add_vertex(pw - nwl * 0.007)
			guide_im.surface_set_color(col); guide_im.surface_add_vertex(pw + nwl * 0.007)
		guide_im.surface_end()
		return
	if absf(nn.y) > 0.2:
		# a thin glowing band round the bark (a strip, so it reads at any distance)
		var nw := (xf.basis * nn).normalized()
		guide_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in range(49):
			var a := TAU * i / 48.0
			var dx := cos(a); var dz := sin(a)
			var y := e.y
			for it in range(3):
				var R := Wood.r_at(TT, clampf(y, 0.0, TT.H)) * 1.03 + 0.004
				y = e.y - (nn.x * (R * dx - e.x) + nn.z * (R * dz - e.z)) / nn.y
			var R2 := Wood.r_at(TT, clampf(y, 0.0, TT.H)) * 1.03 + 0.004
			var pw := xf * Vector3(R2 * dx, y, R2 * dz)
			guide_im.surface_set_color(col); guide_im.surface_add_vertex(pw - nw * 0.009)
			guide_im.surface_set_color(col); guide_im.surface_add_vertex(pw + nw * 0.009)
		guide_im.surface_end()
	# how far in: a tick from the entry toward the far side
	var f: Vector3 = g.f
	var depth: float = (cut.s if cut != null else (g.existing.s if g.existing != null else 0.0))
	guide_im.surface_begin(Mesh.PRIMITIVE_LINES)
	guide_im.surface_set_color(col); guide_im.surface_add_vertex(xf * (e - f * 0.06))
	guide_im.surface_set_color(col); guide_im.surface_add_vertex(xf * (e + f * maxf(depth, 0.0)))
	guide_im.surface_end()

# ---------------------------------------------------------------- what does the bar touch?
func wood_hit(from: Vector3, dir: Vector3, max_t: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_t)
	q.collision_mask = 8 | 32 | 64 | 256
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
	if c.kind == "tree" or c.kind == "stump" or c.kind == "slimb" or c.kind == "top": xf = game.tree.global_transform
	else:
		if not is_instance_valid(c.piece) or c.piece.mode != "dyn": return {}
		xf = c.piece.global_transform
	return {e = xf * c.e, f = (xf.basis * c.f).normalized(), n = (xf.basis * c.n).normalized()}

# ---------------------------------------------------------------- cutting
func step(dt: float, rev: bool, carrying: bool) -> void:
	cutting = false; bind = false
	if pull > 0: pull = maxf(0, pull - dt)
	if on: rpm = lerpf(rpm, 1.0 if rev else 0.05, minf(1, dt * (6 if rev else 3)))
	else: rpm = lerpf(rpm, 0.0, minf(1, dt * 3))
	# the clutch: the chain only runs above idle; at speed it's a blur round the bar
	var cs := maxf(0.0, rpm - 0.25) / 0.75 * 2.4
	if cs > 0.0 and model.visible:
		# capped so it never strobes backwards (the eye can't follow a real chain anyway)
		var pitch := (2.0 * (CHAIN_Z0 - CHAIN_Z1) + 2.0 * PI * CHAIN_R) / CHAIN_LINKS
		chain_pos += minf(cs * dt, pitch * 0.42)
		_place_chain()
	if engine_snd: engine_snd.setv(rpm * (0.82 if cutting else 1.0), 0.0, 0.42)
	if player.tool != "saw" or not on or carrying: cut = null; return
	if not rev or k < 0.96: cut = null; return
	if not guide.is_empty() and guide.get("too_far", false):
		cut = null; return
	if cut == null and not guide.is_empty():
		cut = _start_guided(guide)
		if cut == null: return
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
	var aligned: bool = cut.get("guided", false) or (f.dot(W.f) > 0.93 and absf(n.dot(W.n)) > 0.97)
	var grain: Vector3
	if cut.kind == "tree" or cut.kind == "stump" or cut.kind == "top": grain = game.tree.global_transform.basis.y
	elif cut.kind == "slimb": grain = game.tree.global_transform.basis * (game.tree.T.limbs[int(cut.id)].dir as Vector3)
	else: grain = cut.piece.grain_world(cut.part)
	var crosses: bool = absf(W.n.dot(grain)) > 0.34
	cutting = true
	if engine_snd: engine_snd.setv(rpm * 0.82, 1.0, 0.42)
	# felling cuts in the standing tree never bind (switched off for now); limbs and logs still do
	if (not aligned or not crosses) and cut.kind != "tree": bind = true; return
	# felling cuts go at full speed; bucking a lying log is slower work (the whole bar is buried in it)
	var kind_k := 1.0
	if cut.kind == "piece": kind_k = 0.75 if cut.part.has("limb") else 0.32
	elif cut.kind == "tree": kind_k = 0.5
	elif cut.kind == "slimb": kind_k = 0.8
	elif cut.kind == "top": kind_k = 0.45
	var rate := Wood.CUT_SPEED * (0.35 + 0.65 * rpm) * kind_k
	var max_s: float = cut.exit + 0.004
	# the moment the tree starts to go, the bar stops eating the hinge
	if cut.kind == "tree" and game.tree.go_kind != "": rate = 0.0
	# a leaning tree sits its weight on the side it leans toward: cut in from that side and the kerf
	# closes on the bar part way through. The more it leans, the sooner. Back-cut from the other side.
	# (pinching on the lean side is switched off for now: felling cuts run free)
	if cut.s < max_s: cut.s = minf(max_s, cut.s + rate * dt)
	_emit(W.e, -W.f * 1.6 + Vector3(0, 0.9, 0), 3, Color("#e2cfa0"), 1.4, 0.026)
	if randf() < 0.5: _emit(W.e, -W.f + Vector3(0, 0.3, 0), 1, Color("#b89a6a"), 0.8, 0.045)
	match cut.kind:
		"tree":
			if game.tree.state != "stand": cut = null; return
			game.tree.cut_progress(cut)
		"slimb", "top":
			if game.tree.state != "stand": cut = null; return
			if cut.s >= cut.exit:
				var done: Dictionary = cut
				cut = null
				game.climb.finish_crown_cut(done)
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

## the bar spans the wood: a guided cut is as wide as the trunk or log (a straight cut across, like a real one)
func _guided_width(g: Dictionary) -> float:
	var TT: Dictionary = g.T
	var e: Vector3 = g.e
	return clampf(Wood.r_at(TT, clampf(e.y, 0.0, TT.H)) * 1.2, 0.08, BAR_L * 0.55)

var _pinch_told := false
func _pinched(c: Dictionary) -> bool:
	var tree: AshTree = game.tree
	var lean: float = tree.def.lean
	if lean < 0.03 or absf((c.n as Vector3).y) < 0.8: return false
	var lw := tree.global_transform.basis.inverse() * tree.lean_dir; lw.y = 0
	var side := Vector2((c.e as Vector3).x, (c.e as Vector3).z)
	if side.length() < 0.01 or lw.length() < 0.01: return false
	if side.normalized().dot(Vector2(lw.x, lw.z).normalized()) < 0.35: return false
	var D := 2.0 * Wood.r_at(tree.T, clampf((c.e as Vector3).y, 0.0, tree.T.H))
	var frac := clampf(1.0 - lean * 7.0, 0.4, 0.8)
	if c.s < D * frac: return false
	if not _pinch_told:
		_pinch_told = true
		game.hud.toast("Pinched! The tree leans this way and the cut's closing on the bar. Back-cut from the other side.", 4.5)
		Sfx.play("creak", 0.6)
	return true

func _start_guided(g: Dictionary):
	var tree: AshTree = game.tree
	var c
	match g.kind:
		"tree": c = tree.start_cut(g.e, g.f, g.n)
		"stump": c = tree.stump_start_cut(g.e, g.f, g.n)
		"slimb":
			c = {kind = "slimb", type = "ring", id = g.id, t = g.t, e = g.e, f = g.f, n = g.n, s = 0.0, exit = maxf(0.02, float(g.ring_r) * 2.0)}
			var gd1: Dictionary = g.duplicate(); gd1.erase("existing"); c.gd = gd1
		"top":
			c = {kind = "top", type = "ring", y = g.y, e = g.e, f = g.f, n = g.n, s = 0.0, exit = 2.0 * Wood.r_at(tree.T, float(g.y)) + 0.01}
			var gd2: Dictionary = g.duplicate(); gd2.erase("existing"); c.gd = gd2
		_:
			if not is_instance_valid(g.piece): return null
			c = _start_cut({kind = "piece", piece = g.piece, part = g.get("part", {trunk = true}), p = (g.xf as Transform3D) * g.e, fl = g.f, nl = g.n})
			if c != null and g.has("ring_c"):
				c.e = g.e; c.f = g.f; c.n = g.n; c.exit = maxf(0.02, g.ring_r * 2.0)
				var gd := g.duplicate(); gd.erase("existing"); c.gd = gd
	if c == null: return null
	c.part = c.get("part", {trunk = true})
	c.guided = true
	c.T = g.T
	if not c.has("w"):
		c.w = _guided_width(g)
		if c.has("node") and is_instance_valid(c.node): Wood.update_kerf(c.node, c)
	return c

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
	if h.has("fl"): fl = h.fl; nl = h.nl          # a guided cut says exactly which way it goes
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
	# on a crew member's game the host makes the cut; the pieces it makes come back from there
	if Net.is_guest() and Net.job:
		Net.job.cut_piece(c); return
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
