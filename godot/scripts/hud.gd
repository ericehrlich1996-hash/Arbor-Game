## All on-screen UI, built in code: crosshair, job list, prompt, hotbar, toasts, dialogue,
## help, driving panel, title screen and the payday summary.
class_name Hud
extends CanvasLayer

signal start_pressed
signal next_job_pressed
signal job_chosen(idx: int)
signal computer_closed
signal upgrade_chosen(id: String)

var root: Control
var crosshair: ColorRect
var obj_panel: PanelContainer
var obj_title: Label
var sum_title: Label
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
var help_lbl: RichTextLabel
var title_hint: Label
var drive: PanelContainer
var drive_lbl: RichTextLabel
var title: Control
var summary: Control
var tl_panel: PanelContainer
var tl_rect: TextureRect
var tl_lbl: Label
var tl_frames: Array = []
var tl_stamps: Array = []
var tl_i := 0
var tl_t := 0.0
var sum_rows: VBoxContainer
var sum_notes: Label
var tilt: Label
var dial_box: PanelContainer
var dial: AngleDial
var dial_lbl: Label
var carry_box: PanelContainer
var carry_lbl: Label
var carry_fill: ColorRect
var carry_wt: Label
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

func set_dial(show: bool, continuing: bool, deg: float, too_far: bool) -> void:
	dial_box.visible = show and not carry_box.visible
	if not dial_box.visible: return
	var d := int(round(deg))
	dial.deg = deg
	dial.col = Color(1, 1, 1, 0.5) if too_far else (GREEN if continuing else ACCENT)
	dial.queue_redraw()
	dial_lbl.text = "Level cut" if d == 0 else ("%d° down" % d if d > 0 else "%d° up" % -d)
	dial_lbl.add_theme_color_override("font_color", dial.col)

func set_carry(n: int, what: String, kg: float, max_kg: float, to_lb: Callable) -> void:
	carry_box.visible = n > 0
	if n == 0: return
	var fr := clampf(kg / max_kg, 0.0, 1.0)
	var col := GREEN if fr < 0.7 else (Color("#f0a030") if fr < 0.92 else Color("#e5533d"))
	carry_lbl.text = "Carrying %d %s" % [n, what]
	carry_lbl.add_theme_color_override("font_color", col)
	carry_fill.color = col
	carry_fill.size = Vector2(200.0 * fr, 10)
	carry_wt.text = "%s of %s" % [to_lb.call(kg), to_lb.call(max_kg)] + ("  ·  full" if fr >= 0.92 else "")

