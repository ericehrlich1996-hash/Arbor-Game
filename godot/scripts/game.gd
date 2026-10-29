## A job (Earl's dead ash, Widow Hale's leaning maple): the intro drive, the client, felling, limbing,
## bucking, chipping, piling rounds behind the shed, and payday. Owns input, interaction, dialogue, objectives and the HUD.
extends Node3D

var world: WorldGen
var truck: Truck
var chipper: Chipper
var earl: Earl                  # the client (Earl, or Mrs. Hale)
var tree: AshTree
var job: Dictionary = Jobs.EARL
var rig: Rigging                # felling wedges and the pull rope
var fishing: Fishing            # Gus's rod, once you have it
var trailer: Trailer            # Mrs. Hale's job: Walter's trailer, where the rounds go (null elsewhere)
var damage := {}                # "house" / "garage" -> true once a tree's come down on it
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
var touch: TouchControls          # on-screen controls on phones and tablets
# a crew job (see net.gd / net_job.gd)
var net_job: NetJob               # keeping the crew's copies of the job in step (null on your own)
var storm_Ts: Array = []          # the storm job's tree shapes (so a log can say which tree it came from)
var chipper_holder = null         # whoever is walking the chipper by its tongue (you, or a crew member's stand-in)
var _seat_t := -100.0
var phone: PhoneUI

## the mouse is "ours": captured on a computer, always on a touchscreen (there's no pointer to capture)
func cap() -> bool:
	return touch != null or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func _capture() -> void:
	if touch == null and tests == null: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## 3D resolution: phones render at about 1100 across however sharp the screen is; the Resolution
## setting scales that (or the full resolution on a computer) down further
func apply_render_scale() -> void:
	var w := float(get_viewport().get_visible_rect().size.x)
	var base := clampf(1100.0 / maxf(w, 1.0), 0.4, 1.0) if touch else 1.0
	get_viewport().scaling_3d_scale = clampf(base * Settings.res, 0.3, 1.0)

var pause: PauseMenu

## can the pause menu come up now? (not over the title, the computer, a payday card or the intro drive)
func can_pause() -> bool:
	if phase != "play" and phase != "hub": return false
	if hud.pc_screen.visible: return false
	if hud.get("summary") and hud.summary.visible: return false
	if hud.get("title") and hud.title.visible: return false
	return true

func _notification(what: int) -> void:
	# switching apps or tabs: stop the world rather than let it run on unattended
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause and tests == null and can_pause(): pause.open()
var tests = null
var force_rev := false         # scripted tests hold the throttle without a captured mouse
var test_job_done := false     # scripted tests: count the work as finished (to get to payday)
var on_bed := false
var called_pay := false
var called_tarp := false
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
	Net.game = self
	Net.job = null
	_setup_input()
	_setup_env()
	hud = Hud.new(); add_child(hud)
	Ach.game = self
	if TouchControls.wanted():
		touch = TouchControls.new(); touch.name = "Touch"; add_child(touch)
		touch.setup(self)
		Input.emulate_mouse_from_touch = true
		# phones run hot: no MSAA (costly on phone GPUs); Settings.apply caps them at 30 fps by default
		# (90/120 Hz screens would otherwise draw every refresh) and picks low detail
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		get_tree().create_timer(0.5).timeout.connect(func():
			if Settings.detail == -1: set_detail(0)
			Settings.apply(self))
	Settings.load_all()
	get_viewport().size_changed.connect(apply_render_scale)
	pause = PauseMenu.new(); pause.name = "Pause"; add_child(pause); pause.setup(self)
	get_tree().create_timer(3.0).timeout.connect(Ach.retro)
	hud.start_pressed.connect(_on_start)
	hud.next_job_pressed.connect(next_job)
	Net.roster_changed.connect(_crew_changed)
	_crew_changed()
	hud.job_chosen.connect(start_job)
	hud.computer_closed.connect(_close_computer)
	hud.upgrade_chosen.connect(buy_upgrade)
	var car := Career.load()
	money = car.money
	Mats.set_truck_rust(car.truck_rust)
	var test_name := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="): test_name = a.substr(7)
	if test_name == "" or test_name.begins_with("hub") or test_name.begins_with("net"): enter_hub()
	else:
		if test_name.begins_with("hale"): job = Jobs.HALE
		if test_name.begins_with("dock"): job = Jobs.DOCK
		if test_name.begins_with("storm"): job = Jobs.STORM
		new_level(randi() % 1000000)
	Sfx.start_ambience()
	_prewarm_shaders()
	if OS.get_environment("ARBOR_LOW") != "": set_detail(0)
	Settings.apply(self)
	if test_name != "":
		tests = load("res://scripts/net_tests.gd" if test_name.begins_with("net") else "res://scripts/tests.gd").new()
		add_child(tests)
		tests.run(self, test_name)

# ================================================================ home
func enter_hub() -> void:
	in_hub = true
	if level_root: level_root.queue_free()
	level_root = Node3D.new(); level_root.name = "Level"; add_child(level_root)
	hub = Hub.new(); hub.name = "Home"; level_root.add_child(hub)
	hub.build(self)
	set_detail(detail)
	world = hub.world
	truck = hub.truck
	player = hub.player
	Net.job = null
	Net.set_scene("hub")
	Net.scene_reset()
	_crew_spot(player)
	weather = Weather.new(); weather.name = "Weather"; level_root.add_child(weather)
	weather.setup(self, randi() % 100000)
	Sfx.set_ambient_level(1.0)
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
	_capture()
	hud.fade.color.a = 1.0
	create_tween().tween_property(hud.fade, "color:a", 0.0, 1.0)
	if not hud.toast_lbl.visible or hud.toast_lbl.text == "": hud.toast("Home sweet home. The old computer in the corner is where the work comes in.", 5.0)

func open_computer() -> void:
	hub.busy = true
	hud.set_prompt("")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play("blip")
	hud.show_computer(Jobs.board(Career.load().jobs), money, Career.load().jobs, _upgrades())

func _upgrades() -> Array:
	var c := Career.load()
	return [{id = "truck", title = "Fix up the truck", cost = 400, owned = float(c.truck_rust) <= 0.0, done = "DONE",
		text = "Rust cut out and patched, fresh paint, new chrome, clean glass. She'll look like she just rolled off the lot."},
		{id = "wedges", title = "Felling wedges + sledge", cost = 60, owned = bool(c.get("wedges", false)),
		text = "Three orange plastic wedges and a short sledge. Tap them into the back cut to tip a tree toward your notch. Key 4."},
		{id = "rope", title = "Bull rope (150 ft)", cost = 120, owned = bool(c.get("rope", false)),
		text = "Tie it high on the trunk, hook it to the truck's hitch, and pull the tree where it needs to go. Key 5."}]

const UPGRADE_COST := {wedges = 60, rope = 120}
const UPGRADE_MSG := {wedges = "WEDGES AND SLEDGE IN THE TRUCK. PRESS 4 ON THE JOB.", rope = "BULL ROPE IN THE TRUCK. PRESS 5 ON THE JOB."}

func buy_upgrade(id: String) -> void:
	var c := Career.load()
	if UPGRADE_COST.has(id):
		if bool(c.get(id, false)): return
		if int(c.money) < int(UPGRADE_COST[id]):
			hud.show_computer(Jobs.board(c.jobs), money, c.jobs, _upgrades(), "NOT ENOUGH IN THE BANK.")
			return
		c.money -= UPGRADE_COST[id]; c[id] = true
		Career.save(c); money = c.money
		Ach.check_gear()
		Sfx.play("cash")
		hud.show_computer(Jobs.board(c.jobs), money, c.jobs, _upgrades(), UPGRADE_MSG[id])
		return
	if id == "truck" and float(c.truck_rust) > 0.0 and int(c.money) >= 400:
		c.money -= 400; c.truck_rust = 0.0
		Career.save(c); money = c.money
		Ach.check_gear()
		Mats.set_truck_rust(0.0)
		Sfx.play("cash")
		hud.show_computer(Jobs.board(c.jobs), money, c.jobs, _upgrades(), "TRUCK FIXED UP. GO TAKE A LOOK!")

func _close_computer() -> void:
	hub.busy = false
	_capture()

