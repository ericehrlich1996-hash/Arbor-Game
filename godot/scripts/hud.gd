## All on-screen UI, built in code: crosshair, job list, prompt, hotbar, toasts, dialogue,
## help, driving panel, title screen and the payday summary.
class_name Hud
extends CanvasLayer

signal start_pressed
signal next_job_pressed

var root: Control
var crosshair: ColorRect
var obj_panel: PanelContainer
var obj_title: Label
var obj_list: RichTextLabel
var money: Label
var tool_state: Label
var prompt: RichTextLabel
var hotbar: HBoxContainer
var slots := {}
var toast_lbl: Label
var toast_until := 0.0
var dlg_panel: PanelContainer
var dlg_name: Label
var dlg_text: Label
var dlg_hint: Label
var help: PanelContainer
var drive: PanelContainer
var drive_lbl: RichTextLabel
var title: Control
var summary: Control
var sum_rows: VBoxContainer
var sum_notes: Label
var tilt: Label
var fade: ColorRect
var intro_card: Label
var _t := 0.0

const INK := Color("#f3ead8")
const DIM := Color("#a89f8c")
const ACCENT := Color("#f0a030")
const GREEN := Color("#7bc96f")

func _panel(alpha := 0.78) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.08, alpha)
	sb.set_corner_radius_all(10)
	sb.border_color = Color(1, 1, 1, 0.08); sb.set_border_width_all(1)
	sb.content_margin_left = 16; sb.content_margin_right = 16; sb.content_margin_top = 12; sb.content_margin_bottom = 12
	return sb

