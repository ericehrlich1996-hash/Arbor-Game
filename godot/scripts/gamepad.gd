## Controller support (Xbox layout: ROG Ally, Steam Deck, an Xbox pad on a PC).
## Most buttons are plain input actions (see bind_actions). The rest stand in for the mouse the same
## way the touch controls do: the triggers are the mouse buttons, the right stick is mouse look, and
## the d-pad's up and down are the wheel. In menus the d-pad or left stick moves between buttons,
## A presses one, and B backs out.
##
##   Left stick   walk (click it to run) · in the truck: steer
##   Right stick  look
##   RT           left mouse: grab, cast, reel, swing, throw the climbing line · saw in hand: pull-start
##                it, then it's the throttle (rev and cut) · truck: gas
##   LT           right mouse: rev the saw, set down / throw in the bed, jig · truck: reverse
##   A jump (truck: brake)   X talk / pick up / use / drive   B drop one piece
##   Y throw (hold in the tree: let the lowering rope run) · by the truck or in it: unstick
##   LB (hold)    the tool wheel: point the right stick at a tool, let go to take it
##   RB           kick (hold it in the tree to flip your lanyard past a limb)
##   D-pad ← →    the mouse wheel: angle the cut (→ sets the hook)
##   D-pad ↑      ear muffs        D-pad ↓  drag
##   R3 crouch    View: stop the saw (truck: camera), hold it for help    Menu: pause
class_name Gamepad
extends Node

const DEAD := 0.14
const LOOK_SPEED := 3.2          # rad/s at full stick, before the look-speed setting
const TRIGGER_ON := 0.45
const TRIGGER_OFF := 0.3
const WHEEL_REPEAT := 0.11

var game
var last_used := -1000.0         # when a pad was last touched (seconds): pad hints show for a while after
var _clock := 0.0
var _rt := false
var _lt := false
var _run := false
var _wheel_t := 0.0
var _wheel_dir := 0
var _view_t := -1.0
var _view_help := false
var _pad_last := false
var _moving := false
var _saw_rt := false             # RT is down as the saw's throttle (rev), not the left mouse
var wheel: ToolWheel
var _prev_tool := "hands"
var _cur_tool := "hands"

static var me: Gamepad = null
static var fake := {}            # tests: axis -> value, standing in for a real pad

## the pad's in your hands (it was the last thing used)
static func in_use() -> bool:
	return me != null and me._pad_last

## extra throttle from the triggers when you're driving (RT gas, LT reverse)
static func drive_axis() -> float:
	if me == null or (Input.get_connected_joypads().is_empty() and fake.is_empty()): return 0.0
	var r := Gamepad.axis(JOY_AXIS_TRIGGER_RIGHT)
	var l := Gamepad.axis(JOY_AXIS_TRIGGER_LEFT)
	return clampf((r if r > 0.08 else 0.0) - (l if l > 0.08 else 0.0), -1.0, 1.0)

static func axis(a: int) -> float:
	if not fake.is_empty(): return float(fake.get(a, 0.0))
	return Input.get_joy_axis(_dev(), a)

static func _dev() -> int:
	var pads := Input.get_connected_joypads()
	return int(pads[0]) if not pads.is_empty() else 0

