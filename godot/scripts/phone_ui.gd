## The phone on the cabin wall, close up: a beige push-button phone with a little green LCD, chunky
## keys and a row of function buttons. It's how a crew gets together:
##   HOST   opens your line, and your number shows on the display for your friends to dial
##   CALL   dials the number you've punched in (or typed), and puts you on that crew
##   REDIAL the last number you called
##   HANG UP leaves the crew (or, for the boss, sends everyone home to their own cabins)
class_name PhoneUI
extends Control

var game
var lcd: Label
var name_edit: LineEdit
var dial_edit: LineEdit
var note: Label
var crew_box: VBoxContainer
var b_host: Button
var b_call: Button
var b_hang: Button
var b_redial: Button
var led: ColorRect
var _status := "PICK UP · DIAL OR HOST"
var _t := 0.0

const BEIGE := Color("#ddd3b6")
const BEIGE_DK := Color("#b4a888")
const KEY := Color("#efe8d2")
const LCD_BG := Color("#aac48c")
const LCD_INK := Color("#1d2a17")
const PLASTIC_INK := Color("#5b5340")
## each key's tone (row and column frequencies of a real touch-tone pad, as a pitch for the blip)
const TONES := {"1": [697, 1209], "2": [697, 1336], "3": [697, 1477], "4": [770, 1209], "5": [770, 1336], "6": [770, 1477],
	"7": [852, 1209], "8": [852, 1336], "9": [852, 1477], "*": [941, 1209], "0": [941, 1336], "#": [941, 1477]}

func setup(g) -> void:
	game = g
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new(); dim.color = Color(0.04, 0.03, 0.02, 0.62)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 26)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(row)
	var ph := _build_phone(); ph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sd := _build_side(); sd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ph)
	row.add_child(sd)
	Net.status.connect(func(t): _status = t; _refresh())
	Net.roster_changed.connect(_refresh)
	visible = false

func _font() -> Font:
	return game.hud._mono()

