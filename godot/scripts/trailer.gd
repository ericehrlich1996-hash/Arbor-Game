## Walter's old utility trailer: a single-axle steel trailer with oak stake sides and a drop gate.
## Mrs. Hale gives it to you along with the wood. It's a real trailer: back the truck up to the tongue
## and hitch it (the load comes with it), and there's a ball on the back bumper so the chipper can ride
## behind it: truck, trailer, chipper. Parked, it sits on its tongue jack with the wheels chocked.
## The bed uses the truck's bed frame conventions (floor top at y 0.8, walls to 1.36, back toward -z),
## sitting 0.2 lower so the floor is 0.6 off the ground; it's twice as long as the truck's bed.
## When it's loaded you tarp it: a blue tarp shaped over the actual load unrolls and bungees down.
class_name Trailer
extends VehicleBody3D

const SINK := 0.2
const Z0 := -4.51               # back of the bed (the drop gate)
const Z1 := -0.73               # front of the bed (the front board)
const COUPLER := Vector3(0, 0.42, Z1 + 1.42)     # the coupler on the end of the tongue
const BALL := Vector3(0, 0.54, Z0 - 0.36)        # the hitch ball on the back bumper, for the chipper
const AXLE := (Z0 + Z1) / 2.0 + 0.05

var tarp: Node3D
var tarped := false
var mode := "free"              # "free" (parked on its jack) | "truck" (on the truck's ball)
var truck: Truck
var joint: PinJoint3D
var jack_shape: CollisionShape3D
var jack_mesh: MeshInstance3D
var _steel := Color("#3a4a3e")
var strapped: Array = []        # [[round, its place in the trailer's frame]]: under the tarp, they ride along