## a tiny side view of a trunk with the cut line across it
class AngleDial extends Control:
	var deg := 0.0
	var col := Color("#f0a030")
	func _draw() -> void:
		var c := size / 2.0
		var tw := 34.0; var th := size.y - 6.0
		draw_rect(Rect2(c.x - tw / 2, c.y - th / 2, tw, th), Color(0.55, 0.5, 0.42))
		draw_rect(Rect2(c.x - tw / 2, c.y - th / 2, 5, th), Color(0.42, 0.38, 0.32))
		var a := deg_to_rad(deg)
		# the cut comes in from the left (your side), sloping down for a positive angle
		var d := Vector2(cos(a), sin(a))
		draw_line(c - d * 52.0, c + d * 52.0, col, 3.0, true)
		draw_arc(c - d * 52.0, 4.0, 0, TAU, 12, col, 2.0, true)
		# a level reference, faint
		draw_line(c + Vector2(-52, 0), c + Vector2(52, 0), Color(1, 1, 1, 0.18), 1.0)

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
	crew_lbl = _label("", 14, Color("#ffe1b8")); crew_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	crew_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7)); crew_lbl.add_theme_constant_override("outline_size", 5)
	tr.add_child(crew_lbl)
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
	for k in [["hands", "1  Hands"], ["saw", "2  Chainsaw"], ["muffs", "3  Ear muffs"], ["wedge", "4  Wedges"], ["rope", "5  Rope"], ["rod", "6  Fishing rod"], ["climb", "7  Climbing kit"]]:
		var p := PanelContainer.new(); var sb := _panel(0.8); sb.content_margin_top = 8; sb.content_margin_bottom = 8
		p.add_theme_stylebox_override("panel", sb)
		var l := _label(k[1], 15); p.add_child(l)
		hotbar.add_child(p); slots[k[0]] = p
	root.add_child(hotbar)
	slots.wedge.visible = false; slots.rope.visible = false; slots.rod.visible = false; slots.climb.visible = false
	_center_hotbar.call_deferred()
	# bar tilt readout (bottom right)
	tilt = _label("", 16, DIM); tilt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tilt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tilt.offset_left = -300; tilt.offset_right = 300; tilt.offset_top = -100; tilt.offset_bottom = -76
	tilt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8)); tilt.add_theme_constant_override("outline_size", 5)
	root.add_child(tilt)
	# the cut-angle dial: a little trunk with the cut drawn across it at the angle it'll go in
	dial_box = PanelContainer.new(); var db := _panel(0.8); db.content_margin_top = 8; db.content_margin_bottom = 8
	dial_box.add_theme_stylebox_override("panel", db)
	dial_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	dial_box.offset_left = -170; dial_box.offset_right = -16; dial_box.offset_top = -150; dial_box.offset_bottom = -16
	var dvb := VBoxContainer.new(); dvb.alignment = BoxContainer.ALIGNMENT_CENTER; dial_box.add_child(dvb)
	dial = AngleDial.new(); dial.custom_minimum_size = Vector2(122, 80); dvb.add_child(dial)
	dial_lbl = _label("", 15); dial_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; dvb.add_child(dial_lbl)
	dial_box.visible = false
	dial_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dial_box)
	# what's on your shoulder: how many pieces, and how close to the limit (green, orange, red)
	carry_box = PanelContainer.new(); var cb := _panel(0.8); cb.content_margin_top = 8; cb.content_margin_bottom = 8
	carry_box.add_theme_stylebox_override("panel", cb)
	carry_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	carry_box.offset_left = -250; carry_box.offset_right = -16; carry_box.offset_top = -112; carry_box.offset_bottom = -16
	var cv := VBoxContainer.new(); cv.add_theme_constant_override("separation", 5); carry_box.add_child(cv)
	carry_lbl = _label("", 15); cv.add_child(carry_lbl)
	var track := ColorRect.new(); track.color = Color(1, 1, 1, 0.12); track.custom_minimum_size = Vector2(200, 10)
	cv.add_child(track)
	carry_fill = ColorRect.new(); carry_fill.color = GREEN; carry_fill.size = Vector2(0, 10)
	track.add_child(carry_fill)
	carry_wt = _label("", 13, DIM); cv.add_child(carry_wt)
	carry_box.visible = false
	carry_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(carry_box)
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
	hl.text = "[b]WASD[/b] walk · [b]Shift[/b] run · [b]Space[/b] jump · [b]C[/b] crouch\n[b]Mouse[/b] look (click to capture)\n[b]E[/b] talk / pick up / use / drive / hitch\n[b]1 2 3[/b] hands · chainsaw · ear muffs · [b]4 5[/b] wedges · pull rope (once you've bought them) · [b]6[/b] fishing rod\n[b]Fishing[/b] hold left mouse to cast · wheel down to set the hook when the float goes under · right mouse jigs · hold left to reel · aim at the fish to ease the tension\n[b]R[/b] pull-start the saw · [b]Right mouse[/b] rev and cut\n[b]Wheel[/b] angle the cut (aim at a trunk or log: the line shows where it goes)\n[b]Left click[/b] grab · [b]Right click[/b] set down / throw in the truck · [b]T[/b] drag · [b]F[/b] kick\n[b]U[/b] unstick the truck (lifts it onto its wheels in a clear spot)\n[b]F3[/b] graphics detail (high / low) · [b]H[/b] this help"
	help.add_child(hl); help.visible = false
	help_lbl = hl
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
	_build_computer()
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
	var b := Button.new(); b.text = "  Start  "; b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size = Vector2(280, 56)
	var bs := StyleBoxFlat.new(); bs.bg_color = Color("#d9861c"); bs.set_corner_radius_all(10)
	var bh := bs.duplicate(); bh.bg_color = Color("#f0a030")
	b.add_theme_stylebox_override("normal", bs); b.add_theme_stylebox_override("hover", bh); b.add_theme_stylebox_override("pressed", bh)
	b.add_theme_color_override("font_color", Color("#1b1b1b")); b.add_theme_color_override("font_hover_color", Color("#1b1b1b"))
	b.pressed.connect(func(): start_pressed.emit())
	var bc := CenterContainer.new(); bc.add_child(b); v.add_child(bc)
	var hint := _label("Mouse to look · WASD to walk · E to use · H for all controls", 15, DIM); hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(hint)
	title_hint = hint
	root.add_child(title)

# ---------------------------------------------------------------- the old computer (job select)
var pc_screen: Control
var pc_list: VBoxContainer
var pc_head: Label
var pc_tab := "jobs"
var pc_data := {}
var pc_msg := ""
var pc_tabs: HBoxContainer
const CRT := Color("#7dff8a")
const CRT_DIM := Color("#3f8a48")

## text on the CRT is sized to the monitor (which is sized to your screen), not fixed pixels
var pc_k := 1.0
var pc_text_w := 460.0
var pc_scroll: ScrollContainer