func _box(bg: Color, border: Color, radius := 10, bw := 2, bottom := -1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg; sb.border_color = border
	sb.set_border_width_all(bw)
	if bottom >= 0: sb.border_width_bottom = bottom
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	return sb

func _lbl(t: String, size: int, col: Color, mono := false) -> Label:
	var l := Label.new(); l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if mono: l.add_theme_font_override("font", _font())
	return l

func _build_phone() -> Control:
	var body := PanelContainer.new()
	var sb := _box(BEIGE, BEIGE_DK, 22, 3, 7)
	sb.shadow_color = Color(0, 0, 0, 0.5); sb.shadow_size = 18; sb.shadow_offset = Vector2(0, 8)
	sb.content_margin_left = 20; sb.content_margin_right = 20; sb.content_margin_top = 14; sb.content_margin_bottom = 16
	body.add_theme_stylebox_override("panel", sb)
	body.custom_minimum_size = Vector2(400, 0)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 9)
	body.add_child(v)
	# the maker's badge, moulded into the plastic, and the message light
	var top := HBoxContainer.new()
	var brand := _lbl("ARBOR-TEL  2400", 15, PLASTIC_INK, true)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(brand)
	var lw := HBoxContainer.new(); lw.add_theme_constant_override("separation", 6)
	led = ColorRect.new(); led.custom_minimum_size = Vector2(12, 12); led.color = Color("#5a1a14")
	var ledc := CenterContainer.new(); ledc.add_child(led)
	lw.add_child(ledc); lw.add_child(_lbl("LINE", 12, PLASTIC_INK, true))
	top.add_child(lw)
	v.add_child(top)
	# the display
	var screen := PanelContainer.new()
	var ssb := _box(LCD_BG, Color("#3d4a32"), 6, 4)
	ssb.content_margin_left = 12; ssb.content_margin_right = 12; ssb.content_margin_top = 10; ssb.content_margin_bottom = 10
	screen.add_theme_stylebox_override("panel", ssb)
	var sv := VBoxContainer.new(); sv.add_theme_constant_override("separation", 4)
	screen.add_child(sv)
	lcd = _lbl("", 17, LCD_INK, true)
	lcd.custom_minimum_size = Vector2(330, 104)
	sv.add_child(lcd)
	name_edit = _lcd_field("NAME", Net.my_name, 14)
	name_edit.text_changed.connect(func(t):
		Net.my_name = Net.clean_name(t); Net.save_cfg())
	sv.add_child(name_edit.get_parent())
	dial_edit = _lcd_field("DIAL", "", 40)
	dial_edit.placeholder_text = "192.168.1.20"
	dial_edit.text_submitted.connect(func(_t): _call())
	sv.add_child(dial_edit.get_parent())
	v.add_child(screen)
	# the keypad
	var pad := GridContainer.new(); pad.columns = 3
	pad.add_theme_constant_override("h_separation", 12); pad.add_theme_constant_override("v_separation", 8)
	var letters := {"2": "ABC", "3": "DEF", "4": "GHI", "5": "JKL", "6": "MNO", "7": "PRS", "8": "TUV", "9": "WXY", "0": "OPER", "*": ".", "#": "DEL", "1": ""}
	for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]:
		var b := _key(k, letters[k])
		pad.add_child(b)
	var padc := CenterContainer.new(); padc.add_child(pad)
	v.add_child(padc)
	# the function row
	var fr := GridContainer.new(); fr.columns = 2
	fr.add_theme_constant_override("h_separation", 10); fr.add_theme_constant_override("v_separation", 8)
	b_host = _func_btn("HOST A CREW", Color("#cfe0b4")); b_host.pressed.connect(_host)
	b_call = _func_btn("CALL", Color("#b8dcb0")); b_call.pressed.connect(_call)
	b_redial = _func_btn("REDIAL", KEY); b_redial.pressed.connect(func():
		dial_edit.text = Net.last_addr; _beep("#"); _refresh())
	b_hang = _func_btn("HANG UP", Color("#e8b4a4")); b_hang.pressed.connect(_hang)
	for b in [b_host, b_call, b_redial, b_hang]: fr.add_child(b)
	v.add_child(fr)
	var put := _func_btn("PUT THE PHONE DOWN  (ESC)", BEIGE)
	put.pressed.connect(close)
	v.add_child(put)
	return body

func _lcd_field(label: String, text: String, maxlen: int) -> LineEdit:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 8)
	h.add_child(_lbl(label + ":", 16, LCD_INK, true))
	var e := LineEdit.new()
	e.text = text; e.max_length = maxlen
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_override("font", _font())
	e.add_theme_font_size_override("font_size", 16)
	e.add_theme_color_override("font_color", LCD_INK)
	e.add_theme_color_override("font_placeholder_color", Color(LCD_INK, 0.35))
	e.add_theme_color_override("caret_color", LCD_INK)
	e.add_theme_color_override("selection_color", Color(LCD_INK, 0.25))
	var flat := _box(Color(LCD_BG.darkened(0.06)), Color(LCD_INK, 0.35), 3, 1)
	flat.content_margin_top = 2; flat.content_margin_bottom = 2; flat.content_margin_left = 6
	e.add_theme_stylebox_override("normal", flat)
	var foc := flat.duplicate(); foc.border_color = LCD_INK
	e.add_theme_stylebox_override("focus", foc)
	h.add_child(e)
	return e

func _key(k: String, sub: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(92, 46)
	b.text = k + ("\n" + sub if sub != "" else "")
	b.add_theme_font_override("font", _font())
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color("#2c2820"))
	b.add_theme_color_override("font_hover_color", Color("#2c2820"))
	b.add_theme_color_override("font_pressed_color", Color("#2c2820"))
	b.add_theme_stylebox_override("normal", _box(KEY, BEIGE_DK, 9, 2, 5))
	b.add_theme_stylebox_override("hover", _box(KEY.lightened(0.25), BEIGE_DK, 9, 2, 5))
	var pr := _box(KEY.darkened(0.08), BEIGE_DK, 9, 2, 2)
	pr.content_margin_top = 11
	b.add_theme_stylebox_override("pressed", pr)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): _press(k))
	return b

