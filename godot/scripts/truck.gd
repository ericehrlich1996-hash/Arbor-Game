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
	for part in [[m.paint, Mats.paint], [m.chrome, Mats.chrome], [m.dark, Mats.vcol], [m.lamps, Mats.lamp]]:
		var mb: MeshBuilder = part[0]
		if mb.is_empty(): continue
		mb.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, part[1])
	var body := MeshInstance3D.new(); body.mesh = mesh; body.name = "Body"; add_child(body)
	var tg: MeshInstance3D = m.tailgate.instance(Mats.vcol_glass); tg.name = "Tailgate"
	tg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tg)
	var gl: MeshInstance3D = m.glass.instance(Mats.glass); gl.name = "Glass"
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
	cab_cam.fov = 72; cab_cam.near = 0.03
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

func _physics_process(dt: float) -> void:
	var fwd := global_transform.basis.z
	var v := linear_velocity.dot(fwd)
	if driving:
		var thr := Input.get_axis("move_back", "move_fwd")
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
	# the rear-view mirror is a second render of the world: only refresh it every third frame
	if mirror_live:
		_mirror_n += 1
		if _mirror_n % 3 == 0: mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
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
