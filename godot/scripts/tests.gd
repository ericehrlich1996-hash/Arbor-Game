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
	if DisplayServer.get_name() == "headless": return      # logic-only runs: nothing to capture
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img: img.save_png(out_dir + "/" + name + ".png")

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

func _look() -> void:
	await wait(2.0)
	await shot("look-title")
	g._start()
	var e: Vector3 = g.earl.global_position + Vector3(2.5, 0, -2.0)
	g.player.teleport(Vector3(e.x, g.world.H(e.x, e.z) + 0.05, e.z))
	look_at_point(g.earl.global_position + Vector3(0, 1.3, 0))
	await wait(1.0)
	await shot("look-earl")
	var tr: AshTree = g.tree
	var tp := tr.global_position + Vector3(6, 0, 6)
	g.player.teleport(Vector3(tp.x, g.world.H(tp.x, tp.z) + 0.05, tp.z))
	look_at_point(tr.global_position + Vector3(0, 5, 0))
	await wait(0.8)
	await shot("look-tree")
	var t: Truck = g.truck
	var vp := t.global_transform * Vector3(4.5, 0, 4.0)
	g.player.teleport(Vector3(vp.x, g.world.H(vp.x, vp.z) + 0.05, vp.z))
	look_at_point(t.global_transform * Vector3(0, 0.8, -1.5))
	await wait(0.8)
	await shot("look-truck")
	g.equip("saw")
	g.player.pitch = -0.2
	await wait(0.5)
	await shot("look-saw")
	g.equip("hands")
	await wait(0.4)
	await shot("look-hands")

## cut straight through from one side with the real saw and keep the throttle down while it goes
func _sawdrop() -> void:
	await wait(1.0)
	g._start()
	g.objs.talk = true
	var tr: AshTree = g.tree
	var house := Vector3(g.world.house.x, 0, g.world.house.z)
	var away := (tr.global_position - house); away.y = 0; away = away.normalized()
	g.equip("saw"); g.saw.on = true; g.saw.engine_snd = Sfx.engine("saw")
	g.player.crouch = true
	# come at it at an angle so the bar only grazes the trunk at first
	var side := away.cross(Vector3.UP)
	var st := tr.global_position + away * 1.0 + side * 0.25
	g.player.teleport(Vector3(st.x, g.world.H(st.x, st.z) + 0.05, st.z))
	await wait(0.5)
	look_at_point(tr.global_position + side * 0.2 + Vector3(0, 0.6, 0))
	g.saw.roll = PI / 2
	g.force_rev = true
	await wait(0.6)
	if tr.cuts.size() > 0: note("graze", [tr.cuts[0].s, tr.cuts[0].exit])
	g.force_rev = false
	await wait(0.3)
	var A = tr.analyze()
	note("held_frac_after_graze", A.frac if A != null else 1.0)
	await shot("graze")
	look_at_point(tr.global_position + Vector3(0, 0.6, 0))
	g.force_rev = true
	var tt := 0.0
	while tr.state == "stand" and tt < 20:
		await wait(0.25); tt += 0.25
	note("fell_after", [tt, tr.state])
	await wait(2.0)
	g.force_rev = false
	note("no_crash", true)

func _sawdrop2() -> void:
	await wait(1.0)
	g._start()
	g.objs.talk = true
	var tr: AshTree = g.tree
	var house := Vector3(g.world.house.x, 0, g.world.house.z)
	var away := (tr.global_position - house); away.y = 0; away = away.normalized()
	g.equip("saw"); g.saw.on = true; g.saw.engine_snd = Sfx.engine("saw")
	g.player.crouch = true
	var st := tr.global_position + away * 0.95
	g.player.teleport(Vector3(st.x, g.world.H(st.x, st.z) + 0.05, st.z))
	await wait(0.5)
	look_at_point(tr.global_position + Vector3(0, 0.6, 0))
	g.saw.roll = PI / 2
	g.force_rev = true
	var tt := 0.0
	while tr.state == "stand" and tt < 12:
		await wait(0.25); tt += 0.25
		if int(tt * 4) % 8 == 0 and tr.cuts.size() > 0: print("s ", tr.cuts[0].s, " exit ", tr.cuts[0].exit, " held ", tr.A.frac if tr.A != null else -1.0)
	note("fell_after", [tt, tr.state])
	await wait(3.0)
	g.force_rev = false
	await shot("drop-after")
	note("no_crash", true)

func _window() -> void:
	await wait(1.0)
	g._start()
	var t: Truck = g.truck
	for i in range(8):
		await wait(0.25)
		print("v ", t.linear_velocity.length(), " w ", t.angular_velocity.length(), " still ", t._still_t, " frz ", t.freeze, " drv ", t.driving)
	note("parked_frozen", t.freeze)
	var p0 := t.global_position
	await wait(3.0)
	note("creep_mm", snappedf(t.global_position.distance_to(p0) * 1000, 0.1))
	g.player.teleport(t.global_transform * Vector3(0.3, Truck.BED_FLOOR_Y + 0.05, -2.2))
	look_at_point(t.global_transform * Vector3(0, 1.6, 1.5))
	await wait(0.6)
	await shot("window-from-bed")
	var rs := _make_rounds(1)
	await wait(1.5)
	note("round_kg", rs[0].mass)

func _magnet() -> void:
	await wait(1.0)
	g._start()
	var tr: AshTree = g.tree
	var house := Vector3(g.world.house.x, 0, g.world.house.z)
	var away := (tr.global_position - house); away.y = 0; away = away.normalized()
	g.equip("saw"); g.saw.on = true; g.saw.engine_snd = Sfx.engine("saw")
	g.player.crouch = true
	var st := tr.global_position + away * 0.95
	g.player.teleport(Vector3(st.x, g.world.H(st.x, st.z) + 0.05, st.z))
	await wait(0.5)
	look_at_point(tr.global_position + Vector3(0, 0.6, 0))
	g.saw.roll = PI / 2
	g.force_rev = true
	await wait(0.4)
	g.force_rev = false
	await wait(0.5)
	var s0: float = tr.cuts[0].s
	g.saw.roll = PI / 2 + 0.3        # come back in about 17° off
	g.force_rev = true
	await wait(1.0)
	g.force_rev = false
	note("magnet", {cuts = tr.cuts.size(), s_before = s0, s_after = tr.cuts[0].s, roll_after_deg = rad_to_deg(g.saw.roll)})

func _view(name: String, at: Vector3, look: Vector3) -> void:
	g.player.teleport(Vector3(at.x, g.world.H(at.x, at.z) + 0.05, at.z))
	look_at_point(look)
	await wait(0.8)
	await shot(name)

func _forest() -> void:
	note("startup_ms", Time.get_ticks_msec())
	await wait(1.0)
	await shot("forest-title")
	g._start()
	var w: WorldGen = g.world
	# from the middle of the yard toward each side
	await _view("forest-yard-n", Vector3(0, 0, 30), Vector3(0, 3, 80))
	await _view("forest-yard-w", Vector3(-30, 0, 10), Vector3(-80, 4, 10))
	# standing in the woods
	await _view("forest-inside", Vector3(-70, 0, 20), Vector3(-90, 3, 35))
	await _view("forest-inside2", Vector3(60, 0, 70), Vector3(80, 5, 90))
	# the drive in from the road
	await _view("forest-road", Vector3(w.s * 30, 0, w.road_z), Vector3(0, 2, w.road_z + 30))
	note("fps", Engine.get_frames_per_second())

func _forest2() -> void:
	await wait(1.0)
	var n := 0; var tris := 0
	for c in g.level_root.get_children():
		if c is MultiMeshInstance3D: n += c.multimesh.instance_count
	note("instances", n)
	g._start()
	await _view("f2-inside", Vector3(-70, 0, 20), Vector3(-90, 3, 35))
	await _view("f2-edge", Vector3(-30, 0, 10), Vector3(-80, 4, 10))
	note("fps", Engine.get_frames_per_second())

func _perf() -> void:
	g._start()
	var tr: AshTree = g.tree
	var spots := [g.earl.global_position + Vector3(2.5, 0, -2.0), tr.global_position + Vector3(6, 0, 6), Vector3(60, 0, 60), Vector3(-80, 0, 20)]
	for s: Vector3 in spots:
		g.player.teleport(Vector3(s.x, g.world.H(s.x, s.z) + 0.05, s.z))
		for i in range(6):
			var t0 := Time.get_ticks_msec()
			await get_tree().process_frame
			print("PERF ", s, " frame ", Time.get_ticks_msec() - t0, "ms prims ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), " objs ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), " draws ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		if OS.get_environment("PERF_QUICK") != "": break

func _tris() -> void:
	var f := Forest.new()
	f.w = g.world
	f._models()
	for k in f.models:
		var m: Mesh = f.models[k].mesh
		var n := 0
		for s in range(m.get_surface_count()):
			var a := m.surface_get_arrays(s)
			n += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null else a[Mesh.ARRAY_VERTEX].size()) / 3
		print("TRIS ", k, " ", n)
	var cnt := {}
	for mi in g.get_tree().root.find_children("*", "MultiMeshInstance3D", true, false):
		var k: String = str((mi as MultiMeshInstance3D).multimesh.mesh.get_rid())
		cnt[k] = cnt.get(k, 0) + (mi as MultiMeshInstance3D).multimesh.instance_count
	var tot := 0
	for mi in g.get_tree().root.find_children("*", "MultiMeshInstance3D", true, false):
		tot += (mi as MultiMeshInstance3D).multimesh.instance_count
	print("TRIS instances ", tot)

func _ablate() -> void:
	g._start()
	var s: Vector3 = g.earl.global_position + Vector3(2.5, 0, -2.0)
	g.player.teleport(Vector3(s.x, g.world.H(s.x, s.z) + 0.05, s.z))
	look_at_point(g.earl.global_position + Vector3(0, 1.3, 0))
	var all: Array = g.get_tree().root.find_children("*", "GeometryInstance3D", true, false)
	var groups := {"near": "^(fir|oak|birch)\\d$", "mid": "_mid", "far": "_far", "fern": "fern", "bush": "bush", "grass": "^(grass|Grass)", "rocklog": "^(rock|log|stump|snag)", "flower": "flower", "terrain": "Terrain", "shafts": "LightShafts", "treeline": "Treeline"}
	await _ptime("base")
	for gname in groups:
		var re := RegEx.create_from_string(groups[gname])
		var hid := []
		for n: GeometryInstance3D in all:
			if n.visible and re.search(str(n.get_meta("key", n.name))) != null:
				n.visible = false; hid.append(n)
		await _ptime("no-" + gname + " (" + str(hid.size()) + ")")
		for n: GeometryInstance3D in hid: n.visible = true
	g.sun.shadow_enabled = false
	await _ptime("no-shadow")

