# The Crimson Workhorse truck from Meshy: keep its body, cut out the melted interior Meshy made, and build a
# proper one to the reference sheets: the two-tone woodgrain dash with its gauge cluster, vents, radio, climate
# controls and chrome glovebox; a black three-spoke wheel with silver inlays on its column and stalk; a tan
# pleated bench seat; door cards with armrest, crank and speaker; ribbed rubber mats, three pedals, the shifter
# in its boot; sun visors and the rear-view mirror.
#
# The model is Meshy's scale (1.9 units long, front toward -x, up +z, the driver on the -y side); one unit is
# about 2.8 m of real truck.
# Run: blender -b --factory-startup -P truck_interior.py -- <meshy.fbx> <out_dir> [preview]
import bpy, bmesh, sys, os, math
import numpy as np
from mathutils import Vector, Matrix

A = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = A[0], A[1]
PREVIEW = len(A) > 2
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
coll = bpy.context.collection

# ================================================================ the shell, and the old interior cut out of it
bpy.ops.import_scene.fbx(filepath=SRC)
shell = [o for o in bpy.data.objects if o.type == "MESH"][0]
shell.name = "truck_body"
shell.data.transform(shell.matrix_world); shell.matrix_world = Matrix()
me = shell.data
n = len(me.polygons)
cen = np.zeros(n * 3); me.polygons.foreach_get("center", cen); cen = cen.reshape(-1, 3)
nrm = np.zeros(n * 3); me.polygons.foreach_get("normal", nrm); nrm = nrm.reshape(-1, 3)
# everything inside the cab, clear of its walls, roof and floor: the old dash, wheel, seats, pedals, mirror, visors
CAB = dict(x0=-0.348, x1=0.124, y=0.255, z0=-0.108, z1=0.287)
cut = (cen[:, 0] > CAB["x0"]) & (cen[:, 0] < CAB["x1"]) & (np.abs(cen[:, 1]) < CAB["y"]) & (cen[:, 2] > CAB["z0"]) & (cen[:, 2] < CAB["z1"])
print("CUT faces", int(cut.sum()), "of", n)
# the old dash top runs on under the windshield, and the old headliner up into the roof: take the faces there that
# face into the cab (the outside of the cowl and the roof face out and stay)
front = (cen[:, 0] > -0.42) & (cen[:, 0] < -0.29) & (np.abs(cen[:, 1]) < 0.25) & (cen[:, 2] > 0.125) & (cen[:, 2] < 0.31) & ((nrm[:, 0] > 0.25) | (nrm[:, 2] < -0.35))
top = (cen[:, 0] > -0.37) & (cen[:, 0] < 0.13) & (np.abs(cen[:, 1]) < 0.25) & (cen[:, 2] > 0.265) & (cen[:, 2] < 0.312) & (nrm[:, 2] < -0.35)
# Meshy left the windshield opening ragged: thin teeth standing up off the cowl and hanging under the header.
# The glass and its rubber gasket (below) go in their place
teeth_lo = (cen[:, 0] > -0.378) & (cen[:, 0] < -0.342) & (np.abs(cen[:, 1]) < 0.245) & (cen[:, 2] > 0.157) & (cen[:, 2] < 0.218)
teeth_hi = (cen[:, 0] > -0.312) & (cen[:, 0] < -0.278) & (np.abs(cen[:, 1]) < 0.24) & (cen[:, 2] > 0.252) & (cen[:, 2] < 0.289)
cut = cut | front | top | teeth_lo | teeth_hi
print("CUT faces with the windshield scraps", int(cut.sum()))
sel = np.zeros(n, dtype=bool); sel[cut] = True
me.polygons.foreach_set("select", sel)
bpy.context.view_layer.objects.active = shell; shell.select_set(True)
bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_mode(type="FACE")
bpy.ops.object.mode_set(mode="OBJECT")
me.polygons.foreach_set("select", sel)
bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.delete(type="FACE"); bpy.ops.object.mode_set(mode="OBJECT")
print("SHELL faces left", len(me.polygons))

# ================================================================ materials and painted textures
def img_from(arr, name):
	h, w = arr.shape[:2]
	im = bpy.data.images.new(name, w, h, alpha=False)
	rgba = np.concatenate([arr[::-1], np.ones((h, w, 1))], axis=2).astype(np.float32)
	im.pixels[:] = rgba.ravel()
	im.filepath_raw = os.path.join(OUT, name + ".png"); im.file_format = "PNG"; im.save()
	return im
