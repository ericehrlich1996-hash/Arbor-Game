## Another member of the crew, as you see them: a figure in a hi-vis vest and their own colour of hard
## hat, with their name over their head, the saw in their hands when they've got it out (you hear it
## too), and a coil of rope or a sledge when they're carrying those. Moves smoothly between the
## updates that come in over the line.
class_name Avatar
extends Node3D

var nm := ""
var hat := Color.ORANGE
var visible_here := true
var body: Node3D
var head: Node3D
var saw_node: Node3D
var coil_node: Node3D
var sledge_node: Node3D
var rod_node: Node3D
var arm_r: Node3D
var arm_l: Node3D
var tag: Label3D
var _tgt_pos := Vector3.ZERO
var _tgt_yaw := 0.0
var _pitch := 0.0
var _have := false
var _flags := 0
var _tool := "hands"
var _walk := 0.0
var _last_pos := Vector3.ZERO
var saw_snd = null
var _rpm := 0.0

const F_SAW_ON := 1
const F_REV := 2
const F_CUTTING := 4
const F_TRUCK := 8
const F_CROUCH := 16
const F_CARRY := 32
const F_CLIMB := 64

func setup(n: String, c: Color) -> void:
	nm = n; hat = c
	var vest := Color("#d8f028"); var shirt := Color("#4a5a3a"); var jeans := Color("#3d5070"); var boot := Color("#3a2a1a")
	var skin := Color("#e0b090"); var glove := Color("#c9a46a")
	body = Node3D.new(); add_child(body)
	var legs := MeshBuilder.new()
	for sx: float in [-1.0, 1.0]:
		legs.tube(Vector3(sx * 0.1, 0.05, 0), Vector3(sx * 0.1, 0.88, 0), 0.075, 0.085, jeans, 8)
		legs.bevel_box(sx * 0.1, 0.05, -0.04, 0.12, 0.1, 0.27, boot, 0.03)
	var lm := legs.instance(); body.add_child(lm)
	var torso := MeshBuilder.new()
	torso.tube(Vector3(0, 0.86, 0), Vector3(0, 1.42, 0), 0.17, 0.2, shirt, 10)
	torso.sphere(0, 1.15, 0, 0.215, 0.32, 0.155, vest, 12, 7)
	torso.box(0, 1.08, 0.0, 0.44, 0.04, 0.32, Color("#d8dcd8"))          # reflective bands
	torso.box(0, 1.24, 0.0, 0.44, 0.04, 0.32, Color("#d8dcd8"))
	torso.tube(Vector3(0, 1.42, 0), Vector3(0, 1.52, 0), 0.05, 0.05, skin, 8)
	var tm := torso.instance(); body.add_child(tm)
	head = Node3D.new(); head.position = Vector3(0, 1.6, 0); body.add_child(head)
	var hb := MeshBuilder.new()
	hb.sphere(0, 0, 0, 0.11, 0.125, 0.115, skin, 12, 8)
	hb.box(0, 0.0, -0.105, 0.14, 0.02, 0.01, Color("#3a2a1e"))           # brows, so you can tell which way they face
	hb.sphere(0, 0.075, 0.0, 0.145, 0.085, 0.16, hat, 12, 6)              # hard hat
	hb.cyl(0, 0.035, -0.02, 0.17, 0.17, 0.015, hat, 14, true)
	hb.box(0, 0.035, -0.17, 0.2, 0.012, 0.08, hat)                         # the peak
	for sx: float in [-1.0, 1.0]: hb.sphere(sx * 0.12, -0.01, 0.0, 0.035, 0.055, 0.05, Color("#2e3236"), 8, 5)   # ear muffs
	head.add_child(hb.instance())
	# arms: shoulder pivots, so they can reach for the saw handles
	for sx: float in [-1.0, 1.0]:
		var pv := Node3D.new(); pv.position = Vector3(sx * 0.24, 1.38, 0); body.add_child(pv)
		var am := MeshBuilder.new()
		am.tube(Vector3.ZERO, Vector3(0, -0.5, 0), 0.06, 0.05, shirt, 7)
		am.sphere(0, -0.52, 0, 0.055, 0.055, 0.06, glove, 7, 5)
		pv.add_child(am.instance())
		if sx > 0: arm_r = pv
		else: arm_l = pv
	# the saw, held out in front
	saw_node = Node3D.new(); body.add_child(saw_node)
	var sm := Models.chainsaw().instance(); sm.scale = Vector3.ONE * 0.95
	sm.rotation = Vector3(0, 0, 0)
	saw_node.add_child(sm)
	saw_node.position = Vector3(0.12, 0.98, -0.42)
	saw_node.visible = false
	coil_node = Node3D.new(); body.add_child(coil_node)
	var cm := MeshBuilder.new()
	for k in range(4): cm.cyl(0, k * 0.012, 0, 0.17 - k * 0.004, 0.17 - k * 0.004, 0.02, Color("#d8b440") if k % 2 else Color("#2a6ab8"), 12, false)
	var cmi := cm.instance(); cmi.rotation = Vector3(PI / 2, 0, 0); coil_node.add_child(cmi)
	coil_node.position = Vector3(-0.28, 1.0, -0.15); coil_node.visible = false
	sledge_node = Node3D.new(); body.add_child(sledge_node)
	var sl := MeshBuilder.new()
	sl.tube(Vector3(0, -0.3, 0), Vector3(0, 0.15, 0), 0.016, 0.016, Color("#8a6a42"), 6)
	sl.box(0, 0.18, 0, 0.16, 0.07, 0.07, Color("#3a3a3a"))
	sledge_node.add_child(sl.instance())
	sledge_node.position = Vector3(0.26, 0.92, -0.25); sledge_node.visible = false
	rod_node = Node3D.new(); body.add_child(rod_node)
	var rd := MeshBuilder.new()
	rd.tube(Vector3(0, 0, 0), Vector3(0, 0.7, -1.3), 0.012, 0.004, Color("#2a2a2a"), 5)
	rd.cyl(0, 0.12, -0.22, 0.03, 0.03, 0.04, Color("#9a9a9a"), 8, true)
	rod_node.add_child(rd.instance())
	rod_node.position = Vector3(0.26, 0.98, -0.2); rod_node.visible = false
	for mi in find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).layers = 1 | 16           # not drawn into the job timelapse figure's layer clash
	tag = Label3D.new()
	tag.text = nm
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 44
	tag.pixel_size = 0.004
	tag.outline_size = 10
	tag.modulate = hat.lightened(0.25)
	tag.outline_modulate = Color(0, 0, 0, 0.85)
	tag.no_depth_test = true
	tag.fixed_size = false
	tag.position = Vector3(0, 2.12, 0)
	add_child(tag)
	visible = false

