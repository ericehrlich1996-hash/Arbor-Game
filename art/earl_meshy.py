# Earl from Meshy: stands the textured model on the ground, skins it to the rig scripts/earl.gd drives
# (same bone names and joints as art/earl.py), keeps the old walking stick, and trims the textures for phones.
# Run: blender -b --factory-startup -P earl_meshy.py -- <meshy.glb> <old earl.glb (for the cane)> <out.glb> [preview_dir]
import bpy, sys, math, os
from mathutils import Vector
A = sys.argv[sys.argv.index("--") + 1:]
SRC, OLD, OUT = A[0], A[1], A[2]
PREV = A[3] if len(A) > 3 else ""
TEX = 2048            # colour map; the normal map goes to half that
bpy.ops.wm.read_factory_settings(use_empty=True)
def G(x, y, z): return Vector((x, -z, y))          # game (y up, +z front) -> Blender
def gam(v): return Vector((v.x, v.z, -v.y))

# ---------------------------------------------------------------- the stick from the old model
bpy.ops.import_scene.gltf(filepath=OLD)
cane = bpy.data.objects.get("cane")
for o in list(bpy.data.objects):
	if o is not cane: bpy.data.objects.remove(o)
cane.parent = None
# ---------------------------------------------------------------- the new body
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=SRC)
body = [o for o in bpy.data.objects if o not in before and o.type == "MESH"][0]
body.data.transform(body.matrix_world); body.matrix_world = body.matrix_world.Identity(4)
zmin = min(v.co.z for v in body.data.vertices)
for v in body.data.vertices: v.co.z -= zmin              # feet on the ground
body.name = "earl"; body.data.name = "earl"
for p in body.data.polygons: p.use_smooth = True
# textures: no metal/roughness map (a flat, cloth-like roughness instead), colour 2048, normal 1024
mat = body.data.materials[0]; nt = mat.node_tree
bs = [n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"][0]
for n in list(nt.nodes):
	if n.type == "TEX_IMAGE" and "metallic" in n.image.name: nt.nodes.remove(n)
	elif n.type == "SEPARATE_COLOR": nt.nodes.remove(n)
bs.inputs["Metallic"].default_value = 0.0; bs.inputs["Roughness"].default_value = 0.85
for im in bpy.data.images:
	t = TEX // 2 if "normal" in im.name else TEX
	if im.size[0] > t: im.scale(t, t)

# ---------------------------------------------------------------- the rig (joints as scripts/earl.gd)
BONES = [("hips", None, (0, 0.92, 0), (0, 0.97, 0)), ("torso", "hips", (0, 0.92, 0), (0, 1.5, 0)), ("head", "torso", (0, 1.5, 0), (0, 1.8, 0))]
for s, sx in (("l", 1), ("r", -1)):
	BONES += [("upper_" + s, "torso", (sx * 0.25, 1.42, 0), (sx * 0.25, 1.12, 0)), ("fore_" + s, "upper_" + s, (sx * 0.25, 1.12, 0), (sx * 0.25, 0.82, 0)),
		("leg_" + s, "hips", (sx * 0.1, 0.92, 0), (sx * 0.1, 0.02, 0))]
arm_data = bpy.data.armatures.new("rig"); rig = bpy.data.objects.new("rig", arm_data); bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig; bpy.ops.object.mode_set(mode="EDIT")
for name, parent, h0, t0 in BONES:
	eb = arm_data.edit_bones.new(name); eb.head = G(*h0); eb.tail = G(*t0); eb.roll = 0.0
	if parent: eb.parent = arm_data.edit_bones[parent]
bpy.ops.object.mode_set(mode="OBJECT")
# the limbs in this model sit a touch differently from the joints: the weights follow the real limbs
LIMB = {}
for s, sx in (("l", 1), ("r", -1)):
	LIMB["upper_" + s] = (Vector((sx * 0.23, 1.40, 0.0)), Vector((sx * 0.27, 1.11, 0.0)))
	LIMB["fore_" + s] = (Vector((sx * 0.27, 1.11, 0.0)), Vector((sx * 0.29, 0.78, 0.0)))
	LIMB["leg_" + s] = (Vector((sx * 0.1, 0.9, 0.0)), Vector((sx * 0.1, 0.02, 0.0)))
LIMB["torso"] = (Vector((0, 0.92, 0)), Vector((0, 1.48, 0)))
LIMB["head"] = (Vector((0, 1.5, 0)), Vector((0, 1.85, 0)))
def seg_d(p, a, b):
	ab = b - a; t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared)); return (p - (a + ab * t)).length
