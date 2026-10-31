## A job worked by a crew: keeping everybody's copy of it in step.
## On the host it watches the real world and sends it out: every piece of wood (what it is, where it
## is), the standing tree's cuts and how it falls, the stump, the truck/chipper/trailer, the customer,
## the rope and wedges, the weather and the job list. It also carries out what the guests ask for
## ("cut this log through here", "I've picked this round up", "start the chipper") as if they'd done
## it themselves, standing where they're standing.
## On a guest it builds and moves the copies. The pieces of wood are frozen copies that slide to where
## the host says; the ones you're carrying or dragging are yours, and the host follows you instead.
class_name NetJob
extends Node

const XF_HZ := 20.0
const DEF_EVERY := 0.25
const SLOW_EVERY := 0.2

var game
var host := false

# ---------------------------------------------------------------- host
var pieces := {}          # nid -> WoodPiece
var next_id := 1
var sigs := {}            # nid -> hash of the definition last sent
var sent_xf := {}         # nid -> Transform3D last sent
var holders := {}           # nid -> the guest holding or dragging it (absent: the host's)
var ready_peers := {}           # peer -> true once their copy of the job is built
var proxies := {}         # peer -> Player standing in for them while their requests are carried out
var proxy_haul: Haul      # empty hands for the stand-ins (so nothing of the host's gets dropped)
var _t := 0.0
var _def_t := 0.0
var _slow_t := 0.0
var _last := {}           # what was last sent of each slow state, to send only changes
var _last_tree_state := "stand"
var _lower_on := false

# ---------------------------------------------------------------- guest
var mirrors := {}         # nid -> WoodPiece
var targets := {}         # nid -> Transform3D
var mine := {}            # nid -> true: pieces I'm holding or dragging
var veh_tgt := {}         # "truck" / "chipper" / "trailer" -> Transform3D
var truck_speed := 0.0
var driver := 0           # who's in the truck's seat (0 nobody)
var chipper_holder := 0   # who's walking the chipper by its tongue
var rig_state := {}
var wedge_nodes: Array = []
var earl_tgt = null
var _up_t := 0.0
var _cut_sent := {}       # standing-tree cut -> when it was last sent up
var _cut_depth := {}      # standing-tree cut -> how deep it was then
var _flush_t := 0.0
var _drive_t := 0.0
var _holes := 0
var _pending_stem := 0
var _welcomed := false    # the host's first full picture of the job has arrived
var _ready_t := 0.0

func setup(g) -> void:
	game = g
	host = Net.is_host()
	Net.job = self
	if host:
		proxy_haul = Haul.new(); proxy_haul.name = "ProxyHaul"; add_child(proxy_haul)
		proxy_haul.setup(game)
	else:
		# the host sends its copy once ours is built
		get_tree().create_timer(0.3).timeout.connect(func(): Net.ask("ready"))

func on_crew_gone() -> void:
	# the line dropped: whatever we were holding for the crew goes back to plain physics
	if host:
		for nid in holders.keys(): _release_owner(nid)
		for id in proxies.keys(): _drop_proxy(id)

# ================================================================ helpers
static func is_mirror(b) -> bool:
	return b != null and is_instance_valid(b) and b.has_meta("mirror")

func nid_of(b) -> int:
	return int(b.get_meta("nid", 0)) if b != null and is_instance_valid(b) else 0

func piece(nid: int):
	var d: Dictionary = pieces if host else mirrors
	var b = d.get(nid)
	if b == null or not is_instance_valid(b) or b.is_queued_for_deletion() or b.mode == "gone": return null
	return b

func _peers() -> Array:
	return ready_peers.keys()

## which tree a piece of wood came from (the job tree, or one of the storm's trees)
func _tref(T: Dictionary) -> String:
	if game.tree and is_same(T, game.tree.T): return "tree"
	for i in range(game.storm_Ts.size()):
		if is_same(T, game.storm_Ts[i]): return "s%d" % i
	return "tree"

func _T_of(ref: String) -> Dictionary:
	if ref.begins_with("s"):
		var i := int(ref.substr(1))
		if i >= 0 and i < game.storm_Ts.size(): return game.storm_Ts[i]
	return game.tree.T

