## Two-player checks: run a host and a guest side by side on one machine (two processes):
##   godot --headless --path . -- --test=net_host [--job=0]
##   godot --headless --path . -- --test=net_guest [--job=0]
## The guest does the work (talks to the client, fells, limbs, bucks, carries, throws, chips, drives)
## and both report what their copy of the job looks like, to compare.
extends "res://scripts/tests.gd"

var job_idx := 0

func _arg_job() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--job="): job_idx = int(a.substr(6))

func until(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while t < secs:
		if cond.call(): return true
		await wait(0.1); t += 0.1
	return false

func _summary(tag: String) -> void:
	var ps: Array = g.pieces()
	var m := 0.0; var kinds := {}
	for b in ps:
		m += b.mass
		kinds[b.kind] = int(kinds.get(b.kind, 0)) + 1
	note(tag + "_pieces", [ps.size(), snappedf(m, 0.1), kinds])

# ---------------------------------------------------------------- the host
func _net_host() -> void:
	_arg_job()
	if Engine.get_meta("nt_stage", 1) == 2:
		# back at the cabin after the job (the scene was reloaded): is the crew still together?
		await wait(2.0)
		note("host_back_home", [g.in_hub, Net.role, Net.roster.size()])
		await until(func(): return Net.roster.size() < 2, 20.0)
		return
	await wait(1.0)
	g.hub_begin()
	note("host_err", Net.host())
	note("guest_joined", await until(func(): return Net.roster.size() >= 2, 30.0))
	await wait(1.0)
	g.start_job(job_idx)
	await until(func(): return g.phase == "intro", 10.0)
	await wait(0.5)
	g.end_intro()
	note("host_ready_peers", await until(func(): return g.net_job != null and g.net_job.ready_peers.size() >= 1, 15.0))
	# the guest does the work, then says so
	await until(func(): return g.has_meta("ask_test_done") or Net.roster.size() < 2, 240.0)
	# wrap the job up so the crew can get paid
	g.test_job_done = true
	g.objs.talk = true
	g.update_objectives()
	note("host_paid_on_request", await until(func(): return g.objs.paid, 20.0))
	for i in range(60):
		await wait(0.1)
		if g.dlg != null: g.advance_dialog()
	note("host_summary", [g.phase, g.hud.summary.visible, g.money])
	Engine.set_meta("nt_stage", 2)
	# the guest heads home from their payday card: the host's game takes the crew home (reloading this scene)
	await until(func(): return false, 30.0)
	note("host_never_went_home", true)
	note("host_objs", g.objs)
	note("host_tree", g.tree.state)
	note("host_truck_moved", snappedf(g.truck.global_position.distance_to(g.world.park if false else g.truck.global_position), 0.1))
	note("host_chipped", g.haul.chips_done)
	_summary("host")
	note("host_last_guest_xf", g.get_meta("guest_check", ""))

# ---------------------------------------------------------------- the guest
func _net_guest() -> void:
	_arg_job()
	if Engine.get_meta("nt_stage", 1) == 2:
		await wait(2.0)
		note("guest_back_home", [g.in_hub, Net.role, Net.roster.size()])
		Net.leave()
		await wait(1.0)
		return
	await wait(2.0)
	g.hub_begin()
	note("join_err", Net.join("127.0.0.1"))
	note("guest_on_crew", await until(func(): return Net.is_guest(), 15.0))
	note("guest_in_job", await until(func(): return not g.in_hub and g.phase == "intro", 30.0))
	await wait(0.5)
	g.end_intro()
	note("guest_welcomed", await until(func(): return not g.hud.obj_list_lines.is_empty(), 10.0))
	var start_truck: Vector3 = g.truck.global_position
	# talk to the client
	g.talk_to_earl()
	for i in range(30):
		await wait(0.05)
		if g.dlg != null: g.advance_dialog()
	note("guest_talk_mirrored", await until(func(): return g.objs.get("talk", false), 5.0))
	match g.job.id:
		"earl": await _guest_fell()
		"hale": await _guest_hale()
		"dock": await _guest_dock()
		"storm": note("guest_storm_pieces_at_start", g.pieces().size())
	if g.job.id == "earl": await _guest_real_saw()
	await _guest_limb_and_buck()
	if g.trailer: await _guest_trailer()
	await _guest_carry_and_throw()
	await _guest_chip()
	await _guest_drive(start_truck)
	await wait(1.0)
	note("guest_objs", g.objs)
	note("guest_objective_lines", g.hud.obj_list_lines.size())
	_summary("guest")
	# all done: the host wraps it up; we talk to the client and get our share
	Net.ask("test_done")
	note("guest_job_complete", await until(func(): return g.objs.get("stacked", false) and g.objs.get("limbed", false), 10.0))
	var ep: Vector3 = g.earl.global_position + Vector3(1.6, 0, 0)
	g.player.teleport(Vector3(ep.x, g.world.H(ep.x, ep.z) + 0.05, ep.z))
	g.talk_to_earl()
	note("guest_payday_dialog", await until(func(): return g.dlg != null, 10.0))
	for i in range(60):
		await wait(0.1)
		if g.dlg != null: g.advance_dialog()
	note("guest_summary", [g.phase, g.hud.summary.visible, g.hud.sum_rows.get_child_count()])
	var share_row := ""
	for r in g.hud.sum_rows.get_children():
		for l in r.find_children("*", "Label", true, false):
			if (l as Label).text.contains("Split") or (l as Label).text.begins_with("−$") or (l as Label).text == "Total": share_row += (l as Label).text + " "
	note("guest_share_row", share_row)
	Engine.set_meta("nt_stage", 2)
	await wait(1.0)
	g.next_job()                   # "head home": asks the host, who takes the whole crew
	await wait(15.0)

## the same felling cuts as tests._fell_tree_quick, but through the guest's own copy: each cut goes up
## to the host, and the host's tree decides when it goes
func _guest_fell() -> void:
	var tr: AshTree = g.tree
	var T: Dictionary = tr.T
	var house := Vector3(g.world.house.x, 0, g.world.house.z) if not g.world.house.is_empty() else tr.global_position + Vector3(10, 0, 0)
	var away := (tr.global_position - house); away.y = 0; away = away.normalized()
	var Fn: Vector3 = tr.global_transform.basis.inverse() * away; Fn.y = 0; Fn = Fn.normalized()
	var h := 0.55; var R := Wood.r_at(T, h); var d := 2 * R * 0.33; var a := deg_to_rad(55)
	var right := Fn.cross(Vector3.UP).normalized()
	var bot := tr.start_cut(Fn * R + Vector3(0, h, 0), -Fn, Vector3.UP); bot.s = d + 0.005; tr.cut_progress(bot)
	var ft := (-Fn * cos(a) + Vector3.DOWN * sin(a)).normalized()
	var top := tr.start_cut(Fn * R + Vector3(0, h + d * tan(a), 0), ft, ft.cross(right).normalized()); top.s = d / cos(a) + 0.005; tr.cut_progress(top)
	await wait(0.6)
	var bc := tr.start_cut(-Fn * R + Vector3(0, h + 0.03, 0), Fn, Vector3.UP); bc.s = 2 * R - d - 0.04; tr.cut_progress(bc)
	note("guest_saw_tree_fall", await until(func(): return tr.state != "stand", 10.0))
	note("guest_tree_down", await until(func(): return tr.state == "down", 15.0))
	note("guest_stem_mirror", await until(func(): return tr.stem != null and is_instance_valid(tr.stem) and tr.stem.has_meta("mirror"), 5.0))
	await wait(6.0)
	note("guest_felled_mirrored", g.objs.get("felled", false))

func _cut(b: WoodPiece, c: Dictionary) -> void:
	c.piece = b
	g.saw._finish_piece_cut(c)

func _guest_limb_and_buck() -> void:
	# every limb off every trunk, at the collar
	for round in range(4):
		var any := false
		for b in g.pieces():
			if b.kind != "trunk" or b.limbs.is_empty() or not b.has_meta("mirror"): continue
			for id in b.limbs.duplicate():
				var L: Dictionary = b.T.limbs[id]
				var e: Vector3 = L.base + L.dir * L.len * 0.02
				_cut(b, {kind = "piece", type = "kerf", part = {limb = id}, e = e, f = L.dir.cross(Vector3.UP).normalized(), n = L.dir, s = 1.0, exit = 0.1})
				any = true
			break
		await wait(0.8)
		if not any: break
	note("guest_limbs_left", g.pieces().filter(func(b): return b.kind == "trunk" and not b.limbs.is_empty()).size())
	# buck the heavy trunks into liftable rounds
	var guard := 0
	while guard < 40:
		guard += 1
		var trunks: Array = g.pieces().filter(func(b): return b.kind == "trunk" and b.mass > Wood.LIFT_MAX * 0.92 and b.limbs.is_empty())
		if trunks.is_empty(): break
		var b: WoodPiece = trunks[0]
		var r := Wood.r_at(b.T, b.span.y - 0.3)
		var L := clampf(52.0 / (Wood.RHO * PI * r * r), 0.25, 2.0)
		var y := b.span.y - L
		if y <= b.span.x + 0.1: y = (b.span.x + b.span.y) / 2
		_cut(b, {kind = "piece", type = "kerf", part = {trunk = true}, e = Vector3(0, y, 0), f = Vector3.RIGHT, n = Vector3.UP, s = 1.0, exit = 1.0})
		await wait(0.7)
	note("guest_heavy_left", g.pieces().filter(func(b): return b.kind == "trunk" and b.mass > Wood.LIFT_MAX * 0.92).size())

func _guest_carry_and_throw() -> void:
	var rounds: Array = g.pieces().filter(func(b): return b.kind == "trunk" and b.limbs.is_empty() and b.mass <= Wood.LIFT_MAX and b.mode == "dyn")
	if rounds.is_empty(): note("guest_carry", "no rounds"); return
	var b: WoodPiece = rounds[0]
	var nid: int = b.get_meta("nid")
	var bc := b.center_world()
	var p: Player = g.player
	p.teleport(Vector3(bc.x + 1.0, g.world.H(bc.x + 1, bc.z) + 0.05, bc.z))
	await wait(0.2)
	g.haul.pick_up(b)
	note("guest_holding", g.net_job.mine.has(nid))
	var dest := bc + Vector3(4.0, 0, 3.0)
	p.teleport(Vector3(dest.x, g.world.H(dest.x, dest.z) + 0.05, dest.z))
	await wait(1.2)
	g.haul.drop_all()
	await wait(3.0)
	var mb = g.net_job.mirrors.get(nid)
	note("guest_round_moved", snappedf(mb.global_position.distance_to(bc), 0.1) if mb != null and is_instance_valid(mb) else -1.0)
	note("guest_round_back_to_host", not g.net_job.mine.has(nid))

func _guest_chip() -> void:
	Net.ask("use", ["chipper"])
	note("guest_chipper_running", await until(func(): return g.chipper.running, 5.0))
	var brush: Array = g.pieces().filter(func(b): return b.chippable() and b.mode == "dyn" and b.kind == "limb")
	var n0: int = brush.size()
	var fed := 0
	for b in brush.slice(0, 4):
		var hp: Vector3 = g.chipper.hopper_world()
		g.player.teleport(Vector3(hp.x + 1.2, g.world.H(hp.x + 1.2, hp.z) + 0.05, hp.z))
		await wait(0.15)
		if not is_instance_valid(b) or b.mode != "dyn": continue
		g.haul.pick_up(b)
		await wait(0.3)
		g.haul.feed()
		fed += 1
		await wait(0.3)
	await wait(fed * 2.5 + 2.0)
	var n1: int = g.pieces().filter(func(b): return b.chippable() and b.kind == "limb").size()
	note("guest_brush_chipped", [n0, n1, fed])

func _guest_drive(start: Vector3) -> void:
	var tp: Vector3 = g.truck.global_transform * Vector3(1.75, 0, 0.15)
	g.player.teleport(Vector3(tp.x, g.world.H(tp.x, tp.z) + 0.05, tp.z))
	await wait(0.2)
	g.enter_truck()
	note("guest_in_seat", await until(func(): return g.player.in_truck, 5.0))
	var p0: Vector3 = g.truck.global_position
	Input.action_press("move_fwd")
	await wait(2.5)
	Input.action_release("move_fwd")
	Input.action_press("jump")
	await wait(1.0)
	Input.action_release("jump")
	note("guest_truck_moved", snappedf(g.truck.global_position.distance_to(p0), 0.1))
	note("guest_speedo", snappedf(g.net_job.truck_speed, 0.1))
	g.exit_truck()
	await wait(1.0)
	note("guest_out_of_seat", not g.player.in_truck)

func look_at_point2(p: Vector3) -> void:
	var e: Vector3 = g.player.global_position + Vector3(0, g.player.eye_h, 0)
	var d := (p - e).normalized()
	g.player.yaw = atan2(-d.x, -d.z)
	g.player.pitch = asin(clampf(d.y, -1, 1))

## Mrs. Hale's maple sits back on its hinge: the guest drives wedges (the host's game does the hammering)
func _guest_hale() -> void:
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
	await wait(0.6)
	var bc := tr.start_cut(-Fn * R + Vector3(0, h + 0.03, 0), Fn, Vector3.UP); bc.s = 2 * R - d - 0.05; tr.cut_progress(bc)
	await wait(2.0)
	note("guest_hale_standing_after_backcut", tr.state)
	var back: Vector3 = tr.global_position - away * 1.25
	g.player.teleport(Vector3(back.x, g.world.H(back.x, back.z) + 0.05, back.z))
	g.player.tool = "wedge"
	look_at_point2(tr.to_world(bc.e)); g.player.pitch -= 0.05
	await wait(0.5)
	note("guest_wedge_prompt", g.rig.prompt())
	var hits := 0
	while tr.state == "stand" and hits < 24:
		look_at_point2(tr.to_world(bc.e))
		g.rig.use(); hits += 1
		await wait(0.4)
		if hits == 3: note("guest_sees_wedges", g.net_job.wedge_nodes.size())
	note("guest_wedge_hits", [hits, tr.state])
	note("guest_tree_down", await until(func(): return tr.state == "down", 15.0))
	note("guest_grade", tr.grade)
	g.player.tool = "hands"
	await wait(5.0)

## Gus's dock: tie the rope round a log in the water, hook it to the truck, and drive it up the lawn
func _guest_dock() -> void:
	var logs: Array = g.pieces().filter(func(b): return b.kind == "trunk")
	note("guest_dock_logs", logs.size())
	if logs.is_empty(): return
	var b: WoodPiece = logs[0]
	var c := b.center_world()
	var to_truck: Vector3 = (g.truck.global_position - c); to_truck.y = 0; to_truck = to_truck.normalized()
	var stand := c + to_truck * 1.3
	g.player.teleport(Vector3(stand.x, g.world.H(stand.x, stand.z) + 0.05, stand.z))
	g.player.tool = "rope"
	# keep the crosshair on it (the log bobs, and you settle in the water) like a player would
	for i in range(12):
		look_at_point2(b.center_world())
		await wait(0.05)
	var e: Vector3 = g.player.eye()
	var q := PhysicsRayQueryParameters3D.create(e, c)
	q.collision_mask = 0xFFFFFFFF
	var hit: Dictionary = g.get_world_3d().direct_space_state.intersect_ray(q)
	note("guest_ray_to_log", [hit.get("collider"), (hit.get("collider") as Object).get("collision_layer") if hit.get("collider") else -1, b.collision_layer, b.freeze, b.mode, b.get_child_count(), b.is_inside_tree()])
	note("guest_aimed_log", [g.rig._aimed_log().has("piece"), g.player.eye().distance_to(c), c.y, g.world.lake.y])
	look_at_point2(b.center_world())
	await frames(2)
	note("guest_rope_prompt_log", g.rig.prompt())
	g.rig.use()
	note("guest_rope_tied", await until(func(): return g.rig.rope == "tree", 3.0))
	var hp: Vector3 = g.truck.hitch_world()
	var near: Vector3 = hp - g.truck.global_transform.basis.z * 1.2
	g.player.teleport(Vector3(near.x, g.world.H(near.x, near.z) + 0.05, near.z))
	look_at_point2(hp)
	await wait(0.6)
	g.rig.use()
	note("guest_rope_rigged", await until(func(): return g.rig.rope == "rigged", 3.0))
	var nid: int = b.get_meta("nid")
	var p0 := c
	var tp: Vector3 = g.truck.global_transform * Vector3(1.75, 0, 0.15)
	g.player.tool = "hands"
	g.player.teleport(Vector3(tp.x, g.world.H(tp.x, tp.z) + 0.05, tp.z))
	await wait(0.3)
	g.enter_truck()
	await until(func(): return g.player.in_truck, 5.0)
	# away from the water: which way is that for the truck?
	var fwd: Vector3 = g.truck.global_transform.basis.z
	var away_from_log: Vector3 = (g.truck.global_position - c).normalized()
	var act := "move_fwd" if fwd.dot(away_from_log) > 0 else "move_back"
	Input.action_press(act)
	await wait(4.0)
	Input.action_release(act)
	Input.action_press("jump"); await wait(1.0); Input.action_release("jump")
	g.exit_truck()
	await wait(1.5)
	var mb = g.net_job.mirrors.get(nid)
	note("guest_log_dragged", snappedf(mb.center_world().distance_to(p0), 0.1) if mb != null and is_instance_valid(mb) else -1.0)
	note("guest_rope_state_after", g.rig.rope)

## rounds into the trailer, thrown from beside it (like tests._haletrailer)
func _guest_trailer() -> void:
	var rounds: Array = g.pieces().filter(func(b): return b.kind == "trunk" and b.limbs.is_empty() and b.mass <= Wood.LIFT_MAX and b.mass > 8.0 and b.mode == "dyn" and not g.trailer.in_bed(b.center_world()))
	rounds.sort_custom(func(a, b): return (a.span.y - a.span.x) < (b.span.y - b.span.x))
	if rounds.is_empty(): note("guest_trailer", "no rounds"); return
	var inn := 0; var n := 0
	for b: WoodPiece in rounds.slice(0, 3):
		var nid: int = b.get_meta("nid")
		var bc := b.center_world()
		g.player.teleport(Vector3(bc.x + 1.0, g.world.H(bc.x + 1, bc.z) + 0.05, bc.z))
		await wait(0.25)
		g.haul.pick_up(b)
		var bxf: Transform3D = g.trailer.bed_xf()
		var st := bxf * Vector3(2.6, 0, -1.7)
		g.player.teleport(Vector3(st.x, g.world.H(st.x, st.z) + 0.05, st.z))
		look_at_point2(bxf * Vector3(0, 1.0, -1.7))
		await wait(0.5)
		g.haul.throw_one()
		n += 1
		await wait(2.5)
		var mb = g.net_job.mirrors.get(nid)
		if mb != null and is_instance_valid(mb) and g.trailer.in_bed(mb.center_world()): inn += 1
	note("guest_rounds_in_trailer", [inn, n])

## the real saw, the way a player uses it: stand over the felled stem, aim, rev. The guest's copy shows
## the kerf going in; when it's through, the host bucks it and the two halves come back
func _guest_real_saw() -> void:
	var st = g.tree.stem
	if st == null or not is_instance_valid(st): note("guest_real_saw", "no stem"); return
	var y: float = lerpf(st.span.x, st.span.y, 0.18)
	var p: Vector3 = st.to_world(Vector3(0, y, 0))
	var ax: Vector3 = (st.global_transform.basis.y).normalized()
	var side := ax.cross(Vector3.UP).normalized()
	var stand := p + side * 1.05
	g.equip("saw"); g.saw.on = true
	g.player.teleport(Vector3(stand.x, g.world.H(stand.x, stand.z) + 0.05, stand.z))
	await wait(0.4)
	look_at_point2(p + Vector3(0, Wood.r_at(st.T, y) * 0.5, 0))
	await wait(0.4)
	var n0: int = g.pieces().size()
	note("guest_saw_guide", [g.saw.guide.get("kind", ""), g.saw.guide.get("too_far", null)])
	g.force_rev = true
	var cut_seen := 0.0
	var t := 0.0
	var rr: float = Wood.r_at(st.T, y)
	while t < 25.0 and is_instance_valid(st) and not st.is_queued_for_deletion() and st.mode != "gone":
		await wait(0.25); t += 0.25
		look_at_point2(p + Vector3(0, rr * 0.5, 0))
		if g.saw.cut != null: cut_seen = maxf(cut_seen, float(g.saw.cut.s))
	g.force_rev = false
	note("guest_real_saw", [snappedf(cut_seen, 0.01), snappedf(t, 0.1), n0, g.pieces().size()])
	g.saw.stop(); g.equip("hands")
	await wait(0.5)

## the phone on the wall, close up and picked up (rendered: run under xvfb with SHOTS set)
func _net_phone() -> void:
	await wait(1.0)
	g.hub_begin()
	await wait(0.5)
	var ph: Vector3 = g.hub.spots.phone[0]
	var stand := ph + Vector3(0.4, -1.3, 1.5)
	g.player.teleport(Vector3(stand.x, g.world.H(stand.x, stand.z) + 0.05 if false else stand.y, stand.z))
	look_at_point(ph + Vector3(0, -0.25, 0))
	await wait(1.0)
	note("phone_aim", g.hub.aim)
	await shot("phone-wall")
	var close := ph + Vector3(0.15, -0.35, 0.75)
	g.player.teleport(Vector3(close.x, stand.y, close.z))
	look_at_point(ph + Vector3(-0.15, -0.35, 0))
	await wait(0.6)
	await shot("phone-closeup")
	g.open_phone()
	g.phone.dial_edit.text = "192.168.1.20"
	g.phone._refresh()
	await wait(0.5)
	await shot("phone-ui-idle")
	g.phone._host()
	await wait(0.5)
	await shot("phone-ui-host")
	g.phone.close()
	Net.leave()

## what a crewmate looks like (the guest renders and takes the pictures)
func _net_look_host() -> void:
	await wait(1.0)
	g.hub_begin()
	Net.host()
	await until(func(): return Net.roster.size() >= 2, 40.0)
	# stand in the yard by the truck for the guest's picture
	var sp: Vector3 = g.player.global_position + Vector3(2.5, 0, -2.0)
	g.player.teleport(Vector3(sp.x, g.world.H(sp.x, sp.z) + 0.05, sp.z))
	g.player.yaw = 0.6
	await until(func(): return g.has_meta("ask_shot_hub"), 120.0)
	g.start_job(0)
	await until(func(): return g.phase == "intro", 10.0)
	await wait(0.5)
	g.end_intro()
	await wait(1.0)
	g.equip("saw"); g.saw.on = true
	var tr: AshTree = g.tree
	var st := tr.global_position + Vector3(1.6, 0, 0.8)
	g.player.teleport(Vector3(st.x, g.world.H(st.x, st.z) + 0.05, st.z))
	look_at_point(tr.global_position + Vector3(0, 0.7, 0))
	for i in range(200):
		g.force_rev = (i % 8) < 5
		await wait(0.25)
		if Net.roster.size() < 2: break

func _net_look_guest() -> void:
	await wait(2.0)
	g.hub_begin()
	Net.my_name = "Sam"
	Net.join("127.0.0.1")
	await until(func(): return Net.is_guest(), 20.0)
	await wait(3.0)
	var av = Net.avatars.get(1)
	note("guest_sees_host_avatar", av != null and is_instance_valid(av) and av.visible)
	if av != null and is_instance_valid(av):
		var ap: Vector3 = av.global_position
		var cam_at := ap + Vector3(2.6, 0, 2.2)
		g.player.teleport(Vector3(cam_at.x, g.world.H(cam_at.x, cam_at.z) + 0.05, cam_at.z))
		look_at_point(ap + Vector3(0, 1.2, 0))
		await wait(0.8)
		await shot("crew-hub")
	Net.ask("shot_hub")
	await until(func(): return not g.in_hub and g.phase == "intro", 30.0)
	await wait(0.5)
	g.end_intro()
	await wait(3.0)
	av = Net.avatars.get(1)
	note("guest_sees_host_in_job", av != null and is_instance_valid(av) and av.visible)
	if av != null and is_instance_valid(av):
		var ap: Vector3 = av.global_position
		var cam_at := ap + Vector3(-1.2, 0, 3.2)
		g.player.teleport(Vector3(cam_at.x, g.world.H(cam_at.x, cam_at.z) + 0.05, cam_at.z))
		look_at_point(ap + Vector3(0, 1.1, 0))
		await wait(1.0)
		await shot("crew-job-saw")
		g.player.teleport(Vector3(cam_at.x + 3.0, g.world.H(cam_at.x + 3.0, cam_at.z + 4.0) + 0.05, cam_at.z + 4.0))
		look_at_point(ap + Vector3(0, 1.0, 0))
		await wait(1.0)
		await shot("crew-job-wide")
	Net.leave()

## the crew figures, posed in one game (no network needed to see what they look like)
func _net_figures() -> void:
	await wait(1.0)
	g.hub_begin()
	await wait(0.5)
	Net.roster = {1: {name = "Eric", hat = 0}, 2: {name = "Sam", hat = 1}, 3: {name = "Jo", hat = 2}, 4: {name = "Mo", hat = 3}}
	var base: Vector3 = g.player.global_position + Vector3(0, 0, -4.0)
	var poses := [["saw", Avatar.F_SAW_ON | Avatar.F_REV, -0.3], ["rope", 0, 0.0], ["hands", Avatar.F_CARRY, 0.1], ["wedge", 0, -0.2]]
	var avs := []
	for i in range(4):
		var av := Avatar.new(); g.level_root.add_child(av)
		av.setup(Net.name_of(i + 1), Net.hat_of(i + 1))
		var p := base + Vector3((i - 1.5) * 1.3, 0, 0)
		p.y = g.world.H(p.x, p.z)
		av.apply([p, PI + (i - 1.5) * 0.25, poses[i][2], poses[i][0], poses[i][1], ""])
		avs.append(av)
	await wait(0.3)
	var a0 = avs[0]
	var smi: MeshInstance3D = a0.saw_node.get_child(0)
	note("fig_saw", [smi.mesh.get_aabb(), a0.global_position, a0.saw_node.global_position, a0.saw_node.visible, smi.global_transform.origin])
	var cam_at: Vector3 = base + Vector3(0, 0, 4.2)
	g.player.teleport(Vector3(cam_at.x, g.world.H(cam_at.x, cam_at.z) + 0.05, cam_at.z))
	look_at_point(base + Vector3(0, 1.1, 0))
	await wait(1.2)
	await shot("crew-figures")
	var side: Vector3 = base + Vector3(3.2, 0, 1.8)
	g.player.teleport(Vector3(side.x, g.world.H(side.x, side.z) + 0.05, side.z))
	look_at_point(base + Vector3(-0.6, 1.0, 0))
	await wait(1.0)
	await shot("crew-figures-side")
	Net.roster = {}
