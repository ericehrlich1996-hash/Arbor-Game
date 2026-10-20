# The Meshy truck (body + the interior from truck_interior.py) into the game's truck:
#  - the four wheels are taken off the body (the game spins and steers its own), one kept as the wheel mesh
#  - the body is lightened for phones and painted by region (until it's textured): paint, chrome bumpers and
#    grille, dark chassis / wheel wells / bed floor, lamps; the paint is recoloured in the game per truck
#  - everything is turned and scaled into the game truck's frame: +z forward, +y up, the driver at +x, the ground
#    at y = 0, the axles at z = 1.62 and -1.58 (Models.FRONT_AXLE / REAR_AXLE)
# Run: blender -b --factory-startup -P truck_game.py -- <truck_fixed.blend> <out.glb> [preview_dir]
import bpy, bmesh, sys, os, math
import numpy as np
from mathutils import Vector, Matrix

A = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = A[0], A[1]
PREV = A[2] if len(A) > 2 else ""
BODY_TRIS = 60000
WHEEL_TRIS = 2400
bpy.ops.wm.open_mainfile(filepath=SRC)
body = bpy.data.objects["truck_body"]; inter = bpy.data.objects["truck_interior"]
for o in list(bpy.data.objects):
	if o not in (body, inter): bpy.data.objects.remove(o)

# the wheels, in Meshy's frame (front toward -x, the game's left side at -y)
FRONT = (-0.636, -0.172); REAR = (0.491, -0.167)
TIRE_R = 0.164; WHEEL_Y0 = 0.205; HUB_Y = 0.282
K = 3.2 / (REAR[0] - FRONT[0])                    # the game's wheelbase
GROUND = -0.334
def to_game(v): return Vector((-v.y * K, (v.z - GROUND) * K, -v.x * K + (1.62 - FRONT[0] * -K)))
print("SCALE", K, "front axle z", to_game(Vector((FRONT[0], 0, 0))).z, "rear", to_game(Vector((REAR[0], 0, 0))).z)

def sel_faces(ob, mask):
	me = ob.data
	s = np.zeros(len(me.polygons), dtype=bool); s[mask] = True
	bpy.context.view_layer.objects.active = ob
	for o in bpy.data.objects: o.select_set(o is ob)
	bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_mode(type="FACE"); bpy.ops.mesh.select_all(action="DESELECT")
	bpy.ops.object.mode_set(mode="OBJECT")
	me.polygons.foreach_set("select", s)
def centers(ob):
	me = ob.data; n = len(me.polygons)
	c = np.zeros(n * 3); me.polygons.foreach_get("center", c); return c.reshape(-1, 3)

# ---------------------------------------------------------------- weld (Meshy splits its surface), then take the wheels off
bpy.context.view_layer.objects.active = body
for o in bpy.data.objects: o.select_set(o is body)
bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT"); bpy.ops.mesh.remove_doubles(threshold=0.0003)
bpy.ops.object.mode_set(mode="OBJECT")
c = centers(body)
wheel_any = np.zeros(len(c), dtype=bool); wheel_keep = np.zeros(len(c), dtype=bool)
for wx, wz in (FRONT, REAR):
	r = np.hypot(c[:, 0] - wx, c[:, 2] - wz)
	m = (r < TIRE_R) & (np.abs(c[:, 1]) > WHEEL_Y0)
	wheel_any |= m
	if wx == FRONT[0]: wheel_keep |= m & (c[:, 1] > 0)     # the front wheel on the game's right: its hub faces -x
print("WHEEL faces", int(wheel_any.sum()), "kept", int(wheel_keep.sum()))
sel_faces(body, wheel_keep)
bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.duplicate(); bpy.ops.mesh.separate(type="SELECTED"); bpy.ops.object.mode_set(mode="OBJECT")
wheel = [o for o in bpy.data.objects if o not in (body, inter)][0]; wheel.name = "wheel"
sel_faces(body, wheel_any)
bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.delete(type="FACE"); bpy.ops.object.mode_set(mode="OBJECT")

