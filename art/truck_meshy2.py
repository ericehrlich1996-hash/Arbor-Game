# The textured Crimson Workhorse truck from Meshy into the game, keeping the model as it is:
#  - the body keeps Meshy's mesh, UVs and textures (colour, metal/roughness, normal map); nothing is repainted
#  - the four wheels are lifted off at the tyre line (they sit clear of the fenders, so nothing else goes with them)
#    and exported one per corner, centred on their hubs, so the game can spin and steer them
#  - in the cab only three things change: the melted steering wheel and its column, the opaque windshield slab
#    (glass goes in its place, fitted to the opening) and the smeared gauge faces (a crisp cluster goes over
#    them, its two big dials left blank for the game's live needles)
#  - a white smear on the back of the cab is painted out of the colour texture
#  - turned and scaled into the game truck's frame (+z forward, +y up, ground at y = 0, axles at z = 1.62 / -1.58)
#
# Meshy's frame: 1.9 units long, front toward -x, up +z, the driver on the -y side.
# Run: blender -b --factory-startup -P truck_meshy2.py -- <meshy_textured.glb> <out.glb> [preview_dir]
import bpy, bmesh, sys, os, math, json
import numpy as np
from mathutils import Vector, Matrix

A = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = A[0], A[1]
PREV = A[2] if len(A) > 2 else ""
WORK = os.path.dirname(os.path.abspath(OUT))
bpy.ops.wm.read_factory_settings(use_empty=True)
coll = bpy.context.collection
bpy.ops.import_scene.gltf(filepath=SRC)
body = [o for o in bpy.data.objects if o.type == "MESH"][0]
body.name = "body"
body.data.transform(body.matrix_world); body.matrix_world = Matrix()
me = body.data
MESHY_MAT = me.materials[0]

# ---------------------------------------------------------------- measurements (Meshy units)
FRONT_X, REAR_X, HUB_Z = -0.6387, 0.4898, -0.1975
HUB_Y = 0.2835                         # the middle of the tyre, either side
GROUND = -0.3345
K = 3.2 / (REAR_X - FRONT_X)          # Meshy units to metres: the game's 3.2 m wheelbase
TIRE_R = 0.134                         # to the ground
STEER_C = Vector((-0.247, -0.123, 0.119))    # (where Meshy put it: the cut goes round this)
STEER_NEW = Vector((-0.244, -0.123, float(os.environ.get("STEER_Z", "0.1"))))    # the new wheel, a touch lower so the dials show over its hub
RIM_R = float(os.environ.get("RIM_R", "0.07"))
CL_Z = float(os.environ.get("CL_Z", "0.134"))      # the gauge faces, high on the pod
WS_Y = float(os.environ.get("WS_Y", "0.29"))
STEER_TILT = math.radians(33.5)
WS_N = Vector((0.8434, 0.0, -0.5373))  # the windshield's plane (normal into the cab), and where it sits along it
WS_OFF = -0.3965

def arrays():
	n = len(me.polygons)
	cen = np.zeros(n * 3); me.polygons.foreach_get("center", cen); cen = cen.reshape(-1, 3)
	nrm = np.zeros(n * 3); me.polygons.foreach_get("normal", nrm); nrm = nrm.reshape(-1, 3)
	co = np.zeros(len(me.vertices) * 3); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
	ls = np.zeros(n, dtype=np.int64); me.polygons.foreach_get("loop_start", ls)
	lt = np.zeros(n, dtype=np.int64); me.polygons.foreach_get("loop_total", lt)
	lv = np.zeros(len(me.loops), dtype=np.int64); me.loops.foreach_get("vertex_index", lv)
	assert (lt == 3).all()
	V = co[lv[ls[:, None] + np.arange(3)]]
	return cen, nrm, V

def select(ob, mask):
	bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
	for o in bpy.data.objects: o.select_set(o is ob)
	bpy.context.view_layer.objects.active = ob
	bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_mode(type="FACE"); bpy.ops.mesh.select_all(action="DESELECT")
	bpy.ops.object.mode_set(mode="OBJECT")
	ob.data.polygons.foreach_set("select", mask)
	bpy.ops.object.mode_set(mode="EDIT")

