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
var remote_driver := 0             # a crew member driving it from their computer (their inputs come over the line)
var remote_in := {}                # {thr, st, br} from them
var show_driver := false           # somebody else is at the wheel: draw them in the seat

static var BED_FLOOR_Y := 0.8         # (the Meshy truck's bed sits lower: set in setup)

## the modelled truck (art/truck_meshy2.py): Meshy's textured body, the new steering wheel and gauge faces, the
## windshield glass and its four wheels, already in this truck's frame. Where it's missing, the truck is built in
## code (Models.truck) as before.
const MODEL := "res://models/truck.glb"
const M_WHEEL_R := 0.38
const M_TRACK := 0.804
const M_BED_Y := 0.487
# the two big dials on the gauge faces (they're painted without needles; these are driven)
const M_SPEEDO := Vector3(0.3866, 1.3285, 0.667)
const M_TACH := Vector3(0.3109, 1.3285, 0.667)
const M_DIAL_R := 0.047
const M_MIRROR := Vector3(-0.008, 1.739, 0.517)
var modeled := false
var _model_wheels := {}          # f1 / f0 / r1 / r0 (front or rear, on the +x or -x side)

## the model's parts, ready to add: the body recoloured to this truck's paint and on the game's paint, chrome
## and lamp shaders, the interior as it comes, and the wheel
const USE_MODEL := false        # the code-built square-body is the truck; the Meshy model stays on disk unused
func _load_model(c1: Color) -> Dictionary:
	if not USE_MODEL or not ResourceLoader.exists(MODEL): return {}
	var root: Node = (load(MODEL) as PackedScene).instantiate()
	var out := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		out[String(mi.name).to_lower()] = (mi as MeshInstance3D).mesh
	root.free()
	if not (out.has("body") and out.has("interior")): return {}
	if out.has("wheel_f1"):
		# Meshy's textured truck: the body on its own textures (through the rust shader), the wheels as they come
		var tex_body: Mesh = out.body
		var bm := ArrayMesh.new()
		for si in tex_body.get_surface_count():
			bm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tex_body.surface_get_arrays(si))
			var sm := tex_body.surface_get_material(si) as StandardMaterial3D
			if sm:
				Mats.truck_tex.set_shader_parameter("albedo_tex", sm.albedo_texture)
				if sm.metallic_texture:
					Mats.truck_tex.set_shader_parameter("orm_tex", sm.metallic_texture); Mats.truck_tex.set_shader_parameter("has_orm", true)
				if sm.normal_enabled and sm.normal_texture:
					Mats.truck_tex.set_shader_parameter("normal_tex", sm.normal_texture); Mats.truck_tex.set_shader_parameter("has_normal", true)
			bm.surface_set_material(si, Mats.truck_tex)
		var res := {body = bm, interior = out.interior, wheels = {}}
		for k in ["f1", "f0", "r1", "r0"]:
			var wsrc: Mesh = out["wheel_" + k]
			var wm := ArrayMesh.new()
			for si in wsrc.get_surface_count():
				wm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wsrc.surface_get_arrays(si))
				wm.surface_set_material(si, Mats.truck_tex)
			res.wheels[k] = wm
		if out.has("glass"): res.glass = out.glass
		return res
	if not out.has("wheel"): return {}
	var src: Mesh = out.body
	var body := ArrayMesh.new()
	for si in src.get_surface_count():
		var arr: Array = src.surface_get_arrays(si)
		var mname := String(src.surface_get_material(si).resource_name).to_lower() if src.surface_get_material(si) else ""
		var n: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		if cols.size() != n:
			cols = PackedColorArray(); cols.resize(n); cols.fill(Color(0.2, 0.2, 0.2))
		var mat: Material = Mats.vcol
		if mname.begins_with("paint"):
			cols.fill(c1); mat = Mats.truck_paint
		elif mname.begins_with("chrome"): mat = Mats.truck_chrome
		elif mname.begins_with("lamp"): mat = Mats.lamp
		arr[Mesh.ARRAY_COLOR] = cols
		body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		body.surface_set_material(body.get_surface_count() - 1, mat)
	var wsrc: Mesh = out.wheel
	var wheel := ArrayMesh.new()
	for si in wsrc.get_surface_count():
		var arr: Array = wsrc.surface_get_arrays(si)
		wheel.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		wheel.surface_set_material(wheel.get_surface_count() - 1, Mats.vcol if arr[Mesh.ARRAY_COLOR] != null else wsrc.surface_get_material(si))
	return {body = body, interior = out.interior, wheel = wheel}

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
	var M := _load_model(m.c1)
	modeled = not M.is_empty()
	if modeled:
		var body := MeshInstance3D.new(); body.mesh = M.body; body.name = "Body"; add_child(body)
		var cab := MeshInstance3D.new(); cab.mesh = M.interior; cab.name = "Interior"; add_child(cab)
		cab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_model_wheels = M.wheels if M.has("wheels") else {f1 = M.wheel, f0 = M.wheel, r1 = M.wheel, r0 = M.wheel}
		if M.has("glass"):
			var gl := MeshInstance3D.new(); gl.mesh = M.glass; gl.name = "Glass"; gl.material_override = Mats.truck_glass
			gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(gl)
		BED_FLOOR_Y = M_BED_Y
	else:
		var mesh := ArrayMesh.new()
		for part in [[m.paint, Mats.truck_paint], [m.chrome, Mats.truck_chrome], [m.dark, Mats.vcol], [m.lamps, Mats.lamp]]:
			var mb: MeshBuilder = part[0]
			if mb.is_empty(): continue
			mb.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, part[1])
		var body := MeshInstance3D.new(); body.mesh = mesh; body.name = "Body"; add_child(body)
		BED_FLOOR_Y = 0.8
	driver = _driver_mb().instance(); driver.name = "Driver"; driver.visible = false; add_child(driver)
	if not modeled:
		var tg: MeshInstance3D = m.tailgate.instance(Mats.vcol_glass); tg.name = "Tailgate"
		tg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tg)
	_build_gauges()
	if not modeled:
		var gl: MeshInstance3D = m.glass.instance(Mats.truck_glass); gl.name = "Glass"
		gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(gl)
	# collision: front clip, cab, bed floor, bed walls, tailgate, chassis
	_box(Vector3(0, 0.95, 1.62), Vector3(2.0, 0.75, 1.9))
	_box(Vector3(0, 1.35, 0.05), Vector3(2.0, 1.25, 1.46))
	var bed_t := 0.5 if not modeled else 0.12                        # (the Meshy bed sits low: keep its floor clear of the road)
	_box(Vector3(0, BED_FLOOR_Y - bed_t / 2.0, -1.69), Vector3(1.9, bed_t, 1.9))           # bed floor
	for sx in [-1.0, 1.0]:
		_box(Vector3(sx * 0.97, 1.05, -1.69), Vector3(0.1, 0.6, 1.9))
	_box(Vector3(0, 1.05, -0.73), Vector3(1.9, 0.6, 0.06))
	_box(Vector3(0, 1.0, -2.62), Vector3(2.0, 0.62, 0.08))
	_box(Vector3(0, 0.5, -2.85), Vector3(2.0, 0.2, 0.3))             # rear bumper
	# wheels
	var wmesh: Mesh = null if modeled else Models.wheel().commit()
	var per_corner := modeled and M.has("wheels")
	var wr := M_WHEEL_R if modeled else Models.WHEEL_R
	var trk := M_TRACK if modeled else Models.TRACK
	for w in [[1, Models.FRONT_AXLE, true], [-1, Models.FRONT_AXLE, true], [1, Models.REAR_AXLE, false], [-1, Models.REAR_AXLE, false]]:
		var vw := VehicleWheel3D.new()
		vw.position = Vector3(w[0] * trk, wr + 0.2, w[1])
		vw.wheel_radius = wr
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
		var wm := MeshInstance3D.new()
		if modeled: wm.mesh = _model_wheels[("f" if w[2] else "r") + ("1" if w[0] > 0 else "0")]
		else: wm.mesh = wmesh
		if not modeled: wm.material_override = Mats.vcol
		if w[0] > 0 and not per_corner: wm.rotation.y = PI
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
	var qm := QuadMesh.new(); qm.size = Vector2(0.27, 0.075) if modeled else Vector2(0.37, 0.12)
	mirror_quad.mesh = qm
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_texture = mirror_vp.get_texture()
	mm.uv1_scale = Vector3(-1, 1, 1)     # a mirror shows the world flipped left-right
	mm.uv1_offset = Vector3(1, 0, 0)
	mirror_quad.material_override = mm
	mirror_quad.position = M_MIRROR if modeled else Vector3(0, 1.79, 0.468)
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
	return absf(l.x) < 1.0 and l.z > -2.7 and l.z < -0.7 and l.y > BED_FLOOR_Y - 0.08 and l.y < 3.0