func _crt_label(t: String, size := 18, col := CRT) -> Label:
	var l := _label(t, maxi(9, int(size * pc_k)), col)
	l.add_theme_font_override("font", _mono())
	return l

func _mono() -> Font:
	var f := SystemFont.new(); f.font_names = PackedStringArray(["DejaVu Sans Mono", "Courier New", "Consolas", "monospace"])
	return f

const CRT_SHADER := """
shader_type canvas_item;
// the glass: scanlines, a little flicker, and dark corners
void fragment() {
	vec2 uv = UV;
	float scan = 0.5 + 0.5 * sin(SCREEN_UV.y * 900.0);
	float vig = smoothstep(0.85, 0.35, length(uv - 0.5));
	float flick = 0.97 + 0.03 * sin(TIME * 60.0);
	COLOR = vec4(0.0, 0.03, 0.0, (0.16 * scan + 0.5 * (1.0 - vig)) * flick);
}
"""

func _build_computer() -> void:
	pc_screen = ColorRect.new(); (pc_screen as ColorRect).color = Color(0, 0, 0, 0.55)
	pc_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	var c := CenterContainer.new(); c.set_anchors_preset(Control.PRESET_FULL_RECT); pc_screen.add_child(c)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 0); c.add_child(col)
	# a beige monitor round a 4:3 green-screen CRT, about half the height of your screen
	var bezel := PanelContainer.new()
	var bs := StyleBoxFlat.new(); bs.bg_color = Color("#c9bfa4"); bs.set_corner_radius_all(22)
	bs.border_color = Color("#9e9478"); bs.set_border_width_all(3)
	bezel.add_theme_stylebox_override("panel", bs); col.add_child(bezel)
	pc_bezel_style = bs
	var bv := VBoxContainer.new(); bv.add_theme_constant_override("separation", 6); bezel.add_child(bv)
	var scr := PanelContainer.new()
	var ss := StyleBoxFlat.new(); ss.bg_color = Color("#06140a"); ss.set_corner_radius_all(16)
	ss.border_color = Color("#1a2a1e"); ss.set_border_width_all(6)
	scr.add_theme_stylebox_override("panel", ss); bv.add_child(scr)
	pc_glass = scr; pc_glass_style = ss
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 6); scr.add_child(v)
	pc_head = _crt_label("", 18); v.add_child(pc_head)
	pc_tabs = HBoxContainer.new(); pc_tabs.add_theme_constant_override("separation", 12); v.add_child(pc_tabs)
	pc_rule = _crt_label("-----------------------------------------------", 16, CRT_DIM); v.add_child(pc_rule)
	# the list scrolls inside the glass (wheel, drag, or the pad's cursor walking down it)
	pc_scroll = ScrollContainer.new(); pc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pc_scroll.follow_focus = true; pc_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grab := StyleBoxFlat.new(); grab.bg_color = CRT_DIM; grab.set_corner_radius_all(3)
	var track := StyleBoxFlat.new(); track.bg_color = Color(0.1, 0.25, 0.12, 0.6); track.set_corner_radius_all(3)
	track.content_margin_left = 4; track.content_margin_right = 4
	var vb := pc_scroll.get_v_scroll_bar()
	vb.add_theme_stylebox_override("grabber", grab); vb.add_theme_stylebox_override("grabber_highlight", grab)
	vb.add_theme_stylebox_override("grabber_pressed", grab); vb.add_theme_stylebox_override("scroll", track)
	v.add_child(pc_scroll)
	pc_list = VBoxContainer.new(); pc_list.add_theme_constant_override("separation", 8)
	pc_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc_scroll.add_child(pc_list)
	pc_close = _crt_button("[ LOG OFF ]")
	pc_close.pressed.connect(func(): hide_computer(); computer_closed.emit())
	v.add_child(pc_close)
	# scanlines over the glass (they don't catch clicks)
	var lines := ColorRect.new(); lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new(); var sh := Shader.new(); sh.code = CRT_SHADER; sm.shader = sh
	lines.material = sm
	scr.add_child(lines)
	pc_lines = lines
	# the chin: a badge and a power light
	var chin := HBoxContainer.new(); bv.add_child(chin)
	var badge := _label("ARBORTEK 286", 12, Color("#6e6650")); badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chin.add_child(badge)
	var led := ColorRect.new(); led.color = Color("#59ff6a"); led.custom_minimum_size = Vector2(10, 6)
	led.size_flags_vertical = Control.SIZE_SHRINK_CENTER; chin.add_child(led)
	pc_chin = chin
	# and a neck down to the desk
	var neck := CenterContainer.new(); col.add_child(neck)
	var nk := Panel.new(); var ns := StyleBoxFlat.new(); ns.bg_color = Color("#b3a98e"); nk.add_theme_stylebox_override("panel", ns)
	neck.add_child(nk); pc_neck = nk
	pc_screen.visible = false
	root.add_child(pc_screen)
	_size_pc()
	get_viewport().size_changed.connect(_size_pc)

