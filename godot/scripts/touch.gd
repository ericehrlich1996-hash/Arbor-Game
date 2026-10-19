## Touch controls for phones and tablets. Turns on by itself on a touchscreen (or with ARBOR_TOUCH=1).
## Left thumb: a floating joystick (walk; push it to the edge to run; in the truck it's throttle and
## steering). Right thumb: drag anywhere to look. Buttons on the right do what the mouse and keys do:
## USE is the left mouse button (cut, grab, cast, reel, swing); a double-tap is the right (hold the second
## tap down to keep it held: rev, set down, jig),
## E to talk/use/drive, jump/brake, kick, and two little arrows for the mouse wheel (cut angle, set the
## hook). A row of small buttons along the top right covers the rest, and the hotbar slots are tappable.
## Every press is fed straight to the game as the key, action or mouse button it stands for.
class_name TouchControls
extends CanvasLayer

var game
var pad: Pad
var joy_id := -1; var joy_o := Vector2.ZERO; var joy_v := Vector2.ZERO
var look_id := -1; var look_last := Vector2.ZERO; var look_start := Vector2.ZERO; var look_t := 0
var alt_id := -1                  # the finger holding a double-tap (right mouse) down
var tap_t := -100000; var tap_p := Vector2.ZERO   # when and where the last quick tap ended
var held := {}                    # touch index -> button id
var btn_down := {}                # button id -> true while held
var buttons: Array = []           # [{id, label, c (centre), r (radius), small}]

static func wanted() -> bool:
	if OS.get_environment("ARBOR_TOUCH") == "1": return true
	if OS.get_environment("ARBOR_TOUCH") == "0": return false
	return DisplayServer.is_touchscreen_available()

func setup(g) -> void:
	game = g
	layer = 4                     # under the HUD (5), so its screens and buttons get taps first
	pad = Pad.new(); pad.touch = self
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_STOP      # swallow the mouse clicks the browser fakes from touches
	add_child(pad)
	get_viewport().size_changed.connect(_layout)
	game.hud.use_touch_text()
	_layout()
	# the hotbar's slots become buttons
	for k in game.hud.slots:
		var slot: Control = game.hud.slots[k]
		var key: String = k
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _tool(key))

## is the touch layer in charge right now (no menu or full-screen card up)?
func active() -> bool:
	var h = game.hud
	if h.pc_screen.visible: return false
	if h.get("summary") and h.summary.visible: return false
	if h.get("title") and h.title.visible: return false
	return game.phase == "play" or game.phase == "hub" or game.phase == "intro"

func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	var u := minf(s.x, s.y) / 8.0 * Settings.btn_size
	buttons = []
	var br := Vector2(s.x - u * 1.25, s.y - u * 1.35)
	buttons.append({id = "use", label = "USE", c = br, r = u * 0.82})
	buttons.append({id = "interact", label = "E", c = br + Vector2(-u * 0.25, -u * 1.75), r = u * 0.55})
	buttons.append({id = "jump", label = "JUMP", c = br + Vector2(-u * 1.85, -u * 1.25), r = u * 0.5})
	buttons.append({id = "kick", label = "KICK", c = br + Vector2(-u * 3.3, -u * 0.6), r = u * 0.45})
	buttons.append({id = "wheel_up", label = "▲", c = br + Vector2(u * 0.8, -u * 3.1), r = u * 0.36})
	buttons.append({id = "wheel_down", label = "▼", c = br + Vector2(u * 0.8, -u * 2.3), r = u * 0.36})
	# the rest, small, along the top right under the money
	var small := [["saw_start", "START SAW"], ["drag", "DRAG"], ["throw", "THROW"], ["drop", "DROP"], ["crouch", "CROUCH"], ["camera", "CAMERA"], ["unstick", "UNSTICK"], ["menu", "MENU"]]
	# rows of four across the top right, under the money
	var w := u * 1.3; var h := u * 0.5; var gap := u * 0.12
	for i in range(small.size()):
		var col := i % 4; var row := i / 4
		var c := Vector2(s.x - u * 0.2 - w / 2.0 - (3 - col) * (w + gap), u * 1.05 + row * (h + gap))
		buttons.append({id = small[i][0], label = small[i][1], c = c, r = h / 2.0, w = w, small = true})
	pad.queue_redraw()