## the buttons that are just actions, added alongside the keys
static func bind_actions() -> void:
	var btn := {
		jump = [JOY_BUTTON_A], interact = [JOY_BUTTON_X], kick = [JOY_BUTTON_RIGHT_SHOULDER], drop = [JOY_BUTTON_B],
		throw = [JOY_BUTTON_Y],
		crouch = [JOY_BUTTON_RIGHT_STICK], drag = [JOY_BUTTON_DPAD_DOWN], tool3 = [JOY_BUTTON_DPAD_UP],
	}
	for act in btn:
		if not InputMap.has_action(act): InputMap.add_action(act)
		for b in btn[act]:
			var e := InputEventJoypadButton.new(); e.button_index = b; e.device = -1
			InputMap.action_add_event(act, e)
	# (the left stick drives the move actions from _process, not the input map: a stick that snaps
	# back to exactly 0 can leave a mapped action stuck on)
	# menus: d-pad and left stick move between buttons, A presses, B backs out
	var ui := {ui_up = [JOY_BUTTON_DPAD_UP, JOY_AXIS_LEFT_Y, -1.0], ui_down = [JOY_BUTTON_DPAD_DOWN, JOY_AXIS_LEFT_Y, 1.0],
		ui_left = [JOY_BUTTON_DPAD_LEFT, JOY_AXIS_LEFT_X, -1.0], ui_right = [JOY_BUTTON_DPAD_RIGHT, JOY_AXIS_LEFT_X, 1.0]}
	for act in ui:
		var have_b := false; var have_a := false
		for e in InputMap.action_get_events(act):
			if e is InputEventJoypadButton and e.button_index == ui[act][0]: have_b = true
			if e is InputEventJoypadMotion and e.axis == ui[act][1]: have_a = true
		if not have_b:
			var e := InputEventJoypadButton.new(); e.button_index = ui[act][0]; e.device = -1
			InputMap.action_add_event(act, e)
		if not have_a:
			var m := InputEventJoypadMotion.new(); m.axis = ui[act][1]; m.axis_value = ui[act][2]; m.device = -1
			InputMap.action_add_event(act, m)
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var have := false
		for e in InputMap.action_get_events(pair[0]):
			if e is InputEventJoypadButton and e.button_index == pair[1]: have = true
		if not have:
			var e := InputEventJoypadButton.new(); e.button_index = pair[1]; e.device = -1
			InputMap.action_add_event(pair[0], e)

func setup(g) -> void:
	game = g
	me = self
	process_mode = Node.PROCESS_MODE_ALWAYS      # the pause menu needs the pad too
	wheel = ToolWheel.new(); add_child(wheel)
	Input.joy_connection_changed.connect(func(_d, on):
		if on and game and is_instance_valid(game) and game.hud:
			game.hud.toast("Controller connected. Hold View for the button layout.", 3.5))

# ---------------------------------------------------------------- what's on screen
func _menu() -> Control:
	var h = game.hud
	if game.pause and game.pause.is_open(): return game.pause.panel if is_instance_valid(game.pause.panel) else null
	if game.phone and game.phone.visible: return _first_control(game.phone)
	if h.pc_screen.visible: return h.pc_screen
	if h.get("summary") and h.summary.visible: return h.summary
	if h.get("title") and h.title.visible: return h.title
	return null

func _first_control(n: Node) -> Control:
	for c in n.get_children():
		if c is Control: return c
	return null

func _focusable(n: Node) -> Control:
	if n is Control and (n as Control).is_visible_in_tree() and (n as Control).focus_mode == Control.FOCUS_ALL and (n is BaseButton or n is Range):
		if not (n is BaseButton and (n as BaseButton).disabled): return n
	for c in n.get_children():
		var f := _focusable(c)
		if f: return f
	return null

## the menus are built for the mouse (no keyboard focus, so Space can't press a button by accident);
## with a pad in hand every button and slider in them can take focus
func _let_focus(n: Node) -> void:
	if (n is BaseButton or n is Range) and (n as Control).focus_mode == Control.FOCUS_NONE and not (n is ScrollBar):
		(n as Control).focus_mode = Control.FOCUS_ALL
	# (a text box is never a pad stop: the d-pad would move its cursor, not the focus)
	if n is LineEdit: (n as LineEdit).focus_mode = Control.FOCUS_CLICK
	for c in n.get_children(): _let_focus(c)

var _focus_t := 0.0
var _stick_out := false