var pc_glass: PanelContainer
var pc_glass_style: StyleBoxFlat
var pc_bezel_style: StyleBoxFlat
var pc_rule: Label
var pc_close: Button
var pc_lines: ColorRect
var pc_chin: HBoxContainer
var pc_neck: Panel

## the monitor's size follows your screen: the glass is 4:3 and about half the screen's height
func _size_pc() -> void:
	var vs := get_viewport().get_visible_rect().size
	var gh := clampf(vs.y * 0.5, 300.0, vs.y - 120.0)
	var gw := minf(gh * 4.0 / 3.0, vs.x - 80.0)
	pc_k = gh / 380.0
	pc_glass.custom_minimum_size = Vector2(gw, gh)
	var m := 16.0 * pc_k
	pc_glass_style.content_margin_left = m; pc_glass_style.content_margin_right = m
	pc_glass_style.content_margin_top = m * 0.8; pc_glass_style.content_margin_bottom = m * 0.8
	var bm := 22.0 * pc_k
	pc_bezel_style.content_margin_left = bm; pc_bezel_style.content_margin_right = bm
	pc_bezel_style.content_margin_top = bm; pc_bezel_style.content_margin_bottom = bm * 0.5
	pc_text_w = gw - m * 2.0 - 18.0
	pc_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	pc_neck.custom_minimum_size = Vector2(gw * 0.22, 26.0 * pc_k)
	for l in [pc_head, pc_rule]: l.add_theme_font_size_override("font_size", int(15 * pc_k))
	pc_close.add_theme_font_size_override("font_size", int(15 * pc_k))
	if pc_screen.visible: _render_pc()

func _crt_button(t: String) -> Button:
	var b := Button.new(); b.text = t
	b.add_theme_font_override("font", _mono()); b.add_theme_font_size_override("font_size", int(15 * pc_k))
	var n := StyleBoxFlat.new(); n.bg_color = Color(0, 0, 0, 0); n.content_margin_left = 6; n.content_margin_right = 6
	var hv := StyleBoxFlat.new(); hv.bg_color = CRT; hv.content_margin_left = 6; hv.content_margin_right = 6
	b.add_theme_stylebox_override("normal", n); b.add_theme_stylebox_override("hover", hv); b.add_theme_stylebox_override("pressed", hv)
	# focus (the pad's cursor): a green box round it, so you can see where you are
	var fc := StyleBoxFlat.new(); fc.bg_color = Color(0, 0, 0, 0); fc.border_color = CRT; fc.set_border_width_all(2)
	fc.content_margin_left = 6; fc.content_margin_right = 6
	b.add_theme_stylebox_override("focus", fc); b.add_theme_stylebox_override("disabled", n)
	b.add_theme_color_override("font_color", CRT); b.add_theme_color_override("font_hover_color", Color("#06140a"))
	b.add_theme_color_override("font_pressed_color", Color("#06140a")); b.add_theme_color_override("font_disabled_color", CRT_DIM)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b

## jobs: [{title, text, pay, open}]; upgrades: [{id, title, text, cost, owned}]
func show_computer(jobs: Array, bank: int, jobs_done: int, upgrades: Array = [], msg := "") -> void:
	pc_data = {jobs = jobs, bank = bank, done = jobs_done, upgrades = upgrades}
	pc_msg = msg
	_render_pc()
	pc_screen.visible = true

func _render_pc() -> void:
	pc_head.text = "TREE-MAIL v1.2   BANK $%d   JOBS %d" % [pc_data.bank, pc_data.done]
	if pc_scroll: pc_scroll.set_deferred("scroll_vertical", 0)
	for ch in pc_tabs.get_children(): ch.queue_free()
	for tb in [["jobs", "JOBS"], ["upgrades", "UPGRADES"], ["trophies", "ACHIEVEMENTS"]]:
		var b := _crt_button(("[ %s ]" if pc_tab == tb[0] else "  %s  ") % tb[1])
		var id: String = tb[0]
		b.pressed.connect(func(): pc_tab = id; pc_msg = ""; _render_pc())
		pc_tabs.add_child(b)
	for ch in pc_list.get_children(): ch.queue_free()
	if pc_tab == "jobs":
		pc_list.add_child(_crt_label("> NEW WORK IN YOUR AREA:", 15))
		var jobs: Array = pc_data.jobs
		for i in range(jobs.size()):
			var j: Dictionary = jobs[i]
			var b := _crt_button(("  %d. %s   $%d" % [i + 1, j.title, j.pay]) if j.open else ("  %d. %s" % [i + 1, j.title]))
			b.disabled = not j.open
			b.pressed.connect(func(): hide_computer(); job_chosen.emit(i))
			pc_list.add_child(b)
			_pc_text("     " + j.text, j.open)
	elif pc_tab == "trophies":
		_render_trophies()
	else:
		pc_list.add_child(_crt_label("> FIX UP YOUR GEAR:", 15))
		var ups: Array = pc_data.upgrades
		for u: Dictionary in ups:
			var can: bool = not u.owned and int(pc_data.bank) >= int(u.cost)
			var label: String = ("  %s   %s" % [u.title, u.get("done", "OWNED")]) if u.owned else ("  %s   $%d" % [u.title, u.cost])
			if not u.owned and not can: label += "   (NEED $%d MORE)" % (int(u.cost) - int(pc_data.bank))
			var b := _crt_button(label)
			b.disabled = not can
			var id: String = u.id
			b.pressed.connect(func(): upgrade_chosen.emit(id))
			pc_list.add_child(b)
			_pc_text("     " + u.text, not u.owned)
	if pc_msg != "":
		pc_list.add_child(_crt_label("> " + pc_msg, 15))

