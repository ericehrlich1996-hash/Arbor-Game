## Controller support (Xbox layout: ROG Ally, Steam Deck, an Xbox pad on a PC).
## Most buttons are plain input actions (see bind_actions). The rest stand in for the mouse the same
## way the touch controls do: the triggers are the mouse buttons, the right stick is mouse look, and
## the d-pad's up and down are the wheel. In menus the d-pad or left stick moves between buttons,
## A presses one, and B backs out.
##
##   Left stick   walk (click it to run) · in the truck: steer
##   Right stick  look
##   RT           left mouse: grab, cut, cast, reel, swing, throw the climbing line · truck: gas
##   LT           right mouse: rev the saw, set down / throw in the bed, jig · truck: reverse
##   A jump (truck: brake)   X talk / pick up / use / drive   B kick (hold: flip past a limb)
##   Y throw (hold in the tree: let the lowering rope run) · truck: unstick
##   LB / RB      previous / next tool
##   D-pad ↑ ↓    the mouse wheel: angle the cut, set the hook
##   D-pad ←      ear muffs        D-pad →  drag
##   R3 crouch    View: start the saw (truck: camera), hold it for help    Menu: pause
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
		jump = [JOY_BUTTON_A], interact = [JOY_BUTTON_X], kick = [JOY_BUTTON_B],
		throw = [JOY_BUTTON_Y], unstick = [JOY_BUTTON_Y],
		crouch = [JOY_BUTTON_RIGHT_STICK], drag = [JOY_BUTTON_DPAD_RIGHT], tool3 = [JOY_BUTTON_DPAD_LEFT],
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
	if n is Control and (n as Control).is_visible_in_tree() and (n as Control).focus_mode == Control.FOCUS_ALL and (n is BaseButton or n is Range or n is LineEdit):
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
	for c in n.get_children(): _let_focus(c)

var _focus_t := 0.0

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
	if ev is InputEventJoypadMotion and absf(ev.axis_value) < 0.4: return
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
		JOY_BUTTON_LEFT_SHOULDER: if down: _cycle(-1)
		JOY_BUTTON_RIGHT_SHOULDER: if down: _cycle(1)
		JOY_BUTTON_DPAD_UP:
			_wheel_dir = 1 if down else (0 if _wheel_dir == 1 else _wheel_dir)
			if down: _wheel(MOUSE_BUTTON_WHEEL_UP); _wheel_t = 0.35
		JOY_BUTTON_DPAD_DOWN:
			_wheel_dir = -1 if down else (0 if _wheel_dir == -1 else _wheel_dir)
			if down: _wheel(MOUSE_BUTTON_WHEEL_DOWN); _wheel_t = 0.35
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

## LB / RB: the tools you own, in hotbar order
func _cycle(dir: int) -> void:
	var p = game.player
	if p == null or p.in_truck or game.dlg != null: return
	if game.in_hub: return
	var order := [["hands", "tool1"], ["saw", "tool2"]]
	if Rigging.owned("wedges"): order.append(["wedge", "tool4"])
	if Rigging.owned("rope"): order.append(["rope", "tool5"])
	if Fishing.owned(): order.append(["rod", "tool6"])
	if Rigging.owned("climb"): order.append(["climb", "tool7"])
	if game.climb and game.climb.climbing:
		order = order.filter(func(o): return o[0] in ["hands", "saw", "rope", "climb"])
	var i := 0
	for k in range(order.size()):
		if order[k][0] == p.tool: i = k
	var n: Array = order[(i + dir + order.size()) % order.size()]
	var e := InputEventAction.new(); e.action = n[1]; e.pressed = true
	game._unhandled_input(e)

# ---------------------------------------------------------------- sticks and triggers
func _process(dt: float) -> void:
	_clock += dt
	if Input.get_connected_joypads().is_empty() and fake.is_empty(): return
	var m := _menu()
	if m != null:
		if _pad_last: _menu_focus(m)
		_triggers_off()
		return
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
	if mag > DEAD and game.dlg == null and not Player.input_off:
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
		if not _rt and rt > TRIGGER_ON: _rt = true; _act("use", true); _mouse(MOUSE_BUTTON_LEFT, true)
		elif _rt and rt < TRIGGER_OFF: _rt = false; _act("use", false); _mouse(MOUSE_BUTTON_LEFT, false)
		if not _lt and lt > TRIGGER_ON: _lt = true; _act("rev", true); _mouse(MOUSE_BUTTON_RIGHT, true)
		elif _lt and lt < TRIGGER_OFF: _lt = false; _act("rev", false); _mouse(MOUSE_BUTTON_RIGHT, false)
	# d-pad up/down held: keep turning the cut
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
	if _lt: _lt = false; _act("rev", false); _mouse(MOUSE_BUTTON_RIGHT, false)

# ---------------------------------------------------------------- what the hints say
func _hints_changed() -> void:
	if game and is_instance_valid(game) and game.hud: game.hud.pad_text(_pad_last)
