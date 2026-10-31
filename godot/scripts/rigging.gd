## Felling wedges and the pull rope: the two ways to talk a leaning tree into going where you want.
## Wedges: once the back cut is a few inches in, tap plastic wedges into the kerf behind the bar. Driven
## tight, each one lifts the back of the tree a little, tipping it toward the notch.
## Pull rope: tie it high on the trunk, hook the other end on the truck's hitch, and drive off to take up
## the slack. While it's tight the rope pulls the top over toward the truck. Too tight and it snaps.
class_name Rigging
extends Node3D

const WEDGE_LEN := 0.2
const WEDGE_MAX := 0.17         # how deep a wedge goes (driven tight)
const WEDGE_LIFT := 0.07        # radians of tilt one tight wedge gives
const WEDGE_HIT := 0.034        # depth per hammer blow
const ROPE_MAX_PULL := 0.22     # radians, rope bar-tight
const ROPE_TIGHT := 1.0         # metres of stretch for a full pull
const ROPE_SNAP := 2.6          # metres of stretch before it lets go

var game
var wedges: Array = []          # {cut, side, depth, node}
var rope_used := false          # the pull rope went on the tree at some point this job
var rope := ""                  # "" | "tree" (tied on the tree) | "rigged" (tree to truck)
var rope_pt := Vector3.ZERO     # tie-off on the tree, in the wood frame
var rope_piece: WoodPiece = null   # a log the rope's tied round (dragging logs out of the water), or null for the tree
var rope_local := Vector3.ZERO      # where on the log, in the log's own frame
var _was_wet := true
var anchor_w := Vector3.ZERO    # where the tie-off was when you tied it: tension is measured from here, so
                                # the tree easing over toward the truck doesn't quietly let the rope go slack
var rope_len := 0.0
var rope_stretch := 0.0
var rope_im: ImmediateMesh
var rope_mi: MeshInstance3D
var hammer: MeshInstance3D
var held_wedge: MeshInstance3D
var coil: MeshInstance3D
var swing := 0.0                # hammer swing, counts down
var wedge_mesh: ArrayMesh
var _tip := ""
var holder = null              # whoever tied the rope on and is walking the other end (null: you)
var net_line: Array = []       # on a crew member's game: the rope as the host has it [a, b, slack]
var holder_peer := 0

func setup(g) -> void:
	game = g
	wedge_mesh = _wedge_mb().commit()
	var cam: Node3D = game.player.hands
	hammer = _hammer_mb().instance(); cam.add_child(hammer)
	held_wedge = MeshInstance3D.new(); held_wedge.mesh = wedge_mesh; held_wedge.material_override = Mats.vcol; cam.add_child(held_wedge)
	coil = _coil_mb().instance(); cam.add_child(coil)
	for m in [hammer, held_wedge, coil]:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
	rope_im = ImmediateMesh.new()
	rope_mi = MeshInstance3D.new(); rope_mi.mesh = rope_im; rope_mi.top_level = true
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color("#d8b030"); rm.roughness = 0.9
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	rope_mi.material_override = rm
	rope_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rope_mi)

static func owned(id: String) -> bool:
	if Jobs.ALL_OPEN and (id == "wedges" or id == "rope" or id == "climb" or id == "lowrig"): return true
	return bool(Career.load().get(id, false))

# ---------------------------------------------------------------- models
## an orange plastic felling wedge: thick at the back, thin at the nose, with ribs on top. Nose toward +z.
func _wedge_mb() -> MeshBuilder:
	var mb := MeshBuilder.new()
	var c := Color("#f07a1a"); var w := 0.07
	var back := 0.032
	var pts := [Vector3(-w / 2, back / 2, 0), Vector3(w / 2, back / 2, 0), Vector3(w / 2, 0.002, WEDGE_LEN), Vector3(-w / 2, 0.002, WEDGE_LEN)]
	mb.face(pts, c)
	var bot := [Vector3(-w / 2, -back / 2, 0), Vector3(-w / 2, -0.002, WEDGE_LEN), Vector3(w / 2, -0.002, WEDGE_LEN), Vector3(w / 2, -back / 2, 0)]
	mb.face(bot, MeshBuilder.shade(c, 0.8))
	for sx: float in [-1.0, 1.0]:
		var side := [Vector3(sx * w / 2, back / 2, 0), Vector3(sx * w / 2, -back / 2, 0), Vector3(sx * w / 2, -0.002, WEDGE_LEN), Vector3(sx * w / 2, 0.002, WEDGE_LEN)]
		if sx < 0: side.reverse()
		mb.face(side, MeshBuilder.shade(c, 0.9))
	mb.face([Vector3(-w / 2, -back / 2, 0), Vector3(w / 2, -back / 2, 0), Vector3(w / 2, back / 2, 0), Vector3(-w / 2, back / 2, 0)], MeshBuilder.shade(c, 0.7))
	for k in range(3): mb.box(0, back / 2 - k * 0.004, 0.03 + k * 0.035, w * 0.9, 0.004, 0.006, MeshBuilder.shade(c, 0.75))
	return mb