## the achievement tracker: the overall count and a bar up top, then one category at a time (flip through
## with the arrows), each achievement a row: a star when you've got it, the title and what it takes, and on
## the right the day you got it or how far along you are. The secret ones stay secret until you find them.
var ach_cat := 0
const MONTHS := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

func _render_trophies() -> void:
	var n := Ach.count()
	var got: Dictionary = Career.load().get("ach", {})
	# --- the overview: count, percent and a block bar
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", int(14 * pc_k))
	top.add_child(_crt_label("%d / %d" % [n.x, n.y], 22))
	var bar := _crt_label("%s  %d%%" % [_crt_bar(n.x, n.y, 24), roundi(100.0 * n.x / maxf(1.0, n.y))], 14, CRT_DIM)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(bar)
	pc_list.add_child(top)
	# --- the category pager
	ach_cat = posmod(ach_cat, Ach.CATS.size())
	var cat: String = Ach.CATS[ach_cat]
	var ids := Ach.LIST.keys().filter(func(id): return Ach.LIST[id][0] == cat)
	var have := ids.filter(func(id): return got.has(id)).size()
	var pg := HBoxContainer.new(); pg.add_theme_constant_override("separation", int(6 * pc_k))
	var prev := _crt_button(" < "); prev.pressed.connect(func(): ach_cat -= 1; pc_msg = ""; _render_pc(); _focus_pager(0))
	var next := _crt_button(" > "); next.pressed.connect(func(): ach_cat += 1; pc_msg = ""; _render_pc(); _focus_pager(2))
	var mid := _crt_label(cat.to_upper(), 16)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL; mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cnt := _crt_label("%d/%d" % [have, ids.size()], 14, CRT if have == ids.size() else CRT_DIM)
	pg.add_child(prev); pg.add_child(mid); pg.add_child(cnt); pg.add_child(next)
	pg.set_meta("ach_pager", true)
	pc_list.add_child(pg)
	# --- the rows: earned ones first, then the rest in their order
	ids.sort_custom(func(a, b): return got.has(a) and not got.has(b))
	for id in ids:
		var e: Array = Ach.LIST[id]
		var on := got.has(id)
		var secret: bool = e[5] and not on
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", int(10 * pc_k))
		var mark := _crt_label("*" if on else ("?" if secret else "o"), 18, CRT if on else CRT_DIM)
		mark.custom_minimum_size = Vector2(18 * pc_k, 0); mark.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		row.add_child(mark)
		var txt := VBoxContainer.new(); txt.add_theme_constant_override("separation", 0); txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.add_child(_crt_label("SECRET" if secret else (e[1] as String).to_upper(), 14, CRT if on else CRT_DIM))
		var how := _crt_label("Keep playing to find this one." if secret else e[2], 11, CRT_DIM)
		how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		how.custom_minimum_size = Vector2(pc_text_w - 150 * pc_k, 0)
		txt.add_child(how)
		row.add_child(txt)
		var right := ""
		if on: right = _short_date(str(got[id]))
		elif e[3] != "" and not secret:
			var t := mini(Ach.tally(e[3]), int(e[4]))
			right = "%s %d/%d" % [_crt_bar(t, int(e[4]), 6), t, int(e[4])]
		var rl := _crt_label(right, 12, CRT if on else CRT_DIM)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; rl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		rl.custom_minimum_size = Vector2(96 * pc_k, 0)
		row.add_child(rl)
		row.add_child(Control.new())
		(row.get_child(row.get_child_count() - 1) as Control).custom_minimum_size = Vector2(8 * pc_k, 0)
		pc_list.add_child(row)