## the pad's cursor moves to the nearest button that way (and on a slider, left and right slide it)
func _menu_move(m: Control, dir: Vector2) -> void:
	_let_focus(m)
	var fo := get_viewport().gui_get_focus_owner()
	if fo == null or not m.is_ancestor_of(fo):
		var f := _focusable(m)
		if f: f.grab_focus()
		return
	if fo is Range and dir.y == 0.0:
		var r := fo as Range
		r.value = clampf(r.value + dir.x * maxf(r.step, (r.max_value - r.min_value) / 20.0), r.min_value, r.max_value)
		return
	var from := fo.get_global_rect()
	var c0 := from.get_center()
	var best: Control = null; var bd := INF
	for c in _all_focusable(m):
		if c == fo: continue
		var rc: Rect2 = c.get_global_rect()
		var d := rc.get_center() - c0
		if d.dot(dir) <= 4.0: continue
		# measured edge to edge: the gap that way, and how far off to the side (0 if they overlap)
		var along: float; var across: float
		if dir.y != 0.0:
			along = (rc.position.y - from.end.y) if dir.y > 0.0 else (from.position.y - rc.end.y)
			across = maxf(0.0, maxf(rc.position.x - from.end.x, from.position.x - rc.end.x))
		else:
			along = (rc.position.x - from.end.x) if dir.x > 0.0 else (from.position.x - rc.end.x)
			across = maxf(0.0, maxf(rc.position.y - from.end.y, from.position.y - rc.end.y))
		if along < -from.size.length() * 0.25: continue
		var score := maxf(along, 0.0) + across * 3.0 + absf(d.dot(Vector2(dir.y, dir.x))) * 0.05
		if score < bd: bd = score; best = c
	if best:
		best.grab_focus()
		Sfx.play("pick", 0.2, 1.9)

func _all_focusable(n: Node, out: Array = []) -> Array:
	if n is Control and (n as Control).is_visible_in_tree() and (n as Control).focus_mode == Control.FOCUS_ALL and (n is BaseButton or n is Range) and not (n is ScrollBar):
		if not (n is BaseButton and (n as BaseButton).disabled): out.append(n)
	for c in n.get_children(): _all_focusable(c, out)
	return out

func _menu_focus(m: Control) -> void:
	_focus_t -= get_process_delta_time()
	if _focus_t <= 0.0:
		_focus_t = 0.25
		_let_focus(m)
	var fo := get_viewport().gui_get_focus_owner()
	if fo and fo.is_visible_in_tree() and m.is_ancestor_of(fo): return
	var f := _focusable(m)
	if f: f.grab_focus()

# ---------------------------------------------------------------- buttons
func _input(ev: InputEvent) -> void:
	if not (ev is InputEventJoypadButton or ev is InputEventJoypadMotion):
		if ev is InputEventKey or ev is InputEventMouseButton or (ev is InputEventMouseMotion and ev.relative.length() > 3.0):
			if _pad_last:
				_pad_last = false
				_hints_changed()
				# back on the keyboard and mouse: let go of the menu focus (Space mustn't press a button)
				var fo := get_viewport().gui_get_focus_owner()
				if fo: fo.release_focus()
		return
	if ev is InputEventJoypadMotion:
		# the left stick in a menu: one step each time it's pushed out (the d-pad's handled below)
		if ev.axis == JOY_AXIS_LEFT_X or ev.axis == JOY_AXIS_LEFT_Y:
			var mm := _menu()
			if mm != null:
				get_viewport().set_input_as_handled()
				var st := Vector2(Gamepad.axis(JOY_AXIS_LEFT_X), Gamepad.axis(JOY_AXIS_LEFT_Y)) if fake.is_empty() else Vector2.ZERO
				if ev.axis == JOY_AXIS_LEFT_X: st.x = ev.axis_value
				else: st.y = ev.axis_value
				if st.length() > 0.6 and not _stick_out:
					_stick_out = true
					_menu_move(mm, (Vector2(signf(st.x), 0) if absf(st.x) > absf(st.y) else Vector2(0, signf(st.y))))
				elif st.length() < 0.3: _stick_out = false
		if absf(ev.axis_value) < 0.4: return
	last_used = _clock
	if not _pad_last:
		_pad_last = true
		_hints_changed()
	if not (ev is InputEventJoypadButton): return
	var b: int = ev.button_index
	var down: bool = ev.pressed
	var m := _menu()
	if m != null:
		if down and (b == JOY_BUTTON_B or (b == JOY_BUTTON_START and (game.pause.is_open() or game.phone.visible))):
			_key(KEY_ESCAPE)
			get_viewport().set_input_as_handled()
		elif b in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
			if down: _menu_move(m, {JOY_BUTTON_DPAD_UP: Vector2.UP, JOY_BUTTON_DPAD_DOWN: Vector2.DOWN, JOY_BUTTON_DPAD_LEFT: Vector2.LEFT, JOY_BUTTON_DPAD_RIGHT: Vector2.RIGHT}[b])
			get_viewport().set_input_as_handled()
		return
	# play
	if game.phase == "intro":
		if down and b in [JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_START]: _key(KEY_SPACE)
		return
	if b == JOY_BUTTON_START and down:
		if game.can_pause(): game.pause.open()
		return
	if game.phase != "play" and game.phase != "hub": return
	if down and not game.cap(): game._capture()
	match b:
		JOY_BUTTON_LEFT_STICK:
			if down: _run = not _run; _act("run", _run)
		JOY_BUTTON_LEFT_SHOULDER:
			if down: wheel.open_for(self)
			else: wheel.close_pick()
		JOY_BUTTON_DPAD_LEFT:
			_wheel_dir = 1 if down else (0 if _wheel_dir == 1 else _wheel_dir)
			if down: _wheel(MOUSE_BUTTON_WHEEL_UP); _wheel_t = 0.35
		JOY_BUTTON_DPAD_RIGHT:
			_wheel_dir = -1 if down else (0 if _wheel_dir == -1 else _wheel_dir)
			if down: _wheel(MOUSE_BUTTON_WHEEL_DOWN); _wheel_t = 0.35
		JOY_BUTTON_Y:
			# unstick: in the truck, or standing by it with nothing in your arms (otherwise Y throws)
			if down: _maybe_unstick()
		JOY_BUTTON_BACK:
			# tap: the action (start the saw / truck camera, bound above). Held: the help card
			if down: _view_t = 0.0; _view_help = false
			else:
				if _view_help: game.hud.help.visible = false
				elif _view_t >= 0.0:
					# a tap: start the saw on foot, switch the camera in the truck
					for a in ["saw_start", "camera"]:
						var e := InputEventAction.new(); e.action = a; e.pressed = true
						game._unhandled_input(e)
				_view_t = -1.0

