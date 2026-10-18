## A timelapse of the job: a camera high over the tree and the woodpile snaps a small picture every couple of
## seconds while you work, and the end-of-job screen plays them back. From up there you're a little figure
## in a hard hat and hi-vis (only this camera sees him; your own view stays first-person).
class_name Timelapse
extends Node

const W := 480
const H := 270
const MAX_FRAMES := 150
const LAYER := 8                 # render layer 4: the worker figure

var game
var vp: SubViewport
var cam: Camera3D
var worker: Node3D
var worker_saw: Node3D
var frames: Array[Image] = []
var stamps: Array[float] = []    # minutes into the job for each frame
var interval := 2.0
var _t := 0.0
var _grab := false
var recording := false

func setup(g) -> void:
	game = g
	vp = SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)
	cam = Camera3D.new(); cam.fov = 48; cam.far = 260
	cam.cull_mask = 1 | LAYER        # no grass tufts from up here, but the worker yes
	vp.add_child(cam)
	_frame_the_job()
	_build_worker()
	g.player.cam.cull_mask &= ~LAYER

## high above the middle of the tree, the pile and the truck, tilted to take in all three
func _frame_the_job() -> void:
	var w: WorldGen = game.world
	var pts: Array[Vector3] = [Vector3(w.tree.x, 0, w.tree.z), Vector3(w.pile.x, 0, w.pile.z), Vector3(w.shed.x, 0, w.shed.z)]
	var c := Vector3.ZERO
	for p in pts: c += p
	c /= pts.size()
	# lean the middle toward the tree: that's where most of the work (and the fall) happens
	c = c.lerp(Vector3(w.tree.x, 0, w.tree.z), 0.4); c.y = w.H(c.x, c.z)
	var span := 0.0
	for p in pts: span = maxf(span, Vector2(p.x - c.x, p.z - c.z).length())
	span = maxf(span + float(w.tree.h) * 0.6, 14.0)
	var back := Vector3(0, 0, 1)           # from behind, over the woods' edge, so the house isn't in the way
	cam.global_position = c + back * span * 0.55 + Vector3(0, span * 1.45 + 6.0, 0)
	cam.look_at(c, Vector3.UP)

func _build_worker() -> void:
	worker = Node3D.new()
	var mb := MeshBuilder.new()
	var vest := Color("#d8f028"); var shirt := Color("#4a5a3a"); var jeans := Color("#3d5070"); var boot := Color("#3a2a1a")
	var skin := Color("#e0b090"); var hat := Color("#ff7a12")
	for sx: float in [-1.0, 1.0]:
		mb.tube(Vector3(sx * 0.1, 0.0, 0), Vector3(sx * 0.1, 0.85, 0), 0.085, 0.09, jeans, 8)
		mb.box(sx * 0.1, 0.04, 0.05, 0.13, 0.09, 0.26, boot)
	mb.sphere(0, 1.15, 0, 0.21, 0.34, 0.15, vest, 12, 7)
	mb.box(0, 1.15, 0.0, 0.43, 0.04, 0.31, Color("#c8c8c8"))           # reflective band
	for sx: float in [-1.0, 1.0]:
		mb.tube(Vector3(sx * 0.24, 1.38, 0), Vector3(sx * 0.3, 0.92, 0.12), 0.065, 0.055, shirt, 7)
		mb.sphere(sx * 0.3, 0.88, 0.14, 0.055, 0.055, 0.055, Color("#c9a46a"), 7, 5)
	mb.sphere(0, 1.6, 0, 0.12, 0.13, 0.12, skin, 10, 6)
	mb.sphere(0, 1.68, 0, 0.16, 0.08, 0.17, hat, 12, 5)                  # hard hat
	mb.box(0, 1.65, 0.12, 0.26, 0.02, 0.1, hat)
	mb.box(0, 1.62, -0.12, 0.06, 0.12, 0.04, Color("#d23a2a"))           # ear-muff strap
	var mi := mb.instance()
	mi.layers = LAYER
	mi.scale = Vector3.ONE * 1.8          # a touch bigger than life, so you can pick him out from up there
	worker.add_child(mi)
	var sm := MeshBuilder.new()
	sm.box(0, 0, 0, 0.14, 0.18, 0.3, Color("#e8661c")); sm.box(0, 0, -0.45, 0.02, 0.07, 0.62, Color("#8a8e92"))
	var smi := sm.instance(); smi.layers = LAYER
	worker_saw = Node3D.new(); worker_saw.add_child(smi)
	worker_saw.position = Vector3(0.38, 1.1, -0.25) * 1.8; worker_saw.scale = Vector3.ONE * 1.8
	worker.add_child(worker_saw)
	add_child(worker)

func step(dt: float) -> void:
	var p: Player = game.player
	var playing: bool = game.phase == "play"
	worker.visible = playing and not p.in_truck
	if worker.visible:
		worker.global_transform = Transform3D(Basis(Vector3.UP, p.yaw + PI), p.global_position)
		worker_saw.visible = p.tool == "saw"
	recording = playing and not game.objs.get("paid", false)
	if _grab:
		_grab = false
		var img := vp.get_texture().get_image()
		if img:
			img.convert(Image.FORMAT_RGB8)
			frames.append(img)
			stamps.append((game.clock - game.start_time) / 60.0)
			if frames.size() > MAX_FRAMES:
				# keep it bounded: drop every other frame and slow down
				var kf: Array[Image] = []; var ks: Array[float] = []
				for i in range(0, frames.size(), 2): kf.append(frames[i]); ks.append(stamps[i])
				frames = kf; stamps = ks
				interval *= 2.0
	if not recording: return
	_t += dt
	if _t >= interval:
		_t = 0.0
		_clear_air()
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_grab = true          # the picture's ready next frame

## the camera's high up: through fog or rain haze you'd see nothing but grey, so it gets today's sky and
## light with the fog taken out (you can still tell it was a foggy morning from the colour of it)
func _clear_air() -> void:
	var we := game.find_child("WorldEnvironment", true, false) as WorldEnvironment
	var src: Environment = we.environment if we else null
	if src == null:
		for c in game.get_children():
			if c is WorldEnvironment: src = (c as WorldEnvironment).environment; break
	if src == null: return
	var e := src.duplicate() as Environment
	e.fog_enabled = false
	e.volumetric_fog_enabled = false
	cam.environment = e
