## Little things that make the woods feel alive: autumn leaves drifting down around you,
## and a couple of flocks of birds wheeling over the treetops.
class_name Ambient
extends Node3D

var leaves: CPUParticles3D
var flocks: Array = []          # [{centre, radius, height, speed, phase, birds: [[node, wingL, wingR, off]]}]
var t := 0.0

func setup(centre: Vector3) -> void:
	_leaves()
	var r := RandomNumberGenerator.new(); r.seed = 913
	for f in range(2):
		var fl := {centre = centre + Vector3(r.randf_range(-30, 30), 0, r.randf_range(-30, 30)), radius = r.randf_range(55, 90),
			height = r.randf_range(32, 48), speed = r.randf_range(0.05, 0.08) * (1 if f == 0 else -1), phase = r.randf() * TAU, birds = []}
		for k in range(r.randi_range(4, 7)):
			var b := _bird()
			add_child(b[0])
			fl.birds.append([b[0], b[1], b[2], Vector3(r.randf_range(-4, 4), r.randf_range(-1.5, 1.5), r.randf_range(-4, 4)), r.randf() * TAU])
		flocks.append(fl)

func _leaves() -> void:
	leaves = CPUParticles3D.new()
	var mb := MeshBuilder.new()
	var c := Color.WHITE
	var a := mb.v(Vector3(0, -0.05, 0), Vector3.UP, c); var b := mb.v(Vector3(0.03, 0, 0), Vector3.UP, c)
	var d := mb.v(Vector3(0, 0.05, 0), Vector3.UP, c); var e := mb.v(Vector3(-0.03, 0, 0), Vector3.UP, c)
	mb.quad(a, b, d, e)
	leaves.mesh = mb.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.9
	leaves.material_override = mat
	leaves.amount = 70
	leaves.lifetime = 10.0
	leaves.preprocess = 10.0
	leaves.local_coords = false
	leaves.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	leaves.emission_box_extents = Vector3(16, 1, 16)
	leaves.direction = Vector3(1, -0.3, 0.4)
	leaves.spread = 60.0
	leaves.initial_velocity_min = 0.3; leaves.initial_velocity_max = 0.9
	leaves.gravity = Vector3(0.15, -0.55, 0.05)
	leaves.damping_min = 0.2; leaves.damping_max = 0.5
	leaves.angular_velocity_min = -220; leaves.angular_velocity_max = 220
	leaves.particle_flag_rotate_y = true
	leaves.scale_amount_min = 0.8; leaves.scale_amount_max = 1.6
	var g := Gradient.new()
	g.set_color(0, Color(0.95, 0.55, 0.18)); g.set_color(1, Color(0.8, 0.28, 0.14))
	g.add_point(0.5, Color(0.95, 0.78, 0.28))
	leaves.color_initial_ramp = g
	leaves.position = Vector3(0, 9, 0)
	add_child(leaves)

func _bird() -> Array:
	var root := Node3D.new()
	var dark := Color(0.12, 0.12, 0.13)
	var body := MeshBuilder.new()
	body.sphere(0, 0, 0, 0.06, 0.05, 0.16, dark, 6, 4)
	var bm := body.instance(); bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bm)
	var wings := []
	for sx: float in [-1.0, 1.0]:
		var w := MeshBuilder.new()
		var i0 := w.v(Vector3(0, 0, 0.06), Vector3.UP, dark); var i1 := w.v(Vector3(sx * 0.42, 0, -0.04), Vector3.UP, dark)
		var i2 := w.v(Vector3(0, 0, -0.08), Vector3.UP, dark)
		w.tri(i0, i1, i2); w.tri(i0, i2, i1)
		var wm := w.instance(); wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wm); wings.append(wm)
	return [root, wings[0], wings[1]]

func step(dt: float, eye: Vector3) -> void:
	t += dt
	leaves.global_position = eye + Vector3(0, 7, 0)
	for fl: Dictionary in flocks:
		var a: float = fl.phase + t * fl.speed
		var c: Vector3 = fl.centre
		var p := c + Vector3(cos(a) * fl.radius, fl.height + sin(t * 0.3 + fl.phase) * 3.0, sin(a) * fl.radius)
		var tangent := Vector3(-sin(a), 0, cos(a)) * signf(fl.speed)
		for b: Array in fl.birds:
			var n: Node3D = b[0]
			n.global_position = p + (b[3] as Vector3)
			n.look_at(n.global_position + tangent, Vector3.UP)
			var flap := sin(t * 9.0 + b[4]) * 0.6 if fmod(t * 0.4 + b[4], 3.0) < 1.8 else 0.12     # flap, then glide
			(b[1] as Node3D).rotation.z = flap
			(b[2] as Node3D).rotation.z = -flap