## a short-handled sledge, held at the grip (the origin): hickory handle up +y with a rubber grip, and
## the steel head across the top lying along z, so as the handle swings forward (about x) the striking
## face on the head's -z end is what leads into the wedge
func _hammer_mb() -> MeshBuilder:
	var mb := MeshBuilder.new()
	mb.tube(Vector3(0, -0.06, 0), Vector3(0, 0.34, 0), 0.016, 0.014, Color("#b48a52"), 8, true)
	mb.tube(Vector3(0, -0.07, 0), Vector3(0, 0.05, 0), 0.021, 0.021, Color("#2a2a28"), 8, true)
	mb.bevel_box(0, 0.36, 0, 0.055, 0.058, 0.15, Color("#5a5e64"), 0.008)
	for sz: float in [-1.0, 1.0]: mb.box(0, 0.36, sz * 0.077, 0.062, 0.064, 0.012, Color("#8a8e92"))   # the two faces
	return mb

## a coil of yellow bull rope
func _coil_mb() -> MeshBuilder:
	var mb := MeshBuilder.new()
	for k in range(4):
		var rr := 0.11 + k * 0.012
		var n := 14
		for i in range(n):
			var a0 := TAU * i / n; var a1 := TAU * (i + 1) / n
			mb.tube(Vector3(cos(a0) * rr, sin(a0) * rr * 1.1, k * 0.012), Vector3(cos(a1) * rr, sin(a1) * rr * 1.1, k * 0.012), 0.012, 0.012, Color("#d8b030").lerp(Color("#b8902a"), k * 0.25), 5)
	return mb

# ---------------------------------------------------------------- held in your hands
func pose(dt: float) -> void:
	var tool: String = game.player.tool
	var walking: bool = not game.player.in_truck
	hammer.visible = walking and tool == "wedge"
	held_wedge.visible = walking and tool == "wedge"
	coil.visible = walking and tool == "rope"
	swing = maxf(0.0, swing - dt)
	if hammer.visible:
		# a short chop: cock it back, swing the head down and forward onto the wedge, bounce back up.
		# The handle pivots at your hand; the angle is how far the handle's tipped forward from upright.
		var rest := 0.45
		var ang := rest
		if swing > 0:
			var p := clampf(1.0 - swing / 0.28, 0, 1)
			if p < 0.3: ang = lerpf(rest, 0.05, p / 0.3)                               # wind up
			elif p < 0.62: ang = lerpf(0.05, 1.45, ease((p - 0.3) / 0.32, 0.4))       # strike
			else: ang = lerpf(1.45, rest, (p - 0.62) / 0.38)                          # recover
		var reach := clampf((ang - rest) / (1.45 - rest), 0, 1)
		hammer.transform = Transform3D(Basis(Vector3.RIGHT, -ang) * Basis(Vector3.BACK, 0.12), Vector3(0.2 - reach * 0.08, -0.3 + reach * 0.04, -0.42 - reach * 0.12))
		held_wedge.transform = Transform3D(Basis(Vector3.RIGHT, -0.25) * Basis(Vector3.UP, PI * 0.1), Vector3(-0.23, -0.23, -0.6))
	if coil.visible:
		coil.transform = Transform3D(Basis(Vector3.UP, 0.5).scaled(Vector3(0.55, 0.55, 0.55)), Vector3(-0.3, -0.3, -0.62))

