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
# the sequence: dive under when the window opens, a close-up on the strike, back up through the surface after
var dive := 1.0                   # 0 above the water .. 1 down at the action
var rise_t := 0.0                 # counting down while the camera comes back up
var zoom_t := 0.0                 # the strike close-up
var was_on := false
var last_phase := ""
var last_state := ""
var last_fp := Vector3.ZERO
var fdir_s := Vector3.RIGHT       # the fish's heading, smoothed from how it's moving
var bubbles: CPUParticles3D
var _crossed := false
var yaw_s := 0.0
var fish_fresh := true

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
	env.glow_enabled = false
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
	_build_shafts()
	_build_motes()
	_build_bubbles()
	_build_minnows()
	_build_frame()

func _layer(m: VisualInstance3D) -> VisualInstance3D:
	m.layers = LAYER
	if m is GeometryInstance3D: (m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m

# ---------------------------------------------------------------- pieces
## light coming down through the surface: soft slanted bands, crossed planes, faded at both ends and
## kept out of the fog (fog on an additive sheet is what made the first try look like slabs)
func _build_shafts() -> void:
	shafts = Node3D.new(); add_child(shafts)
	var mat := ShaderMaterial.new(); var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float strength = 0.11;
void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float down = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.35, 1.0, UV.y));
	float near = smoothstep(0.4, 1.6, -VERTEX.z) * (1.0 - smoothstep(9.0, 16.0, -VERTEX.z));
	float flick = 0.7 + 0.3 * sin(TIME * (0.6 + COLOR.g) + COLOR.b * 30.0);
	ALBEDO = vec3(0.7, 0.95, 0.85) * across * across * down * near * flick * COLOR.a * strength;
}
"""
	mat.shader = sh
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new(); r.seed = 77
	var slant := Vector3(0.35, -1.0, 0.2).normalized()
	for k in range(9):
		var top := Vector3(r.randf_range(-4.0, 4.0), 0.0, r.randf_range(-4.0, 4.0))
		var bot := top + slant * r.randf_range(2.2, 3.4)
		var w := r.randf_range(0.18, 0.5)
		var c := Color(1.0, r.randf(), r.randf(), r.randf_range(0.6, 1.0))
		for k2 in range(2):
			var side := slant.cross(Vector3.UP if k2 == 0 else Vector3.RIGHT).normalized() * w
			var i0 := mb.v(top - side, Vector3.UP, c, Vector2(0, 0.001)); var i1 := mb.v(top + side, Vector3.UP, c, Vector2(1, 0.001))
			var i2 := mb.v(bot + side * 1.5, Vector3.UP, c, Vector2(1, 1)); var i3 := mb.v(bot - side * 1.5, Vector3.UP, c, Vector2(0, 1))
			mb.quad(i0, i1, i2, i3)
	shafts.add_child(_layer(mb.instance(mat)))

func _build_bubbles() -> void:
	bubbles = CPUParticles3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.012; sm.height = 0.024; sm.radial_segments = 6; sm.rings = 3
	bubbles.mesh = sm
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.albedo_color = Color(0.85, 0.97, 1.0, 0.55)
	bubbles.material_override = m
	bubbles.amount = 40; bubbles.lifetime = 1.6; bubbles.one_shot = true; bubbles.explosiveness = 0.85
	bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; bubbles.emission_sphere_radius = 0.25
	bubbles.direction = Vector3.UP; bubbles.spread = 40.0
	bubbles.initial_velocity_min = 0.2; bubbles.initial_velocity_max = 0.6
	bubbles.gravity = Vector3(0, 0.9, 0)
	bubbles.scale_amount_min = 0.5; bubbles.scale_amount_max = 1.6
	bubbles.local_coords = false; bubbles.emitting = false
	add_child(_layer(bubbles))

func _burst(p: Vector3, n := 40) -> void:
	bubbles.global_position = p
	bubbles.amount = n
	bubbles.restart()
	bubbles.emitting = true

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
	# the line's out of the water (landed, lost, reeled in): ride back up through the surface before closing
	if was_on and not on and fishing.rod.visible: rise_t = 1.1
	if on: rise_t = 0.0
	rise_t = maxf(0.0, rise_t - dt)
	was_on = on
	var showing := on or rise_t > 0.0
	show_k = move_toward(show_k, 1.0 if showing else 0.0, dt * 2.5)
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
		last_phase = ""; last_state = ""
		return
	var f: Dictionary = fishing.fish if on else {}
	var lure: Vector3 = fishing.lure
	var hp: Vector3 = hook_point(lure)
	var wy: float = surface_at(lure)
	if wy == INF: wy = lure.y
	# the strike: a close-up and a burst of bubbles when it takes the bait, and again as the hook goes in
	var ph: String = f.get("phase", "")
	if ph == "bite" and last_phase != "bite": zoom_t = 1.4; _burst(hp, 24)
	if st == "fight" and last_state == "wait": zoom_t = 1.8; _burst(hp, 50)
	last_phase = ph; last_state = st
	zoom_t = maxf(0.0, zoom_t - dt)
	var zk := smoothstep(0.0, 0.35, zoom_t)
	_frame_size(zk)
	# the hook, swaying a little, and the line up to the float
	if st == "wait" and on:
		hook.global_position = hp + Vector3(sin(t * 1.3) * 0.015, sin(fishing.jig_t / 0.3 * PI) * 0.12, 0)
		_line(Vector3(lure.x, wy, lure.z), hook.global_position + Vector3(0, 0.05, 0))
	# the fish
	var fp: Vector3 = hp
	var fdir := fdir_s
	if not f.is_empty() and (st == "fight" or f.has("pos")):
		if int(f.get("uid", -2)) != fish_uid: _new_fish(f); last_fp = hook_point(f.get("pos", lure))
		if st == "fight":
			var w: Vector3 = fishing._fish_world()
			fp = hook_point(w)
			var ang: float = float(f.ang) + PI / 2.0 * signf(float(f.run) + 0.001)
			fdir = Vector3(sin(ang), 0, cos(ang)) if absf(float(f.run)) > 0.5 else (game.player.global_position - w).normalized()
			_line(Vector3(w.x, wy, w.z) + (game.player.global_position - w).normalized() * 3.0, fp + Vector3(0.0, 0.02, 0))
		else:
			var p: Vector3 = f.pos
			fp = hook_point(p)
			var to: Vector3 = hp - fp; to.y = 0
			# heading: where it's swimming while it cruises in and circles; nose to the hook once it commits
			var mv := fp - last_fp; mv.y = 0
			if ph == "come" or ph == "circle":
				if mv.length() > 0.0005: fdir = mv.normalized()
			elif ph == "spooked":
				if mv.length() > 0.0005: fdir = mv.normalized()
			elif to.length() > 0.02:
				fdir = to.normalized()
			if ph == "nibble" or ph == "bite":
				# nose right on the hook: its middle sits a half-length back (the model's drawn 1.5x)
				var mouth := float(f.len) / 100.0 * 0.45 * 1.5
				fp = Vector3(hp.x, fp.y, hp.z) - Vector3(fdir.x, 0, fdir.z).normalized() * mouth
				if ph == "nibble" and float(f.get("dip", 0.0)) > 0.0: fp += fdir * 0.06      # darting in for a nibble
		last_fp = fp if st != "wait" else hook_point(f.pos)
		# turn by angle, not by blending vectors (blending opposite headings can swing it the wrong way round)
		var want_yaw: float = atan2(-fdir.z, fdir.x)
		yaw_s = want_yaw if fish_fresh else lerp_angle(yaw_s, want_yaw, minf(1.0, dt * (9.0 if ph == "nibble" or ph == "bite" else 4.0)))
		fish_fresh = false
		fdir_s = Vector3(cos(yaw_s), 0, -sin(yaw_s))
		fish_node.visible = true
		var yaw: float = yaw_s
		var wig := sin(t * (14.0 if st == "fight" else 6.0)) * (0.16 if st == "fight" else 0.07)
		fish_node.global_transform = Transform3D(Basis(Vector3.UP, yaw + wig).scaled(Vector3.ONE * 1.5), fp)      # a touch bigger than life, so you can read it
	elif fish_node:
		fish_node.visible = false
	# the school wanders round near the lure
	school_c = school_c.lerp(hp + Vector3(sin(t * 0.13) * 2.5, 0, cos(t * 0.11) * 2.5), minf(1.0, dt * 0.4)) if not _fresh else hp + Vector3(2, 0, 1)
	_school(school_c, wy)
	# the camera: off to the side, level with the action, inside the water; closer in on the strike,
	# further back in the fight so you can see where it's going
	var target: Vector3 = fp if (st == "fight" or not f.is_empty()) else hp
	if st == "wait" and not f.is_empty() and ph != "bite": target = (fp + hp) * 0.5
	var pl: Vector3 = game.player.global_position
	var away: Vector3 = target - pl; away.y = 0; away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	var side: Vector3 = away.cross(Vector3.UP).normalized()
	if fish_node and fish_node.visible:
		var fs := Vector3(fdir_s.x, 0, fdir_s.z).cross(Vector3.UP).normalized()
		if fs.length() > 0.5: side = fs if fs.dot(side) >= 0.0 else -fs
	var dist := lerpf(2.1 if st == "fight" else 1.5, 0.85, zk)
	var want: Vector3 = target + side * dist - away * 0.3
	for k in range(3):
		if surface_at(want) != INF: break
		want = target + (-side if k == 0 else side) * (dist - k * 0.4) + away * 0.3 * k
	var sy: float = surface_at(want); if sy == INF: sy = wy
	want.y = clampf(target.y + 0.04, bed_at(want) + 0.12, sy - 0.08)
	if _fresh:
		# the dive: start just above the water and sink in
		cam_pos = Vector3(want.x, wy + 0.6, want.z); cam_look = target; _fresh = false
		dive = 0.0; _crossed = false
		Sfx.play("drop", 0.25, 0.7)
	dive = minf(1.0, dive + dt / 1.4)
	var dk := dive * dive * (3.0 - 2.0 * dive)
	cam_pos.x = lerpf(cam_pos.x, want.x, minf(1.0, dt * 2.0)); cam_pos.z = lerpf(cam_pos.z, want.z, minf(1.0, dt * 2.0))
	var y_under := lerpf(cam_pos.y, want.y, minf(1.0, dt * 2.0))
	cam_pos.y = lerpf(wy + 0.6, y_under, dk) if dive < 1.0 else y_under
	if rise_t > 0.0:
		var rk := 1.0 - rise_t / 1.1
		cam_pos.y = lerpf(cam_pos.y, wy + 0.6, minf(1.0, dt * (1.5 + rk * 4.0)))
	if not _crossed and cam_pos.y < wy - 0.05 and on:
		_crossed = true; _burst(Vector3(cam_pos.x, wy - 0.15, cam_pos.z), 50)
	cam_look = cam_look.lerp(target, minf(1.0, dt * 4.0))
	cam.global_position = cam_pos
	if cam_pos.distance_to(cam_look) > 0.05: cam.look_at(cam_look, Vector3.UP)
	# above the surface the camera sees the normal world; below it, the underwater grade
	cam.environment = env if cam_pos.y < wy - 0.02 else null
	motes.global_position = cam_pos
	shafts.global_position = Vector3(cam_look.x, wy - 0.03, cam_look.z)
	# murkier in the creek's tea-coloured water, clearer and bluer in the lake
	if game.world.lake.is_empty():
		env.fog_light_color = Color(0.14, 0.24, 0.16); env.background_color = Color(0.1, 0.2, 0.13); env.fog_density = 0.22
		env.ambient_light_color = Color(0.45, 0.58, 0.42)

## the window grows for the strike close-up, then settles back
func _frame_size(zk: float) -> void:
	var w := lerpf(448.0, 640.0, zk); var h := w * 256.0 / 448.0
	frame.offset_left = -16 - w; frame.offset_bottom = 58 + h
	tex.custom_minimum_size = Vector2(w - 8, h - 8)

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
	fish_fresh = true
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
