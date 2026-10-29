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
const WAVES := false                     # the waving arm is off: he just stands there (state "wave" poses like idle)
var wave_twist := Vector2(0.0, -1.3)    # palm toward you: turns the upper arm (x) and forearm (y) about their length while waving
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
var mirror := false            # a crew copy: placed and posed from the host's game
var remote_talk := false       # talking to someone else on the crew

func setup(w: WorldGen, at: Vector2, look := "earl") -> void:
	world = w
	position = Vector3(at.x, w.H(at.x, at.y), at.y)
	var P := Models.old_lady() if look == "hale" else (Models.sheriff() if look == "sheriff" else Models.old_man(look))
	var M := modeled("res://models/%s.glb" % look)       # the Blender model (art/<look>.py), if there is one
	if not M.is_empty(): P = M
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
	if P.has("skinned"): _skin_setup(P.skinned)
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

func _part(src, parent: Node3D) -> Node3D:
	if src == null:                          # a skinned character: the rig's joints are just empty pivots
		var n := Node3D.new(); parent.add_child(n); return n
	var mi: MeshInstance3D
	if src is MeshBuilder: mi = (src as MeshBuilder).instance()
	else: mi = MeshInstance3D.new(); mi.mesh = src
	parent.add_child(mi); return mi

# ---------------------------------------------------------------- a skinned (one-piece) character
# The .glb holds one mesh skinned to a skeleton whose bones sit at the same joints as the pivots above.
# The pivots still do all the posing; each frame their movement is copied onto the bones.
var skel: Skeleton3D
var _bones: Array = []          # [bone index, pivot node, the pivot's rest transform, the bone's rest pose]
var _skel_k := Transform3D()     # the skeleton's place relative to this node

func _rel(n: Node3D) -> Transform3D:
	var t := Transform3D(); var c: Node = n
	while c != null and c != self:
		t = (c as Node3D).transform * t; c = c.get_parent()
	return t

func _skin_setup(scene: PackedScene) -> void:
	var root: Node3D = scene.instantiate(); add_child(root)
	var cn := root.find_child("cane", true, false)
	if cn: cn.queue_free()                   # the stick is held on the hand pivot instead
	var found := root.find_children("*", "Skeleton3D", true, false)
	if found.is_empty(): return
	skel = found[0]
	for mi in root.find_children("*", "MeshInstance3D", true, false): _crisp_palette((mi as MeshInstance3D).mesh)
	# the pivots in their rest pose (standing straight, arms down) to measure movement from
	n_hip.position = Vector3(0, 0.92, 0)
	for n in [n_hip, n_torso, n_head] + n_up.values() + n_fore.values() + n_leg.values(): (n as Node3D).rotation = Vector3.ZERO
	_skel_k = _rel(skel)
	var map := {"hips": n_hip, "torso": n_torso, "head": n_head, "upper_l": n_up[1.0], "upper_r": n_up[-1.0],
		"fore_l": n_fore[1.0], "fore_r": n_fore[-1.0], "leg_l": n_leg[1.0], "leg_r": n_leg[-1.0]}
	for name in ["hips", "torso", "head", "upper_l", "upper_r", "fore_l", "fore_r", "leg_l", "leg_r"]:
		var i := skel.find_bone(name)
		if i >= 0: _bones.append([i, map[name], _rel(map[name]), skel.get_bone_global_rest(i)])

func _drive_skeleton() -> void:
	if skel == null: return
	var ki := _skel_k.affine_inverse()
	for b in _bones:                          # parents come first in the list, so children build on them
		var delta: Transform3D = _rel(b[1]) * (b[2] as Transform3D).affine_inverse()
		skel.set_bone_global_pose(b[0], ki * delta * _skel_k * (b[3] as Transform3D))

static func _crisp_palette(m: Mesh) -> void:
	if m == null: return
	for si in m.get_surface_count():
		var mat := m.surface_get_material(si)
		if mat is BaseMaterial3D:
			var bm := (mat as BaseMaterial3D)
			if bm.albedo_texture and bm.albedo_texture.get_width() <= 64:
				bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			bm.roughness = 0.9; bm.metallic_specular = 0.25

## a character modelled in Blender: the .glb holds one mesh per posable part (torso, head, upper, fore,
## leg, cane), each with its origin at the joint it turns about, so they drop straight into the rig above
static var _models := {}
static func modeled(path: String) -> Dictionary:
	if _models.has(path): return _models[path]
	var out := {}
	if ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		var root: Node = ps.instantiate()
		if not root.find_children("*", "Skeleton3D", true, false).is_empty():
			# one skinned body: no separate part meshes, only the stick
			out = {"skinned": ps, "torso": null, "head": null, "upper": null, "fore": null, "leg": null, "cane": null}
			var cn := root.find_child("cane", true, false)
			if cn is MeshInstance3D: out.cane = (cn as MeshInstance3D).mesh; _crisp_palette(out.cane)
			root.free()
			_models[path] = out
			return out
		for k in ["torso", "head", "upper", "fore", "leg", "cane"]:
			var n := root.find_child(k, true, false)
			if n is MeshInstance3D:
				var m: Mesh = (n as MeshInstance3D).mesh
				for si in m.get_surface_count():
					var mat := m.surface_get_material(si)
					if mat is BaseMaterial3D:
						var bm := (mat as BaseMaterial3D)
						# the palette atlas is flat swatches: sample it exactly (no blending between swatches)
						if bm.albedo_texture and bm.albedo_texture.get_width() <= 64:
							bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
						bm.roughness = 0.9; bm.metallic_specular = 0.25
				out[k] = m
		root.free()
		if out.size() < 6: out = {}
	_models[path] = out
	return out

func bark(text: String, secs := 3.0) -> void:
	if Net.is_host() and Net.job: Net.job.bark(text, secs)
	bubble.text = text
	bubble.visible = true
	bubble_until = t + secs

func go_to(p: Vector2, then := "idle") -> void:
	walk_to = p; after = then

func step(dt: float, look_at_pos: Vector3, truck: Truck) -> void:
	t += dt
	if mirror:
		var keep := talking
		talking = talking or remote_talk
		body.global_transform = Transform3D(Basis(), global_position)
		if bubble.visible and t > bubble_until: bubble.visible = false
		_pose()
		talking = keep
		return
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
		if WAVES and state == "wave" and side > 0:
			# upper arm out and up beside the head, elbow bent, the hand waving from the elbow
			up = Vector3(-0.25, wave_twist.x, side * 1.95); fo = Vector3(0, wave_twist.y, side * (0.95 + sin(t * 8) * 0.35))
		elif talking and side > 0:
			up = Vector3(-0.6 - sin(t * 3) * 0.3, 0, side * -0.35); fo = Vector3(-0.9, 0, 0)
		else:
			up = Vector3((-sw * side * 0.8) if walk else sin(t * 1.2 + side) * 0.04, 0, side * 0.12); fo = Vector3(-0.25, 0, 0)
		n_up[side].rotation = up
		n_fore[side].rotation = fo
		n_leg[side].rotation = Vector3(sw * side, 0, 0)
	_drive_skeleton()