# ---------------------------------------------------------------- aiming
## the back cut under the crosshair that can take a wedge, or {}
func _wedge_target() -> Dictionary:
	var tree: AshTree = game.tree
	if tree.state != "stand": return {}
	var notch := []
	for w in tree.freed.values(): notch.append(w.c1); notch.append(w.c2)
	var eye: Vector3 = game.player.eye(); var dir: Vector3 = game.player.aim_dir()
	var best := {}; var bd := 1e9
	for c in tree.cuts:
		if notch.has(c) or c.s < 0.004 or absf((c.n as Vector3).y) < 0.7: continue
		var e := tree.to_world(c.e)
		var to := e - eye
		if to.length() > 2.2 or to.normalized().dot(dir) < 0.72: continue
		var score := to.length() - to.normalized().dot(dir) * 2.0
		if score < bd: bd = score; best = {cut = c, e = e}
	return best

func _near_tree() -> bool:
	var tree: AshTree = game.tree
	if tree.state != "stand": return false
	var p: Vector3 = game.player.global_position
	var b := tree.global_position
	if Vector2(p.x - b.x, p.z - b.z).length() > 3.4: return false
	var to: Vector3 = (tree.to_world(Vector3(0, 1.6, 0)) - game.player.eye()).normalized()
	return to.dot(game.player.aim_dir()) > 0.55

func _near_hitch() -> bool:
	return game.player.global_position.distance_to(game.truck.hitch_world()) < 2.8

## what E / left click would do right now with the wedges or rope in hand ("" if nothing)
func prompt() -> String:
	var tool: String = game.player.tool
	if tool == "wedge":
		var tg := _wedge_target()
		if tg.is_empty():
			return "Aim at your back cut to set a wedge" if game.tree.state == "stand" and _near_tree() else ""
		if tg.cut.s < 0.06: return "Cut the back cut a little deeper first"
		var w = _wedge_in(tg.cut)
		if w == null: return "[b]Left click[/b] Set a wedge in the back cut" + (" (%d in)" % wedges.size() if wedges.size() > 0 else "")
		if w.depth >= _wedge_max(tg.cut) - 0.002: return "Driven tight · [b]Left click[/b] set another beside it" if _count_in(tg.cut) < 3 else "Wedges driven tight"
		return "[b]Left click[/b] Drive the wedge · %d%%" % roundi(w.depth / _wedge_max(tg.cut) * 100)
	if tool == "rope":
		match rope:
			"":
				if not _aimed_log().is_empty(): return "[b]Left click[/b] Tie the rope round this log"
				if _near_tree(): return "[b]Left click[/b] Throw the rope up and tie it off on the trunk"
			"tree":
				if _near_hitch(): return "[b]Left click[/b] Hook the rope on the truck's hitch"
				if _near_tie(): return "[b]Left click[/b] Untie the rope"
				return ("Rope's round the log" if rope_piece else "Rope's on the tree") + " · take the other end to the truck's hitch"
			"rigged":
				if rope_piece: return ("[b]Left click[/b] Unhook the rope" if _near_hitch() or _near_tie() else "Rope's on the log and the truck") + " · drive away to drag it out"
				if _near_hitch() or _near_tree(): return "[b]Left click[/b] Unhook the rope" + _tension_txt()
				return "Rope rigged" + _tension_txt() + " · drive the truck away to take up the slack"
	return ""

func _tension_txt() -> String:
	if rope_stretch <= 0.0: return " · slack"
	if rope_stretch > ROPE_SNAP * 0.7: return " · TOO TIGHT, ease off!"
	if rope_stretch >= ROPE_TIGHT: return " · bar-tight, good"
	return " · taking up slack %d%%" % roundi(rope_stretch / ROPE_TIGHT * 100)

func _wedge_max(c: Dictionary) -> float:
	return minf(WEDGE_MAX, c.s - 0.015)

func _wedge_in(c: Dictionary):
	var latest = null
	for w in wedges:
		if w.cut == c and (latest == null or w.depth < latest.depth): latest = w
	return latest

func _count_in(c: Dictionary) -> int:
	return wedges.filter(func(w): return w.cut == c).size()