# ---------------------------------------------------------------- the wheels: every corner of the face inside the tyre
cen, nrm, V = arrays()
wheels = {}
for key, cx, sg in (("f1", FRONT_X, -1), ("f0", FRONT_X, 1), ("r1", REAR_X, -1), ("r0", REAR_X, 1)):
	# (f1/r1: the wheel on the game's +x side, which is Meshy's -y)
	cen, nrm, V = arrays()
	r = np.hypot(V[..., 0] - cx, V[..., 2] - HUB_Z); ay = V[..., 1] * sg
	rmax = 0.152 if key[0] == "f" else 0.146
	m = np.all((r < rmax) & (ay > 0.212), axis=1)
	print("WHEEL", key, int(m.sum()))
	select(body, m)
	bpy.ops.mesh.separate(type="SELECTED")
	bpy.ops.object.mode_set(mode="OBJECT")
	w = [o for o in bpy.data.objects if o.type == "MESH" and o is not body and o.name not in [x.name for x in wheels.values()]][0]
	w.name = "wheel_" + key
	# centred on its hub (the game puts it on the axle)
	w.data.transform(Matrix.Translation(Vector((-cx, -sg * HUB_Y, -HUB_Z))))
	w["hub"] = (cx, sg * HUB_Y, HUB_Z)
	wheels[key] = w

# ---------------------------------------------------------------- the steering wheel and column, and the windshield slab
cen, nrm, V = arrays()
N = np.array([math.cos(STEER_TILT), 0, math.sin(STEER_TILT)])
d = cen - np.array(STEER_C); h = d @ N
rad = np.linalg.norm(d - np.outer(h, N), axis=1)
steer = (np.abs(h) < 0.03) & (rad < 0.095)
t = -h; perp = np.linalg.norm(d + np.outer(t, N), axis=1)
column = (t > 0.0) & (t < 0.13) & (perp < 0.036)
wn = np.array(WS_N)
off = cen @ wn
ws = (np.abs(off - WS_OFF) < 0.009) & (np.abs(nrm @ wn) > 0.93) & (np.abs(cen[:, 1]) < WS_Y) & (cen[:, 2] > 0.145) & (cen[:, 2] < 0.31)
# the slab curls round at its two ends, up to the pillars: take that too
ws |= (np.abs(off - WS_OFF) < 0.03) & (np.abs(nrm @ wn) > 0.2) & (np.abs(cen[:, 1]) > 0.15) & (np.abs(cen[:, 1]) < 0.30) & (cen[:, 2] > 0.15) & (cen[:, 2] < 0.305) & (cen[:, 0] > -0.42) & (cen[:, 0] < -0.22)
print("STEER", int(steer.sum()), "COLUMN", int(column.sum()), "WINDSHIELD", int(ws.sum()))
# the opening the glass fills: the windshield faces' corners, in the plane
up = Vector((WS_N.z, 0, -WS_N.x)) * -1            # up the glass
if up.z < 0: up = -up
wpts = V[ws].reshape(-1, 3)
uv2 = np.stack([wpts[:, 1], wpts @ np.array(up)], axis=1)
cut = steer | column | ws
select(body, cut)
bpy.ops.mesh.delete(type="FACE"); bpy.ops.object.mode_set(mode="OBJECT")
print("BODY tris", len(me.polygons))

# ---------------------------------------------------------------- measure the cab now it's clear
cen, nrm, V = arrays()
def stat(mask, nm):
	p = cen[mask]
	print("MEASURE", nm, int(mask.sum()), "min", p.min(0).round(4) if len(p) else None, "max", p.max(0).round(4) if len(p) else None, "median", np.median(p, 0).round(4) if len(p) else None)
	return p
