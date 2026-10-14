## Scripted playthroughs for automated checks: run with  godot --path . -- --test=<name>
## Saves screenshots to user://shots (or $SHOTS) and prints a report, then quits.
extends Node

var g
var out_dir := ""
var report := []

func run(game, name: String) -> void:
	g = game
	out_dir = OS.get_environment("SHOTS")
	if out_dir == "": out_dir = OS.get_user_data_dir() + "/shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().process_frame
	match name:
		"m1": await _m1()
		_: await call("_" + name)
	print("REPORT ", JSON.stringify(report))
	get_tree().quit()

func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func frames(n: int) -> void:
	for i in range(n): await get_tree().process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + "/" + name + ".png")

func note(k: String, v) -> void:
	report.append([k, v])
	print("NOTE ", k, " ", v)

func look_at_point(p: Vector3) -> void:
	var e: Vector3 = g.player.global_position + Vector3(0, g.player.eye_h, 0)
	var d := (p - e).normalized()
	g.player.yaw = atan2(-d.x, -d.z)
	g.player.pitch = asin(clampf(d.y, -1, 1))

func press(act: String, secs: float) -> void:
	Input.action_press(act)
	await wait(secs)
	Input.action_release(act)

func _m1() -> void:
	await wait(1.5)
	await shot("m1-title")
	g._start()
	await wait(0.5)
	var ep: Vector3 = g.earl.global_position + (g.player.global_position - g.earl.global_position).normalized() * 2.2
	g.player.teleport(Vector3(ep.x, g.world.H(ep.x, ep.z) + 0.05, ep.z))
	look_at_point(g.earl.global_position + Vector3(0, 1.4, 0))
	await wait(0.8)
	await shot("m1-earl")
	note("aim_on_earl", g.aim.get("kind", ""))
	g.talk_to_earl()
	for i in range(14):
		await wait(0.15)
		if g.dlg != null: g.advance_dialog()
	await shot("m1-after-talk")
	note("talked", g.objs.talk)
	# truck settled on its wheels?
	note("truck_height_above_ground", snappedf(g.truck.global_position.y - g.world.H(g.truck.global_position.x, g.truck.global_position.z), 0.01))
	note("hitch_gap", snappedf(g.chipper.coupler_world().distance_to(g.truck.hitch_world()), 0.01))
	# walk along the truck side
	var t: Truck = g.truck
	var start := t.global_transform * Vector3(3.0, 0, -1.5)
	g.player.teleport(Vector3(start.x, g.world.H(start.x, start.z) + 0.05, start.z))
	look_at_point(t.global_transform * Vector3(0, 1.0, -1.5))
	g.player.pitch = 0
	await press("move_fwd", 1.5)
	var l := t.bed_local(g.player.global_position)
	note("closest_to_truck_side_x", snappedf(l.x, 0.01))
	note("truck_after_side_walk", [t.global_position, snappedf(rad_to_deg(t.global_transform.basis.y.angle_to(Vector3.UP)), 0.1)])
	# hop in the bed
	var tg := t.global_transform * Vector3(0.7, 0, -3.5)
	g.player.teleport(Vector3(tg.x, g.world.H(tg.x, tg.z) + 0.05, tg.z))
	look_at_point(t.global_transform * Vector3(0, 1.1, -2.62))
	await wait(0.3)
	note("aim_tailgate", g.aim.get("kind", ""))
	note("truck_before_hop", [t.global_position, g.player.global_position])
	g.interact()
	await wait(0.6)
	note("on_bed", g.on_bed)
	note("player_bed_y", snappedf(t.bed_local(g.player.global_position).y, 0.01))
	look_at_point(t.global_transform * Vector3(0, 1.0, 1.5))
	await wait(0.4)
	await shot("m1-in-bed")
	# drive with the player standing in the bed? no: hop down, get in, drive
	look_at_point(t.global_transform * Vector3(0, 1.1, -2.62))
	await wait(0.2)
	g.interact()
	await wait(0.3)
	note("on_bed_after_hop_down", g.on_bed)
	var door := t.global_transform * Vector3(2.0, 0, 0.2)
	g.player.teleport(Vector3(door.x, g.world.H(door.x, door.z) + 0.05, door.z))
	look_at_point(t.global_transform * Vector3(1.05, 1.1, 0.2))
	await wait(0.3)
	note("aim_door", g.aim.get("kind", ""))
	g.interact()
	await wait(0.5)
	note("in_truck", g.player.in_truck)
	var p0 := t.global_position
	await press("move_fwd", 3.0)
	await wait(0.5)
	note("drove_m", snappedf(t.global_position.distance_to(p0), 0.1))
	note("hitch_gap_after_drive", snappedf(g.chipper.coupler_world().distance_to(t.hitch_world()), 0.02))
	await shot("m1-cab")
	t.look_pitch = 0.18
	await wait(0.4)
	await shot("m1-cab-mirror")
	t.look_pitch = 0
	t.toggle_cam()
	Input.action_press("move_fwd"); Input.action_press("move_left")
	await wait(2.0)
	Input.action_release("move_fwd"); Input.action_release("move_left")
	await shot("m1-chase")
	await press("jump", 1.5)
	t.toggle_cam()
	g.exit_truck()
	await wait(0.5)
	note("out_of_truck", not g.player.in_truck)
	# unhitch, walk the chipper by the tongue, set it down
	var c: Chipper = g.chipper
	var cp := c.coupler_world() + (t.global_transform.basis.x * 1.4) - t.global_transform.basis.z * 0.5
	g.player.teleport(Vector3(cp.x, g.world.H(cp.x, cp.z) + 0.05, cp.z))
	look_at_point(c.coupler_world())
	await wait(0.3)
	note("aim_hitch", g.aim.get("kind", ""))
	g.interact()
	await wait(0.4)
	note("chip_mode_after_unhitch", c.mode)
	g.interact()
	await wait(0.2)
	note("chip_mode_grab", c.mode)
	var c0 := c.global_position
	g.player.yaw += PI * 0.5
	await press("move_fwd", 2.0)
	note("chipper_walked_m", snappedf(c.global_position.distance_to(c0), 0.1))
	g.interact()
	await wait(1.0)
	note("chip_mode_set_down", c.mode)
	note("chipper_tilt_deg", snappedf(rad_to_deg(c.global_transform.basis.y.angle_to(Vector3.UP)), 0.1))
	look_at_point(c.global_position + Vector3(0, 0.5, -2))
	g.player.global_position += Vector3(0, 0, 0)
	await wait(0.3)
	await shot("m1-chipper")
	# overview of the house
	var h: Dictionary = g.world.house
	g.player.teleport(Vector3(h.x + 4, g.world.H(h.x + 4, h.z - 16) + 0.05, h.z - 16))
	look_at_point(Vector3(h.x, g.world.H(h.x, h.z) + 2.5, h.z))
	await wait(0.6)
	await shot("m1-house")