# ---------------------------------------------------------------- using them
func use() -> bool:
	if Net.is_guest() and Net.job:
		# the host's game does the hammering and the tying; we just swing
		if prompt() == "": return false
		if game.player.tool == "wedge": swing = 0.28
		Net.ask("rig", [game.net_pose()])
		return true
	match game.player.tool:
		"wedge": return _hit()
		"rope": return _rope_action()
	return false

func _hit() -> bool:
	var tg := _wedge_target()
	if tg.is_empty():
		if game.tree.state == "stand" and _near_tree():
			game.hud.toast("Wedges go in the back cut, right behind the bar. Make your notch, then start the back cut from the other side.", 4.0)
			return true
		return false
	var c: Dictionary = tg.cut
	swing = 0.28
	if c.s < 0.06:
		game.hud.toast("Not deep enough for a wedge yet. Get the back cut a few inches in.", 2.5)
		return true
	var w = _wedge_in(c)
	var tight: bool = w != null and w.depth >= _wedge_max(c) - 0.002
	if w == null or (tight and _count_in(c) < 3):
		w = {cut = c, side = [0.0, 0.12, -0.12][_count_in(c)], depth = 0.04, node = null}
		var mi := MeshInstance3D.new(); mi.mesh = wedge_mesh; mi.material_override = Mats.vcol
		game.tree.add_child(mi)
		w.node = mi
		wedges.append(w)
		Sfx.play("pick", 0.8)
		_place(w)
		_update_push()
		return true
	if w.depth >= _wedge_max(c) - 0.002:
		game.hud.toast("That's as tight as they go.", 1.5)
		Sfx.play("clank", 0.5, 0.8)
		return true
	w.depth = minf(_wedge_max(c), w.depth + WEDGE_HIT)
	_place(w)
	_update_push()
	Sfx.play("clank", 0.9, randf_range(0.85, 1.05))
	Sfx.play("thud", 0.35, 1.6)
	if game.tree.sits_back(): Sfx.play("creak", 0.25, randf_range(1.1, 1.4))
	return true

## seat the wedge in its kerf: nose in along the cut, sunk by how far it's been driven
func _place(w: Dictionary) -> void:
	var c: Dictionary = w.cut
	var f: Vector3 = c.f; var n: Vector3 = c.n
	if n.y < 0: n = -n
	var across := n.cross(f).normalized()
	var p: Vector3 = (c.e as Vector3) + across * w.side + f * (w.depth - WEDGE_LEN)
	var basis := Basis(across, n, f).orthonormalized()
	(w.node as Node3D).transform = Transform3D(basis, p)

func _update_push() -> void:
	var tree: AshTree = game.tree
	var push := Vector3.ZERO
	for w in wedges:
		var c: Dictionary = w.cut
		var f: Vector3 = tree.global_transform.basis * (c.f as Vector3); f.y = 0
		if f.length() < 0.01: continue
		push += f.normalized() * WEDGE_LIFT * clampf(w.depth / WEDGE_MAX, 0, 1)
	if rope == "rigged" and rope_stretch > 0.0:
		var d: Vector3 = game.truck.hitch_world() - tree.global_position; d.y = 0
		push += d.normalized() * clampf(rope_stretch / ROPE_TIGHT, 0, 1) * ROPE_MAX_PULL
	tree.push = push

