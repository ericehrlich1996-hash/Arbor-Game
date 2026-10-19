## The pause menu: stops the world (the tree is paused and the sound muted) and holds the settings.
## Opens with Esc on a computer (or when the browser lets go of the mouse), the MENU button on a phone,
## and by itself when the game loses focus. Every change takes effect straight away and is saved.
class_name PauseMenu
extends CanvasLayer

var game
var dim: ColorRect
var panel: PanelContainer
var scroll: ScrollContainer
var body: VBoxContainer
var help_btn: Button
var showing_help := false
var f := 1.0                      # size factor for the screen
var _vals := {}                   # setting name -> value label

const INK := Color("#f3ead8")
const DIM := Color("#a89f8c")
const ACCENT := Color("#f0a030")

func setup(g) -> void:
	game = g
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	get_viewport().size_changed.connect(func(): if visible: _build())

func is_open() -> bool:
	return visible

func open() -> void:
	if visible: return
	visible = true                        # first: letting go of held buttons can call back in here
	if game.touch: game.touch._release_all()
	get_tree().paused = true
	AudioServer.set_bus_mute(0, true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()

func close() -> void:
	if not visible: return
	visible = false
	showing_help = false
	get_tree().paused = false
	AudioServer.set_bus_mute(0, false)
	Settings.save()
	game._was_captured = false            # the browser may refuse to grab the mouse back until a click
	game._capture()

func _unhandled_input(ev: InputEvent) -> void:
	if not visible: return
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

# ---------------------------------------------------------------- building it
func _build() -> void:
	for c in get_children(): c.queue_free()
	_vals = {}
	var s := get_viewport().get_visible_rect().size
	f = clampf(minf(s.x, s.y) / 560.0, 1.0, 1.7)
	dim = ColorRect.new(); dim.color = Color(0.03, 0.035, 0.03, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT); dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var cc := CenterContainer.new(); cc.set_anchors_preset(Control.PRESET_FULL_RECT); dim.add_child(cc)
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.09, 0.09, 0.08, 0.95); sb.set_corner_radius_all(int(12 * f))
	sb.border_color = Color(1, 1, 1, 0.1); sb.set_border_width_all(1)
	sb.content_margin_left = 22 * f; sb.content_margin_right = 22 * f; sb.content_margin_top = 16 * f; sb.content_margin_bottom = 16 * f
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", int(10 * f)); panel.add_child(v)

	# header: title on the left, resume on the right (always in reach, whatever the scroll)
	var head := HBoxContainer.new(); head.add_theme_constant_override("separation", int(14 * f)); v.add_child(head)
	var t := _lbl("Paused", 30, Color("#ffe1b8")); t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(t)
	help_btn = _btn("Settings" if showing_help else "Controls", false); head.add_child(help_btn)
	help_btn.pressed.connect(func(): showing_help = not showing_help; _build())
	var rb := _btn("Resume", true); head.add_child(rb)
	rb.pressed.connect(close)

	scroll = ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(minf(560.0 * f, s.x - 60.0), minf(s.y * 0.72, 430.0 * f))
	v.add_child(scroll)
	body = VBoxContainer.new(); body.add_theme_constant_override("separation", int(8 * f))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	if showing_help:
		var ht := RichTextLabel.new(); ht.bbcode_enabled = true; ht.fit_content = true; ht.scroll_active = false
		ht.add_theme_font_size_override("normal_font_size", int(16 * f)); ht.add_theme_font_size_override("bold_font_size", int(16 * f))
		ht.add_theme_color_override("default_color", INK)
		ht.text = game.hud.help_lbl.text.replace("\n", "\n\n")
		ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(ht)
		return

	_section("Sound")
	_slider("volume", "Volume", 0.0, 1.0, 0.05, func(x): return "%d%%" % roundi(x * 100))
	_slider("ambience", "Nature sounds", 0.0, 1.0, 0.05, func(x): return "%d%%" % roundi(x * 100))
	_section("Looking around")
	_slider("look_sens", "Look speed", 0.3, 2.5, 0.05, func(x): return "%.2fx" % x)
	_choice("invert_y", "Invert up/down", [["Off", false], ["On", true]])
	_slider("fov", "Field of view", 60.0, 95.0, 1.0, func(x): return "%d°" % roundi(x))
	if game.touch: _slider("btn_size", "Button size", 0.75, 1.4, 0.05, func(x): return "%d%%" % roundi(x * 100))
	_section("Graphics")
	_choice("detail", "Detail", [["Auto", -1], ["Low", 0], ["High", 1]])
	_choice("fps", "Frame rate", [["Auto", -1], ["30", 30], ["60", 60], ["Max", 0]])
	_choice("res", "Resolution", [["Full", 1.0], ["85%", 0.85], ["70%", 0.7]])
	var note := _lbl("Phones: Auto runs at 30 fps and low detail to keep it cool. Lower resolution saves battery.", 13, DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; body.add_child(note)

# ---------------------------------------------------------------- widgets
func _lbl(text: String, size: int, col := INK) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", int(size * f))
	l.add_theme_color_override("font_color", col)
	return l

func _box(col: Color, edge := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var b := StyleBoxFlat.new(); b.bg_color = col; b.set_corner_radius_all(int(8 * f))
	b.content_margin_left = 14 * f; b.content_margin_right = 14 * f; b.content_margin_top = 6 * f; b.content_margin_bottom = 6 * f
	if edge.a > 0: b.border_color = edge; b.set_border_width_all(max(1, int(1.5 * f)))
	return b

func _btn(text: String, primary: bool) -> Button:
	var b := Button.new(); b.text = text
	b.add_theme_font_size_override("font_size", int(18 * f))
	b.custom_minimum_size = Vector2(0, 42 * f)
	var n := _box(Color("#d9861c") if primary else Color(1, 1, 1, 0.08), Color(0, 0, 0, 0) if primary else Color(1, 1, 1, 0.25))
	var h := _box(Color("#f0a030") if primary else Color(1, 1, 1, 0.16), Color(0, 0, 0, 0) if primary else Color(1, 1, 1, 0.4))
	b.add_theme_stylebox_override("normal", n); b.add_theme_stylebox_override("hover", h); b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fc := Color("#1b1b1b") if primary else INK
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: b.add_theme_color_override(k, fc)
	return b

func _section(name: String) -> void:
	var l := _lbl(name.to_upper(), 13, ACCENT)
	l.add_theme_constant_override("line_spacing", 0)
	var m := MarginContainer.new(); m.add_theme_constant_override("margin_top", int(6 * f)); m.add_child(l)
	body.add_child(m)

func _row(label: String) -> HBoxContainer:
	var r := HBoxContainer.new(); r.add_theme_constant_override("separation", int(12 * f))
	var l := _lbl(label, 17); l.custom_minimum_size = Vector2(170 * f, 0)
	r.add_child(l); body.add_child(r)
	return r

func _slider(key: String, label: String, lo: float, hi: float, step: float, fmt: Callable) -> void:
	var r := _row(label)
	var sl := HSlider.new(); sl.min_value = lo; sl.max_value = hi; sl.step = step
	sl.value = Settings._get_static(key)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size = Vector2(200 * f, 36 * f)
	var track := StyleBoxFlat.new(); track.bg_color = Color(1, 1, 1, 0.18); track.set_corner_radius_all(int(4 * f))
	track.content_margin_top = 3 * f; track.content_margin_bottom = 3 * f
	var fill := track.duplicate(); fill.bg_color = ACCENT
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", fill); sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := _knob(int(22 * f))
	sl.add_theme_icon_override("grabber", knob); sl.add_theme_icon_override("grabber_highlight", knob)
	sl.focus_mode = Control.FOCUS_NONE
	r.add_child(sl)
	var val := _lbl(fmt.call(sl.value), 16, DIM); val.custom_minimum_size = Vector2(64 * f, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.add_child(val)
	sl.value_changed.connect(func(x):
		_change(key, x)
		val.text = fmt.call(x))

func _choice(key: String, label: String, opts: Array) -> void:
	var r := _row(label)
	var g := HBoxContainer.new(); g.add_theme_constant_override("separation", int(6 * f)); r.add_child(g)
	var bg := ButtonGroup.new()
	var cur = Settings._get_static(key)
	for o in opts:
		var b := Button.new(); b.text = o[0]; b.toggle_mode = true; b.button_group = bg
		b.add_theme_font_size_override("font_size", int(16 * f))
		b.custom_minimum_size = Vector2(64 * f, 38 * f)
		b.focus_mode = Control.FOCUS_NONE
		var off := _box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.2))
		var on := _box(Color(0.94, 0.63, 0.19, 0.9))
		var hov := _box(Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.3))
		b.add_theme_stylebox_override("normal", off); b.add_theme_stylebox_override("hover", hov)
		b.add_theme_stylebox_override("pressed", on); b.add_theme_stylebox_override("hover_pressed", on)
		b.add_theme_color_override("font_color", INK); b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_pressed_color", Color("#1b1b1b")); b.add_theme_color_override("font_hover_pressed_color", Color("#1b1b1b"))
		b.button_pressed = (cur == o[1]) if not (cur is float) else is_equal_approx(float(cur), float(o[1]))
		var value = o[1]
		b.toggled.connect(func(on_now): if on_now: _change(key, value))
		g.add_child(b)

func _knob(d: int) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := (d - 1) / 2.0
	for y in range(d):
		for x in range(d):
			var r := Vector2(x - c, y - c).length()
			var a := clampf(c - r + 0.5, 0.0, 1.0)
			var col := Color("#ffe1b8") if r < c - 2.0 * f else Color("#d9861c")
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)

func _change(key: String, x) -> void:
	match key:
		"volume": Settings.volume = x
		"ambience": Settings.ambience = x
		"look_sens": Settings.look_sens = x
		"invert_y": Settings.invert_y = x
		"fov": Settings.fov = x
		"btn_size": Settings.btn_size = x
		"detail":
			Settings.detail = x
			if x == -1: game.set_detail(0 if game.touch else 1)
		"fps": Settings.fps = x
		"res": Settings.res = x
	Settings.apply(game)
	Settings.save()