func enter(remote := false) -> void:
	freeze = false
	_still_t = 0.0
	driving = true
	look_yaw = 0; look_pitch = 0
	if remote: return
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
const GAUGE_Y := 1.215
const GAUGE_Z := 0.41               # just in front of the dial faces (they face back toward the seat)
const SPEEDO_X := 0.5
const TACH_X := 0.3
const FUEL_X := 0.66
const TEMP_X := 0.14
const SWEEP := 4.71                  # 270 degrees, from lower left round to lower right
const SMALL_SWEEP := 1.7             # the little fuel and temp dials swing about 100 degrees
static var odometer := 84213.4       # miles; carried from job to job while the game's running
var speedo_needle: Node3D
var tach_needle: Node3D
var fuel_needle: Node3D
var temp_needle: Node3D
var gear_mark: Node3D
var odo_label: Label3D
var _speedo_a := 0.0
var _tach_a := 0.0
var _rpm := 0.0
var _thr := 0.0
var _fuel := 0.62
var _temp := 0.25
var _gear := "P"
func _label(text: String, pos: Vector3, size: int, col: Color) -> Label3D:
	var lb := Label3D.new()
	lb.text = text
	lb.font_size = size; lb.pixel_size = 0.0004; lb.outline_size = 0
	lb.modulate = col
	lb.position = pos
	lb.rotation = Vector3(0, PI, 0)                     # facing back at the driver
	lb.shaded = false; lb.double_sided = false
	add_child(lb)
	return lb