func build() -> void:
	collision_layer = 4; collision_mask = 1 | 4 | 8 | 64
	mass = 420.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.45, AXLE)
	angular_damp = 1.5
	var mb := MeshBuilder.new()
	var steel := _steel; var dk := Color("#1e2420"); var oak := Color("#8a6a48"); var deck := Color("#7a6a52")
	var rust := Color("#6b3a22")
	var z0 := Z0; var z1 := Z1; var zc := (z0 + z1) / 2; var L := z1 - z0
	# frame and floor
	for sx: float in [-1.0, 1.0]: mb.box(sx * 0.82, 0.66, zc, 0.08, 0.12, L + 0.1, steel)
	for k in range(9): mb.box(0, 0.64, z0 + 0.1 + k * (L - 0.2) / 8.0, 1.7, 0.08, 0.06, steel)
	var x := -0.88
	var r := RandomNumberGenerator.new(); r.seed = 41
	while x < 0.88:
		mb.box(x + 0.09, 0.76, zc, 0.175, 0.07, L, deck.lerp(Color("#8e7c60"), r.randf()))
		x += 0.18
	# stake sides: steel pockets with oak boards, and the drop gate at the back
	for sx: float in [-1.0, 1.0]:
		for k in range(7):
			var zz := z0 + 0.12 + k * (L - 0.24) / 6.0
			mb.box(sx * 0.93, 1.06, zz, 0.06, 0.62, 0.06, steel)
		for k in range(3): mb.box(sx * 0.93, 0.92 + k * 0.17, zc, 0.04, 0.13, L, oak.lerp(Color("#9a7a56"), r.randf()))
		mb.box(sx * 0.93, 1.36, zc, 0.07, 0.04, L + 0.06, steel)
	for k in range(3): mb.box(0, 0.92 + k * 0.17, z1 + 0.02, 1.86, 0.13, 0.04, oak.lerp(Color("#9a7a56"), r.randf()))   # front board
	for k in range(3): mb.box(0, 0.92 + k * 0.17, z0 - 0.02, 1.86, 0.13, 0.04, oak.lerp(Color("#9a7a56"), r.randf()))   # drop gate
	for sx: float in [-1.0, 1.0]:
		mb.box(sx * 0.5, 1.06, z0 - 0.05, 0.05, 0.5, 0.03, steel)
		mb.box(sx * 0.78, 0.7, z0 - 0.08, 0.12, 0.07, 0.03, Color("#c22a1e"))           # tail lights
	# the rear bumper and its hitch ball, for the chipper
	mb.box(0, 0.6, z0 - 0.1, 1.7, 0.1, 0.1, steel)
	mb.box(0, BALL.y + SINK - 0.08, z0 - 0.24, 0.1, 0.08, 0.32, dk)
	mb.sphere(0, BALL.y + SINK, BALL.z, 0.045, 0.045, 0.045, Color("#c8ccd0"), 10, 6)
	mb.cyl(0, BALL.y + SINK - 0.06, BALL.z, 0.025, 0.025, 0.05, Color("#c8ccd0"), 8, true)
	# axle, fenders and wheels
	var ax := AXLE
	mb.push(Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(0, 0.5, ax)))
	mb.cyl(0, -1.0, 0, 0.04, 0.04, 2.0, dk, 8, true)
	mb.pop()
	for sx: float in [-1.0, 1.0]:
		var prev := Vector3.ZERO
		for k in range(9):
			var a := PI * k / 8.0
			var q := Vector3(sx * 1.08, 0.52 + sin(a) * 0.36, ax - cos(a) * 0.4)
			if k > 0:
				var dir := (q - prev).normalized(); var mid := (prev + q) / 2
				mb.push(Transform3D(Basis(Vector3.RIGHT, atan2(-dir.y, dir.z)), mid))
				mb.box(0, 0, 0, 0.26, 0.025, prev.distance_to(q) + 0.01, steel.lerp(rust, 0.3))
				mb.pop()
			prev = q
		mb.push(Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(sx * 1.08, 0.5, ax)))
		mb.cyl(0, -0.1, 0, 0.29, 0.29, 0.2, Color("#1a1a1a"), 18, true, Color("#222222"))
		mb.cyl(0, sx * 0.1 - (0.01 if sx < 0 else 0.0), 0, 0.17, 0.17, 0.012, Color("#c8ccd0"), 14, true)
		mb.pop()
	# the tongue and coupler
	mb.tube(Vector3(-0.8, 0.66, z1), Vector3(0, 0.62, z1 + 1.3), 0.04, 0.04, steel, 6)
	mb.tube(Vector3(0.8, 0.66, z1), Vector3(0, 0.62, z1 + 1.3), 0.04, 0.04, steel, 6)
	mb.bevel_box(0, 0.62, z1 + 1.42, 0.1, 0.09, 0.24, dk, 0.02)
	var mi := mb.instance(); mi.position.y = -SINK; add_child(mi)
	# the tongue jack: wound down when it's parked, cranked up out of the way when it's on the truck
	var jm := MeshBuilder.new()
	jm.cyl(0.15, 0.2, z1 + 0.95, 0.04, 0.04, 0.55, dk, 8, true)
	jm.box(0.15, 0.2, z1 + 0.95, 0.18, 0.03, 0.18, dk)
	jm.cyl(0.15, 0.75, z1 + 0.95, 0.015, 0.015, 0.12, dk, 6, true)
	jack_mesh = jm.instance(); jack_mesh.position.y = -SINK; add_child(jack_mesh)
	# collision: floor and the four sides (same as the truck's bed), the tongue, and the jack
	_col(Vector3(0, 0.55, zc), Vector3(1.9, 0.5, L))
	for sx: float in [-1.0, 1.0]: _col(Vector3(sx * 0.93, 1.06, zc), Vector3(0.1, 0.62, L + 0.1))
	_col(Vector3(0, 1.06, z1 + 0.02), Vector3(1.9, 0.62, 0.08))
	_col(Vector3(0, 1.06, z0 - 0.02), Vector3(1.9, 0.62, 0.08))
	_col(Vector3(0, 0.62, z1 + 0.7), Vector3(0.3, 0.2, 1.4))
	jack_shape = CollisionShape3D.new(); var jb := BoxShape3D.new(); jb.size = Vector3(0.2, 0.36, 0.2)
	jack_shape.shape = jb; jack_shape.position = Vector3(0.15, 0.2 - SINK, z1 + 0.95)
	add_child(jack_shape)
	# the wheels (the drawn ones are part of the body; these carry it)
	for sx: float in [-1.0, 1.0]:
		var vw := VehicleWheel3D.new()
		vw.wheel_radius = 0.29
		vw.wheel_rest_length = 0.12
		vw.position = Vector3(sx * 1.08, 0.5 - SINK + 0.12, ax)
		vw.suspension_travel = 0.1
		vw.suspension_stiffness = 70.0
		vw.suspension_max_force = 26000.0
		vw.damping_compression = 3.0
		vw.damping_relaxation = 3.5
		vw.wheel_friction_slip = 3.0
		add_child(vw)
	_build_tarp()
	_set_jack(true)