## [#####.....] for n of total, w blocks wide
func _crt_bar(n: int, total: int, w: int) -> String:
	var k := 0 if total <= 0 else clampi(roundi(float(n) / total * w), 0, w)
	if n > 0 and k == 0: k = 1
	return "[" + "#".repeat(k) + ".".repeat(w - k) + "]"

## 2026-10-31 -> OCT 31
func _short_date(d: String) -> String:
	var p := d.split("-")
	if p.size() != 3: return d
	return "%s %d" % [MONTHS[clampi(int(p[1]) - 1, 0, 11)], int(p[2])]

## after flipping a page, keep the pad's cursor on the arrow you pressed
func _focus_pager(i: int) -> void:
	await get_tree().process_frame
	for pg in pc_list.get_children():
		if pg.has_meta("ach_pager") and not pg.is_queued_for_deletion() and pg.get_child_count() > i:
			(pg.get_child(i) as Control).grab_focus(); return

func _pc_text(t: String, bright: bool) -> void:
	pc_list.add_child(_crt_indent(t, 12, CRT if bright else CRT_DIM))

## wrapped text set in from the left, every line of it (not just the first)
func _crt_indent(t: String, size: int, col: Color) -> Control:
	var mc := MarginContainer.new(); mc.add_theme_constant_override("margin_left", int(34 * pc_k))
	var d := _crt_label(t.strip_edges(), size, col)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; d.custom_minimum_size = Vector2(pc_text_w - 34 * pc_k, 0)
	mc.add_child(d)
	return mc

func hide_computer() -> void:
	pc_screen.visible = false

func _build_summary() -> void:
	summary = ColorRect.new(); (summary as ColorRect).color = Color(0, 0, 0, 0.6)
	summary.set_anchors_preset(Control.PRESET_FULL_RECT)
	var c := CenterContainer.new(); c.set_anchors_preset(Control.PRESET_FULL_RECT); summary.add_child(c)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 18); c.add_child(row)
	# the timelapse of the job, playing on a loop beside the pay slip
	tl_panel = PanelContainer.new(); tl_panel.add_theme_stylebox_override("panel", _panel(0.95)); row.add_child(tl_panel)
	var tv := VBoxContainer.new(); tv.add_theme_constant_override("separation", 6); tl_panel.add_child(tv)
	tv.add_child(_label("Timelapse", 18, Color("#ffe1b8")))
	tl_rect = TextureRect.new(); tl_rect.custom_minimum_size = Vector2(528, 297)
	tl_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tl_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tv.add_child(tl_rect)
	tl_lbl = _label("", 14, DIM); tv.add_child(tl_lbl)
	tl_panel.visible = false
	var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", _panel(0.95)); p.custom_minimum_size = Vector2(460, 0); row.add_child(p)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); p.add_child(v)
	sum_title = _label("Job done · Earl's dead ash", 26, Color("#ffe1b8")); v.add_child(sum_title)
	sum_rows = VBoxContainer.new(); v.add_child(sum_rows)
	sum_notes = _label("", 15, DIM); sum_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; sum_notes.custom_minimum_size = Vector2(420, 0); v.add_child(sum_notes)
	var b := Button.new(); b.text = "Head home"; b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(func(): next_job_pressed.emit())
	v.add_child(b)
	summary.visible = false
	root.add_child(summary)

func show_summary(rows: Array, total: int, notes: Array, bank: int, title := "") -> void:
	if title != "": sum_title.text = title
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

func play_timelapse(frames: Array, stamps: Array) -> void:
	tl_frames = []
	for img in frames: tl_frames.append(ImageTexture.create_from_image(img))
	tl_stamps = stamps
	tl_panel.visible = tl_frames.size() >= 3
	tl_i = 0; tl_t = 0.0
	if tl_panel.visible: tl_rect.texture = tl_frames[0]

func _step_timelapse(dt: float) -> void:
	if not summary.visible or tl_frames.size() < 3: return
	tl_t += dt
	# about ten seconds for the whole job, then hold on the finished yard for a moment and go round again
	var fps := clampf(tl_frames.size() / 10.0, 6.0, 24.0)
	var hold := 2.0 if tl_i == tl_frames.size() - 1 else 1.0 / fps
	if tl_t < hold: return
	tl_t = 0.0
	tl_i = (tl_i + 1) % tl_frames.size()
	tl_rect.texture = tl_frames[tl_i]
	var m: float = tl_stamps[tl_i]
	tl_lbl.text = "%d:%02d into the job" % [int(m), int(fmod(m * 60.0, 60.0))]

func set_play_visible(on: bool) -> void:
	for n in [crosshair, obj_panel, hotbar, prompt, tilt]:
		n.visible = on

var crew_lbl: Label
## who's on the crew, under the bank balance
func set_crew(text: String) -> void:
	if crew_lbl: crew_lbl.text = text