pod = stat((np.abs(cen[:, 1] + 0.123) < 0.075) & (cen[:, 2] > 0.09) & (cen[:, 2] < 0.18) & (cen[:, 0] > -0.34) & (cen[:, 0] < -0.22) & (nrm[:, 0] > 0.75), "pod_face")
mir = stat((np.abs(cen[:, 1]) < 0.06) & (cen[:, 2] > 0.235) & (cen[:, 2] < 0.295) & (cen[:, 0] > -0.34) & (cen[:, 0] < -0.2) & (nrm[:, 0] > 0.7), "mirror_face")
bed = stat((cen[:, 0] > 0.25) & (cen[:, 0] < 0.85) & (np.abs(cen[:, 1]) < 0.15) & (nrm[:, 2] > 0.9) & (cen[:, 2] < 0.05), "bed_floor")
seat = stat((cen[:, 0] > -0.12) & (cen[:, 0] < 0.08) & (np.abs(cen[:, 1]) < 0.2) & (nrm[:, 2] > 0.85) & (cen[:, 2] < 0.08) & (cen[:, 2] > -0.12), "seat_top")
backwall = (cen[:, 0] > 0.1) & (cen[:, 0] < 0.2) & (nrm[:, 0] > 0.8) & (cen[:, 2] > -0.12) & (cen[:, 2] < 0.12) & (np.abs(cen[:, 1]) < 0.3)
stat(backwall, "cab_back_wall")
# the gauge face sits on the pod's face, in front of the driver
POD_X = float(np.percentile(pod[:, 0], 85)) if len(pod) else -0.27
POD_Z = float(np.median(pod[:, 2])) if len(pod) else 0.13
MIR = Vector(np.median(mir, 0)) if len(mir) else Vector((-0.27, 0, 0.268))
MIR.x = float(np.percentile(mir[:, 0], 90)) if len(mir) else MIR.x
BED_Z = float(np.median(bed[:, 2])) if len(bed) else -0.1
print("POD_X", POD_X, "POD_Z", POD_Z, "MIRROR", tuple(MIR), "BED_Z", BED_Z)

# ---------------------------------------------------------------- a white smear on the back of the cab: paint it out
img = MESHY_MAT.node_tree.nodes["Image Texture"].image
W, H = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
uvl = me.uv_layers.active.data
uvs = np.zeros(len(me.loops) * 2); uvl.foreach_get("uv", uvs); uvs = uvs.reshape(-1, 2)
ls = np.zeros(len(me.polygons), dtype=np.int64); me.polygons.foreach_get("loop_start", ls)
mask = np.zeros((H, W), dtype=bool)
YY, XX = np.mgrid[0:H, 0:W]
for fi in np.nonzero(backwall)[0]:
	tri = uvs[ls[fi]:ls[fi] + 3] * [W, H]
	x0, y0 = np.floor(tri.min(0)).astype(int) - 1; x1, y1 = np.ceil(tri.max(0)).astype(int) + 2
	x0 = max(x0, 0); y0 = max(y0, 0); x1 = min(x1, W); y1 = min(y1, H)
	if x1 <= x0 or y1 <= y0: continue
	sx = XX[y0:y1, x0:x1] + 0.5; sy = YY[y0:y1, x0:x1] + 0.5
	(ax, ay), (bx, by), (cx2, cy2) = tri
	den = (by - cy2) * (ax - cx2) + (cx2 - bx) * (ay - cy2)
	if abs(den) < 1e-9: continue
	l1 = ((by - cy2) * (sx - cx2) + (cx2 - bx) * (sy - cy2)) / den
	l2 = ((cy2 - ay) * (sx - cx2) + (ax - cx2) * (sy - cy2)) / den
	l3 = 1 - l1 - l2
	inside = (l1 > -0.08) & (l2 > -0.08) & (l3 > -0.08)
	mask[y0:y1, x0:x1] |= inside
rgb = px[..., :3]
bright = rgb.max(2); sat = bright - rgb.min(2)
light = mask & (bright > 0.45) & (sat < 0.12)
good = mask & ~light
print("SMEAR texels", int(light.sum()), "of", int(mask.sum()))
if light.sum() > 0 and good.sum() > 0:
	fill = np.median(rgb[good], axis=0)
	rng = np.random.default_rng(3)
	rgb[light] = fill * (1 + 0.05 * (rng.random((int(light.sum()), 1)) - 0.5))
	px[..., :3] = rgb
	img.pixels[:] = px.ravel()
	img.update()