func _dbg_tailgate() -> void:
	await wait(1.0)
	g._start()
	await wait(1.0)
	var t: Truck = g.truck
	var tg := t.global_transform * Vector3(0.7, 0, -3.5)
	print("ground at spot ", g.world.H(tg.x, tg.z), " truck y ", t.global_position.y, " chip ", g.chipper.global_position)
	g.player.teleport(Vector3(tg.x, g.world.H(tg.x, tg.z) + 0.05, tg.z))
	for i in range(12):
		await wait(0.1)
		print(i, " pl ", g.player.global_position, " chip ", g.chipper.global_position, " truck ", t.global_position, " plv ", g.player.velocity)
	look_at_point(t.global_transform * Vector3(0, 1.1, -2.62))
	await wait(0.3)
	print("aim ", g.aim)
	await shot("dbg-tail")

func _chase() -> void:
	await wait(1.0)
	g._start()
	await wait(0.5)
	g.enter_truck()
	await wait(0.3)
	g.truck.toggle_cam()
	await shot("chase-0")
	Input.action_press("move_fwd")
	await wait(2.5)
	await shot("chase-1")
	Input.action_press("move_left")
	await wait(2.0)
	Input.action_release("move_fwd"); Input.action_release("move_left")
	await shot("chase-2")
	note("chip_up_deg", snappedf(rad_to_deg(g.chipper.global_transform.basis.y.angle_to(Vector3.UP)), 0.1))
	note("truck_up_deg", snappedf(rad_to_deg(g.truck.global_transform.basis.y.angle_to(Vector3.UP)), 0.1))
	note("hitch_gap", snappedf(g.chipper.coupler_world().distance_to(g.truck.hitch_world()), 0.02))