def hexc(h): h = h.lstrip("#"); return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])
def lin(c): return [((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c]
MATS = {}
def mat(name, col, rough=0.6, metal=0.0, tex=None):
	m = bpy.data.materials.new(name); m.use_nodes = True
	b = m.node_tree.nodes["Principled BSDF"]
	b.inputs["Base Color"].default_value = (*lin(hexc(col)), 1)
	b.inputs["Roughness"].default_value = rough; b.inputs["Metallic"].default_value = metal
	if tex is not None:
		t = m.node_tree.nodes.new("ShaderNodeTexImage"); t.image = tex
		m.node_tree.links.new(t.outputs[0], b.inputs["Base Color"])
	MATS[name] = m
	return m

# woodgrain for the dash fascia: warm brown with long wavering grain lines (tiles)
W = 256
yy, xx = np.mgrid[0:W, 0:W] / W
rng = np.random.default_rng(7)
warp = 0.012 * np.sin(xx * 2 * math.pi + 1.3) + 0.006 * np.sin(xx * 4 * math.pi + 0.4)
grain = 0.5 + 0.5 * np.sin((yy + warp) * 2 * math.pi * 7.0 + 2.0 * np.sin(yy * 2 * math.pi * 2.0))
grain = grain ** 4
fine = 0.5 + 0.5 * np.sin((yy + warp * 1.5) * 2 * math.pi * 37.0)
streak = 0.5 + 0.5 * np.sin(yy * 2 * math.pi * 3.0 + xx * 2 * math.pi)
wood = hexc("#8e5a32") * (1 - 0.16 * grain[..., None]) * (1 - 0.05 * fine[..., None]) * (1 - 0.05 * streak[..., None])
wood = wood * (1 + 0.04 * (rng.random((W, W, 1)) - 0.5))
wood_img = img_from(np.clip(wood, 0, 1), "truck_wood")

# the dash atlas: gauge cluster, radio, climate controls, vent grille, switch panel, the mirror's view
AW, AH = 1024, 512
at = np.zeros((AH, AW, 3)) + hexc("#151515")
Y, X = np.mgrid[0:AH, 0:AW]
def disc(cx, cy, r, col, ring=None):
	d = np.hypot(X - cx, Y - cy)
	m = d < r if ring is None else (d < r) & (d > r - ring)
	at[m] = col
def seg(x0, y0, x1, y1, w, col):
	px, py = X - x0, Y - y0; dx, dy = x1 - x0, y1 - y0
	t = np.clip((px * dx + py * dy) / (dx * dx + dy * dy), 0, 1)
	m = np.hypot(px - t * dx, py - t * dy) < w
	at[m] = col
def rect(x0, y0, x1, y1, col): at[y0:y1, x0:x1] = col
def dial(cx, cy, r, val):
	disc(cx, cy, r + 5, hexc("#3a3a3a")); disc(cx, cy, r, hexc("#0d0d0d"))
	for k in range(11):
		a = math.radians(225 - k * 27)
		ln = 0.22 if k % 2 == 0 else 0.12
		seg(cx + math.cos(a) * r * (1 - ln), cy - math.sin(a) * r * (1 - ln), cx + math.cos(a) * r * 0.92, cy - math.sin(a) * r * 0.92, max(1.2, r * 0.03), hexc("#e8e4d8"))
	a = math.radians(225 - val * 270)
	seg(cx, cy, cx + math.cos(a) * r * 0.8, cy - math.sin(a) * r * 0.8, max(1.5, r * 0.045), hexc("#e0301e"))
	disc(cx, cy, r * 0.09, hexc("#2a2a2a"))
# the cluster (0,0)-(512,200): two big dials in the middle, two pairs of small ones either side
rect(0, 0, 512, 200, hexc("#101010"))
for cx, cy, r, v in ((128 + 72, 100, 70, 0.35), (384 - 72, 100, 70, 0.22)):
	dial(cx, cy, r, v)
for i, cx in enumerate((42, 98, 414, 470)):
	for j, cy in enumerate((52, 148)):
		dial(cx, cy, 30, 0.2 + 0.15 * ((i + j) % 3))
# the radio (0,210)-(512,300): faceplate, tuning window, station buttons
rect(0, 210, 512, 300, hexc("#1a1a1a"))
rect(130, 228, 382, 262, hexc("#2c2a24")); rect(140, 236, 372, 254, hexc("#3a3428"))
seg(150, 245, 362, 245, 1.5, hexc("#a08860"))
seg(250, 236, 250, 254, 2.0, hexc("#e0301e"))
for k in range(6): rect(150 + k * 37, 272, 178 + k * 37, 290, hexc("#3a3a3a"))
# the climate panel (0,310)-(512,400): blue to red slides, two levers
rect(0, 310, 512, 400, hexc("#161616"))
for j, yl in enumerate((335, 372)):
	g = np.linspace(0, 1, 300)
	for k in range(300):
		at[yl - 3:yl + 3, 100 + k] = hexc("#2a6ad0") * (1 - g[k]) + hexc("#d02a20") * g[k]
	rect(100 + 120 + j * 60, yl - 10, 112 + 120 + j * 60, yl + 10, hexc("#c8c8c8"))
rect(30, 330, 70, 380, hexc("#2a2a2a")); rect(440, 330, 480, 380, hexc("#2a2a2a"))
# a vent grille (520,0)-(648,128): dark slats
rect(520, 0, 648, 128, hexc("#0e0e0e"))
for k in range(8): rect(526, 8 + k * 15, 642, 16 + k * 15, hexc("#2e2e2e"))
rect(520, 0, 648, 6, hexc("#3a3a3a")); rect(520, 122, 648, 128, hexc("#3a3a3a"))
# the switch panel (520,140)-(776,220): three rockers with their symbols
rect(520, 140, 776, 220, hexc("#3a2414"))
for k in range(3):
	x0 = 535 + k * 80; rect(x0, 150, x0 + 66, 210, hexc("#141414"))
	disc(x0 + 33, 180, 12, hexc("#d8d8d8"), ring=3)
# the mirror's reflection (800,0)-(1024,80): sky over autumn woods
for yv in range(0, 80):
	at[yv, 800:1024] = hexc("#9cc4e0") * (1 - yv / 80) + hexc("#d8e8f0") * (yv / 80)
for k in range(14):
	cx = 806 + k * 16; h = 26 + (k * 7) % 14
	col = [hexc("#2e5a2a"), hexc("#c86a24"), hexc("#3e6a30"), hexc("#d8a030")][k % 4]
	m = (Y > 80 - h) & (Y < 80) & (np.abs(X - cx) < (Y - (80 - h)) * 0.35 + 1)
	at[m] = col
atlas = img_from(np.clip(at, 0, 1), "truck_dash_atlas")

M_wood = mat("dash_wood", "#8a5530", 0.55, tex=wood_img)
M_pad = mat("dash_pad", "#5a3420", 0.75)
M_black = mat("black_plastic", "#1c1b1a", 0.6)
M_rubber = mat("rubber", "#151515", 0.9)
M_chrome = mat("chrome", "#d8dce0", 0.28, 0.85)
M_silver = mat("silver_trim", "#9a9ea2", 0.35, 0.8)
M_seat = mat("seat_vinyl", "#c49a62", 0.55)
M_seat_dk = mat("seat_piping", "#9a7445", 0.6)
M_door = mat("door_vinyl", "#c8a06a", 0.6)
M_door_dk = mat("door_trim", "#8a6a40", 0.6)
M_red = mat("cab_red", "#9a1e1a", 0.45)
M_tan_liner = mat("headliner", "#d2b48a", 0.85)
M_atlas = mat("dash_faces", "#ffffff", 0.45, tex=atlas)
M_glass = mat("mirror", "#ffffff", 0.1, 0.3, tex=atlas)
M_wind = mat("windshield_glass", "#a8bcc8", 0.05)
M_wind.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 0.22
for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
	try: setattr(M_wind, attr, val)
	except Exception: pass
M_gasket = mat("gasket", "#121212", 0.7)

# ================================================================ building blocks (each becomes its own object; all joined at the end)
parts = []
def part(name, bm, m):
	bm.normal_update()
	me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
	me.materials.append(m)
	ob = bpy.data.objects.new(name, me); coll.objects.link(ob); parts.append(ob)
	for p in me.polygons: p.use_smooth = False
	return ob
def boxuv(bm, s):
	uvl = bm.loops.layers.uv.verify()
	for f in bm.faces:
		nn = f.normal; ax = max(range(3), key=lambda i: abs(nn[i]))
		a, b = [(1, 2), (0, 2), (0, 1)][ax]
		for l in f.loops: l[uvl].uv = (l.vert.co[a] * s, l.vert.co[b] * s)
def place(bm, c, rot):
	for v in bm.verts: v.co = rot @ v.co + Vector(c)
def box(name, c, s, m, rot=None, bev=0.0, seg=2, uvs=10.0):
	bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
	for v in bm.verts: v.co = Vector((v.co.x * s[0], v.co.y * s[1], v.co.z * s[2]))
	if bev > 0: bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bev, segments=seg, affect="EDGES", profile=0.5, clamp_overlap=True)
	place(bm, c, rot if rot is not None else Matrix.Identity(3))
	bm.normal_update(); boxuv(bm, uvs)
	return part(name, bm, m)
def cyl(name, a, b, r0, r1, m, segs=16, caps=True):
	a = Vector(a); b = Vector(b); d = b - a
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=r0, radius2=r1, depth=d.length)
	rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix()
	place(bm, (a + b) / 2, rot); bm.normal_update(); boxuv(bm, 10.0)
	return part(name, bm, m)