func _needle(at: Vector3, length: float, col: Color) -> Node3D:
	var pivot := Node3D.new(); pivot.position = at
	var nm := MeshBuilder.new()
	nm.box(0, length * 0.4, 0, 0.0035, length, 0.002, col)
	nm.box(0, -length * 0.12, 0, 0.0035, length * 0.25, 0.002, col)
	nm.cyl(0, -0.002, 0, 0.0075, 0.0075, 0.004, Color("#2a2a2a"), 10, true)
	var mi := nm.instance(); mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mi)
	add_child(pivot)
	return pivot

func _build_gauges() -> void:
	if modeled:
		for e in [[M_SPEEDO, true], [M_TACH, false]]:
			var pivot := Node3D.new(); pivot.position = e[0]
			var nm := MeshBuilder.new()
			var L := M_DIAL_R * 0.82
			nm.box(0, L * 0.42, 0, 0.0028, L * 1.0, 0.0015, Color("#e0301e"))
			nm.cyl(0, -0.001, 0, 0.0045, 0.0045, 0.003, Color("#2a2a2a"), 10, true)
			var mi := nm.instance(); pivot.add_child(mi)
			add_child(pivot)
			if e[1]: speedo_needle = pivot
			else: tach_needle = pivot
		_set_needles(0.0, 0.0)
		return
	var mb := MeshBuilder.new()
	var ink := Color("#1a1a1a"); var red := Color("#c0392b"); var grey := Color("#555555")
	var fz := GAUGE_Z + 0.004
	for g in [[SPEEDO_X, 60.0, 5.0, 10.0], [TACH_X, 5.0, 0.5, 1.0]]:
		var gx: float = g[0]; var top: float = g[1]; var step: float = g[2]; var lab: float = g[3]
		var n := int(round(top / step))
		for k in range(n + 1):
			var th := -SWEEP / 2.0 + SWEEP * k / n
			var major := is_equal_approx(fmod(k * step, lab), 0.0) or is_equal_approx(fmod(k * step, lab), lab)
			var ln := 0.015 if major else 0.008
			var r := 0.064 - ln / 2.0
			mb.push(Transform3D(Basis(Vector3.BACK, th), Vector3(gx, GAUGE_Y, fz)))
			mb.box(0, r, 0, 0.0035 if major else 0.002, ln, 0.002, red if (gx == TACH_X and k * step >= 4.0) else ink)
			mb.pop()
		var v := 0.0
		while v <= top + 0.001:
			var th := -SWEEP / 2.0 + SWEEP * v / top
			_label(str(int(v)), Vector3(gx - sin(th) * 0.043, GAUGE_Y + cos(th) * 0.043, GAUGE_Z - 0.001), 44, red if (gx == TACH_X and v >= 4.0) else ink)
			v += lab
		_label("MPH" if gx == SPEEDO_X else "RPM x1000", Vector3(gx, GAUGE_Y + 0.02, GAUGE_Z - 0.001), 26, grey)
	# red line arc on the tach
	for k in range(8):
		var th := -SWEEP / 2.0 + SWEEP * (0.8 + 0.2 * k / 8.0)
		mb.push(Transform3D(Basis(Vector3.BACK, th), Vector3(TACH_X, GAUGE_Y, fz)))
		mb.box(0, 0.066, 0, 0.0085, 0.004, 0.002, red)
		mb.pop()
	# odometer window on the speedo
	mb.box(SPEEDO_X, GAUGE_Y - 0.036, fz - 0.0015, 0.05, 0.013, 0.001, Color("#111111"))
	odo_label = _label("", Vector3(SPEEDO_X, GAUGE_Y - 0.036, GAUGE_Z - 0.002), 26, Color("#e8e2cc"))
	# the shift quadrant on the tach: P R N D 2 1 and an orange marker under the gear you're in
	var gears := ["P", "R", "N", "D", "2", "1"]
	for k in range(gears.size()):
		_label(gears[k], Vector3(TACH_X + 0.025 - k * 0.01, GAUGE_Y - 0.036, GAUGE_Z - 0.001), 22, ink)
	gear_mark = Node3D.new()
	var gm := MeshBuilder.new(); gm.box(0, 0, 0, 0.008, 0.002, 0.001, Color("#ff7a1a"))
	gear_mark.add_child(gm.instance()); add_child(gear_mark)
	# the little dials: fuel (E to F) and temperature (C to H)
	for s in [[FUEL_X, "E", "F", "FUEL"], [TEMP_X, "C", "H", "TEMP"]]:
		var gx: float = s[0]
		for k in range(5):
			var th := -SMALL_SWEEP / 2.0 + SMALL_SWEEP * k / 4.0
			mb.push(Transform3D(Basis(Vector3.BACK, th), Vector3(gx, GAUGE_Y - 0.008, fz)))
			mb.box(0, 0.024, 0, 0.0025, 0.008 if k % 2 == 0 else 0.005, 0.002, red if ((s[1] == "E" and k == 0) or (s[1] == "C" and k == 4)) else ink)
			mb.pop()
		var tl := -SMALL_SWEEP / 2.0; var tr := SMALL_SWEEP / 2.0
		_label(s[1], Vector3(gx - sin(tl) * 0.019, GAUGE_Y - 0.008 + cos(tl) * 0.019 - 0.006, GAUGE_Z - 0.001), 24, ink)
		_label(s[2], Vector3(gx - sin(tr) * 0.019, GAUGE_Y - 0.008 + cos(tr) * 0.019 - 0.006, GAUGE_Z - 0.001), 24, ink)
		_label(s[3], Vector3(gx, GAUGE_Y - 0.02, GAUGE_Z - 0.001), 16, grey)
	var faces := mb.instance(); faces.name = "GaugeMarks"; faces.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(faces)
	speedo_needle = _needle(Vector3(SPEEDO_X, GAUGE_Y, GAUGE_Z - 0.003), 0.058, red)
	tach_needle = _needle(Vector3(TACH_X, GAUGE_Y, GAUGE_Z - 0.003), 0.058, red)
	fuel_needle = _needle(Vector3(FUEL_X, GAUGE_Y - 0.008, GAUGE_Z - 0.003), 0.022, red)
	temp_needle = _needle(Vector3(TEMP_X, GAUGE_Y - 0.008, GAUGE_Z - 0.003), 0.022, red)
	_set_needles(0.0, 0.0)

