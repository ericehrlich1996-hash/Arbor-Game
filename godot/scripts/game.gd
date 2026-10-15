## Level 1, "Earl's dead ash": the intro drive, the client, felling, limbing, bucking, chipping,
## piling rounds behind the shed, and payday. Owns input, interaction, dialogue, objectives and the HUD.
extends Node3D

var world: WorldGen
var truck: Truck
var chipper: Chipper
var earl: Earl
var tree: AshTree
var saw: Saw
var haul: Haul
var player: Player
var hud: Hud
var sun: DirectionalLight3D
var level_root: Node3D
var phase := "title"           # title | hub | intro | play | done
var in_hub := false
var hub: Hub
var objs := {talk = false, felled = false, limbed = false, stacked = false, paid = false}
var aim := {}
var dlg = null
var muffs := false
var money := 0
var title_cam: Camera3D
var clock := 0.0
var seed := 0
var start_time := 0.0
var tests = null
var force_rev := false         # scripted tests hold the throttle without a captured mouse
var on_bed := false
var called_pay := false
var counts := {}
var rack_saw: MeshInstance3D
# intro
var intro := {}
var path: Array = []
var path_len: Array = []
var can_node: Node3D

const INTRO_DRIVE := 11.0
const INTRO_DRINK := 4.4
const INTRO_OUT := 2.4

func _ready() -> void:
	_setup_input()
	_setup_env()
	hud = Hud.new(); add_child(hud)
	hud.start_pressed.connect(_on_start)
	hud.next_job_pressed.connect(func(): Hub.come_home = true; get_tree().reload_current_scene())
	hud.job_chosen.connect(start_job)
	hud.computer_closed.connect(_close_computer)
	var car := Career.load()
	money = car.money
	Mats.set_truck_rust(car.truck_rust)
	var test_name := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="): test_name = a.substr(7)
	if test_name == "" or test_name.begins_with("hub"): enter_hub()
	else: new_level(randi() % 1000000 + 1)
	Sfx.start_ambience()
	_prewarm_shaders()
	if OS.get_environment("ARBOR_LOW") != "": set_detail(0)
	if test_name != "":
		tests = load("res://scripts/tests.gd").new()
		add_child(tests)
		tests.run(self, test_name)

# ================================================================ home
func enter_hub() -> void:
	in_hub = true
	if level_root: level_root.queue_free()
	level_root = Node3D.new(); level_root.name = "Level"; add_child(level_root)
	hub = Hub.new(); hub.name = "Home"; level_root.add_child(hub)
	hub.build(self)
	world = hub.world
	truck = hub.truck
	player = hub.player
	weather = Weather.new(); weather.name = "Weather"; level_root.add_child(weather)
	weather.setup(self, randi() % 100000)
	ambient = Ambient.new(); ambient.name = "Ambient"; level_root.add_child(ambient)
	ambient.setup(Vector3(0, world.H(0, 0), 0))
	saw = Saw.new(); saw.name = "Saw"; player.hands.add_child(saw)
	saw.setup(self, player)
	hud.set_play_visible(false)
	hub.title_cam.make_current()
	if Hub.come_home:
		Hub.come_home = false
		hub_begin()
		hud.toast("Home again. $%d in the bank." % money, 3.5)
	else:
		phase = "title"
		hud.title.visible = true

func _on_start() -> void:
	if in_hub: hub_begin()
	else: start_intro()

func hub_begin() -> void:
	phase = "hub"
	hud.title.visible = false
	hud.set_play_visible(true)
	for n in [hud.obj_panel, hud.hotbar, hud.tilt]: n.visible = false
	hub.begin()
	if tests == null: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.fade.color.a = 1.0
	create_tween().tween_property(hud.fade, "color:a", 0.0, 1.0)
	if not hud.toast_lbl.visible or hud.toast_lbl.text == "": hud.toast("Home sweet home. The old computer in the corner is where the work comes in.", 5.0)

const JOBS := [
	{title = "Earl's dead ash", pay = 400, open = true,
		text = "Old fella out on Birch Rd. Dead ash in the yard, leaning. Drop it, limb it, chip the brush, stack the rounds behind his shed."},
	{title = "-- nothing else yet --", pay = 0, open = false, text = "Word gets around. Check back after a job or two."},
]

func open_computer() -> void:
	hub.busy = true
	hud.set_prompt("")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play("blip")
	hud.show_computer(JOBS, money, Career.load().jobs)

func _close_computer() -> void:
	hub.busy = false
	if tests == null: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func start_job(_idx: int) -> void:
	Sfx.play("ding")
	var tw := create_tween()
	tw.tween_property(hud.fade, "color:a", 1.0, 0.7)
	tw.tween_callback(func():
		in_hub = false
		hub = null
		hud.set_play_visible(false); hud.set_prompt("")
		new_level(randi() % 1000000 + 1)
		_prewarm_shaders()
		start_intro())

func _hub_input(ev: InputEvent) -> void:
	if phase != "hub": return
	if hud.pc_screen.visible:
		if ev is InputEventKey and ev.pressed and ev.physical_keycode == KEY_ESCAPE: hud.hide_computer(); _close_computer()
		return
	if ev is InputEventMouseButton and ev.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED; return
	if ev is InputEventKey and ev.pressed and ev.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE; return
	if ev.is_action_pressed("help"): hud.help.visible = not hud.help.visible; return
	if ev.is_action_pressed("interact") or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT): hub.interact()

func _setup_input() -> void:
	var keys := {
		move_fwd = [KEY_W, KEY_UP], move_back = [KEY_S, KEY_DOWN], move_left = [KEY_A, KEY_LEFT], move_right = [KEY_D, KEY_RIGHT],
		jump = [KEY_SPACE], run = [KEY_SHIFT], crouch = [KEY_C, KEY_CTRL], interact = [KEY_E], drop = [KEY_Q], kick = [KEY_F],
		throw = [KEY_G], drag = [KEY_T], tool1 = [KEY_1], tool2 = [KEY_2], tool3 = [KEY_3], saw_start = [KEY_R], help = [KEY_H], camera = [KEY_V],
	}
	for act in keys:
		if not InputMap.has_action(act): InputMap.add_action(act)
		for k in keys[act]:
			var ev := InputEventKey.new(); ev.physical_keycode = k
			InputMap.action_add_event(act, ev)
	for act in [["rev", MOUSE_BUTTON_RIGHT], ["use", MOUSE_BUTTON_LEFT]]:
		if not InputMap.has_action(act[0]): InputMap.add_action(act[0])
		var mb := InputEventMouseButton.new(); mb.button_index = act[1]
		InputMap.action_add_event(act[0], mb)