var obj_list_lines: Array = []          # the last objective lines (sent on to the crew)
func set_objectives(lines: Array) -> void:
	obj_list_lines = lines
	var s := ""
	for l in lines:
		if l[0]: s += "[color=#7bc96f]■[/color] [color=#8a8476][s]%s[/s][/color]\n" % l[1]
		else: s += "[color=#a89f8c]□[/color] %s\n" % l[1]
	obj_list.text = s.strip_edges()

## the wedges and rope only show on the hotbar once you've bought them
func set_owned(wedges: bool, rope: bool, rod := false, climb := false) -> void:
	if slots.has("wedge"): slots.wedge.visible = wedges
	if slots.has("rope"): slots.rope.visible = rope or climb
	if slots.has("rod"): slots.rod.visible = rod
	if slots.has("climb"): slots.climb.visible = climb
	_center_hotbar.call_deferred()

## keep the hotbar centred along the bottom, however many slots are showing
func _center_hotbar() -> void:
	hotbar.reset_size()
	var w := hotbar.get_combined_minimum_size().x
	hotbar.offset_left = -w / 2; hotbar.offset_right = w / 2
	hotbar.offset_top = -62; hotbar.offset_bottom = -62 + hotbar.get_combined_minimum_size().y

func set_tool(t: String, muffs: bool) -> void:
	for k in slots:
		var sb: StyleBoxFlat = slots[k].get_theme_stylebox("panel")
		var on: bool = (k == t) or (k == "muffs" and muffs)
		sb.border_color = ACCENT if on else Color(1, 1, 1, 0.08)
		sb.set_border_width_all(2 if on else 1)

func shout(msg: String) -> void:
	if capture != null: return
	toast(msg, 2.5)
	toast_lbl.add_theme_font_size_override("font_size", 40)
	get_tree().create_timer(2.5).timeout.connect(func(): toast_lbl.add_theme_font_size_override("font_size", 17))

## phones: the hints and the help card talk about thumbs, not the mouse and keys
var touch_text := false
func use_touch_text() -> void:
	touch_text = true
	if title_hint: title_hint.text = "Left thumb to move · swipe to look · USE is your left mouse button, a double-tap your right"
	if help_lbl: help_lbl.text = "[b]Left stick[/b] walk (push to the edge to run) · in the truck: drive and steer\n[b]Swipe[/b] anywhere on the right to look\n[b]USE[/b] = left mouse: grab, cut, cast, reel, swing the axe\n[b]Double-tap[/b] = right mouse (hold the second tap): rev the saw, set down / throw in the truck, jig the lure\n[b]E[/b] talk / pick up / drive / hitch · [b]JUMP[/b] jump (brake in the truck) · [b]KICK[/b] kick\n[b]Up / down arrows[/b] the mouse wheel: angle the cut · the down arrow sets the hook when the float goes under\n[b]Tap a slot[/b] on the bar to switch tools\n[b]START SAW[/b] pull-start (a few pulls) · [b]DRAG[/b] drag a log · [b]THROW[/b] / [b]DROP[/b] what you carry\n[b]CAMERA[/b] truck view · [b]UNSTICK[/b] free the truck"

var capture = null                       # while doing something for a crew member: their messages go to them
func toast(msg: String, secs := 3.2) -> void:
	if capture != null:
		capture.append([msg, secs]); return
	toast_lbl.text = pad_words(msg)
	toast_until = _t + secs
	toast_lbl.modulate.a = 1

func show_dialog(who: String, text: String, hint: String) -> void:
	dlg_panel.visible = true
	dlg_name.text = who; dlg_text.text = text; dlg_hint.text = hint

func hide_dialog() -> void:
	dlg_panel.visible = false