func _rope_action() -> bool:
	var tree: AshTree = game.tree
	match rope:
		"":
			var lg := _aimed_log()
			if not lg.is_empty():
				rope_piece = lg.piece
				rope_local = rope_piece.global_transform.affine_inverse() * (lg.p as Vector3)
				rope = "tree"; rope_used = true
				holder = game.player
				anchor_w = _anchor()
				_was_wet = true
				Sfx.play("pick")
				game.hud.toast("You get the bull rope round the log and cinch it tight. Now take the other end to the truck's hitch.", 4.0)
				return true
			if not _near_tree(): return false
			rope_piece = null
			var p: Vector3 = game.player.global_position
			var lp := tree.to_wood(p); lp.y = 0
			var y: float = minf(tree.T.H * 0.55, 9.5)
			rope_pt = Vector3(0, y, 0) + lp.normalized() * Wood.r_at(tree.T, y)
			rope = "tree"; rope_used = true
			holder = game.player
			anchor_w = _anchor()
			Sfx.play("pick")
			game.hud.toast("You toss a throw line over a limb and haul the rope up. Tied off about %d ft up. Now take the other end to the truck's hitch." % roundi(y * 3.28), 5.0)
			return true
		"tree":
			if _near_hitch():
				rope = "rigged"
				rope_len = (_anchor() if rope_piece else anchor_w).distance_to(game.truck.hitch_world()) + 0.6
				Sfx.play("clank")
				if rope_piece: game.hud.toast("Rope's on the hitch. Get in and drive up the lawn, nice and slow, to drag the log out.", 4.5)
				else: game.hud.toast("Rope's on the hitch. Get in and ease the truck away until it's bar-tight (don't overdo it), park, then go make your cuts.", 5.5)
				return true
			if _near_tie():
				rope = ""; rope_piece = null; Sfx.play("pick"); game.hud.toast("Rope's off.", 1.5); return true
			return false
		"rigged":
			if _near_hitch() or _near_tie():
				rope = ""; rope_stretch = 0.0; rope_piece = null; _update_push()
				Sfx.play("pick"); game.hud.toast("Rope's off.", 1.5)
				return true
	return false

func _anchor() -> Vector3:
	if rope_piece and is_instance_valid(rope_piece): return rope_piece.global_transform * rope_local
	return game.tree.to_world(rope_pt)

## the log under the crosshair, within arm's reach: {piece, p} or {}
func _aimed_log() -> Dictionary:
	var e: Vector3 = game.player.eye()
	var q := PhysicsRayQueryParameters3D.create(e, e + game.player.aim_dir() * 3.0)
	q.collision_mask = 8
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit.collider is WoodPiece): return {}
	var wp := hit.collider as WoodPiece
	if wp.kind != "trunk" or wp.mode != "dyn": return {}
	return {piece = wp, p = hit.position}

## close enough to where the rope's tied (the log, or the tree)
func _near_tie() -> bool:
	if rope_piece and is_instance_valid(rope_piece): return game.player.global_position.distance_to(_anchor()) < 3.2
	return _near_tree()

# ---------------------------------------------------------------- every frame
func physics_step(_dt: float) -> void:
	if Net.is_guest(): return
	if rope_piece != null and not is_instance_valid(rope_piece):
		rope = ""; rope_piece = null; rope_stretch = 0.0
		return
	if rope == "rigged" and rope_piece:
		_drag_log()
		return
	if rope != "rigged" or game.tree.state != "stand": return
	var a := anchor_w; var hpt: Vector3 = game.truck.hitch_world()
	var d := a.distance_to(hpt)
	rope_stretch = d - rope_len
	if rope_stretch > ROPE_SNAP:
		rope = ""; rope_stretch = 0.0
		Sfx.play("crack", 0.7, 1.4)
		game.hud.toast("TWANG! You pulled too hard and the rope snapped. Tie on a fresh one and go easier.", 4.5)
		_update_push()
		return
	if rope_stretch > 0.0 and game.truck.driving:
		# while you're driving, the rope holds the truck back like a big spring; parked, the brakes hold it
		var dir := (a - hpt).normalized()
		game.truck.apply_central_force(dir * rope_stretch * 3000.0)
	_update_push()

## the rope's on a log and the truck: once it's tight, it hauls the log toward the truck
func _drag_log() -> void:
	var a := _anchor(); var hpt: Vector3 = game.truck.hitch_world()
	var d := a.distance_to(hpt)
	rope_stretch = d - rope_len
	if rope_stretch > ROPE_SNAP * 1.6:
		rope = ""; rope_piece = null; rope_stretch = 0.0
		Sfx.play("crack", 0.7, 1.4)
		game.hud.toast("TWANG! You yanked it too hard and the rope snapped. Tie it on again and drive slower.", 4.5)
		return
	if rope_stretch <= 0.0: return
	var dir := (hpt - a).normalized()
	var f := minf(rope_stretch * 6000.0, 14000.0)
	rope_piece.apply_force(dir * f, a - rope_piece.global_position)
	if game.truck.driving: game.truck.apply_central_force(-dir * f * 0.5)
	var c := rope_piece.center_world()
	var wet: bool = game.world.lake_d(c.x, c.z) < -0.4
	if _was_wet and not wet:
		_was_wet = false
		Sfx.play("thud", 0.8, 0.8)
		game.hud.toast("That one's out of the water! Unhook it and go get the next.", 3.0)
		game.update_objectives()