## sky: blue overhead, hazy at the horizon, a warm sun with a glow round it, and soft fair-weather clouds
const SKY_SHADER := """
shader_type sky;
uniform vec3 top_color : source_color = vec3(0.29, 0.5, 0.76);
uniform vec3 horizon_color : source_color = vec3(0.78, 0.85, 0.9);
uniform vec3 ground_color : source_color = vec3(0.36, 0.42, 0.3);
uniform float cover = 0.0;      // 0 fair-weather clouds .. 1 a solid grey lid
uniform float grey = 0.0;       // how much the whole sky goes grey (fog, rain)
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}
void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.55, y));
	if (y < 0.0) col = mix(horizon_color, ground_color, smoothstep(0.0, -0.25, y));
	float sd = 0.0;
	if (LIGHT0_ENABLED) {
		sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
		col += LIGHT0_COLOR * (pow(sd, 900.0) * 6.0 + pow(sd, 24.0) * 0.3 + pow(sd, 4.0) * 0.06);
	}
	if (y > 0.0) {
		vec2 uv = d.xz / (y + 0.12) * 0.55;
		float c = fbm(uv * 1.3 + vec2(3.0, 1.0));
		c = smoothstep(0.5 - cover * 0.48, 0.78 - cover * 0.3, c) * smoothstep(0.02, 0.22, y);
		float shade = 0.82 + 0.18 * fbm(uv * 2.6 + vec2(-1.0, 2.0)) + 0.25 * pow(sd, 6.0) * (1.0 - cover);
		vec3 cloud = mix(vec3(1.0, 0.98, 0.95), vec3(0.52, 0.55, 0.58), cover) * shade;
		col = mix(col, cloud, c * mix(0.85, 1.0, cover));
	}
	col = mix(col, vec3(0.62, 0.65, 0.67) * (0.8 + 0.2 * smoothstep(-0.2, 0.6, y)), grey);
	COLOR = col;
}
"""

func _setup_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new(); var ssh := Shader.new()
	ssh.code = SKY_SHADER
	sm.shader = ssh
	sky.sky_material = sm; env.sky = sky
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color("#c9d2b0")
	env.ambient_light_energy = 0.95
	env.ambient_light_sky_contribution = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.25; env.glow_bloom = 0.04
	env.fog_enabled = true
	env.fog_light_color = Color("#dcd6c0"); env.fog_density = 0.0022; env.fog_sky_affect = 0.15; env.fog_aerial_perspective = 0.3
	env.fog_sun_scatter = 0.25
	if OS.has_feature("web"): env.tonemap_exposure = 1.08      # browsers present the frame a touch darker
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	sky_mat = sm
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(145), 0)     # warm afternoon light from behind your shoulder on the drive in
	sun.light_energy = 1.3; sun.light_color = Color("#ffe2b8")
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 60
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)

# ================================================================ graphics detail
var detail := 1
var done_frac := 0.0
var timelapse: Timelapse
var ambient: Ambient
var sky_mat: ShaderMaterial
var weather: Weather
var _fps_t := 0.0
var _fps_frames := 0
var _fps_checked := false

## low detail pulls the forest's draw distances in and turns off sun shadows, for slower machines
func set_detail(d: int) -> void:
	detail = d
	sun.shadow_enabled = d == 1
	var k := 1.0 if d == 1 else 0.55
	RenderingServer.global_shader_parameter_set(&"detail_k", k)
	if level_root == null: return
	for n in level_root.find_children("*", "GeometryInstance3D", true, false):
		if n.has_meta("vr"):
			var vr: Vector2 = n.get_meta("vr")
			(n as GeometryInstance3D).visibility_range_begin = vr.x * k
			(n as GeometryInstance3D).visibility_range_end = vr.y * (k if vr.y < 200.0 else (0.65 if d == 0 else 1.0))

## if the first few seconds of play run badly, drop to low detail once and say so
## watch the frame rate from the start of the drive in: if it's struggling, drop to low detail early
## (rather than after you're already playing), once, and say so
func _watch_fps(dt: float) -> void:
	if _fps_checked or (phase != "play" and phase != "intro" and phase != "hub") or tests != null: return
	_fps_t += dt
	if _fps_t < 1.0: return              # the first moment is always lumpy
	_fps_frames += 1
	if _fps_t > 4.0:
		_fps_checked = true
		if _fps_frames / (_fps_t - 1.0) < 26.0 and detail == 1:
			set_detail(0)
			hud.toast("Running slow, so I lowered the graphics detail. F3 switches it back.", 4.0)

# ================================================================ a new property
func new_level(sd: int) -> void:
	seed = sd
	in_hub = false
	if level_root: level_root.queue_free()
	level_root = Node3D.new(); level_root.name = "Level"; add_child(level_root)
	world = WorldGen.new(); world.setup(sd); world.build(level_root)
	ambient = Ambient.new(); ambient.name = "Ambient"; level_root.add_child(ambient)
	weather = Weather.new(); weather.name = "Weather"; level_root.add_child(weather)
	weather.setup(self, sd)
	ambient.setup(Vector3(0, world.H(0, 0), 0))
	var rng := RandomNumberGenerator.new(); rng.seed = sd + 99
	truck = Truck.new(); truck.name = "Truck"
	level_root.add_child(truck)
	truck.setup(rng)
	_build_path()
	_place_on_path(path_len[path_len.size() - 1])
	chipper = Chipper.new(); chipper.name = "Chipper"
	level_root.add_child(chipper)
	chipper.setup(truck)
	chipper.world = world
	chipper.hitch_now()
	rack_saw = Models.chainsaw().instance(); chipper.add_child(rack_saw)
	rack_saw.transform = Transform3D(Basis(Vector3.BACK, -0.08) * Basis(Vector3.UP, PI), Vector3(-0.74, 0.36, -1.78))
	rack_saw.visible = false
	tree = AshTree.new(); tree.name = "Ash"; level_root.add_child(tree)
	tree.setup(self, world)
	tree.fell.connect(_on_fell)
	earl = Earl.new(); earl.name = "Earl"; level_root.add_child(earl)
	earl.setup(world, world.old_man)
	player = Player.new(); player.name = "Player"; level_root.add_child(player)
	var out := truck.global_transform * Vector3(1.75, 0, 0.15)
	player.teleport(Vector3(out.x, world.H(out.x, out.z) + 0.05, out.z), truck.rotation.y + PI)
	saw = Saw.new(); saw.name = "Saw"; player.hands.add_child(saw)
	saw.setup(self, player)
	haul = Haul.new(); haul.name = "Haul"; add_child(haul)
	haul.setup(self)
	title_cam = Camera3D.new(); title_cam.fov = 60; level_root.add_child(title_cam); title_cam.make_current()
	timelapse = Timelapse.new(); timelapse.name = "Timelapse"; level_root.add_child(timelapse)
	timelapse.setup(self)
	objs = {talk = false, felled = false, limbed = false, stacked = false, paid = false}
	called_pay = false
	update_objectives()

# ---------------------------------------------------------------- the drive in
func _build_path() -> void:
	var s := world.s
	var ctrl := [Vector2(s * 70, world.road_z - 1.8), Vector2(s * 40, world.road_z - 1.8), Vector2(s * 22, world.road_z - 1.6)]
	for i in range(5): ctrl.append(world.drive[i])
	path = WorldGen._spline(ctrl, 10)
	path_len = [0.0]
	for i in range(1, path.size()): path_len.append(path_len[i - 1] + (path[i] - path[i - 1]).length())

func _path_at(d: float) -> Vector2:
	d = clampf(d, 0, path_len[path_len.size() - 1])
	var i := 1
	while i < path_len.size() - 1 and path_len[i] < d: i += 1
	var t: float = (d - path_len[i - 1]) / maxf(path_len[i] - path_len[i - 1], 1e-4)
	return path[i - 1].lerp(path[i], t)

func _place_on_path(d: float) -> void:
	var p := _path_at(d); var p2 := _path_at(d + 1.6); var p0 := _path_at(d - 1.6)
	var tg := (p2 - p0).normalized()
	var yaw := atan2(tg.x, tg.y)
	var hf := world.H(p.x + tg.x * 1.6, p.y + tg.y * 1.6); var hb := world.H(p.x - tg.x * 1.6, p.y - tg.y * 1.6)
	var pitch := atan2(hf - hb, 3.2)
	var y := (hf + hb) * 0.5 + 0.02
	truck.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch), Vector3(p.x, y, p.y))

