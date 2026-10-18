## Weather: mostly fair, but now and then an overcast day, a foggy morning, rain, or a thunderstorm.
## Each job rolls its own weather, and every few minutes it may change, easing over in about half a minute.
## Drives the sun, sky, fog, ambient light, wet ground, rain around the camera, rain sound and lightning.
class_name Weather
extends Node

const PRESETS := {
	"clear":    {sun = 1.3,  amb = 0.95, fog = 0.0022, fog_col = Color("#dcd6c0"), sky_fog = 0.15, cover = 0.0,  grey = 0.0,  rain = 0.0, wet = 0.0, sat = 1.0},
	"overcast": {sun = 0.5,  amb = 0.82, fog = 0.0055, fog_col = Color("#b9bdbb"), sky_fog = 0.3,  cover = 0.78, grey = 0.18, rain = 0.0, wet = 0.0, sat = 0.88},
	"fog":      {sun = 0.42, amb = 0.85, fog = 0.032,  fog_col = Color("#c9cdcb"), sky_fog = 0.85, cover = 0.65, grey = 0.75, rain = 0.0, wet = 0.25, sat = 0.82},
	"rain":     {sun = 0.32, amb = 0.72, fog = 0.012,  fog_col = Color("#9ea6aa"), sky_fog = 0.5,  cover = 0.92, grey = 0.45, rain = 0.55, wet = 1.0, sat = 0.8},
	"storm":    {sun = 0.2,  amb = 0.58, fog = 0.017,  fog_col = Color("#7f888e"), sky_fog = 0.6,  cover = 1.0,  grey = 0.55, rain = 1.0, wet = 1.0, sat = 0.75},
}
const NAMES := {"clear": "Clear skies", "overcast": "Grey and overcast", "fog": "Fog's in this morning", "rain": "Rain today", "storm": "Storm's rolling in"}

var game
var kind := "clear"
var cur := {}                  # current blended values
var target := {}
var rng := RandomNumberGenerator.new()
var rain_fx: CPUParticles3D
var rain_snd: AudioStreamPlayer
var _change_t := 0.0
var _flash_t := 12.0
var _flash := 0.0
var _thunder_at := -1.0
var _t := 0.0

## pick today's weather: mostly clear; overcast, fog and rain now and then; a storm rarely
static func roll(r: RandomNumberGenerator) -> String:
	var x := r.randf()
	if x < 0.66: return "clear"
	if x < 0.78: return "overcast"
	if x < 0.88: return "fog"
	if x < 0.96: return "rain"
	return "storm"

var _base_rough := 1.0

func setup(g, sd: int) -> void:
	game = g
	if not Mats.terrain.has_meta("base_rough"): Mats.terrain.set_meta("base_rough", Mats.terrain.roughness)
	_base_rough = Mats.terrain.get_meta("base_rough")
	rng.seed = sd * 7 + 3
	kind = roll(rng)
	var forced := OS.get_environment("ARBOR_WEATHER")
	if PRESETS.has(forced): kind = forced
	target = PRESETS[kind].duplicate()
	cur = target.duplicate()
	_change_t = rng.randf_range(150.0, 260.0)
	_build_rain()
	_apply()

## jump straight to a weather (tests, debugging)
func force(k: String) -> void:
	kind = k
	target = PRESETS[k].duplicate()
	cur = target.duplicate()
	_applied = {}
	_apply()

func announce() -> void:
	if kind != "clear": game.hud.toast(NAMES[kind] + ".", 3.0)

func set_kind(k: String) -> void:
	if not PRESETS.has(k) or k == kind: return
	kind = k
	target = PRESETS[k].duplicate()
	if game.phase == "play": game.hud.toast({"clear": "The weather's clearing up.", "overcast": "Clouding over.", "fog": "Fog's rolling in.", "rain": "Here comes the rain.", "storm": "Thunder. Here comes a storm."}[k], 3.0)

func _build_rain() -> void:
	rain_fx = CPUParticles3D.new()
	var mb := MeshBuilder.new()
	var c := Color(1, 1, 1)
	for k in range(2):
		var ax := Vector3(0.006, 0, 0) if k == 0 else Vector3(0, 0, 0.006)
		var a := mb.v(-ax + Vector3(0, -0.22, 0), Vector3.UP, c); var b := mb.v(ax + Vector3(0, -0.22, 0), Vector3.UP, c)
		var d := mb.v(ax + Vector3(0, 0.22, 0), Vector3.UP, c); var e := mb.v(-ax + Vector3(0, 0.22, 0), Vector3.UP, c)
		mb.quad(a, b, d, e)
	rain_fx.mesh = mb.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.8, 0.84, 0.9, 0.42)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	rain_fx.material_override = m
	rain_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain_fx.amount = 1600
	rain_fx.lifetime = 0.85
	rain_fx.local_coords = false
	rain_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain_fx.emission_box_extents = Vector3(13, 0.5, 13)
	rain_fx.direction = Vector3(0.1, -1, 0.05)
	rain_fx.spread = 3.0
	rain_fx.initial_velocity_min = 12.0; rain_fx.initial_velocity_max = 15.0
	rain_fx.gravity = Vector3(1.2, -9.8, 0.6)
	rain_fx.particle_flag_align_y = true
	rain_fx.emitting = false
	rain_fx.top_level = true
	add_child(rain_fx)
	rain_snd = AudioStreamPlayer.new()
	rain_snd.stream = Sfx.sounds.get("rain")
	rain_snd.volume_db = -60
	rain_snd.bus = "Ambient"
	add_child(rain_snd)