func _col(c: Vector3, s: Vector3) -> void:
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = s
	cs.shape = bs; cs.position = c - Vector3(0, SINK, 0); add_child(cs)

func _set_jack(down: bool) -> void:
	jack_shape.disabled = not down
	jack_mesh.position.y = -SINK + (0.0 if down else 0.3)

## parked for good (at the cabin): a fixed piece of the scenery
func park_fixed() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true

## the bed's frame, matching the truck's local bed coordinates (for throwing, loading and counting)
func bed_xf() -> Transform3D:
	return global_transform * Transform3D(Basis(), Vector3(0, -SINK, 0))

## the middle of the bed, a little above the floor (for aiming at it)
func bed_mid() -> Vector3:
	return bed_xf() * Vector3(0, 1.1, (Z0 + Z1) / 2.0)

## is this point in the trailer? Anywhere over the bed counts, including a round piled up above the
## sides or leaning on one (it's in the trailer, it'll go home with you)
func in_bed(p: Vector3) -> bool:
	var l := bed_xf().affine_inverse() * p
	return absf(l.x) < 1.25 and l.z > Z0 - 0.25 and l.z < Z1 + 0.15 and l.y > 0.55 and l.y < 3.4

func coupler_world() -> Vector3:
	return global_transform * COUPLER

## the ball on the back, for the chipper
func hitch_world() -> Vector3:
	return global_transform * BALL

## back the truck up to it and drop the coupler on the ball: the trailer (and everything in it) swings
## round in line behind the truck, then the joint takes over
func hitch_to(t: Truck, cargo: Array = []) -> void:
	truck = t
	_clear_joint()
	add_collision_exception_with(t)
	var tb := t.global_transform.basis
	var yaw := atan2(tb.z.x, tb.z.z)
	var b := Basis(Vector3.UP, yaw)
	var target := Transform3D(b, t.hitch_world() - b * COUPLER)
	_move_to(target, cargo)
	joint = PinJoint3D.new()
	add_child(joint)
	joint.global_position = t.hitch_world()
	joint.node_a = t.get_path()
	joint.node_b = get_path()
	mode = "truck"
	_set_jack(false)

func unhitch() -> void:
	_clear_joint()
	mode = "free"
	_set_jack(true)
	linear_velocity = Vector3.ZERO; angular_velocity = Vector3.ZERO

func _clear_joint() -> void:
	if joint:
		joint.queue_free(); joint = null

## move the trailer to a new place, carrying what's in it along
func _move_to(target: Transform3D, cargo: Array) -> void:
	var delta := target * global_transform.affine_inverse()
	global_transform = target
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, target)
	linear_velocity = Vector3.ZERO; angular_velocity = Vector3.ZERO
	for b in cargo:
		if not is_instance_valid(b): continue
		var body := b as RigidBody3D
		body.global_transform = delta * body.global_transform
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
		body.linear_velocity = Vector3.ZERO; body.angular_velocity = Vector3.ZERO

## the truck's been moved (unstuck): bring the trailer back in line behind it, load and all
func follow_truck(cargo: Array = []) -> void:
	if mode == "truck" and truck: hitch_to(truck, cargo)

func _physics_process(_dt: float) -> void:
	brake = 300.0 if mode == "free" else 0.0
	# the strapped-down load goes wherever the trailer goes
	for s in strapped:
		var b = s[0]
		if not is_instance_valid(b) or not (b as RigidBody3D).freeze: continue
		(b as Node3D).global_transform = global_transform * (s[1] as Transform3D)

