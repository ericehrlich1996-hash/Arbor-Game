## Moving wood around by hand: carrying several pieces (rounds on the shoulder, brush under the arm),
## throwing (into the truck bed when you're near it), dragging heavy logs, kicking, and feeding the chipper.
class_name Haul
extends Node

var game
var carry: Array = []          # WoodPiece list
var drag = null                # {b, lp (wood frame)}
var feeding = null
var feed_queue: Array = []
var feed_t := 0.0
var chips_done := 0

func setup(g) -> void:
	game = g

func carry_mass() -> float:
	var m := 0.0
	for b in carry: m += b.mass
	return m

func carrying() -> bool:
	return not carry.is_empty()

func can_add(b: WoodPiece) -> bool:
	if carry.is_empty(): return b.mass <= Wood.LIFT_MAX
	if carry[0].is_brush() != b.is_brush(): return false
	return carry_mass() + b.mass <= Wood.LIFT_MAX

func liftable(b: WoodPiece) -> bool:
	return b.mass <= Wood.LIFT_MAX and not (b.kind == "trunk" and not b.limbs.is_empty())

func _hold(b: WoodPiece, on: bool) -> void:
	if on:
		b.mode = "held"
		b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		b.freeze = true
		b.collision_layer = 0; b.collision_mask = 0
	else:
		b.mode = "dyn"
		b.freeze = false
		b.collision_layer = 64 if b.kind == "limb" else 8
		b.collision_mask = 1 | 4 | 8 | 32 | 64
		b.sleeping = false

func pick_up(b: WoodPiece) -> void:
	_hold(b, true)
	carry.append(b)
	Sfx.play("pick")

func release(b: WoodPiece, v := Vector3.ZERO) -> void:
	_hold(b, false)
	b.linear_velocity = v
	b.angular_velocity = Vector3.ZERO

func drop_one() -> void:
	if carry.is_empty(): return
	var b: WoodPiece = carry.pop_back()
	release(b, game.player.aim_dir() * 1.0 + Vector3(0, 0.5, 0))
	Sfx.play("drop")
	game.get_tree().create_timer(1.5).timeout.connect(game.update_objectives)

func drop_all() -> void:
	var i := 0
	for b in carry:
		release(b, game.player.aim_dir() * 1.0 + Vector3(0.3 if i % 2 else -0.3, 0.5, 0))
		i += 1
	carry.clear()
	Sfx.play("drop")
	game.get_tree().create_timer(1.5).timeout.connect(game.update_objectives)

## put a piece so its wood-frame point `anchor` sits at world `at`, its wood-frame axis turning toward `dir`
static func place(b: WoodPiece, axis_l: Vector3, dir: Vector3, anchor: Vector3, at: Vector3, k: float) -> void:
	var cur := b.global_transform.basis.orthonormalized()
	var aw := (cur * axis_l).normalized()
	var turn := Quaternion(aw, dir.normalized()) if aw.dot(dir.normalized()) > -0.999 else Quaternion(cur.x, PI)
	var target := Basis(turn) * cur
	var q := Quaternion(cur).slerp(Quaternion(target.orthonormalized()), k)
	var nb := Basis(q)
	var want := at - nb * anchor
	b.global_transform = Transform3D(nb, b.global_position.lerp(want, k))

func step_carry(dt: float) -> void:
	if carry.is_empty(): return
	var p: Player = game.player
	var fw := p.fwd(); var rt := Vector3(cos(p.yaw), 0, -sin(p.yaw))
	var stack_y := 0.0
	var i := 0
	for b in carry:
		var k := minf(1.0, dt * 12)
		if b.is_brush() or b.kind == "wedge":
			var ba: Dictionary = b.brush_axis()
			var dir := (fw * 0.8 + rt * (-0.55 + i * 0.06) + Vector3(0, -0.08 + i * 0.03, 0)).normalized()
			var hands := p.global_position + Vector3(0, 1.0 + i * 0.05, 0) + fw * 0.5 + rt * (0.22 - i * 0.05)
			place(b, ba.ax, dir, ba.butt, hands, k)
		else:
			# over the right shoulder, the round's axis running fore and aft
			var r := Wood.r_at(b.T, b.center_wood().y)
			var sh := p.global_position + Vector3(0, p.eye_h - 0.16 + r + stack_y, 0) + rt * (0.3 + r * 0.5) + fw * 0.12
			stack_y += r * 1.85
			place(b, Vector3.UP, fw + Vector3(0, 0.18, 0), b.center_wood(), sh, k)
		i += 1