def ball(name, c, r, m, scale=(1, 1, 1), segs=14):
	bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(6, segs // 2), radius=r)
	for v in bm.verts: v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
	place(bm, c, Matrix.Identity(3)); bm.normal_update(); boxuv(bm, 10.0)
	return part(name, bm, m)
def torus(name, c, R, r, m, frame, segs=48, rsegs=10):
	# frame: (u, v) unit vectors spanning the ring's plane
	u, v = frame; nrm_ = u.cross(v)
	bm = bmesh.new(); rings = []
	for i in range(segs):
		a = 2 * math.pi * i / segs
		radial = u * math.cos(a) + v * math.sin(a)
		ring = []
		for j in range(rsegs):
			b = 2 * math.pi * j / rsegs
			p = Vector(c) + radial * (R + r * math.cos(b)) + nrm_ * (r * math.sin(b) * 1.15)
			ring.append(bm.verts.new(p))
		rings.append(ring)
	for i in range(segs):
		for j in range(rsegs):
			bm.faces.new((rings[i][j], rings[(i + 1) % segs][j], rings[(i + 1) % segs][(j + 1) % rsegs], rings[i][(j + 1) % rsegs]))
	bm.normal_update(); boxuv(bm, 10.0)
	ob = part(name, bm, m)
	for p in ob.data.polygons: p.use_smooth = True
	return ob
def decal(name, corners, uvrect, m=None):
	# a flat quad (corners in order: bottom-left, bottom-right, top-right, top-left as seen from the front)
	# showing the atlas rectangle (x0, y0, x1, y1) in atlas pixels (y down)
	x0, y0, x1, y1 = uvrect
	bm = bmesh.new(); uvl = bm.loops.layers.uv.verify()
	vs = [bm.verts.new(Vector(p)) for p in corners]
	f = bm.faces.new(vs)
	uvs = [(x0 / AW, 1 - y1 / AH), (x1 / AW, 1 - y1 / AH), (x1 / AW, 1 - y0 / AH), (x0 / AW, 1 - y0 / AH)]
	for l, uv in zip(f.loops, uvs): l[uvl].uv = uv
	return part(name, bm, m or M_atlas)
def face_x(xf, yc, zc, w, h, uvrect, toward=1.0, m=None):
	# a decal on a plane facing +x (toward the seats) centred at (xf, yc, zc), w across (y), h tall
	# seen from +x (from the seats), screen-right is +y (the passenger side)
	if toward > 0: c = [(xf, yc - w / 2, zc - h / 2), (xf, yc + w / 2, zc - h / 2), (xf, yc + w / 2, zc + h / 2), (xf, yc - w / 2, zc + h / 2)]
	else: c = [(xf, yc + w / 2, zc - h / 2), (xf, yc - w / 2, zc - h / 2), (xf, yc - w / 2, zc + h / 2), (xf, yc + w / 2, zc + h / 2)]
	return decal("decal", c, uvrect, m)

DRV = -0.135        # the driver's side (left hand drive: -y)
YIN = 0.258         # the inside of the door skins

# ================================================================ the dash
# a padded brown top shelf under the windshield, a woodgrain face sloping back under it, a recessed knee panel
box("dash_top", (-0.312, 0, 0.142), (0.078, 2 * YIN, 0.026), M_pad, bev=0.008)
box("dash_lip", (-0.272, 0, 0.128), (0.012, 2 * YIN - 0.004, 0.012), M_pad, bev=0.004)
tilt = Matrix.Rotation(math.radians(-8), 3, "Y")
box("dash_face", (-0.282, 0, 0.083), (0.03, 2 * YIN, 0.082), M_wood, rot=tilt, bev=0.004, uvs=2.5)
box("dash_lower", (-0.296, 0, 0.022), (0.04, 2 * YIN, 0.044), M_wood, bev=0.004, uvs=2.5)
box("dash_trim", (-0.268, 0, 0.042), (0.008, 2 * YIN, 0.006), M_pad, bev=0.002)
XF = -0.2655          # the front face's x, at the decals' height
# gauge cluster: a black panel set into a brown surround in front of the driver
box("cluster_bezel", (XF - 0.004, DRV, 0.094), (0.012, 0.128, 0.056), M_pad, bev=0.005)
box("cluster_hood", (XF - 0.002, DRV, 0.126), (0.03, 0.13, 0.01), M_pad, bev=0.004)
face_x(XF + 0.0025, DRV, 0.094, 0.116, 0.045, (0, 0, 512, 200))
# vents: one out at each end, two either side of the middle
for vy in (-0.232, 0.232, -0.03, 0.03 + 0.0):
	if abs(vy) < 0.1 and vy > 0: continue
	box("vent_bezel", (XF - 0.002, vy, 0.105), (0.01, 0.042, 0.034), M_black, bev=0.003)
	face_x(XF + 0.0035, vy, 0.105, 0.036, 0.028, (520, 0, 648, 128))
# radio and climate controls in the middle stack, a switch panel left of the column
box("radio_bezel", (XF - 0.002, 0.038, 0.105), (0.01, 0.094, 0.03), M_black, bev=0.003)
face_x(XF + 0.0035, 0.038, 0.105, 0.088, 0.024, (0, 210, 512, 300))
for ky in (-0.0, 0.076):
	cyl("radio_knob", (XF + 0.003, ky, 0.105), (XF + 0.012, ky, 0.105), 0.0065, 0.0058, M_black, 14)
box("climate_bezel", (XF + 0.0, 0.038, 0.062), (0.01, 0.094, 0.026), M_black, bev=0.003, rot=tilt)
face_x(XF + 0.0075, 0.038, 0.062, 0.088, 0.02, (0, 310, 512, 400))
face_x(XF + 0.002, -0.235, 0.06, 0.04, 0.014, (520, 140, 776, 220))
# the glovebox: a brushed chrome door with a lock, on the passenger side
box("glovebox", (XF - 0.001, 0.17, 0.066), (0.008, 0.11, 0.03), M_chrome, bev=0.003, rot=tilt)
cyl("glove_lock", (XF + 0.0, 0.17, 0.066), (XF + 0.006, 0.17, 0.066), 0.004, 0.004, M_black, 12)
box("ashtray", (XF - 0.004, 0.038, 0.034), (0.01, 0.04, 0.01), M_chrome, bev=0.002)
# under the dash: a dark firewall and kick panels closing it off
box("firewall", (-0.344, 0, -0.045), (0.012, 2 * YIN, 0.15), M_black)
box("knee_shadow", (-0.31, 0, -0.005), (0.05, 2 * YIN, 0.01), M_black)

# ================================================================ the windshield: glass in a black rubber gasket
WB = Vector((-0.362, 0, 0.148)); WT = Vector((-0.272, 0, 0.303)); WY = 0.252
def wpt(t, y, lift=0.0):
	up = (WT - WB); nn = Vector((up.z, 0, -up.x)).normalized() * -1      # the plane's normal, pointing into the cab
	return WB + up * t + Vector((0, y, 0)) + nn * lift
bm = bmesh.new()
g = [bm.verts.new(wpt(t, y)) for t, y in ((0, -WY), (0, WY), (1, WY), (1, -WY))]
bm.faces.new(g); boxuv(bm, 4.0)
part("windshield", bm, M_wind)
# the gasket: a strip round the edge, standing a little proud both sides of the glass
for (t0, y0), (t1, y1) in (((0, -WY), (0, WY)), ((1, -WY), (1, WY)), ((0, -WY), (1, -WY)), ((0, WY), (1, WY))):
	a = wpt(t0, y0); b = wpt(t1, y1)
	along = (b - a).normalized()
	inward = (wpt(0.5, 0) - (a + b) / 2); inward = (inward - along * inward.dot(along)).normalized()
	ln = (b - a).length
	nn = along.cross(inward).normalized()
	rot = Matrix((along, inward, nn)).transposed()
	box("gasket", (a + b) / 2 + inward * 0.006, (ln + 0.02, 0.022, 0.012), M_gasket, rot=rot, bev=0.003)

# ================================================================ the steering wheel, column and stalk
col_dir = Vector((math.cos(math.radians(26)), 0, math.sin(math.radians(26))))
S0 = Vector((-0.282, DRV, 0.05))
WC = S0 + col_dir * 0.075               # the wheel's centre
wr = Vector((0, 1, 0)); wu = col_dir.cross(wr).normalized() * -1
if wu.z < 0: wu = -wu
cyl("column", S0 - col_dir * 0.02, WC - col_dir * 0.012, 0.011, 0.009, M_black, 16)
box("column_shroud", S0 + col_dir * 0.03, (0.05, 0.03, 0.028), M_black, rot=col_dir.to_track_quat("X", "Z").to_matrix(), bev=0.006)
# the turn-signal stalk out to the left, and the wiper stalk to the right
sb = S0 + col_dir * 0.045
cyl("stalk", sb + Vector((0, -0.012, 0.004)), sb + Vector((0.004, -0.065, 0.012)), 0.0028, 0.0024, M_black, 10)
cyl("stalk_tip", sb + Vector((0.004, -0.058, 0.011)), sb + Vector((0.005, -0.072, 0.013)), 0.0042, 0.0042, M_black, 10)
cyl("stalk2", sb + Vector((0, 0.012, 0.004)), sb + Vector((0.004, 0.05, 0.01)), 0.0025, 0.0022, M_black, 10)
# the rim
torus("wheel_rim", WC, 0.0715, 0.0072, M_black, (wr, wu), segs=56, rsegs=12)
# the hub: a rounded square with a pad, the spokes with silver trim and dark insets
hub_rot = Matrix((wr, wu, col_dir)).transposed()       # local x across, y up the wheel, z toward the driver
box("hub", WC + col_dir * 0.003, (0.05, 0.044, 0.022), M_black, rot=hub_rot, bev=0.008, seg=3)
box("hub_pad", WC + col_dir * 0.0145, (0.036, 0.03, 0.004), M_black, rot=hub_rot, bev=0.004)
box("hub_ring", WC + col_dir * 0.0128, (0.042, 0.036, 0.002), M_silver, rot=hub_rot, bev=0.004)
for ang, ln in ((-8, 0.05), (188, 0.05), (-90, 0.048)):
	a = math.radians(ang)
	dirv = wr * math.cos(a) + wu * math.sin(a)
	mid = WC + dirv * (0.025 + ln / 2) + col_dir * 0.004
	srot = Matrix((dirv, col_dir.cross(dirv).normalized(), col_dir)).transposed()
	wdt = 0.026 if ang != -90 else 0.02
	box("spoke", mid, (ln, wdt, 0.008), M_silver, rot=srot, bev=0.003)
	box("spoke_inset", mid + col_dir * 0.004, (ln * 0.86, wdt * 0.62, 0.003), M_black, rot=srot, bev=0.002)

# ================================================================ the bench seat: tan vinyl, pleated, piped edges
SX0, SX1 = -0.088, 0.072
CZ = -0.018                  # cushion top
box("seat_base", ((SX0 + SX1) / 2 + 0.01, 0, -0.07), (SX1 - SX0 - 0.01, 2 * 0.245, 0.06), M_black, bev=0.004)
box("cushion_body", ((SX0 + SX1) / 2, 0, CZ - 0.016), (SX1 - SX0, 2 * 0.25, 0.034), M_seat, bev=0.01, seg=3)
NP = 11
for k in range(NP):
	y = -0.228 + k * (0.456 / (NP - 1))
	box("pleat", ((SX0 + SX1) / 2 + 0.004, y, CZ - 0.004), (SX1 - SX0 - 0.014, 0.0418, 0.022), M_seat, bev=0.009, seg=3)
box("cushion_piping", (SX0 + 0.004, 0, CZ - 0.004), (0.008, 2 * 0.25, 0.008), M_seat_dk, bev=0.003)
back_rot = Matrix.Rotation(math.radians(-13), 3, "Y")
BC = Vector((0.092, 0, 0.074))
box("back_body", BC, (0.032, 2 * 0.25, 0.19), M_seat, rot=back_rot, bev=0.01, seg=3)
for k in range(NP):
	y = -0.228 + k * (0.456 / (NP - 1))
	a = BC + back_rot @ Vector((-0.016, y, -0.078)); b = BC + back_rot @ Vector((-0.016, y, 0.078))
	box("pleat_back", (a + b) / 2 + back_rot @ Vector((0.004, 0, 0)), (0.022, 0.0418, 0.156), M_seat, rot=back_rot, bev=0.009, seg=3)
box("back_piping", BC + back_rot @ Vector((-0.012, 0, 0.094)), (0.012, 2 * 0.25, 0.008), M_seat_dk, rot=back_rot, bev=0.003)
for sy in (-1, 1):
	box("seat_bracket", (SX1 - 0.01, sy * 0.24, -0.058), (0.05, 0.012, 0.03), M_black, bev=0.002)

# ================================================================ the floor: a transmission hump, ribbed rubber mats, pedals, the shifter
box("hump", (-0.24, 0, -0.1), (0.2, 0.08, 0.04), M_rubber, bev=0.012, seg=3)
for sy in (-1, 1):
	cy = sy * 0.145
	box("mat", (-0.215, cy, -0.116), (0.24, 0.17, 0.006), M_rubber, bev=0.002)
	for k in range(14):
		box("mat_rib", (-0.215, cy + (-0.07 + k * 0.0108), -0.1125), (0.21, 0.004, 0.003), M_rubber)
# pedals hang from under the dash: clutch, brake, gas
for py, wdt, ln in ((DRV - 0.05, 0.03, 0.06), (DRV - 0.005, 0.034, 0.06), (DRV + 0.048, 0.02, 0.078)):
	top = Vector((-0.31, py, 0.0)); pad = Vector((-0.282, py, -0.078))
	cyl("pedal_arm", top, pad + Vector((0, 0, 0.012)), 0.0035, 0.0035, M_chrome, 8)
	prot = Matrix.Rotation(math.radians(-24), 3, "Y")
	box("pedal_pad", pad, (0.006, wdt, 0.03 if ln < 0.07 else 0.05), M_rubber, rot=prot, bev=0.002)
	for k in range(3): box("pedal_rib", pad + Vector((0.0035, 0, -0.01 + k * 0.01)), (0.002, wdt * 0.85, 0.002), M_black, rot=prot)
# the shifter: a stepped rubber boot on a square base, a chrome stick, a black knob
SB = Vector((-0.2, 0.0, -0.08))
box("shift_base", SB, (0.05, 0.05, 0.008), M_black, bev=0.003)
for k in range(4):
	box("shift_boot", SB + Vector((0, 0, 0.007 + k * 0.007)), (0.04 - k * 0.008, 0.04 - k * 0.008, 0.008), M_rubber, bev=0.002)
stick_top = SB + Vector((0.03, 0, 0.12))
cyl("shift_stick", SB + Vector((0, 0, 0.03)), stick_top, 0.0042, 0.0036, M_chrome, 10)
ball("shift_knob", stick_top + Vector((0.002, 0, 0.008)), 0.0125, M_black, scale=(1, 1, 1.1))

# ================================================================ the door cards: tan vinyl, a darker armrest, crank, handle, speaker
for sy in (-1, 1):
	yy = sy * YIN
	inward = -sy
	box("door_card", (-0.085, yy, 0.025), (0.31, 0.008, 0.21), M_door, bev=0.004)
	box("door_upper", (-0.085, yy + inward * 0.003, 0.118), (0.3, 0.006, 0.024), M_door_dk, bev=0.003)
	box("door_sill", (-0.085, yy + inward * 0.001, 0.142), (0.31, 0.014, 0.012), M_red, bev=0.003)
	box("armrest", (-0.07, yy + inward * 0.012, 0.045), (0.13, 0.022, 0.018), M_door_dk, bev=0.006, seg=3)
	box("pull_cup", (-0.02, yy + inward * 0.006, 0.072), (0.04, 0.008, 0.016), M_door_dk, bev=0.004)
	box("handle_plate", (-0.19, yy + inward * 0.005, 0.088), (0.032, 0.004, 0.016), M_chrome, bev=0.002)
	box("handle_lever", (-0.19, yy + inward * 0.008, 0.088), (0.022, 0.004, 0.005), M_black, bev=0.0015)
	# the window crank: a round base, an arm, a black knob
	cb = Vector((0.0, yy + inward * 0.005, 0.098))
	cyl("crank_base", cb, cb + Vector((0, inward * 0.006, 0)), 0.008, 0.007, M_chrome, 14)
	arm_end = cb + Vector((0.004, inward * 0.008, -0.03))
	cyl("crank_arm", cb + Vector((0, inward * 0.006, 0)), arm_end, 0.0026, 0.0022, M_chrome, 8)
	cyl("crank_knob", arm_end, arm_end + Vector((0, inward * 0.018, 0)), 0.0052, 0.0048, M_black, 12)
	# the speaker grille low on the door, and a storage pocket
	box("speaker", (-0.18, yy + inward * 0.005, -0.03), (0.07, 0.004, 0.05), M_black, bev=0.003)
	for k in range(6): box("speaker_slat", (-0.18, yy + inward * 0.0075, -0.048 + k * 0.0075), (0.062, 0.002, 0.003), M_door_dk)
	box("pocket", (-0.06, yy + inward * 0.01, -0.055), (0.14, 0.016, 0.04), M_door_dk, bev=0.004)
	box("kick_panel", (-0.31, yy + inward * 0.004, -0.06), (0.06, 0.008, 0.1), M_door_dk, bev=0.003)

# ================================================================ up top: sun visors, the rear-view mirror, the dome light, a headliner
for sy in (-1, 1):
	box("visor", (-0.255, sy * 0.13, 0.283), (0.044, 0.16, 0.008), M_tan_liner, bev=0.003, rot=Matrix.Rotation(math.radians(-6), 3, "Y"))
	cyl("visor_rod", (-0.272, sy * 0.05, 0.288), (-0.272, sy * 0.215, 0.288), 0.0022, 0.0022, M_black, 8)
cyl("mirror_stem", (-0.276, 0, 0.29), (-0.283, 0, 0.276), 0.0028, 0.0028, M_black, 8)
box("mirror_frame", (-0.284, 0, 0.268), (0.008, 0.078, 0.022), M_black, bev=0.004)
face_x(-0.2796, 0, 0.268, 0.07, 0.016, (800, 0, 1024, 80), m=M_glass)
box("dome_light", (-0.02, 0, 0.2875), (0.04, 0.06, 0.006), M_tan_liner, bev=0.003)
box("headliner", (-0.075, 0, 0.291), (0.4, 2 * YIN + 0.004, 0.004), M_tan_liner)      # from the windshield header back
# the defroster outlets along the top of the dash, just inside the glass
for k in range(6): box("defrost_slot", (-0.343, -0.2 + k * 0.08, 0.1555), (0.01, 0.05, 0.003), M_black)
box("back_panel", (0.124, 0, 0.11), (0.004, 2 * YIN, 0.06), M_door_dk)

# ================================================================ join the interior into one object
bpy.ops.object.select_all(action="DESELECT")
for ob in parts: ob.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
interior = bpy.context.view_layer.objects.active; interior.name = "truck_interior"
interior.data.calc_loop_triangles(); print("INTERIOR tris", len(interior.data.loop_triangles), "parts", len(parts))

# ================================================================ export: the cleaned body (for texturing), the interior on its own, and both
def export(path, objs, fmt="GLB"):
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs: o.select_set(True)
	if path.endswith(".fbx"): bpy.ops.export_scene.fbx(filepath=path, use_selection=True)
	else: bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_image_format="AUTO")
	print("EXPORTED", path)