def decimate(ob, tris):
	bpy.context.view_layer.objects.active = ob
	for o in bpy.data.objects: o.select_set(o is ob)
	m = ob.modifiers.new("d", "DECIMATE"); m.ratio = min(1.0, tris / max(1, len(ob.data.polygons)))
	bpy.ops.object.modifier_apply(modifier="d")
	ob.data.calc_loop_triangles(); print("DECIMATED", ob.name, len(ob.data.loop_triangles))
decimate(body, BODY_TRIS)
decimate(wheel, WHEEL_TRIS)

# ---------------------------------------------------------------- paint the body by region
def mk(name, col):
	m = bpy.data.materials.new(name); m.use_nodes = True
	m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*col, 1)
	return m
PAINT, CHROME, DARK, LAMP = 0, 1, 2, 3
body.data.materials.clear()
for nm, col in (("paint", (0.42, 0.05, 0.03)), ("chrome", (0.6, 0.62, 0.64)), ("dark", (0.03, 0.03, 0.03)), ("lamp", (0.9, 0.88, 0.8))):
	body.data.materials.append(mk(nm, col))
me = body.data
c = centers(body)
nr = np.zeros(len(c) * 3); me.polygons.foreach_get("normal", nr); nr = nr.reshape(-1, 3)
x, y, z = c[:, 0], c[:, 1], c[:, 2]; ay = np.abs(y)
cls = np.full(len(c), PAINT)
# the chassis and everything low under the body, the wheel wells, the bed floor
cls[z < -0.215] = DARK
for wx, wz in (FRONT, REAR):
	r = np.hypot(x - wx, z - wz)
	# only the inside of the wells (facing down or in), not the body panel round the arch
	cls[(r < 0.205) & (ay > 0.17) & (ay < 0.33) & ((np.abs(nr[:, 1]) < 0.55) | (ay < 0.29))] = DARK
cls[(x > 0.17) & (x < 0.93) & (ay < 0.31) & (z < -0.05) & (nr[:, 2] > 0.6)] = DARK
# chrome: the front and rear bumpers, the grille, the side mirrors
cls[(x < -0.885) & (z < -0.105) & (z > -0.24)] = CHROME
cls[(x > 0.9) & (z < -0.12) & (z > -0.25)] = CHROME
cls[(x < -0.9) & (z >= -0.105) & (z < 0.09) & (ay < 0.24)] = CHROME
cls[(ay > 0.355) & (z > 0.06) & (z < 0.26) & (x > -0.42) & (x < -0.2)] = CHROME
# lamps: headlights either side of the grille, the tail lights in the rear corners
head = (x < -0.905) & (z > -0.06) & (z < 0.07) & (ay >= 0.215) & (ay < 0.32)
tail = (x > 0.915) & (z > -0.1) & (z < 0.1) & (ay > 0.255)
cls[head | tail] = LAMP
me.polygons.foreach_set("material_index", cls.astype(np.int32))
# vertex colours (the game's paint and chrome shaders read them): paint gets recoloured in the game
col_of = {PAINT: (0.545, 0.165, 0.12), CHROME: (0.78, 0.8, 0.82), DARK: (0.16, 0.15, 0.14), LAMP: (0.95, 0.94, 0.86)}
ca = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
loop_cols = np.zeros((len(me.loops), 4)); loop_cols[:, 3] = 1.0
li = np.zeros(len(me.polygons), dtype=np.int64); me.polygons.foreach_get("loop_start", li)
lt = np.zeros(len(me.polygons), dtype=np.int64); me.polygons.foreach_get("loop_total", lt)
for i in range(len(me.polygons)):
	cc = col_of[int(cls[i])]
	if tail[i]: cc = (0.76, 0.16, 0.12)
	loop_cols[li[i]:li[i] + lt[i], :3] = cc
ca.data.foreach_set("color", loop_cols.ravel())
me.color_attributes.active_color = ca
print("CLASSES", {k: int((cls == v).sum()) for k, v in (("paint", PAINT), ("chrome", CHROME), ("dark", DARK), ("lamp", LAMP))})