func _ptime(label: String) -> void:
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	await get_tree().process_frame
	await get_tree().process_frame
	print("ABL ", label, " ", (Time.get_ticks_msec() - t0) / 2, "ms prims ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))

func _gallery() -> void:
	await wait(0.5)
	g._start()
	var h: Dictionary = g.world.house
	var fz: float = h.z - h.d / 2
	await _view("gal-house", Vector3(h.x + 4, 0, fz - 12), Vector3(h.x, g.world.H(h.x, h.z) + 2.2, h.z))
	await _view("gal-porch", Vector3(h.x + h.w * 0.18 - 3, 0, fz - 5.5), Vector3(h.x + h.w * 0.18, g.world.H(h.x, h.z) + 1.3, fz - 1.2))
	var s: Dictionary = g.world.shed
	await _view("gal-shed", Vector3(s.x + 3, 0, s.z - 6), Vector3(s.x, g.world.H(s.x, s.z) + 1.3, s.z))
	var e: Vector3 = g.earl.global_position
	var ef: Vector3 = g.earl.global_transform.basis.z
	await _view("gal-earl", e + ef * 1.8 + Vector3(0.3, 0, 0), e + Vector3(0, 1.45, 0))
	var c: Chipper = g.chipper
	await _view("gal-chipper", c.global_transform * Vector3(3.2, 0, -2.0), c.global_transform * Vector3(0, 0.6, -2.2))
	var t: Truck = g.truck
	await _view("gal-truck", t.global_transform * Vector3(3.5, 0, 2.8), t.global_transform * Vector3(0, 0.9, 0.5))
	await _view("gal-truck-rear", t.global_transform * Vector3(-2.5, 0, -5.5), t.global_transform * Vector3(0, 0.9, -1.5))
	await _view("gal-woods", Vector3(-70, 0, 20), Vector3(-90, 2, 32))
	await _view("gal-woods2", Vector3(60, 0, -60), Vector3(80, 2, -75))
	var cz: float = g.world.creek_z(-20.0)
	await _view("gal-creek", Vector3(-24, 0, cz - 8), Vector3(-16, g.world.H(-16, cz) + 0.3, cz))
	g.equip("saw")
	await _view("gal-saw", g.tree.global_position + Vector3(2, 0, 2), g.tree.global_position + Vector3(0, 0.8, 0))

## chaos: a long run of random actions all over the job, checking nothing goes NaN, flips or falls through the world
func _soak() -> void:
	await wait(0.5)
	g._start()
	g.objs.talk = true
	await _fell_tree_quick()
	var rng := RandomNumberGenerator.new(); rng.seed = int(OS.get_environment("SOAK_SEED")) if OS.get_environment("SOAK_SEED") != "" else 7
	var steps := int(OS.get_environment("SOAK_STEPS")) if OS.get_environment("SOAK_STEPS") != "" else 50
	var acts := {}
	for i in range(steps):
		var ps: Array = g.pieces()
		var a := rng.randi() % 10
		var name := ""
		if g.player.in_truck and a != 6: g.exit_truck()
		match a:
			0, 1:
				name = "pickup"
				if not ps.is_empty():
					var b: WoodPiece = ps[rng.randi() % ps.size()]
					var p := b.global_position + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
					g.player.teleport(Vector3(p.x, g.world.H(p.x, p.z) + 0.05, p.z))
					look_at_point(b.global_position)
					await wait(0.15)
					g.equip("hands"); g.interact()
			2:
				name = "throw"
				if g.haul.carrying(): look_at_point(g.truck.global_position + Vector3(0, 1, 0)); g.haul.throw_one()
			3:
				name = "drop"
				if g.haul.carrying(): g.haul.drop_all()
			4:
				name = "kick"
				g.haul.kick()
			5:
				name = "saw"
				if not ps.is_empty():
					var b: WoodPiece = ps[rng.randi() % ps.size()]
					var p := b.global_position + Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2))
					g.haul.drop_all()
					g.player.teleport(Vector3(p.x, g.world.H(p.x, p.z) + 0.05, p.z))
					look_at_point(b.global_position)
					g.equip("saw"); g.saw.on = true
					if g.saw.engine_snd == null: g.saw.engine_snd = Sfx.engine("saw")
					g.force_rev = true
					await wait(rng.randf_range(0.3, 2.0))
					g.force_rev = false
			6:
				name = "drive"
				g.haul.drop_all()
				if not g.player.in_truck:
					var tp: Vector3 = g.truck.global_transform * Vector3(-1.6, 0, 0.2)
					g.player.teleport(Vector3(tp.x, g.world.H(tp.x, tp.z) + 0.05, tp.z))
					look_at_point(g.truck.global_position + Vector3(0, 1.2, 0))
					await wait(0.1)
					g.enter_truck()
				var act := "move_fwd" if rng.randf() < 0.7 else "move_back"
				Input.action_press(act)
				if rng.randf() < 0.5: Input.action_press("move_left")
				await wait(rng.randf_range(0.5, 1.5))
				Input.action_release(act); Input.action_release("move_left")
			7:
				name = "drag"
				if not ps.is_empty():
					var b: WoodPiece = ps[rng.randi() % ps.size()]
					if g.haul.can_drag(b):
						g.haul.drop_all()
						var p := b.global_position + Vector3(1.0, 0, 0.5)
						g.player.teleport(Vector3(p.x, g.world.H(p.x, p.z) + 0.05, p.z))
						look_at_point(b.global_position)
						await wait(0.1)
						g.haul.start_drag(b)
						Input.action_press("move_back"); await wait(0.6); Input.action_release("move_back")
						g.haul.stop_drag()
			8:
				name = "chipper"
				g.haul.drop_all()
				var hp: Vector3 = g.chipper.hopper_world()
				g.player.teleport(Vector3(hp.x, g.world.H(hp.x, hp.z) + 0.05, hp.z - 1.0))
				g.toggle_chipper()
			9:
				name = "detail"
				g.set_detail(1 - g.detail)
		acts[name] = acts.get(name, 0) + 1
		await wait(0.2)
		# sanity
		for b in g.pieces():
			var bp: Vector3 = b.center_world()
			if not bp.is_finite(): note("BAD_nan_piece", [i, name]); break
			if bp.y < g.world.H(bp.x, bp.z) - 3.0: note("BAD_fell_through", [i, name, bp]); break
		var pp: Vector3 = g.player.global_position
		if not pp.is_finite() or pp.y < g.world.H(pp.x, pp.z) - 2.0: note("BAD_player", [i, name, pp])
		if g.truck.global_transform.basis.y.y < 0.3: note("BAD_truck_flipped", [i, name])
	if g.player.in_truck: g.exit_truck()
	g.set_detail(1)
	note("acts", acts)
	note("pieces", g.pieces().size())
	note("fps_end", Engine.get_frames_per_second())

func _gal2() -> void:
	await wait(1.0)
	await shot("g2-title")
	g._start()
	var x := -20.0
	var cz: float = g.world.creek_z(x)
	await _view("g2-creek", Vector3(x, 0, cz - 3.9), Vector3(x + 12, g.world.H(x + 12, g.world.creek_z(x + 12)), g.world.creek_z(x + 12)))
	await _view("g2-creek2", Vector3(x + 3, 0, cz + 4.2), Vector3(x - 8, g.world.H(x - 8, g.world.creek_z(x - 8)) + 0.4, g.world.creek_z(x - 8)))
	await _view("g2-road", Vector3(10, 0, g.world.road_z + 5), Vector3(30, 5, g.world.road_z - 6))
	g.player.pitch = 0.6
	await wait(0.5)
	await shot("g2-sky")

## fell the tree with the guided saw the way a player would: notch on the fall side, back cut from behind
func _guided() -> void:
	await wait(0.5)
	g._start()
	g.objs.talk = true
	var tr: AshTree = g.tree
	var R: float = Wood.r_at(tr.T, 0.6)
	var house := Vector3(g.world.house.x, 0, g.world.house.z)
	var away := tr.global_position - house; away.y = 0; away = away.normalized()
	var side := away.cross(Vector3.UP).normalized()
	var base := tr.global_position
	g.equip("saw"); g.saw.on = true; g.saw.engine_snd = Sfx.engine("saw")
	g.player.crouch = true
	# stand beside the tree, square to the way it should fall; the bar points across the trunk
	var stand := base + side * (R + float(OS.get_environment('STAND_D') if OS.get_environment('STAND_D') != '' else '0.8'))
	g.player.teleport(Vector3(stand.x, g.world.H(stand.x, stand.z) + 0.05, stand.z))
	await wait(0.5)
	var hb := 0.55
	var top_h := hb + 2 * R * 0.33 * tan(deg_to_rad(50))
	# aim at the fall side of the trunk: the notch opens that way
	look_at_point(tr.to_world(Vector3(0, top_h, 0)) + away * R * 0.8 + side * R * 0.5)
	g.saw.tilt = deg_to_rad(50)
	await wait(0.5)
	note("guide_top", [not g.saw.guide.is_empty(), g.saw.guide.get("kind", ""), g.saw.guide.get("too_far", null), g.saw.guide.get("too_close", null), g.saw.guide.get("hand_ahead", null)])
	await shot("guided-aim")
	g.force_rev = true
	var tt := 0.0
	while tt < 12.0 and (g.saw.cut == null or g.saw.cut.s < 2 * R * 0.33 / cos(deg_to_rad(50))):
		await wait(0.1); tt += 0.1
	note("top_cut", [g.saw.cut.s if g.saw.cut else -1.0, tt])
	await shot("guided-topcut")
	g.force_rev = false
	await wait(0.3)
	look_at_point(tr.to_world(Vector3(0, hb, 0)) + away * R * 0.8 + side * R * 0.5)
	g.saw.tilt = 0.0
	await wait(0.4)
	g.force_rev = true
	tt = 0.0
	while tt < 12.0 and tr.freed.is_empty():
		await wait(0.1); tt += 0.1
	g.force_rev = false
	note("notch_out", [not tr.freed.is_empty(), tt])
	await wait(0.6)
	await shot("guided-notch")
	# back cut from the same spot: aim at the back of the trunk, a little above the notch floor
	look_at_point(tr.to_world(Vector3(0, hb + 0.04, 0)) - away * R * 0.8 + side * R * 0.5)
	await wait(0.5)
	await shot("guided-backaim")
	g.force_rev = true
	tt = 0.0
	while tt < 20.0 and tr.state == "stand":
		await wait(0.1); tt += 0.1
	g.force_rev = false
	note("fell", [tr.state, tt, tr.grade])
	g.player.crouch = false
	await wait(4.0)
	var vp := base - away * 6.0
	g.player.teleport(Vector3(vp.x, g.world.H(vp.x, vp.z) + 0.05, vp.z))
	look_at_point(base + away * 6.0)
	await wait(0.5)
	await shot("guided-down")
	# buck: aim at the stem 3 m out and cut a round, timing it
	var st: WoodPiece = tr.stem
	if st and is_instance_valid(st):
		for id in st.limbs.duplicate(): Lumber.limb_off(g, st, id)
		await wait(1.0)
		st = tr.stem
		var wp := st.to_world(Vector3(0, st.span.x + 3.0, 0))
		var ax := st.global_transform.basis.y.normalized()
		var sd := ax.cross(Vector3.UP).normalized()
		var ey := wp + sd * 0.9
		g.player.teleport(Vector3(ey.x, g.world.H(ey.x, ey.z) + 0.05, ey.z))
		await wait(0.3)
		look_at_point(wp + Vector3(0, 0.15, 0))
		await wait(0.4)
		note("buck_guide", [not g.saw.guide.is_empty(), g.saw.guide.get("kind", "")])
		await shot("guided-buckaim")
		var n0: int = g.pieces().size()
		g.force_rev = true
		tt = 0.0
		while tt < 25.0 and g.pieces().size() == n0:
			await wait(0.1); tt += 0.1
		g.force_rev = false
		note("buck_time", tt)
		await wait(0.5)
		await shot("guided-bucked")