## a cut or a clip, cut down to what it takes to rebuild it on the other end
static func op_out(op: Dictionary):
	match str(op.get("type", "")):
		"clip":
			var o := {ty = "clip", p = op.p, n = op.n}
			if op.has("gap"): o.gap = op.gap
			return o
		"kerf":
			var o := {ty = "kerf", e = op.e, f = op.f, n = op.n, s = snappedf(float(op.s), 0.004), exit = float(op.get("exit", op.s))}
			if op.get("done", false): o.done = true
			if op.has("w"): o.w = op.w
			return o
		"prism":
			if not op.has("pts"): return null
			return {ty = "prism", pts = op.pts}
		"keep", "cutbox":
			return {ty = op.type, xf = op.xf, size = op.size}
	return null

static var _prism_cache := {}
static func op_in(o: Dictionary) -> Dictionary:
	var op := {}
	for k in o: op[k] = o[k]
	op.type = op.ty
	op.erase("ty")
	if op.type == "prism":
		var key := hash(op.pts)
		if not _prism_cache.has(key): _prism_cache[key] = Wood.prism_mesh(op.pts)
		op.mesh = _prism_cache[key]
	return op

func piece_def(b: WoodPiece) -> Dictionary:
	var ops := []
	for op in b.ops:
		var o = op_out(op)
		if o != null: ops.append(o)
	var d := {k = b.kind, t = _tref(b.T), y0 = b.y0, y1 = b.y1, m = b.mode, ops = ops}
	if not b.limbs.is_empty(): d.l = b.limbs.duplicate()
	if not b.lt.is_empty(): d.lt = b.lt.duplicate()
	if not b.stubs.is_empty(): d.st = b.stubs.duplicate()
	if b.kind == "limb": d.li = b.limb; d.t0 = b.t0; d.t1 = b.t1
	if b.kind == "wedge": d.wp = b.wedge_pts.duplicate()
	return d

func _fill(b: WoodPiece, d: Dictionary) -> void:
	b.T = _T_of(str(d.t))
	b.kind = str(d.k)
	b.y0 = float(d.y0); b.y1 = float(d.y1)
	var ops := []
	for o in d.ops: ops.append(op_in(o))
	b.ops = ops
	b.limbs = (d.get("l", []) as Array).duplicate()
	b.lt = (d.get("lt", {}) as Dictionary).duplicate()
	b.stubs = (d.get("st", []) as Array).duplicate()
	if d.has("li"): b.limb = int(d.li); b.t0 = float(d.t0); b.t1 = float(d.t1)
	if d.has("wp"): b.wedge_pts = (d.wp as Array).duplicate()

## a copy sitting still where the host says, solid unless someone has it in their hands
func _mirror_phys(b: WoodPiece) -> void:
	b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	b.freeze = true
	if b.mode == "held" or b.mode == "feed" or b.mode == "feedwait":
		b.collision_layer = 0; b.collision_mask = 0
	else:
		b.collision_layer = 64 if b.kind == "limb" else 8
		b.collision_mask = 1 | 4 | 8 | 32 | 64

static func _xf_moved(a: Transform3D, b: Transform3D) -> bool:
	if a.origin.distance_squared_to(b.origin) > 0.000016: return true
	return not a.basis.is_equal_approx(b.basis)

static func _ease_xf(cur: Transform3D, tx: Transform3D, k: float) -> Transform3D:
	if cur.origin.distance_to(tx.origin) > 4.0: return tx
	var q := Quaternion(cur.basis.orthonormalized()).slerp(Quaternion(tx.basis.orthonormalized()), k)
	return Transform3D(Basis(q), cur.origin.lerp(tx.origin, k))

# ================================================================ the host: watching and sending
func _physics_process(dt: float) -> void:
	if not Net.active() or game == null or game.level_root == null: return
	if host: _host_step(dt)
	else: _guest_step(dt)