def ramp(x, a, b): return max(0.0, min(1.0, (x - a) / (b - a)))
def weights(g):
	"""nearest bones, but a limb only pulls on what's that limb: the arms on what's out past the side of the
	body (wider at the belt, where the pouch and buckle reach out), the legs on what's below the seat"""
	w = {}
	for n, (a, b) in LIMB.items():
		x = 1.0 / (seg_d(g, a, b) + 0.012) ** 3
		if n.startswith(("upper", "fore")):
			sx = 1 if n.endswith("_l") else -1
			lo = 0.205 if g.y < 1.02 else 0.15
			x *= ramp(g.x * sx, lo, lo + 0.055) * ramp(1.53 - g.y, 0.0, 0.06)   # nothing above the shoulders: hat, ears
		if n.startswith("leg"):
			sx = 1 if n.endswith("_l") else -1
			x *= ramp(0.9 - g.y, 0.0, 0.12) * ramp(g.x * sx, -0.02, 0.04)
		if n == "head": x *= ramp(g.y, 1.47, 1.55)
		w[n] = x
	top = sorted(w.items(), key=lambda kv: -kv[1])[:3]
	tot = sum(x for _, x in top) or 1.0
	return [(n, x / tot) for n, x in top if x > 0]
groups = {b[0]: body.vertex_groups.new(name=b[0]) for b in BONES}
for v in body.data.vertices:
	for n, x in weights(gam(v.co)): groups[n].add([v.index], x, "REPLACE")
body.parent = rig
md = body.modifiers.new("rig", "ARMATURE"); md.object = rig
body.data.calc_loop_triangles(); print("EARL TRIS", len(body.data.loop_triangles))

bpy.ops.object.select_all(action="DESELECT")
for o in (body, rig, cane): o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_skins=True, use_selection=True,
	export_animations=False, export_texcoords=True, export_normals=True, export_materials="EXPORT",
	export_image_format="JPEG", export_jpeg_quality=90)
print("EXPORTED", OUT)

# ---------------------------------------------------------------- previews: standing, waving, mid-stride
if PREV:
	cane.hide_render = True
	sc = bpy.context.scene; sc.render.engine = "CYCLES"; sc.cycles.samples = 24; sc.cycles.use_denoising = True
	sc.view_settings.view_transform = "Standard"
	w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True; w.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.62, 0.66, 1)
	bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(-35))); bpy.context.object.data.energy = 3.0
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); bpy.context.collection.objects.link(cam); sc.camera = cam; cam.data.lens = 85
	def pose(**r):
		bpy.context.view_layer.objects.active = rig; bpy.ops.object.mode_set(mode="POSE")
		for pb in rig.pose.bones: pb.rotation_mode = "XYZ"; pb.rotation_euler = r.get(pb.name, (0, 0, 0))
		bpy.ops.object.mode_set(mode="OBJECT")
	def snap(name, tgt, pos, wh):
		sc.render.resolution_x, sc.render.resolution_y = wh
		cam.location = G(*pos); cam.rotation_euler = (G(*tgt) - G(*pos)).to_track_quat("-Z", "Y").to_euler()
		sc.render.filepath = os.path.join(PREV, "e-%s.png" % name); bpy.ops.render.render(write_still=True)
	pose()
	snap("front", (0, 0.95, 0), (0, 1.1, 6.0), (360, 640))
	snap("34", (0, 0.95, 0), (math.sin(0.7) * 6, 1.1, math.cos(0.7) * 6), (360, 640))
	pose(upper_l=(0, 0, 2.4), fore_l=(0, 0, 0.6), upper_r=(-0.7, 0, -0.1), fore_r=(-1.2, 0, 0))
	snap("wave", (0, 1.1, 0), (0.6, 1.2, 5.0), (360, 640))
	pose(leg_l=(0.45, 0, 0), leg_r=(-0.45, 0, 0), upper_l=(-0.4, 0, 0), upper_r=(0.4, 0, 0), torso=(0.08, 0, 0), head=(-0.1, 0.3, 0))
	snap("walk", (0, 0.95, 0), (6.0, 1.1, 0.3), (360, 640))
	snap("walk34", (0, 0.95, 0), (4.0, 1.4, 4.0), (360, 640))
	print("PREVIEWS", PREV)