export(os.path.join(OUT, "truck_body_interior_removed.fbx"), [shell])
export(os.path.join(OUT, "truck_interior.glb"), [interior])
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "truck_fixed.blend"))

# ================================================================ previews
if PREVIEW:
	# the body in red paint (the cab's inside surfaces: tan liner up top, red on the pillars and sills)
	paint = mat("body_paint_preview", "#9a1e1a", 0.4)
	shell.data.materials.clear(); shell.data.materials.append(paint)
	sc = bpy.context.scene; sc.render.engine = "CYCLES"; sc.cycles.samples = 32; sc.cycles.use_denoising = True
	sc.view_settings.view_transform = "Standard"
	w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
	w.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.8, 0.85, 1); w.node_tree.nodes["Background"].inputs[1].default_value = 1.4
	bpy.ops.object.light_add(type="SUN", rotation=(math.radians(55), 0, math.radians(-30))); bpy.context.object.data.energy = 3.5
	bpy.ops.object.light_add(type="POINT", location=(-0.05, 0, 0.24)); bpy.context.object.data.energy = 6.0; bpy.context.object.data.shadow_soft_size = 0.2
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); coll.objects.link(cam); sc.camera = cam
	sc.render.resolution_x, sc.render.resolution_y = 1000, 560
	def snap(name, pos, tgt, lens=18):
		cam.data.lens = lens; cam.data.clip_start = 0.003
		cam.location = pos; cam.rotation_euler = (Vector(tgt) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
		sc.render.filepath = os.path.join(OUT, "view_%s.png" % name); bpy.ops.render.render(write_still=True)
	snap("driver", (0.03, DRV, 0.205), (-0.4, DRV + 0.03, 0.09), 16)
	snap("cab_front", (0.06, 0.0, 0.22), (-0.4, 0.0, 0.07), 14)
	snap("passenger", (0.03, 0.15, 0.2), (-0.4, -0.06, 0.07), 16)
	snap("wheel", (-0.12, DRV + 0.02, 0.14), (-0.24, DRV, 0.09), 28)
	snap("dash_mid", (-0.12, 0.06, 0.13), (-0.28, 0.06, 0.08), 22)
	snap("seat", (-0.3, 0.02, 0.2), (0.1, 0.0, 0.0), 16)
	snap("door_l", (-0.05, 0.12, 0.12), (-0.08, -0.26, 0.03), 18)
	snap("window", (-0.06, -0.8, 0.25), (-0.1, 0.0, 0.08), 26)
	snap("outside34", (-1.6, -1.3, 0.75), (0.0, 0.0, 0.0), 40)
	print("PREVIEWS", OUT)