func _host_step(dt: float) -> void:
	_t += dt; _def_t += dt; _slow_t += dt
	if _t < 1.0 / XF_HZ: return
	_t = 0.0
	# every piece of wood gets a number the crew can refer to it by
	var live := {}
	for b in game.pieces():
		var nid := nid_of(b)
		if nid == 0:
			nid = next_id; next_id += 1
			b.set_meta("nid", nid)
			pieces[nid] = b
		live[nid] = true
	var gone := []
	for nid in pieces.keys():
		if not live.has(nid):
			gone.append(nid)
			pieces.erase(nid); sigs.erase(nid); sent_xf.erase(nid); holders.erase(nid)
	if not gone.is_empty(): _tell_ready("gone", [gone])
	# new pieces, and pieces that changed shape (a limb off, a cut started or finished)
	if _def_t >= DEF_EVERY or not gone.is_empty():
		_def_t = 0.0
		_send_defs(false)
	# where everything is
	var ids := PackedInt32Array(); var xfs := []; var own := PackedInt32Array()
	for nid in pieces:
		var b: WoodPiece = pieces[nid]
		var xf := b.global_transform
		if sent_xf.has(nid) and not _xf_moved(sent_xf[nid], xf): continue
		sent_xf[nid] = xf
		ids.append(nid); xfs.append(xf); own.append(int(holders.get(nid, 0)))
	var tr: Truck = game.truck
	var veh := [tr.global_transform, tr.linear_velocity.dot(tr.global_transform.basis.z), game.chipper.global_transform,
		game.trailer.global_transform if game.trailer else null]
	for peer in _peers():
		if not ids.is_empty():
			# everyone but the one carrying it (they're the ones moving it)
			var pi := PackedInt32Array(); var px := []
			for i in range(ids.size()):
				if own[i] == peer: continue
				pi.append(ids[i]); px.append(xfs[i])
			if not pi.is_empty(): Net.stream("xf", [pi, px], peer)
		Net.stream("veh", veh, peer)
		if game.lower.active() or _lower_on:
			Net.stream("lower", [game.lower.line_points()], peer)
	_lower_on = game.lower.active()
	if _slow_t >= SLOW_EVERY:
		_slow_t = 0.0
		_send_slow(false)

func _tell_ready(name: String, args: Array) -> void:
	for peer in _peers(): Net.tell(name, args, peer)

func _send_defs(all: bool, to := 0) -> void:
	var out := []
	for nid in pieces:
		var b: WoodPiece = pieces[nid]
		if not is_instance_valid(b): continue
		var d := piece_def(b)
		var h := hash(d)
		if not all and sigs.get(nid, 0) == h: continue
		sigs[nid] = h
		out.append([nid, d, b.global_transform])
	if out.is_empty(): return
	if to > 0: Net.tell("defs", [out], to)
	else: _tell_ready("defs", [out])

## the things that change now and then: the tree, the stump, the rope, the vehicles' state, the
## customer, the weather. Each only goes out when it's different from last time (or to a newcomer).
func _send_slow(all: bool, to := 0) -> void:
	var states := {}
	var tree: AshTree = game.tree
	if tree.state == "stand":
		var cuts := []
		for c in tree.cuts:
			if c.s > 0.002: cuts.append([c.e, c.f, c.n, snappedf(c.s, 0.002), c.exit, float(c.get("w", -1.0))])
		var holes := []
		for w in tree.freed.values():
			if w.has("pts"): holes.append(w.pts)
		states.tree = [cuts, tree.net, holes, tree.crown_state()]
	if tree.state != _last_tree_state:
		if tree.state == "down": _tell_ready("tree_down", [])
		_last_tree_state = tree.state
	states.rig = game.rig.net_state(self)
	var ch: Chipper = game.chipper
	var holder := 0
	if ch.mode == "hand": holder = _peer_of(game.chipper_holder)
	states.vstate = [ch.mode, ch.running, holder, game.trailer.mode if game.trailer else "", game.trailer.tarped if game.trailer else false, game.truck.remote_driver if game.truck.remote_driver != 0 else (1 if game.player.in_truck else 0)]
	var e: Earl = game.earl
	states.earl = [e.global_transform, e.state, e.talking]
	if game.weather: states.weather = [game.weather.kind]
	for k in states:
		var h := hash(states[k])
		if not all and _last.get(k, 0) == h: continue
		_last[k] = h
		if to > 0: Net.tell(k, states[k], to)
		else: _tell_ready(k, states[k])

func _peer_of(node) -> int:
	if node == null or not is_instance_valid(node) or node == game.player: return 1
	for id in proxies:
		if proxies[id] == node: return id
	return 1

## a guest's copy of the job is built: send them everything as it stands
func _welcome(id: int) -> void:
	ready_peers[id] = true
	_make_proxy(id)
	_send_defs(true, id)
	for k in _last.keys(): _last.erase(k)
	_send_slow(true)
	if game.tree.state != "stand":
		Net.tell("fall", [fall_state("")], id)
	if not game.objs.is_empty(): Net.tell("obj", objective_state(), id)