func _func_btn(t: String, col: Color) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(170, 38)
	b.add_theme_font_override("font", _font())
	b.add_theme_font_size_override("font_size", 15)
	for s in ["font_color", "font_hover_color", "font_pressed_color"]: b.add_theme_color_override(s, Color("#2c2820"))
	b.add_theme_color_override("font_disabled_color", Color("#2c2820", 0.35))
	b.add_theme_stylebox_override("normal", _box(col, BEIGE_DK, 8, 2, 5))
	b.add_theme_stylebox_override("hover", _box(col.lightened(0.2), BEIGE_DK, 8, 2, 5))
	b.add_theme_stylebox_override("pressed", _box(col.darkened(0.1), BEIGE_DK, 8, 2, 2))
	b.add_theme_stylebox_override("disabled", _box(col.darkened(0.12), Color(BEIGE_DK, 0.5), 8, 2, 3))
	b.focus_mode = Control.FOCUS_NONE
	return b

## beside the phone: who's on the line, and how to give a friend your number
func _build_side() -> Control:
	var card := PanelContainer.new()
	var sb := _box(Color("#f3ecd8"), Color("#c9bc98"), 4, 1)
	sb.shadow_color = Color(0, 0, 0, 0.4); sb.shadow_size = 10
	sb.content_margin_left = 18; sb.content_margin_right = 18; sb.content_margin_top = 14; sb.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(340, 0)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	v.add_child(_lbl("CREW SHEET", 18, Color("#7a2a1e"), true))
	var rule := ColorRect.new(); rule.color = Color("#d07a6a"); rule.custom_minimum_size = Vector2(0, 2)
	v.add_child(rule)
	crew_box = VBoxContainer.new(); crew_box.add_theme_constant_override("separation", 4)
	v.add_child(crew_box)
	var rule2 := ColorRect.new(); rule2.color = Color("#9ab4d0"); rule2.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule2)
	note = _lbl("", 14, Color("#3a3428"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(300, 0)
	v.add_child(note)
	return card

# ---------------------------------------------------------------- open, close
func open() -> void:
	visible = true
	name_edit.text = Net.my_name
	if dial_edit.text == "": dial_edit.text = Net.last_addr
	Sfx.play("pick", 0.7, 0.8)
	_refresh()

func close() -> void:
	if not visible: return
	visible = false
	name_edit.release_focus(); dial_edit.release_focus()
	Sfx.play("clank", 0.35, 1.6)
	game.phone_closed()

func _input(ev: InputEvent) -> void:
	if not visible: return
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if name_edit.has_focus() or dial_edit.has_focus():
			name_edit.release_focus(); dial_edit.release_focus()
		else:
			close()

# ---------------------------------------------------------------- the buttons
func _beep(k: String) -> void:
	var tn: Array = TONES.get(k, [800, 1200])
	Sfx.play("blip", 0.55, (float(tn[0]) + float(tn[1])) / 1900.0)

func _press(k: String) -> void:
	_beep(k)
	if Net.active(): return                  # you're on a call: the keys just beep
	match k:
		"#": dial_edit.text = dial_edit.text.substr(0, maxi(0, dial_edit.text.length() - 1))
		"*": dial_edit.text += "."
		_: dial_edit.text += k
	dial_edit.caret_column = dial_edit.text.length()
	_refresh()

func _host() -> void:
	if Net.active(): return
	Net.my_name = Net.clean_name(name_edit.text)
	_beep("1")
	var err := Net.host()
	if err != "": _status = err
	_refresh()
	game._crew_changed()

func _call() -> void:
	if Net.active() or Net.role == "dialing": return
	Net.my_name = Net.clean_name(name_edit.text)
	var err := Net.join(dial_edit.text)
	if err != "": _status = err
	_refresh()

func _hang() -> void:
	if Net.role == "": return
	Net.leave()
	game._crew_changed()
	_refresh()

# ---------------------------------------------------------------- the display
func _refresh() -> void:
	if lcd == null: return
	var tm := Time.get_time_dict_from_system()
	var hr := int(tm.hour) % 12
	if hr == 0: hr = 12
	var clock := "%d:%02d%s" % [hr, int(tm.minute), "P" if int(tm.hour) >= 12 else "A"]
	var lines := []
	lines.append(_pad("ARBOR-TEL", clock, 26))
	match Net.role:
		"host":
			var addrs := Net.local_addresses()
			lines.append(_pad("LINE OPEN", "CREW %d/%d" % [Net.roster.size(), Net.MAX_CREW], 26))
			lines.append("YOUR NO: " + (str(addrs[0]) if not addrs.is_empty() else "???"))
			lines.append("PORT %d" % Net.PORT)
		"guest":
			lines.append(_pad("ON THE LINE", "CREW %d/%d" % [Net.roster.size(), Net.MAX_CREW], 26))
			lines.append(("BOSS: " + Net.boss_name()).to_upper().substr(0, 26))
			lines.append("WAIT FOR A JOB")
		"dialing":
			lines.append("CALLING")
			lines.append(dial_edit.text.substr(0, 26))
			lines.append("")
		_:
			lines.append("ON HOOK")
			lines.append("HOST, OR DIAL A CREW")
			lines.append("")
	lines.append(_status.substr(0, 26))
	lcd.text = "\n".join(lines)
	b_host.disabled = Net.role != ""
	b_call.disabled = Net.role != "" or dial_edit.text.strip_edges() == ""
	b_redial.disabled = Net.role != "" or Net.last_addr == ""
	b_hang.disabled = Net.role == ""
	name_edit.editable = Net.role == ""
	dial_edit.editable = Net.role == ""
	# the crew sheet
	for c in crew_box.get_children(): c.queue_free()
	if Net.active():
		var ids := Net.roster.keys(); ids.sort()
		for id in ids:
			var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 8)
			var hat := ColorRect.new(); hat.color = Net.hat_of(id); hat.custom_minimum_size = Vector2(14, 14)
			var hc := CenterContainer.new(); hc.add_child(hat)
			h.add_child(hc)
			var who := Net.name_of(id) + ("  (boss)" if id == 1 else "") + ("  ← you" if id == Net.me() else "")
			h.add_child(_lbl(who, 16, Color("#2a2620")))
			crew_box.add_child(h)
		for i in range(Net.MAX_CREW - Net.roster.size()): crew_box.add_child(_lbl("· · · open seat", 15, Color("#9a9078")))
	else:
		crew_box.add_child(_lbl("Nobody on the line.", 16, Color("#5a5444")))
	match Net.role:
		"host":
			var addrs := Net.local_addresses()
			var more := "" if addrs.size() <= 1 else "\n(Also: " + ", ".join(addrs.slice(1)) + ")"
			note.text = "Friends in your house dial %s.%s\n\nFriends somewhere else: forward port %d (UDP) on your router to this computer, then give them your public address (search \"what is my IP\").\n\nWhen the crew's here, take a job on the computer and everybody goes." % [addrs[0] if not addrs.is_empty() else "your computer's address", more, Net.PORT]
		"guest":
			note.text = "You're on %s's crew. When they take a job on their computer, you'll all head out together.\n\nYou keep your own money and gear. The pay's split evenly." % Net.boss_name()
		_:
			note.text = "HOST a crew and give your friends the number on the display, or punch in a friend's number and CALL.\n\nUp to %d on a crew. The boss picks the jobs; everyone gets a share of the pay." % Net.MAX_CREW

static func _pad(a: String, b: String, w: int) -> String:
	var gap := maxi(1, w - a.length() - b.length())
	return a + " ".repeat(gap) + b

func _process(dt: float) -> void:
	if not visible: return
	_t += dt
	# the line light: steady on a call, blinking while it rings
	match Net.role:
		"host", "guest": led.color = Color("#ff3a26")
		"dialing": led.color = Color("#ff3a26") if int(_t * 3.0) % 2 == 0 else Color("#5a1a14")
		_: led.color = Color("#5a1a14")
	if int(_t) != int(_t - dt): _refresh()