# the wheel: black tyre outside the rim radius, a silver steel wheel and hub inside
wme = wheel.data
wc = centers(wheel)
rr = np.hypot(wc[:, 0] - FRONT[0], wc[:, 2] - FRONT[1])
wme.materials.clear(); wme.materials.append(mk("tire", (0.03, 0.03, 0.03))); wme.materials.append(mk("rim", (0.6, 0.62, 0.64)))
wcls = np.where(rr < TIRE_R * 0.5, 1, 0).astype(np.int32)
wme.polygons.foreach_set("material_index", wcls)
wca = wme.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
wcols = np.zeros((len(wme.loops), 4)); wcols[:, 3] = 1.0
li = np.zeros(len(wme.polygons), dtype=np.int64); wme.polygons.foreach_get("loop_start", li)
lt = np.zeros(len(wme.polygons), dtype=np.int64); wme.polygons.foreach_get("loop_total", lt)
for i in range(len(wme.polygons)):
	wcols[li[i]:li[i] + lt[i], :3] = (0.5, 0.52, 0.54) if wcls[i] == 1 else (0.09, 0.09, 0.09)
wca.data.foreach_set("color", wcols.ravel())

# ---------------------------------------------------------------- into the game's frame
G = Matrix(((0, -K, 0, 0), (0, 0, K, -GROUND * K), (-K, 0, 0, 1.62 + FRONT[0] * K), (0, 0, 0, 1)))
# (the glTF exporter turns Blender's z-up into the game's y-up: so build the game frame, then express it z-up)
YUP = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))        # game (x, y, z) -> Blender (x, -z, y)
for ob in (body, inter):
	ob.data.transform(YUP @ G); ob.matrix_world = Matrix()
# the wheel about its own hub: centred, hub face toward the game's -x
WG = Matrix(((0, -K, 0, HUB_Y * K), (0, 0, K, -FRONT[1] * K), (-K, 0, 0, FRONT[0] * K), (0, 0, 0, 1)))
wheel.data.transform(YUP @ WG); wheel.matrix_world = Matrix()
for ob in (body, inter, wheel):
	for p in ob.data.polygons: p.use_smooth = True
bpy.ops.object.select_all(action="DESELECT")
for o in (body, inter, wheel): o.select_set(True)
body.name = "body"; inter.name = "interior"
opts = dict(filepath=OUT, export_format="GLB", use_selection=True, export_image_format="AUTO")
props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
if "export_vertex_color" in props: opts["export_vertex_color"] = "ACTIVE"          # (Blender 4.2+)
elif "export_colors" in props: opts["export_colors"] = True
bpy.ops.export_scene.gltf(**opts)
print("EXPORTED", OUT, os.path.getsize(OUT) // 1024, "KB")

if PREV:
	sc = bpy.context.scene; sc.render.engine = "CYCLES"; sc.cycles.samples = 24; sc.cycles.use_denoising = True
	sc.view_settings.view_transform = "Standard"
	for ob in (body, wheel):
		for m in ob.data.materials:
			b = m.node_tree.nodes["Principled BSDF"]
			at = m.node_tree.nodes.new("ShaderNodeVertexColor"); at.layer_name = "Col"
			m.node_tree.links.new(at.outputs[0], b.inputs["Base Color"])
	# put a wheel at each corner, for the look of it
	for wx, wz in ((0.86 * 0 + 0.80, 1.62), (-0.80, 1.62), (0.80, -1.58), (-0.80, -1.58)):
		d = wheel.copy(); d.data = wheel.data; bpy.context.collection.objects.link(d)
		d.matrix_world = Matrix.Translation(Vector((wx, -wz, TIRE_R * K))) @ (Matrix.Rotation(math.pi, 4, "Z") if wx > 0 else Matrix())
	w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True; w.node_tree.nodes["Background"].inputs[0].default_value = (0.7, 0.75, 0.8, 1)
	bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(-30))); bpy.context.object.data.energy = 3.5
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); bpy.context.collection.objects.link(cam); sc.camera = cam; cam.data.lens = 40
	sc.render.resolution_x, sc.render.resolution_y = 900, 520
	for nm, pos in (("front34", (5.5, -7.5, 2.6)), ("rear34", (-5.5, 7.5, 2.8)), ("side", (-9.0, 0.0, 1.6))):
		cam.location = pos; cam.rotation_euler = (Vector((0, 0, 1.0)) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
		sc.render.filepath = os.path.join(PREV, "game_%s.png" % nm); bpy.ops.render.render(write_still=True)
	print("PREVIEWS", PREV)