# ---------------------------------------------------------------- stand-ins
func _make_proxy(id: int) -> void:
	if proxies.has(id) and is_instance_valid(proxies[id]): return
	var px := Player.new(); px.name = "Stand_in_%d" % id
	game.level_root.add_child(px)
	px.set_physics_process(false)
	px.collision_layer = 0; px.collision_mask = 0
	px.visible = false
	px.global_position = game.player.global_position
	proxies[id] = px

func _drop_proxy(id: int) -> void:
	if proxies.has(id):
		if is_instance_valid(proxies[id]): proxies[id].queue_free()
		proxies.erase(id)

func on_pose(id: int, p: Array) -> void:
	var px = proxies.get(id)
	if px == null or not is_instance_valid(px): return
	px.global_position = p[0]
	px.yaw = float(p[1]); px.pitch = float(p[2])
	px.rotation = Vector3(0, px.yaw, 0)
	px.head.rotation = Vector3(px.pitch, 0, 0)
	px.tool = str(p[3])
	var fl := int(p[4])
	px.in_truck = bool(fl & Avatar.F_TRUCK)
	px.head.position.y = 0.98 if (fl & Avatar.F_CROUCH) else 1.62
	px.eye_h = px.head.position.y

## carry something out on the host as if the guest had done it, standing where they stand; any
## message it would have shown goes back to them instead
func as_peer(id: int, fn: Callable) -> void:
	var px = proxies.get(id)
	if px == null or not is_instance_valid(px): return
	var keep_p = game.player; var keep_h = game.haul; var keep_aim: Dictionary = game.aim
	game.player = px; game.haul = proxy_haul
	game.aim = game.compute_aim()
	game.hud.capture = []
	fn.call()
	var said: Array = game.hud.capture
	game.hud.capture = null
	game.player = keep_p; game.haul = keep_h; game.aim = keep_aim
	for s in said: Net.tell("toast", s, id)

# ---------------------------------------------------------------- the guests' requests
func on_ask(id: int, name: String, a: Array) -> void:
	match name:
		"ready": _welcome(id)
		"take":
			var b = piece(int(a[0]))
			var nid := int(a[0])
			var busy: bool = b == null or (holders.has(nid) and holders[nid] != id) or b.mode == "feed" or b.mode == "feedwait" \
				or game.haul.carry.has(b) or (game.haul.drag != null and game.haul.drag.b == b)
			if busy: Net.tell("take_no", [nid], id); return
			holders[nid] = id
			b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			b.freeze = true
			b.mode = str(a[1])
			if b.mode == "held": b.collision_layer = 0; b.collision_mask = 0
		"give":
			var nid := int(a[0])
			if holders.get(nid, 0) != id: return
			_release_owner(nid, a[1], a[2], a[3])
		"feed":
			for nid in a[0]:
				var b = piece(int(nid))
				if b == null: continue
				holders.erase(int(nid))
				b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC; b.freeze = true
				b.mode = "feedwait"
				b.collision_layer = 0; b.collision_mask = 0
				game.haul.feed_queue.append(b)
			game.haul._next_feed()
		"kick":
			var b = piece(int(a[0]))
			if b != null and b.mode == "dyn" and not holders.has(int(a[0])): game.haul.kick_piece(b, a[1], a[2])
		"pcut": _guest_piece_cut(int(a[0]), a[1])
		"tcut": _guest_tree_cut(a)
		"scut":
			var tree: AshTree = game.tree
			if tree.stump == null: return
			var c: Dictionary = tree.stump_start_cut(a[0], a[1], a[2])
			c.s = c.exit
			tree.finish_stump_cut(c)
			game.update_objectives()
		# done as them, from exactly where they stood and looked when they clicked
		"rig":
			if a.size() > 0 and a[0] is Array: on_pose(id, a[0])
			as_peer(id, func(): game.rig.use())
		# up in the tree: a guest climber's cut through a limb or the stem, and their lowering line
		"crown": game.climb.cut_crown(str(a[0]), float(a[1]), int(a[2]), float(a[3]), a[4])
		"lower_tie":
			on_pose(id, a[0])
			as_peer(id, func(): game.lower.tie_aimed(float(a[1])))
		"use":
			if a.size() > 1 and a[1] is Array: on_pose(id, a[1])
			as_peer(id, func(): game.net_use(str(a[0])))
		"seat":
			var tr: Truck = game.truck
			if tr.remote_driver != 0 or game.player.in_truck:
				Net.tell("toast", ["%s's got the wheel." % (Net.name_of(tr.remote_driver) if tr.remote_driver != 0 else Net.boss_name()), 2.5], id); return
			tr.remote_driver = id; tr.remote_in = {}
			tr.enter(true)
			Net.tell("seat", [], id)
		"unseat": _unseat(id)
		"talked":
			if not game.objs.talk:
				game.objs.talk = true; game.earl.state = "idle"; game.update_objectives()
		"pay":
			if game.objs.felled and game.objs.limbed and game.objs.stacked and game.objs.tarped and not game.objs.paid: game.payday()
		"home": game.next_job()
		_: game.set_meta("ask_" + name, true)        # (the two-player tests signal each other this way)

