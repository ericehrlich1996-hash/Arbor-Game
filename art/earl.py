# Earl, "classic logger" - built in Blender from the concept sheet, exported in the pieces the game poses.
# Run: blender -b --factory-startup -P earl.py -- <out.glb> [preview_dir]
#
# Coordinates are written in GAME space (Godot: x right, y up, +z is the way he faces) and converted to
# Blender's (x, -z, y) on the way in, so the numbers line up with scripts/earl.gd:
#   torso: pivot at the hips; neck at y 0.58; shoulders at (+-0.25, 0.5)
#   head: pivot at the base of the neck, faces +z
#   upper: pivot at the shoulder, elbow at y -0.3;  fore: pivot at the elbow, hand (cane grip) at y -0.3
#   leg: pivot at the hip joint, sole at y -0.92;  cane: pivot in the hand
# Two materials: "palette" (flat colours, each face's UVs on one swatch of a small atlas) and
# "plaid" (a tiling buffalo-check texture, wrapped round the shirt and sleeves).
import bpy, bmesh, math, sys, os, random
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "/tmp/earl.glb"
PREV = argv[1] if len(argv) > 1 else ""
HERE = os.path.dirname(os.path.abspath(__file__))
random.seed(7)

bpy.ops.wm.read_factory_settings(use_empty=True)

def G(x, y, z):            # game space -> Blender space
	return Vector((x, -z, y))