func _hit(p: Vector2) -> String:
	for b in buttons:
		if b.get("small", false):
			if absf(p.x - b.c.x) <= float(b.w) / 2.0 + 4.0 and absf(p.y - b.c.y) <= float(b.r) + 4.0: return b.id
		elif p.distance_to(b.c) <= float(b.r) * 1.15: return b.id
	return ""

func _input(ev: InputEvent) -> void:
	if not (ev is InputEventScreenTouch or ev is InputEventScreenDrag): return
	if not active():
		_release_all()
		return
	var s := get_viewport().get_visible_rect().size
	if ev is InputEventScreenTouch:
		if ev.pressed:
			# in the intro drive any tap skips it; in a conversation any tap moves it on
			if game.phase == "intro":
				var k := InputEventKey.new(); k.physical_keycode = KEY_SPACE; k.pressed = true
				game._unhandled_input(k); return
			var b := _hit(ev.position)
			if b != "":
				held[ev.index] = b; _press(b, true)
			elif ev.position.x < s.x * 0.42 and ev.position.y > s.y * 0.35:
				# the left thumb always gets the stick, even if an old touch never reported lifting
				# (otherwise it would fall through to looking)
				if joy_id != -1 and joy_id != ev.index: _move(Vector2.ZERO)
				joy_id = ev.index; joy_o = ev.position; joy_v = Vector2.ZERO
				if look_id == ev.index: look_id = -1
			else:
				if game.dlg != null: _press("interact", true); _press("interact", false); return
				var now := Time.get_ticks_msec()
				# a second tap close behind a quick first one is the right mouse button, held while it's down
				if now - tap_t < 350 and ev.position.distance_to(tap_p) < minf(s.x, s.y) * 0.2 and alt_id == -1:
					alt_id = ev.index; tap_t = -100000; _press("alt", true)
				look_id = ev.index; look_last = ev.position; look_start = ev.position; look_t = now
		else:
			if held.has(ev.index):
				_press(held[ev.index], false); held.erase(ev.index)
			if ev.index == joy_id: joy_id = -1; joy_v = Vector2.ZERO; _move(Vector2.ZERO)
			if ev.index == alt_id: alt_id = -1; _press("alt", false)
			elif ev.index == look_id:
				var now := Time.get_ticks_msec()
				if now - look_t < 250 and ev.position.distance_to(look_start) < minf(s.x, s.y) * 0.05:
					tap_t = now; tap_p = ev.position
			if ev.index == look_id: look_id = -1
		pad.queue_redraw()
	elif ev is InputEventScreenDrag:
		if ev.index == joy_id:
			var R := minf(s.x, s.y) / 8.0
			var d: Vector2 = ev.position - joy_o
			if d.length() > R: joy_o += d - d.normalized() * R; d = d.normalized() * R        # the base follows your thumb
			joy_v = d / R
			_move(joy_v)
			pad.queue_redraw()
		elif ev.index == look_id:
			var dd: Vector2 = ev.position - look_last
			look_last = ev.position
			var k := 2.6 / s.y * Settings.look_sens        # a full-height swipe turns you about 150°
			var ky := k * (-1.0 if Settings.invert_y else 1.0)
			if game.player and game.dlg == null:
				if game.player.in_truck: game.truck.look(dd.x * k, dd.y * ky)
				else: game.player.look(dd.x * k, dd.y * ky)

## the joystick as the four move actions (analogue), and running when it's pushed right out
func _move(v: Vector2) -> void:
	for e in [["move_right", maxf(0.0, v.x)], ["move_left", maxf(0.0, -v.x)], ["move_fwd", maxf(0.0, -v.y)], ["move_back", maxf(0.0, v.y)]]:
		if e[1] > 0.08: Input.action_press(e[0], minf(1.0, e[1] * 1.15))
		else: Input.action_release(e[0])
	if v.length() > 0.93 and game.player and not game.player.in_truck: Input.action_press("run")
	else: Input.action_release("run")