## unhitch the chipper, walk it around by the tongue, set it down: it must stay on its wheels
func _tow() -> void:
	await wait(0.5)
	g._start()
	var c: Chipper = g.chipper
	g.hitch_action()
	await wait(1.0)
	var cp := c.coupler_world()
	var fwd: Vector3 = c.global_transform.basis.z; fwd.y = 0; fwd = fwd.normalized()
	var stand := cp + fwd * 1.0
	g.player.teleport(Vector3(stand.x, g.world.H(stand.x, stand.z) + 0.05, stand.z))
	look_at_point(cp)
	await wait(0.3)
	g.hitch_action()
	note("mode", c.mode)
	# walk backwards, then turn and walk on
	Input.action_press("move_back"); await wait(2.0)
	Input.action_press("move_left"); await wait(1.5); Input.action_release("move_left")
	Input.action_release("move_back")
	g.player.yaw += 1.2
	Input.action_press("move_fwd"); await wait(2.0); Input.action_release("move_fwd")
	note("up_while_towing", c.global_transform.basis.y.y)
	await shot("tow-moving")
	g.interact()
	await wait(2.0)
	note("mode_after", c.mode)
	note("up_after_setdown", c.global_transform.basis.y.y)
	await shot("tow-down")

func _fix2() -> void:
	await wait(0.5)
	g._start()
	g.player.pitch = -0.1
	await wait(0.4)
	await shot("fix2-hands")
	# unhitch the chipper: it must sit still on its jack
	var c: Chipper = g.chipper
	var cp := c.coupler_world()
	g.player.teleport(Vector3(cp.x + 1.5, g.world.H(cp.x + 1.5, cp.z) + 0.05, cp.z + 1.0))
	look_at_point(cp)
	await wait(0.3)
	g.hitch_action()
	await wait(3.0)
	note("chipper_up", c.global_transform.basis.y.y)
	note("chipper_spin", c.angular_velocity.length())
	await shot("fix2-unhitched")
	# knock the truck over and flip it back
	var t: Truck = g.truck
	t.freeze = false
	t.global_transform = Transform3D(Basis(t.global_transform.basis.z, 1.7) * t.global_transform.basis, t.global_position + Vector3(0, 1.2, 0))
	await wait(3.0)
	note("truck_tipped_up", t.global_transform.basis.y.y)
	var tp := t.global_position + Vector3(3, 0, 0)
	g.player.teleport(Vector3(tp.x, g.world.H(tp.x, tp.z) + 0.05, tp.z))
	await wait(0.3)
	note("tipped_near", g._tipped_near())
	await shot("fix2-tipped")
	g.interact()
	await wait(3.0)
	note("truck_after_flip", t.global_transform.basis.y.y)
	# the saw across the trunk, mid back-cut
	var tr: AshTree = g.tree
	var R: float = Wood.r_at(tr.T, 0.6)
	var dir := Vector3(1, 0, 0)
	g.equip("saw"); g.saw.on = true; g.saw.engine_snd = Sfx.engine("saw")
	var st := tr.global_position + dir * (R + 0.9)
	g.player.teleport(Vector3(st.x, g.world.H(st.x, st.z) + 0.05, st.z))
	look_at_point(tr.to_world(Vector3(0, 0.9, 0)) + dir * R)
	await wait(0.4)
	g.force_rev = true
	await wait(0.5)
	await shot("fix2-sawing")
	g.force_rev = false
	note("cut_w", g.saw.cut.get("w", -1.0) if g.saw.cut else -2.0)
	await wait(0.3)
	g.player.crouch = true
	look_at_point(tr.to_world(Vector3(0, 0.5, 0)) + dir * R)
	await wait(0.6)
	g.force_rev = true
	await wait(0.4)
	await shot("fix2-sawing2")
	g.force_rev = false

func _fix3() -> void:
	await wait(0.5)
	g._start()
	var p: Vector3 = g.tree.global_position + Vector3(4, 0, 4)
	g.player.teleport(Vector3(p.x, g.world.H(p.x, p.z) + 0.05, p.z))
	g.player.pitch = -0.25
	await wait(0.5)
	await shot("fix3-hands")
	var t: Truck = g.truck
	t.freeze = false
	var b := t.global_transform.basis
	var txf := Transform3D(Basis(b.z.normalized(), PI) * b, t.global_position + Vector3(0, 1.8, 0))
	t.global_transform = txf
	PhysicsServer3D.body_set_state(t.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, txf)
	await wait(1.5)
	note("after_tip_up", t.global_transform.basis.y.y)
	var tp := t.global_position + Vector3(3, 0, 0)
	g.player.teleport(Vector3(tp.x, g.world.H(tp.x, tp.z) + 0.05, tp.z))
	look_at_point(t.global_position)
	await wait(0.3)
	note("tipped_near", g._tipped_near())
	await shot("fix3-tipped")
	g.interact()
	await wait(3.0)
	note("truck_after_flip", t.global_transform.basis.y.y)
	await shot("fix3-flipped")

func _hands() -> void:
	await wait(0.5)
	g._start()
	var p: Vector3 = g.tree.global_position + Vector3(4, 0, 4)
	g.player.teleport(Vector3(p.x, g.world.H(p.x, p.z) + 0.05, p.z))
	g.player.pitch = 0.0
	await wait(0.5)
	await shot("hands-idle")

func _weather() -> void:
	await wait(0.5)
	g._start()
	var h: Dictionary = g.world.house
	var at := Vector3(h.x + 6, 0, h.z - h.d / 2 - 16)
	for k: String in ["clear", "overcast", "fog", "rain", "storm"]:
		g.weather.force(k)
		await _view("weather-" + k, at, Vector3(h.x, g.world.H(h.x, h.z) + 3.0, h.z))
	note("kind", g.weather.kind)

func _carrymeter() -> void:
	await wait(0.5)
	g._start()
	g.objs.talk = true
	await _fell_tree_quick()
	var st: WoodPiece = g.tree.stem
	for id in st.limbs.duplicate(): Lumber.limb_off(g, st, id)
	await wait(1.0)
	var brush: Array = g.pieces().filter(func(b): return b.is_brush() and g.haul.liftable(b))
	brush.sort_custom(func(a, b): return a.mass < b.mass)
	var shots := 0
	for b: WoodPiece in brush:
		if not g.haul.can_add(b): continue
		var p := b.center_world() + Vector3(1.0, 0, 0)
		g.player.teleport(Vector3(p.x, g.world.H(p.x, p.z) + 0.05, p.z))
		look_at_point(b.center_world())
		await wait(0.3)
		g.aim = g.compute_aim()
		var ok: bool = g._grab_aimed()
		note("grab", [ok, g.haul.carry.size(), g.haul.carry_mass()])
		await wait(0.2)
		if g.haul.carry.size() in [1, 3]:
			await shot("carry-%d" % g.haul.carry.size())
		if g.haul.carry.size() >= 5: break
	await shot("carry-final")