# ------------------------------------------------------------------ the two textures
PAL = {
	"skin": "#eab08c", "skin_dk": "#d89878", "nose": "#e5876a", "cheek": "#e9967f", "eye": "#141414",
	"beard": "#ece8de", "beard_dk": "#d6d1c4", "hair": "#cfcabf",
	"hat": "#3f5626", "hat_dk": "#31441d", "band": "#5a3a22", "leaf": "#d88a2a", "leaf2": "#e2b03a",
	"denim": "#34507c", "denim_dk": "#2b4268", "denim_lt": "#5f7ba6", "stitch": "#8a8466",
	"brass": "#c9a24a", "leather": "#6a4426", "leather_dk": "#53341c", "patch": "#8a5a30",
	"glove": "#a07c32", "glove_dk": "#7f6226", "cuff": "#a8342c", "cuff_lt": "#b8443a",
	"boot": "#6c4425", "boot_dk": "#53331b", "sole": "#2a2420", "lace": "#d8bf86",
	"wood": "#6a4a2a", "rubber": "#1e1e1e", "red_dk": "#6e1e1a",
}
NAMES = list(PAL.keys())
SW = 8                      # swatches per row
def hex2rgb(h):
	h = h.lstrip("#"); return [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
def srgb2lin(c):
	return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def make_palette():
	n = 8 * SW; img = bpy.data.images.new("earl_palette", n, n, alpha=False)
	px = [0.0] * (n * n * 4)
	for i, k in enumerate(NAMES):
		cx, cy = i % SW, i // SW
		r, g, b = hex2rgb(PAL[k])
		for y in range(cy * 8, cy * 8 + 8):
			for x in range(cx * 8, cx * 8 + 8):
				o = (y * n + x) * 4; px[o:o + 4] = [r, g, b, 1.0]
	img.pixels = px
	img.filepath_raw = os.path.join(HERE, "earl_palette.png"); img.file_format = "PNG"; img.save()
	return img

def swatch_uv(name):
	i = NAMES.index(name); n = 8 * SW
	return ((i % SW) * 8 + 4) / n, ((i // SW) * 8 + 4) / n

def make_plaid():
	# buffalo check: red, black where both stripes cross, a dark red where one does; a fine twill speck
	n = 128; img = bpy.data.images.new("earl_plaid", n, n, alpha=False)
	red = hex2rgb("#a32a25"); blk = hex2rgb("#1c1416"); mid = [red[i] * 0.42 + blk[i] * 0.58 for i in range(3)]
	px = [0.0] * (n * n * 4)
	for y in range(n):
		for x in range(n):
			sx = (x // 32) % 2 == 0; sy = (y // 32) % 2 == 0
			c = blk if (sx and sy) else (mid if (sx or sy) else red)
			k = 0.94 + 0.06 * (((x + y) // 2) % 2)          # twill
			o = (y * n + x) * 4; px[o:o + 4] = [c[0] * k, c[1] * k, c[2] * k, 1.0]
	img.pixels = px
	img.filepath_raw = os.path.join(HERE, "earl_plaid.png"); img.file_format = "PNG"; img.save()
	return img

def material(name, img):
	m = bpy.data.materials.new(name); m.use_nodes = True
	nt = m.node_tree; bsdf = nt.nodes["Principled BSDF"]
	tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img
	tex.interpolation = "Closest" if name == "palette" else "Linear"
	nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
	bsdf.inputs["Roughness"].default_value = 0.9
	bsdf.inputs["Specular IOR Level"].default_value = 0.2
	return m

PALETTE = material("palette", make_palette())
PLAID = material("plaid", make_plaid())

# ------------------------------------------------------------------ building blocks (bmesh, game space)
class Part:
	def __init__(self, name):
		self.name = name; self.bm = bmesh.new(); self.uv = self.bm.loops.layers.uv.new("UV")

	def _add(self, geom_verts, faces_new, color, plaid=None):
		# colour: put each new face's UVs on a swatch, or wrap the plaid round an axis
		for f in faces_new:
			if plaid is None:
				f.material_index = 0
				u, v = swatch_uv(color)
				for l in f.loops: l[self.uv].uv = (u, v)
			else:
				f.material_index = 1
				axis_o, scale = plaid
				for l in f.loops:
					p = l.vert.co                              # blender space
					gx, gy, gz = p.x - axis_o.x, p.z - axis_o.z, -(p.y - axis_o.y)
					a = math.atan2(gx, gz)
					l[self.uv].uv = (a / (2 * math.pi) * scale[0], gy * scale[1])
		# fix the plaid seam: faces straddling the back get their u unwrapped
		if plaid is not None:
			for f in faces_new:
				us = [l[self.uv].uv.x for l in f.loops]
				if max(us) - min(us) > scale_half(plaid):
					for l in f.loops:
						if l[self.uv].uv.x < 0: l[self.uv].uv.x += plaid[1][0]

	def _xf(self, verts, m):
		bmesh.ops.transform(self.bm, matrix=m, verts=verts)

	def mesh_from(self, fn, color, m, plaid=None):
		tmp = bmesh.new(); fn(tmp)
		bmesh.ops.transform(tmp, matrix=m, verts=tmp.verts)
		me = bpy.data.meshes.new("tmp"); tmp.to_mesh(me); tmp.free()
		before = set(self.bm.faces)
		self.bm.from_mesh(me); bpy.data.meshes.remove(me)
		self.bm.faces.ensure_lookup_table()
		new = [f for f in self.bm.faces if f not in before]
		self._add(None, new, color, plaid)
		return new

	# ellipsoid: centre and radii in game space, segments
	def ball(self, c, r, color, seg=12, rings=8, rot=None, plaid=None, jitter=0.0):
		def fn(b):
			bmesh.ops.create_uvsphere(b, u_segments=seg, v_segments=rings, radius=1.0)
			if jitter:
				for v in b.verts: v.co *= 1.0 + random.uniform(-jitter, jitter)
		m = Matrix.Translation(G(*c)) @ (rot or Matrix()) @ Matrix.Diagonal((r[0], r[2], r[1], 1.0))
		return self.mesh_from(fn, color, m, plaid)

	def icob(self, c, r, color, subdiv=1, rot=None, jitter=0.0):
		def fn(b):
			bmesh.ops.create_icosphere(b, subdivisions=subdiv, radius=1.0)
			if jitter:
				for v in b.verts: v.co *= 1.0 + random.uniform(-jitter, jitter)
		m = Matrix.Translation(G(*c)) @ (rot or Matrix()) @ Matrix.Diagonal((r[0], r[2], r[1], 1.0))
		return self.mesh_from(fn, color, m)

	# rounded box: centre, full size, bevel radius
	def box(self, c, s, color, bevel=0.0, rot=None, segs=2):
		def fn(b):
			bmesh.ops.create_cube(b, size=1.0)
			if bevel > 0:
				bmesh.ops.bevel(b, geom=list(b.edges), offset=min(bevel, min(s) * 0.49) / 1.0, offset_type="OFFSET",
					segments=segs, profile=0.5, affect="EDGES", clamp_overlap=True)
		# bevel in unit space would be scaled unevenly: build at size, not scaled
		def fn2(b):
			bmesh.ops.create_cube(b, size=1.0)
			bmesh.ops.scale(b, vec=Vector((s[0], s[2], s[1])), verts=b.verts)
			if bevel > 0:
				bmesh.ops.bevel(b, geom=list(b.edges), offset=min(bevel, min(s) * 0.45), offset_type="OFFSET",
					segments=segs, profile=0.5, affect="EDGES", clamp_overlap=True)
		m = Matrix.Translation(G(*c)) @ (rot or Matrix())
		return self.mesh_from(fn2, color, m)

	# a tapered tube along game-space a->b, elliptical (rx, rz) section
	def tube(self, a, b, r0, r1, color, seg=10, caps=True, plaid=None, squash=1.0):
		A = G(*a); B = G(*b); d = B - A; L = d.length
		def fn(bb):
			bmesh.ops.create_cone(bb, cap_ends=caps, cap_tris=False, segments=seg, radius1=r0, radius2=r1, depth=L)
			bmesh.ops.scale(bb, vec=Vector((1.0, squash, 1.0)), verts=bb.verts)
			bmesh.ops.translate(bb, vec=Vector((0, 0, L / 2)), verts=bb.verts)
		q = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
		m = Matrix.Translation(A) @ q
		return self.mesh_from(fn, color, m, plaid)

	# a body of revolution from a profile [(y, rx, rz), ...] (game space), closed at the ends
	def lathe(self, prof, color, seg=20, plaid=None, cap_top=True, cap_bot=True, x=0.0, z=0.0):
		def fn(b):
			rings = []
			for (y, rx, rz) in prof:
				ring = []
				for i in range(seg):
					a = 2 * math.pi * i / seg
					ring.append(b.verts.new(G(x + math.sin(a) * rx, y, z + math.cos(a) * rz)))
				rings.append(ring)
			for j in range(len(rings) - 1):
				for i in range(seg):
					b.faces.new((rings[j][i], rings[j][(i + 1) % seg], rings[j + 1][(i + 1) % seg], rings[j + 1][i]))
			if cap_bot: b.faces.new(list(reversed(rings[0])))
			if cap_top: b.faces.new(rings[-1])
			bmesh.ops.recalc_face_normals(b, faces=b.faces)
		return self.mesh_from(fn, color, Matrix(), plaid)

	def finish(self, smooth_angle=38.0):
		bm = self.bm
		bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0002)
		for f in bm.faces: f.smooth = True
		lim = math.radians(smooth_angle)
		for e in bm.edges:
			if len(e.link_faces) == 2 and e.calc_face_angle(0) > lim: e.smooth = False
		me = bpy.data.meshes.new(self.name); bm.to_mesh(me); bm.free()
		me.materials.append(PALETTE); me.materials.append(PLAID)
		ob = bpy.data.objects.new(self.name, me); bpy.context.collection.objects.link(ob)
		return ob

def scale_half(plaid): return plaid[1][0] * 0.5

def Rx(a): return Matrix.Rotation(a, 4, "X")      # blender axes
def Ry(a): return Matrix.Rotation(a, 4, "Y")
def Rz(a): return Matrix.Rotation(a, 4, "Z")
# game-space rotations: about game x = blender x; about game y (up) = blender z; about game z = blender -y
def gRx(a): return Rx(a)
def gRy(a): return Rz(a)
def gRz(a): return Ry(-a)

PLAID_TORSO = (G(0, 0, 0), (5.0, 7.5))      # 5 checks round the body, ~7.5 per metre up
PLAID_ARM = (G(0, 0, 0), (2.0, 7.5))

# ------------------------------------------------------------------ torso (pivot: hips)
t = Part("torso")
# shirt: broad and a little round in the belly, narrowing to the shoulders and neck
t.lathe([(0.06, 0.205, 0.158), (0.16, 0.228, 0.182), (0.28, 0.236, 0.186), (0.40, 0.232, 0.172), (0.48, 0.222, 0.155),
	(0.535, 0.19, 0.135), (0.565, 0.12, 0.1), (0.585, 0.07, 0.07)], None, seg=20, plaid=PLAID_TORSO)
for sx in (-1, 1):                                   # shoulder caps
	t.ball((sx * 0.19, 0.488, 0.0), (0.082, 0.07, 0.1), None, 12, 8, plaid=(G(sx * 0.2, 0, 0), (2.0, 7.5)))
# collar: two points over a band, and a placket with buttons above the bib
t.lathe([(0.545, 0.085, 0.078), (0.6, 0.078, 0.072)], "red_dk", seg=14, cap_bot=False)
for sx in (-1, 1):
	t.box((sx * 0.048, 0.582, 0.072), (0.07, 0.014, 0.06), "red_dk", 0.006, rot=gRz(sx * 0.6) @ gRx(0.5))
t.box((0, 0.48, 0.152), (0.026, 0.12, 0.008), "red_dk", 0.003)
for k in range(2): t.ball((0, 0.455 + k * 0.05, 0.158), (0.008, 0.008, 0.005), "beard", 6, 4)
# overalls: the seat and legs' tops, then the bib with its pocket, patch and brass buttons
t.lathe([(-0.16, 0.2, 0.156), (-0.05, 0.218, 0.17), (0.08, 0.232, 0.184), (0.16, 0.238, 0.19)], "denim", seg=20, cap_top=False)
t.box((0, 0.285, 0.168), (0.31, 0.27, 0.034), "denim", 0.014, segs=2)
t.box((0, 0.297, 0.188), (0.16, 0.12, 0.01), "denim_dk", 0.004)            # bib pocket
t.box((0, 0.355, 0.194), (0.16, 0.006, 0.004), "stitch")
t.box((0, 0.297, 0.195), (0.048, 0.048, 0.004), "patch", 0.002)              # the leather patch
t.box((0, 0.297, 0.198), (0.016, 0.022, 0.003), "leaf")
t.box((0, 0.05, 0.188), (0.004, 0.14, 0.004), "denim_dk")                    # fly seam
for sx in (-1, 1):
	# straps: up over the shoulder, crossing down the back
	t.tube((sx * 0.115, 0.4, 0.176), (sx * 0.135, 0.565, 0.07), 0.024, 0.024, "denim", 6, squash=0.35)
	t.tube((sx * 0.135, 0.565, 0.07), (sx * 0.13, 0.55, -0.135), 0.024, 0.024, "denim", 6, squash=0.35)
	# down the back in two straight runs, sitting just proud of the shirt, crossing in the middle
	t.tube((sx * 0.13, 0.55, -0.135), (0.0, 0.36, -0.192), 0.026, 0.026, "denim", 6, squash=0.35)
	t.tube((0.0, 0.36, -0.192), (-sx * 0.11, 0.17, -0.198), 0.026, 0.026, "denim", 6, squash=0.35)
	t.ball((sx * 0.115, 0.392, 0.194), (0.022, 0.022, 0.012), "brass", 10, 6)
	t.ball((sx * 0.222, 0.13, 0.08), (0.012, 0.016, 0.012), "brass", 8, 5)        # side buttons
	t.box((sx * 0.09, -0.04, -0.18), (0.11, 0.12, 0.012), "denim_dk", 0.004)     # back pockets
	t.box((sx * 0.09, 0.016, -0.186), (0.11, 0.006, 0.004), "stitch")
# tool belt, buckle, and the pouch on his left hip
t.lathe([(0.105, 0.244, 0.194), (0.15, 0.246, 0.196)], "leather", seg=20, cap_top=False, cap_bot=False)
t.lathe([(0.105, 0.24, 0.19), (0.15, 0.242, 0.192)], "leather_dk", seg=20, cap_top=False, cap_bot=False)
t.box((0, 0.128, 0.2), (0.052, 0.044, 0.012), "brass", 0.004)
t.box((0, 0.128, 0.205), (0.03, 0.024, 0.006), "leather_dk")
t.box((0.22, 0.04, 0.06), (0.065, 0.13, 0.095), "leather", 0.014)
t.box((0.22, 0.095, 0.062), (0.07, 0.035, 0.1), "leather_dk", 0.01)
torso = t.finish()

# ------------------------------------------------------------------ head (pivot: base of the neck); drawn a touch large
h = Part("head")
S = 1.12
def hs(c): return (c[0] * S, c[1] * S, c[2] * S)
def hr(r): return (r[0] * S, r[1] * S, r[2] * S)
h.tube((0, -0.03, 0), (0, 0.07, 0.01), 0.062, 0.058, "skin_dk", 10, False)       # neck
h.ball(hs((0, 0.168, 0.0)), hr((0.112, 0.124, 0.112)), "skin", 16, 10)
for sx in (-1, 1):
	h.ball(hs((sx * 0.112, 0.163, -0.006)), hr((0.02, 0.034, 0.026)), "skin_dk", 8, 6)            # ears
	h.ball(hs((sx * 0.066, 0.15, 0.088)), hr((0.022, 0.016, 0.012)), "cheek", 8, 6)               # cheeks
	h.ball(hs((sx * 0.043, 0.186, 0.101)), hr((0.0125, 0.017, 0.008)), "eye", 8, 6)               # dot eyes
	h.box(hs((sx * 0.045, 0.214, 0.103)), (0.05, 0.017, 0.024), "beard", 0.006, rot=gRz(-sx * 0.08))   # brows
h.ball(hs((0, 0.146, 0.122)), hr((0.034, 0.032, 0.03)), "nose", 12, 8)              # the nose
# beard: full and faceted, from the cheeks down over the collar; moustache on top
h.icob(hs((0, 0.06, 0.05)), hr((0.112, 0.11, 0.085)), "beard", 2, jitter=0.05)
h.icob(hs((0, -0.005, 0.06)), hr((0.085, 0.07, 0.07)), "beard", 1, jitter=0.06)
for sx in (-1, 1):
	h.icob(hs((sx * 0.088, 0.105, 0.035)), hr((0.034, 0.07, 0.06)), "beard", 1, jitter=0.05)      # sideburns
	h.icob(hs((sx * 0.04, 0.112, 0.112)), hr((0.048, 0.022, 0.026)), "beard", 1, rot=gRz(sx * 0.18), jitter=0.04)   # moustache
# grey hair round the back, under the brim
h.icob(hs((0, 0.16, -0.045)), hr((0.118, 0.085, 0.09)), "hair", 1, jitter=0.06)
# crusher hat: crown with a dent, leather band, wide brim turned up a touch at the sides, a leaf in the band
h.lathe([(0.0, 0.124, 0.13), (0.06, 0.118, 0.123), (0.11, 0.104, 0.108), (0.125, 0.07, 0.074)], "hat", seg=16,
	x=0, z=0) if False else None
crown = [(y * S + 0.0, rx * S, rz * S) for (y, rx, rz) in [(0.232, 0.126, 0.132), (0.3, 0.122, 0.128), (0.355, 0.11, 0.115), (0.382, 0.085, 0.09), (0.392, 0.04, 0.045)]]
h.lathe(crown, "hat", seg=16)
h.box(hs((0, 0.388, 0)), (0.03, 0.02, 0.15 * S), "hat_dk", 0.008)
h.lathe([(0.243 * S, 0.128 * S, 0.134 * S), (0.272 * S, 0.124 * S, 0.13 * S)], "band", seg=16, cap_top=False, cap_bot=False)
brim = []
for (y, rx, rz) in [(0.232, 0.13, 0.136), (0.237, 0.185, 0.195), (0.246, 0.196, 0.206)]:
	brim.append((y * S, rx * S, rz * S))
h.lathe(brim, "hat", seg=20, cap_top=False, cap_bot=False)
h.lathe([(0.243 * S, 0.196 * S, 0.206 * S), (0.226 * S, 0.188 * S, 0.198 * S), (0.226 * S, 0.13 * S, 0.136 * S)], "hat_dk", seg=20, cap_top=False, cap_bot=False)
for k, lc in enumerate(("leaf", "leaf2")):
	rot = gRy(-0.5 - k * 0.25) @ gRz(-0.35 - k * 0.3)
	h.ball(hs((0.118 - k * 0.012, 0.32 + k * 0.01, 0.035 - k * 0.03)), (0.006, 0.042, 0.02), lc, 8, 5, rot=rot)
head = h.finish(45)

# ------------------------------------------------------------------ upper arm (pivot: shoulder)
u = Part("upper")
u.lathe([(0.04, 0.072, 0.078), (-0.12, 0.068, 0.072), (-0.3, 0.06, 0.063)], None, seg=12, plaid=PLAID_ARM)
u.ball((0, -0.3, 0), (0.06, 0.035, 0.063), "red_dk", 10, 6)
upper = u.finish()

# ------------------------------------------------------------------ forearm + glove (pivot: elbow; cane grip at y -0.3)
f = Part("fore")
f.lathe([(0.0, 0.06, 0.062), (-0.17, 0.056, 0.058)], None, seg=12, plaid=PLAID_ARM, cap_top=False)
f.lathe([(-0.165, 0.068, 0.07), (-0.2, 0.07, 0.072), (-0.225, 0.066, 0.068)], "cuff", seg=12)       # rolled cuff
f.lathe([(-0.168, 0.07, 0.072), (-0.176, 0.07, 0.072)], "cuff_lt", seg=12, cap_top=False, cap_bot=False)
f.lathe([(-0.215, 0.054, 0.056), (-0.27, 0.05, 0.052)], "glove_dk", seg=10)                         # gauntlet
f.box((0, -0.312, 0.004), (0.094, 0.085, 0.066), "glove", 0.022, segs=3)                            # palm / back
for i in range(4):                                                                                   # curled fingers
	x = -0.033 + i * 0.022
	f.box((x, -0.36, 0.016), (0.021, 0.048, 0.054), "glove", 0.009, rot=gRx(0.25))
	f.box((x, -0.372, 0.044), (0.02, 0.03, 0.03), "glove_dk", 0.008)
f.box((0.048, -0.31, 0.034), (0.026, 0.06, 0.03), "glove", 0.01, rot=gRz(0.5) @ gRx(0.3))          # thumb
fore = f.finish()

# ------------------------------------------------------------------ leg (pivot: hip joint)
l = Part("leg")
l.lathe([(0.04, 0.098, 0.098), (-0.3, 0.09, 0.09), (-0.6, 0.084, 0.084), (-0.72, 0.082, 0.082)], "denim", seg=12, cap_top=False)
l.box((0.0, -0.36, 0.09), (0.004, 0.6, 0.004), "denim_dk")
l.lathe([(-0.725, 0.094, 0.094), (-0.79, 0.094, 0.094)], "denim_lt", seg=12)                       # rolled cuff
l.lathe([(-0.735, 0.0955, 0.0955), (-0.74, 0.0955, 0.0955)], "denim", seg=12, cap_top=False, cap_bot=False)
l.box((0, -0.835, 0.0), (0.135, 0.11, 0.17), "boot", 0.04, segs=3)                                  # boot shaft/heel
l.box((0, -0.86, 0.085), (0.13, 0.075, 0.15), "boot", 0.035, segs=3)                                # toe
l.box((0, -0.892, 0.035), (0.148, 0.036, 0.3), "sole", 0.012)
l.box((0, -0.875, -0.085), (0.142, 0.06, 0.07), "sole", 0.01)
l.box((0, -0.8, 0.066), (0.06, 0.07, 0.012), "boot_dk", 0.005, rot=gRx(-0.35))                      # tongue
for k in range(4):
	l.box((0, -0.79 - k * 0.017, 0.072 + k * 0.022), (0.076, 0.008, 0.008), "lace")
leg = l.finish()

# ------------------------------------------------------------------ cane (pivot: in the hand)
c = Part("cane")
c.tube((0, 0, 0), (0, -0.9, 0), 0.016, 0.015, "wood", 8)
c.tube((0, -0.9, 0), (0, -0.96, 0), 0.02, 0.02, "rubber", 8)
prev = (0, 0, 0)
for k in range(1, 7):
	a = k * math.pi / 6
	q = (0, math.sin(a) * 0.05, 0.05 - math.cos(a) * 0.05)
	c.tube(prev, q, 0.017, 0.017, "wood", 8); prev = q
cane = c.finish()

# ------------------------------------------------------------------ report and export
tris = 0
for ob in (torso, head, upper, fore, leg, cane):
	me = ob.data; me.calc_loop_triangles(); tris += len(me.loop_triangles)
	print("PART", ob.name, len(me.loop_triangles), "tris")
print("TOTAL TRIS (one of each part)", tris, " whole figure ~", tris + len(upper.data.loop_triangles) + len(fore.data.loop_triangles) + len(leg.data.loop_triangles))
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False, export_apply=True,
	export_yup=True, export_texcoords=True, export_normals=True, export_materials="EXPORT", export_image_format="AUTO")
print("EXPORTED", OUT)

# ------------------------------------------------------------------ previews: assemble him standing and render a turnaround
if PREV:
	def place(ob, at, rot=None):
		d = ob.copy(); d.data = ob.data; d.hide_render = False; bpy.context.collection.objects.link(d)
		d.matrix_world = Matrix.Translation(G(*at)) @ (rot or Matrix()); return d
	for ob in (torso, head, upper, fore, leg, cane): ob.hide_render = True
	HIP = 0.92
	place(torso, (0, HIP, 0), gRx(0.08))
	place(head, (0, HIP + 0.575, 0.045), gRx(-0.05))
	for sx in (-1, 1):
		place(leg, (sx * 0.1, HIP, 0))
		sh = (sx * 0.25, HIP + 0.5, 0.04)
		place(upper, sh, gRz(sx * 0.13))
		el = Vector(G(*sh)) + (gRz(sx * 0.13).to_3x3() @ G(0, -0.3, 0))
		pf = place(fore, (el.x, el.z, -el.y), gRz(sx * 0.1) @ gRx(-0.22))
	# ground, sky, sun and fill
	bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
	gm = bpy.data.materials.new("ground"); gm.use_nodes = True
	gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*[srgb2lin(c) for c in hex2rgb("#6b8a4a")], 1)
	bpy.context.object.data.materials.append(gm)
	w = bpy.data.worlds.new("w"); bpy.context.scene.world = w; w.use_nodes = True
	w.node_tree.nodes["Background"].inputs["Color"].default_value = (*[srgb2lin(c) for c in hex2rgb("#9fb3bd")], 1)
	w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
	bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(-35)))
	bpy.context.object.data.energy = 3.0; bpy.context.object.data.angle = math.radians(12)
	sc = bpy.context.scene; sc.render.engine = "CYCLES"; sc.cycles.samples = 24; sc.cycles.device = "CPU"
	sc.cycles.use_denoising = True
	sc.view_settings.view_transform = "Standard"
	sc.render.resolution_x = 360; sc.render.resolution_y = 640
	cam_data = bpy.data.cameras.new("cam"); cam_data.lens = 85
	cam = bpy.data.objects.new("cam", cam_data); bpy.context.collection.objects.link(cam); sc.camera = cam
	views = [("front", 0.0, 6.0, 0.95), ("34", 0.7, 6.0, 0.95), ("side", math.pi / 2, 6.0, 0.95), ("back", math.pi, 6.0, 0.95)]
	for name, ang, dist, ty in views:
		tgt = G(0, ty, 0)
		pos = G(math.sin(ang) * dist, ty + 0.15, math.cos(ang) * dist)
		cam.location = pos
		cam.rotation_euler = (tgt - pos).to_track_quat("-Z", "Y").to_euler()
		sc.render.filepath = os.path.join(PREV, "earl-%s.png" % name)
		bpy.ops.render.render(write_still=True)
	# head close-ups
	sc.render.resolution_x = 360; sc.render.resolution_y = 360
	for name, ang in (("head1", 0.0), ("head2", 0.55), ("head3", 1.25)):
		tgt = G(0, HIP + 0.75, 0.04)
		pos = G(math.sin(ang) * 1.6, HIP + 0.8, math.cos(ang) * 1.6)
		cam.location = pos; cam.rotation_euler = (tgt - pos).to_track_quat("-Z", "Y").to_euler()
		sc.render.filepath = os.path.join(PREV, "earl-%s.png" % name)
		bpy.ops.render.render(write_still=True)
	print("PREVIEWS", PREV)