func _key(k: Key) -> void:
	var e := InputEventKey.new(); e.keycode = k; e.physical_keycode = k; e.pressed = true
	Input.parse_input_event(e)
	var u := InputEventKey.new(); u.keycode = k; u.physical_keycode = k; u.pressed = false
	Input.parse_input_event(u)

func _act(act: String, down: bool) -> void:
	if down: Input.action_press(act)
	else: Input.action_release(act)

func _mouse(b: MouseButton, down: bool) -> void:
	var e := InputEventMouseButton.new(); e.button_index = b; e.pressed = down
	e.position = get_viewport().get_visible_rect().size / 2.0
	game._unhandled_input(e)

func _wheel(b: MouseButton) -> void:
	if game.player and game.player.in_truck: return
	_mouse(b, true); _mouse(b, false)

## the tools you've got, in hotbar order: [slot id, label, action]
func tools() -> Array:
	var out := []
	var h = game.hud
	for t in [["hands", "Hands", "tool1"], ["saw", "Chainsaw", "tool2"], ["muffs", "Ear muffs", "tool3"], ["wedge", "Wedges", "tool4"],
			["rope", "Rope", "tool5"], ["rod", "Fishing rod", "tool6"], ["climb", "Climbing kit", "tool7"]]:
		if h.slots.has(t[0]) and not h.slots[t[0]].visible: continue
		if game.climb and game.climb.climbing and t[0] in ["wedge", "rod"]: continue
		out.append(t)
	return out

func can_switch() -> bool:
	var p = game.player
	return p != null and not p.in_truck and game.dlg == null and not game.in_hub and game.phase == "play"

func equip_slot(id: String) -> void:
	for t in tools():
		if t[0] == id:
			var e := InputEventAction.new(); e.action = t[2]; e.pressed = true
			game._unhandled_input(e)
			return

## RB: back to whatever you had in your hands before this
func _swap_back() -> void:
	if not can_switch(): return
	if _prev_tool != game.player.tool: equip_slot(_prev_tool)

func _maybe_unstick() -> void:
	var p = game.player
	if p == null or game.dlg != null or game.in_hub: return
	var near: bool = p.in_truck or (game.truck != null and p.global_position.distance_to(game.truck.global_position) < 6.0 and not game.haul.carrying() and not (game.climb != null and game.climb.climbing))
	if near:
		var e := InputEventAction.new(); e.action = "unstick"; e.pressed = true
		game._unhandled_input(e)