## a blue poly tarp shaped over what's actually in the bed (so it covers every log), draped down the
## sides to the rails, grommets and bungees to the stake pockets. Hinged at the front board so it can
## unroll toward the back. load: [[centre (bed frame), radius]] samples along each round in the bed.
func _build_tarp(load: Array = []) -> void:
	if tarp: tarp.queue_free()
	var mb := MeshBuilder.new()
	var blue := Color("#2f63b8"); var blue2 := Color("#264f96")
	var z0 := Z0; var z1 := Z1; var L := z1 - z0
	var nx := 12; var nz := 16
	var rail := 1.4
	var hw := 1.02                                   # half width over the rails
	# the height of the load over each point of the bed, with a little slack over the top
	var top_at := func(px: float, pz: float) -> float:
		var hgt := rail + 0.06
		for s in load:
			var c: Vector3 = s[0]; var rr: float = s[1] + 0.12
			var dx := px - c.x; var dz := pz - c.z
			var d2 := dx * dx + dz * dz
			if d2 < rr * rr: hgt = maxf(hgt, c.y + sqrt(rr * rr - d2) + 0.03)
		return hgt
	var ids := []
	var peak := rail
	for j in range(nz + 1):
		var row := []
		for i in range(nx + 1):
			var u := float(i) / nx * 2.0 - 1.0; var v := float(j) / nz
			var px := u * hw
			var pz := z1 + 0.03 - v * (L + 0.1)
			# over the middle it follows the load; toward the edges it drapes down to the rail
			var h: float = top_at.call(px * 0.8, pz)
			var edge := clampf((absf(u) - 0.8) / 0.2, 0.0, 1.0)
			var py := lerpf(h, rail - 0.25, edge * edge)
			py += 0.02 * sin(v * 11.0 + u * 4.0)
			peak = maxf(peak, py)
			var c := blue if (i + j) % 3 else blue2
			row.append(mb.v(Vector3(px, py, pz - z1), Vector3.UP, c))
		ids.append(row)
	for j in range(nz):
		for i in range(nx):
			mb.quad(ids[j][i], ids[j + 1][i], ids[j + 1][i + 1], ids[j][i + 1])
			mb.quad(ids[j][i], ids[j][i + 1], ids[j + 1][i + 1], ids[j + 1][i])
	# down over the front and back boards, from the top of the load
	var fh := (peak - (rail - 0.4))
	for zz: float in [0.06, -(L + 0.12)]:
		mb.box(0, rail - 0.4 + fh / 2, zz, 2.06, fh, 0.01, blue2)
	# grommets and bungees down to the stake pockets
	for sx: float in [-1.0, 1.0]:
		for k in range(7):
			var zz := -0.12 - k * (L - 0.24) / 6.0
			mb.sphere(sx * hw, rail - 0.25, zz, 0.025, 0.025, 0.025, Color("#c8ccd0"), 6, 4)
			mb.tube(Vector3(sx * hw, rail - 0.25, zz), Vector3(sx * 0.97, 0.88, zz), 0.012, 0.012, Color("#d84020") if k % 2 else Color("#202020"), 4)
	tarp = Node3D.new(); tarp.position = Vector3(0, -SINK, z1)
	var ti := mb.instance(); ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	tarp.add_child(ti)
	tarp.visible = false
	add_child(tarp)

## the rounds in the bed as [centre in the bed frame, radius] samples along each one
func _load_samples(cargo: Array) -> Array:
	var out := []
	var inv := bed_xf().affine_inverse()
	for b in cargo:
		if not is_instance_valid(b) or not (b is WoodPiece): continue
		var wp := b as WoodPiece
		if wp.kind != "trunk": continue
		for k in range(5):
			var y := lerpf(wp.y0, wp.y1, (k + 0.5) / 5.0)
			out.append([inv * wp.to_world(Vector3(0, y, 0)), Wood.r_at(wp.T, y)])
	return out

## pull the tarp over the load: it unrolls from the front to the back
func tarp_it(on_done: Callable = Callable(), cargo: Array = []) -> void:
	if tarped: return
	tarped = true
	strapped = []
	for b in cargo:
		if is_instance_valid(b):
			strapped.append([b, global_transform.affine_inverse() * (b as Node3D).global_transform])
			add_collision_exception_with(b)          # strapped down, it rides with the trailer instead of pushing on it
	_build_tarp(_load_samples(cargo))
	tarp.visible = true
	tarp.scale = Vector3(1, 1, 0.02)
	var tw := create_tween()
	tw.tween_property(tarp, "scale", Vector3(1, 1, 1), 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if on_done.is_valid(): tw.tween_callback(on_done)

## already tarped (at home, or the moment you load in): a full load, mounded up
func set_tarped() -> void:
	tarped = true
	var mound := []
	for k in range(6): mound.append([Vector3(0, 1.05, Z1 - 0.4 - k * (Z1 - Z0 - 0.8) / 5.0), 0.55])
	_build_tarp(mound)
	tarp.visible = true; tarp.scale = Vector3.ONE
