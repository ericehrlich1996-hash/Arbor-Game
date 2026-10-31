## The lowering rig: a rope through a block hung at the climber's tie-in, down the trunk to a friction
## brake at the base. Tie it round a limb (or the top you're about to cut) with the rope tool while
## you're in the tree, then make the cut: the piece swings off on the rope instead of falling.
## Let the rope run and it comes down; stop and it holds.
##   Playing alone you work the brake from up in the tree: hold G.
##   With a crew, anyone at the base of the tree with the rope tool can hold left mouse to run it.
## Let a heavy piece drop and catch it hard and it shock-loads the tree (you feel it in your spurs);
## catch it too hard and the rope parts.
## Everything here runs on the host's game; the crew sees the rope through net_line.
class_name Lower
extends Node

const RUN_SPEED := 1.6          # m/s of rope through the brake while it's let run
const SHOCK_FELT := 2.6         # m/s outward when the rope comes tight: you feel that
const SHOCK_SNAP := 6.0         # ...and this hard, the rope parts
const BASE_Y := 0.9             # the friction brake, on the trunk at waist height

var game
var tie := {}                   # waiting on a cut: {kind: "slimb" | "top", id, t, y, block_y, by}
var load: WoodPiece = null      # what's hanging on it now
var load_pt := Vector3.ZERO     # where the rope's tied, in the load's own frame
var block_y := 0.0
var rope_len := 0.0
var run_local := false
var run_remote_until := 0.0
var _rest_t := 0.0
var net_line: Array = []        # on a crew member's game: [block, tie, base] from the host
var rope_im: ImmediateMesh
var rope_mi: MeshInstance3D

func setup(g) -> void:
	game = g
	rope_im = ImmediateMesh.new()
	rope_mi = MeshInstance3D.new(); rope_mi.mesh = rope_im; rope_mi.top_level = true
	rope_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new(); m.albedo_color = Color("#3a7ad0"); m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	rope_mi.material_override = m
	add_child(rope_mi)

static func owned() -> bool:
	return Rigging.owned("lowrig")

## something tied on or hanging (so left mouse at the base, or G in the tree, works the brake)
func active() -> bool:
	if Net.is_guest(): return not net_line.is_empty()
	return not tie.is_empty() or (load != null and is_instance_valid(load))

func _tree() -> AshTree:
	return game.tree

## the crotch the block hangs in: just under the climber's tie-in, or under the top
func _block_world() -> Vector3:
	var tr := _tree()
	var y := minf(block_y, tr.top_y - 0.25) if tr.state == "stand" else block_y
	return tr.to_world(Vector3(0.12, y + 0.12, 0.08))

func _base_world() -> Vector3:
	return _tree().to_world(Vector3(Wood.r_at(_tree().T, BASE_Y) + 0.05, BASE_Y, 0.0))

# ---------------------------------------------------------------- tying on
## the rope tool, in the tree, aimed at a limb or the stem above you: tie the lowering line on.
## line_y is the climber's tie-in height (the block goes there). Runs as the climber (see NetJob.as_peer).
func tie_aimed(line_y: float) -> bool:
	var tr := _tree()
	if tr.state != "stand": return false
	if line_y <= 0.0:
		game.hud.toast("The lowering line runs through a block at your tie-in. Set a climbing line first.", 3.5); return true
	if load != null and is_instance_valid(load):
		game.hud.toast("There's still a piece on the rope. Get it on the ground first.", 2.5); return true
	var p: Player = game.player
	var e := p.eye()
	var q := PhysicsRayQueryParameters3D.create(e, e + p.aim_dir() * 2.4)
	q.collision_mask = 256
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		# a near miss on a thin limb still counts: you're throwing a loop of rope round it, not threading a needle
		var sph := SphereShape3D.new(); sph.radius = 0.14
		var sq := PhysicsShapeQueryParameters3D.new(); sq.shape = sph; sq.collision_mask = 256
		for i in range(1, 17):
			var at: Vector3 = e + p.aim_dir() * (0.15 * i)
			sq.transform = Transform3D(Basis(), at)
			var rs: Dictionary = space.get_rest_info(sq)
			if not rs.is_empty():
				hit = {collider = instance_from_id(int(rs.collider_id)), shape = int(rs.shape), position = rs.point}
				break
	if hit.is_empty() or hit.collider != tr.crown_body:
		game.hud.toast("Aim at a limb, or the stem above you, to tie the lowering line on.", 2.5); return true
	var ow = hit.collider.shape_owner_get_owner(hit.collider.shape_find_owner(hit.shape))
	var part: Dictionary = ow.get_meta("part", {}) if ow else {}
	var w := tr.to_wood(hit.position)
	if part.has("slimb"):
		var id := int(part.slimb)
		var L: Dictionary = tr.T.limbs[id]
		var reach := float(tr.on_limbs.get(id, 1.0))
		var k := clampf((w - L.base).dot(L.dir) / float(L.len), 0.05, reach)
		tie = {kind = "slimb", id = id, t = k, block_y = line_y}
		Sfx.play("pick")
		game.hud.toast("Lowering line's tied on that limb. Cut it between the tie and the stem, then let it down.", 4.0)
		return true
	if part.has("upper"):
		var y := w.y
		if y > line_y + 0.05:
			game.hud.toast("Tie it below your block, or the top'll take the block with it.", 3.0); return true
		tie = {kind = "top", y = y, block_y = line_y}
		Sfx.play("pick")
		game.hud.toast("Lowering line's tied round the stem. Top it below the tie, then let it down.", 4.0)
		return true
	return true

