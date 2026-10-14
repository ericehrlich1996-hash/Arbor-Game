## The towed wood chipper: two free-rolling wheels, a ball-hitch joint to the truck,
## a jack stand when it's parked, and a tongue you can walk around by hand.
class_name Chipper
extends VehicleBody3D

var mode := "truck"      # "truck" (on the ball), "free" (on its jack), "hand" (you're walking it)
var running := false
var engine_snd = null
var truck: Truck
var world: WorldGen
var joint: PinJoint3D
var anchor: AnimatableBody3D
var jack_shape: CollisionShape3D
var jack_mesh: MeshInstance3D
var load := 0.0
var queue: Array = []
var feeding = null

func setup(t: Truck) -> void:
	truck = t
	add_collision_exception_with(t)     # the coupler sits on the ball; the joint keeps them apart
	collision_layer = 4
	collision_mask = 1 | 4 | 8 | 64
	mass = 650.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.15, -2.05)
	var mi: MeshInstance3D = Models.chipper().instance(); mi.name = "Body"; add_child(mi)
	jack_mesh = Models.jack().instance(); add_child(jack_mesh)
	_box(Vector3(0, 0.5, -1.55), Vector3(1.1, 0.9, 1.0))
	_box(Vector3(0, 0.55, -2.45), Vector3(1.0, 1.1, 0.9))
	_box(Vector3(0, -0.05, -2.2), Vector3(1.1, 0.12, 2.0))
	_box(Vector3(0, 0.5, -3.4), Vector3(1.2, 0.9, 1.0))          # infeed hood
	_box(Vector3(0, 0.0, -0.6), Vector3(0.25, 0.12, 1.2))         # tongue
	jack_shape = CollisionShape3D.new()
	var jb := BoxShape3D.new(); jb.size = Vector3(0.2, 0.3, 0.2)
	jack_shape.shape = jb; jack_shape.position = Vector3(0, -0.35, -0.4)
	add_child(jack_shape)
	var wmesh := Models.wheel().commit()
	for sx in [-1.0, 1.0]:
		var vw := VehicleWheel3D.new()
		vw.position = Vector3(sx * 0.78, -0.1 + 0.12, Models.CHIP_AXLE)
		vw.wheel_radius = Models.WHEEL_R
		vw.wheel_rest_length = 0.16
		vw.suspension_travel = 0.15
		vw.suspension_stiffness = 40.0
		vw.suspension_max_force = 9000.0
		vw.damping_compression = 2.5
		vw.damping_relaxation = 3.0
		vw.wheel_friction_slip = 3.0
		var wm := MeshInstance3D.new(); wm.mesh = wmesh; wm.material_override = Mats.vcol
		if sx > 0: wm.rotation.y = PI
		vw.add_child(wm)
		add_child(vw)
	anchor = AnimatableBody3D.new()
	anchor.sync_to_physics = false
	var acs := CollisionShape3D.new(); var asph := SphereShape3D.new(); asph.radius = 0.02; acs.shape = asph; acs.disabled = true
	anchor.add_child(acs)
	anchor.top_level = true
	add_child(anchor)
	_set_jack(false)

func _box(center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new(); b.size = size
	cs.shape = b; cs.position = center
	add_child(cs)

func _set_jack(down: bool) -> void:
	jack_shape.disabled = not down
	jack_mesh.position.y = 0.0 if down else 0.22

func coupler_world() -> Vector3:
	return global_position

func hopper_world() -> Vector3:
	return global_transform * Vector3(0, 0.5, -3.75)

func mouth_world() -> Vector3:
	return global_transform * Vector3(0, 0.5, -4.25)

func throat_world() -> Vector3:
	return global_transform * Vector3(0, 0.5, -2.95)

func chute_world() -> Vector3:
	return global_transform * Vector3(0, 2.0, -0.95)

func rack_world() -> Vector3:
	return global_transform * Vector3(-0.7, 0.32, -2.2)

func engine_world() -> Vector3:
	return global_transform * Vector3(0, 0.6, -1.6)

## put the coupler on the hitch ball and connect it
func hitch_now() -> void:
	_clear_joint()
	var hp := truck.hitch_world()
	var tb := truck.global_transform.basis
	global_transform = Transform3D(tb, hp)
	linear_velocity = truck.linear_velocity; angular_velocity = Vector3.ZERO
	joint = PinJoint3D.new()
	joint.position = Vector3.ZERO
	add_child(joint)
	joint.global_position = hp
	joint.node_a = truck.get_path()
	joint.node_b = get_path()
	mode = "truck"
	_set_jack(false)

func _clear_joint() -> void:
	if joint:
		joint.queue_free(); joint = null

func unhitch() -> void:
	_clear_joint()
	mode = "free"
	_set_jack(true)

func grab_tongue(hand: Vector3) -> void:
	_clear_joint()
	anchor.global_position = global_position
	joint = PinJoint3D.new()
	add_child(joint)
	joint.global_position = global_position
	joint.node_a = anchor.get_path()
	joint.node_b = get_path()
	mode = "hand"
	_set_jack(false)

## while walking it: the anchor follows your hands (moved a bit each physics step so the joint pulls smoothly)
func move_hand(target: Vector3, dt: float) -> void:
	if mode != "hand": return
	var p := anchor.global_position
	var d := target - p
	var mx := 3.0 * dt
	if d.length() > mx: d = d.normalized() * mx
	anchor.global_position = p + d

func set_down() -> void:
	_clear_joint()
	mode = "free"
	_set_jack(true)

## during the scripted drive in: no joint, the trailer just follows the ball like a real trailer would
var _axle_prev := Vector3.ZERO
func follow_kinematic(on: bool) -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = on
	if on:
		_clear_joint()
		_axle_prev = global_transform * Vector3(0, 0, Models.CHIP_AXLE)
	else:
		linear_velocity = Vector3.ZERO; angular_velocity = Vector3.ZERO

func trail(_dt: float) -> void:
	var hp := truck.hitch_world()
	var head := hp - _axle_prev; head.y = 0
	if head.length() < 1e-3: return
	head = head.normalized()
	var axle := hp - head * absf(Models.CHIP_AXLE)
	_axle_prev = axle
	var gy := world.H(axle.x, axle.z) if world else hp.y - 0.5
	var pitch := atan2((hp.y - 0.54) - gy, absf(Models.CHIP_AXLE))
	global_transform = Transform3D(Basis(Vector3.UP, atan2(head.x, head.z)) * Basis(Vector3.RIGHT, pitch), hp)

func near_hitch() -> bool:
	return global_position.distance_to(truck.hitch_world()) < 0.8

func _physics_process(_dt: float) -> void:
	if mode == "free":
		brake = 300.0
	else:
		brake = 0.0