func _label(text: String, size := 16, col := INK) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _ready() -> void:
	layer = 5
	root = Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	crosshair = ColorRect.new(); crosshair.color = Color(1, 1, 1, 0.9); crosshair.size = Vector2(6, 6)
	crosshair.set_anchors_preset(Control.PRESET_CENTER); crosshair.position = Vector2(-3, -3)
	root.add_child(crosshair)
	# job list
	obj_panel = PanelContainer.new(); obj_panel.add_theme_stylebox_override("panel", _panel())
	obj_panel.position = Vector2(14, 14); obj_panel.custom_minimum_size = Vector2(340, 0)
	var vb := VBoxContainer.new(); obj_panel.add_child(vb)
	obj_title = _label("Job 1 · Earl's dead ash", 19, Color("#ffe1b8")); vb.add_child(obj_title)
	obj_list = RichTextLabel.new(); obj_list.bbcode_enabled = true; obj_list.fit_content = true; obj_list.scroll_active = false
	obj_list.custom_minimum_size = Vector2(320, 0); obj_list.add_theme_font_size_override("normal_font_size", 15)
	obj_list.add_theme_color_override("default_color", INK)
	vb.add_child(obj_list)
	root.add_child(obj_panel)
	# money + tool state (top right)
	var tr := VBoxContainer.new(); tr.set_anchors_preset(Control.PRESET_TOP_RIGHT); tr.position = Vector2(-220, 12); tr.custom_minimum_size = Vector2(205, 0)
	tr.alignment = BoxContainer.ALIGNMENT_END
	money = _label("$0", 30, Color("#bff2a8")); money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7)); money.add_theme_constant_override("outline_size", 6)
	tool_state = _label("", 14, DIM); tool_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(money); tr.add_child(tool_state)
	root.add_child(tr)
	# interaction prompt
	prompt = RichTextLabel.new(); prompt.bbcode_enabled = true; prompt.fit_content = true; prompt.scroll_active = false
	prompt.set_anchors_preset(Control.PRESET_CENTER); prompt.custom_minimum_size = Vector2(640, 0); prompt.position = Vector2(-320, 34)
	prompt.add_theme_font_size_override("normal_font_size", 18); prompt.add_theme_font_size_override("bold_font_size", 18)
	prompt.add_theme_color_override("default_color", INK)
	prompt.add_theme_constant_override("outline_size", 6); prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(prompt)
	# hotbar
	hotbar = HBoxContainer.new(); hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM); hotbar.position = Vector2(-190, -62)
	hotbar.add_theme_constant_override("separation", 10)
	for k in [["hands", "1  Hands"], ["saw", "2  Chainsaw"], ["muffs", "3  Ear muffs"]]:
		var p := PanelContainer.new(); var sb := _panel(0.8); sb.content_margin_top = 8; sb.content_margin_bottom = 8
		p.add_theme_stylebox_override("panel", sb)
		var l := _label(k[1], 15); p.add_child(l)
		hotbar.add_child(p); slots[k[0]] = p
	root.add_child(hotbar)
	# bar tilt readout (bottom right)
	tilt = _label("", 15, DIM); tilt.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT); tilt.position = Vector2(-150, -50)
	root.add_child(tilt)
	# toast
	toast_lbl = _label("", 17); toast_lbl.set_anchors_preset(Control.PRESET_CENTER); toast_lbl.position = Vector2(-300, -170)
	toast_lbl.custom_minimum_size = Vector2(600, 0); toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.add_theme_constant_override("outline_size", 6); toast_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	toast_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(toast_lbl)
	# dialogue
	dlg_panel = PanelContainer.new(); dlg_panel.add_theme_stylebox_override("panel", _panel(0.88))
	dlg_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM); dlg_panel.custom_minimum_size = Vector2(720, 130); dlg_panel.position = Vector2(-360, -250)
	var dv := VBoxContainer.new(); dlg_panel.add_child(dv)
	dlg_name = _label("Earl", 18, ACCENT); dv.add_child(dlg_name)
	dlg_text = _label("", 18); dlg_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; dlg_text.custom_minimum_size = Vector2(680, 60); dv.add_child(dlg_text)
	dlg_hint = _label("", 13, DIM); dlg_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; dv.add_child(dlg_hint)
	dlg_panel.visible = false
	root.add_child(dlg_panel)
	# driving panel
	drive = PanelContainer.new(); drive.add_theme_stylebox_override("panel", _panel(0.8))
	drive.set_anchors_preset(Control.PRESET_CENTER_BOTTOM); drive.position = Vector2(-330, -70); drive.custom_minimum_size = Vector2(660, 0)
	drive_lbl = RichTextLabel.new(); drive_lbl.bbcode_enabled = true; drive_lbl.fit_content = true; drive_lbl.scroll_active = false
	drive_lbl.add_theme_font_size_override("normal_font_size", 15); drive_lbl.add_theme_font_size_override("bold_font_size", 15)
	drive.add_child(drive_lbl); drive.visible = false
	root.add_child(drive)
	# help
	help = PanelContainer.new(); help.add_theme_stylebox_override("panel", _panel(0.9))
	help.set_anchors_preset(Control.PRESET_TOP_RIGHT); help.position = Vector2(-410, 90); help.custom_minimum_size = Vector2(390, 0)
	var hl := RichTextLabel.new(); hl.bbcode_enabled = true; hl.fit_content = true; hl.scroll_active = false; hl.custom_minimum_size = Vector2(360, 0)
	hl.add_theme_font_size_override("normal_font_size", 14); hl.add_theme_font_size_override("bold_font_size", 14)
	hl.text = "[b]WASD[/b] walk · [b]Shift[/b] run · [b]Space[/b] jump · [b]C[/b] crouch\n[b]Mouse[/b] look (click to capture)\n[b]E[/b] talk / pick up / use / drive / hitch\n[b]1 2 3[/b] hands · chainsaw · ear muffs\n[b]R[/b] pull-start the saw · [b]Right mouse[/b] rev and cut\n[b]Wheel[/b] roll the saw (turns the cut)\n[b]Q[/b] drop one · [b]G[/b] throw · [b]T[/b] drag · [b]F[/b] kick\n[b]F3[/b] graphics detail (high / low) · [b]H[/b] this help"
	help.add_child(hl); help.visible = false
	root.add_child(help)
	# fade + intro card
	fade = ColorRect.new(); fade.color = Color(0, 0, 0, 0); fade.set_anchors_preset(Control.PRESET_FULL_RECT); fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	intro_card = _label("", 44, Color("#ffe1b8")); intro_card.set_anchors_preset(Control.PRESET_CENTER); intro_card.position = Vector2(-400, -160)
	intro_card.custom_minimum_size = Vector2(800, 0); intro_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_card.add_theme_constant_override("outline_size", 10); intro_card.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	intro_card.modulate.a = 0
	root.add_child(intro_card)
	_build_title()
	_build_summary()
	_ignore_mouse(root)
	title.mouse_filter = Control.MOUSE_FILTER_STOP

## only buttons take the mouse; everything else lets clicks and motion through to the game
func _ignore_mouse(n: Node) -> void:
	if n is Control and not (n is Button): n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children(): _ignore_mouse(c)
	set_play_visible(false)

