# A Meshy fish into the game: decimate the sculpt to a phone budget, bake its texture onto the light mesh,
# and lay it out like every fish in the game: 1 m nose to tail, nose at +x 0.48, back up, centred on its body.
# Run: blender -b --factory-startup -P meshy_fish.py -- <meshy.glb> <out.glb> <nose axis: -y|+y|-x|+x> [tris] [tex] [preview_dir]
import bpy, sys, math, os, time
T0 = time.time()
def log(*x): print("[%5.1fs]" % (time.time() - T0), *x, flush=True)
from mathutils import Vector, Matrix
a = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, NOSE = a[0], a[1], a[2]
TRIS = int(a[3]) if len(a) > 3 else 6000
TEX = int(a[4]) if len(a) > 4 else 1024
PREV = a[5] if len(a) > 5 else ""
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
hi = [o for o in bpy.data.objects if o.type == "MESH"][0]
# turn it so the nose points along +x (Blender), back up (+z); glTF's +x is Godot's +x
rot = {"-y": Matrix.Rotation(math.pi / 2, 4, "Z"), "+y": Matrix.Rotation(-math.pi / 2, 4, "Z"), "+x": Matrix(), "-x": Matrix.Rotation(math.pi, 4, "Z")}[NOSE]
hi.data.transform(rot @ hi.matrix_world); hi.matrix_world = Matrix()
xs = [v.co.x for v in hi.data.vertices]; zs = [v.co.z for v in hi.data.vertices]
L = max(xs) - min(xs); s = 1.0 / L
hi.data.transform(Matrix.Diagonal((s, s, s, 1)))
xs = [v.co.x for v in hi.data.vertices]
# centre the body's mid-line (between its back and belly, measured through the middle third) on y=0
cx = (max(xs) + min(xs)) / 2
mid = [v.co.z for v in hi.data.vertices if abs(v.co.x - cx) < 0.15]
hi.data.transform(Matrix.Translation((0.48 - max(xs), 0, -(max(mid) + min(mid)) / 2)))
hi.data.update()
log("laid out")
# already light (Meshy remeshed it): keep its own mesh and texture, just shrink the texture
if len(hi.data.polygons) <= TRIS * 1.3:
	lo = hi; lo.name = "fish"
	for p in lo.data.polygons: p.use_smooth = True
	for im in bpy.data.images:
		if im.size[0] > TEX: im.scale(TEX, TEX)
	hi = None
	log("kept its own mesh", len(lo.data.polygons))
else:
	# the light copy, unwrapped afresh (decimating smears the sculpt's UVs), then the sculpt's colours baked on
	lo = hi.copy(); lo.data = hi.data.copy(); lo.name = "fish"; bpy.context.collection.objects.link(lo)
	bpy.context.view_layer.objects.active = lo; bpy.ops.object.select_all(action="DESELECT"); lo.select_set(True)
	# Meshy splits the surface along its texture seams: weld it, or the seams tear open as it's reduced
	bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
	bpy.ops.mesh.remove_doubles(threshold=0.0004); bpy.ops.object.mode_set(mode="OBJECT")
	log("welded", len(lo.data.vertices))
	m = lo.modifiers.new("d", "DECIMATE"); m.ratio = TRIS / len(lo.data.polygons)
	bpy.ops.object.modifier_apply(modifier="d")
	log("decimated", len(lo.data.polygons))
	for p in lo.data.polygons: p.use_smooth = True
	while lo.data.uv_layers: lo.data.uv_layers.remove(lo.data.uv_layers[0])
	lo.data.uv_layers.new(name="UVMap")
	bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
	bpy.ops.uv.smart_project(angle_limit=1.2, island_margin=0.006)
	bpy.ops.uv.pack_islands(margin=0.006, rotate=True)
	bpy.ops.object.mode_set(mode="OBJECT")
	img = bpy.data.images.new("fish_tex", TEX, TEX)
	mat = bpy.data.materials.new("fish"); mat.use_nodes = True; nt = mat.node_tree
	tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = img; nt.nodes.active = tn
	bs = nt.nodes["Principled BSDF"]; nt.links.new(tn.outputs[0], bs.inputs["Base Color"]); bs.inputs["Roughness"].default_value = 0.45
	lo.data.materials.clear(); lo.data.materials.append(mat)
	sc = bpy.context.scene; sc.render.engine = "CYCLES"; sc.cycles.samples = 4
	sc.render.bake.use_pass_direct = False; sc.render.bake.use_pass_indirect = False; sc.render.bake.use_pass_color = True
	sc.render.bake.use_selected_to_active = True; sc.render.bake.cage_extrusion = 0.02; sc.render.bake.max_ray_distance = 0.08
	sc.render.bake.margin = 8
	bpy.ops.object.select_all(action="DESELECT"); hi.select_set(True); lo.select_set(True); bpy.context.view_layer.objects.active = lo
	log("baking"); bpy.ops.object.bake(type="DIFFUSE"); log("baked")
	img.filepath_raw = os.path.splitext(OUT)[0] + "_tex.png"; img.file_format = "PNG"; img.save()
sc = bpy.context.scene; sc.render.engine = "CYCLES"
lo.data.calc_loop_triangles(); print("TRIS", len(lo.data.loop_triangles), "LEN", L)
if hi: bpy.data.objects.remove(hi)
bpy.ops.object.select_all(action="DESELECT"); lo.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_image_format="JPEG", export_jpeg_quality=88)
print("EXPORTED", OUT)
if PREV:
	sc.cycles.samples = 24; sc.cycles.use_denoising = True; sc.view_settings.view_transform = "Standard"
	sc.render.resolution_x, sc.render.resolution_y = 900, 450
	w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True; w.node_tree.nodes["Background"].inputs[0].default_value = (0.7, 0.72, 0.72, 1)
	bpy.ops.object.light_add(type="SUN", rotation=(math.radians(40), 0, math.radians(30))); bpy.context.object.data.energy = 3
	cam = bpy.data.objects.new("c", bpy.data.cameras.new("c")); bpy.context.collection.objects.link(cam); sc.camera = cam
	cam.data.type = "ORTHO"; cam.data.ortho_scale = 1.15
	for nm, loc in (("side", (-0.02, -5, 0)), ("34", (2.5, -3.5, 1.6)), ("other", (-0.02, 5, 0))):
		cam.location = loc; cam.rotation_euler = (Vector((-0.02, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
		sc.render.filepath = f"{PREV}/lo_{nm}.png"; bpy.ops.render.render(write_still=True)
