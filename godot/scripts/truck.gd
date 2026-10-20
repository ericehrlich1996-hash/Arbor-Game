## The '80s square-body: a real VehicleBody3D. Solid cab and bed (logs ride in it, you can stand in it),
## see-through tailgate, rear-view mirror rendered live, cab and chase cameras.
class_name Truck
extends VehicleBody3D

signal exited

var driving := false
var chase := false
var look_yaw := 0.0
var look_pitch := 0.0
var cab_cam: Camera3D
var chase_cam: Camera3D
var mirror_vp: SubViewport
var mirror_cam: Camera3D
var mirror_quad: MeshInstance3D
var wheels: Array[VehicleWheel3D] = []
var paint := {}
var engine_snd = null
var _still_t := 0.0
var mirror_live := false        # the mirror is redrawn a few times a second while someone's driving
var _mirror_n := 0
var mirror_div := 3             # redraw the mirror every Nth frame
var _last_pos := Vector3.ZERO

const BED_FLOOR_Y := 0.8

func setup(rng: RandomNumberGenerator) -> void:
	collision_layer = 4
	collision_mask = 1 | 4 | 8 | 64
	mass = 1700.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.38, 0.3)
	angular_damp = 0.6
	continuous_cd = true
	var m := Models.truck(rng)
	paint = m
	var mesh := ArrayMesh.new()
	for part in [[m.paint, Mats.truck_paint], [m.chrome, Mats.truck_chrome], [m.dark, Mats.vcol], [m.lamps, Mats.lamp]]:
		var mb: MeshBuilder = part[0]
		if mb.is_empty(): continue
		mb.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, part[1])
	var body := MeshInstance3D.new(); body.mesh = mesh; body.name = "Body"; add_child(body)
	driver = _driver_mb().instance(); driver.name = "Driver"; driver.visible = false; add_child(driver)
	var tg: MeshInstance3D = m.tailgate.instance(Mats.vcol_glass); tg.name = "Tailgate"
	tg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tg)
	_build_gauges()
	var gl: MeshInstance3D = m.glass.instance(Mats.truck_glass); gl.name = "Glass"
	gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gl)
	# collision: front clip, cab, bed floor, bed walls, tailgate, chassis
	_box(Vector3(0, 0.95, 1.62), Vector3(2.0, 0.75, 1.9))
	_box(Vector3(0, 1.35, 0.05), Vector3(2.0, 1.25, 1.46))
	_box(Vector3(0, 0.55, -1.69), Vector3(1.9, 0.5, 1.9))           # bed floor, top at 0.8
	for sx in [-1.0, 1.0]:
		_box(Vector3(sx * 0.97, 1.05, -1.69), Vector3(0.1, 0.6, 1.9))
	_box(Vector3(0, 1.05, -0.73), Vector3(1.9, 0.6, 0.06))
	_box(Vector3(0, 1.0, -2.62), Vector3(2.0, 0.62, 0.08))
	_box(Vector3(0, 0.5, -2.85), Vector3(2.0, 0.2, 0.3))             # rear bumper
	# wheels
	var wmesh := Models.wheel().commit()
	for w in [[1, Models.FRONT_AXLE, true], [-1, Models.FRONT_AXLE, true], [1, Models.REAR_AXLE, false], [-1, Models.REAR_AXLE, false]]:
		var vw := VehicleWheel3D.new()
		vw.position = Vector3(w[0] * Models.TRACK, Models.WHEEL_R + 0.2, w[1])
		vw.wheel_radius = Models.WHEEL_R
		vw.wheel_rest_length = 0.2
		vw.suspension_travel = 0.2
		vw.suspension_stiffness = 46.0
		vw.suspension_max_force = 20000.0
		vw.damping_compression = 3.6
		vw.damping_relaxation = 4.2
		vw.wheel_friction_slip = 3.4
		vw.wheel_roll_influence = 0.05
		vw.use_as_steering = w[2]
		vw.use_as_traction = not w[2]
		var wm := MeshInstance3D.new(); wm.mesh = wmesh; wm.material_override = Mats.vcol
		if w[0] > 0: wm.rotation.y = PI
		vw.add_child(wm)
		add_child(vw)
		wheels.append(vw)
	# cameras
	cab_cam = Camera3D.new(); cab_cam.name = "CabCam"
	cab_cam.position = Models.EYE
	cab_cam.rotation = Vector3(0, PI, 0)
	cab_cam.fov = Settings.fov + 2.0; cab_cam.near = 0.03
	add_child(cab_cam)
	chase_cam = Camera3D.new(); chase_cam.name = "ChaseCam"; chase_cam.fov = 65
	chase_cam.top_level = true
	add_child(chase_cam)
	# rear-view mirror: a camera just behind the cab looking back, rendered into the mirror glass
	mirror_vp = SubViewport.new()
	mirror_vp.size = Vector2i(360, 120)
	mirror_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(mirror_vp)
	mirror_cam = Camera3D.new(); mirror_cam.fov = 28; mirror_cam.near = 0.1; mirror_cam.far = 160
	mirror_cam.cull_mask = 1             # no grass, ferns or flowers in the mirror: you'd never see them
	mirror_vp.add_child(mirror_cam)
	mirror_quad = MeshInstance3D.new()
	var qm := QuadMesh.new(); qm.size = Vector2(0.37, 0.12)
	mirror_quad.mesh = qm
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_texture = mirror_vp.get_texture()
	mm.uv1_scale = Vector3(-1, 1, 1)     # a mirror shows the world flipped left-right
	mm.uv1_offset = Vector3(1, 0, 0)
	mirror_quad.material_override = mm
	mirror_quad.position = Vector3(0, 1.79, 0.468)
	mirror_quad.rotation.y = PI          # glass faces the driver (−Z)
	mirror_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mirror_quad)