var _last_prompt := "-"
## a controller's in use: the hints name its buttons instead of the keys and mouse
var pad_on := false
var _key_help := ""
const PAD_NAMES := {
	"Hold right mouse": "Hold RT", "hold right mouse": "hold RT", "Saw: off · R to start": "Saw: off · RT to start", "Wheel to angle": "D-pad ← → to angle", "saw off (R)": "saw off (RT to start)",
	"[b]W/S[/b] drive": "[b]RT / LT[/b] drive", "[b]A/D[/b] steer": "[b]left stick[/b] steer", "[b]Space[/b] brake": "[b]A[/b] brake",
	"[b]E[/b]": "[b]X[/b]", "[b]Left click[/b]": "[b]RT[/b]", "[b]left click[/b]": "[b]RT[/b]", "[b]left mouse[/b]": "[b]RT[/b]",
	"[b]Left mouse[/b]": "[b]RT[/b]", "[b]Right click[/b]": "[b]LT[/b]", "[b]Right mouse[/b]": "[b]LT[/b]", "[b]right mouse[/b]": "[b]LT[/b]",
	"[b]Space[/b]": "[b]A[/b]", "[b]F[/b]": "[b]B[/b]", "[b]G[/b]": "[b]Y[/b]", "[b]T[/b]": "[b]D-pad ↓[/b]", "[b]R[/b]": "[b]RT[/b]",
	"[b]U[/b]": "[b]Y[/b]", "[b]V[/b]": "[b]View[/b]", "[b]W/S[/b]": "[b]left stick[/b]", "[b]A/D[/b]": "[b]left stick[/b]", "[b]W[/b]": "[b]left stick up[/b]",
	"[b]WASD[/b]": "[b]Left stick[/b]", "[b]Shift[/b]": "[b]L3[/b]", "[b]C[/b]": "[b]R3[/b]", "[b]Wheel[/b]": "[b]D-pad ← →[/b]", "[b]H[/b]": "[b]hold View[/b]",
	"[b]Q[/b]": "[b]LT[/b]", "[b]Esc[/b]": "[b]Menu[/b]",
	"[b]1[/b]": "[b]LB[/b]", "[b]2[/b]": "[b]LB[/b]", "[b]3[/b]": "[b]D-pad ↑[/b]", "[b]4[/b]": "[b]LB[/b]", "[b]5[/b]": "[b]LB[/b]", "[b]6[/b]": "[b]LB[/b]", "[b]7[/b]": "[b]LB[/b]",
	"hold G": "hold Y", "left mouse": "RT", "Left mouse": "RT", "right mouse": "LT", "Right mouse": "LT", "left click": "RT", "Left click": "RT",
	"press E": "press X", "Press E": "Press X", "Press R to pull-start the saw.": "Pull RT to start the saw.",
	"Shift + S": "L3 and pull back", "Shift+S": "L3 and pull back", "Rope tool (5)": "Rope (hold LB)", "ROPE TOOL (5)": "ROPE (HOLD LB)",
	"Click to look around. Walk with WASD.": "Right stick looks, left stick walks.", " with E.": " with X.",
}
const PAD_HELP := "[b]Left stick[/b] walk · click it ([b]L3[/b]) to run · [b]Right stick[/b] look\n[b]RT[/b] grab · cast · reel · swing · throw the climbing line\n[b]RT with the saw[/b] pull-start it (a few pulls), then it's the throttle: rev and cut\n[b]LT[/b] rev the saw · set down / throw in the truck bed · jig the lure\n[b]X[/b] talk / pick up / use / drive / hitch · [b]A[/b] jump · [b]B[/b] kick (hold: flip past a limb) · [b]Y[/b] throw (hold in the tree: lower the rope) · by the truck: unstick\n[b]Hold LB[/b] tool wheel: point the right stick, let go · [b]RB[/b] back to your last tool\n[b]D-pad ← →[/b] angle the cut · → sets the hook · [b]D-pad ↑[/b] ear muffs · [b]D-pad ↓[/b] drag · [b]R3[/b] crouch\n[b]View[/b] stop the saw (truck: camera) · hold it for this card · [b]Menu[/b] pause\n[b]In the truck[/b] RT gas · LT reverse · A brake · left stick steers · Y unstick · X get out\n[b]In menus[/b] d-pad moves · A picks · B backs out"

func pad_words(t: String) -> String:
	if not pad_on or t == "": return t
	for k in PAD_NAMES: t = t.replace(k, PAD_NAMES[k])
	return t

var _slot_txt := {}
func pad_text(on: bool) -> void:
	if touch_text: return
	pad_on = on
	for k in slots:
		var l: Label = slots[k].get_child(0) as Label
		if l == null: continue
		if not _slot_txt.has(k): _slot_txt[k] = l.text
		l.text = (str(_slot_txt[k]).substr(3) if on else str(_slot_txt[k]))
	if help_lbl:
		if _key_help == "": _key_help = help_lbl.text
		help_lbl.text = PAD_HELP if on else _key_help
	var lp := _last_prompt; _last_prompt = "~"; set_prompt(lp)
	if on and toast_lbl and toast_lbl.text != "": toast_lbl.text = pad_words(toast_lbl.text)
	# the tool wheel (hold LB) takes the hotbar's place on a pad
	if hotbar: hotbar.modulate.a = 0.0 if on else 1.0

func set_prompt(t: String) -> void:
	t = pad_words(t)
	if t == _last_prompt: return
	_last_prompt = t
	prompt.text = ("[center]" + t + "[/center]") if t != "" else ""

func _process(dt: float) -> void:
	_t += dt
	_step_timelapse(dt)
	if toast_lbl.text != "" and _t > toast_until:
		toast_lbl.modulate.a = maxf(0, toast_lbl.modulate.a - dt * 2)
		if toast_lbl.modulate.a <= 0: toast_lbl.text = ""