## injected notch + back cut, the fall, then real-saw bucking of the stem
func _fell() -> void:
	await wait(1.0)
	g._start()
	g.objs.talk = true
	var tr: AshTree = g.tree
	var T: Dictionary = tr.T
	var house := Vector3(g.world.house.x, 0, g.world.house.z)
	var away := (tr.global_position - house); away.y = 0; away = away.normalized()
	var Fn: Vector3 = tr.global_transform.basis.inverse() * away; Fn.y = 0; Fn = Fn.normalized()
	var h := 0.55; var R := Wood.r_at(T, h); var d := 2 * R * 0.33; var a := deg_to_rad(55)
	var right := Fn.cross(Vector3.UP).normalized()
	var bot := tr.start_cut(Fn * R + Vector3(0, h, 0), -Fn, Vector3.UP)
	bot.s = d + 0.005; tr.cut_progress(bot)
	var ft := (-Fn * cos(a) + Vector3.DOWN * sin(a)).normalized()
	var top := tr.start_cut(Fn * R + Vector3(0, h + d * tan(a), 0), ft, ft.cross(right).normalized())
	top.s = d / cos(a) + 0.005; tr.cut_progress(top)
	# stand by the tree and look at the notch
	var pp := tr.global_position + away * 2.2 + right.rotated(Vector3.UP, 0) * 0.0
	g.player.teleport(Vector3(pp.x, g.world.H(pp.x, pp.z) + 0.05, pp.z))
	look_at_point(tr.global_position + Vector3(0, 0.7, 0))
	await wait(1.0)
	await shot("fell-notch")
	note("wedges", tr.freed.size())
	var bc := tr.start_cut(-Fn * R + Vector3(0, h + 0.03, 0), Fn, Vector3.UP)
	bc.s = 2 * R - d - 0.04; tr.cut_progress(bc)
	var side := tr.global_position + right * 9 + away * 4
	g.player.teleport(Vector3(side.x, g.world.H(side.x, side.z) + 0.05, side.z))
	look_at_point(tr.global_position + Vector3(0, 6, 0) + away * 4)
	await wait(1.2)
	await shot("fell-going")
	note("state", tr.state)
	note("grade", tr.grade)
	await wait(5.0)
	await shot("fell-down")
	note("state_after", tr.state)
	var st: WoodPiece = tr.stem
	note("stem_up_angle", snappedf(rad_to_deg(st.global_transform.basis.y.angle_to(Vector3.UP)), 1))
	note("limbs_left_on_stem", st.limbs.size())
	note("pieces", g.pieces().size())
	# stump close-up
	var sp := tr.global_position + right * 1.4 + away * 0.6
	g.player.teleport(Vector3(sp.x, g.world.H(sp.x, sp.z) + 0.05, sp.z))
	look_at_point(tr.global_position + Vector3(0, 0.3, 0))
	await wait(0.6)
	await shot("fell-stump")
	# the butt of the stem
	var butt := st.to_world(Vector3(0, tr.stump_y0, 0))
	var bdir := st.global_transform.basis.y; bdir.y = 0; bdir = bdir.normalized()
	var bp := butt - bdir * 1.6 + bdir.cross(Vector3.UP) * 0.6
	g.player.teleport(Vector3(bp.x, g.world.H(bp.x, bp.z) + 0.05, bp.z))
	look_at_point(butt)
	await wait(0.6)
	await shot("fell-butt")
	# buck with the real saw 3 m up the stem
	g.equip("saw")
	g.saw.on = true; g.saw.engine_snd = Sfx.engine("saw")
	var y := tr.stump_y0 + 3.0
	var wp := st.to_world(Vector3(0, y, 0))
	var ax := st.global_transform.basis.y.normalized()
	var sd := ax.cross(Vector3.UP).normalized()
	g.player.crouch = true
	var ey := wp + sd * 1.0
	g.player.teleport(Vector3(ey.x, g.world.H(ey.x, ey.z) + 0.05, ey.z))
	await wait(0.4)
	look_at_point(wp + Vector3(0, 0.1, 0))
	# pick the roll that puts the cut across the grain
	var best := 0.0; var bv := -1.0
	for i in range(25):
		g.saw.roll = PI * i / 24.0
		g.saw.pose(0.016, true, false)
		var v := absf(g.saw.n.dot(ax))
		if v > bv: bv = v; best = g.saw.roll
	g.saw.roll = best
	g.force_rev = true
	var n0: int = g.pieces().size()
	var tt := 0.0
	while tt < 9.0 and g.pieces().size() == n0:
		await wait(0.25); tt += 0.25
		if tt == 2.0: await shot("buck-mid")
	g.force_rev = false
	note("buck_secs", tt)
	note("pieces_after_buck", g.pieces().size())
	await wait(1.5)
	g.player.crouch = false
	await shot("buck-done")

