## Player settings, kept between sessions in user://settings.cfg (in the browser that's its local
## storage, so they survive updates to the site). Everything is static: read them anywhere as Settings.x,
## change them through the pause menu, which calls save() and apply().
class_name Settings
extends RefCounted

const PATH := "user://settings.cfg"

static var volume := 1.0          # everything
static var ambience := 1.0        # wind, birds, rain, water
static var look_sens := 1.0       # multiplies mouse and swipe look
static var invert_y := false
static var fov := 70.0            # on foot; the cab view is a touch wider
static var detail := -1           # -1 automatic (drops to low if the game runs slow), 0 low, 1 high
static var fps := -1              # -1 automatic (30 on phones, as fast as the screen on a computer), else a cap
static var res := 1.0             # 3D resolution, as a fraction of the usual (1.0, 0.85, 0.7)
static var btn_size := 1.0        # touch buttons, as a fraction of the usual
static var _loaded := false

static func load_all() -> void:
	if _loaded: return
	_loaded = true
	var c := ConfigFile.new()
	if not FileAccess.file_exists(PATH) or c.load(PATH) != OK: return
	volume = clampf(c.get_value("s", "volume", volume), 0.0, 1.0)
	ambience = clampf(c.get_value("s", "ambience", ambience), 0.0, 1.0)
	look_sens = clampf(c.get_value("s", "look_sens", look_sens), 0.2, 3.0)
	invert_y = bool(c.get_value("s", "invert_y", invert_y))
	fov = clampf(c.get_value("s", "fov", fov), 55.0, 100.0)
	detail = int(c.get_value("s", "detail", detail))
	fps = int(c.get_value("s", "fps", fps))
	res = clampf(c.get_value("s", "res", res), 0.5, 1.0)
	btn_size = clampf(c.get_value("s", "btn_size", btn_size), 0.7, 1.5)

static func save() -> void:
	var c := ConfigFile.new()
	for k in ["volume", "ambience", "look_sens", "invert_y", "fov", "detail", "fps", "res", "btn_size"]:
		c.set_value("s", k, _get_static(k))
	c.save(PATH)

static func _get_static(k: String):
	match k:
		"volume": return volume
		"ambience": return ambience
		"look_sens": return look_sens
		"invert_y": return invert_y
		"fov": return fov
		"detail": return detail
		"fps": return fps
		"res": return res
		"btn_size": return btn_size
	return null

## put the current settings into effect
static func apply(g) -> void:
	Sfx.apply_volume()
	if g == null: return
	# frame rate: phones default to 30 (they run hot otherwise), computers to the screen's rate
	if fps == -1: Engine.max_fps = 30 if g.touch != null else 0
	else: Engine.max_fps = fps
	if detail != -1 and g.detail != detail: g.set_detail(detail)
	g.apply_render_scale()
	if g.player and is_instance_valid(g.player) and g.player.cam: g.player.cam.fov = fov
	if g.truck and is_instance_valid(g.truck) and g.truck.cab_cam: g.truck.cab_cam.fov = fov + 2.0
	if g.touch: g.touch._layout()