func step(dt: float, eye: Vector3) -> void:
	_t += dt
	# ease toward the target weather (about half a minute for a full change)
	var k := minf(1.0, dt * 0.09)
	for key in target:
		var a = cur[key]; var b = target[key]
		cur[key] = a.lerp(b, k) if a is Color else lerpf(a, b, k)
	# every few minutes the weather may turn
	_change_t -= dt
	if _change_t <= 0 and game.phase == "play" and OS.get_environment("ARBOR_WEATHER") == "":
		_change_t = rng.randf_range(150.0, 260.0)
		if rng.randf() < 0.18:
			if kind == "clear": set_kind(["overcast", "overcast", "rain", "fog"][rng.randi() % 4])
			elif kind == "overcast": set_kind("rain" if rng.randf() < 0.5 else "clear")
			elif kind == "storm": set_kind("rain")
			else: set_kind("clear" if rng.randf() < 0.7 else "overcast")
	# rain follows the camera, a little ahead of it; none inside the cab
	var r: float = cur.rain
	var in_cab: bool = game.player.in_truck and not game.truck.chase
	rain_fx.emitting = r > 0.03 and not in_cab
	# changing the count restarts the particles, so only step it in coarse notches
	var want := maxi(200, int(round(r * 8.0)) * 200)
	if rain_fx.amount != want: rain_fx.amount = want
	var cam: Camera3D = game.get_viewport().get_camera_3d()
	var ahead := Vector3.ZERO
	if cam: ahead = -cam.global_transform.basis.z * 4.0; ahead.y = 0
	rain_fx.global_position = eye + ahead + Vector3(0, 7.5, 0)
	if rain_snd.stream:
		if r > 0.03 and not rain_snd.playing: rain_snd.play()
		elif r <= 0.03 and rain_snd.playing: rain_snd.stop()
		rain_snd.volume_db = linear_to_db(maxf(r * (0.55 if in_cab else 0.4) * Sfx.amb_level, 0.0005))
	# lightning in a storm: a double flash, then thunder a moment later
	if kind == "storm" and cur.rain > 0.7:
		_flash_t -= dt
		if _flash_t <= 0:
			_flash_t = rng.randf_range(9.0, 26.0)
			_flash = 1.0
			_thunder_at = _t + rng.randf_range(0.4, 2.8)
	if _thunder_at > 0 and _t >= _thunder_at:
		_thunder_at = -1.0
		Sfx.play("thunder", rng.randf_range(0.5, 0.9) * Sfx.amb_level, rng.randf_range(0.85, 1.1), "Ambient")
	_flash = maxf(0.0, _flash - dt * 2.2)
	_apply()

var _applied := {}
func _apply() -> void:
	# only touch the renderer when something actually changed (a sky change re-renders its lighting)
	var changed := _flash > 0.0 or _applied.is_empty()
	if not changed:
		for key in cur:
			var a = cur[key]; var b = _applied.get(key)
			if b == null or (a is Color and not (a as Color).is_equal_approx(b)) or (a is float and absf(a - b) > 0.0005): changed = true; break
	if not changed: return
	_applied = cur.duplicate()
	_apply_now()

func _apply_now() -> void:
	var env: Environment = _find_env()
	var fl := 0.0
	if _flash > 0.0: fl = 3.5 * _flash if fmod(_flash, 0.5) > 0.2 else 0.6 * _flash      # a flicker
	game.sun.light_energy = cur.sun + fl
	if env:
		env.ambient_light_energy = cur.amb + fl * 0.3
		env.fog_density = cur.fog
		env.fog_light_color = cur.fog_col
		env.fog_sky_affect = cur.sky_fog
		env.adjustment_saturation = cur.sat
	if game.sky_mat:
		game.sky_mat.set_shader_parameter("cover", cur.cover)
		game.sky_mat.set_shader_parameter("grey", cur.grey)
	# wet ground: darker, with a sheen
	var w: float = cur.wet
	Mats.terrain.albedo_color = Color(1, 1, 1).lerp(Color(0.74, 0.76, 0.78), w)
	Mats.terrain.roughness = lerpf(_base_rough, 0.5, w)
	# sunbeams only in sunshine; the painted far treeline hides in thick fog
	if _shafts == null and game.level_root:
		_shafts = game.level_root.find_child("LightShafts", true, false)
		_treeline = game.level_root.find_child("Treeline", true, false)
	if is_instance_valid(_shafts): _shafts.visible = cur.sun > 0.9
	if is_instance_valid(_treeline): _treeline.visible = cur.fog < 0.012

var _env: Environment
var _shafts: Node3D
var _treeline: Node3D
func _find_env() -> Environment:
	if _env: return _env
	for c in game.get_children():
		if c is WorldEnvironment: _env = c.environment
	return _env