func start_job(idx: int) -> void:
	if Net.is_guest():
		hud.toast("%s picks the work for the crew. Hang tight." % Net.boss_name(), 3.0)
		return
	if idx < 0 or idx >= Jobs.LIST.size(): return
	var need: String = Jobs.LIST[idx].get("needs", "")
	if need != "" and not Jobs.ALL_OPEN and not bool(Career.load().get(need, false)): return
	var variant := randi() % 1000000
	if Net.is_host(): Net.tell("begin", [idx, variant])
	begin_job(idx, variant)

## off to a job (the whole crew goes when the host takes one)
func begin_job(idx: int, variant: int) -> void:
	if idx < 0 or idx >= Jobs.LIST.size(): return
	if hud.pc_screen.visible: hud.hide_computer()
	if phone and phone.visible: phone.close()
	if hub: hub.busy = true
	job = Jobs.LIST[idx]
	Sfx.play("ding")
	var tw := create_tween()
	tw.tween_property(hud.fade, "color:a", 1.0, 0.7)
	tw.tween_callback(func():
		in_hub = false
		hub = null
		hud.set_play_visible(false); hud.set_prompt("")
		new_level(variant)
		_prewarm_shaders()
		start_intro())

func _hub_input(ev: InputEvent) -> void:
	if phase != "hub": return
	if hud.pc_screen.visible:
		if ev is InputEventKey and ev.pressed and ev.physical_keycode == KEY_ESCAPE: hud.hide_computer(); _close_computer()
		return
	if ev is InputEventMouseButton and ev.pressed and not cap():
		_capture(); return
	if ev is InputEventKey and ev.pressed and ev.physical_keycode == KEY_ESCAPE:
		pause.open(); return
	if ev.is_action_pressed("help"): hud.help.visible = not hud.help.visible; return
	var ws: WoodSplit = hub.split
	if ws and ws.active:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed: ws.press()
			else: ws.release()
		elif ev.is_action_pressed("interact"): ws.stop_chopping()
		return
	if ev.is_action_pressed("interact") or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT): hub.interact()

func _setup_input() -> void:
	var keys := {
		move_fwd = [KEY_W, KEY_UP], move_back = [KEY_S, KEY_DOWN], move_left = [KEY_A, KEY_LEFT], move_right = [KEY_D, KEY_RIGHT],
		jump = [KEY_SPACE], run = [KEY_SHIFT], crouch = [KEY_C, KEY_CTRL], interact = [KEY_E], drop = [KEY_Q], kick = [KEY_F],
		throw = [KEY_G], drag = [KEY_T], tool1 = [KEY_1], tool2 = [KEY_2], tool3 = [KEY_3], tool4 = [KEY_4], tool5 = [KEY_5], tool6 = [KEY_6], unstick = [KEY_U], saw_start = [KEY_R], help = [KEY_H], camera = [KEY_V],
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
	# PS2-style look: broad, baked-feeling light - more fill, a gentler sun, softer shadows, no bloom, more haze
	env.ambient_light_energy = 1.0
	env.ambient_light_sky_contribution = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.0
	env.glow_enabled = false
	env.fog_enabled = true
	env.fog_light_color = Color("#c9d2d0"); env.fog_density = 0.0033; env.fog_sky_affect = 0.25; env.fog_aerial_perspective = 0.5
	env.fog_sun_scatter = 0.25
	if OS.has_feature("web"): env.tonemap_exposure = 1.08      # browsers present the frame a touch darker
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	sky_mat = sm
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(145), 0)     # warm afternoon light from behind your shoulder on the drive in
	sun.light_energy = 1.3; sun.light_color = Color("#ffe2b8")
	sun.shadow_enabled = true
	sun.shadow_blur = 2.6
	sun.shadow_opacity = 0.82
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
	# down the long straight county road you'd see miles of woods: draw them shorter there, the haze hides it
	if world != null and world.job == "storm": k *= 0.7
	for n in level_root.find_children("*", "GeometryInstance3D", true, false):
		if n.has_meta("vr"):
			var vr: Vector2 = n.get_meta("vr")
			var vm: float = n.get_meta("vm", 0.0)          # the patch's half-diagonal: plants sit anywhere in it
			(n as GeometryInstance3D).visibility_range_begin = maxf(0.0, vr.x * k - vm) if vr.x > 0.0 else 0.0
			(n as GeometryInstance3D).visibility_range_end = vr.y * k + vm

## if the first few seconds of play run badly, drop to low detail once and say so
## watch the frame rate from the start of the drive in: if it's struggling, drop to low detail early
## (rather than after you're already playing), once, and say so
func _watch_fps(dt: float) -> void:
	if _fps_checked or (phase != "play" and phase != "intro" and phase != "hub") or tests != null or Settings.detail != -1: return
	_fps_t += dt
	if _fps_t < 1.0: return              # the first moment is always lumpy
	_fps_frames += 1
	if _fps_t > 4.0:
		_fps_checked = true
		if _fps_frames / (_fps_t - 1.0) < 26.0 and detail == 1:
			set_detail(0)
			hud.toast("Running slow, so I lowered the graphics detail. F3 switches it back.", 4.0)

# ================================================================ a new property
## a job's property: always the same layout (WorldGen.LAYOUT); "variant" only varies the job tree
func new_level(variant: int) -> void:
	var sd := WorldGen.layout_seed(job.id)
	seed = sd
	in_hub = false
	storm_Ts = []
	chipper_holder = null
	Net.job = null
	Net.set_scene("job:%s:%d" % [job.id, variant])
	Net.scene_reset()
	if level_root: level_root.queue_free()
	level_root = Node3D.new(); level_root.name = "Level"; add_child(level_root)
	world = WorldGen.new(); world.setup(sd, job.id, variant); world.build(level_root)
	set_detail(detail)            # fit the new forest's draw distances to the detail setting (phones: shorter)
	_job_light()
	Mats.bark.albedo_color = job.bark_tint
	ambient = Ambient.new(); ambient.name = "Ambient"; level_root.add_child(ambient)
	weather = Weather.new(); weather.name = "Weather"; level_root.add_child(weather)
	weather.setup(self, variant)       # the weather still changes from visit to visit
	Sfx.set_ambient_level(0.6 if job.id == "hale" or job.id == "dock" else 1.0)     # the lake jobs are quiet spots
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
	tree = AshTree.new(); tree.name = "Maple" if job.id == "hale" else "Ash"; level_root.add_child(tree)
	tree.setup(self, world)
	tree.fell.connect(_on_fell)
	earl = Earl.new(); earl.name = "Client"; level_root.add_child(earl)
	earl.setup(world, world.old_man, job.look)
	earl.mirror = Net.is_guest()
	earl.display = job.who; earl.idle_lines = job.idle
	player = Player.new(); player.name = "Player"; level_root.add_child(player)
	var out := truck.global_transform * Vector3(1.75, 0, 0.15)
	player.teleport(Vector3(out.x, world.H(out.x, out.z) + 0.05, out.z), truck.rotation.y + PI)
	saw = Saw.new(); saw.name = "Saw"; player.hands.add_child(saw)
	saw.setup(self, player)
	haul = Haul.new(); haul.name = "Haul"; add_child(haul)
	haul.setup(self)
	rig = Rigging.new(); rig.name = "Rigging"; level_root.add_child(rig)
	rig.setup(self)
	fishing = Fishing.new(); fishing.name = "Fishing"; level_root.add_child(fishing)
	fishing.setup(self)
	damage = {}
	trailer = null
	if not world.trailer.is_empty():
		trailer = Trailer.new(); trailer.name = "Trailer"; level_root.add_child(trailer)
		trailer.build()
		var tw: Dictionary = world.trailer
		var gy := world.H(tw.x, tw.z + 1.0)
		trailer.global_transform = Transform3D(Basis(Vector3.UP, tw.yaw), Vector3(tw.x, gy, tw.z))
		chipper.trailer = trailer
	hud.obj_title.text = "Job %d · %s" % [job.n, job.title]
	hud.set_owned(Rigging.owned("wedges"), Rigging.owned("rope"), Fishing.owned())
	title_cam = Camera3D.new(); title_cam.fov = 60; level_root.add_child(title_cam); title_cam.make_current()
	timelapse = Timelapse.new(); timelapse.name = "Timelapse"; level_root.add_child(timelapse)
	timelapse.setup(self)
	var logs_job: bool = job.get("kind", "") == "logs"
	var storm_job: bool = job.get("kind", "") == "storm"
	objs = {talk = false, felled = logs_job or storm_job, limbed = false, stacked = false, tarped = trailer == null or logs_job, hauled = not logs_job, paid = false}
	if Net.is_guest():
		# the host's game puts the wood out; here we only need the storm trees' shapes to rebuild it
		for t in world.storm_trees: storm_Ts.append(Wood.make_tree_def(t))
	else:
		if logs_job: _spawn_lake_logs()
		if storm_job: _spawn_storm_trees()
	if storm_job and OS.get_environment("ARBOR_WEATHER") == "": weather.force("overcast")       # the grey morning after
	called_pay = false; called_tarp = false
	if Net.active():
		net_job = NetJob.new(); net_job.name = "NetJob"; level_root.add_child(net_job)
		net_job.setup(self)
	else:
		net_job = null
	update_objectives()