func _unseat(id: int) -> void:
	var tr: Truck = game.truck
	if tr.remote_driver != id: return
	tr.remote_driver = 0; tr.remote_in = {}
	tr.exit()

func _release_owner(nid: int, xf = null, lv = Vector3.ZERO, av = Vector3.ZERO) -> void:
	holders.erase(nid)
	var b = piece(nid)
	if b == null: return
	b.mode = "dyn"
	b.collision_layer = 64 if b.kind == "limb" else 8
	b.collision_mask = 1 | 4 | 8 | 32 | 64
	if xf != null:
		b.global_transform = xf
		PhysicsServer3D.body_set_state(b.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	b.freeze = false
	b.linear_velocity = lv; b.angular_velocity = av
	b.sleeping = false
	get_tree().create_timer(1.5).timeout.connect(game.update_objectives)

## a guest's saw went through a log or a branch: make the same cut here, and the pieces follow
func _guest_piece_cut(nid: int, a: Dictionary) -> void:
	var b = piece(nid)
	if b == null or holders.has(nid): return
	var part: Dictionary = a.part
	var e: Vector3 = a.e; var f: Vector3 = a.f; var n: Vector3 = a.n
	var c := {kind = "piece", type = "kerf", piece = b, part = part, e = e, f = f, n = n, s = float(a.exit) + 0.004, exit = float(a.exit)}
	if not part.has("limb"):
		var found = null
		for op in b.ops:
			if op.type == "kerf" and not op.get("done", false) and absf(op.n.dot(n)) > 0.97 and absf(op.n.dot(e - op.e)) < 0.04 and op.f.dot(f) > 0.9:
				found = op; break
		if found != null:
			found.s = found.exit + 0.004; found.piece = b; found.part = part; c = found
		else:
			b.ops.append(c)
	game.saw._finish_piece_cut(c)

## a guest's saw is in the standing tree: the same cut, as deep as theirs, in the host's tree
func _guest_tree_cut(a: Array) -> void:
	var tree: AshTree = game.tree
	if tree.state != "stand": return
	var c: Dictionary = tree.start_cut(a[0], a[1], a[2])
	c.s = maxf(float(c.s), float(a[3]))
	c.exit = maxf(float(c.exit), float(a[4]))
	if float(a[5]) > 0.0: c.w = float(a[5])
	c.guided = true
	tree.cut_progress(c)

func on_stream_up(id: int, name: String, a: Array) -> void:
	match name:
		"own":
			var ids: PackedInt32Array = a[0]; var xfs: Array = a[1]
			for i in range(ids.size()):
				var nid := ids[i]
				if holders.get(nid, 0) != id: continue
				var b = piece(nid)
				if b != null: b.global_transform = xfs[i]
		"drive":
			var tr: Truck = game.truck
			if tr.remote_driver == id: tr.remote_in = {thr = float(a[0]), st = float(a[1]), br = bool(a[2])}
		"lrun": game.lower.remote_run()

func on_peer_left(id: int) -> void:
	ready_peers.erase(id)
	for nid in holders.keys():
		if holders[nid] == id: _release_owner(nid)
	_unseat(id)
	if game.chipper.mode == "hand" and game.chipper_holder == proxies.get(id):
		game.chipper.set_down(); game.chipper_holder = null
	if game.rig.holder == proxies.get(id): game.rig.holder = null
	_drop_proxy(id)

# ---------------------------------------------------------------- the host's tree and job, as messages
func fall_state(kind: String) -> Dictionary:
	var tree: AshTree = game.tree
	var stem_id := nid_of(tree.stem)
	return {kind = kind, stem = stem_id, stump = stump_state(), grade = tree.grade}

func stump_state() -> Dictionary:
	var tree: AshTree = game.tree
	var ops := []
	for op in tree.stump_ops:
		var o = op_out(op)
		if o != null: ops.append(o)
	return {ops = ops, top = tree.stump_top, y0 = tree.stump_y0, bd = tree.barber_dir, sx = tree.slab_xf, ss = tree.slab_size}

## the host's tree just went: give the stem its number now and send it with the fall
func tree_fell(kind: String) -> void:
	var st: WoodPiece = game.tree.stem
	if st and nid_of(st) == 0:
		var nid := next_id; next_id += 1
		st.set_meta("nid", nid); pieces[nid] = st
	_send_defs(false)
	_tell_ready("fall", [fall_state(kind)])
	_last.erase("tree")

func stump_changed() -> void:
	_send_defs(false)
	_tell_ready("stump", [stump_state()])

func objective_state() -> Array:
	return [game.hud.obj_list_lines, game.objs, game.counts]

func objectives_changed() -> void:
	var st := objective_state()
	var h := hash(st)
	if _last.get("obj", 0) == h: return
	_last.obj = h
	_tell_ready("obj", st)

func bark(text: String, secs: float) -> void:
	_tell_ready("bark", [text, secs])

func event_all(name: String, args: Array) -> void:
	_tell_ready(name, args)

# ================================================================ the guest: building and moving the copies
func _guest_step(dt: float) -> void:
	# until the host's first full picture arrives, keep asking (their copy may have been built after ours)
	if not _welcomed:
		_ready_t += dt
		if _ready_t > 1.5:
			_ready_t = 0.0
			Net.ask("ready")
	var k := 1.0 - exp(-dt * 16.0)
	for nid in targets:
		if mine.has(nid): continue
		var b = mirrors.get(nid)
		if b == null or not is_instance_valid(b): continue
		b.global_transform = _ease_xf(b.global_transform, targets[nid], k)
	# the vehicles are the host's: keep ours frozen copies and slide them along
	var tr: Truck = game.truck
	for pair in [["truck", tr], ["chipper", game.chipper], ["trailer", game.trailer]]:
		var v = pair[1]
		if v == null or not is_instance_valid(v): continue
		if not v.freeze: v.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC; v.freeze = true
		if v.get("joint") != null and is_instance_valid(v.joint): v._clear_joint()
		if game.phase == "play" and veh_tgt.has(pair[0]): v.global_transform = _ease_xf(v.global_transform, veh_tgt[pair[0]], k)
	if game.phase == "play": tr.scripted_speed = absf(truck_speed)
	# the customer
	if earl_tgt != null and game.phase == "play":
		var ex: Transform3D = earl_tgt
		game.earl.global_transform = _ease_xf(game.earl.global_transform, ex, k)
	# what I'm carrying or dragging, up to the host
	_up_t += dt
	if _up_t >= 1.0 / XF_HZ:
		_up_t = 0.0
		if not mine.is_empty():
			var ids := PackedInt32Array(); var xfs := []
			for nid in mine.keys():
				var b = mirrors.get(nid)
				if b == null or not is_instance_valid(b): mine.erase(nid); continue
				ids.append(nid); xfs.append(b.global_transform)
			if not ids.is_empty(): Net.stream_up("own", [ids, xfs])
	# working the lowering line's brake (from up in the tree, or at the base): keep telling the host
	if game.lower and game.lower.run_local and _up_t == 0.0: Net.stream_up("lrun", [true])
	if game.player and game.player.in_truck:
		_drive_t += dt
		if _drive_t >= 1.0 / 30.0:
			_drive_t = 0.0
			var cap: bool = game.cap() or game.tests != null
			Net.stream_up("drive", [Input.get_axis("move_back", "move_fwd") if cap else 0.0,
				Input.get_axis("move_right", "move_left") if cap else 0.0, Input.is_action_pressed("jump") and cap])
	# a cut that's gone deeper since it was last sent (you let off the trigger between updates): send it now
	_flush_t += dt
	if _flush_t > 0.25 and game.tree and game.tree.state == "stand":
		_flush_t = 0.0
		for c in game.tree.cuts:
			if _cut_depth.has(c) and float(c.s) > float(_cut_depth[c]) + 0.0005: tree_cut(c, true)
	if _pending_stem != 0:
		var st = mirrors.get(_pending_stem)
		if st != null and is_instance_valid(st):
			game.tree.stem = st; _pending_stem = 0

func on_stream(name: String, a: Array) -> void:
	if host: return
	match name:
		"xf":
			var ids: PackedInt32Array = a[0]; var xfs: Array = a[1]
			for i in range(ids.size()):
				if mirrors.has(ids[i]) and not mine.has(ids[i]): targets[ids[i]] = xfs[i]
		"veh":
			veh_tgt.truck = a[0]; truck_speed = float(a[1]); veh_tgt.chipper = a[2]
			if a[3] != null: veh_tgt.trailer = a[3]
		"lower": game.lower.net_line = a[0]

func on_event(name: String, a: Array) -> void:
	if host: return
	_welcomed = true
	match name:
		"defs": _apply_defs(a[0])
		"gone":
			for nid in a[0]: _remove_mirror(int(nid))
		"take_no":
			var b = mirrors.get(int(a[0]))
			mine.erase(int(a[0]))
			if b != null and is_instance_valid(b):
				game.haul.carry.erase(b)
				if game.haul.drag != null and game.haul.drag.b == b: game.haul.drag = null
				_mirror_phys(b)
			game.hud.toast("Somebody's already got that one.", 2.0)
		"tree":
			game.tree.net_apply(a[0], a[1], a[2])
			if a.size() > 3: game.tree.net_crown(a[3])
		"fall":
			var d: Dictionary = a[0]
			_pending_stem = int(d.stem)
			game.tree.net_fall(d)
		"tree_down":
			if game.tree.state == "hinge": game.tree.state = "down"; game.tree.down_t = game.tree.t
		"stump": game.tree.net_stump(a[0])
		"rig": game.rig.net_apply(a, self)
		"vstate": _apply_vstate(a)
		"earl":
			earl_tgt = a[0]
			game.earl.mirror = true
			if game.earl.walk_to == null: game.earl.state = str(a[1])
			game.earl.remote_talk = bool(a[2])
		"bark": game.earl.bark(str(a[0]), float(a[1]))
		"weather":
			if game.weather: game.weather.net_set(str(a[0]))
		"obj":
			game.hud.set_objectives(a[0])
			game.objs = a[1]; game.counts = a[2]
		"crunch": game.net_crunch(str(a[0]))
		"seat": game.enter_truck_mirror()
		"toast": game.hud.toast(str(a[0]), float(a[1]) if a.size() > 1 else 3.0)

func _apply_defs(list: Array) -> void:
	for e in list:
		var nid := int(e[0]); var d: Dictionary = e[1]; var xf: Transform3D = e[2]
		var b = mirrors.get(nid)
		if b != null and not is_instance_valid(b): b = null
		var fresh: bool = b == null
		if fresh:
			b = WoodPiece.new()
			b.set_meta("nid", nid); b.set_meta("mirror", true)
			b.name = "Wood_%d" % nid
			game.level_root.add_child(b)
			mirrors[nid] = b
		var keep_mode: String = b.mode
		_fill(b, d)
		if mine.has(nid): b.mode = keep_mode
		else: b.mode = str(d.m)
		# a cut I've got going in this piece stays in it while the host's copy catches up
		var c = game.saw.cut
		if c != null and c.get("piece") == b and c.get("type", "") == "kerf" and not c.get("done", false) and not c.get("part", {}).has("limb"):
			b.ops.append(c)
		b.build()
		if fresh:
			b.global_transform = xf
			targets[nid] = xf
		if not mine.has(nid): _mirror_phys(b)
		elif b.mode == "held":
			b.collision_layer = 0; b.collision_mask = 0          # still in my hands: rebuilt, but not solid
		if b.mode == "gone": _remove_mirror(nid)

func _remove_mirror(nid: int) -> void:
	var b = mirrors.get(nid)
	mirrors.erase(nid); targets.erase(nid); mine.erase(nid)
	if b == null or not is_instance_valid(b): return
	game.haul.carry.erase(b)
	if game.haul.drag != null and game.haul.drag.b == b: game.haul.drag = null
	if game.saw.cut != null and game.saw.cut.get("piece") == b: game.saw.cut = null
	if game.haul.feeding == b: game.haul.feeding = null
	b.mode = "gone"
	b.queue_free()

func _apply_vstate(a: Array) -> void:
	var ch: Chipper = game.chipper
	ch.mode = str(a[0])
	var run := bool(a[1])
	if run != ch.running:
		ch.running = run
		if run and ch.engine_snd == null: ch.engine_snd = Sfx.engine("chipper")
		elif not run and ch.engine_snd: ch.engine_snd.stop(); ch.engine_snd = null
	chipper_holder = int(a[2])
	if game.trailer:
		game.trailer.mode = str(a[3])
		if bool(a[4]) and not game.trailer.tarped:
			var cargo: Array = game.pieces().filter(func(b): return game.trailer.in_bed(b.center_world()))
			game.trailer.tarp_it(Callable(), cargo)
	driver = int(a[5])
	game.truck.show_driver = driver != 0 and driver != Net.me()
	# the host let me out of the seat (or never let me in)
	if game.player.in_truck and driver != Net.me() and game.get("_seat_t") != null and game.clock - game._seat_t > 2.0:
		game.exit_truck_mirror()

# ---------------------------------------------------------------- what a guest does to the shared world
## picked up, or started dragging: mine now (the host follows me)
func take(b: WoodPiece, mode: String) -> void:
	var nid := nid_of(b)
	if nid == 0: return
	mine[nid] = true
	targets.erase(nid)
	Net.ask("take", [nid, mode])

## let go of it: back to the host, with the way it's moving
func give(b: WoodPiece, lv: Vector3, av: Vector3) -> void:
	var nid := nid_of(b)
	if nid == 0 or not mine.has(nid): return
	mine.erase(nid)
	Net.ask("give", [nid, b.global_transform, lv, av])
	targets[nid] = b.global_transform
	_mirror_phys(b)

func feed(list: Array) -> void:
	var ids := []
	for b in list:
		var nid := nid_of(b)
		if nid == 0: continue
		mine.erase(nid)
		b.mode = "feedwait"
		_mirror_phys(b)
		ids.append(nid)
	if not ids.is_empty(): Net.ask("feed", [ids])

func kick(b: WoodPiece, at: Vector3, d: Vector3) -> void:
	var nid := nid_of(b)
	if nid != 0: Net.ask("kick", [nid, at, d])

func cut_piece(c: Dictionary) -> void:
	var b = c.get("piece")
	var nid := nid_of(b)
	if nid == 0: return
	c.done = true
	Net.ask("pcut", [nid, {e = c.e, f = c.f, n = c.n, exit = float(c.exit), part = c.get("part", {trunk = true})}])
	Sfx.play("crunch")

## my saw in the standing tree: tell the host how deep (often enough to feel live, not every frame)
func tree_cut(c: Dictionary, final := false) -> void:
	var now: float = game.clock
	if not final and now - float(_cut_sent.get(c, -1.0)) < 0.1: return
	_cut_sent[c] = now
	_cut_depth[c] = float(c.s)
	Net.ask("tcut", [c.e, c.f, c.n, float(c.s), float(c.exit), float(c.get("w", -1.0))])

func stump_cut(c: Dictionary) -> void:
	Net.ask("scut", [c.e, c.f, c.n, float(c.exit)])

## is somebody else holding this piece?
func taken(b) -> bool:
	if b == null or not is_instance_valid(b): return false
	if host: return holders.has(nid_of(b))
	return b.mode == "held" and not mine.has(nid_of(b))

## the guests' wedges, where the host has them
func show_wedges(xfs: Array, mesh: Mesh) -> void:
	while wedge_nodes.size() > xfs.size():
		var n = wedge_nodes.pop_back()
		if is_instance_valid(n): n.queue_free()
	while wedge_nodes.size() < xfs.size():
		if game.tree.state != "stand": break
		var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = Mats.vcol
		game.tree.add_child(mi)
		wedge_nodes.append(mi)
	for i in range(mini(xfs.size(), wedge_nodes.size())):
		if is_instance_valid(wedge_nodes[i]): wedge_nodes[i].transform = xfs[i]