# ---------------------------------------------------------------- sticks and triggers
func _process(dt: float) -> void:
	_clock += dt
	_jump_guard()
	var m := _menu()
	if m != null:
		if _pad_last: _menu_focus(m)
		_triggers_off()
		return
	if Input.get_connected_joypads().is_empty() and fake.is_empty(): return
	if game.phase != "play" and game.phase != "hub": _triggers_off(); return
	var p = game.player
	if p == null: return
	# walk (the truck reads the same actions to steer)
	var ls := Vector2(Gamepad.axis(JOY_AXIS_LEFT_X), Gamepad.axis(JOY_AXIS_LEFT_Y))
	if ls.length() > 0.2:
		var v2 := ls.normalized() * clampf((ls.length() - 0.2) / 0.75, 0.0, 1.0)
		for e in [["move_right", maxf(0.0, v2.x)], ["move_left", maxf(0.0, -v2.x)], ["move_fwd", maxf(0.0, -v2.y)], ["move_back", maxf(0.0, v2.y)]]:
			if e[1] > 0.02: Input.action_press(e[0], minf(1.0, e[1]))
			else: Input.action_release(e[0])
		_moving = true
	elif _moving:
		_moving = false
		for a in ["move_right", "move_left", "move_fwd", "move_back"]: Input.action_release(a)
	# run stays on until you let the stick come back
	if _run and ls.length() < 0.25:
		_run = false; _act("run", false)
	# look
	var look := Vector2(Gamepad.axis(JOY_AXIS_RIGHT_X), Gamepad.axis(JOY_AXIS_RIGHT_Y))
	var mag := look.length()
	if wheel.visible: wheel.aim(look)
	elif mag > DEAD and game.dlg == null and not Player.input_off:
		var k := pow((minf(mag, 1.0) - DEAD) / (1.0 - DEAD), 1.7) * LOOK_SPEED * Settings.look_sens * dt
		var v := look / mag * k
		var vy := v.y * (-1.0 if Settings.invert_y else 1.0)
		if p.in_truck: game.truck.look(v.x, vy)
		else: p.look(v.x, vy * 0.8)
		if not game.cap(): game._capture()
	# triggers: the mouse buttons (in the truck they're the pedals: see drive_axis)
	var rt := Gamepad.axis(JOY_AXIS_TRIGGER_RIGHT)
	var lt := Gamepad.axis(JOY_AXIS_TRIGGER_LEFT)
	if p.in_truck:
		_triggers_off()
	else:
		if not _rt and rt > TRIGGER_ON:
			_rt = true
			if p.tool == "saw" and not game.in_hub:
				# the saw: a pull on the cord while it's off, the throttle once it's running
				if game.saw.on: _saw_rt = true; _act("rev", true)
				else: game.saw.pull_start()
			else: _act("use", true); _mouse(MOUSE_BUTTON_LEFT, true)
		elif _rt and rt < TRIGGER_OFF:
			_rt = false
			if _saw_rt:
				_saw_rt = false
				if not _lt: _act("rev", false)
			elif p.tool != "saw" or game.in_hub: _act("use", false); _mouse(MOUSE_BUTTON_LEFT, false)
		if not _lt and lt > TRIGGER_ON: _lt = true; _act("rev", true); _mouse(MOUSE_BUTTON_RIGHT, true)
		elif _lt and lt < TRIGGER_OFF:
			_lt = false; _mouse(MOUSE_BUTTON_RIGHT, false)
			if not _saw_rt: _act("rev", false)
	# what's in your hands (RB goes back to the one before)
	if p.tool != _cur_tool:
		_prev_tool = _cur_tool; _cur_tool = p.tool
	# d-pad left/right held: keep turning the cut
	if _wheel_dir != 0:
		_wheel_t -= dt
		if _wheel_t <= 0.0:
			_wheel_t = WHEEL_REPEAT
			_wheel(MOUSE_BUTTON_WHEEL_UP if _wheel_dir > 0 else MOUSE_BUTTON_WHEEL_DOWN)
	# View held: the help card
	if _view_t >= 0.0:
		_view_t += dt
		if _view_t > 0.5 and not _view_help:
			_view_help = true; game.hud.help.visible = true