## a cut up in the crown just came through: if it's the piece the rope's tied on, it's hanging now
func on_crown_cut(kind: String, y: float, id: int, t: float, p: WoodPiece) -> void:
	if tie.is_empty() or p == null: return
	var tr := _tree()
	var hit := false
	var tie_w: Vector3
	if kind == "slimb" and tie.kind == "slimb" and int(tie.id) == id and t < float(tie.t):
		hit = true
		tie_w = tr.to_world(Wood.limb_pt(tr.T.limbs[id], float(tie.t)))
	elif kind == "top" and tie.kind == "top" and y < float(tie.y):
		hit = true
		tie_w = tr.to_world(Vector3(0, float(tie.y), 0))
	if not hit: return
	load = p
	load_pt = p.global_transform.affine_inverse() * tie_w
	block_y = float(tie.block_y)
	rope_len = tie_w.distance_to(_block_world()) + 0.1
	tie = {}
	_rest_t = 0.0
	p.remove_meta("drop")                  # on a rope it comes down slow, it doesn't smash anything
	game.hud.toast("It's on the rope. Let it run to bring it down (" + ("hold G" if game.climb and game.climb.climbing else "left mouse at the base") + ").", 3.5)

# ---------------------------------------------------------------- the brake
## somebody's running the rope (another computer's player: kept on for a moment after each message)
func remote_run() -> void:
	run_remote_until = game.clock + 0.25

func _running() -> bool:
	return run_local or game.clock < run_remote_until

## while there's a load on the rope: hold it out from the block, let it down as the brake's run, and
## feel it when it comes tight
func physics_step(dt: float) -> void:
	if Net.is_guest(): return
	if load == null or not is_instance_valid(load) or load.mode != "dyn":
		if load != null: load = null
		return
	var b := _block_world()
	var a := load.global_transform * load_pt
	if _running():
		rope_len = minf(rope_len + RUN_SPEED * dt, b.y - game.world.H(b.x, b.z) + 4.0)
	var d := a - b
	var L := d.length()
	if L > rope_len and L > 0.01:
		var n := d / L
		var st := PhysicsServer3D.body_get_direct_state(load.get_rid())
		if st:
			var com := load.global_position + st.center_of_mass
			var v := st.linear_velocity + st.angular_velocity.cross(a - com)
			var vout := v.dot(n)
			if vout > 0.0:
				load.apply_impulse(-n * vout * load.mass * 0.9, a - load.global_position)
				if vout > SHOCK_SNAP:
					_snap(); return
				if vout > SHOCK_FELT:
					Sfx.play("thud", 0.8, 0.7); Sfx.play("creak", 0.5, 0.9)
					game.hud.toast("Shock load! The whole tree shook. Let it run sooner.", 2.5)
					Ach.add("shock")
			load.apply_central_force(-n * (L - rope_len) * load.mass * 40.0)
			load.angular_velocity *= maxf(0.0, 1.0 - dt * 1.5)
	# down and still: untie it
	# (or set down on something, a deck or a roof: the rope's gone slack and it's sitting still)
	var low: bool = a.y - game.world.H(a.x, a.z) < 1.2
	var slack: bool = (a - b).length() < rope_len - 0.4 and _running()
	if (low or slack) and load.linear_velocity.length() < 0.4:
		_rest_t += dt
		if _rest_t > 1.2:
			load = null
			Sfx.play("pick")
			game.hud.toast("It's on the ground. Rope's off.", 1.8)
			Ach.add("lowered")
			game.update_objectives()
	else:
		_rest_t = 0.0

func _snap() -> void:
	load = null
	Sfx.play("crack", 0.8, 1.5)
	game.hud.toast("SNAP! It caught too hard and the rope parted. Let it run before it drops.", 4.0)

# ---------------------------------------------------------------- the rope, drawn
func line_points() -> Array:
	if Net.is_guest(): return net_line
	var tr := _tree()
	if not tie.is_empty() and tr.state == "stand":
		var tw: Vector3
		if tie.kind == "slimb":
			if not tr.on_limbs.has(int(tie.id)): tie = {}; return []
			tw = tr.to_world(Wood.limb_pt(tr.T.limbs[int(tie.id)], float(tie.t)))
		else: tw = tr.to_world(Vector3(0, float(tie.y), 0))
		block_y = float(tie.block_y)
		return [_block_world(), tw, _base_world()]
	if load != null and is_instance_valid(load):
		return [_block_world(), load.global_transform * load_pt, _base_world()]
	return []

func step(_dt: float) -> void:
	rope_im.clear_surfaces()
	var P := line_points()
	if P.size() < 3: return
	var cam := get_viewport().get_camera_3d()
	rope_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [[P[0], P[1]], [P[0], P[2]]]:
		var a: Vector3 = s[0]; var b: Vector3 = s[1]
		var along := (b - a).normalized()
		var side := along.cross((cam.global_position - a).normalized() if cam else Vector3.UP).normalized() * 0.013
		for q in [a - side, b - side, b + side, a - side, b + side, a + side]:
			rope_im.surface_set_normal(Vector3.UP)
			rope_im.surface_add_vertex(q)
	rope_im.surface_end()

## is the player at the brake (the base of the tree, rope tool in hand)?
func at_brake() -> bool:
	var p: Player = game.player
	if game.climb and game.climb.climbing: return false
	return p.tool == "rope" and p.global_position.distance_to(_tree().global_position) < 3.2
