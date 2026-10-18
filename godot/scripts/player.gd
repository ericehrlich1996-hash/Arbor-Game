## First-person player: walking, looking, crouching, jumping, and standing on whatever is underneath
## (including the truck bed, which carries you along when it moves).
class_name Player
extends CharacterBody3D

var cam: Camera3D
var head: Node3D
var hands: Node3D           # view-model root (attached to the camera)
var yaw := 0.0
var pitch := 0.0
var crouch := false
var eye_h := 1.62
var bob := 0.0
var step_t := 0.0
var tool := "hands"
var in_truck := false
var speed_mult := 1.0
var col_shape: CollisionShape3D

const WALK := 3.3
const RUN := 5.6
const CROUCH_SPEED := 1.4
const JUMP := 4.2
const GRAV := 9.81

func _ready() -> void:
	col_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new(); cap.radius = 0.3; cap.height = 1.75
	col_shape.shape = cap; col_shape.position = Vector3(0, 0.875, 0)
	add_child(col_shape)
	head = Node3D.new(); head.position = Vector3(0, eye_h, 0); add_child(head)
	cam = Camera3D.new(); cam.fov = 70; cam.near = 0.03; cam.far = 700
	head.add_child(cam)
	hands = Node3D.new(); cam.add_child(hands)
	collision_layer = 2
	collision_mask = 1 | 4 | 8 | 16 | 32     # blocked by everything, but never shoves the truck or logs around
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50)
	safe_margin = 0.02

func look(dx: float, dy: float) -> void:
	yaw -= dx
	pitch = clampf(pitch - dy, -1.5, 1.45)

func fwd() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))

func eye() -> Vector3:
	return cam.global_position

func aim_dir() -> Vector3:
	return -cam.global_transform.basis.z

func teleport(p: Vector3, y := INF) -> void:
	global_position = p
	velocity = Vector3.ZERO
	if y != INF: yaw = y

func _physics_process(dt: float) -> void:
	rotation = Vector3(0, yaw, 0)
	head.rotation = Vector3(pitch, 0, 0)
	if in_truck: return
	var target_eye := 0.98 if crouch else 1.62
	eye_h = lerpf(eye_h, target_eye, minf(1, dt * 8))
	var mv := Input.get_vector("move_left", "move_right", "move_fwd", "move_back")
	var dir := (global_transform.basis * Vector3(mv.x, 0, mv.y))
	dir.y = 0
	if dir.length() > 1: dir = dir.normalized()
	var sp := (RUN if Input.is_action_pressed("run") and not crouch else (CROUCH_SPEED if crouch else WALK)) * speed_mult
	var hv := dir * sp
	velocity.x = move_toward(velocity.x, hv.x, dt * 30); velocity.z = move_toward(velocity.z, hv.z, dt * 30)
	if is_on_floor():
		if Input.is_action_just_pressed("jump") and not crouch: velocity.y = JUMP
	else:
		velocity.y -= GRAV * dt
	var grounded := is_on_floor()
	move_and_slide()
	if grounded and hv.length() > 0.1 and is_on_wall(): _step_up(hv, dt)
	var moving := hv.length() > 0.1 and is_on_floor()
	if moving:
		bob += dt * sp * 2.2
		step_t += sp * dt
		if step_t > 1.3:
			step_t = 0
			Sfx.play("step")
	var bob_y := absf(sin(bob)) * 0.025 if moving else 0.0
	head.position.y = eye_h + bob_y

const STEP_H := 0.36            # the tallest step you walk straight up (stairs, a porch, a dock edge)

## walked into something low: if there's room above it, step up onto it instead of stopping dead
func _step_up(hv: Vector3, dt: float) -> void:
	var fwd := hv.normalized() * maxf(hv.length() * dt, 0.08)
	var xf := global_transform
	var up := Vector3(0, STEP_H, 0)
	if test_move(xf, up): return                        # no headroom
	var raised := xf.translated(up)
	if test_move(raised, fwd): return                   # still a wall up there: it's not a step
	var over := raised.translated(fwd)
	var hit := KinematicCollision3D.new()
	if not test_move(over, -up * 1.05, hit): return     # nothing to stand on: don't step off into the air
	var top := over.origin + hit.get_travel()
	if hit.get_normal().y < cos(floor_max_angle): return    # landed on a slope too steep to stand on
	if top.y - xf.origin.y < 0.02: return
	global_position = top + Vector3(0, 0.01, 0)
	velocity.y = 0.0