func _press(id: String, down: bool) -> void:
	btn_down[id] = down
	match id:
		"use": _mouse(MOUSE_BUTTON_LEFT, down); _poll("use", down)
		"alt": _mouse(MOUSE_BUTTON_RIGHT, down); _poll("rev", down)
		"wheel_up": if down: _mouse(MOUSE_BUTTON_WHEEL_UP, true); _mouse(MOUSE_BUTTON_WHEEL_UP, false)
		"wheel_down": if down: _mouse(MOUSE_BUTTON_WHEEL_DOWN, true); _mouse(MOUSE_BUTTON_WHEEL_DOWN, false)
		"menu": if not down and game.can_pause(): game.pause.open()
		_: _action(id, down)
	pad.queue_redraw()

func _tool(slot: String) -> void:
	var a: String = {"hands": "tool1", "saw": "tool2", "muffs": "tool3", "wedge": "tool4", "rope": "tool5", "rod": "tool6"}.get(slot, "")
	if a != "": _action(a, true); _action(a, false)

func _action(a: String, down: bool) -> void:
	_poll(a, down)
	var e := InputEventAction.new(); e.action = a; e.pressed = down
	game._unhandled_input(e)

func _poll(a: String, down: bool) -> void:
	if down: Input.action_press(a)
	else: Input.action_release(a)

func _mouse(b: MouseButton, down: bool) -> void:
	var e := InputEventMouseButton.new(); e.button_index = b; e.pressed = down
	e.position = get_viewport().get_visible_rect().size / 2.0
	game._unhandled_input(e)

func _release_all() -> void:
	for i in held: _press(held[i], false)
	held.clear()
	if joy_id != -1: joy_id = -1; _move(Vector2.ZERO)
	if alt_id != -1: alt_id = -1; _press("alt", false)
	look_id = -1

func _process(_dt: float) -> void:
	pad.visible = active()

## draws the stick and the buttons
class Pad extends Control:
	var touch
	func _draw() -> void:
		var t = touch
		var font := ThemeDB.fallback_font
		if t.joy_id != -1:
			var R := minf(size.x, size.y) / 8.0
			draw_circle(t.joy_o, R, Color(1, 1, 1, 0.12))
			draw_arc(t.joy_o, R, 0, TAU, 40, Color(1, 1, 1, 0.35), 2.0)
			draw_circle(t.joy_o + t.joy_v * R, R * 0.42, Color(1, 1, 1, 0.45))
		else:
			# a hint where the stick lives
			var hp := Vector2(size.x * 0.16, size.y * 0.72)
			draw_arc(hp, minf(size.x, size.y) / 8.0, 0, TAU, 40, Color(1, 1, 1, 0.18), 2.0)
			draw_string(font, hp + Vector2(-30, 6), "MOVE", HORIZONTAL_ALIGNMENT_CENTER, 60, 14, Color(1, 1, 1, 0.4))
		for b in t.buttons:
			var on: bool = t.btn_down.get(b.id, false)
			var small: bool = b.get("small", false)
			var bg := Color(0.08, 0.08, 0.07, 0.62 if not on else 0.85)
			var edge := Color("#e8b84a") if on else Color(1, 1, 1, 0.45)
			var w := float(b.r) * 2.0
			if small:
				w = float(b.w)
				var rc := Rect2(b.c - Vector2(w / 2.0, b.r), Vector2(w, b.r * 2.0))
				var sb := StyleBoxFlat.new(); sb.bg_color = bg; sb.border_color = edge; sb.set_border_width_all(2); sb.set_corner_radius_all(int(b.r))
				draw_style_box(sb, rc)
			else:
				draw_circle(b.c, b.r, bg)
				draw_arc(b.c, b.r, 0, TAU, 36, edge, 2.0)
			var fs := 12 if small else (20 if b.label.length() <= 2 else 16)
			draw_string(font, b.c + Vector2(-w / 2.0, fs * 0.35), b.label, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(1, 1, 1, 0.9))
