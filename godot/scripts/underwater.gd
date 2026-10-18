## The underwater camera while you fish, as in the old reel-fishing games: once the lure's in, a window opens
## onto the water round it - the line down to the hook, weed beds swaying, light coming down through the
## surface, a school of minnows, and the fish itself, nosing in to take a look, nibbling, then taking it.
## In the fight it follows the fish. It renders the same world through a second camera; the extra
## underwater bits (light shafts, motes, minnows, the fish model) sit on render layer 2, which the
## main view leaves out.
class_name Underwater
extends Node3D

const LAYER := 2
const VIEW := Vector2i(512, 288)

var fishing
var game
var vp: SubViewport
var cam: Camera3D
var env: Environment
var frame: PanelContainer
var tex: TextureRect
var fish_node: Node3D
var fish_uid := -1
var hook: MeshInstance3D
var line_im: ImmediateMesh
var shafts: Node3D
var motes: CPUParticles3D
var minnows: MultiMeshInstance3D
var school_c := Vector3.ZERO
var show_k := 0.0
var t := 0.0
var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO
var _fresh := true

func setup(f) -> void:
	fishing = f; game = f.game
	vp = SubViewport.new(); vp.size = VIEW; vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(vp)
	cam = Camera3D.new(); cam.fov = 68; cam.near = 0.03; cam.far = 24.0
	vp.add_child(cam)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.33, 0.36)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.62, 0.62); env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.36, 0.38); env.fog_density = 0.14
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true; env.glow_intensity = 0.5; env.glow_bloom = 0.1
	cam.environment = env
	# the hook and a soft plastic grub on it
	var hb := MeshBuilder.new()
	hb.tube(Vector3(0, 0.05, 0), Vector3(0, -0.02, 0), 0.0035, 0.0035, Color("#b8bcc0"), 5)
	hb.tube(Vector3(0, -0.02, 0), Vector3(0.025, -0.035, 0), 0.003, 0.003, Color("#b8bcc0"), 4)
	hb.sphere(0, 0.055, 0, 0.012, 0.012, 0.012, Color("#c0302a"), 6, 4)                      # split shot
	hb.sphere(0.0, -0.01, 0, 0.011, 0.04, 0.011, Color("#e8c23a"), 6, 5)                   # the grub
	hook = _layer(hb.instance())
	add_child(hook)
	line_im = ImmediateMesh.new()
	var lm := MeshInstance3D.new(); lm.mesh = line_im
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.9, 0.95, 0.95, 0.7); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	lm.material_override = mat
	add_child(_layer(lm))
	shafts = Node3D.new(); add_child(shafts)      # (light shafts read as slabs; caustics on the bed instead)
	_build_motes()
	_build_minnows()
	_build_frame()