func _fell_tree_quick() -> void:
	var tr: AshTree = g.tree
	var T: Dictionary = tr.T
	var house := Vector3(g.world.house.x, 0, g.world.house.z)
	var away := (tr.global_position - house); away.y = 0; away = away.normalized()
	var Fn: Vector3 = tr.global_transform.basis.inverse() * away; Fn.y = 0; Fn = Fn.normalized()
	var h := 0.55; var R := Wood.r_at(T, h); var d := 2 * R * 0.33; var a := deg_to_rad(55)
	var right := Fn.cross(Vector3.UP).normalized()
	var bot := tr.start_cut(Fn * R + Vector3(0, h, 0), -Fn, Vector3.UP); bot.s = d + 0.005; tr.cut_progress(bot)
	var ft := (-Fn * cos(a) + Vector3.DOWN * sin(a)).normalized()
	var top := tr.start_cut(Fn * R + Vector3(0, h + d * tan(a), 0), ft, ft.cross(right).normalized()); top.s = d / cos(a) + 0.005; tr.cut_progress(top)
	await wait(0.4)
	var bc := tr.start_cut(-Fn * R + Vector3(0, h + 0.03, 0), Fn, Vector3.UP); bc.s = 2 * R - d - 0.04; tr.cut_progress(bc)
	while tr.state != "down": await wait(0.2)
	await wait(5.5)

func _carry_to(b: WoodPiece, where: Vector3) -> void:
	var p: Player = g.player
	var bc := b.center_world()
	p.teleport(Vector3(bc.x + 1.0, g.world.H(bc.x + 1, bc.z) + 0.05, bc.z))
	await wait(0.15)
	g.haul.pick_up(b)
	p.teleport(Vector3(where.x, g.world.H(where.x, where.z) + 0.05, where.z))
	await wait(0.4)