# ---------------------------------------------------------------- throwing
## the emptiest spot in the truck bed if you're close and facing it, else null
func throw_target():
	var p: Player = game.player
	var t: Truck = game.truck
	var c := t.global_transform * Vector3(0, 1.0, -1.7)
	if Vector2(c.x - p.global_position.x, c.z - p.global_position.z).length() > 6.5: return null
	var to := Vector3(c.x - p.eye().x, 0, c.z - p.eye().z).normalized()
	var fw := p.fwd()
	if not game.on_bed and to.dot(fw) < 0.6: return null
	var best := {}
	for x in [-0.45, 0.0, 0.45]:
		for z in [-2.25, -1.75, -1.25]:
			var w := t.global_transform * Vector3(x, 1.0, z)
			var crowd := 0.0
			for b in game.pieces():
				if b.mode != "dyn": continue
				var l := t.bed_local(b.center_world())
				if absf(l.x - x) < 0.4 and absf(l.z - z) < 0.4: crowd += 1 + maxf(0, l.y - 0.8) * 3
			var score := crowd * 10 + w.distance_to(p.eye() + fw * 2) * 0.3
			if best.is_empty() or score < best.score: best = {score = score, x = x, z = z, crowd = crowd}
	return t.global_transform * Vector3(best.x, 1.05 + minf(0.6, best.crowd * 0.25), best.z)

func throw_one() -> void:
	if carry.is_empty(): return
	var b: WoodPiece = carry.pop_back()
	var tgt = throw_target()
	var start := b.center_world()
	release(b)
	if tgt != null:
		# the quickest lob whose arc clears the bed walls with the piece's thickness to spare
		var t: Truck = game.truck
		var inv := t.global_transform.affine_inverse()
		var r := (Wood.r_at(b.T, b.center_wood().y) + 0.06) if b.kind == "trunk" else 0.15
		var d: Vector3 = tgt - start
		var tf := 1.2
		var tt := 0.4
		while tt <= 1.2:
			var ok := true
			for i in range(1, 20):
				var f := i / 20.0
				var w := start + Vector3(d.x * f, d.y * f + 0.5 * 9.81 * tt * tt * f * (1 - f), d.z * f)
				var l := inv * w
				var outside := absf(l.x) > 0.9 - r * 0.3 or l.z < -2.55 or l.z > -0.8
				if outside and absf(l.x) < 1.1 + r and l.z > -2.75 - r and l.z < -0.6 + r and l.y < 1.36 + r:
					ok = false; break
			if ok: tf = tt; break
			tt += 0.04
		b.linear_velocity = Vector3(d.x / tf, d.y / tf + 0.5 * 9.81 * tf, d.z / tf) + t.linear_velocity
	else:
		var fw: Vector3 = game.player.fwd()
		b.linear_velocity = fw * 4.2 * (1 - minf(0.5, b.mass / 120.0)) + Vector3(0, 2.4, 0)
	b.angular_velocity = Vector3(randf() - 0.5, (randf() - 0.5) * 0.5, randf() - 0.5) * 2
	Sfx.play("pick")
	game.get_tree().create_timer(1.8).timeout.connect(game.update_objectives)

# ---------------------------------------------------------------- dragging
func can_drag(b: WoodPiece) -> bool:
	return b != null and b.mode == "dyn" and (b.mass > Wood.LIFT_MAX or (b.kind == "trunk" and not b.limbs.is_empty())) and b.mass <= Wood.DRAG_MAX

func start_drag(b: WoodPiece) -> void:
	var p: Player = game.player
	var ends: Array
	if b.kind == "trunk":
		ends = [Vector3(0, b.span.x, 0), Vector3(0, b.span.y, 0)]
	else:
		var ba: Dictionary = b.brush_axis(); ends = [ba.butt, ba.butt + ba.ax * 0.6]
	var lp: Vector3 = ends[0] if b.to_world(ends[0]).distance_to(p.global_position) < b.to_world(ends[1]).distance_to(p.global_position) else ends[1]
	drag = {b = b, lp = lp}
	b.sleeping = false
	Sfx.play("pick")

func stop_drag() -> void:
	if drag == null: return
	if is_instance_valid(drag.b): drag.b.sleeping = false
	drag = null
	Sfx.play("drop")
	game.get_tree().create_timer(1.5).timeout.connect(game.update_objectives)

## a spring from your right hand to the grabbed end: the end lifts, the rest drags along behind
func step_drag(dt: float) -> void:
	if drag == null: return
	var b: WoodPiece = drag.b
	if not is_instance_valid(b) or b.mode != "dyn": drag = null; return
	var p: Player = game.player
	var fw := p.fwd(); var rt := Vector3(cos(p.yaw), 0, -sin(p.yaw))
	var tgt := p.global_position + fw * 0.45 + rt * 0.42 + Vector3(0, 0.62, 0)
	var gp := b.to_world(drag.lp)
	var err := tgt - gp
	if Vector2(err.x, err.z).length() > 2.4: stop_drag(); return
	b.sleeping = false
	var st := PhysicsServer3D.body_get_direct_state(b.get_rid())
	if st == null: return
	var rel := gp - b.global_position
	var vel := st.linear_velocity + st.angular_velocity.cross(gp - (b.global_position + st.center_of_mass))
	var vdes := err * 6.0
	if vdes.length() > 4.0: vdes = vdes.normalized() * 4.0
	var dv := vdes - vel
	var j := dv * b.mass * 0.45 * minf(1.0, dt * 14)
	if j.length() > 1150 * dt: j = j.normalized() * 1150 * dt
	b.apply_impulse(j, rel)
	b.angular_velocity *= maxf(0, 1 - dt * 3)