func _layer(m: VisualInstance3D) -> VisualInstance3D:
	m.layers = LAYER
	if m is GeometryInstance3D: (m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m

# ---------------------------------------------------------------- pieces
func _build_shafts() -> void:
	shafts = Node3D.new(); add_child(shafts)
	var mat := ShaderMaterial.new(); var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float strength = 0.09;
void vertex() {
	// face the camera round the vertical axis
	vec3 cam_dir = normalize((INV_VIEW_MATRIX[3].xyz - (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz) * vec3(1.0, 0.0, 1.0));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), cam_dir));
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz + right * VERTEX.x + vec3(0.0, VERTEX.y, 0.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
}
void fragment() {
	float edge = 1.0 - abs(UV.x * 2.0 - 1.0);
	ALBEDO = COLOR.rgb * COLOR.a * strength * smoothstep(0.0, 0.8, edge);
}
"""
	mat.shader = sh
	var r := RandomNumberGenerator.new(); r.seed = 77
	for k in range(7):
		var mb := MeshBuilder.new()
		var w := r.randf_range(0.25, 0.7); var h := 4.0
		var top := Color(0.8, 1.0, 0.9, r.randf_range(0.6, 1.0)); var bot := Color(0.6, 0.9, 0.8, 0.0)
		var a := mb.v(Vector3(-w, 0, 0), Vector3.BACK, top, Vector2(0, 0)); var b := mb.v(Vector3(w, 0, 0), Vector3.BACK, top, Vector2(1, 0))
		var c := mb.v(Vector3(w * 1.6, -h, 0), Vector3.BACK, bot, Vector2(1, 1)); var d := mb.v(Vector3(-w * 1.6, -h, 0), Vector3.BACK, bot, Vector2(0, 1))
		mb.quad(a, b, c, d)
		var mi: MeshInstance3D = _layer(mb.instance(mat))
		mi.position = Vector3(r.randf_range(-4.0, 4.0), 0, r.randf_range(-4.0, 4.0))
		mi.set_meta("phase", r.randf() * TAU)
		shafts.add_child(mi)

func _build_motes() -> void:
	motes = CPUParticles3D.new()
	var qm := QuadMesh.new(); qm.size = Vector2(0.006, 0.006)
	motes.mesh = qm
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; m.albedo_color = Color(0.8, 0.9, 0.8, 0.5)
	motes.material_override = m
	motes.amount = 70; motes.lifetime = 7.0; motes.preprocess = 7.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; motes.emission_sphere_radius = 2.6
	motes.direction = Vector3(0, 1, 0); motes.spread = 180.0
	motes.initial_velocity_min = 0.01; motes.initial_velocity_max = 0.06
	motes.gravity = Vector3(0.03, 0.01, 0.0)
	motes.local_coords = false; motes.emitting = false
	add_child(_layer(motes))

func _build_minnows() -> void:
	var mb := MeshBuilder.new()
	mb.sphere(0, 0, 0, 0.035, 0.009, 0.006, Color("#b8c0b8"), 6, 4)
	mb.sphere(0.004, 0.003, 0, 0.026, 0.004, 0.0065, Color("#5a6a5a"), 6, 3)
	mb.face([Vector3(-0.03, 0, 0), Vector3(-0.048, 0.01, 0), Vector3(-0.048, -0.01, 0)], Color("#9aa49a"))
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mb.commit(); mm.instance_count = 26
	minnows = MultiMeshInstance3D.new(); minnows.multimesh = mm; minnows.material_override = Mats.vcol
	minnows.top_level = true
	add_child(_layer(minnows))

func _build_frame() -> void:
	frame = PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.02, 0.05, 0.05, 0.9); sb.set_corner_radius_all(10)
	sb.border_color = Color(0.75, 0.85, 0.8, 0.55); sb.set_border_width_all(2)
	sb.content_margin_left = 4; sb.content_margin_right = 4; sb.content_margin_top = 4; sb.content_margin_bottom = 4
	frame.add_theme_stylebox_override("panel", sb)
	frame.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	frame.offset_right = -16; frame.offset_left = -16 - 448; frame.offset_top = 58; frame.offset_bottom = 58 + 256
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex = TextureRect.new(); tex.texture = vp.get_texture()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.custom_minimum_size = Vector2(440, 248); tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(tex)
	var l := Label.new(); l.text = "UNDERWATER"; l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.85, 0.95, 0.9, 0.75))
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	l.position = Vector2(10, 6)
	tex.add_child(l)
	frame.modulate.a = 0.0; frame.visible = false
	fishing.ui.get_child(0).add_child(frame)

# ---------------------------------------------------------------- the water round the lure
func surface_at(p: Vector3) -> float:
	return fishing.water_at(p)

func bed_at(p: Vector3) -> float:
	return game.world.H(p.x, p.z)

## where the hook hangs under the float: about halfway down, never in the mud
func hook_point(p: Vector3) -> Vector3:
	var wy: float = surface_at(p)
	if wy == INF: return p
	var depth: float = wy - bed_at(p)
	return Vector3(p.x, wy - clampf(depth * 0.5, 0.12, 0.75), p.z)

func step(dt: float) -> void:
	t += dt
	# the main view never draws the underwater-only bits
	var main: Camera3D = game.get_viewport().get_camera_3d()
	if main and main != cam: main.cull_mask = main.cull_mask & ~LAYER
	var st: String = fishing.state
	var on: bool = (st == "wait" or st == "fight") and fishing.rod.visible
	show_k = move_toward(show_k, 1.0 if on else 0.0, dt * 2.5)
	frame.visible = show_k > 0.01
	frame.modulate.a = show_k
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if frame.visible else SubViewport.UPDATE_DISABLED
	motes.emitting = frame.visible
	hook.visible = on and st == "wait"
	minnows.visible = frame.visible
	shafts.visible = frame.visible
	line_im.clear_surfaces()
	if not frame.visible:
		if fish_node: fish_node.visible = false
		_fresh = true
		return
	var f: Dictionary = fishing.fish
	var lure: Vector3 = fishing.lure
	var hp: Vector3 = hook_point(lure)
	var wy: float = surface_at(lure)
	if wy == INF: wy = lure.y
	# the hook, swaying a little, and the line up to the float
	if st == "wait":
		hook.global_position = hp + Vector3(sin(t * 1.3) * 0.015, sin(fishing.jig_t / 0.3 * PI) * 0.12, 0)
		_line(Vector3(lure.x, wy, lure.z), hook.global_position + Vector3(0, 0.05, 0))
	# the fish
	var fp: Vector3 = hp
	var fdir := Vector3.RIGHT
	if not f.is_empty() and (st == "fight" or f.has("pos")):
		if int(f.get("uid", -2)) != fish_uid: _new_fish(f)
		if st == "fight":
			var w: Vector3 = fishing._fish_world()
			fp = hook_point(w)
			var ang: float = float(f.ang) + PI / 2.0 * signf(float(f.run) + 0.001)
			fdir = Vector3(sin(ang), 0, cos(ang)) if absf(float(f.run)) > 0.5 else (game.player.global_position - w).normalized()
			_line(Vector3(w.x, wy, w.z) + (game.player.global_position - w).normalized() * 3.0 + Vector3(0, 0.0, 0), fp + Vector3(0.0, 0.02, 0))
		else:
			var p: Vector3 = f.pos
			fp = hook_point(p)
			var to: Vector3 = hp - fp; to.y = 0
			fdir = to.normalized() if to.length() > 0.02 else Vector3.RIGHT
			if f.phase == "nibble" and float(f.get("dip", 0.0)) > 0.0: fp += fdir * 0.06      # darting in for a nibble
			if f.phase == "spooked": fdir = -fdir
			fp.x -= fdir.x * float(f.len) / 200.0; fp.z -= fdir.z * float(f.len) / 200.0       # its mouth at the hook, not its middle
		fish_node.visible = true
		var yaw: float = atan2(-fdir.z, fdir.x)
		var wig := sin(t * (14.0 if st == "fight" else 6.0)) * (0.16 if st == "fight" else 0.07)
		fish_node.global_transform = Transform3D(Basis(Vector3.UP, yaw + wig).scaled(Vector3.ONE * 1.5), fp)      # a touch bigger than life, so you can read it
	elif fish_node:
		fish_node.visible = false
	# the school wanders round near the lure
	school_c = school_c.lerp(hp + Vector3(sin(t * 0.13) * 2.5, 0, cos(t * 0.11) * 2.5), minf(1.0, dt * 0.4)) if not _fresh else hp + Vector3(2, 0, 1)
	_school(school_c, wy)
	# the camera: off to the side of the line, level with the action, inside the water
	var target: Vector3 = fp if (st == "fight" or not f.is_empty()) else hp
	if st == "wait" and not f.is_empty(): target = (fp + hp) * 0.5
	var pl: Vector3 = game.player.global_position
	var away: Vector3 = target - pl; away.y = 0; away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	var side: Vector3 = away.cross(Vector3.UP).normalized()
	# with a fish about, sit off its flank so you see it side-on: the shape that tells you what it is
	if fish_node and fish_node.visible and absf(fdir.y) < 0.9:
		var fs := Vector3(fdir.x, 0, fdir.z).cross(Vector3.UP).normalized()
		side = fs if fs.dot(side) >= 0.0 else -fs
	var want: Vector3 = target + side * 1.5 - away * 0.3
	for k in range(3):
		if surface_at(want) != INF: break
		want = target + (-side if k == 0 else side) * (1.5 - k * 0.4) + away * 0.3 * k
	var sy: float = surface_at(want); if sy == INF: sy = wy
	want.y = clampf(target.y + 0.04, bed_at(want) + 0.12, sy - 0.08)
	if _fresh: cam_pos = want; cam_look = target; _fresh = false
	cam_pos = cam_pos.lerp(want, minf(1.0, dt * 2.0))
	cam_look = cam_look.lerp(target, minf(1.0, dt * 4.0))
	cam.global_position = cam_pos
	if cam_pos.distance_to(cam_look) > 0.05: cam.look_at(cam_look, Vector3.UP)
	motes.global_position = cam_pos
	# light from the surface: shafts round the camera, swaying
	shafts.global_position = Vector3(cam_look.x, wy - 0.02, cam_look.z)
	for s: Node3D in shafts.get_children():
		var ph: float = s.get_meta("phase")
		s.scale = Vector3(1.0 + 0.25 * sin(t * 0.7 + ph), 1, 1)
	# murkier in the creek's tea-coloured water, clearer and bluer in the lake
	if game.world.lake.is_empty():
		env.fog_light_color = Color(0.14, 0.24, 0.16); env.background_color = Color(0.1, 0.2, 0.13); env.fog_density = 0.22
		env.ambient_light_color = Color(0.45, 0.58, 0.42)

func _line(a: Vector3, b: Vector3) -> void:
	var c: Vector3 = cam.global_position
	var along := (b - a).normalized()
	var side := along.cross((c - a).normalized()).normalized() * 0.003
	line_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in [a - side, b - side, b + side, a - side, b + side, a + side]: line_im.surface_add_vertex(q)
	line_im.surface_end()

func _new_fish(f: Dictionary) -> void:
	if fish_node: fish_node.queue_free()
	fish_uid = int(f.get("uid", -2))
	var mi: MeshInstance3D = fishing._fish_model(f.name, float(f.len)).instance()
	_layer(mi)
	mi.rotation.x = 0.0
	fish_node = Node3D.new(); fish_node.top_level = true
	fish_node.add_child(mi)
	add_child(fish_node)
	# it swims upright: the model's built lying along x, side on
	mi.rotation = Vector3(0, 0, 0)

func _school(c: Vector3, wy: float) -> void:
	var mm := minnows.multimesh
	for i in range(mm.instance_count):
		var fi := float(i)
		var a := t * (0.35 + 0.05 * sin(fi)) + fi * 0.9
		var p := c + Vector3(cos(a) * (0.6 + 0.3 * sin(fi * 2.1)), sin(t * 0.8 + fi) * 0.12 - 0.15 * sin(fi), sin(a) * (0.6 + 0.3 * cos(fi * 1.7)))
		var b: float = bed_at(p)
		p.y = clampf(p.y, b + 0.12, wy - 0.1)
		var d := Vector3(-sin(a), 0, cos(a))
		var yaw := atan2(-d.z, d.x) + sin(t * 9.0 + fi) * 0.15
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), p))