## the whole job, scripted
func _job() -> void:
	await wait(1.0)
	g._start()
	g.talk_to_earl()
	for i in range(20):
		await wait(0.05)
		if g.dlg != null: g.advance_dialog()
	note("talked", g.objs.talk)
	await _fell_tree_quick()
	note("felled", g.objs.felled)
	var st: WoodPiece = g.tree.stem
	# limb it: one with the real saw, the rest directly
	for id in st.limbs.duplicate(): Lumber.limb_off(g, st, id)
	await wait(1.5)
	note("limbs_left", st.limbs.size())
	# buck into liftable rounds from the top down
	var guard := 0
	while guard < 40:
		guard += 1
		var trunks: Array = g.pieces().filter(func(b): return b.kind == "trunk" and b.mass > Wood.LIFT_MAX * 0.92)
		if trunks.is_empty(): break
		var b: WoodPiece = trunks[0]
		var r := Wood.r_at(b.T, b.span.y - 0.3)
		var L := clampf(52.0 / (Wood.RHO * PI * r * r), 0.25, 2.0)
		var y := b.span.y - L
		if y <= b.span.x + 0.1: y = (b.span.x + b.span.y) / 2
		var c := {kind = "piece", type = "kerf", piece = b, part = {trunk = true}, e = Vector3(0, y, 0), f = Vector3.RIGHT, n = Vector3.UP, s = 1.0, exit = 1.0, done = true}
		Lumber.buck(g, b, c)
		await wait(0.1)
	await wait(2.0)
	g.update_objectives()
	note("counts_after_buck", g.counts)
	await shot("job-bucked")
	# start the chipper and feed the brush
	g.toggle_chipper()
	await wait(0.8)
	var hop: Vector3 = g.chipper.hopper_world() + (g.chipper.global_transform.basis * Vector3(0, 0, -1.6))
	for b in g.pieces().filter(func(b): return b.kind == "limb" or b.kind == "wedge"):
		await _carry_to(b, hop)
		look_at_point(g.chipper.hopper_world())
		await wait(0.1)
		g.interact()
		await wait(0.2)
	await shot("job-feeding")
	var tt := 0.0
	while (g.haul.feeding != null or not g.haul.feed_queue.is_empty()) and tt < 90:
		await wait(0.5); tt += 0.5
	g.update_objectives()
	note("chips", g.haul.chips_done)
	note("counts_after_chip", g.counts)
	# carry the rounds to the pile behind the shed
	var pile := Vector3(g.world.pile.x, 0, g.world.pile.z)
	var k := 0
	for b in g.pieces().filter(func(b): return b.kind == "trunk"):
		await _carry_to(b, pile + Vector3((k % 3 - 1) * 0.9, 0, -2.4))
		look_at_point(pile + Vector3((k % 3 - 1) * 0.9, 0.3, 0))
		g.haul.drop_all()
		k += 1
		await wait(0.3)
	await wait(2.0)
	g.update_objectives()
	note("counts_piled", g.counts)
	note("objs", g.objs)
	g.player.teleport(pile + Vector3(3, g.world.H(pile.x + 3, pile.z) + 0.05, -3))
	look_at_point(pile + Vector3(0, 0.2, 0))
	await wait(0.6)
	await shot("job-pile")
	# get paid
	var e: Vector3 = g.earl.global_position + Vector3(1.5, 0, 0)
	g.player.teleport(Vector3(e.x, g.world.H(e.x, e.z) + 0.05, e.z))
	g.talk_to_earl()
	for i in range(20):
		await wait(0.05)
		if g.dlg != null: g.advance_dialog()
	await wait(0.5)
	note("paid", g.objs.paid)
	await shot("job-summary")

func _intro() -> void:
	await wait(1.0)
	g.start_intro()
	for t in [2.0, 6.0, 10.0, 12.5, 14.0, 16.5]:
		while g.intro.t < t and g.phase == "intro": await get_tree().process_frame
		await shot("intro-%04.1f" % t)
		note("intro_t", [t, g.truck.global_position, g.chipper.coupler_world().distance_to(g.truck.hitch_world())])
	while g.phase == "intro": await wait(0.2)
	await wait(0.5)
	note("phase", g.phase)
	note("truck_settled_speed", g.truck.linear_velocity.length())
	await shot("intro-end")

func _aim_saw_across(pc: WoodPiece, wp: Vector3) -> void:
	look_at_point(wp + Vector3(0, 0.08, 0))
	var ax := pc.global_transform.basis.y.normalized()
	var best := 0.0; var bv := -1.0
	for i in range(25):
		g.saw.roll = PI * i / 24.0
		g.saw.pose(0.016, true, false)
		var v := absf(g.saw.n.dot(ax))
		if v > bv: bv = v; best = g.saw.roll
	g.saw.roll = best