## per-frame CPU cost from launch: script process time, physics time, and frame time
func _startprof() -> void:
	if OS.get_environment("NORENDER") != "": RenderingServer.render_loop_enabled = false
	var t0 := Time.get_ticks_msec()
	for i in range(40):
		var f0 := Time.get_ticks_usec()
		await get_tree().process_frame
		print("SP title %d frame %.1fms proc %.1fms phys %.1fms" % [i, (Time.get_ticks_usec() - f0) / 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	g.start_intro()
	for i in range(60):
		var f0 := Time.get_ticks_usec()
		await get_tree().process_frame
		if OS.get_environment("NOMIRROR") != "": g.truck.mirror_live = false
		print("SP intro %d frame %.1fms prims %d draws %d" % [i, (Time.get_ticks_usec() - f0) / 1000.0, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	g.end_intro()
	for i in range(60):
		var f0 := Time.get_ticks_usec()
		await get_tree().process_frame
		print("SP play %d frame %.1fms prims %d draws %d" % [i, (Time.get_ticks_usec() - f0) / 1000.0, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	print("SP total ", Time.get_ticks_msec() - t0)

func _introablate() -> void:
	await wait(0.5)
	g.start_intro()
	for i in range(15): await get_tree().process_frame
	g.truck.mirror_live = false
	var all: Array = g.get_tree().root.find_children("*", "GeometryInstance3D", true, false)
	var groups := {"near": "^(fir|oak|birch)\\\\d$", "mid": "_mid", "far": "_far", "shadow": "_shadow", "plants": "^(fern|grass|flower|bush|litter|Grass)", "rocklog": "^(rock|log|stump|snag|sapling)", "terrain": "Terrain", "truck": "Body|Glass|Tailgate", "power": "PowerLine"}
	await _ptime("base")
	for gname in groups:
		var re := RegEx.create_from_string(groups[gname])
		var hid := []
		for n: GeometryInstance3D in all:
			if n.visible and re.search(str(n.get_meta("key", n.name))) != null:
				n.visible = false; hid.append(n)
		await _ptime("no-" + gname + " (" + str(hid.size()) + ")")
		for n: GeometryInstance3D in hid: n.visible = true

func _woodsview() -> void:
	await wait(0.5)
	g._start()
	await _view("wv-woods", Vector3(-70, 0, 20), Vector3(-90, 3, 32))
	await _view("wv-edge", Vector3(-30, 0, 10), Vector3(-80, 6, 10))
	await _view("wv-road", Vector3(10, 0, g.world.road_z + 2), Vector3(60, 4, g.world.road_z))

func _ringaim() -> void:
	await wait(0.5)
	g._start()
	var tr: AshTree = g.tree
	var R: float = Wood.r_at(tr.T, 0.6)
	var dir := Vector3(1, 0, 0)
	g.equip("saw"); g.saw.on = true; g.saw.engine_snd = Sfx.engine("saw")
	g.player.crouch = true
	var st := tr.global_position + dir * (R + 0.5)
	g.player.teleport(Vector3(st.x, g.world.H(st.x, st.z) + 0.05, st.z))
	look_at_point(tr.to_world(Vector3(0, 0.7, 0)) + dir * R)
	g.saw.tilt = deg_to_rad(45)
	await wait(0.8)
	await shot("ring-aim45")
	g.saw.tilt = 0.0
	look_at_point(tr.to_world(Vector3(0, 0.5, 0)) + dir * R)
	await wait(0.6)
	await shot("ring-aim0")

func _bucktime() -> void:
	await wait(0.5)
	g._start()
	g.objs.talk = true
	await _fell_tree_quick()
	var st: WoodPiece = g.tree.stem
	for id in st.limbs.duplicate(): Lumber.limb_off(g, st, id)
	await wait(3.0)
	st = g.tree.stem
	var wp := st.to_world(Vector3(0, st.span.x + 3.0, 0))
	var ax := st.global_transform.basis.y.normalized()
	var sd := ax.cross(Vector3.UP).normalized()
	var ey := wp + sd * 0.95
	g.player.teleport(Vector3(ey.x, g.world.H(ey.x, ey.z) + 0.05, ey.z))
	g.equip("saw"); g.saw.on = true; g.saw.engine_snd = Sfx.engine("saw")
	await wait(0.3)
	look_at_point(wp + Vector3(0, 0.12, 0))
	await wait(0.5)
	note("guide", [g.saw.guide.get("kind", ""), g.saw.guide.get("too_far", null), g.saw.guide.get("hand_ahead", null)])
	g.force_rev = true
	var tt := 0.0
	var n0: int = g.pieces().size()
	while tt < 15.0:
		await wait(0.5); tt += 0.5
		var c = g.saw.cut
		note("s", [tt, c.s if c else -1.0, c.exit if c else -1.0, g.pieces().size() - n0])
		if g.pieces().size() != n0: break
	g.force_rev = false

func _limbring() -> void:
	await wait(0.5)
	g._start()
	g.objs.talk = true
	# pinch: cut level straight in from the side the tree leans to
	var tr: AshTree = g.tree
	tr.def.lean = 0.08
	var R: float = Wood.r_at(tr.T, 0.6)
	var lw: Vector3 = tr.lean_dir
	var side := lw.cross(Vector3.UP).normalized()
	g.equip("saw"); g.saw.on = true; g.saw.engine_snd = Sfx.engine("saw")
	g.player.crouch = true
	var st := tr.global_position + side * (R + 0.8)
	g.player.teleport(Vector3(st.x, g.world.H(st.x, st.z) + 0.05, st.z))
	await wait(0.4)
	look_at_point(tr.to_world(Vector3(0, 0.6, 0)) + lw * R * 0.8 + side * R * 0.5)
	await wait(0.4)
	g.force_rev = true
	await wait(6.0)
	g.force_rev = false
	var c = tr.cuts[0] if not tr.cuts.is_empty() else null
	note("pinch", [c.s if c else -1.0, 2 * R, g.saw._pinch_told, tr.state])
	g.player.crouch = false
	# then the stem on the ground: aim at a limb
	tr.def.lean = 0.03
	await _fell_tree_quick()
	var stem: WoodPiece = tr.stem
	var lp := Vector3.ZERO; var best := 1e9
	for id in stem.limbs:
		var LL: Dictionary = stem.T.limbs[id]
		for t: float in [0.15, 0.3, 0.45, 0.6]:
			var w := stem.to_world(Wood.limb_pt(LL, t))
			var hgt: float = w.y - g.world.H(w.x, w.z)
			if hgt > 0.3 and absf(hgt - 0.8) < best: best = absf(hgt - 0.8); lp = w
	var vp := lp + Vector3(0.75, 0, 0.35)
	g.equip("saw"); g.saw.on = true
	g.player.teleport(Vector3(vp.x, g.world.H(vp.x, vp.z) + 0.05, vp.z))
	await wait(0.3)
	look_at_point(lp)
	await wait(0.6)
	note("limb_guide", [g.saw.guide.has("ring_c"), g.saw.guide.get("too_far", null)])
	await shot("limbring")
	var n0: int = stem.limbs.size()
	g.force_rev = true
	var tt := 0.0
	while tt < 8.0 and is_instance_valid(stem) and stem.limbs.size() == n0:
		await wait(0.2); tt += 0.2
	g.force_rev = false
	note("limb_cut", [tt, is_instance_valid(stem) and stem.limbs.size() < n0])
	await shot("limbring-after")

func _tlapse() -> void:
	await wait(0.5)
	g._start()
	g.objs.talk = true
	g.timelapse.interval = 0.6
	var tr: AshTree = g.tree
	var R: float = Wood.r_at(tr.T, 0.6)
	var p0 := tr.global_position + Vector3(R + 0.8, 0, 0)
	g.player.teleport(Vector3(p0.x, g.world.H(p0.x, p0.z) + 0.05, p0.z))
	g.equip("saw")
	look_at_point(tr.global_position + Vector3(0, 0.6, 0))
	await wait(3.0)
	await _fell_tree_quick()
	var pile := Vector3(g.world.pile.x, 0, g.world.pile.z)
	for k in range(6):
		var q := tr.global_position.lerp(pile, k / 5.0) + Vector3(1.5, 0, 0)
		g.player.teleport(Vector3(q.x, g.world.H(q.x, q.z) + 0.05, q.z))
		g.equip("hands" if k % 2 else "saw")
		await wait(0.8)
	note("frames", g.timelapse.frames.size())
	note("tl_cam", [g.timelapse.cam.global_position, Vector3(g.world.tree.x, 0, g.world.tree.z), Vector3(g.world.pile.x, 0, g.world.pile.z)])
	if g.timelapse.frames.size() > 0:
		g.timelapse.frames[0].save_png(out_dir + "/tl-f0.png")
		g.timelapse.frames[g.timelapse.frames.size() - 1].save_png(out_dir + "/tl-flast.png")
	if OS.get_environment("TL_QUICK") != "": return
	await shot("tl-play")
	g.payday()
	for i in range(10):
		await wait(0.4)
		if g.dlg != null: g.advance_dialog()
	await wait(1.5)
	await shot("tl-summary")
	await wait(1.0)
	await shot("tl-summary2")

func _kickleg() -> void:
	await wait(0.5)
	g._start()
	g.player.pitch = -0.7
	g.haul.kick()
	await wait(0.22)
	await shot("kick-out")

func _hview(name: String, at: Vector3, look: Vector3) -> void:
	var y0: float = g.hub.y0
	var p: Player = g.player
	p.teleport(Vector3(at.x, g.world.H(at.x, at.z) + 0.05 if at.y < 0.2 else y0 + at.y, at.z))
	look_at_point(Vector3(look.x, y0 + look.y, look.z))
	await wait(0.8)
	await shot(name)

func _hub() -> void:
	await wait(1.5)
	await shot("hub-title")
	g.hub_begin()
	await wait(1.2)
	await shot("hub-start")
	await _hview("hub-yard", Vector3(9, 0, -12), Vector3(0, 2, 0))
	await _hview("hub-truck", Vector3(4.5, 0, -12.5), Vector3(7, 1, -9.5))
	await _hview("hub-door", Vector3(1.3, 0.5, -2.6), Vector3(-1.5, 1.2, 1.5))
	await _hview("hub-fire", Vector3(0.5, 0.5, -1.5), Vector3(-4, 1.0, -0.5))
	await _hview("hub-kitchen", Vector3(-0.5, 0.5, 0.0), Vector3(4, 1.2, -1.0))
	await _hview("hub-bath", Vector3(2.6, 0.5, 0.3), Vector3(3.3, 1.0, 2.9))
	await _hview("hub-desk", Vector3(-2.6, 0.5, -1.4), Vector3(-3.1, 1.25, -2.8))
	note("aim", g.hub.aim)
	g.hub.interact()
	await wait(0.6)
	await shot("hub-computer")
	note("pc_open", g.hud.pc_screen.visible)
	g.start_job(0)
	await wait(4.0)
	note("after_job", [g.phase, g.in_hub])
	await shot("hub-intro")

func _hub2() -> void:
	await wait(1.0)
	g.hub_begin()
	await _hview("hub2-yard", Vector3(9, 0, -12), Vector3(0, 2, 0))
	await _hview("hub2-truckside", Vector3(10.5, 0, -8.5), Vector3(7, 1, -9.5))
	await _hview("hub2-door", Vector3(1.3, 0.5, -2.6), Vector3(-1.5, 1.2, 1.5))

func _hubup() -> void:
	await wait(1.0)
	g.hub_begin()
	var c := Career.load(); c.truck_rust = 1.0; c.money = maxi(int(c.money), 500); Career.save(c); g.money = c.money
	Mats.set_truck_rust(1.0)
	await _hview("hubup-before", Vector3(10.5, 0, -8.5), Vector3(7, 1, -9.5))
	g.open_computer()
	g.hud.pc_tab = "upgrades"; g.hud._render_pc()
	await wait(0.5)
	await shot("hubup-tab")
	g.buy_upgrade("truck")
	await wait(0.5)
	await shot("hubup-bought")
	note("rust", Career.load().truck_rust)
	g.hud.hide_computer(); g._close_computer()
	await _hview("hubup-after", Vector3(10.5, 0, -8.5), Vector3(7, 1, -9.5))
	await _hview("hubup-after2", Vector3(9, 0, -12), Vector3(6, 1, -8))
	c = Career.load(); c.truck_rust = 1.0; c.money += 400; Career.save(c)

## the cabin fixes: porch steps, door frame, yard props, chimney smoke, the fixed-up truck, the boulders
func _hubfix() -> void:
	await wait(1.0)
	g.hub_begin()
	var y0: float = g.hub.y0
	var p: Player = g.player
	# walk straight up the porch steps
	p.teleport(Vector3(1.3, g.world.H(1.3, -7.6) + 0.05, -7.6), 0.0)
	p.yaw = PI; p.pitch = -0.2
	await wait(0.4)
	Input.action_press("move_fwd")
	await wait(2.2)
	Input.action_release("move_fwd")
	await wait(0.3)
	note("steps_climbed", [snappedf(p.global_position.y - y0, 0.01), snappedf(p.global_position.z, 0.01)])
	await shot("fix-porch-top")
	await _hview("fix-steps", Vector3(3.6, 0, -8.5), Vector3(1.3, 0.2, -5.3))
	await _hview("fix-jamb-in", Vector3(1.3, 0.5, -2.75), Vector3(0.78, 1.3, -3.3))
	await _hview("fix-jamb-out", Vector3(2.4, 0.5, -4.4), Vector3(1.3, 1.4, -3.25))
	await _hview("fix-corner", Vector3(-8.0, 0, 7.5), Vector3(-5.0, 0.3, 3.9))
	await _hview("fix-tire", Vector3(-6.5, 0, -9.0), Vector3(-5.5, 0.0, -6.5))
	await _hview("fix-smoke", Vector3(9, 0, -14), Vector3(-3.0, 4.5, -0.5))
	note("smoke", [g.hub.smoke != null, g.hub.smoke.emitting if g.hub.smoke else false])
	# the truck, fixed up: no more grumbling
	Mats.set_truck_rust(0.0)
	await _hview("fix-truck", Vector3(4.5, 0, -12.5), Vector3(7, 1, -9.5))
	note("truck_fixed_aim_prompt", [g.hub.aim, g.hud.prompt.text if "prompt" in g.hud else "?"])
	Mats.set_truck_rust(1.0)
	await wait(0.3)
	note("truck_rusty_prompt", [g.hub.aim, g.hud.prompt.text if "prompt" in g.hud else "?"])
	# the nearest boulder in the woods: look at it, then stand over it
	var best = null; var bd := 1e9
	var trunks: Node = g.hub.find_child("ForestTrunks", true, false)
	for cs in trunks.get_children():
		var cy := (cs as CollisionShape3D).shape as CylinderShape3D
		if cy == null or cy.height > 4.0: continue
		var d := Vector2(cs.position.x, cs.position.z).length()
		if d > 17.0 and d < bd: bd = d; best = cs
	note("rock_found", best != null)
	if best:
		var rp: Vector3 = best.position
		var away := Vector2(rp.x, rp.z).normalized() * -4.5
		var at := Vector3(rp.x + away.x, 0, rp.z + away.y)
		p.teleport(Vector3(at.x, g.world.H(at.x, at.z) + 0.05, at.z))
		look_at_point(rp + Vector3(0, 0.3, 0))
		await wait(0.8)
		await shot("fix-rock")
		var near := Vector3(rp.x + away.x * 0.3, 0, rp.z + away.y * 0.3)
		p.teleport(Vector3(near.x, g.world.H(near.x, near.z) + 0.05, near.z))
		look_at_point(rp)
		await wait(0.8)
		await shot("fix-rock-close")
		# walk into it: it should stop you
		var from := p.global_position
		Input.action_press("move_fwd"); await wait(1.5); Input.action_release("move_fwd")
		note("rock_blocks", [snappedf(Vector2(p.global_position.x - rp.x, p.global_position.z - rp.z).length(), 0.01), snappedf((cs_radius(best)), 0.01)])

func cs_radius(cs) -> float:
	return ((cs as CollisionShape3D).shape as CylinderShape3D).radius

func _hubfix2() -> void:
	await wait(1.0)
	g.hub_begin()
	await _hview("fix2-smoke", Vector3(6, 0, -11), Vector3(-3.5, 4.5, -0.5))
	var tp: Vector3 = g.hub.spots.truck[0]
	var p: Player = g.player
	var at := tp + Vector3(1.6, 0, -0.6)
	for rust: float in [1.0, 0.0]:
		Mats.set_truck_rust(rust)
		p.teleport(Vector3(at.x, g.world.H(at.x, at.z) + 0.05, at.z))
		look_at_point(tp)
		await wait(0.6)
		note("truck_prompt_rust_%d" % int(rust), [g.hub.aim, g.hud.prompt.text])
	await shot("fix2-truck-fixed")

# ================================================================ job 2: Widow Hale's leaning maple
## notch facing away from the garage (the way it has to go), and a back cut that leaves a hinge
func _hale_cuts(hinge_left := 0.05) -> Dictionary:
	var tr: AshTree = g.tree
	var T: Dictionary = tr.T
	var gar := Vector3(g.world.garage.x, 0, g.world.garage.z)
	var away := (tr.global_position - gar); away.y = 0; away = away.normalized()
	var Fn: Vector3 = tr.global_transform.basis.inverse() * away; Fn.y = 0; Fn = Fn.normalized()
	var h := 0.55; var R := Wood.r_at(T, h); var d := 2 * R * 0.3; var a := deg_to_rad(55)
	var right := Fn.cross(Vector3.UP).normalized()
	var bot := tr.start_cut(Fn * R + Vector3(0, h, 0), -Fn, Vector3.UP); bot.s = d + 0.005; tr.cut_progress(bot)
	var ft := (-Fn * cos(a) + Vector3.DOWN * sin(a)).normalized()
	var top := tr.start_cut(Fn * R + Vector3(0, h + d * tan(a), 0), ft, ft.cross(right).normalized()); top.s = d / cos(a) + 0.005; tr.cut_progress(top)
	await wait(0.4)
	var bc := tr.start_cut(-Fn * R + Vector3(0, h + 0.03, 0), Fn, Vector3.UP); bc.s = 2 * R - d - hinge_left; tr.cut_progress(bc)
	await wait(1.0)
	return {away = away, Fn = Fn, R = R, d = d, bc = bc, right = right}

func _hale_side_view(away: Vector3) -> void:
	var tr: AshTree = g.tree
	var right := away.cross(Vector3.UP).normalized()
	var side := tr.global_position + right * 16 + away * 2
	g.player.teleport(Vector3(side.x, g.world.H(side.x, side.z) + 0.05, side.z))
	look_at_point(tr.global_position + Vector3(0, 5, 0))

func _hale() -> void:
	await wait(1.0)
	note("job", g.job.id)
	note("tree", [g.tree.def.get("sits_back", false), snappedf(g.tree.def.lean, 0.001)])
	await shot("hale-title")
	g._start()
	await wait(0.8)
	var tr: AshTree = g.tree
	var gar := Vector3(g.world.garage.x, 0, g.world.garage.z)
	var away := (tr.global_position - gar); away.y = 0; away = away.normalized()
	# the yard from the lawn: the house, the garage, and the maple leaning at it
	var v: Vector3 = tr.global_position + away * 14 + away.cross(Vector3.UP) * 10
	g.player.teleport(Vector3(v.x, g.world.H(v.x, v.z) + 0.05, v.z))
	look_at_point((tr.global_position + gar) * 0.5 + Vector3(0, 3, 0))
	await wait(1.0)
	await shot("hale-yard")
	_hale_side_view(away)
	await wait(0.8)
	await shot("hale-lean")
	# Mrs. Hale
	var hp: Vector3 = g.earl.global_position
	var cp: Vector3 = hp + (g.truck.global_position - hp).normalized() * 2.3
	g.player.teleport(Vector3(cp.x, g.world.H(cp.x, cp.z) + 0.05, cp.z))
	look_at_point(hp + Vector3(0, 1.3, 0))
	await wait(0.8)
	await shot("hale-mrs")
	g.talk_to_earl()
	await wait(0.4)
	await shot("hale-talk")
	while g.dlg != null: g.advance_dialog(); g.advance_dialog(); await wait(0.05)
	note("talked", g.objs.talk)

## with wedges: it sits back, then two tight wedges tip it over toward the notch
func _hale_wedge() -> void:
	await wait(1.0)
	g._start()
	g.objs.talk = true
	var tr: AshTree = g.tree
	var c := await _hale_cuts(0.05)
	note("after_backcut", [tr.state, tr.sat_back, snappedf(tr.A.frac if tr.A else -1.0, 0.001)])
	var back: Vector3 = tr.global_position - c.away * 1.25
	g.player.teleport(Vector3(back.x, g.world.H(back.x, back.z) + 0.05, back.z))
	g.player.tool = "wedge"
	look_at_point(tr.to_world(c.bc.e) + Vector3(0, 0.0, 0))
	g.player.pitch -= 0.05
	await wait(0.5)
	note("prompt", g.rig.prompt())
	var hits := 0
	while tr.state == "stand" and hits < 18:
		look_at_point(tr.to_world(c.bc.e))
		g.rig.use(); hits += 1
		await wait(0.35)
		if hits == 4: await shot("hale-wedge-in")
	note("wedge_hits", [hits, g.rig.wedges.size(), tr.state])
	_hale_side_view(c.away)
	await wait(1.0)
	await shot("hale-wedge-going")
	await wait(6.0)
	await shot("hale-wedge-down")
	note("grade", tr.grade)
	note("damage", g.damage)
	var st: WoodPiece = tr.stem
	var top := st.to_world(Vector3(0, tr.T.H * 0.8, 0)) - tr.global_position; top.y = 0
	note("fell_dir_vs_away_deg", snappedf(rad_to_deg(top.normalized().angle_to(c.away)), 1))

## no wedges, no rope: it sits back, you keep cutting, the hinge goes and it lands on the garage
func _hale_back() -> void:
	await wait(1.0)
	g._start()
	g.objs.talk = true
	var tr: AshTree = g.tree
	var c := await _hale_cuts(0.05)
	note("sat_back", [tr.state, tr.sat_back])
	c.bc.s += 0.06; tr.cut_progress(c.bc)
	var gar := Vector3(g.world.garage.x, 0, g.world.garage.z)
	var rt: Vector3 = c.right
	var v: Vector3 = gar + (gar - tr.global_position).normalized() * -2.0 + rt * 14
	g.player.teleport(Vector3(v.x, g.world.H(v.x, v.z) + 0.05, v.z))
	look_at_point(gar + Vector3(0, 2.5, 0))
	await wait(1.2)
	await shot("hale-back-going")
	await wait(5.0)
	await shot("hale-back-down")
	note("state", tr.state)
	note("damage", g.damage)
	note("garage_crushed", g.world.garage_crushed)

## the pull rope: tied high, truck out on the lawn the way it should go, rope taken up tight
func _hale_rope() -> void:
	await wait(1.0)
	g._start()
	g.objs.talk = true
	var tr: AshTree = g.tree
	var gar := Vector3(g.world.garage.x, 0, g.world.garage.z)
	var away := (tr.global_position - gar); away.y = 0; away = away.normalized()
	# park the truck (and chipper) out on the lawn, 24 m out along the way it should fall
	g.chipper.unhitch()
	var tp := tr.global_position + away * 24.0
	var yaw := atan2(-away.x, -away.z)
	g.truck.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(tp.x, g.world.H(tp.x, tp.z) + 0.6, tp.z))
	# let it land and settle on its brakes before rigging
	var waited := 0.0
	while not g.truck.freeze and waited < 8.0: await wait(0.25); waited += 0.25
	await wait(0.5)
	# walk up and tie the rope on
	var at := tr.global_position + away * 1.6
	g.player.teleport(Vector3(at.x, g.world.H(at.x, at.z) + 0.05, at.z))
	g.player.tool = "rope"
	look_at_point(tr.global_position + Vector3(0, 1.6, 0))
	await wait(0.3)
	note("rope_prompt_tree", g.rig.prompt())
	g.rig.use()
	var hp: Vector3 = g.truck.hitch_world()
	g.player.teleport(Vector3(hp.x, g.world.H(hp.x, hp.z) + 0.05, hp.z) + away * 1.0)
	await wait(0.3)
	note("rope_prompt_truck", g.rig.prompt())
	g.rig.use()
	# take up the slack (as if you'd eased the truck out a couple of metres)
	g.rig.rope_len -= 1.6
	await wait(1.0)
	var v: Vector3 = tr.global_position + away * 10 + away.cross(Vector3.UP) * 9
	g.player.teleport(Vector3(v.x, g.world.H(v.x, v.z) + 0.05, v.z))
	look_at_point(tr.global_position + away * 6 + Vector3(0, 4, 0))
	await wait(1.5)
	note("rope", [g.rig.rope, snappedf(g.rig.rope_stretch, 0.01), snappedf(tr.push.length(), 0.001)])
	await shot("hale-rope")
	var c := await _hale_cuts(0.05)
	await wait(1.0)
	await shot("hale-rope-going")
	await wait(6.0)
	note("state", tr.state)
	note("damage", g.damage)
	var st: WoodPiece = tr.stem
	var top := st.to_world(Vector3(0, tr.T.H * 0.8, 0)) - tr.global_position; top.y = 0
	note("fell_dir_vs_away_deg", snappedf(rad_to_deg(top.normalized().angle_to(away)), 1))
	await shot("hale-rope-down")

## the pull rope the way you'd really do it: tie on, hook up, drive out until it's bar-tight, park, cut
func _hale_drive() -> void:
	await wait(1.0)
	g._start()
	g.objs.talk = true
	var tr: AshTree = g.tree
	var gar := Vector3(g.world.garage.x, 0, g.world.garage.z)
	var away := (tr.global_position - gar); away.y = 0; away = away.normalized()
	g.chipper.unhitch()
	# truck parked out on the lawn, nose pointing away from the tree
	var tp := tr.global_position + away * 15.0
	var yaw := atan2(away.x, away.z)
	g.truck.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(tp.x, g.world.H(tp.x, tp.z) + 0.4, tp.z))
	await wait(1.5)
	var at := tr.global_position + away * 1.6
	g.player.teleport(Vector3(at.x, g.world.H(at.x, at.z) + 0.05, at.z))
	g.player.tool = "rope"
	look_at_point(tr.global_position + Vector3(0, 1.6, 0))
	await wait(0.3)
	g.rig.use()
	var hp: Vector3 = g.truck.hitch_world()
	g.player.teleport(Vector3(hp.x, g.world.H(hp.x, hp.z) + 0.05, hp.z) - away * 1.0)
	await wait(0.3)
	g.rig.use()
	note("rigged", [g.rig.rope, snappedf(g.rig.rope_stretch, 0.01)])
	g.enter_truck()
	await wait(0.5)
	var held := 0.0
	Input.action_press("move_fwd")
	while g.rig.rope_stretch < 1.05 and held < 12.0 and g.rig.rope == "rigged":
		await wait(0.1); held += 0.1
	Input.action_release("move_fwd")
	Input.action_press("jump")
	note("drove", [snappedf(held, 0.1), snappedf(g.rig.rope_stretch, 0.01), g.hud.prompt.text])
	await shot("hale-drive-tight")
	await wait(0.6)
	Input.action_release("jump")
	g.exit_truck()
	await wait(2.0)
	note("parked", [g.rig.rope, snappedf(g.rig.rope_stretch, 0.01), g.truck.freeze, snappedf(tr.push.length(), 0.001)])
	var c := await _hale_cuts(0.05)
	_hale_side_view(away)
	await wait(1.5)
	await shot("hale-drive-going")
	await wait(6.0)
	note("state", tr.state)
	note("damage", g.damage)
	if is_instance_valid(tr.stem):
		var top := tr.stem.to_world(Vector3(0, tr.T.H * 0.8, 0)) - tr.global_position; top.y = 0
		note("fell_dir_vs_away_deg", snappedf(rad_to_deg(top.normalized().angle_to(away)), 1))
	await shot("hale-drive-down")

## the computer: both jobs listed (the maple locked until you've done one), the new gear on the upgrades tab
func _hubjobs() -> void:
	await wait(1.0)
	g.hub_begin()
	var c := Career.load(); c.jobs = 1; c.money = 700; c.wedges = false; c.rope = false; Career.save(c); g.money = c.money
	g.open_computer()
	await wait(0.5)
	await shot("pc-jobs")
	g.hud.pc_tab = "upgrades"; g.hud._render_pc()
	await wait(0.4)
	await shot("pc-upgrades")
	note("hale_open_without_wedges", Jobs.board(1)[1].open)
	g.start_job(1)
	await wait(0.3)
	note("started_without_wedges", g.in_hub)
	g.buy_upgrade("wedges")
	await wait(0.3)
	note("bought_wedges", [Career.load().wedges, Career.load().money])
	note("hale_open_with_wedges", Jobs.board(1)[1].open)
	await shot("pc-bought")
	g.hud.pc_tab = "jobs"; g.hud._render_pc()
	await wait(0.3)
	await shot("pc-jobs-after")
	c = Career.load(); c.jobs = 0; c.money = 0; c.wedges = false; c.rope = false; Career.save(c)


## skip to payday (as if limbed, chipped and piled) and read the pay off the summary
func _hale_payday(tag: String) -> void:
	g.objs.felled = true; g.objs.limbed = true; g.objs.stacked = true
	g.payday()
	var n := 0
	while g.dlg != null and n < 40: g.advance_dialog(); g.advance_dialog(); n += 1; await wait(0.05)
	await wait(1.0)
	var rows := []
	for r in g.hud.sum_rows.get_children():
		var t := []
		for l in r.get_children(): if l is Label: t.append((l as Label).text)
		rows.append(" ".join(t))
	note("pay_" + tag, rows)
	note("bank_" + tag, g.money)
	await shot("hale-pay-" + tag)

func _hale_drive_pay() -> void:
	await _hale_drive()
	await _hale_payday("clean")

func _hale_back_pay() -> void:
	await _hale_back()
	await _hale_payday("garage")

func _halelook() -> void:
	await wait(1.0)
	await shot("hl-title")
	g._start()
	var h: Dictionary = g.world.house
	var L: Dictionary = g.world.lake
	var front: float = h.z - h.d / 2
	await _view("hl-front", Vector3(h.x + 6, 0, front - 14), Vector3(h.x, g.world.H(h.x, h.z) + 2.5, h.z))
	await _view("hl-porch", Vector3(h.x + h.w * 0.18 - 2.5, 0, front - 6), Vector3(h.x + h.w * 0.18, g.world.H(h.x, h.z) + 0.8, front - 2.5))
	var dx: float = g.world._dock_x()
	var sz: float = g.world._shore_z(dx)
	await _view("hl-lawn", Vector3(h.x, 0, h.z + 10), Vector3(dx, float(L.y) + 1.0, sz + 15))
	await _view("hl-dock", Vector3(dx + 4, 0, sz - 7), Vector3(dx, float(L.y) + 0.5, sz + 6))
	await _view("hl-back", Vector3(dx - 6, 0, sz - 3), Vector3(h.x, g.world.H(h.x, h.z) + 2.0, h.z))
	var t: Vector3 = g.tree.global_position
	await _view("hl-tree", t + Vector3(g.world.s * 14, 0, -6), t + Vector3(0, 6, 0))

## Mrs. Hale's trailer: throw rounds in, everything counts as loaded, tarp it, get paid
func _haletrailer() -> void:
	await wait(1.0)
	g._start()
	g.objs.talk = true
	var tr: Trailer = g.trailer
	note("trailer", tr != null)
	var bxf := tr.bed_xf()
	var side := bxf * Vector3(2.6, 0, -1.7)
	g.player.teleport(Vector3(side.x, g.world.H(side.x, side.z) + 0.05, side.z))
	look_at_point(bxf * Vector3(0, 1.0, -1.7))
	await wait(0.5)
	await shot("ht-empty")
	var rs := _make_rounds(6)
	await wait(1.5)
	var inn := 0
	for r: WoodPiece in rs:
		g.player.teleport(Vector3(side.x, g.world.H(side.x, side.z) + 0.05, side.z))
		look_at_point(bxf * Vector3(0, 1.0, -1.7))
		await wait(0.2)
		g.haul.pick_up(r)
		await wait(0.4)
		g.haul.throw_one()
		await wait(1.6)
		if tr.in_bed(r.center_world()): inn += 1
	note("in_trailer", [inn, rs.size()])
	g.objs.felled = true
	g.update_objectives()
	note("stacked", [g.objs.stacked, g.objs.tarped, g.done_frac])
	await shot("ht-loaded")
	g.aim = g.compute_aim()
	note("aim", g.aim.get("kind", ""))
	g.tarp_trailer()
	await wait(2.2)
	note("tarped", g.objs.tarped)
	await shot("ht-tarped")
	var vp := bxf * Vector3(3.5, 0, -5.0)
	g.player.teleport(Vector3(vp.x, g.world.H(vp.x, vp.z) + 0.05, vp.z))
	look_at_point(bxf * Vector3(0, 1.0, -1.7))
	await wait(0.6)
	await shot("ht-tarped2")

## splitting firewood at the cabin: take rounds from the trailer, split them, tie bundles
func _hubchop() -> void:
	var c0 := Career.load()
	var c := c0.duplicate(); c.trailer = true; c.rounds = 4; c.bundles = 0; Career.save(c)
	g.enter_hub()
	await wait(1.0)
	g.hub_begin()
	await wait(0.5)
	var ws: WoodSplit = g.hub.split
	var tr: Trailer = g.hub.get_node("Trailer")
	var m0: int = Career.load().money
	var swings := 0; var splits_done := 0
	for rnd in range(3):
		var tp := tr.bed_xf() * Vector3(-2.2, 0, -1.7)
		g.player.teleport(Vector3(tp.x, g.world.H(tp.x, tp.z) + 0.05, tp.z))
		look_at_point(tr.bed_xf() * Vector3(0, 1.2, -1.7))
		await wait(0.3)
		if rnd == 0: await shot("chop-trailer")
		note("aim_trailer", g.hub.aim)
		g.hub.interact()
		await wait(0.3)
		var bt: Vector3 = g.hub.block_top
		var sp := bt + Vector3(0, 0, -1.2)
		g.player.teleport(Vector3(sp.x, g.world.H(sp.x, sp.z) + 0.05, sp.z))
		look_at_point(bt + Vector3(0, 0.3, 0))
		await wait(0.3)
		if rnd == 0: await shot("chop-carry")
		g.hub.interact()
		await wait(0.4)
		note("active", [ws.active, ws.pieces.size()])
		var guard := 0
		while not ws.pieces.is_empty() and guard < 30:
			guard += 1
			# aim at the middle of the first piece on the block
			var pc: Dictionary = ws.pieces[0]
			var mid: float = (pc.a0 + pc.a1) / 2.0
			var full: bool = pc.a1 - pc.a0 > TAU - 0.01
			var off: Vector2 = pc.off
			var aimp: Vector3 = ws.block_c + Vector3(off.x, pc.h, off.y) + (Vector3.ZERO if full else Vector3(cos(mid), 0, sin(mid)) * pc.R * 0.5)
			look_at_point(aimp)
			await wait(0.05)
			ws.press()
			await wait(0.42 if guard % 3 else 0.7)
			if rnd == 0 and guard == 1: await shot("chop-windup")
			var n0 := ws.pieces.size() + ws.pile.size()
			ws.release()
			await wait(0.13)
			if rnd == 0 and guard <= 2: await shot("chop-hit%d" % guard)
			await wait(0.6)
			swings += 1
			if ws.pieces.size() + ws.pile.size() > n0 or ws.pile.size() == 0: splits_done += 1
		note("round_done", [rnd, guard, ws.pile.size()])
		ws.stop_chopping()
		await wait(0.3)
	await shot("chop-pile")
	var c1 := Career.load()
	note("result", {swings = swings, bundles = c1.bundles, money_gained = int(c1.money) - m0, rounds_left = c1.rounds})
	var rk: Vector3 = g.hub.spots.rack[0]
	g.player.teleport(Vector3(rk.x - 3.0, g.world.H(rk.x - 3.0, rk.z) + 0.05, rk.z + 1.0))
	look_at_point(rk)
	await wait(0.5)
	await shot("chop-rack")
	Career.save(c0)

## the cabin close up: door jambs from inside both sides, under the windows, along the floor, the steps
func _hubcabin() -> void:
	await wait(1.0)
	g.hub_begin()
	await _hview("cl-jamb-left", Vector3(-0.6, 0.5, -2.55), Vector3(0.79, 1.4, -3.25))
	await _hview("cl-jamb-right", Vector3(3.2, 0.5, -2.55), Vector3(1.81, 1.4, -3.25))
	await _hview("cl-jamb-out", Vector3(2.6, 0.5, -4.6), Vector3(1.81, 1.4, -3.25))
	await _hview("cl-win-left", Vector3(-2.4, 0.5, -1.2), Vector3(-4.0, 1.0, -2.4))
	await _hview("cl-win-front", Vector3(-1.0, 0.5, -1.6), Vector3(-1.0, 0.9, -3.25))
	await _hview("cl-floor-side", Vector3(2.0, 0.5, 0.5), Vector3(4.0, 0.5, -1.5))
	await _hview("cl-steps", Vector3(1.3, 0, -8.0), Vector3(1.3, 0.2, -5.3))


## the lake house: the rowboat (dry inside), the lake (nothing growing under it), the porch roof, and
## walking straight up the porch steps
func _hale_lake() -> void:
	await wait(1.0)
	g._start()
	var w: WorldGen = g.world
	var dx: float = w._dock_x(); var zs: float = w._shore_z(dx) - 3.0; var ze := zs + 13.0
	var deck: float = float(w.lake.y) + 0.55
	var p: Player = g.player
	# on the dock, looking down into the boat
	p.teleport(Vector3(dx - 0.4, deck + 0.05, ze - 3.6))
	look_at_point(Vector3(dx - 1.9, float(w.lake.y), ze - 3.5))
	await wait(1.0)
	await shot("lake-boat")
	# out along the dock, looking over the water
	p.teleport(Vector3(dx, deck + 0.05, ze - 0.5))
	look_at_point(Vector3(dx + 6.0, float(w.lake.y) - 1.0, ze + 8.0))
	await wait(1.0)
	await shot("lake-water")
	# the house front and its porch roof
	var h: Dictionary = w.house
	var pdx: float = h.x + h.w * 0.18
	var front: float = h.z - h.d / 2
	var at := Vector3(pdx, 0, front - 8.0)
	p.teleport(Vector3(at.x, w.H(at.x, at.z) + 0.05, at.z))
	look_at_point(Vector3(pdx, w.H(pdx, front) + 2.2, front - 1.0))
	await wait(1.0)
	await shot("lake-porch")
	# walk straight at the porch steps and up them, no jumping
	at = Vector3(pdx, 0, front - 5.0)
	p.teleport(Vector3(at.x, w.H(at.x, at.z) + 0.05, at.z))
	p.yaw = PI; p.pitch = -0.2
	var y_start := p.global_position.y
	Input.action_press("move_fwd"); await wait(3.0); Input.action_release("move_fwd")
	note("porch_climb", [snappedf(p.global_position.y - y_start, 0.01), snappedf(p.global_position.z - front, 0.01)])
	await shot("lake-porch-up")

## walk straight up the cabin's porch steps from the yard, no jumping
func _hubsteps() -> void:
	await wait(1.0)
	g.hub_begin()
	var y0: float = g.hub.y0
	var p: Player = g.player
	for x: float in [1.3, 0.95, 1.65]:
		p.teleport(Vector3(x, g.world.H(x, -7.6) + 0.05, -7.6), PI)
		p.yaw = PI; p.pitch = -0.2
		await wait(0.4)
		Input.action_press("move_fwd"); await wait(2.4); Input.action_release("move_fwd")
		await wait(0.2)
		note("cabin_steps_x%.2f" % x, [snappedf(p.global_position.y - y0, 0.01), snappedf(p.global_position.z, 0.01)])

## Walter's trailer, towed: load and tarp it, hitch it to the truck, hook the chipper on the back of the
## trailer, drive off with the lot, then jam the truck into the porch and unstick it
func _haletow() -> void:
	await wait(1.0)
	g._start()
	g.objs.talk = true
	var tr: Trailer = g.trailer
	var bxf := tr.bed_xf()
	var mid := (Trailer.Z0 + Trailer.Z1) / 2.0
	var side := bxf * Vector3(2.6, 0, mid)
	var rs := _make_rounds(10)
	await wait(1.5)
	for r: WoodPiece in rs:
		g.player.teleport(Vector3(side.x, g.world.H(side.x, side.z) + 0.05, side.z))
		look_at_point(bxf * Vector3(0, 1.0, mid))
		await wait(0.2)
		g.haul.pick_up(r)
		await wait(0.4)
		g.haul.throw_one()
		await wait(1.4)
	var inn := rs.filter(func(r): return tr.in_bed(r.center_world())).size()
	note("in_trailer", [inn, rs.size()])
	g.objs.felled = true
	g.update_objectives()
	g.tarp_trailer()
	await wait(2.2)
	var vp := bxf * Vector3(3.6, 0, mid - 3.5)
	g.player.teleport(Vector3(vp.x, g.world.H(vp.x, vp.z) + 0.05, vp.z))
	look_at_point(bxf * Vector3(0, 1.2, mid))
	await wait(0.8)
	await shot("tow-tarped")
	# the chipper comes off the truck; the truck backs up to the trailer's tongue
	g.chipper.unhitch()
	await wait(0.5)
	var tb := tr.global_transform.basis
	var tp: Vector3 = tr.coupler_world() - tb * Models.HITCH + tb.z * 1.2
	g.truck.global_transform = Transform3D(tb, Vector3(tp.x, g.world.H(tp.x, tp.z) + 0.3, tp.z))
	await wait(1.5)
	var cp := tr.coupler_world() + tb.x * 1.4
	g.player.teleport(Vector3(cp.x, g.world.H(cp.x, cp.z) + 0.05, cp.z))
	look_at_point(tr.coupler_world())
	await wait(0.3)
	g.aim = g.compute_aim()
	note("coupler_aim", [g.aim.get("kind", ""), g.hud.prompt.text])
	g.trailer_hitch_action()
	await wait(0.6)
	note("trailer_mode", tr.mode)
	# walk the chipper's tongue round to the ball on the back of the trailer and drop it on
	var ch: Chipper = g.chipper
	var ball := tr.hitch_world()
	# pick up the tongue, then walk round behind the trailer with it, facing the ball
	var cpw := ch.coupler_world() + Vector3(0.0, 0, 1.0)
	g.player.teleport(Vector3(cpw.x, g.world.H(cpw.x, cpw.z) + 0.05, cpw.z))
	look_at_point(ch.coupler_world())
	await wait(0.2)
	g.aim = g.compute_aim()
	g.hitch_action()
	for k in range(60):
		ball = tr.hitch_world()
		var back_dir: Vector3 = -(tr.global_transform.basis.z); back_dir.y = 0; back_dir = back_dir.normalized()
		var stand := ball + back_dir * 0.9
		g.player.teleport(Vector3(stand.x, g.world.H(stand.x, stand.z) + 0.05, stand.z))
		g.player.yaw = atan2(back_dir.x, back_dir.z)
		await wait(0.25)
		if ch.nearest_hitch() == tr: break
	ball = tr.hitch_world()
	note("tongue", [ch.mode, snappedf(ch.coupler_world().distance_to(ball), 0.01)])
	note("chipper_nearest", ch.nearest_hitch() == tr)
	if ch.nearest_hitch() == tr: g.interact()
	else: ch.hitch_now(tr)
	await wait(1.0)
	var rv := tr.global_transform * Vector3(-7.0, 0, Trailer.Z0 - 2.0)
	g.player.teleport(Vector3(rv.x, g.world.H(rv.x, rv.z) + 0.05, rv.z))
	look_at_point(tr.global_transform * Vector3(0, 1.0, Trailer.Z0))
	await wait(0.8)
	await shot("tow-hitched")
	# drive off with the lot
	note("before_drive", [ch.mode, ch.freeze, ch.brake, ch.jack_shape.disabled, tr.mode, tr.jack_shape.disabled, tr.freeze, ch.tow == tr, g.truck.freeze])
	var start: Vector3 = g.truck.global_position
	g.enter_truck()
	await wait(0.4)
	Input.action_press("move_fwd")
	var top_speed := 0.0
	for k in range(16):
		await wait(0.25); top_speed = maxf(top_speed, g.truck.speed_mph())
	Input.action_release("move_fwd")
	note("top_mph", snappedf(top_speed, 0.1))
	Input.action_press("jump"); await wait(1.5); Input.action_release("jump")
	note("towed", [snappedf(g.truck.global_position.distance_to(start), 0.1),
		snappedf(tr.coupler_world().distance_to(g.truck.hitch_world()), 0.01),
		snappedf(ch.coupler_world().distance_to(tr.hitch_world()), 0.01),
		rs.filter(func(r): return tr.in_bed(r.center_world())).size()])
	g.truck.chase = true; g.truck._set_cam()
	await wait(0.6)
	await shot("tow-driving")
	g.truck.chase = false
	g.exit_truck()
	await wait(0.5)
	# jam it into the porch, then unstick it
	var h: Dictionary = g.world.house
	var porch := Vector3(h.x + h.w * 0.18, 0, h.z - h.d / 2 - 1.2)
	g.truck.freeze = false
	g.truck.global_transform = Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -0.25), Vector3(porch.x, g.world.H(porch.x, porch.z) + 0.9, porch.z))
	await wait(1.0)
	g.unstick_truck()
	await wait(2.0)
	note("unstuck", [snappedf(g.truck.global_transform.basis.y.y, 0.01), snappedf(Vector2(g.truck.global_position.x - porch.x, g.truck.global_position.z - porch.z).length(), 0.1),
		snappedf(tr.coupler_world().distance_to(g.truck.hitch_world()), 0.01), rs.filter(func(r): return tr.in_bed(r.center_world())).size()])
	var uv: Vector3 = g.truck.global_position + Vector3(8, 0, 6)
	g.player.teleport(Vector3(uv.x, g.world.H(uv.x, uv.z) + 0.05, uv.z))
	look_at_point(g.truck.global_position + Vector3(0, 1, 0))
	await wait(0.6)
	await shot("tow-unstuck")

## two cuts from the top and from underneath, in the same spot, that don't quite meet: a kick snaps it
func _kicksplit() -> void:
	await wait(1.0)
	g._start()
	g.objs.talk = true
	await _fell_tree_quick()
	var st: WoodPiece = g.tree.stem
	var yy := lerpf(st.y0, st.y1, 0.25)
	var R := Wood.r_at(st.T, yy)
	var up: Vector3 = st.global_transform.basis.inverse() * Vector3.UP; up.y = 0; up = up.normalized()
	var top = g.saw._start_cut({kind = "piece", piece = st, part = {trunk = true}, p = st.to_world(Vector3(0, yy, 0) + up * (R + 0.05)), fl = -up, nl = Vector3.UP})
	top.s = top.exit * 0.5; Wood.update_kerf(top.node, top)
	var bot = g.saw._start_cut({kind = "piece", piece = st, part = {trunk = true}, p = st.to_world(Vector3(0, yy, 0) - up * (R + 0.05)), fl = up, nl = Vector3.UP})
	bot.s = bot.exit * 0.38; Wood.update_kerf(bot.node, bot)
	var before: int = g.pieces().size()
	note("cuts", [top != null, bot != null, snappedf(top.exit, 0.01) if top else -1.0, snappedf(bot.exit, 0.01) if bot else -1.0, st.ops.filter(func(o): return o.type == "kerf").size()])
	var at := st.to_world(Vector3(0, yy, 0))
	var side: Vector3 = (st.global_transform.basis * Vector3(1, 0, 0)).normalized()
	if absf(side.y) > 0.7: side = (st.global_transform.basis * Vector3(0, 0, 1)).normalized()
	side.y = 0; side = side.normalized()
	var stand := at + side * 1.0
	g.player.teleport(Vector3(stand.x, g.world.H(stand.x, stand.z) + 0.05, stand.z))
	look_at_point(at)
	await wait(0.4)
	await shot("kick-before")
	var e: Vector3 = g.player.eye(); var d: Vector3 = g.player.aim_dir()
	if d.y > -0.15: d = Vector3(d.x, -0.15, d.z).normalized()
	var rq := PhysicsRayQueryParameters3D.create(e, e + d * 1.9); rq.collision_mask = 8 | 64
	var hit: Dictionary = g.get_world_3d().direct_space_state.intersect_ray(rq)
	note("kick_ray", [not hit.is_empty(), hit.get("collider") == st if not hit.is_empty() else false])
	g.haul.kick()
	await wait(1.0)
	note("kick_split", [before, g.pieces().size()])
	await shot("kick-after")

## the sledge swing: frames through one blow onto a wedge in the back cut
func _hale_hammer() -> void:
	await wait(1.0)
	g._start()
	g.objs.talk = true
	var tr: AshTree = g.tree
	var c := await _hale_cuts(0.05)
	var back: Vector3 = tr.global_position - c.away * 1.15
	g.player.teleport(Vector3(back.x, g.world.H(back.x, back.z) + 0.05, back.z))
	g.player.tool = "wedge"
	look_at_point(tr.to_world(c.bc.e))
	await wait(0.5)
	g.rig.use()
	await wait(0.6)
	g.rig.use()
	for k in range(5):
		await wait(0.055)
		await shot("hammer-%d" % k)

## the firewood stand by the track, with a few bundles on it
func _hubstand() -> void:
	await wait(1.0)
	var c := Career.load(); var b0 := int(c.get("bundles", 0)); c.bundles = 7; Career.save(c)
	g.hub_begin()
	g.hub.split._refresh_rack()
	var rk := Vector3(8.6, 0, -27.0)
	var B := Basis(Vector3.UP, PI / 2)
	var front := rk + B * Vector3(0.6, 0, -3.2)
	g.player.teleport(Vector3(front.x, g.world.H(front.x, front.z) + 0.05, front.z))
	look_at_point(Vector3(rk.x, g.world.H(rk.x, rk.z) + 0.9, rk.z))
	await wait(1.2)
	await shot("stand-front")
	var near := rk + B * Vector3(-0.3, 0, -1.5)
	g.player.teleport(Vector3(near.x, g.world.H(near.x, near.z) + 0.05, near.z))
	look_at_point(Vector3(rk.x, g.world.H(rk.x, rk.z) + 0.75, rk.z))
	await wait(0.8)
	await shot("stand-close")
	c = Career.load(); c.bundles = b0; Career.save(c)

## a quick look at the trailer: rounds dropped straight in, tarped, hitched up with the chipper behind
func _hale_trailer_look() -> void:
	await wait(0.5)
	g._start()
	var tr: Trailer = g.trailer
	var rs := _make_rounds(12)
	var bxf := tr.bed_xf()
	for k in range(rs.size()):
		var r: WoodPiece = rs[k]
		var p := bxf * Vector3(-0.5 + (k % 3) * 0.5, 1.0 + (k / 9) * 0.35, Trailer.Z1 - 0.45 - ((k / 3) % 3) * 1.2)
		r.global_transform = Transform3D(r.global_transform.basis, p - (r.center_world() - r.global_position))
		r.linear_velocity = Vector3.ZERO
	await wait(1.5)
	g.objs.felled = true; g.update_objectives()
	g.tarp_trailer()
	await wait(1.8)
	var mid := (Trailer.Z0 + Trailer.Z1) / 2.0
	var v := bxf * Vector3(4.0, 0, mid - 3.0)
	g.player.teleport(Vector3(v.x, g.world.H(v.x, v.z) + 0.05, v.z))
	look_at_point(bxf * Vector3(0, 1.1, mid))
	await wait(0.5)
	await shot("tl-tarped")
	g.chipper.unhitch()
	var tb := tr.global_transform.basis
	var tp: Vector3 = tr.coupler_world() - tb * Models.HITCH + tb.z * 1.2
	g.truck.global_transform = Transform3D(tb, Vector3(tp.x, g.world.H(tp.x, tp.z) + 0.3, tp.z))
	await wait(1.0)
	tr.hitch_to(g.truck, g.trailer_cargo())
	g.chipper.hitch_now(tr)
	await wait(1.0)
	var sv := tr.global_transform * Vector3(-7.5, 0, (Trailer.Z0 + Trailer.Z1) / 2.0 - 1.0)
	g.player.teleport(Vector3(sv.x, g.world.H(sv.x, sv.z) + 0.05, sv.z))
	look_at_point(tr.global_transform * Vector3(0, 1.0, Trailer.Z0 + 0.5))
	await wait(0.5)
	await shot("tl-train")

## a foggy morning: the timelapse camera should still see the yard (and you in it)
func _fogtl() -> void:
	await wait(0.5)
	g.weather.force("fog")
	g._start()
	await wait(2.0)
	g.timelapse.interval = 0.3
	await wait(1.5)
	await shot("fog-ground")
	var f: Array = g.timelapse.frames
	note("tl_frames", f.size())
	if f.size() > 0: (f[f.size() - 1] as Image).save_png(out_dir + "/fog-timelapse.png")
	note("cam_env", [g.timelapse.cam.environment != null, g.timelapse.cam.environment.fog_enabled if g.timelapse.cam.environment else true])


## job 3: Gus's dock logs. Wade out, rope a log, hook it to the truck, drive off and drag it up the beach
func _dock() -> void:
	await wait(1.0)
	g._start()
	g.objs.talk = true
	note("logs", [g.lake_logs.size(), g.logs_in_water()])
	var lg: WoodPiece = g.lake_logs[0]
	await wait(2.0)
	var c := lg.center_world()
	note("log_float", [snappedf(c.y - float(g.world.lake.y), 0.01), snappedf(float(g.world.lake.y) - g.world.H(c.x, c.z), 0.01)])
	# the view from the beach
	var sz: float = g.world._shore_z(c.x)
	var beach := Vector3(c.x - 3.0, 0, sz - 4.0)
	g.player.teleport(Vector3(beach.x, g.world.H(beach.x, beach.z) + 0.05, beach.z))
	look_at_point(c)
	await wait(0.8)
	await shot("dock-beach")
	# wade out to it
	var ax: Vector3 = lg.global_transform.basis.y; ax.y = 0; ax = ax.normalized()
	var side := ax.cross(Vector3.UP).normalized()
	if side.z > 0: side = -side                                         # the shore side of it
	var stand := c + side * 1.2
	g.player.teleport(Vector3(stand.x, g.world.H(stand.x, stand.z) + 0.05, stand.z))
	look_at_point(c)
	await wait(0.6)
	note("wade", snappedf(g.player.wade, 0.01))
	g.player.tool = "rope"
	note("rope_prompt", g.rig.prompt())
	g.rig.use()
	await shot("dock-tie")
	# park the truck up the lawn facing away from the lake, hook up
	var tp := Vector3(c.x, 0, sz - 9.0)
	g.chipper.unhitch()
	g.truck.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(tp.x, g.world.H(tp.x, tp.z) + 0.3, tp.z))
	await wait(1.5)
	var hp: Vector3 = g.truck.hitch_world()
	g.player.teleport(Vector3(hp.x, g.world.H(hp.x, hp.z) + 0.05, hp.z + 0.8))
	await wait(0.3)
	g.rig.use()
	note("rigged", [g.rig.rope, g.rig.rope_piece == lg])
	g.enter_truck()
	await wait(0.4)
	Input.action_press("move_fwd")
	for k in range(40):
		await wait(0.25)
		if g.logs_in_water() < 4: break
	Input.action_release("move_fwd")
	Input.action_press("jump"); await wait(1.0); Input.action_release("jump")
	g.exit_truck()
	c = lg.center_world()
	note("dragged", [g.logs_in_water(), snappedf(g.world.lake_d(c.x, c.z), 0.1), g.rig.rope])
	var v := c + Vector3(5, 0, -3)
	g.player.teleport(Vector3(v.x, g.world.H(v.x, v.z) + 0.05, v.z))
	look_at_point(c)
	await wait(0.6)
	await shot("dock-out")

## Gus's rod at his lake: cast, strike on the bite, fight it in, keep it
func _dock_fish() -> void:
	await wait(1.0)
	var c := Career.load(); c.rod = true; Career.save(c)
	g._start()
	var lg: WoodPiece = g.lake_logs[0]
	var lc := lg.center_world()
	var sz: float = g.world._shore_z(lc.x + 12.0)
	var beach := Vector3(lc.x + 12.0, 0, sz - 1.5)
	g.player.teleport(Vector3(beach.x, g.world.H(beach.x, beach.z) + 0.05, beach.z))
	look_at_point(Vector3(beach.x, g.world.H(beach.x, beach.z) + 1.0, beach.z + 20.0))
	await wait(0.4)
	g.equip("rod")
	note("near", g.fishing.water_near())
	await wait(3.0)
	note("music", [g.fishing.music.playing, snappedf(g.fishing.music.volume_db, 0.1)])
	g.fishing.press(true); await wait(0.9); g.fishing.press(false)
	await wait(1.2)
	note("cast", [g.fishing.state, snappedf(g.fishing.lure.distance_to(g.player.global_position), 0.1)])
	await shot("fish-wait")
	var caught := 0; var lost := 0; var dry := 0
	for round in range(4):
		var tw := 0.0
		while g.fishing.state == "wait" and tw < 40.0:
			if not g.fishing.fish.is_empty() and g.fishing.fish.phase == "bite":
				g.fishing.wheel_down(); break
			if tw > 3.0 and fmod(tw, 2.0) < 0.1: g.fishing.alt(true); g.fishing.alt(false)       # jig now and then
			await wait(0.1); tw += 0.1
		if g.fishing.state != "fight": note("nobite%d" % round, g.fishing.state); continue
		await shot("fish-fight")
		# keep the tension in the middle by looking at the fish and pulling the rod up off it
		var off := 0.4; var tf := 0.0; var tmax := 0.0
		while g.fishing.state == "fight" and tf < 90.0:
			if g.fishing.tension > 0.8: off = maxf(0.0, off - 0.05)
			elif g.fishing.tension < 0.45: off = minf(1.2, off + 0.05)
			var fp: Vector3 = g.fishing._fish_world()
			if g.fishing.water_at(fp) == INF: dry += 1
			look_at_point(fp)
			g.player.pitch = clampf(g.player.pitch + off, -1.5, 1.45)
			g.fishing.reel_held = g.fishing.tension < 0.75
			tmax = maxf(tmax, g.fishing.tension)
			await wait(0.1); tf += 0.1
		if g.fishing.state == "landed":
			caught += 1
			note("fish%d" % round, [g.fishing.fish.name, snappedf(g.fishing.fish.len, 0.1), snappedf(tf, 0.1), snappedf(tmax, 0.01)])
			await shot("fish-card")
			g.fishing.press(true)
		else: lost += 1; note("lost%d" % round, [g.fishing.msg, snappedf(tf, 0.1)])
		g.fishing.press(true); await wait(0.9); g.fishing.press(false); await wait(1.2)
	note("result", [caught, lost, "dry", dry])

## rain stops at the cabin door
func _hubrain() -> void:
	await wait(1.0)
	g.weather.force("rain")
	var h: Hub = g.hub
	var inside := h.to_global(Vector3(0, h.y0 + Hub.F + 0.05, 0))
	g.player.teleport(inside)
	g.player.cam.make_current()
	await wait(1.0)
	note("dbg", [h.global_position, h.y0, g.player.global_position, g.get_viewport().get_camera_3d().global_position, g.get_viewport().get_camera_3d() == g.player.cam])
	note("inside", [h.indoors(g.get_viewport().get_camera_3d().global_position), g.weather.rain_fx.emitting])
	g.player.teleport(h.to_global(Vector3(0, 0, -Hub.HZ - 6.0)) + Vector3(0, g.world.H(0, -Hub.HZ - 6.0) + 0.05, 0))
	await wait(1.0)
	note("outside", [h.indoors(g.get_viewport().get_camera_3d().global_position), g.weather.rain_fx.emitting])

## you're in the truck in the chase view
func _driver() -> void:
	await wait(1.0)
	g._start()

	g.enter_truck()
	await wait(0.3)
	g.truck.chase = true; g.truck._set_cam()
	g.truck.look_yaw = 2.2
	await wait(1.0)
	await shot("driver-a")
	g.truck.look_yaw = -1.2
	await wait(0.6)
	await shot("driver-b")