func _build_title() -> void:
	title = ColorRect.new(); (title as ColorRect).color = Color(0.05, 0.06, 0.05, 0.28)
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	var c := CenterContainer.new(); c.set_anchors_preset(Control.PRESET_FULL_RECT); title.add_child(c)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 14); c.add_child(v)
	var t := _label("ARBOR SIMULATOR", 64, Color("#ffe1b8")); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 12); t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	v.add_child(t)
	var st := _label("A chainsaw, a chipper and a square-body. Start small.", 20, INK); st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(st)
	var b := Button.new(); b.text = "  Start the job  "; b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size = Vector2(280, 56)
	var bs := StyleBoxFlat.new(); bs.bg_color = Color("#d9861c"); bs.set_corner_radius_all(10)
	var bh := bs.duplicate(); bh.bg_color = Color("#f0a030")
	b.add_theme_stylebox_override("normal", bs); b.add_theme_stylebox_override("hover", bh); b.add_theme_stylebox_override("pressed", bh)
	b.add_theme_color_override("font_color", Color("#1b1b1b")); b.add_theme_color_override("font_hover_color", Color("#1b1b1b"))
	b.pressed.connect(func(): start_pressed.emit())
	var bc := CenterContainer.new(); bc.add_child(b); v.add_child(bc)
	var hint := _label("Mouse to look · WASD to walk · E to use · H for all controls", 15, DIM); hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(hint)
	root.add_child(title)

func _build_summary() -> void:
	summary = ColorRect.new(); (summary as ColorRect).color = Color(0, 0, 0, 0.6)
	summary.set_anchors_preset(Control.PRESET_FULL_RECT)
	var c := CenterContainer.new(); c.set_anchors_preset(Control.PRESET_FULL_RECT); summary.add_child(c)
	var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", _panel(0.95)); p.custom_minimum_size = Vector2(520, 0); c.add_child(p)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); p.add_child(v)
	v.add_child(_label("Job done · Earl's dead ash", 26, Color("#ffe1b8")))
	sum_rows = VBoxContainer.new(); v.add_child(sum_rows)
	sum_notes = _label("", 15, DIM); sum_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; sum_notes.custom_minimum_size = Vector2(480, 0); v.add_child(sum_notes)
	var b := Button.new(); b.text = "Next property"; b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(func(): next_job_pressed.emit())
	v.add_child(b)
	summary.visible = false
	root.add_child(summary)

func show_summary(rows: Array, total: int, notes: Array, bank: int) -> void:
	for c in sum_rows.get_children(): c.queue_free()
	for r in rows:
		var h := HBoxContainer.new()
		var a := _label(r[0], 17); a.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(a)
		var amt: int = r[1]
		h.add_child(_label(("−$%d" % -amt) if amt < 0 else ("+$%d" % amt), 17, Color("#ff8a7a") if amt < 0 else GREEN))
		sum_rows.add_child(h)
	var ht := HBoxContainer.new()
	var ta := _label("Total", 20, Color("#ffe1b8")); ta.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ht.add_child(ta)
	ht.add_child(_label("$%d" % total, 20, Color("#ffe1b8")))
	sum_rows.add_child(ht)
	sum_notes.text = "\n".join(notes) + "\n\nBank: $%d" % bank
	summary.visible = true

func set_play_visible(on: bool) -> void:
	for n in [crosshair, obj_panel, hotbar, prompt, tilt]:
		n.visible = on

func set_objectives(lines: Array) -> void:
	var s := ""
	for l in lines:
		if l[0]: s += "[color=#7bc96f]■[/color] [color=#8a8476][s]%s[/s][/color]\n" % l[1]
		else: s += "[color=#a89f8c]□[/color] %s\n" % l[1]
	obj_list.text = s.strip_edges()

func set_tool(t: String, muffs: bool) -> void:
	for k in slots:
		var sb: StyleBoxFlat = slots[k].get_theme_stylebox("panel")
		var on: bool = (k == t) or (k == "muffs" and muffs)
		sb.border_color = ACCENT if on else Color(1, 1, 1, 0.08)
		sb.set_border_width_all(2 if on else 1)

func shout(msg: String) -> void:
	toast(msg, 2.5)
	toast_lbl.add_theme_font_size_override("font_size", 40)
	get_tree().create_timer(2.5).timeout.connect(func(): toast_lbl.add_theme_font_size_override("font_size", 17))

func toast(msg: String, secs := 3.2) -> void:
	toast_lbl.text = msg
	toast_until = _t + secs
	toast_lbl.modulate.a = 1

func show_dialog(who: String, text: String, hint: String) -> void:
	dlg_panel.visible = true
	dlg_name.text = who; dlg_text.text = text; dlg_hint.text = hint

func hide_dialog() -> void:
	dlg_panel.visible = false

var _last_prompt := "-"
func set_prompt(t: String) -> void:
	if t == _last_prompt: return
	_last_prompt = t
	prompt.text = ("[center]" + t + "[/center]") if t != "" else ""

func _process(dt: float) -> void:
	_t += dt
	if toast_lbl.text != "" and _t > toast_until:
		toast_lbl.modulate.a = maxf(0, toast_lbl.modulate.a - dt * 2)
		if toast_lbl.modulate.a <= 0: toast_lbl.text = ""