## visual QA: partial cut from one side, cut ends, carrying, throwing into the truck, dragging, feeding
func _qa() -> void:
	await wait(1.0)
	g._start()
	g.objs.talk = true
	await _fell_tree_quick()
	var st: WoodPiece = g.tree.stem
	for id in st.limbs.duplicate(): Lumber.limb_off(g, st, id)
	await wait(1.0)
	st = g.tree.stem
	# a half-depth cut with the real saw, 4 m up the stem
	g.equip("saw"); g.saw.on = true; g.saw.engine_snd = Sfx.engine("saw")
	var y: float = st.span.x + 4.0
	var wp := st.to_world(Vector3(0, y, 0))
	var ax := st.global_transform.basis.y.normalized()
	var sd := ax.cross(Vector3.UP).normalized()
	g.player.crouch = true
	var ey := wp + sd * 1.0
	g.player.teleport(Vector3(ey.x, g.world.H(ey.x, ey.z) + 0.05, ey.z))
	await wait(0.4)
	await _aim_saw_across(st, wp)
	g.force_rev = true
	var tt := 0.0
	while tt < 6 and (g.saw.cut == null or g.saw.cut.s < g.saw.cut.exit * 0.5):
		await wait(0.1); tt += 0.1
	g.force_rev = false
	note("partial", [g.saw.cut.s if g.saw.cut else -1.0, g.saw.cut.exit if g.saw.cut else -1.0])
	await wait(0.4)
	g.equip("hands"); g.player.crouch = false
	for sgn in [1.0, -1.0]:
		var vp: Vector3 = wp + sd * 1.6 * sgn
		g.player.teleport(Vector3(vp.x, g.world.H(vp.x, vp.z) + 0.05, vp.z))
		look_at_point(wp)
		await wait(0.5)
		await shot("qa-partial-%s" % ("near" if sgn > 0 else "far"))
	# kick it through, then look at the two ends
	var kp := wp + sd * 1.0
	g.player.teleport(Vector3(kp.x, g.world.H(kp.x, kp.z) + 0.05, kp.z))
	look_at_point(wp)
	await wait(0.2)
	var n0: int = g.pieces().size()
	g.haul.kick()
	await wait(1.0)
	note("kick_split", g.pieces().size() - n0)
	var ep := wp + sd * 0.9 + ax * 1.3
	g.player.teleport(Vector3(ep.x, g.world.H(ep.x, ep.z) + 0.05, ep.z))
	look_at_point(wp)
	await wait(0.6)
	await shot("qa-ends")
	# buck the rest quickly into rounds
	var guard := 0
	while guard < 40:
		guard += 1
		var trunks: Array = g.pieces().filter(func(b): return b.kind == "trunk" and b.mass > Wood.LIFT_MAX * 0.92)
		if trunks.is_empty(): break
		var b: WoodPiece = trunks[0]
		var r := Wood.r_at(b.T, b.span.y - 0.3)
		var L := clampf(48.0 / (Wood.RHO * PI * r * r), 0.25, 2.0)
		var yy := b.span.y - L
		if yy <= b.span.x + 0.1: yy = (b.span.x + b.span.y) / 2
		Lumber.buck(g, b, {kind = "piece", type = "kerf", piece = b, part = {trunk = true}, e = Vector3(0, yy, 0), f = Vector3.RIGHT, n = (Vector3.UP + Vector3(0.12, 0, 0.05)).normalized(), s = 1.0, exit = 1.0, done = true})
		await wait(0.05)
	await wait(2.0)
	# carry two rounds on the shoulder
	var rounds: Array = g.pieces().filter(func(b): return b.kind == "trunk" and b.mass < 30)
	note("light_rounds", rounds.size())
	var r0: WoodPiece = rounds[0]
	var c0 := r0.center_world()
	g.player.teleport(Vector3(c0.x + 1, g.world.H(c0.x + 1, c0.z) + 0.05, c0.z))
	g.haul.pick_up(rounds[0]); g.haul.pick_up(rounds[1])
	await wait(0.6)
	g.player.pitch = -0.1
	g.player.yaw += 0.6
	await wait(0.3)
	await shot("qa-carry")
	# throw them in the truck from behind it
	var t: Truck = g.truck
	var bp := t.global_transform * Vector3(0.9, 0, -5.4)
	g.player.teleport(Vector3(bp.x, g.world.H(bp.x, bp.z) + 0.05, bp.z))
	look_at_point(t.global_transform * Vector3(0, 1.2, -1.7))
	await wait(0.3)
	note("throw_target", g.haul.throw_target() != null)
	g.haul.throw_one(); await wait(0.5); g.haul.throw_one()
	await wait(2.5)
	note("in_bed", [t.in_bed(rounds[0].center_world()), t.in_bed(rounds[1].center_world())])
	look_at_point(t.global_transform * Vector3(0, 0.8, -1.7))
	await wait(0.3)
	await shot("qa-bed")
	# drag a heavy one
	var heavy: Array = g.pieces().filter(func(b): return g.haul.can_drag(b))
	if heavy.is_empty():
		var big: Array = g.pieces().filter(func(b): return b.kind == "trunk")
		big.sort_custom(func(a, b): return a.mass > b.mass)
		var hb: WoodPiece = big[0]
		var hy: float = (hb.span.x + hb.span.y) / 2
		Lumber.buck(g, hb, {kind = "piece", type = "kerf", piece = hb, part = {trunk = true}, e = Vector3(0, hy, 0), f = Vector3.RIGHT, n = Vector3.UP, s = 1.0, exit = 1.0, done = true})
		await wait(0.5)
		heavy = g.pieces().filter(func(b): return g.haul.can_drag(b))
	note("draggable", heavy.size())
	if not heavy.is_empty():
		var hv: WoodPiece = heavy[0]
		var hc := hv.center_world()
		g.player.teleport(Vector3(hc.x + 1.2, g.world.H(hc.x + 1.2, hc.z) + 0.05, hc.z))
		look_at_point(hc)
		await wait(0.3)
		g.haul.start_drag(hv)
		var p0 := hv.center_world()
		g.player.yaw += PI
		await press("move_fwd", 3.0)
		note("dragged_m", snappedf(hv.center_world().distance_to(p0), 0.1))
		g.player.yaw += PI * 0.85; g.player.pitch = -0.45
		await wait(0.3)
		await shot("qa-drag")
		g.haul.stop_drag()
	# feeding: carry brush to the running chipper
	g.toggle_chipper()
	await wait(0.8)
	var brush: Array = g.pieces().filter(func(b): return b.kind == "limb")
	var hop: Vector3 = g.chipper.hopper_world() + (g.chipper.global_transform.basis * Vector3(0.9, 0, -1.4))
	var bb: WoodPiece = brush[0]
	await _carry_to(bb, hop)
	look_at_point(g.chipper.hopper_world())
	await wait(0.2)
	g.interact()
	await wait(1.3)
	await shot("qa-feed")
	await wait(2.0)
	await shot("qa-feed2")