func _box(center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new(); b.size = size
	cs.shape = b; cs.position = center
	add_child(cs)

## set it back on its wheels where it lies, still facing the same way
func right_up(w: WorldGen) -> void:
	var fwd := global_transform.basis.z; fwd.y = 0
	if fwd.length() < 0.1: fwd = global_transform.basis.y; fwd.y = 0
	if fwd.length() < 0.1: fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var p := global_position
	var gy: float = w.H(p.x, p.z) if w else p.y
	freeze = false
	linear_velocity = Vector3.ZERO; angular_velocity = Vector3.ZERO
	var xf := Transform3D(Basis.looking_at(-fwd, Vector3.UP), Vector3(p.x, gy + 0.35, p.z))
	global_transform = xf
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	_still_t = 0.0

func hitch_world() -> Vector3:
	return global_transform * Models.HITCH

func bed_local(p: Vector3) -> Vector3:
	return global_transform.affine_inverse() * p

func in_bed(p: Vector3) -> bool:
	var l := bed_local(p)
	return absf(l.x) < 1.0 and l.z > -2.7 and l.z < -0.7 and l.y > 0.6 and l.y < 3.0

func enter() -> void:
	freeze = false
	_still_t = 0.0
	driving = true
	look_yaw = 0; look_pitch = 0
	_set_cam()
	mirror_live = true
	mirror_div = 3

func exit() -> void:
	driving = false
	engine_force = 0; brake = 30.0; steering = 0
	mirror_live = false
	exited.emit()

func _set_cam() -> void:
	if chase: chase_cam.make_current()
	else: cab_cam.make_current()

func toggle_cam() -> void:
	chase = not chase
	_set_cam()

func speed_mph() -> float:
	return linear_velocity.length() * 2.237

# ---------------------------------------------------------------- the gauges
## The two dials on the dash, either side of the column (the body is built mirrored, so they're at +x here):
## the speedometer (0 to 60 mph) on the left and the tachometer (0 to 5,000 rpm) on the right, as you sit.
## Each gets its tick marks and numbers, and a red needle that's turned every frame.
const GAUGE_Y := 1.2
const GAUGE_Z := 0.41               # just in front of the dial faces (they face back toward the seat)
const SWEEP := 4.71                  # 270 degrees, from lower left round to lower right
var speedo_needle: Node3D
var tach_needle: Node3D
var _speedo_a := 0.0
var _tach_a := 0.0
var _rpm := 0.0
var _thr := 0.0
func _build_gauges() -> void:
	var mb := MeshBuilder.new()
	var ink := Color("#1a1a1a"); var red := Color("#c0392b")
	for g in [[0.52, 60.0, 10.0, 20.0], [0.28, 5.0, 1.0, 1.0]]:
		var gx: float = g[0]; var top: float = g[1]; var step: float = g[2]; var lab: float = g[3]
		var n := int(round(top / step))
		for k in range(n * 2 + 1):
			var th := -SWEEP / 2.0 + SWEEP * k / (n * 2)
			var major := k % 2 == 0
			var ln := 0.014 if major else 0.008
			var r := 0.06 - ln / 2.0
			mb.push(Transform3D(Basis(Vector3.BACK, th), Vector3(gx, GAUGE_Y, GAUGE_Z + 0.003)))
			mb.box(0, r, 0, 0.003 if major else 0.002, ln, 0.002, red if (gx < 0.4 and k >= n * 2 - 1) else ink)
			mb.pop()
		var v := 0.0
		while v <= top + 0.001:
			var th := -SWEEP / 2.0 + SWEEP * v / top
			var lb := Label3D.new()
			lb.text = str(int(v))
			lb.font_size = 40; lb.pixel_size = 0.0004; lb.outline_size = 0
			lb.modulate = ink
			lb.position = Vector3(gx - sin(th) * 0.041, GAUGE_Y + cos(th) * 0.041, GAUGE_Z - 0.001)
			lb.rotation = Vector3(0, PI, 0)                     # facing back at the driver
			add_child(lb)
			v += lab
		var unit := Label3D.new()
		unit.text = "MPH" if gx > 0.4 else "RPM x1000"
		unit.font_size = 28; unit.pixel_size = 0.0004; unit.outline_size = 0; unit.modulate = Color("#555555")
		unit.position = Vector3(gx, GAUGE_Y - 0.03, GAUGE_Z - 0.001); unit.rotation = Vector3(0, PI, 0)
		add_child(unit)
	var faces := mb.instance(); faces.name = "GaugeMarks"; faces.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(faces)
	for gx: float in [0.52, 0.28]:
		var pivot := Node3D.new(); pivot.position = Vector3(gx, GAUGE_Y, GAUGE_Z - 0.003)
		var nm := MeshBuilder.new()
		nm.box(0, 0.024, 0, 0.0035, 0.058, 0.002, red)
		nm.box(0, -0.006, 0, 0.0035, 0.014, 0.002, red)
		nm.cyl(0, -0.002, 0, 0.007, 0.007, 0.004, Color("#2a2a2a"), 10, true)
		var mi := nm.instance(); mi.rotation = Vector3(PI / 2, 0, 0)       # the cap's cylinder faces the driver
		mi.rotation = Vector3.ZERO
		pivot.add_child(mi)
		add_child(pivot)
		if gx > 0.4: speedo_needle = pivot
		else: tach_needle = pivot
	_set_needles(0.0, 0.0)

func _set_needles(mph: float, rpm: float) -> void:
	if speedo_needle: speedo_needle.rotation = Vector3(0, 0, -SWEEP / 2.0 + SWEEP * clampf(mph / 60.0, 0.0, 1.0))
	if tach_needle: tach_needle.rotation = Vector3(0, 0, -SWEEP / 2.0 + SWEEP * clampf(rpm / 5000.0, 0.0, 1.0))

## the engine's revs: idling when you're in the cab, climbing through three gears as the truck picks up speed,
## a bit higher with your foot down; off when you're out of it
func _gauges_step(dt: float) -> void:
	var mph := absf(linear_velocity.dot(global_transform.basis.z)) * 2.237
	var want := 0.0
	if driving:
		var gears := [[0.0, 11.0], [11.0, 21.0], [21.0, 40.0]]
		var gear: Array = gears[0]
		for gr in gears:
			if mph >= gr[0]: gear = gr
		var frac := clampf((mph - float(gear[0])) / (float(gear[1]) - float(gear[0])), 0.0, 1.0)
		want = 750.0 + frac * 3300.0 + absf(_thr) * (500.0 if mph < 1.0 else 350.0) + sin(Time.get_ticks_msec() * 0.031) * 25.0
		if mph > 0.5 and float(gear[0]) > 0.0: want = maxf(want, 1500.0)
	_rpm = lerpf(_rpm, want, minf(1.0, dt * 6.0))
	_speedo_a = lerpf(_speedo_a, mph, minf(1.0, dt * 8.0))
	_set_needles(_speedo_a, _rpm)

## you, behind the wheel: only drawn from the chase camera (in the cab you're looking out of your own eyes)
var driver: MeshInstance3D

func _driver_mb() -> MeshBuilder:
	var mb := MeshBuilder.new()
	var shirt := Color("#4f6b3a"); var pants := Color("#5a4a36"); var glove := Color("#c8a46a"); var skin := Color("#e0b090")
	var helmet := Color("#e8701e"); var muff := Color("#2e3236"); var boot := Color("#4a3624")
	var x := Models.EYE.x                                # in the driver's seat, where the cab camera sits behind the wheel
	var hip := Vector3(x, 0.86, -0.28); var sh_y := 1.33; var sh_z := -0.36
	# legs: thighs forward along the seat, shins down to the pedals
	for sx: float in [-1.0, 1.0]:
		var h := hip + Vector3(sx * 0.1, 0, 0)
		var knee := Vector3(x + sx * 0.11, 0.9, 0.12)
		var foot := Vector3(x + sx * 0.12, 0.74, 0.34)
		mb.tube(h, knee, 0.075, 0.065, pants, 8, true)
		mb.tube(knee, foot, 0.06, 0.05, pants, 8, true)
		mb.box(foot.x, foot.y - 0.02, foot.z + 0.05, 0.1, 0.07, 0.2, boot)
	# torso, leaning back into the bench a touch
	mb.tube(hip + Vector3(0, 0.02, 0), Vector3(x, sh_y - 0.05, sh_z), 0.17, 0.19, shirt, 10, true)
	mb.sphere(x, sh_y - 0.04, sh_z, 0.2, 0.08, 0.13, shirt, 10, 6)
	# arms out to the wheel at ten and two
	for sx: float in [-1.0, 1.0]:
		var s0 := Vector3(x + sx * 0.2, sh_y - 0.06, sh_z)
		var elbow := Vector3(x + sx * 0.25, 1.05, -0.05)
		var hand := Vector3(x + sx * 0.15, 1.2, 0.34)
		mb.tube(s0, elbow, 0.05, 0.045, shirt, 8, true)
		mb.tube(elbow, hand, 0.045, 0.04, shirt, 8, true)
		mb.sphere(hand.x, hand.y, hand.z, 0.045, 0.045, 0.05, glove, 8, 5)
	# neck and head, hard hat and ear muffs
	var head := Vector3(x, Models.EYE.y + 0.02, sh_z + 0.08)
	mb.tube(Vector3(x, sh_y, sh_z + 0.02), head + Vector3(0, -0.1, 0), 0.05, 0.05, skin, 8)
	mb.sphere(head.x, head.y, head.z, 0.1, 0.12, 0.11, skin, 12, 8)
	mb.sphere(head.x, head.y + 0.08, head.z - 0.01, 0.135, 0.09, 0.15, helmet, 12, 6)
	mb.cyl(head.x, head.y + 0.03, head.z - 0.01, 0.16, 0.16, 0.015, helmet, 14, true)
	for sx: float in [-1.0, 1.0]:
		mb.sphere(head.x + sx * 0.11, head.y - 0.01, head.z, 0.035, 0.055, 0.05, muff, 8, 5)
	return mb

func _physics_process(dt: float) -> void:
	if driver: driver.visible = driving and chase
	var fwd := global_transform.basis.z
	var v := linear_velocity.dot(fwd)
	if driving:
		var thr := Input.get_axis("move_back", "move_fwd")
		_thr = thr
		var st := Input.get_axis("move_right", "move_left")
		steering = move_toward(steering, st * (0.55 if absf(v) < 6 else 0.3), dt * 2.0)
		var want_brake := Input.is_action_pressed("jump")
		if thr > 0 and v < -0.5 or thr < 0 and v > 0.5:
			engine_force = 0; brake = 40.0       # pressing against the motion brakes first
		elif thr != 0:
			brake = 0.0
			var cap := 15.0 if thr > 0 else 4.0      # ~33 mph forward, slow in reverse
			engine_force = thr * (3600.0 if absf(v) < cap else 0.0)
		else:
			engine_force = 0; brake = 6.0           # engine braking / rolling resistance
		if want_brake: brake = 60.0; engine_force = 0
	else:
		engine_force = 0
		brake = 400.0
		# parked: as soon as it's rolled to a stop on its wheels, pin it, so logs thrown in (or a pile it's
		# backed against) can't rock it, creep it or flip it; and failing that, once it stops drifting
		if not freeze and linear_velocity.length() < 0.6 and angular_velocity.length() < 0.4 and global_transform.basis.y.y > 0.85:
			freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			freeze = true
		_still_t += dt
		if _still_t > 0.5:
			if global_position.distance_to(_last_pos) < 0.06 and not freeze:
				freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				freeze = true
			_last_pos = global_position
			_still_t = 0.0

func _process(dt: float) -> void:
	_gauges_step(dt)
	# the rear-view mirror is a second render of the world: only refresh it every third frame
	if mirror_live:
		_mirror_n += 1
		if _mirror_n % mirror_div == 0: mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if driving:
		cab_cam.rotation = Vector3(look_pitch, PI + look_yaw, 0)
		var back := -global_transform.basis.z
		back.y = 0; back = back.normalized()
		var yaw := atan2(back.x, back.z) + look_yaw
		var eye := global_position + Vector3(sin(yaw), 0, cos(yaw)) * 12.0 + Vector3(0, 5.0, 0)
		chase_cam.global_position = eye
		chase_cam.look_at(global_position + Vector3(0, 1.2, 0))
	# the mirror camera rides just behind the cab, above the roof line, looking back
	mirror_cam.global_transform = global_transform * Transform3D(Basis(Vector3.RIGHT, -0.08), Vector3(0, 2.05, -0.85))

func look(dx: float, dy: float) -> void:
	look_yaw = clampf(look_yaw - dx, -2.2, 2.2)
	look_pitch = clampf(look_pitch - dy, -0.9, 0.7)