# ---------------------------------------------------------------- the drive in
func _build_path() -> void:
	var s := world.s
	var ctrl := [Vector2(s * 70, world.road_z - 1.8), Vector2(s * 40, world.road_z - 1.8), Vector2(s * 22, world.road_z - 1.6)]
	if world.job == "storm":       # up the county road and pull up short of the trees
		ctrl = [Vector2(s * 115, world.road_z - 1.7), Vector2(s * 95, world.road_z - 1.7), Vector2(s * 75, world.road_z - 1.7)]
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
	hud.intro_card.text = "Job %d · %s" % [job.n, job.title]
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
	truck.scripted_speed = absf(speed) if I.t < INTRO_DRIVE else 0.0
	truck.scripted_engine = I.t < INTRO_DRIVE + 0.6
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
	truck.scripted_speed = -1.0; truck.scripted_engine = false
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
	_crew_spot(player)
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
	_capture()
	earl.state = "wave"
	get_tree().create_timer(4.0).timeout.connect(func(): if earl.state == "wave": earl.state = "idle")
	hud.toast(("Swipe to look around, left thumb to walk. Talk to %s with E." if touch else "Click to look around. Walk with WASD. Talk to %s with E.") % job.who, 5)
	hud.set_tool(player.tool, muffs)
	if weather: get_tree().create_timer(5.5).timeout.connect(weather.announce)

# ================================================================ input
func _input(ev: InputEvent) -> void:
	# on a touchscreen the browser fakes mouse movement from the first finger down (often the move
	# thumb), so mouse look is for computers only; touch looking is the right-thumb swipe in touch.gd
	if touch == null and (phase == "play" or phase == "hub") and ev is InputEventMouseMotion and cap() and dlg == null:
		var k := 0.0022 * Settings.look_sens; var ky := k * (-1.0 if Settings.invert_y else 1.0)
		if player.in_truck: truck.look(ev.relative.x * k, ev.relative.y * ky)
		else: player.look(ev.relative.x * k, ev.relative.y * ky)
		get_viewport().set_input_as_handled()

func _unhandled_input(ev: InputEvent) -> void:
	if pause and pause.is_open(): return
	if phone and phone.visible: return
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.physical_keycode == KEY_F3:
		set_detail(1 - detail)
		Settings.detail = detail; Settings.save()
		hud.toast("Graphics: " + ("high detail" if detail == 1 else "low detail (faster)") + "  ·  F3 to switch", 2.5)
		return
	if in_hub: _hub_input(ev); return
	if phase == "intro":
		if ev is InputEventKey and ev.pressed and ev.physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]: end_intro()
		return
	if phase != "play": return
	if ev is InputEventMouseButton and ev.pressed and not cap() and dlg == null:
		_capture()
		return
	if ev is InputEventMouseMotion and cap():
		if touch != null: return
		var k := 0.0022 * Settings.look_sens; var ky := k * (-1.0 if Settings.invert_y else 1.0)
		if player.in_truck: truck.look(ev.relative.x * k, ev.relative.y * ky)
		else: player.look(ev.relative.x * k, ev.relative.y * ky)
		return
	if ev is InputEventMouseButton and ev.pressed and (ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		if player.tool == "rod" and not player.in_truck and ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and dlg == null:
			fishing.wheel_down()
		elif player.tool == "saw" and not player.in_truck:
			if not saw.guide.is_empty():
				# guided cut: the wheel tilts the cut, in 5° steps (level, a sloping notch top, or an upward cut)
				saw.tilt = clampf(saw.tilt + deg_to_rad(5.0 if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN else -5.0), deg_to_rad(-70), deg_to_rad(70))
			else:
				saw.roll = wrapf(saw.roll + (0.08 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else -0.08), -PI, PI)
		return
	if ev is InputEventKey and ev.pressed and ev.physical_keycode == KEY_ESCAPE:
		pause.open()
		return
	if dlg != null:
		if ev.is_action_pressed("interact") or ev.is_action_pressed("jump") or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
			advance_dialog()
		return
	if ev.is_action_pressed("help"): hud.help.visible = not hud.help.visible; return
	if player.in_truck:
		if ev.is_action_pressed("interact"): exit_truck()
		elif ev.is_action_pressed("camera"): truck.toggle_cam()
		elif ev.is_action_pressed("unstick"):
			if Net.is_guest(): Net.ask("use", ["unstick", net_pose()])
			else: unstick_truck()
		return
	if player.tool == "rod" and ev is InputEventMouseButton and cap():
		if ev.button_index == MOUSE_BUTTON_LEFT: fishing.press(ev.pressed); return
		if ev.button_index == MOUSE_BUTTON_RIGHT: fishing.alt(ev.pressed); return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and (player.tool == "wedge" or player.tool == "rope") and cap():
		if rig.use(): return
	if ev.is_action_pressed("interact") and (player.tool == "wedge" or player.tool == "rope") and rig.prompt().begins_with("[b]"):
		rig.use(); return
	if ev is InputEventMouseButton and ev.pressed and player.tool == "hands" and cap():
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
	elif ev.is_action_pressed("tool4"): _equip_owned("wedge", "wedges", "felling wedges")
	elif ev.is_action_pressed("tool5"): _equip_owned("rope", "rope", "a pull rope")
	elif ev.is_action_pressed("tool6"):
		if Fishing.owned(): equip("rod")
		else: hud.toast("No fishing rod yet. Somebody down by a lake might lend you one.", 3.0)
	elif ev.is_action_pressed("crouch"): player.crouch = not player.crouch
	elif ev.is_action_pressed("unstick"):
		if player.global_position.distance_to(truck.global_position) < 12.0:
			if Net.is_guest(): Net.ask("use", ["unstick", net_pose()])
			else: unstick_truck()
		else: hud.toast("Walk over to the truck to unstick it.", 2.0)
	elif ev.is_action_pressed("saw_start") and player.tool == "saw": saw.pull_start()

func equip(t: String) -> void:
	if t == "saw" and saw.racked: hud.toast("The saw is on the chipper rack.", 1.8); return
	if haul.carrying(): haul.drop_all()
	if t != "saw" and saw.on: saw.stop()
	if fishing and (player.tool == "rod") != (t == "rod"): fishing.equip(t == "rod")
	player.tool = t
	hud.set_tool(t, muffs)
	if t == "saw" and not saw.on: hud.toast("Press R to pull-start the saw.", 2.2)
	if t == "wedge": hud.toast("Wedges: make your notch, start the back cut, then tap a wedge into the kerf behind the bar.", 3.5)
	if t == "rope": hud.toast("Pull rope: tie it on the trunk, hook it on the truck's hitch, then ease the truck away.", 3.5)

func _equip_owned(t: String, id: String, what: String) -> void:
	if not Rigging.owned(id):
		hud.toast("You don't have %s yet. They're on the computer at home, under Upgrades." % what, 3.0); return
	equip(t)

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
	if trailer and objs.stacked and not objs.tarped: cand.append(["trailer", trailer.bed_mid(), 3.6, 0.55])
	if trailer: cand.append(["coupler", trailer.coupler_world(), 2.2, 0.7])
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

## each property has its own time of day: Earl's is a bright early afternoon, the lake house is
## golden hour, the sun low over the water and long shadows across the lawn
func _job_light() -> void:
	if job.id == "hale":
		sun.rotation = Vector3(deg_to_rad(-21), deg_to_rad(205), 0)
		sun.light_color = Color("#ffc27a")
		if sky_mat:
			sky_mat.set_shader_parameter("horizon_color", Color(0.95, 0.78, 0.6))
			sky_mat.set_shader_parameter("top_color", Color(0.32, 0.48, 0.72))
		var env := _env()
		if env: env.fog_light_color = Color("#e8c8a0")
	else:
		sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(145), 0)
		sun.light_color = Color("#ffe2b8")
		if sky_mat:
			sky_mat.set_shader_parameter("horizon_color", Color(0.78, 0.85, 0.9))
			sky_mat.set_shader_parameter("top_color", Color(0.29, 0.5, 0.76))