# ---------------------------------------------------------------- new parts
def hexc(h): h = h.lstrip("#"); return [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
def lin(c): return [((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c]
def mat(name, col, rough=0.6, metal=0.0, tex=None):
	m = bpy.data.materials.new(name); m.use_nodes = True
	b = m.node_tree.nodes["Principled BSDF"]
	b.inputs["Base Color"].default_value = (*lin(hexc(col)), 1)
	b.inputs["Roughness"].default_value = rough; b.inputs["Metallic"].default_value = metal
	if tex is not None:
		tn = m.node_tree.nodes.new("ShaderNodeTexImage"); tn.image = tex
		m.node_tree.links.new(tn.outputs[0], b.inputs["Base Color"])
	return m
# the gauge atlas: the cluster face (two big dials, blank, and four small ones each side)
AW, AH = 512, 200
at = np.zeros((AH, AW, 3)) + np.array(hexc("#101010"))
Y, X = np.mgrid[0:AH, 0:AW]
def disc(cx, cy, r, col, ring=None):
	dd = np.hypot(X - cx, Y - cy); m = dd < r if ring is None else (dd < r) & (dd > r - ring); at[m] = col
def seg(x0, y0, x1, y1, w, col):
	pxx, pyy = X - x0, Y - y0; dx, dy = x1 - x0, y1 - y0
	tt = np.clip((pxx * dx + pyy * dy) / (dx * dx + dy * dy), 0, 1)
	at[np.hypot(pxx - tt * dx, pyy - tt * dy) < w] = col
def dial(cx, cy, r, val, needle=True, red_end=False):
	disc(cx, cy, r + 5, np.array(hexc("#3a3a3a"))); disc(cx, cy, r, np.array(hexc("#0d0d0d")))
	for k in range(11):
		a = math.radians(225 - k * 27)
		ln = 0.22 if k % 2 == 0 else 0.12
		col = hexc("#d8402e") if (red_end and k >= 9) else hexc("#e8e4d8")
		seg(cx + math.cos(a) * r * (1 - ln), cy - math.sin(a) * r * (1 - ln), cx + math.cos(a) * r * 0.92, cy - math.sin(a) * r * 0.92, max(1.2, r * 0.03), np.array(col))
	if needle:
		a = math.radians(225 - val * 270)
		seg(cx, cy, cx + math.cos(a) * r * 0.8, cy - math.sin(a) * r * 0.8, max(1.5, r * 0.045), np.array(hexc("#e0301e")))
	disc(cx, cy, r * 0.09, np.array(hexc("#2a2a2a")))
dial(200, 100, 70, 0, needle=False)
dial(312, 100, 70, 0, needle=False, red_end=True)
for i, cx in enumerate((42, 98, 414, 470)):
	for j, cy in enumerate((52, 148)):
		dial(cx, cy, 30, 0.2 + 0.15 * ((i + j) % 3))
gimg = bpy.data.images.new("truck_gauges", AW, AH, alpha=False)
gimg.pixels[:] = np.concatenate([np.clip(at, 0, 1)[::-1], np.ones((AH, AW, 1))], axis=2).astype(np.float32).ravel()
gimg.filepath_raw = os.path.join(WORK, "truck_gauges.png"); gimg.file_format = "PNG"; gimg.save()

M_black = mat("black_plastic", "#1c1b1a", 0.6)
M_silver = mat("silver_trim", "#a4a8ac", 0.32, 0.85)
M_bezel = mat("cluster_bezel", "#2a2622", 0.7)
M_gauges = mat("gauge_faces", "#ffffff", 0.45, tex=gimg)
M_glass = mat("windshield_glass", "#b8c8d0", 0.05)
M_glass.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 0.2

parts = []
def part(name, bm, m, smooth=False):
	bm.normal_update()
	mm = bpy.data.meshes.new(name); bm.to_mesh(mm); bm.free()
	mm.materials.append(m)
	ob = bpy.data.objects.new(name, mm); coll.objects.link(ob); parts.append(ob)
	for p in mm.polygons: p.use_smooth = smooth
	return ob
def boxuv(bm, s):
	uvl2 = bm.loops.layers.uv.verify()
	for f in bm.faces:
		nn = f.normal; ax = max(range(3), key=lambda i: abs(nn[i]))
		a, b = [(1, 2), (0, 2), (0, 1)][ax]
		for l in f.loops: l[uvl2].uv = (l.vert.co[a] * s, l.vert.co[b] * s)
def place(bm, c, rot):
	for v in bm.verts: v.co = rot @ v.co + Vector(c)
def box(name, c, s, m, rot=None, bev=0.0, seg=2):
	bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
	for v in bm.verts: v.co = Vector((v.co.x * s[0], v.co.y * s[1], v.co.z * s[2]))
	if bev > 0: bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bev, segments=seg, affect="EDGES", profile=0.5, clamp_overlap=True)
	place(bm, c, rot if rot is not None else Matrix.Identity(3))
	bm.normal_update(); boxuv(bm, 10.0)
	return part(name, bm, m)
def cyl(name, a, b, r0, r1, m, segs=16):
	a = Vector(a); b = Vector(b); dv = b - a
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r0, radius2=r1, depth=dv.length)
	place(bm, (a + b) / 2, Vector((0, 0, 1)).rotation_difference(dv.normalized()).to_matrix()); bm.normal_update(); boxuv(bm, 10.0)
	return part(name, bm, m, smooth=True)
def torus(name, c, R, r, m, frame, segs=56, rsegs=12):
	u, v = frame; nn = u.cross(v)
	bm = bmesh.new(); rings = []
	for i in range(segs):
		a = 2 * math.pi * i / segs; radial = u * math.cos(a) + v * math.sin(a)
		rings.append([bm.verts.new(Vector(c) + radial * (R + r * math.cos(2 * math.pi * j / rsegs)) + nn * (r * math.sin(2 * math.pi * j / rsegs) * 1.15)) for j in range(rsegs)])
	for i in range(segs):
		for j in range(rsegs):
			bm.faces.new((rings[i][j], rings[(i + 1) % segs][j], rings[(i + 1) % segs][(j + 1) % rsegs], rings[i][(j + 1) % rsegs]))
	bm.normal_update(); boxuv(bm, 10.0)
	return part(name, bm, m, smooth=True)

# the steering wheel: black three-spoke on its column, silver spokes, the hub pad
col_dir = Vector(N)                        # the column's axis, up toward the driver
wr = Vector((0, 1, 0)); wu = col_dir.cross(wr).normalized()
if wu.z < 0: wu = -wu
WC = STEER_NEW.copy()
cyl("column", WC - col_dir * 0.13, WC - col_dir * 0.012, 0.013, 0.010, M_black, 18)
box("column_shroud", WC - col_dir * 0.05, (0.06, 0.034, 0.03), M_black, rot=col_dir.to_track_quat("X", "Z").to_matrix(), bev=0.007)
sb = WC - col_dir * 0.035
cyl("stalk", sb + Vector((0, -0.014, 0.004)), sb + Vector((0.006, -0.066, 0.012)), 0.0028, 0.0024, M_black, 10)
cyl("stalk_tip", sb + Vector((0.006, -0.06, 0.011)), sb + Vector((0.007, -0.074, 0.013)), 0.0042, 0.0042, M_black, 10)
torus("wheel_rim", WC, RIM_R, 0.0075, M_black, (wr, wu))
hub_rot = Matrix((wr, wu, col_dir)).transposed()
box("hub", WC + col_dir * 0.003, (0.05, 0.044, 0.022), M_black, rot=hub_rot, bev=0.008, seg=3)
box("hub_ring", WC + col_dir * 0.0128, (0.042, 0.036, 0.002), M_silver, rot=hub_rot, bev=0.004)
box("hub_pad", WC + col_dir * 0.0145, (0.036, 0.03, 0.004), M_black, rot=hub_rot, bev=0.004)
for ang, ln in ((-8, 0.05), (188, 0.05), (-90, 0.05)):
	a = math.radians(ang)
	dirv = wr * math.cos(a) + wu * math.sin(a)
	ln = RIM_R - 0.024
	mid = WC + dirv * (0.025 + ln / 2) + col_dir * 0.004
	srot = Matrix((dirv, col_dir.cross(dirv).normalized(), col_dir)).transposed()
	wdt = 0.026 if ang != -90 else 0.02
	box("spoke", mid, (ln, wdt, 0.008), M_silver, rot=srot, bev=0.003)
	box("spoke_inset", mid + col_dir * 0.004, (ln * 0.86, wdt * 0.62, 0.003), M_black, rot=srot, bev=0.002)

# the gauge cluster: a dark bezel on the pod's face, the faces just proud of it
GW, GH = 0.122, 0.047
GY = STEER_C.y
XF = POD_X + 0.004
POD_Z = CL_Z
box("cluster_bezel", (XF - 0.003, GY, POD_Z), (0.008, GW + 0.01, GH + 0.006), M_bezel, bev=0.004)
bm = bmesh.new(); uvq = bm.loops.layers.uv.verify()
vs = [bm.verts.new(Vector(p)) for p in ((XF + 0.0012, GY - GW / 2, POD_Z - GH / 2), (XF + 0.0012, GY + GW / 2, POD_Z - GH / 2), (XF + 0.0012, GY + GW / 2, POD_Z + GH / 2), (XF + 0.0012, GY - GW / 2, POD_Z + GH / 2))]
f = bm.faces.new(vs)
for l, uv in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))): l[uvq].uv = uv
part("gauge_faces", bm, M_gauges)
# where the two big dials' centres are (atlas x 200 and 312 of 512, y 100 of 200)
SPEEDO = Vector((XF + 0.0012, GY - GW / 2 + GW * 200 / 512, POD_Z))
TACH = Vector((XF + 0.0012, GY - GW / 2 + GW * 312 / 512, POD_Z))
DIAL_R = GW * 70 / 512