func _make_rounds(n: int) -> Array:
	# a short log section spawned straight from the tree definition, cut into light rounds
	var out := []
	var T: Dictionary = g.tree.T
	for i in range(n):
		var y := 8.0 + i * 0.6
		var p := WoodPiece.new(); p.T = T; p.kind = "trunk"; p.y0 = y - 0.2; p.y1 = y + 0.6
		p.ops = [{type = "clip", p = Vector3(0, y, 0), n = Vector3.DOWN}, {type = "clip", p = Vector3(0, y + 0.4, 0), n = Vector3.UP}]
		g.level_root.add_child(p)
		var at: Vector3 = g.player.global_position + g.player.fwd() * 2.0 + Vector3(i * 0.7, 0, 0)
		p.global_transform = Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(at.x, g.world.H(at.x, at.z) + 0.5, at.z) - Basis(Vector3.RIGHT, PI / 2) * Vector3(0, y + 0.2, 0))
		p.build()
		out.append(p)
	return out

func _throw() -> void:
	await wait(1.0)
	g._start()
	var t: Truck = g.truck
	var rs := _make_rounds(4)
	await wait(1.5)
	note("round_mass", rs.map(func(r): return snappedf(r.mass, 0.1)))
	var results := []
	for side in [2.4, -2.4]:
		for r in rs.slice(0, 2) if side > 0 else rs.slice(2, 4):
			var c: Vector3 = r.center_world()
			g.player.teleport(Vector3(c.x + 1, g.world.H(c.x + 1, c.z) + 0.05, c.z))
			await wait(0.1)
			g.haul.pick_up(r)
			var sp := t.global_transform * Vector3(side, 0, -1.7)
			g.player.teleport(Vector3(sp.x, g.world.H(sp.x, sp.z) + 0.05, sp.z))
			look_at_point(t.global_transform * Vector3(0, 1.0, -1.7))
			await wait(0.4)
			var tg = g.haul.throw_target()
			g.haul.throw_one()
			await wait(2.5)
			results.append([tg != null, t.in_bed(r.center_world()), t.bed_local(r.center_world())])
	note("throws", results)
	var vp := t.global_transform * Vector3(2.6, 0, -4.0)
	g.player.teleport(Vector3(vp.x, g.world.H(vp.x, vp.z) + 0.05, vp.z))
	look_at_point(t.global_transform * Vector3(0, 0.9, -1.7))
	await wait(0.5)
	await shot("throw-bed")
	# chipper stability while feeding
	g.toggle_chipper()
	await wait(0.8)
	var c: Chipper = g.chipper
	note("chip_up_before", snappedf(rad_to_deg(c.global_transform.basis.y.angle_to(Vector3.UP)), 0.1))
	var b := WoodPiece.new(); b.T = g.tree.T; b.kind = "limb"; b.limb = 3; b.t0 = 0.0; b.t1 = 1.0
	g.level_root.add_child(b)
	var hop: Vector3 = c.hopper_world() + (c.global_transform.basis * Vector3(0.9, 0, -1.4))
	b.global_transform = Transform3D(Basis(), hop + Vector3(0, 0.5, 0) - g.tree.T.limbs[3].base)
	b.build()
	await wait(0.5)
	await _carry_to(b, hop)
	look_at_point(c.hopper_world())
	await wait(0.2)
	g.interact()
	for i in range(6):
		await wait(0.7)
		note("chip_up", [i, snappedf(rad_to_deg(c.global_transform.basis.y.angle_to(Vector3.UP)), 0.1), c.global_position])
		if i == 1: await shot("feed-a")
	await shot("feed-b")
	note("chips_done", g.haul.chips_done)