func start_intro() -> void:
	phase = "intro"
	hud.title.visible = false
	intro = {t = 0.0, d = 0.0, flags = {}}
	truck.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	truck.freeze = true
	_place_on_path(0)
	chipper.hitch_now()
	chipper.follow_kinematic(true)
	player.visible = false
	truck.mirror_live = true; truck.mirror_div = 6     # just a glance during the drive in
	truck.cab_cam.make_current()
	truck.cab_cam.rotation = Vector3(-0.06, PI, 0)
	intro.eng = Sfx.engine("truck")
	can_node = Node3D.new(); truck.cab_cam.add_child(can_node)
	var can_mi := Models.can().instance(); can_mi.position = Vector3(0, -0.02, 0); can_node.add_child(can_mi)
	var hand := Models.fist(1).instance(); hand.position = Vector3(0.0, 0.07, 0.0); hand.rotation = Vector3(0, 0, PI / 2); can_node.add_child(hand)
	for c in [can_mi, hand]: c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	can_node.visible = false
	hud.intro_card.text = "Job 1 · Earl's dead ash"
	hud.fade.color.a = 1.0
	create_tween().tween_property(hud.fade, "color:a", 0.0, 1.5)

func _step_intro(dt: float) -> void:
	var I := intro
	I.t += dt
	var L: float = path_len[path_len.size() - 1]
	var td := clampf(I.t / INTRO_DRIVE, 0, 1)
	var d := L * (1 - pow(1 - smoothstep(0, 1, td), 1.15))
	var speed: float = (d - I.d) / maxf(dt, 1e-3)
	I.d = d
	_place_on_path(d)
	chipper.trail(dt)
	for w in truck.wheels:
		var wm: Node3D = w.get_child(0)
		wm.rotation.x += speed * dt / Models.WHEEL_R
	if I.has("eng") and I.eng:
		I.eng.setv(clampf(speed / 9, 0, 1) * (1.0 if I.t < INTRO_DRIVE else 0.0) + 0.15, clampf(speed / 12, 0, 0.6), 0.5 if I.t < INTRO_DRIVE + 0.6 else 0.0)
		if I.t > INTRO_DRIVE + 0.6: I.eng.stop(); I.eng = null
	if I.t > INTRO_DRIVE + 0.15 and not I.flags.has("park"): I.flags.park = true; Sfx.play("park", 0.9)
	# the title card
	hud.intro_card.modulate.a = clampf(minf(I.t - 1.0, 9.0 - I.t), 0, 1)
	if I.t > 9.5 and not I.flags.has("om"):
		I.flags.om = true; earl.bark("Over here! OVER HERE! I'm the one that called!", 3.5)
	# the cab camera: a glance at Earl near the end of the drive
	var cam := truck.cab_cam
	var eye := truck.global_transform * Models.EYE
	var to_om := earl.global_position + Vector3(0, 1.5, 0) - eye
	var ty := truck.rotation.y + PI
	var want_yaw := atan2(-to_om.x, -to_om.z)
	var glance := smoothstep(0, 1, clampf((I.t - (INTRO_DRIVE - 4)) / 1.5, 0, 1)) * 0.7 if I.t < INTRO_DRIVE + 0.6 else 0.0
	var rel := clampf(angle_difference(ty, want_yaw), -0.6, 0.6) * glance
	var pitch := -0.06
	# the energy drink
	var t0: float = I.t - INTRO_DRIVE - 0.6
	can_node.visible = t0 > -0.5 and t0 < 4.2
	if can_node.visible:
		var k1 := smoothstep(0, 1, clampf(t0 / 0.8, 0, 1)); var k2 := smoothstep(0, 1, clampf((t0 - 2.6) / 0.4, 0, 1))
		var pos := Vector3(0.2, -0.3, -0.42).lerp(Vector3(0.05, -0.11, -0.3), k1 * (1 - k2))
		var rx := lerpf(0, 1.3, k1 * (1 - k2) * smoothstep(0, 1, clampf((t0 - 0.3) / 0.6, 0, 1)))
		var sc := 1.0
		if t0 > 2.9: sc = lerpf(1, 0.5, clampf((t0 - 2.9) / 0.25, 0, 1))
		var rz := 0.15
		if t0 > 3.6:
			var k := clampf((t0 - 3.6) / 0.6, 0, 1)
			pos = Vector3(0.22, -0.28, -0.42).lerp(Vector3(0.55, -0.5, -0.35), k); pos.y += sin(k * PI) * 0.12; rz = lerpf(0.15, 2.5, k)
		can_node.transform = Transform3D(Basis(Vector3.RIGHT, rx) * Basis(Vector3.BACK, rz) * Basis.from_scale(Vector3(1, sc, 1)), pos)
		pitch += smoothstep(0, 1, clampf(t0 / 0.8, 0, 1)) * smoothstep(0, 1, clampf((3.4 - t0) / 0.6, 0, 1)) * 0.38
		for g in [[0.9, "glug0"], [1.5, "glug1"], [2.1, "glug2"], [2.9, "can_crush"], [4.1, "clank"]]:
			if t0 > g[0] and not I.flags.has(g[1]): I.flags[g[1]] = true; Sfx.play(g[1])
	cam.rotation = Vector3(pitch, PI + rel, 0)
	var t2: float = I.t - INTRO_DRIVE - INTRO_DRINK
	if t2 > 0:
		if not I.flags.has("door"): I.flags.door = true; Sfx.play("door")
		var k := smoothstep(0, 1, clampf((t2 - 0.5) / 1.6, 0, 1))
		var out := truck.global_transform * Vector3(1.75, 0, 0.15); out.y = world.H(out.x, out.z) + 1.62
		cam.global_position = eye.lerp(out, k)
		var face := atan2(-(earl.global_position.x - cam.global_position.x), -(earl.global_position.z - cam.global_position.z))
		cam.global_rotation = Vector3(lerpf(pitch, -0.05, k), lerp_angle(ty + rel, face, smoothstep(0, 1, clampf((t2 - 0.2) / 1.8, 0, 1))), 0)
	if I.t > INTRO_DRIVE + INTRO_DRINK + INTRO_OUT: end_intro()

func end_intro() -> void:
	if phase != "intro": return
	if intro.get("eng"): intro.eng.stop()
	Sfx.play("slam")
	_place_on_path(path_len[path_len.size() - 1])
	truck.freeze = false
	truck.brake = 400
	truck.mirror_live = false
	chipper.follow_kinematic(false)
	chipper.hitch_now()
	player.visible = true
	if can_node: can_node.queue_free(); can_node = null
	truck.cab_cam.position = Models.EYE
	hud.intro_card.modulate.a = 0
	var out := truck.global_transform * Vector3(1.75, 0, 0.15)
	player.teleport(Vector3(out.x, world.H(out.x, out.z) + 0.05, out.z))
	var to := earl.global_position - player.global_position
	player.yaw = atan2(-to.x, -to.z); player.pitch = -0.05
	_start()