## [pos, yaw, pitch, tool, flags, ...] as sent by game.net_pose()
func apply(p: Array) -> void:
	_tgt_pos = p[0]; _tgt_yaw = p[1]; _pitch = p[2]; _tool = str(p[3]); _flags = int(p[4])
	if not _have:
		_have = true
		global_position = _tgt_pos; rotation.y = _tgt_yaw
		_last_pos = _tgt_pos

func _process(dt: float) -> void:
	var show_me := _have and visible_here and not (_flags & F_TRUCK)
	visible = show_me
	if not _have: return
	if global_position.distance_to(_tgt_pos) > 6.0: global_position = _tgt_pos
	else: global_position = global_position.lerp(_tgt_pos, minf(1.0, dt * 12.0))
	rotation.y = lerp_angle(rotation.y, _tgt_yaw, minf(1.0, dt * 12.0))
	var crouch: bool = bool(_flags & F_CROUCH)
	body.position.y = lerpf(body.position.y, -0.5 if crouch else 0.0, minf(1.0, dt * 10.0))
	# up a tree: leaning back into the lanyard, feet in toward the trunk
	body.rotation.x = lerpf(body.rotation.x, -0.22 if (_flags & F_CLIMB) else 0.0, minf(1.0, dt * 6.0))
	head.rotation.x = clampf(_pitch, -0.9, 0.8) * 0.8
	var moved := Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
	_last_pos = global_position
	var speed := moved / maxf(dt, 1e-3)
	_walk += dt * speed * 2.6
	var sw := sin(_walk) * clampf(speed / 3.0, 0.0, 1.0) * 0.5
	var saw_out: bool = _tool == "saw" and not bool(_flags & F_CARRY)
	saw_node.visible = saw_out
	coil_node.visible = _tool == "rope"
	sledge_node.visible = _tool == "wedge"
	rod_node.visible = _tool == "rod"
	if saw_out:
		# held out at waist height, the bar following where they look
		var engaged := 1.0 if (_flags & F_REV) else 0.0
		saw_node.position = Vector3(0.1, 1.04 + engaged * 0.06, -0.3 - engaged * 0.1)
		saw_node.rotation = Vector3(clampf(_pitch, -1.0, 0.5) * engaged * 0.7 + (0.0 if engaged > 0.5 else -0.35), 0, 0)
		arm_r.rotation = Vector3(-1.1 - engaged * 0.2, 0, 0.1)
		arm_l.rotation = Vector3(-1.2 - engaged * 0.2, 0, -0.35)
	elif _flags & F_CARRY:
		arm_r.rotation = Vector3(-2.6, 0, 0.2); arm_l.rotation = Vector3(-1.2, 0, -0.3)
	else:
		arm_r.rotation = Vector3(sw, 0, 0.08); arm_l.rotation = Vector3(-sw, 0, -0.08)
	# their saw, by ear: louder when they rev it, rougher in the wood, fading with distance
	var on: bool = saw_out and bool(_flags & F_SAW_ON) and visible
	if on and saw_snd == null: saw_snd = Sfx.engine("saw")
	elif not on and saw_snd != null: saw_snd.stop(); saw_snd = null
	if saw_snd:
		_rpm = lerpf(_rpm, 1.0 if (_flags & F_REV) else 0.05, minf(1.0, dt * 6.0))
		var cam := get_viewport().get_camera_3d()
		var d := cam.global_position.distance_to(global_position) if cam else 10.0
		saw_snd.setv(_rpm * (0.82 if (_flags & F_CUTTING) else 1.0), 1.0 if (_flags & F_CUTTING) else 0.0, clampf(1.0 - d / 70.0, 0.0, 1.0) * 0.4)

func _exit_tree() -> void:
	if saw_snd: saw_snd.stop(); saw_snd = null
