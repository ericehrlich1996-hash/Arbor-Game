## The client (Earl, or Mrs. Hale on the second job). Posed procedurally: idles, waves, talks with his hands, walks (and gets out of the truck's way).
class_name Earl
extends Node3D

const NAME := "Earl"
const IDLE := [
	"Did I ever tell ya about the squirrel that robbed me? Took a whole bag of peanuts. Looked me dead in the eye.",
	"Them little green beetles came all the way here just to ruin MY tree. I take that personal.",
	"My cousin Del didn't watch his hinge. Now he sells insurance.",
	"Don't mind the chickens. Wait, I don't have chickens. Whose chickens are those?",
	"That tree's been creakin' at me every night for two years. Plottin', I tell ya.",
	"You want a coffee? I don't have coffee. Just askin' if you WANT one.",
	"Back in my day we cut trees with a butter knife and a positive attitude.",
]

var world: WorldGen
var display := NAME             # the name in the dialogue box
var idle_lines: Array = IDLE
var state := "wave"
var t := 0.0
var talking := false
var walk_to = null        # Vector2 or null
var after := "idle"
var dodge_t := -100.0
var face_target := Vector3.ZERO
var body: AnimatableBody3D
var parts := {}
var n_torso: Node3D; var n_head: Node3D; var n_hip: Node3D
var n_up := {}; var n_fore := {}; var n_leg := {}; var n_cane: Node3D
var bubble: Label3D
var bubble_until := 0.0
var last_bark := 0.0

func setup(w: WorldGen, at: Vector2, look := "earl") -> void:
	world = w
	position = Vector3(at.x, w.H(at.x, at.y), at.y)
	var P := Models.old_lady() if look == "hale" else Models.old_man(look)
	n_hip = Node3D.new(); add_child(n_hip)
	n_torso = _part(P.torso, n_hip)
	var neck := Node3D.new(); neck.position = Vector3(0, 0.58, 0); n_torso.add_child(neck)
	n_head = _part(P.head, neck)
	for side in [1.0, -1.0]:
		var sh := Node3D.new(); sh.position = Vector3(side * 0.25, 0.5, 0); n_torso.add_child(sh)
		n_up[side] = _part(P.upper, sh)
		var el := Node3D.new(); el.position = Vector3(0, -0.3, 0); n_up[side].add_child(el)
		n_fore[side] = _part(P.fore, el)
		var hp := Node3D.new(); hp.position = Vector3(side * 0.1, 0, 0); n_hip.add_child(hp)
		n_leg[side] = _part(P.leg, hp)
	var hand := Node3D.new(); hand.position = Vector3(0, -0.3, 0); n_fore[-1.0].add_child(hand)
	n_cane = _part(P.cane, hand)
	body = AnimatableBody3D.new()
	var cs := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.3; cap.height = 1.7
	cs.shape = cap; cs.position = Vector3(0, 0.85, 0); body.add_child(cs)
	body.set_meta("kind", "earl")
	body.collision_layer = 16; body.collision_mask = 0
	add_child(body)
	bubble = Label3D.new()
	bubble.position = Vector3(0, 2.15, 0)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.font_size = 40; bubble.pixel_size = 0.0028
	bubble.outline_size = 10; bubble.outline_modulate = Color(0, 0, 0, 0.85)
	bubble.modulate = Color(1, 0.97, 0.88)
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; bubble.width = 620
	bubble.visible = false
	add_child(bubble)

func _part(mb: MeshBuilder, parent: Node3D) -> Node3D:
	var mi := mb.instance(); parent.add_child(mi); return mi

func bark(text: String, secs := 3.0) -> void:
	bubble.text = text
	bubble.visible = true
	bubble_until = t + secs

func go_to(p: Vector2, then := "idle") -> void:
	walk_to = p; after = then

func step(dt: float, look_at_pos: Vector3, truck: Truck) -> void:
	t += dt
	# get out of the way of a moving truck
	if truck and truck.linear_velocity.length() > 1.0:
		var to_me := global_position - truck.global_position; to_me.y = 0
		var tf := truck.global_transform.basis.z * signf(truck.linear_velocity.dot(truck.global_transform.basis.z))
		var ahead := to_me.dot(tf); var side := to_me.dot(truck.global_transform.basis.x)
		if ahead > -1 and ahead < 9 and absf(side) < 2.6 and (walk_to == null or t - dodge_t > 2.5):
			var away := truck.global_transform.basis.x * (1.0 if side >= 0 else -1.0)
			var dest := global_position + away * (3.4 - absf(side))
			walk_to = Vector2(dest.x, dest.z); after = "idle"; dodge_t = t
			if randf() < 0.5: bark("Whoa whoa WHOA!", 1.6)
	if walk_to != null:
		var d := Vector2(walk_to.x - position.x, walk_to.y - position.z)
		if d.length() < 0.15:
			walk_to = null; state = after
		else:
			var sp := (1.8 if t - dodge_t < 3 else 1.1) * dt
			var mvv := d.normalized() * minf(sp, d.length())
			position.x += mvv.x; position.z += mvv.y
			rotation.y = atan2(d.x, d.y)
			state = "walk"
	else:
		var want := atan2(look_at_pos.x - position.x, look_at_pos.z - position.z)
		rotation.y = lerp_angle(rotation.y, want, minf(1, dt * 3))
	position.y = lerpf(position.y, world.floor_h(position.x, position.z), minf(1.0, dt * 12.0)) if absf(position.y - world.floor_h(position.x, position.z)) < 0.6 else world.floor_h(position.x, position.z)
	body.global_transform = Transform3D(Basis(), global_position)
	if bubble.visible and t > bubble_until: bubble.visible = false
	_pose()

func _pose() -> void:
	var walk := state == "walk"
	var sw := sin(t * 6) * 0.5 if walk else 0.0
	n_hip.position = Vector3(0, 0.92 + (absf(cos(t * 6)) * 0.03 if walk else sin(t * 1.3) * 0.005), 0)
	n_torso.rotation = Vector3(0.08 if walk else 0.12 + sin(t * 1.1) * 0.02, 0, 0)
	n_head.rotation = Vector3(sin(t * 9) * 0.08 if talking else -0.05, sin(t * 0.7) * 0.15, 0)
	for side in [1.0, -1.0]:
		var up: Vector3; var fo: Vector3
		if state == "wave" and side > 0:
			up = Vector3(-0.2, 0, side * 2.5); fo = Vector3(0, 0, side * (0.5 + sin(t * 8) * 0.45))
		elif talking and side > 0:
			up = Vector3(-0.6 - sin(t * 3) * 0.3, 0, side * -0.35); fo = Vector3(-0.9, 0, 0)
		else:
			up = Vector3((-sw * side * 0.8) if walk else sin(t * 1.2 + side) * 0.04, 0, side * 0.12); fo = Vector3(-0.25, 0, 0)
		n_up[side].rotation = up
		n_fore[side].rotation = fo
		n_leg[side].rotation = Vector3(sw * side, 0, 0)