# the windshield glass: a flat sheet filling the opening (the convex outline of the faces it replaces)
def hull(p):
	p = sorted(set(map(tuple, np.round(p, 5))))
	def cross(o, a, b): return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
	lo, hi = [], []
	for q in p:
		while len(lo) >= 2 and cross(lo[-2], lo[-1], q) <= 0: lo.pop()
		lo.append(q)
	for q in reversed(p):
		while len(hi) >= 2 and cross(hi[-2], hi[-1], q) <= 0: hi.pop()
		hi.append(q)
	return lo[:-1] + hi[:-1]
outline = hull(uv2)
base = Vector(wn) * WS_OFF
yax = Vector((0, 1, 0))
bm = bmesh.new()
vs = [bm.verts.new(base - Vector(wn) * 0.0 + yax * p[0] + up * (p[1] - base.dot(up)) + Vector(wn) * 0.0) for p in outline]
# (in-plane: y across, 'up' along the glass; base is the plane's point on the x-z line)
gf = bm.faces.new(vs)
bmesh.ops.triangulate(bm, faces=[gf])
glass_bm = bm
print("GLASS outline", len(outline))
gme = bpy.data.meshes.new("glass"); glass_bm.normal_update(); glass_bm.to_mesh(gme); glass_bm.free()
gme.materials.append(M_glass)
glass = bpy.data.objects.new("glass", gme); coll.objects.link(glass)