## begin play (end of the intro, or straight away in tests)
func _start() -> void:
	phase = "play"
	start_time = clock
	hud.title.visible = false
	hud.set_play_visible(true)
	player.cam.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	earl.state = "wave"
	get_tree().create_timer(4.0).timeout.connect(func(): if earl.state == "wave": earl.state = "idle")
	hud.toast("Click to look around. Walk with WASD. Talk to Earl with E.", 5)
	hud.set_tool(player.tool, muffs)
	if weather: get_tree().create_timer(5.5).timeout.connect(weather.announce)

# ================================================================ input
func _input(ev: InputEvent) -> void:
	if (phase == "play" or phase == "hub") and ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and dlg == null:
		var k := 0.0022
		if player.in_truck: truck.look(ev.relative.x * k, ev.relative.y * k)
		else: player.look(ev.relative.x * k, ev.relative.y * k)
		get_viewport().set_input_as_handled()

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.physical_keycode == KEY_F3:
		set_detail(1 - detail)
		hud.toast("Graphics: " + ("high detail" if detail == 1 else "low detail (faster)") + "  ·  F3 to switch", 2.5)
		return
	if in_hub: _hub_input(ev); return
	if phase == "intro":
		if ev is InputEventKey and ev.pressed and ev.physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]: end_intro()
		return
	if phase != "play": return
	if ev is InputEventMouseButton and ev.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and dlg == null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var k := 0.0022
		if player.in_truck: truck.look(ev.relative.x * k, ev.relative.y * k)
		else: player.look(ev.relative.x * k, ev.relative.y * k)
		return
	if ev is InputEventMouseButton and ev.pressed and (ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		if player.tool == "saw" and not player.in_truck:
			if not saw.guide.is_empty():
				# guided cut: the wheel tilts the cut, in 5° steps (level, a sloping notch top, or an upward cut)
				saw.tilt = clampf(saw.tilt + deg_to_rad(5.0 if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN else -5.0), deg_to_rad(-70), deg_to_rad(70))
			else:
				saw.roll = wrapf(saw.roll + (0.08 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else -0.08), -PI, PI)
		return
	if ev is InputEventKey and ev.pressed and ev.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if dlg != null:
		if ev.is_action_pressed("interact") or ev.is_action_pressed("jump") or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
			advance_dialog()
		return
	if ev.is_action_pressed("help"): hud.help.visible = not hud.help.visible; return
	if player.in_truck:
		if ev.is_action_pressed("interact"): exit_truck()
		elif ev.is_action_pressed("camera"): truck.toggle_cam()
		return
	if ev is InputEventMouseButton and ev.pressed and player.tool == "hands" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if ev.button_index == MOUSE_BUTTON_LEFT and _grab_aimed(): return
		if ev.button_index == MOUSE_BUTTON_RIGHT and haul.carrying():
			# into the truck bed if you're by it, otherwise set one down
			if haul.throw_target() != null: haul.throw_one()
			else: haul.drop_one()
			return
	if ev.is_action_pressed("interact"): interact()
	elif ev.is_action_pressed("drop") and haul.carrying(): haul.drop_one()
	elif ev.is_action_pressed("throw") and haul.carrying(): haul.throw_one()
	elif ev.is_action_pressed("drag"): toggle_drag()
	elif ev.is_action_pressed("kick"): haul.kick()
	elif ev.is_action_pressed("tool1"): equip("hands")
	elif ev.is_action_pressed("tool2"): equip("saw")
	elif ev.is_action_pressed("tool3"): toggle_muffs()
	elif ev.is_action_pressed("crouch"): player.crouch = not player.crouch
	elif ev.is_action_pressed("saw_start") and player.tool == "saw": saw.pull_start()

func equip(t: String) -> void:
	if t == "saw" and saw.racked: hud.toast("The saw is on the chipper rack.", 1.8); return
	if haul.carrying(): haul.drop_all()
	if t != "saw" and saw.on: saw.stop()
	player.tool = t
	hud.set_tool(t, muffs)
	if t == "saw" and not saw.on: hud.toast("Press R to pull-start the saw.", 2.2)

func toggle_muffs() -> void:
	muffs = not muffs
	Sfx.set_muffs(muffs)
	Sfx.play("pick")
	hud.set_tool(player.tool, muffs)

func toggle_drag() -> void:
	if haul.drag != null: haul.stop_drag(); return
	if haul.carrying() or player.in_truck: return
	if aim.get("kind", "") != "piece": return
	var b: WoodPiece = aim.piece
	if b.mass <= Wood.LIFT_MAX and haul.liftable(b): hud.toast("Light enough to pick up (E).", 1.6); return
	if not haul.can_drag(b): hud.toast("Too heavy to drag (%s). Buck it smaller." % lb(b.mass), 2.2); return
	if player.tool == "saw": equip("hands")
	haul.start_drag(b)

static func lb(kg: float) -> String:
	return "%d lb" % roundi(kg * 2.205)

# ================================================================ aiming + interaction
## how directly you're looking at p (1 = dead centre), or -1 if it's out of reach or off to the side
func _near(p: Vector3, max_d: float, min_dot: float) -> float:
	var e := player.eye()
	var to := p - e
	var d := to.length()
	var dot := to.normalized().dot(player.aim_dir())
	if d < max_d and dot > min_dot: return dot
	return -1.0

func compute_aim() -> Dictionary:
	var best := {}
	var e := player.eye(); var dir := player.aim_dir()
	var q := PhysicsRayQueryParameters3D.create(e, e + dir * 2.4)
	q.exclude = [player.get_rid()]
	q.collision_mask = 1 | 4 | 8 | 16 | 32 | 64
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		if hit.collider == earl.body: best = {kind = "earl", t = 2.0}
		elif hit.collider is WoodPiece and hit.collider.mode == "dyn": best = {kind = "piece", piece = hit.collider, t = 1.5, p = hit.position}
	if best.is_empty():
		var d := _near(earl.global_position + Vector3(0, 1.2, 0), 3.2, 0.9)
		if d >= 0: best = {kind = "earl", t = d}
	var cand := [
		["truck", truck.global_transform * Vector3(1.05, 1.1, 0.2), 2.2, 0.8],
		["tailgate", truck.global_transform * Vector3(0, 1.1, -2.62), 2.3, 0.55],
		["hitch", chipper.coupler_world(), 2.1, 0.72],
		["chipper", chipper.engine_world(), 2.4, 0.82],
	]
	if player.tool == "saw" or saw.racked: cand.append(["rack", chipper.rack_world(), 2.0, 0.85])
	for c in cand:
		var d := _near(c[1], c[2], c[3])
		if d >= 0 and (best.is_empty() or (best.kind != "piece" and d > best.t) or (best.kind == "piece" and d > 0.97)):
			best = {kind = c[0], t = d}
	return best

## left click with your hands: pick up what you're looking at (adding to what's on your shoulder),
## or feed the chipper if you're carrying brush at the hopper
func _grab_aimed() -> bool:
	var a := aim
	if a.get("kind", "") == "piece":
		var b: WoodPiece = a.piece
		if haul.liftable(b) and (not haul.carrying() or haul.can_add(b)):
			haul.pick_up(b); return true
		if haul.carrying() and haul.liftable(b):
			hud.toast("That's all you can carry. Right click to set one down.", 2.0); return true
	if haul.carrying():
		var brush: bool = haul.carry.any(func(b): return b.chippable())
		if brush and haul.near_hopper() and chipper.running: haul.feed(); return true
	return false

## Compile every shader the level uses up front, behind the title screen, instead of hitching the first time
## each tree, plant or material comes into view: one copy of every mesh, tiny, right in front of the camera
## for a few frames (MultiMesh copies for the instanced plants, since that's a different shader variant).
func _prewarm_shaders() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null: return
	var holder := Node3D.new(); holder.name = "Prewarm"
	add_child(holder)
	holder.global_transform = cam.global_transform * Transform3D(Basis.from_scale(Vector3.ONE * 0.0005), Vector3(0, 0, -1.0))
	var seen := {}
	var i := 0
	for n in level_root.find_children("*", "GeometryInstance3D", true, false):
		var mesh: Mesh = null; var multi := false
		if n is MeshInstance3D: mesh = n.mesh
		elif n is MultiMeshInstance3D and n.multimesh: mesh = n.multimesh.mesh; multi = true
		if mesh == null: continue
		var key := str(mesh.get_instance_id()) + (":m" if multi else "") + str((n as GeometryInstance3D).material_override)
		if seen.has(key): continue
		seen[key] = true
		var gi: GeometryInstance3D
		if multi:
			var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = n.multimesh.use_colors
			mm.mesh = mesh; mm.instance_count = 1
			var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; gi = mmi
		else:
			var mi := MeshInstance3D.new(); mi.mesh = mesh; gi = mi
		gi.material_override = (n as GeometryInstance3D).material_override
		gi.position = Vector3((i % 10) * 0.5 - 2.5, (i / 10) * 0.5 - 1.0, 0)
		i += 1
		holder.add_child(gi)
	# a handful of frames is enough for the renderer to build every pipeline; then let it go
	for f in range(4): await get_tree().process_frame
	holder.queue_free()

## the angle of the cut on the guide, in degrees (+ slopes down into the wood), for the dial
func _guide_tilt() -> float:
	var g: Dictionary = saw.guide
	if g.is_empty(): return rad_to_deg(saw.tilt)
	var f: Vector3 = g.f
	return rad_to_deg(atan2(-f.y, Vector2(f.x, f.z).length()))

## the truck or chipper lying on its side or roof within reach: "truck", "chipper" or ""
func _tipped_near() -> String:
	if player.in_truck or chipper.mode == "hand": return ""
	for pair in [["truck", truck], ["chipper", chipper]]:
		var v: Node3D = pair[1]
		if v.global_transform.basis.y.y < 0.55 and v.global_position.distance_to(player.global_position) < 5.5:
			return pair[0]
	return ""

func interact() -> void:
	var tipped := _tipped_near()
	if tipped != "":
		if tipped == "truck": truck.right_up(world)
		else: chipper.right_up()
		Sfx.play("thud"); hud.toast("Back on its wheels.", 1.6)
		return
	if chipper.mode == "hand":
		if chipper.near_hitch():
			chipper.hitch_now(); Sfx.play("clank"); hud.toast("Hitched.", 1.5)
		else:
			chipper.set_down(); Sfx.play("drop")
		player.speed_mult = 1.0
		return
	if haul.drag != null: haul.stop_drag(); return
	if haul.carrying():
		if aim.get("kind", "") == "piece" and player.tool == "hands" and haul.liftable(aim.piece) and haul.can_add(aim.piece):
			haul.pick_up(aim.piece); return
		var brush: bool = haul.carry.any(func(b): return b.chippable())
		if brush and haul.near_hopper() and chipper.running: haul.feed(); return
		haul.drop_all(); return
	if aim.is_empty(): return
	match aim.kind:
		"earl": talk_to_earl()
		"truck": enter_truck()
		"tailgate": hop_truck()
		"hitch": hitch_action()
		"chipper": toggle_chipper()
		"rack": rack_action()
		"piece":
			var b: WoodPiece = aim.piece
			if player.tool == "saw":
				if not saw.on: hud.toast("The saw is off. R to pull-start it.", 1.8)
				return
			if b.kind == "trunk" and not b.limbs.is_empty() and b.mass > Wood.LIFT_MAX: hud.toast("Can't lift that. Limb it first."); return
			if b.mass > Wood.LIFT_MAX:
				hud.toast(("Too heavy to lift (%s). T to drag it." if haul.can_drag(b) else "Too heavy to lift (%s). Buck it smaller.") % lb(b.mass)); return
			haul.pick_up(b)

func hitch_action() -> void:
	if chipper.mode == "truck":
		chipper.unhitch(); Sfx.play("clank"); hud.toast("Unhitched.", 1.5)
	elif chipper.mode == "free":
		if haul.carrying(): haul.drop_all()
		chipper.grab_tongue(_hand_point()); Sfx.play("pick"); player.speed_mult = 0.55

func _hand_point() -> Vector3:
	var h := player.global_position + player.fwd() * 0.9
	h.y = world.H(h.x, h.z) + 0.55
	return h

func toggle_chipper() -> void:
	if chipper.running:
		chipper.running = false
		if chipper.engine_snd: chipper.engine_snd.stop(); chipper.engine_snd = null
		hud.toast("Chipper off."); return
	Sfx.play("pull")
	get_tree().create_timer(0.5).timeout.connect(func():
		chipper.running = true
		chipper.engine_snd = Sfx.engine("chipper")
		hud.toast("Chipper running.", 1.8))

func rack_action() -> void:
	if saw.racked:
		saw.racked = false; rack_saw.visible = false
		player.tool = "hands"; equip("saw"); Sfx.play("pick")
		return
	if player.tool != "saw": return
	saw.stop(); saw.racked = true; rack_saw.visible = true
	player.tool = "hands"; hud.set_tool("hands", muffs)
	Sfx.play("clank")

func hop_truck() -> void:
	if haul.carry.size() > 1: haul.drop_all()
	if on_bed:
		var o := truck.global_transform * Vector3(0, 0, -3.4)
		var side := truck.global_transform.basis.x * 0.9
		player.teleport(Vector3(o.x + side.x, world.H(o.x, o.z) + 0.05, o.z + side.z))
	else:
		player.teleport(truck.global_transform * Vector3(0, Truck.BED_FLOOR_Y + 0.05, -2.1))
	Sfx.play("step")

func enter_truck() -> void:
	if haul.carrying(): haul.drop_all()
	if haul.drag != null: haul.stop_drag()
	if saw.on: saw.stop()
	player.in_truck = true
	player.visible = false
	player.col_shape.disabled = true
	truck.enter()
	Sfx.play("door")
	truck.engine_snd = Sfx.engine("truck")
	hud.set_play_visible(false); hud.crosshair.visible = false
	hud.drive.visible = true

func exit_truck() -> void:
	truck.exit()
	if truck.engine_snd: truck.engine_snd.stop(); truck.engine_snd = null
	var out := truck.global_transform * Vector3(1.75, 0, 0.15)
	player.teleport(Vector3(out.x, world.H(out.x, out.z) + 0.05, out.z), truck.rotation.y + PI)
	player.pitch = 0
	player.col_shape.disabled = false
	player.in_truck = false; player.visible = true
	player.cam.make_current()
	Sfx.play("slam")
	hud.set_play_visible(true); hud.drive.visible = false

# ================================================================ dialogue
func start_dialog(lines: Array, on_done: Callable = Callable()) -> void:
	dlg = {lines = lines, i = 0, shown = 0.0, on_done = on_done, last_blip = 0.0}
	earl.talking = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if tests == null else Input.mouse_mode
	_render_dialog()

func _render_dialog() -> void:
	var L: Dictionary = dlg.lines[dlg.i]
	var full: String = L.text
	var hint := ""
	if dlg.shown >= full.length(): hint = "Click or E to continue" if dlg.i < dlg.lines.size() - 1 else "Click or E to close"
	hud.show_dialog(L.who, full.substr(0, int(dlg.shown)), hint)

func advance_dialog() -> void:
	var L: Dictionary = dlg.lines[dlg.i]
	if dlg.shown < L.text.length():
		dlg.shown = L.text.length(); _render_dialog(); return
	if dlg.i < dlg.lines.size() - 1:
		dlg.i += 1; dlg.shown = 0.0; _render_dialog(); return
	var cb: Callable = dlg.on_done
	dlg = null; earl.talking = false
	hud.hide_dialog()
	if phase == "play" and tests == null: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if cb.is_valid(): cb.call()

func _step_dialog(dt: float) -> void:
	if dlg == null: return
	var L: Dictionary = dlg.lines[dlg.i]
	if dlg.shown < L.text.length():
		var before := int(dlg.shown)
		dlg.shown = minf(L.text.length(), dlg.shown + dt * 48)
		if L.who == Earl.NAME and int(dlg.shown) != before and clock - dlg.last_blip > 0.07:
			var ch: String = L.text[mini(int(dlg.shown), L.text.length() - 1)]
			if ch.to_lower() != ch.to_upper():
				dlg.last_blip = clock; Sfx.play("blip", 1.0, randf_range(0.85, 1.25))
		_render_dialog()

func talk_to_earl() -> void:
	var E := Earl.NAME
	if not objs.talk:
		start_dialog([
			{who = E, text = "Well it's about dang time! You the tree fella? You look like a tree fella."},
			{who = E, text = "That ash out back's deader'n disco. Them little green beetles got it. Emerald ash borers, the TV called 'em."},
			{who = E, text = "It creaks at me every night. Every. Night. Like it's plottin' somethin'."},
			{who = E, text = "Here's the deal: drop it, chip the branches, and cut the trunk into rounds I can lift. Pile 'em up out behind my shed."},
			{who = E, text = "Four hundred bucks, cash. From my mattress. Don't ask about the mattress."},
			{who = E, text = "Go on, git! And don't drop it on my house."}],
			func(): objs.talk = true; earl.state = "idle"; update_objectives())
		return
	if objs.felled and objs.limbed and objs.stacked and not objs.paid:
		payday(); return
	start_dialog([{who = E, text = Earl.IDLE[randi() % Earl.IDLE.size()]}])

func payday() -> void:
	var g := tree.grade
	var total := 400
	var rows := [["Job: drop, limb, chip and pile", 400]]
	var clean: bool = g.get("open", false) and not g.get("barber", false) and g.notch_pct >= 0.18 and g.notch_pct <= 0.45 and g.notch_angle >= 40 and g.hinge_pct >= 0.05 and g.hinge_pct <= 0.18 and g.dir_err < 15
	if clean: rows.append(["Textbook felling (notch, hinge, aim)", 50]); total += 50
	if g.get("barber", false): rows.append(["Barber chair (Earl is shaken)", -100]); total -= 100
	var mins := (clock - start_time) / 60.0
	if mins < 15: rows.append(["Quick work (under 15 min)", 25]); total += 25
	var E := Earl.NAME
	start_dialog([{who = E, text = "Well I'll be. Look at that. Neat as a pin!"}, {who = E, text = "Here's your money. Mostly twenties. One's Canadian, don't ask."},
		{who = E, text = "I got a buddy with a whole yard of sick maples. I'll put in a good word. Maybe."}],
		func():
			objs.paid = true; update_objectives(); Sfx.play("cash")
			var c := Career.load(); c.money += total; c.jobs += 1; Career.save(c); money = c.money
			var notes := []
			if g.has("notch_pct"):
				if g.open:
					notes.append("Notch: %d%% of the diameter deep, %d° open." % [roundi(g.notch_pct * 100), roundi(g.notch_angle)])
					notes.append("Hinge: %.1f in, %d%% of the diameter." % [g.hinge_in, roundi(g.hinge_pct * 100)])
					notes.append("Fell direction: %d° off the notch." % roundi(g.dir_err))
				else: notes.append("The stem split up the back (barber chair)." if g.barber else "No notch was cut.")
			notes.append("Time: %d min." % roundi(mins))
			phase = "done"
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			hud.show_summary(rows, total, notes, money)
			hud.play_timelapse(timelapse.frames, timelapse.stamps))

func _on_fell(kind: String) -> void:
	hud.shout("BARBER CHAIR!" if kind == "barber" else "TIMBER!")
	saw.cut = null
	if kind == "barber":
		earl.bark("Holy smokes! It split right up the middle!", 3.5)
	else:
		get_tree().create_timer(2.6).timeout.connect(func(): earl.bark(["WHOOO-EE! Did ya feel that in your boots?!", "Timber! I always wanted to yell that.", "Lord, that was louder than my ex-wife."][randi() % 3], 3.5))

# ================================================================ objectives
func pieces() -> Array:
	return level_root.get_children().filter(func(c): return c is WoodPiece and is_instance_valid(c) and c.mode != "gone" and not c.is_queued_for_deletion())

func in_pile(b: WoodPiece) -> bool:
	var p := world.pile
	var c := b.center_world()
	return absf(c.x - p.x) < p.w / 2 + 0.6 and absf(c.z - p.z) < p.d / 2 + 0.6

func update_objectives() -> void:
	var brush := 0; var rounds := 0; var heavy := 0; var piled := 0
	for b in pieces():
		if b.kind == "limb" or b.kind == "wedge":
			if b.mode != "feed" and b.mode != "feedwait": brush += 1
		elif b.kind == "trunk" and not b.limbs.is_empty():
			if b.mass <= Wood.LIFT_MAX:
				if b.mode != "feed" and b.mode != "feedwait": brush += 1      # a liftable top with twigs on is just brush
			else:
				brush += b.limbs.size()
				rounds += 1; heavy += 1
		else:
			rounds += 1
			if b.mass > Wood.LIFT_MAX: heavy += 1
			if in_pile(b) and b.mode == "dyn": piled += 1
	counts = {brush = brush, rounds = rounds, heavy = heavy, piled = piled}
	# by weight: once 95% of the wood is chipped or on the pile, the job's done (crumbs don't count)
	var total := haul.chipped_mass; var brush_kg := 0.0; var done_kg := haul.chipped_mass
	for b in pieces():
		total += b.mass
		if b.mode == "feed" or b.mode == "feedwait": done_kg += b.mass; continue
		var is_brush: bool = b.kind == "limb" or b.kind == "wedge" or (b.kind == "trunk" and not b.limbs.is_empty() and b.mass <= Wood.LIFT_MAX)
		if is_brush: brush_kg += b.mass
		elif in_pile(b) and b.mode == "dyn": done_kg += b.mass
	done_frac = done_kg / maxf(total, 0.001)
	if objs.felled:
		var attached := pieces().any(func(b): return b.kind == "trunk" and not b.limbs.is_empty() and b.mass > Wood.LIFT_MAX)
		objs.limbed = not attached and (brush == 0 or brush_kg <= total * 0.05)
		objs.stacked = objs.limbed and rounds > 0 and done_frac >= 0.95
	var buck_txt := "Buck the stem into liftable rounds and pile them behind the shed"
	if objs.felled and rounds > 0:
		buck_txt += " · %d/%d · %d%%" % [piled, rounds, int(floor(done_frac * 100.0))]
		if heavy > 0: buck_txt += " · %d too heavy" % heavy
	hud.set_objectives([
		[objs.talk, "Talk to Earl"],
		[objs.felled, "Drop the dead ash"],
		[objs.limbed, "Limb it and chip the brush" + (" · %d left" % brush if objs.felled and not objs.limbed else "")],
		[objs.stacked, buck_txt],
		[objs.paid, "Get paid"]])
	if objs.limbed and objs.stacked and not objs.paid and not called_pay:
		called_pay = true
		Sfx.play("ding")
		earl.bark("Hey! Looks done to me! Come get your money!", 6.0)
		hud.toast("Job done. Talk to Earl to get paid.")

# ================================================================ HUD
func _update_hud() -> void:
	hud.money.text = "$%d" % money
	var nc := haul.carry.size()
	if nc > 0:
		var brushy: bool = haul.carry.all(func(b): return b.brushy())
		hud.set_carry(nc, ("piece" if nc == 1 else "pieces") + (" of brush" if brushy else "") if brushy else ("round" if nc == 1 else "rounds"), haul.carry_mass(), Wood.LIFT_MAX, lb)
	else:
		hud.set_carry(0, "", 0.0, 1.0, lb)
	hud.tool_state.text = ("Saw: running" if saw.on else "Saw: off · R to start") if player.tool == "saw" else ""
	hud.tilt.visible = player.tool == "saw" and not player.in_truck and phase == "play"
	hud.set_dial(not saw.guide.is_empty() and not saw.guide.has("ring_c") and player.tool == "saw" and not player.in_truck and phase == "play",
		saw.guide.get("existing") != null and saw.guide.existing.has("f"), _guide_tilt(), saw.guide.get("too_far", false))
	if not saw.guide.is_empty():
		var tdeg := int(round(rad_to_deg(saw.tilt)))
		var ang := "level" if tdeg == 0 else ("%d° down" % tdeg if tdeg > 0 else "%d° up" % -tdeg)
		if saw.guide.has("ring_c") and not saw.guide.get("too_far", false): hud.tilt.text = "Hold right mouse to cut the branch"
		elif saw.guide.get("too_close", false): hud.tilt.text = "Step back a little to get the saw in"
		elif saw.guide.get("too_far", false): hud.tilt.text = "Step closer to cut there"
		elif saw.guide.existing != null: hud.tilt.text = "Carrying on your cut · hold right mouse"
		else: hud.tilt.text = "Wheel to angle the cut · hold right mouse to cut"
	else:
		hud.tilt.text = "Bar roll %d°" % int(rad_to_deg(saw.roll))
	if player.in_truck:
		hud.drive_lbl.text = "[b]W/S[/b] drive · [b]A/D[/b] steer · [b]Space[/b] brake · [b]V[/b] camera · [b]E[/b] get out      [b]%d mph[/b]" % int(truck.speed_mph())
		hud.obj_panel.visible = truck.chase     # out of the way of the rear-view mirror
		hud.set_prompt("")
		return
	hud.obj_panel.visible = true
	var t := ""
	var a := aim
	var tipped := _tipped_near()
	if dlg != null: t = ""
	elif tipped != "": t = "[b]E[/b] Flip the %s back over" % tipped
	elif chipper.mode == "hand":
		t = "[b]E[/b] Hitch it to the truck" if chipper.near_hitch() else "[b]E[/b] Set the tongue down"
	elif haul.drag != null:
		t = "Dragging · %s · [b]T[/b] let go" % lb(haul.drag.b.mass)
	elif haul.carrying():
		var n := haul.carry.size()
		var brush: bool = haul.carry.any(func(b): return b.chippable())
		if a.get("kind", "") == "piece" and player.tool == "hands" and haul.liftable(a.piece) and haul.can_add(a.piece):
			t = "[b]Left click[/b] Grab another · %s total" % lb(haul.carry_mass() + a.piece.mass)
		elif brush and haul.near_hopper() and chipper.running:
			t = "[b]Left click[/b] Feed the chipper" + (" (%d)" % n if n > 1 else "")
		else:
			t = "[b]Right click[/b] %s · [b]E[/b] drop all" % ("Throw one in the truck" if haul.throw_target() != null else "Set one down")
	elif not a.is_empty():
		match a.kind:
			"earl": t = "[b]E[/b] Talk to Earl" + (" · get paid" if objs.limbed and objs.stacked and not objs.paid else "")
			"truck": t = "[b]E[/b] Get in the truck"
			"tailgate": t = "[b]E[/b] Hop down" if on_bed else "[b]E[/b] Hop in the back"
			"hitch": t = "[b]E[/b] Unhitch the chipper" if chipper.mode == "truck" else "[b]E[/b] Grab the tongue"
			"chipper": t = "[b]E[/b] %s the chipper" % ("Stop" if chipper.running else "Start")
			"rack": t = "[b]E[/b] Take the saw" if saw.racked else "[b]E[/b] Hang the saw on the rack"
			"piece":
				var b: WoodPiece = a.piece
				if player.tool == "saw": t = "" if saw.on else "[b]R[/b] Pull-start the saw"
				elif b.kind == "trunk" and not b.limbs.is_empty() and b.mass > Wood.LIFT_MAX: t = lb(b.mass) + (" · [b]T[/b] Drag" if haul.can_drag(b) else "")
				elif b.mass > Wood.LIFT_MAX: t = ("[b]T[/b] Drag · %s" % lb(b.mass)) if haul.can_drag(b) else "%s · too heavy" % lb(b.mass)
				else: t = "[b]Left click[/b] Pick up %s · %s" % [b.label(), lb(b.mass)] + (" · small enough to chip" if b.chippable() and b.kind == "trunk" and b.limbs.is_empty() else "")
	hud.set_prompt(t)

# ================================================================ frame loop
func _physics_process(dt: float) -> void:
	if chipper and chipper.mode == "hand":
		chipper.move_hand(_hand_point(), dt)
	if haul: haul.step_drag(dt)

func _process(dt: float) -> void:
	clock += dt
	_watch_fps(dt)
	var cam := get_viewport().get_camera_3d()
	if ambient and cam: ambient.step(dt, cam.global_position)
	if weather and cam: weather.step(dt, cam.global_position)
	if in_hub:
		hub.step(dt)
		hud.money.text = "$%d" % money
		return
	if timelapse: timelapse.step(dt)
	_step_kick(dt)
	if phase == "title":
		# a slow orbit over the yard, between the house and the dead ash
		var a := clock * 0.04
		var c := Vector3((world.tree.x + world.house.x) * 0.5, 0, (world.tree.z + world.house.z) * 0.5)
		title_cam.global_position = Vector3(c.x + sin(a) * 26, world.H(c.x, c.z) + 21, c.z + cos(a) * 26)
		title_cam.look_at(Vector3(c.x, world.H(c.x, c.z) + 2, c.z))
	elif phase == "intro":
		_step_intro(dt)
	earl.step(dt, player.global_position if phase == "play" else truck.global_position, truck)
	tree.step(dt)
	saw.step_particles(dt)
	haul.step_feed(dt)
	if phase != "play": return
	if not player.in_truck:
		aim = compute_aim()
		var l := truck.bed_local(player.global_position)
		on_bed = absf(l.x) < 1.0 and l.z > -2.7 and l.z < -0.7 and l.y > 0.5
	else:
		aim = {}
	_step_dialog(dt)
	# speed: slowed by what you carry or drag
	player.speed_mult = (0.55 if chipper.mode == "hand" else 1.0) * (1.0 - haul.carry_mass() / Wood.LIFT_MAX * 0.45) * (0.5 if haul.drag != null else 1.0)
	haul.step_carry(dt)
	# the saw (or bare hands)
	var rev := (Input.is_action_pressed("rev") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and dlg == null) or force_rev
	var show_hands := not player.in_truck
	if player.tool == "saw" and not player.in_truck and not haul.carrying():
		saw.set_visible_tool(true)
		saw.pose(dt, rev, false)
		saw.step(dt, rev, false)
	else:
		saw.model.visible = false
		for m in [saw.fist_r, saw.fist_l, saw.arm_r, saw.arm_l]: m.visible = show_hands
		saw.pose_hands(haul.carrying())
		saw.step(dt, false, true)
	if tree.state == "down":
		_break_under_limbs()
		if not objs.felled and (tree.t - tree.down_t > 5.0 or (is_instance_valid(tree.stem) and tree.stem.sleeping)):
			objs.felled = true; update_objectives(); Sfx.play("ding")
	# Earl heads for the porch once the saw's running near the tree
	if objs.talk and not earl.get_meta("to_porch", false) and saw.on and player.global_position.distance_to(tree.global_position) < tree.T.H:
		earl.set_meta("to_porch", true)
		var h: Dictionary = world.house
		earl.go_to(Vector2(h.x + h.w * 0.18, h.z - h.d / 2 - 1.4))
		earl.bark("I'll be on the porch! If that thing lands on my house I'm keepin' your truck!", 4.0)
	if objs.felled and not objs.paid and dlg == null and clock - earl.last_bark > 38.0:
		earl.last_bark = clock
		earl.bark(Earl.IDLE[randi() % Earl.IDLE.size()], 5.0)
	# engines
	var eng = chipper.engine_snd
	if eng:
		chipper.load = maxf(0, chipper.load - dt * 1.5)
		var d := player.global_position.distance_to(chipper.global_position)
		eng.setv(0.5 + chipper.load * 0.4, chipper.load, clampf(1 - d / 60, 0.05, 1) * 0.55)
	if truck.engine_snd:
		var sp := truck.linear_velocity.length()
		truck.engine_snd.setv(clampf(sp / 9, 0, 1) * 0.85 + 0.15 + absf(truck.engine_force) / 3600.0 * 0.2, clampf(sp / 12, 0, 0.6), 0.5)
	if int(clock * 2) != int((clock - dt) * 2) and objs.felled: update_objectives()
	_update_hud()

## limbs under a stem that's come down snap off instead of propping it up
var _prop_t := 0.0
## branches snap when the tree comes down on them, and a stem left propped up on its branches keeps
## breaking the ones holding it until it lies down (a dead ash's branches are brittle)
func _break_under_limbs() -> void:
	var st: WoodPiece = tree.stem
	if st == null or not is_instance_valid(st) or st.freeze or st.limbs.is_empty(): return
	var fresh: bool = tree.t - tree.down_t < 8.0
	var tilt := absf(st.global_transform.basis.y.normalized().y)       # 0 lying flat, 1 standing up
	var propped := tilt > 0.18 and st.linear_velocity.length() < 1.5
	_prop_t += get_process_delta_time()
	var best_id := -1; var best_low := 1e9
	for id in st.limbs.duplicate():
		var L: Dictionary = st.T.limbs[id]
		var low := 1e9
		for tt in [0.35, 0.7, 1.0]:
			var w := st.to_world(Wood.limb_pt(L, tt))
			low = minf(low, w.y - world.floor_h(w.x, w.z))
		var bw := st.to_world(L.base)
		var base_h := bw.y - world.H(bw.x, bw.z)
		if fresh and low < 0.12 and low < base_h - 0.15:
			_snap_limb(st, id)
		elif propped and low < 0.35 and low < base_h - 0.1 and low < best_low:
			best_low = low; best_id = id
	if best_id >= 0 and _prop_t > 0.25 and is_instance_valid(st) and st.limbs.has(best_id):
		_prop_t = 0.0
		_snap_limb(st, best_id)
		st.sleeping = false

## your leg, for kicking: hip to boot, swung out from under you and back
var kick_leg: Node3D
var kick_t := -1.0
var kick_foot: MeshInstance3D
func _make_leg() -> void:
	kick_leg = Node3D.new()
	var mb := MeshBuilder.new()
	var jeans := Color("#3d5070"); var boot := Color("#4a3626"); var sole := Color("#1e1a16")
	mb.tube(Vector3(0, 0, 0), Vector3(0, -0.48, 0.02), 0.085, 0.07, jeans, 10)
	mb.sphere(0, -0.48, 0.02, 0.072, 0.072, 0.072, jeans, 10, 6)
	mb.tube(Vector3(0, -0.48, 0.02), Vector3(0, -0.88, 0), 0.068, 0.058, jeans, 10)
	mb.cyl(0, -0.86, 0, 0.066, 0.066, 0.05, Color("#4a5d80"), 10, false)          # rolled cuff
	var fb := MeshBuilder.new()          # the boot hinges at the ankle, so the toe stays pointing out
	fb.bevel_box(0, -0.05, -0.06, 0.12, 0.13, 0.26, boot, 0.035)
	fb.box(0, -0.115, -0.06, 0.125, 0.025, 0.28, sole)
	for k in range(4): fb.box(0, 0.02 - k * 0.02, -0.12 + k * 0.025, 0.07, 0.008, 0.008, Color("#d8c890"))
	kick_foot = fb.instance(); kick_foot.position = Vector3(0, -0.88, 0); kick_foot.layers = 16
	kick_foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mi := mb.instance()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 16                   # first person only: the timelapse figure has his own legs
	kick_leg.add_child(mi)
	kick_leg.add_child(kick_foot)
	kick_leg.visible = false
	player.add_child(kick_leg)

func start_kick() -> void:
	if kick_leg == null: _make_leg()
	kick_t = 0.0

func _step_kick(dt: float) -> void:
	if kick_leg == null or kick_t < 0.0: return
	kick_t += dt
	const DUR := 0.5
	if kick_t > DUR: kick_t = -1.0; kick_leg.visible = false; return
	# wind up a touch, snap out, hold a beat, come back
	var u := kick_t / DUR
	var a := 0.0
	if u < 0.15: a = -0.25 * (u / 0.15)
	elif u < 0.35: a = lerpf(-0.25, 1.35, smoothstep(0.0, 1.0, (u - 0.15) / 0.2))
	elif u < 0.55: a = 1.35
	else: a = lerpf(1.35, 0.0, smoothstep(0.0, 1.0, (u - 0.55) / 0.45))
	kick_leg.visible = true
	kick_leg.position = Vector3(0.14, player.eye_h - 0.66, 0.08)
	kick_leg.rotation = Vector3(a, 0, 0.06)
	kick_foot.rotation = Vector3(-a * 0.75, 0, 0)

func _snap_limb(st: WoodPiece, id: int) -> void:
	var lp := Lumber.limb_off(self, st, id)
	if lp: lp.linear_velocity *= 0.5
	Sfx.play("crack", 0.6, randf_range(0.9, 1.3))
	if tree.stem and is_instance_valid(tree.stem): tree.stem.sleeping = false