func _sawreal() -> void:
	await wait(1.0)
	g._start()
	g.objs.talk = true
	var tr: AshTree = g.tree
	var house := Vector3(g.world.house.x, 0, g.world.house.z)
	var away := (tr.global_position - house); away.y = 0; away = away.normalized()
	# stand on the face side and cut a level kerf at knee height with the real saw
	g.equip("saw"); g.saw.on = true; g.saw.engine_snd = Sfx.engine("saw")
	g.player.crouch = true
	var st := tr.global_position + away * 1.15
	g.player.teleport(Vector3(st.x, g.world.H(st.x, st.z) + 0.05, st.z))
	await wait(0.5)
	look_at_point(tr.global_position + Vector3(0, 0.6, 0))
	g.saw.roll = PI / 2     # kerf normal up: a level cut
	await wait(0.3)
	g.force_rev = true
	await wait(2.5)
	note("tree_cut", [tr.cuts.size(), tr.cuts[0].s if tr.cuts.size() > 0 else -1.0, g.saw.bind])
	await shot("real-cutting")
	g.force_rev = false
	await wait(0.4)
	g.player.crouch = false
	var vp := tr.global_position + away * 1.8 + away.cross(Vector3.UP) * 0.8
	g.player.teleport(Vector3(vp.x, g.world.H(vp.x, vp.z) + 0.05, vp.z))
	g.equip("hands")
	look_at_point(tr.global_position + Vector3(0, 0.6, 0))
	await wait(0.5)
	await shot("real-kerf")
	# other side: nothing showing through
	var bp := tr.global_position - away * 1.8
	g.player.teleport(Vector3(bp.x, g.world.H(bp.x, bp.z) + 0.05, bp.z))
	look_at_point(tr.global_position + Vector3(0, 0.6, 0))
	await wait(0.5)
	await shot("real-kerf-back")