# join the new parts into the interior
bpy.ops.object.select_all(action="DESELECT")
for ob in parts: ob.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
inter = bpy.context.view_layer.objects.active; inter.name = "interior"

# ---------------------------------------------------------------- into the game's frame
G = Matrix(((0, -K, 0, 0), (0, 0, K, -GROUND * K), (-K, 0, 0, 1.62 + FRONT_X * K), (0, 0, 0, 1)))
YUP = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))       # game (x, y, z) -> Blender (x, -z, y)
def game(p): return G @ Vector(p)
for ob in (body, inter, glass):
	ob.data.transform(YUP @ G); ob.matrix_world = Matrix()
GR = Matrix(((0, -K, 0, 0), (0, 0, K, 0), (-K, 0, 0, 0), (0, 0, 0, 1)))       # (rotation and scale only, for the wheels)
for w in wheels.values():
	w.data.transform(YUP @ GR); w.matrix_world = Matrix()
info = {
	"wheel_r": TIRE_R * K, "track": HUB_Y * K, "hub_y": (HUB_Z - GROUND) * K,
	"speedo": list(game(SPEEDO)), "tach": list(game(TACH)), "dial_r": DIAL_R * K,
	"mirror": list(game(MIR + Vector((0.004, 0, 0)))), "bed_y": (BED_Z - GROUND) * K,
	"front_axle": list(game((FRONT_X, 0, HUB_Z))), "rear_axle": list(game((REAR_X, 0, HUB_Z))),
	"eye_meshy": list(G.inverted() @ Vector((0.38, 1.55, -0.20))),
}
print("GAMEINFO", json.dumps(info))

bpy.ops.object.select_all(action="DESELECT")
for o in [body, inter, glass] + list(wheels.values()): o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_image_format="AUTO")
print("EXPORTED", OUT, os.path.getsize(OUT) // 1024, "KB")
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(WORK, "truck_meshy2.blend"))