func _env() -> Environment:
	for c in get_children():
		if c is WorldEnvironment: return c.environment
	return null

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
## the truck's hung up (on a porch, a stump, a log): lift it out and set it down on its wheels at the
## nearest clear spot, facing the way it was, with whatever's hitched brought along behind it
func unstick_truck() -> void:
	Ach.add("unstuck")
	var fwd := truck.global_transform.basis.z; fwd.y = 0
	if fwd.length() < 0.1: fwd = Vector3.BACK
	fwd = fwd.normalized()
	var b := Basis(Vector3.UP, atan2(fwd.x, fwd.z))
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(2.4, 1.3, 6.0)     # the body, from knee height up (the ground under it doesn't count)
	q.shape = box
	q.collision_mask = 1 | 4 | 8
	var ex: Array[RID] = [truck.get_rid(), chipper.get_rid(), player.get_rid()]
	if trailer: ex.append(trailer.get_rid())
	var gnd := level_root.find_child("Ground", true, false) as CollisionObject3D
	if gnd: ex.append(gnd.get_rid())
	q.exclude = ex
	var p0 := truck.global_position
	var spot = null
	for r: float in [0.0, 1.5, 3.0, 4.5, 6.0, 8.0, 10.0, 13.0, 16.0]:
		var n := 1 if r == 0.0 else 16
		for k in range(n):
			# try behind it first (backing out the way it came in), then round about
			var a := PI + (k / 2) * (TAU / n) * (1 if k % 2 == 0 else -1)
			var p := p0 + b * Vector3(sin(a) * r, 0, cos(a) * r)
			p.y = world.H(p.x, p.z)
			# lift the test box clear of the ground's own slope across the truck's length
			var lo := minf(world.H(p.x + fwd.x * 3.0, p.z + fwd.z * 3.0), world.H(p.x - fwd.x * 3.0, p.z - fwd.z * 3.0))
			var hi := maxf(world.H(p.x + fwd.x * 3.0, p.z + fwd.z * 3.0), world.H(p.x - fwd.x * 3.0, p.z - fwd.z * 3.0))
			if hi - lo > 1.2: continue                                    # too steep to park on
			q.transform = Transform3D(b, Vector3(p.x, hi + 0.75, p.z) + b * Vector3(0, 0, -0.3))
			if space.intersect_shape(q, 1).is_empty():
				spot = p; break
		if spot != null: break
	if spot == null: spot = Vector3(world.park.x, world.H(world.park.x, world.park.z), world.park.z)
	var cargo := trailer_cargo()
	var xf := Transform3D(b, spot + Vector3(0, 0.35, 0))
	truck.freeze = false
	truck.global_transform = xf
	PhysicsServer3D.body_set_state(truck.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	truck.linear_velocity = Vector3.ZERO; truck.angular_velocity = Vector3.ZERO
	if trailer and trailer.mode == "truck": trailer.follow_truck(cargo)
	if chipper.mode == "truck": chipper.hitch_now(chipper.tow)
	Sfx.play("thud", 0.8); Sfx.play("clank", 0.5)
	hud.toast("Truck's unstuck.", 2.0)

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
		if Net.is_guest(): Net.ask("use", ["flip_" + tipped, net_pose()]); return
		if tipped == "truck": truck.right_up(world)
		else: chipper.right_up()
		Sfx.play("thud"); hud.toast("Back on its wheels.", 1.6)
		return
	if chipper.mode == "hand" and holding_chipper():
		if Net.is_guest(): Net.ask("use", ["hand", net_pose()]); return
		chipper_hand_action()
		return
	if haul.drag != null: haul.stop_drag(); return
	if haul.carrying():
		if aim.get("kind", "") == "piece" and player.tool == "hands" and haul.liftable(aim.piece) and haul.can_add(aim.piece):
			haul.pick_up(aim.piece); return
		var brush: bool = haul.carry.any(func(b): return b.chippable())
		if brush and haul.near_hopper() and chipper.running: haul.feed(); return
		haul.drop_all(); return
	if aim.is_empty(): return
	if Net.is_guest() and aim.kind in ["hitch", "chipper", "trailer", "coupler"]:
		Net.ask("use", [aim.kind, net_pose()]); return
	match aim.kind:
		"earl": talk_to_earl()
		"truck": enter_truck()
		"tailgate": hop_truck()
		"hitch": hitch_action()
		"chipper": toggle_chipper()
		"rack": rack_action()
		"trailer": tarp_trailer()
		"coupler": trailer_hitch_action()
		"piece":
			var b: WoodPiece = aim.piece
			if player.tool == "saw":
				if not saw.on: hud.toast("The saw is off. R to pull-start it.", 1.8)
				return
			if b.kind == "trunk" and not b.limbs.is_empty() and b.mass > Wood.LIFT_MAX: hud.toast("Can't lift that. Limb it first."); return
			if b.mass > Wood.LIFT_MAX:
				hud.toast(("Too heavy to lift (%s). T to drag it." if haul.can_drag(b) else "Too heavy to lift (%s). Buck it smaller.") % lb(b.mass)); return
			haul.pick_up(b)

## the trailer's tongue: hitch it to the truck (back up close first), or drop it on its jack
func trailer_hitch_action() -> void:
	if trailer == null: return
	if trailer.mode == "truck":
		trailer.unhitch(); Sfx.play("clank"); hud.toast("Trailer unhitched. The jack's down.", 2.0)
		return
	if chipper.mode == "truck" and chipper.tow == truck:
		hud.toast("The chipper's on the truck's ball. Unhitch it, hitch the trailer, then hook the chipper on the back of the trailer.", 5.0)
		return
	if truck.hitch_world().distance_to(trailer.coupler_world()) > 3.5:
		hud.toast("Back the truck up to the trailer's tongue first.", 2.5)
		return
	trailer.hitch_to(truck, trailer_cargo())
	if chipper.mode == "truck" and chipper.tow == trailer: chipper.hitch_now(trailer)
	Sfx.play("clank"); hud.toast("Trailer hitched. The chipper can go on the ball on its back bumper.", 3.5)

## Gus's job: the old log-drive timber floating in the shallows where his dock goes
var lake_logs: Array = []
func _spawn_lake_logs() -> void:
	lake_logs = []
	var T: Dictionary = tree.T
	for L in world.logs:
		var y0 := 2.0; var y1: float = y0 + float(L.len)
		var p := WoodPiece.new(); p.T = T; p.kind = "trunk"; p.y0 = y0; p.y1 = y1
		p.ops = [{type = "clip", p = Vector3(0, y0, 0), n = Vector3.DOWN}, {type = "clip", p = Vector3(0, y1, 0), n = Vector3.UP}]
		level_root.add_child(p)
		var b := Basis(Vector3.UP, float(L.yaw)) * Basis(Vector3.RIGHT, PI / 2)
		var mid := Vector3(float(L.x), float(world.lake.y) - 0.08, float(L.z))
		p.global_transform = Transform3D(b, mid - b * Vector3(0, (y0 + y1) / 2.0, 0))
		p.build()
		p.mass *= 3.0                    # a century in the lake: soaked through, far too heavy to lift or drag by hand
		lake_logs.append(p)

## the sheriff's job: the trees the storm put down across the road, lying where they fell, limbs and all
## (the ones that would be underground broke off in the fall, the ones that hit the road are shortened)
var storm_pieces: Array = []
func _spawn_storm_trees() -> void:
	storm_pieces = []
	for t in world.storm_trees:
		var T := Wood.make_tree_def(t)
		storm_Ts.append(T)
		var d3 := Vector3(t.dir.x, 0, t.dir.y).normalized()
		var lay := Basis(Vector3.UP.cross(d3).normalized(), PI / 2)          # the wood's +y down the trunk, along d3
		# roll it round its own axis so the crown spreads up and sideways rather than into the road
		var best := lay; var best_sc := -1e9
		for k in range(16):
			var b := Basis(d3, TAU * k / 16.0) * lay
			var sc := 0.0
			for L in T.limbs:
				var dy: float = (b * (L.dir as Vector3)).y
				sc += dy * float(L.len) if dy > -0.2 else -3.0 * float(L.len)
			if sc > best_sc: best_sc = sc; best = b
		var y0: float = -0.3 if t.kind == "uproot" else float(t.snap) + 0.05
		var p := WoodPiece.new(); p.T = T; p.kind = "trunk"; p.y0 = y0; p.y1 = T.H
		p.ops = [{type = "clip", p = Vector3(0, y0, 0), n = Vector3.DOWN}]
		for L in T.limbs:
			var dw: Vector3 = best * (L.dir as Vector3)
			var r_ax := Wood.r_at(T, float(L.y))
			var off: float = (best * ((L.base as Vector3) - Vector3(0, float(L.y), 0))).y
			if dw.y < -0.05:
				var reach := (r_ax + off - 0.1) / (-dw.y * float(L.len))
				if reach < 0.3: continue                    # snapped off underneath
				if reach < 1.0: p.lt[L.id] = reach
			p.limbs.append(L.id)
		level_root.add_child(p)
		var gy := world.H(t.x, t.z)
		var butt := Vector3(t.x, gy, t.z) + d3 * (0.15 if t.kind == "uproot" else 1.0 + Wood.r_at(T, y0))
		butt.y = maxf(world.H(butt.x, butt.z), world.road_y() if absf(butt.z - world.road_z) < 4.0 else -1e9) + Wood.r_at(T, y0 + 0.4) + 0.04
		p.global_transform = Transform3D(best, butt - best * Vector3(0, y0, 0))
		p.build()
		storm_pieces.append(p)

## how many pieces of wood are still out in the water
func logs_in_water() -> int:
	if world.lake.is_empty(): return 0
	var n := 0
	for b in pieces():
		if b.kind != "trunk" or b.mode != "dyn": continue
		var c: Vector3 = b.center_world()
		if world.lake_d(c.x, c.z) < -0.4: n += 1
	return n

## water: wood floats (old waterlogged timber rides low, mostly under), and drags; you wade slowly
func _water_step(dt: float) -> void:
	if world == null or world.lake.is_empty(): return
	var wy: float = world.lake.y
	for b in pieces():
		if b.mode != "dyn" or b.freeze: continue
		var c: Vector3 = b.center_world()
		if world.lake_d(c.x, c.z) > 0.5: continue
		var r: float = Wood.r_at(b.T, b.center_wood().y) if b.kind == "trunk" else 0.06
		var sub := clampf((wy - c.y) / (2.0 * r) + 0.5, 0.0, 1.0)
		if sub <= 0.0: continue
		b.apply_central_force(Vector3.UP * b.mass * 9.81 * sub * 1.2)
		b.apply_central_force(-b.linear_velocity * b.mass * 1.4 * sub)
		b.angular_velocity *= 1.0 - minf(1.0, 2.0 * dt * sub)
	var pf := player.global_position
	var deep := wy - world.H(pf.x, pf.z)
	player.wade = 1.0 if world.lake_d(pf.x, pf.z) > 0.0 or deep < 0.25 else clampf(1.0 - deep * 0.5, 0.45, 1.0)

## the rounds in the trailer right now
func trailer_cargo() -> Array:
	if trailer == null: return []
	return pieces().filter(func(b): return (b.mode == "dyn") and trailer.in_bed(b.center_world()))

func hitch_action() -> void:
	if chipper.mode == "truck":
		chipper.unhitch(); Sfx.play("clank"); hud.toast("Unhitched.", 1.5)
	elif chipper.mode == "free":
		if haul.carrying(): haul.drop_all()
		chipper.grab_tongue(_hand_point()); Sfx.play("pick"); player.speed_mult = 0.55
		chipper_holder = player

func _hand_point(p = null) -> Vector3:
	if p == null or not is_instance_valid(p): p = player
	var h: Vector3 = p.global_position + p.fwd() * 0.9
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
	if Net.is_guest():
		Net.ask("seat"); return               # the host hands over the wheel (or says who has it)
	if truck.remote_driver != 0:
		hud.toast("%s's got the wheel." % Net.name_of(truck.remote_driver), 2.5); return
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

## a crew member gets the seat: the host's game drives the truck from their keys
func enter_truck_mirror() -> void:
	if haul.carrying(): haul.drop_all()
	if haul.drag != null: haul.stop_drag()
	if saw.on: saw.stop()
	player.in_truck = true
	player.visible = false
	player.col_shape.disabled = true
	truck.driving = true; truck.look_yaw = 0; truck.look_pitch = 0
	truck._set_cam(); truck.mirror_live = true; truck.mirror_div = 3
	_seat_t = clock
	Sfx.play("door")
	truck.engine_snd = Sfx.engine("truck")
	hud.set_play_visible(false); hud.crosshair.visible = false
	hud.drive.visible = true

func exit_truck_mirror() -> void:
	exit_truck(false)

func exit_truck(ask := true) -> void:
	if Net.is_guest():
		if ask: Net.ask("unseat")
		truck.driving = false; truck.mirror_live = false
	else:
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
	if phase == "play": _capture()
	if cb.is_valid(): cb.call()

func _step_dialog(dt: float) -> void:
	if dlg == null: return
	var L: Dictionary = dlg.lines[dlg.i]
	if dlg.shown < L.text.length():
		var before := int(dlg.shown)
		dlg.shown = minf(L.text.length(), dlg.shown + dt * 48)
		if L.who == job.who and int(dlg.shown) != before and clock - dlg.last_blip > 0.07:
			var ch: String = L.text[mini(int(dlg.shown), L.text.length() - 1)]
			if ch.to_lower() != ch.to_upper():
				dlg.last_blip = clock; Sfx.play("blip", 1.0, randf_range(0.85, 1.25))
		_render_dialog()

func talk_to_earl() -> void:
	var E: String = job.who
	if job.id == "earl": Ach.add("earl_talks")
	if not objs.talk:
		var lines := []
		for l in job.talk: lines.append({who = E, text = l})
		if job.id == "hale" and not (Rigging.owned("wedges") or Rigging.owned("rope")):
			lines.append({who = E, text = "You didn't bring wedges? Or a rope? Oh dear. Well, you know your business. I hope."})
		start_dialog(lines, func():
			objs.talk = true; earl.state = "idle"; update_objectives()
			if Net.is_guest(): Net.ask("talked"))
		return
	if objs.felled and objs.limbed and objs.stacked and not objs.tarped:
		start_dialog([{who = job.who, text = "Tarp it first, dear. Walter lost a whole load of firewood on the Route 9 hill in 1983. I still hear about it. From myself."}]); return
	if objs.felled and objs.limbed and objs.stacked and objs.tarped and not objs.paid:
		if Net.is_guest(): Net.ask("pay")
		else: payday()
		return
	start_dialog([{who = E, text = earl.idle_lines[randi() % earl.idle_lines.size()]}])

## pull the tarp over the load and bungee it down; the rounds under it stay put from then on
func tarp_trailer() -> void:
	if trailer == null or trailer.tarped: return
	Sfx.play("pick"); Sfx.play("crunch", 0.4, 1.6)
	var cargo := []
	for b in pieces():
		if b.mode == "dyn" and trailer.in_bed(b.center_world()):
			b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC; b.freeze = true
			cargo.append(b)
	if cargo.size() >= 12: get_tree().create_timer(2.0).timeout.connect(func(): Ach.unlock("tarp_life"))
	trailer.tarp_it(func():
		for k in range(4): get_tree().create_timer(0.15 * k).timeout.connect(func(): Sfx.play("clank", 0.35, 1.5 + randf() * 0.4))
		objs.tarped = true
		hud.toast("Tarped and strapped down.", 2.0)
		update_objectives(), cargo)

## the heavy leaner sat back on its hinge: the client has an opinion
func customer_sits_back() -> void:
	if job.id == "hale": earl.bark("Is it... stuck? Walter always said it'd be stubborn.", 4.0)

func payday() -> void:
	if objs.paid: return
	var g := tree.grade
	var total: int = job.pay
	var kind_txt: String = {"logs": "Job: haul, buck and load", "storm": "Job: clear the road (limb, chip, buck, move)"}.get(job.get("kind", ""), "Job: drop, limb, chip and %s" % ("load" if trailer else "pile"))
	var rows := [[kind_txt, job.pay]]
	var clean: bool = g.get("open", false) and not g.get("barber", false) and g.notch_pct >= 0.18 and g.notch_pct <= 0.45 and g.notch_angle >= 40 and g.hinge_pct >= 0.05 and g.hinge_pct <= 0.18 and g.dir_err < 15
	if clean: rows.append(["Textbook felling (notch, hinge, aim)", 50]); total += 50
	if g.get("barber", false): rows.append(["Barber chair (%s is shaken)" % job.who, -100]); total -= 100
	if damage.get("garage", false): rows.append(["Dropped it on the garage", -500]); total -= 500
	if damage.get("house", false): rows.append(["Dropped it on the house", -500]); total -= 500
	if job.id == "hale" and not damage.get("garage", false) and not damage.get("house", false): rows.append(["Garage untouched (and polite)", 20]); total += 20
	total = maxi(total, 0)
	var mins := (clock - start_time) / 60.0
	if mins < 15: rows.append(["Quick work (under 15 min)", 25]); total += 25
	var E: String = job.who
	var plines := []
	if damage.get("garage", false) or damage.get("house", false):
		plines.append({who = E, text = "Well. It's down. Most of it's down where it should be. Most of it."})
		plines.append({who = E, text = "I'm taking the damage out of what I owe you. That's only fair."})
	else:
		for l in job.paid: plines.append({who = E, text = l})
	var notes := []
	if job.id == "dock": notes.append("Gus gave you his old spinning rod. Press 6 near water to fish.")
	if g.has("notch_pct") and job.get("kind", "") != "logs":
		if g.open:
			notes.append("Notch: %d%% of the diameter deep, %d° open." % [roundi(g.notch_pct * 100), roundi(g.notch_angle)])
			notes.append("Hinge: %.1f in, %d%% of the diameter." % [g.hinge_in, roundi(g.hinge_pct * 100)])
			notes.append("Fell direction: %d° off the notch." % roundi(g.dir_err))
		else: notes.append("The stem split up the back (barber chair)." if g.barber else "No notch was cut.")
	notes.append("Time: %d min." % roundi(mins))
	objs.paid = true                     # (once: two of the crew asking at the same moment get paid once)
	var data := {rows = rows, total = total, notes = notes, lines = plines, mins = mins, crew = Net.crew_size()}
	if Net.is_host() and net_job: net_job.event_all("payday", [data])
	_payday_show(data)

## everybody on the crew hears the customer out, then banks their share
func _payday_show(d: Dictionary) -> void:
	var total: int = int(d.total)
	var crew: int = maxi(1, int(d.crew))
	var share: int = total if crew == 1 else roundi(float(total) / crew)
	var mins: float = float(d.mins)
	start_dialog(d.lines,
		func():
			objs.paid = true; update_objectives(); Sfx.play("cash")
			var c := Career.load(); c.money += share; c.jobs += 1
			if job.id == "dock": c.rod = true
			if trailer:
				c.trailer = true; c.firewood = true
				var loaded := pieces().filter(func(b): return b.kind == "trunk" and trailer.in_bed(b.center_world())).size()
				c.rounds = int(c.get("rounds", 0)) + maxi(12, loaded)
			Career.save(c); money = c.money
			_payday_achievements(share, mins)
			var rows: Array = (d.rows as Array).duplicate()
			if crew > 1: rows.append(["Split %d ways: the rest goes to the crew" % crew, share - total])
			phase = "done"
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			hud.show_summary(rows, share, d.notes, money, "Job done · %s" % job.title)
			hud.play_timelapse(timelapse.frames, timelapse.stamps))

## after the money's in the bank (so the career file already has it)
func _payday_achievements(total: int, mins: float) -> void:
	var g := tree.grade
	Ach.earn(total)
	Ach.unlock({"earl": "first_day", "hale": "widows_peace", "dock": "clear_water"}.get(job.id, "first_day"))
	if mins < {"earl": 10.0, "hale": 15.0, "dock": 12.0}.get(job.id, 10.0): Ach.unlock({"earl": "speed_earl", "hale": "speed_hale", "dock": "speed_dock"}.get(job.id, "speed_earl"))
	if job.id == "hale" and not damage.get("garage", false) and not damage.get("house", false): Ach.unlock("not_on_my_watch")
	if g.has("notch_pct") and job.get("kind", "") != "logs" and g.get("open", false) and not g.get("barber", false):
		var notch_ok: bool = g.notch_pct >= 0.18 and g.notch_pct <= 0.45 and g.notch_angle >= 40
		var hinge_ok: bool = g.hinge_pct >= 0.05 and g.hinge_pct <= 0.18
		if notch_ok: Ach.unlock("textbook_notch")
		if hinge_ok: Ach.unlock("hinge_master")
		if g.dir_err < 5: Ach.unlock("on_the_line")
		if job.id == "hale" and notch_ok and hinge_ok and g.dir_err < 15: Ach.unlock("gentle_giant")
	if weather and (weather.kind == "rain" or weather.kind == "storm"): Ach.unlock("rain_or_shine")
	if trailer:
		var loaded := pieces().filter(func(b): return b.kind == "trunk" and trailer.in_bed(b.center_world())).size()
		if loaded >= 16: Ach.unlock("full_load")
	Ach.check_gear()

func _on_fell(kind: String) -> void:
	if weather and weather.kind == "fog": Ach.unlock("lost_in_fog")
	if job.id == "hale" and kind != "barber" and rig.wedges.size() > 0 and not rig.rope_used: Ach.unlock("wedge_whisperer")
	hud.shout("BARBER CHAIR!" if kind == "barber" else "TIMBER!")
	saw.cut = null
	rig.on_fell()
	if Net.is_guest(): return
	if kind == "barber":
		earl.bark(job.barber, 3.5)
	else:
		get_tree().create_timer(2.6).timeout.connect(func(): if damage.is_empty(): earl.bark(job.fell[randi() % job.fell.size()], 3.5))

## while it's coming down: did it land on the garage or the house?
func _check_damage() -> void:
	if tree.state != "hinge" and tree.state != "down": return
	if tree.t - tree.down_t > 6.0 and tree.state == "down": return
	if not is_instance_valid(tree.stem): return
	var T: Dictionary = tree.T
	var pts := []
	var y := tree.stump_top + 1.2
	while y < T.H: pts.append(Vector3(0, y, 0)); y += 0.6
	for L in T.limbs:
		if tree.stem.limbs.has(L.id):
			for k: float in [0.35, 0.65, 0.95]: pts.append(Wood.limb_pt(L, k))
	# how high each building reaches: walls plus roof, and a little for the trunk's own thickness
	var gar_top: float = 0.15 + float(world.garage.get("wall", 2.6)) + 1.5 + 0.9
	var house_top: float = float(world.house.get("wall", 2.7)) + 3.6
	# your own truck
	if truck and not Ach.has("ow"):
		for p in pts:
			var lt: Vector3 = truck.to_local(tree.stem.to_world(p))
			if absf(lt.x) < 1.1 and lt.z > -3.2 and lt.z < 2.6 and lt.y < 2.2 and lt.y > -0.2:
				Ach.unlock("ow"); break
	for b in [["garage", world.garage, gar_top], ["house", world.house, house_top]]:
		var box: Dictionary = b[1]
		if box.is_empty() or damage.get(b[0], false): continue
		var gy := world.H(box.x, box.z)
		for p in pts:
			var w := tree.stem.to_world(p)
			if absf(w.x - box.x) < box.w / 2 + 0.45 and absf(w.z - box.z) < box.d / 2 + 0.45 and w.y < gy + b[2]:
				damage[b[0]] = true
				if Net.is_host() and net_job: net_job.event_all("crunch", [b[0]])
				Sfx.play("crunch", 1.0, 0.6); Sfx.play("crack", 0.9, 0.7); Sfx.play("thud", 1.0, 0.8)
				hud.shout("CRUNCH!")
				if b[0] == "garage": world.crush_garage()
				var line: String = job.hit_garage if b[0] == "garage" else job.hit_house
				if line != "": earl.bark(line, 5.0)
				break

# ================================================================ objectives
func pieces() -> Array:
	return level_root.get_children().filter(func(c): return c is WoodPiece and is_instance_valid(c) and c.mode != "gone" and not c.is_queued_for_deletion())

func in_pile(b: WoodPiece) -> bool:
	if world.job == "storm":
		# off the road: in the ditch or the trees either side (not over the bridge, not dumped in the creek)
		var c := b.center_world()
		return absf(c.z - world.road_z) > 3.9 and world.creek_d(c.x, c.z) > 3.2      # (the asphalt is 7 m wide)
	if trailer: return trailer.in_bed(b.center_world())
	var p := world.pile
	var c := b.center_world()
	return absf(c.x - p.x) < p.w / 2 + 0.6 and absf(c.z - p.z) < p.d / 2 + 0.6

func update_objectives() -> void:
	if Net.is_guest(): return               # the host keeps the job list; ours arrives from there
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
	var buck_txt := "Buck the stem into liftable rounds and load them in %s's trailer" % job.who if trailer else "Buck the stem into liftable rounds and pile them behind the shed"
	if objs.felled and rounds > 0:
		buck_txt += " · %d/%d · %d%%" % [piled, rounds, int(floor(done_frac * 100.0))]
		if heavy > 0: buck_txt += " · %d too heavy" % heavy
	if job.get("kind", "") == "storm":
		var off_txt := "Buck the trunks into rounds and get them all off the road"
		if rounds > 0: off_txt += " · %d/%d · %d%%" % [piled, rounds, int(floor(done_frac * 100.0))]
		if heavy > 0: off_txt += " · %d too heavy" % heavy
		hud.set_objectives([
			[objs.talk, "Talk to %s" % job.who],
			[objs.limbed, "Limb the downed trees and chip the brush" + (" · %d left" % brush if not objs.limbed else "")],
			[objs.stacked, off_txt],
			[objs.paid, "Get paid"]])
	elif job.get("kind", "") == "logs":
		var wet := logs_in_water()
		if not objs.hauled and wet == 0 and lake_logs.size() > 0:
			objs.hauled = true
			Sfx.play("ding"); hud.toast("That's the last of them out of the water. Buck 'em and load the trailer.", 4.0)
		var lb_txt := "Buck them into liftable rounds and load them in your trailer"
		if objs.hauled and rounds > 0: lb_txt += " · %d/%d · %d%%" % [piled, rounds, int(floor(done_frac * 100.0))]
		objs.stacked = objs.stacked and objs.hauled
		hud.set_objectives([
			[objs.talk, "Talk to %s" % job.who],
			[objs.hauled, "Rope the logs and drag them out of the water with the truck" + (" · %d left" % wet if not objs.hauled else "")],
			[objs.stacked, lb_txt],
			[objs.paid, "Get paid"]])
	else:
		hud.set_objectives([
			[objs.talk, "Talk to %s" % job.who],
			[objs.felled, ("Drop the %s, away from the garage" % job.tree_word) if job.id == "hale" else ("Drop the %s" % job.tree_word)],
			[objs.limbed, "Limb it and chip the brush" + (" · %d left" % brush if objs.felled and not objs.limbed else "")],
			[objs.stacked, buck_txt]]
			+ ([[objs.tarped, "Tarp the trailer so nothing falls out"]] if trailer else [])
			+ [[objs.paid, "Get paid"]])
	if test_job_done:
		objs.felled = true; objs.limbed = true; objs.stacked = true; objs.tarped = true; objs.hauled = true
	if trailer and objs.stacked and not objs.tarped and not called_tarp:
		called_tarp = true
		Sfx.play("ding")
		earl.bark("That's a full load, dear. Throw the tarp over it before something rolls out on the road.", 5.0)
		hud.toast("Loaded. Walk up to the trailer and press E to tarp it.", 4.0)
	if objs.limbed and objs.stacked and objs.tarped and not objs.paid and not called_pay:
		called_pay = true
		Sfx.play("ding")
		earl.bark(job.done, 6.0)
		hud.toast("Job done. Talk to %s to get paid." % job.who)
		if net_job: net_job.event_all("toast", ["Job done. Talk to %s to get paid." % job.who, 3.2])
	if Net.is_host() and net_job: net_job.objectives_changed()

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
	if player.tool == "wedge": hud.tool_state.text = "Wedges: %d in the tree" % rig.wedges.size()
	elif player.tool == "rope": hud.tool_state.text = "Pull rope" + ("" if rig.rope == "" else (" · on the tree" if rig.rope == "tree" else " · rigged to the truck"))
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
		hud.drive_lbl.text = "[b]W/S[/b] drive · [b]A/D[/b] steer · [b]Space[/b] brake · [b]V[/b] camera · [b]U[/b] unstick · [b]E[/b] get out    [b]%d mph[/b]" % int(truck.speed_mph())
		if rig.rope == "rigged":
			var tx := rig._tension_txt().substr(3)
			var col := "#ff6a4a" if rig.rope_stretch > Rigging.ROPE_SNAP * 0.7 else ("#9be36b" if rig.rope_stretch >= Rigging.ROPE_TIGHT else "#ffd27a")
			hud.drive_lbl.text = "[b]W/S[/b] drive · [b]Space[/b] brake · [b]E[/b] get out    [b]%d mph[/b]    Rope: [color=%s][b]%s[/b][/color]" % [int(truck.speed_mph()), col, tx]
		hud.obj_panel.visible = truck.chase     # out of the way of the rear-view mirror
		hud.set_prompt("")
		return
	hud.obj_panel.visible = true
	var t := ""
	var a := aim
	var tipped := _tipped_near()
	if dlg != null: t = ""
	elif tipped != "": t = "[b]E[/b] Flip the %s back over" % tipped
	elif chipper.mode == "hand" and holding_chipper():
		var nh := chipper.nearest_hitch()
		t = ("[b]E[/b] Hitch it to the trailer" if nh == trailer else "[b]E[/b] Hitch it to the truck") if nh != null else "[b]E[/b] Set the tongue down"
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
			var tt = haul.throw_target()
			var where: String = haul.lands_in_bed(tt) if tt != null else ""
			t = "[b]Right click[/b] %s · [b]E[/b] drop all" % ({"trailer": "Throw one in the trailer", "truck": "Throw one in the truck"}.get(where, "Throw one there") if tt != null else "Set one down")
	elif (player.tool == "wedge" or player.tool == "rope") and rig.prompt() != "":
		t = rig.prompt()
	elif not a.is_empty():
		match a.kind:
			"earl": t = "[b]E[/b] Talk to %s" % job.who + (" · get paid" if objs.limbed and objs.stacked and not objs.paid else "")
			"truck": t = "[b]E[/b] Get in the truck"
			"tailgate": t = "[b]E[/b] Hop down" if on_bed else "[b]E[/b] Hop in the back"
			"hitch": t = "[b]E[/b] Unhitch the chipper" if chipper.mode == "truck" else "[b]E[/b] Grab the tongue"
			"coupler":
				if trailer.mode == "truck": t = "[b]E[/b] Unhitch the trailer"
				elif truck.hitch_world().distance_to(trailer.coupler_world()) <= 3.5: t = "[b]E[/b] Hitch the trailer to the truck"
				else: t = "Trailer tongue · back the truck up to it to hitch"
			"chipper": t = "[b]E[/b] %s the chipper" % ("Stop" if chipper.running else "Start")
			"trailer": t = "[b]E[/b] Tarp the trailer"
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
	if chipper and chipper.mode == "hand" and not Net.is_guest():
		chipper.move_hand(_hand_point(chipper_holder), dt)
	if rig and phase == "play": rig.physics_step(dt)
	if phase == "play": _water_step(dt)
	if haul: haul.step_drag(dt)

var _was_captured := false
func _process(dt: float) -> void:
	clock += dt
	# a browser swallows Esc and drops the pointer lock on its own: if the mouse got loose mid-game, pause
	var capd := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _was_captured and not capd and touch == null and tests == null and not pause.is_open() and can_pause() and dlg == null:
		pause.open()
	_was_captured = capd
	_watch_fps(dt)
	var cam := get_viewport().get_camera_3d()
	if ambient and cam: ambient.step(dt, cam.global_position)
	if weather and cam: weather.step(dt, cam.global_position)
	if in_hub:
		hub.step(dt)
		hud.money.text = "$%d" % money
		return
	if timelapse: timelapse.step(dt)
	if fishing: fishing.step(dt)
	# truck, trailer and chipper all strung together and moving
	if trailer and chipper and truck and player.in_truck and trailer.mode == "truck" and chipper.tow == trailer and truck.speed_mph() >= 12.0:
		Ach.unlock("road_train")
	_step_kick(dt)
	if phase == "title":
		# a slow orbit over the yard, between the house and the dead ash
		var a := clock * 0.04
		var c := Vector3(world.s * 28.0, 0, world.road_z) if world.house.is_empty() else Vector3((world.tree.x + world.house.x) * 0.5, 0, (world.tree.z + world.house.z) * 0.5)
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
		on_bed = absf(l.x) < 1.0 and l.z > -2.7 and l.z < -0.7 and l.y > Truck.BED_FLOOR_Y - 0.15
	else:
		aim = {}
	_step_dialog(dt)
	# speed: slowed by what you carry or drag
	player.speed_mult = (0.55 if chipper.mode == "hand" and holding_chipper() else 1.0) * (1.0 - haul.carry_mass() / Wood.LIFT_MAX * 0.45) * (0.5 if haul.drag != null else 1.0)
	haul.step_carry(dt)
	# the saw (or bare hands)
	var rev := (Input.is_action_pressed("rev") and cap() and dlg == null) or force_rev
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
	rig.step(dt)
	if tree.state == "down" and not Net.is_guest():
		_break_under_limbs()
		if not objs.felled and (tree.t - tree.down_t > 5.0 or (is_instance_valid(tree.stem) and tree.stem.sleeping)):
			objs.felled = true; update_objectives(); Sfx.play("ding")
	# Earl heads for the porch once the saw's running near the tree
	if not Net.is_guest() and objs.talk and not world.house.is_empty() and not earl.get_meta("to_porch", false) and _anyone_sawing_near(tree.global_position, tree.T.H):
		earl.set_meta("to_porch", true)
		var h: Dictionary = world.house
		earl.go_to(Vector2(h.x + h.w * 0.18, h.z - h.d / 2 - 1.4))
		earl.bark(job.porch, 4.0)
	if not Net.is_guest() and objs.felled and not objs.paid and dlg == null and clock - earl.last_bark > 38.0:
		earl.last_bark = clock
		earl.bark(earl.idle_lines[randi() % earl.idle_lines.size()], 5.0)
	if not Net.is_guest(): _check_damage()
	# engines
	var eng = chipper.engine_snd
	if eng:
		chipper.load = maxf(0, chipper.load - dt * 1.5)
		var d := player.global_position.distance_to(chipper.global_position)
		eng.setv(0.5 + chipper.load * 0.4, chipper.load, clampf(1 - d / 60, 0.05, 1) * 0.55)
	if truck.engine_snd:
		var sp := truck.linear_velocity.length() if not (Net.is_guest() and net_job) else absf(net_job.truck_speed)
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

# ================================================================ the crew (see net.gd, net_job.gd)
## is the chipper's tongue in my hands (rather than a crew member's)?
func holding_chipper() -> bool:
	if Net.is_guest(): return net_job != null and net_job.chipper_holder == Net.me()
	return chipper_holder == null or not is_instance_valid(chipper_holder) or chipper_holder == player

## walking the chipper: drop the tongue on a hitch ball if it's over one, otherwise on its jack
func chipper_hand_action() -> void:
	var to := chipper.nearest_hitch()
	if to != null:
		chipper.hitch_now(to); Sfx.play("clank"); hud.toast("Hitched to the back of the trailer." if to == trailer else "Hitched.", 1.8)
	else:
		chipper.set_down(); Sfx.play("drop")
	player.speed_mult = 1.0
	chipper_holder = null

## a crew member pressed E on something of the host's (done "as" them: see NetJob.as_peer)
func net_use(kind: String) -> void:
	match kind:
		"flip_truck":
			truck.right_up(world); Sfx.play("thud"); hud.toast("Back on its wheels.", 1.6)
		"flip_chipper":
			chipper.right_up(); Sfx.play("thud"); hud.toast("Back on its wheels.", 1.6)
		"hand":
			if chipper.mode == "hand" and chipper_holder == player: chipper_hand_action()
		"hitch":
			if chipper.mode == "hand": return
			hitch_action()
		"chipper": toggle_chipper()
		"trailer":
			if trailer and objs.stacked and not objs.tarped: tarp_trailer()
		"coupler": trailer_hitch_action()
		"unstick": unstick_truck()

## is anyone on the crew running a saw near here?
func _anyone_sawing_near(p: Vector3, r: float) -> bool:
	if saw.on and player.global_position.distance_to(p) < r: return true
	for id in Net.avatars:
		var av = Net.avatars[id]
		if is_instance_valid(av) and av.visible and (av._flags & Avatar.F_SAW_ON) and av.global_position.distance_to(p) < r: return true
	return false

## where I am and what I'm doing, for the rest of the crew's screens
func net_pose():
	if player == null or not is_instance_valid(player): return null
	var fl := 0
	if saw and is_instance_valid(saw) and saw.on:
		fl |= Avatar.F_SAW_ON
		if (Input.is_action_pressed("rev") and cap()) or force_rev: fl |= Avatar.F_REV
		if saw.cutting: fl |= Avatar.F_CUTTING
	if player.in_truck: fl |= Avatar.F_TRUCK
	if player.crouch: fl |= Avatar.F_CROUCH
	if haul != null and is_instance_valid(haul) and haul.carrying(): fl |= Avatar.F_CARRY
	var tool: String = player.tool if not in_hub else "hands"
	return [player.global_position, player.yaw, player.pitch, tool, fl]

## a message from the host
func net_event(name: String, a: Array) -> void:
	match name:
		"begin":
			if in_hub: begin_job(int(a[0]), int(a[1]))
		"home": go_home_now()
		"payday":
			if not in_hub: _payday_show(a[0])
		"toast": hud.toast(str(a[0]), float(a[1]) if a.size() > 1 else 3.0)
		_:
			if net_job and is_instance_valid(net_job): net_job.on_event(name, a)

## a crew member asks the host's game for something
func net_ask(id: int, name: String, a: Array) -> void:
	match name:
		"home":
			if phase == "done": next_job()
		_:
			if net_job and is_instance_valid(net_job): net_job.on_ask(id, name, a)
			elif name == "ready":
				# their copy's built before ours: tell them to try again in a moment
				get_tree().create_timer(0.5).timeout.connect(func(): if net_job: net_job.on_ask(id, name, a))

## the crew hears it come down on a building
func net_crunch(kind: String) -> void:
	damage[kind] = true
	Sfx.play("crunch", 1.0, 0.6); Sfx.play("crack", 0.9, 0.7); Sfx.play("thud", 1.0, 0.8)
	hud.shout("CRUNCH!")
	if kind == "garage": world.crush_garage()

## the payday card's button: home to the cabin (the whole crew goes when the host does)
func next_job() -> void:
	if Net.is_guest():
		Net.ask("home")
		hud.toast("Waiting on %s to head home..." % Net.boss_name(), 3.0)
		return
	if Net.is_host(): Net.tell("home")
	go_home_now()

func go_home_now() -> void:
	Player.input_off = false
	get_tree().paused = false
	Hub.come_home = true
	get_tree().reload_current_scene()

## stand the crew side by side rather than all in one spot
func _crew_spot(p: Player) -> void:
	if not Net.active() or not Net.roster.has(Net.me()): return
	var slot := int(Net.roster[Net.me()].hat)
	if slot == 0: return
	var side := Vector3(cos(p.yaw), 0, -sin(p.yaw))
	var q := p.global_position + side * (0.9 * slot)
	p.teleport(Vector3(q.x, world.H(q.x, q.z) + 0.05 if world else q.y, q.z))

func _crew_changed() -> void:
	if hud == null: return
	if not Net.active(): hud.set_crew(""); return
	var names := []
	for id in Net.roster:
		names.append(Net.name_of(id) + (" (boss)" if id == 1 else ""))
	hud.set_crew("Crew: " + ", ".join(names))

## the phone on the cabin wall: the crew lobby
func open_phone() -> void:
	if phone == null:
		phone = PhoneUI.new(); phone.name = "Phone"
		hud.add_child(phone)
		phone.setup(self)
	if hub: hub.busy = true
	hud.set_prompt("")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	phone.open()

func phone_closed() -> void:
	if hub: hub.busy = false
	_capture()