func _set_needles(mph: float, rpm: float) -> void:
	# the needles turn the way a real dial does as you look at it (clockwise from the driver's seat)
	if speedo_needle: speedo_needle.rotation = Vector3(0, 0, -SWEEP / 2.0 + SWEEP * clampf(mph / 60.0, 0.0, 1.0))
	if tach_needle: tach_needle.rotation = Vector3(0, 0, -SWEEP / 2.0 + SWEEP * clampf(rpm / 5000.0, 0.0, 1.0))
	if fuel_needle: fuel_needle.rotation = Vector3(0, 0, -SMALL_SWEEP / 2.0 + SMALL_SWEEP * _fuel)
	if temp_needle: temp_needle.rotation = Vector3(0, 0, -SMALL_SWEEP / 2.0 + SMALL_SWEEP * _temp)
	if gear_mark:
		var k := "PRND21".find(_gear)
		gear_mark.position = Vector3(TACH_X + 0.025 - k * 0.01, GAUGE_Y - 0.045, GAUGE_Z - 0.002)
	if odo_label: odo_label.text = "%06d" % int(odometer) + "." + str(int(fmod(odometer, 1.0) * 10.0))

## the engine's revs: idling when you're in the cab, climbing through three gears as the truck picks up speed,
## a bit higher with your foot down; off when you're out of it. The odometer counts the miles, the engine
## warms the temperature needle up to the middle, and the fuel needle creeps down as you drive.
var scripted_speed := -1.0       # m/s while the intro drive slides the truck along the road (physics reads 0 then); -1 = off
var scripted_engine := false     # the engine's running in the intro (idling once it's parked)
func _gauges_step(dt: float) -> void:
	var fwd_v := linear_velocity.dot(global_transform.basis.z)
	var mph := absf(fwd_v) * 2.237
	if scripted_speed >= 0.0: mph = scripted_speed * 2.237; fwd_v = scripted_speed
	var want := 0.0
	var running := driving or scripted_engine
	if running:
		var gears := [[0.0, 11.0], [11.0, 21.0], [21.0, 40.0]]
		var gear: Array = gears[0]
		for gr in gears:
			if mph >= gr[0]: gear = gr
		var frac := clampf((mph - float(gear[0])) / (float(gear[1]) - float(gear[0])), 0.0, 1.0)
		want = 750.0 + frac * 3300.0 + absf(_thr) * (500.0 if mph < 1.0 else 350.0) + sin(Time.get_ticks_msec() * 0.031) * 25.0
		if mph > 0.5 and float(gear[0]) > 0.0: want = maxf(want, 1500.0)
		if fwd_v < -0.3 or (_thr < -0.1 and mph < 1.0): _gear = "R"
		elif mph > 0.5 or _thr > 0.1: _gear = "D"
		elif _gear != "P" and _gear != "D": _gear = "N"
		_temp = move_toward(_temp, 0.5 + 0.03 * clampf(_rpm / 4000.0, 0.0, 1.0), dt * 0.03)
		_fuel = maxf(0.08, _fuel - mph * dt * 0.00002)
	else:
		_gear = "P"
		_temp = move_toward(_temp, 0.0, dt * 0.004)
	odometer += mph * dt / 3600.0
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
		var hand := Vector3(x + sx * 0.17, 1.07, 0.35)
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
	if driver: driver.visible = (driving and chase) or show_driver or remote_driver != 0
	if freeze and (driving or remote_driver != 0) and Net.is_guest(): return       # a crew copy: the host drives it
	var fwd := global_transform.basis.z
	var v := linear_velocity.dot(fwd)
	if driving:
		var thr := Input.get_axis("move_back", "move_fwd")
		var st := Input.get_axis("move_right", "move_left")
		var want_brake := Input.is_action_pressed("jump")
		if remote_driver != 0:
			thr = float(remote_in.get("thr", 0.0)); st = float(remote_in.get("st", 0.0)); want_brake = bool(remote_in.get("br", false))
		_thr = thr
		steering = move_toward(steering, st * (0.55 if absf(v) < 6 else 0.3), dt * 2.0)
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