# ---------------------------------------------------------------- kicking
func kick() -> void:
	var p: Player = game.player
	if not carry.is_empty() or p.in_truck: return
	var e := p.eye()
	var d := p.aim_dir()
	if d.y > -0.15: d = Vector3(d.x, -0.15, d.z).normalized()
	var q := PhysicsRayQueryParameters3D.create(e, e + d * 1.9)
	q.collision_mask = 8 | 64
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit.collider is WoodPiece): Sfx.play("step"); return
	var b: WoodPiece = hit.collider
	b.sleeping = false
	# a piece that's nearly cut through snaps apart
	var best = null
	for op in b.ops:
		if op.type == "kerf" and not op.get("done", false) and op.s < op.exit and op.s / op.exit > 0.72:
			if best == null or op.s / op.exit > best.s / best.exit: best = op
	if best != null:
		best.s = best.exit + 0.01
		best.piece = b
		best.part = {trunk = true}
		Sfx.play("crack")
		game.saw._emit(hit.position, Vector3(0, 1.2, 0), 12, Color("#c4ae88"), 2, 0.04)
		game.saw._finish_piece_cut(best)
		if game.saw.cut == best: game.saw.cut = null
		return
	var J := Vector3(d.x, 0, d.z).normalized() * minf(220, b.mass * 3) + Vector3(0, minf(60, b.mass * 0.8), 0)
	b.apply_impulse(J, hit.position - b.global_position)
	Sfx.play("thud", 0.4)

# ---------------------------------------------------------------- the chipper
func near_hopper() -> bool:
	return game.chipper.hopper_world().distance_to(game.player.eye()) < 3.4

func feed() -> void:
	var c: Chipper = game.chipper
	if not c.running: game.hud.toast("The chipper isn't running."); return
	var brush := carry.filter(func(b): return b.is_brush() or b.kind == "wedge")
	carry = carry.filter(func(b): return not (b.is_brush() or b.kind == "wedge"))
	for b in brush:
		b.mode = "feedwait"
		feed_queue.append(b)
	_next_feed()

func _next_feed() -> void:
	if feeding != null or feed_queue.is_empty(): return
	feeding = feed_queue.pop_front()
	feeding.mode = "feed"
	feed_t = 0.0

func step_feed(dt: float) -> void:
	if feeding == null: return
	var b: WoodPiece = feeding
	if not is_instance_valid(b): feeding = null; _next_feed(); return
	var c: Chipper = game.chipper
	feed_t += dt
	var throat := c.throat_world(); var mouth := c.mouth_world()
	var ax := (throat - mouth).normalized()
	var ba: Dictionary = b.brush_axis()
	var tip_l: Vector3 = ba.butt + ba.ax * ba.len
	if feed_t < 0.7:
		# swing it level, butt first, and set the butt in the mouth
		place(b, ba.ax, ax, ba.butt, mouth, minf(1, dt * 7))
	else:
		# the feed rollers grab it and pull it through
		b.global_position += ax * 1.5 * dt
		c.load = 1.0
		game.saw._emit(c.chute_world(), (c.global_transform.basis * Vector3(0, 0, 1)) * 4 + Vector3(0, 1.5, 0), 4, Color("#c9a46a"), 1.6, 0.05)
		if randf() < dt * 6: Sfx.play("crunch", 0.7)
		# branches fold in against the hood as they go: squash everything sideways around the feed axis
		var past := (b.to_world(ba.butt) - mouth).dot(ax)
		var kq := clampf(1.0 - past / 1.35, 0.12, 1.0)
		var a: Vector3 = ba.ax.normalized()
		var S := Basis.IDENTITY
		for i in range(3):
			var e := Vector3.ZERO; e[i] = 1.0
			var col := a * a.dot(e) + (e - a * a.dot(e)) * kq
			S[i] = col
		for ch in b.get_children():
			if ch is MeshInstance3D or ch is CSGShape3D:
				ch.transform = Transform3D(S, ba.butt - S * ba.butt)
		var tip_w := b.to_world(tip_l)
		if (tip_w - throat).dot(ax) > 0 or feed_t > 12:
			b.mode = "gone"
			b.queue_free()
			feeding = null
			chips_done += 1
			game.update_objectives()
			_next_feed()