func _triggers_off() -> void:
	if _rt: _rt = false; _act("use", false); _mouse(MOUSE_BUTTON_LEFT, false)
	if _lt: _lt = false; _mouse(MOUSE_BUTTON_RIGHT, false)
	if _saw_rt or Input.is_action_pressed("rev"): _saw_rt = false; _act("rev", false)
	if wheel and wheel.visible: wheel.visible = false

# ---------------------------------------------------------------- what the hints say
func _hints_changed() -> void:
	if game and is_instance_valid(game) and game.hud: game.hud.pad_text(_pad_last)

## no jumping off the A button while it's pressing a menu button or moving a conversation on (and for
## a moment after, so the press that closes one doesn't hop you either)
func _jump_guard() -> void:
	if game == null or game.hud == null: return
	var busy: bool = game.dlg != null or _menu() != null or (wheel != null and wheel.visible)
	if busy: Player.no_jump_until = Time.get_ticks_msec() + 350

# ---------------------------------------------------------------- the tool wheel
## hold LB: the tools you've got round a ring; point the right stick (or the left) at one and let go
class ToolWheel extends CanvasLayer:
	var pad
	var items: Array = []
	var pick := -1
	var face: Control

	func _init() -> void:
		layer = 12
		visible = false
		face = Control.new(); face.set_anchors_preset(Control.PRESET_FULL_RECT); face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.draw.connect(_draw_face)
		add_child(face)

	func open_for(p) -> void:
		pad = p
		if not pad.can_switch(): return
		items = pad.tools()
		pick = -1
		for i in range(items.size()):
			if items[i][0] == pad.game.player.tool: pick = i
		visible = true
		Sfx.play("pick", 0.5, 1.4)
		face.queue_redraw()

	func close_pick() -> void:
		if not visible: return
		visible = false
		if pick >= 0 and pick < items.size() and pad.can_switch():
			var id: String = items[pick][0]
			if id == "muffs" or id != pad.game.player.tool: pad.equip_slot(id)

	func aim(v: Vector2) -> void:
		var lv := Vector2(Gamepad.axis(JOY_AXIS_LEFT_X), Gamepad.axis(JOY_AXIS_LEFT_Y))
		if v.length() < 0.5 and lv.length() > 0.6: v = lv
		if v.length() < 0.5 or items.is_empty(): return
		# item 0 at the top, going round clockwise
		var a := fposmod(atan2(v.x, -v.y), TAU)
		var n := items.size()
		var i := int(round(a / (TAU / n))) % n
		if i != pick:
			pick = i
			Sfx.play("pick", 0.25, 1.8)
			face.queue_redraw()

	func _draw_face() -> void:
		if items.is_empty(): return
		var s := face.get_viewport_rect().size
		var c := s / 2.0
		var R := minf(s.x, s.y) * 0.26
		var n := items.size()
		var font := ThemeDB.fallback_font
		face.draw_circle(c, R * 1.32, Color(0.05, 0.05, 0.045, 0.62))
		face.draw_arc(c, R * 1.32, 0, TAU, 64, Color(1, 1, 1, 0.12), 2.0, true)
		for i in range(n):
			var a := -PI / 2 + TAU * i / n
			var at := c + Vector2(cos(a), sin(a)) * R
			var on := i == pick
			var r := R * (0.34 if on else 0.28)
			face.draw_circle(at, r, Color(0.94, 0.63, 0.19, 0.95) if on else Color(0.16, 0.16, 0.14, 0.92))
			face.draw_arc(at, r, 0, TAU, 40, Color(1, 1, 1, 0.35 if on else 0.15), 2.0, true)
			var txt: String = items[i][1]
			if items[i][0] == "muffs": txt += " (on)" if pad.game.muffs else " (off)"
			var fs := int(R * (0.13 if on else 0.115))
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if w > r * 1.8:
				fs = int(fs * r * 1.8 / w)
				w = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			face.draw_string(font, at + Vector2(-w / 2.0, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#1b1b1b") if on else Color("#f3ead8"))
		var hint := "Right stick to pick · let go of LB"
		var hs := int(R * 0.09)
		var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x
		face.draw_string(font, c + Vector2(-hw / 2.0, hs * 0.35), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color(1, 1, 1, 0.6))