func step(dt: float) -> void:
	pose(dt)
	_draw_rope()

## the rope as it hangs: [tie-off, other end, sag] or [] when there's no rope out
func rope_line() -> Array:
	if rope == "" or (rope_piece == null and game.tree.state != "stand"): return []
	var a := _anchor()
	var b: Vector3
	var slack := 0.0
	if rope == "rigged":
		b = game.truck.hitch_world()
		slack = sqrt(maxf(rope_len * rope_len - a.distance_squared_to(b), 0.0)) * 0.5
	else:
		# hanging down the trunk to the ground, or to the hand of whoever's walking it to the truck
		var hp = holder if holder != null and is_instance_valid(holder) else game.player
		if hp.tool == "rope" and not hp.in_truck:
			b = hp.global_position + Vector3(0, 1.1, 0) + hp.fwd() * 0.3
			slack = clampf(a.distance_to(b) * 0.12, 0.3, 2.5)
		else:
			b = game.tree.global_position + Vector3(0.4, 0.05, 0.4)
	return [a, b, slack]

## for the crew: the rope, the log it's on, how tight, who's holding the end, and where the wedges sit
func net_state(job) -> Array:
	var wx := []
	for w in wedges:
		if is_instance_valid(w.node): wx.append((w.node as Node3D).transform)
	var line := rope_line()
	if not line.is_empty(): line = [line[0], line[1], snappedf(line[2], 0.05)]
	return [rope, line, job.nid_of(rope_piece) if rope_piece else 0, snappedf(rope_stretch, 0.05), job._peer_of(holder) if rope == "tree" else 0, wx]

func net_apply(a: Array, job) -> void:
	rope = str(a[0])
	net_line = a[1]
	rope_piece = job.mirrors.get(int(a[2])) if int(a[2]) != 0 else null
	if rope_piece != null and not is_instance_valid(rope_piece): rope_piece = null
	rope_stretch = float(a[3])
	holder_peer = int(a[4])
	job.show_wedges(a[5], wedge_mesh)

func _draw_rope() -> void:
	rope_im.clear_surfaces()
	var L := rope_line() if not Net.is_guest() else net_line.duplicate()
	if L.is_empty(): return
	var a: Vector3 = L[0]
	var b: Vector3 = L[1]
	var slack: float = L[2]
	# the end in my own hands follows me, not the host's last word on where I was
	if Net.is_guest() and rope == "tree" and holder_peer == Net.me() and game.player.tool == "rope" and not game.player.in_truck:
		b = game.player.global_position + Vector3(0, 1.1, 0) + game.player.fwd() * 0.3
		slack = clampf(a.distance_to(b) * 0.12, 0.3, 2.5)
	var n := 18
	var pts := []
	for i in range(n + 1):
		var t := float(i) / n
		var p := a.lerp(b, t)
		p.y -= slack * 4.0 * t * (1.0 - t)
		pts.append(p)
	var cam := get_viewport().get_camera_3d()
	rope_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		var p0: Vector3 = pts[i]; var p1: Vector3 = pts[i + 1]
		var along := (p1 - p0).normalized()
		var side := along.cross((cam.global_position - p0).normalized() if cam else Vector3.UP).normalized() * 0.018
		for q in [p0 - side, p1 - side, p1 + side, p0 - side, p1 + side, p0 + side]:
			rope_im.surface_set_normal(Vector3.UP)
			rope_im.surface_add_vertex(q)
	rope_im.surface_end()

## the tree's going: the rope goes slack and the wedges drop out of the kerf
func on_fell() -> void:
	if rope != "": game.hud.toast("The rope goes slack as it comes down. You'll coil it back up.", 3.0)
	rope = ""; rope_stretch = 0.0
	for w in wedges:
		if is_instance_valid(w.node): w.node.queue_free()
	wedges.clear()
	rope_im.clear_surfaces()
