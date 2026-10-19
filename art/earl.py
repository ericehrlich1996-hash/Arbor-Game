# Earl as ONE continuous, skinned character (replaces the part-by-part earl.py).
#  - the body (torso, arms, legs) is a single surface grown from a stick skeleton (Skin modifier) and smoothed
#  - clothing is draped onto that surface by ray-casting (bib, straps, belt, pockets, cuffs, collar)
#  - gloves, boots, head, beard, hair and hat are each one fused solid (voxel remesh of their volumes)
#  - everything is skinned to an armature whose joints match scripts/earl.gd's rig
# Run: blender -b --factory-startup -P earl.py -- <out.glb> [preview_dir]
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from charkit import *
import bpy, bmesh
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

PAL = {
	"skin": "#eab08c", "skin_dk": "#d89878", "nose": "#e5876a", "cheek": "#e39a82", "eye": "#141414",
	"beard": "#ece8de", "hair": "#cfcabf",
	"hat": "#46602b", "hat_dk": "#384e22", "band": "#5a3a22", "leaf": "#d88a2a", "leaf2": "#e2b03a",
	"denim": "#3d5a86", "denim_dk": "#33507a", "denim_lt": "#6b89b6", "stitch": "#c9a256",
	"brass": "#c9a24a", "leather": "#6a4426", "leather_dk": "#53341c", "patch": "#8a5a30",
	"glove": "#a8833a", "glove_dk": "#8a6a2c", "cuff": "#b03a30",
	"boot": "#7a4c28", "boot_dk": "#5e3b1f", "sole": "#2a2420", "lace": "#d8bf86",
	"wood": "#6a4a2a", "rubber": "#1e1e1e", "red_dk": "#7a2420",
}
RED = hex2rgb("#a8302a"); BLK = hex2rgb("#2a1a1a"); MID = [RED[i] * 0.5 + BLK[i] * 0.5 for i in range(3)]
def buffalo(x, y, n):
	sx = (x // 32) % 2 == 0; sy = (y // 32) % 2 == 0
	c = BLK if (sx and sy) else (MID if (sx or sy) else RED)
	k = 0.95 + 0.05 * (((x + y) // 2) % 2)
	return [c[0] * k, c[1] * k, c[2] * k]

kit = Kit("earl", PAL, buffalo, cloth_n=128)
ARGS = ARGV

def Gv(x, y, z): return Vector((x, -z, y))                        # a game-space direction in Blender space
def gam(v): return Vector((v.x, v.z, -v.y))                       # Blender point -> game space
def dg(): return bpy.context.evaluated_depsgraph_get()
def link(ob): bpy.context.collection.objects.link(ob); return ob

def bake(ob):
	"""the object's evaluated mesh (all modifiers applied) as a new mesh datablock; the object is removed"""
	me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg()))
	bpy.data.objects.remove(ob)
	return me

def paint(me, fn):
	"""colour a mesh face by face: fn(centre_game, normal_game) -> swatch name, or ('cloth', uv_fn) where
	uv_fn(point_game) -> (u, v). Writes the UV layer "UV" and material indices (0 palette, 1 cloth)"""
	bm = bmesh.new(); bm.from_mesh(me)
	uv = bm.loops.layers.uv.get("UV") or bm.loops.layers.uv.new("UV")
	for f in bm.faces:
		f.smooth = True
		r = fn(gam(f.calc_center_median()), gam(f.normal) - gam(Vector()))
		if isinstance(r, tuple):
			f.material_index = 1
			us = []
			for l in f.loops:
				u, v = r[1](gam(l.vert.co)); l[uv].uv = (u, v); us.append(u)
			if max(us) - min(us) > 0.5 * r[2]:                  # seam: unwrap
				for l in f.loops:
					if l[uv].uv.x < (max(us) + min(us)) / 2: l[uv].uv.x += r[2]
		else:
			f.material_index = 0
			u, v = kit.swatch_uv(r)
			for l in f.loops: l[uv].uv = (u, v)
	# keep only our UV layer
	for name in [l.name for l in bm.loops.layers.uv if l.name != "UV"]: bm.loops.layers.uv.remove(bm.loops.layers.uv[name])
	bm.to_mesh(me); bm.free()
	return me

def solid(name, build, voxel, keep, painter):
	"""build(part) adds volumes; they're fused into one closed surface (voxel remesh), thinned, painted"""
	p = kit.part("_" + name); build(p)
	me = bpy.data.meshes.new(name); p.bm.to_mesh(me); p.bm.free()
	ob = link(bpy.data.objects.new(name, me))
	r = ob.modifiers.new("fuse", "REMESH"); r.mode = "VOXEL"; r.voxel_size = voxel; r.use_smooth_shade = True
	if keep < 1.0:
		d = ob.modifiers.new("thin", "DECIMATE"); d.ratio = keep
	me = bake(ob)
	return paint(me, painter if callable(painter) else (lambda c, n, s=painter: s))

def plain(name, build):
	"""small hard-surface bits (buttons, buckle, laces) kept as built, smooth-shaded"""
	p = kit.part("_" + name); build(p)
	kit.parts.pop("_" + name, None)
	for f in p.bm.faces: f.smooth = True
	me = bpy.data.meshes.new(name); p.bm.to_mesh(me); p.bm.free()
	return me

# ================================================================== 1. the body: one surface
# a stick skeleton in game space: (position, radius); the Skin modifier wraps it in one mesh
J = {
	"pelvis": ((0, 0.86, 0.0), 0.2), "waist": ((0, 1.0, 0.006), 0.225), "belly": ((0, 1.15, 0.012), 0.24),
	"chest": ((0, 1.29, 0.0), 0.245), "upper": ((0, 1.41, -0.008), 0.215), "neck0": ((0, 1.5, 0.0), 0.085),
	"neck1": ((0, 1.6, 0.012), 0.066),
}
E = [("pelvis", "waist"), ("waist", "belly"), ("belly", "chest"), ("chest", "upper"), ("upper", "neck0"), ("neck0", "neck1")]
for s, sx in (("l", 1), ("r", -1)):
	J["sho_" + s] = ((sx * 0.2, 1.425, 0.0), 0.095)
	J["arm_" + s] = ((sx * 0.245, 1.33, 0.0), 0.086)
	J["elb_" + s] = ((sx * 0.258, 1.12, 0.006), 0.07)
	J["wri_" + s] = ((sx * 0.262, 0.88, 0.02), 0.06)
	J["hip_" + s] = ((sx * 0.105, 0.8, 0.0), 0.125)
	J["kne_" + s] = ((sx * 0.11, 0.5, 0.006), 0.112)
	J["ank_" + s] = ((sx * 0.11, 0.2, 0.0), 0.106)
	J["foot_" + s] = ((sx * 0.11, 0.06, 0.0), 0.104)          # runs on into the boot, so the jeans stay straight
	E += [("upper", "sho_" + s), ("sho_" + s, "arm_" + s), ("arm_" + s, "elb_" + s), ("elb_" + s, "wri_" + s),
		("pelvis", "hip_" + s), ("hip_" + s, "kne_" + s), ("kne_" + s, "ank_" + s), ("ank_" + s, "foot_" + s)]
names = list(J.keys())
me = bpy.data.meshes.new("body")
me.from_pydata([G(*J[k][0]) for k in names], [(names.index(a), names.index(b)) for a, b in E], [])
ob = link(bpy.data.objects.new("body", me))
sk = ob.modifiers.new("skin", "SKIN"); sk.branch_smoothing = 0.7; sk.use_smooth_shade = True
for i, k in enumerate(names):
	sv = me.skin_vertices[0].data[i]; sv.radius = (J[k][1], J[k][1])
	if k == "pelvis": sv.use_root = True
sub = ob.modifiers.new("smooth", "SUBSURF"); sub.levels = 2; sub.render_levels = 2
body = bake(ob)
# a person is wider than deep: flatten the trunk front-to-back (not the arms), keep a little belly
bm = bmesh.new(); bm.from_mesh(body)
for v in bm.verts:
	g = gam(v.co)
	if 0.7 < g.y < 1.62:
		ax = abs(g.x)
		k = 1.0 - 0.22 * max(0.0, min(1.0, (0.25 - ax) / 0.08))           # 0.78 in the trunk, 1 out at the arms
		if g.y < 0.84: k = 1.0 - (1.0 - k) * max(0.0, (g.y - 0.7) / 0.14)   # fade out down the thighs
		if g.y > 1.48: k = 1.0 - (1.0 - k) * max(0.0, (1.62 - g.y) / 0.14)  # and up the neck
		gz = g.z * k + (0.012 if 0.95 < g.y < 1.25 and g.z > 0 else 0.0)
		v.co = G(g.x, g.y, gz)
bm.normal_update(); bm.to_mesh(body); bm.free()

# what's what on the body: legs and the seat are denim (the overalls), arms and chest are the shirt
ARM = {}
for s, sx in (("l", 1), ("r", -1)):
	a = Vector((sx * 0.215, 1.425, 0.0)); b = Vector((sx * 0.262, 0.88, 0.02))
	ARM[s] = (a, (b - a).normalized(), (b - a).length)
def arm_of(p):
	for s, (a, d, L) in ARM.items():
		t = (p - a).dot(d)
		if -0.06 < t < L + 0.05 and (p - (a + d * t)).length < 0.1 and abs(p.x) > 0.17: return s, t
	return None, 0.0
def check_uv(axis_o, axis_d, ref, per_turn, per_m):
	side = axis_d.cross(ref).normalized(); fwd = side.cross(axis_d).normalized()
	def uvf(p):
		q = p - axis_o; t = q.dot(axis_d); r = q - axis_d * t
		return (math.atan2(r.dot(side), r.dot(fwd)) / (2 * math.pi) * per_turn, t * per_m)
	return uvf
TORSO_UV = check_uv(Vector((0, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)), 5.0, 7.5)
ARM_UV = {s: check_uv(a, d, Vector((0, 0, 1)), 2.0, 7.5) for s, (a, d, L) in ARM.items()}
def body_paint(c, n):
	s, t = arm_of(c)
	if s: return ("cloth", ARM_UV[s], 2.0)
	if c.y < 1.06: return "denim"
	return ("cloth", TORSO_UV, 5.0)
paint(body, body_paint)
body_ob = link(bpy.data.objects.new("body_ref", body))
BVH = BVHTree.FromObject(body_ob, dg())

def hit(o, d):
	loc, nrm, i, dist = BVH.ray_cast(G(*o), Gv(*d).normalized())
	return (loc, nrm) if loc is not None else (None, None)

# ================================================================== 2. clothing draped on the body
def drape(name, nu, nv, ray, offset, thick, color, wrap=False):
	"""a sheet over the body: ray(u, v) -> (origin, dir) in game space for each grid point (u, v in 0..1);
	each lands on the body, lifted off it by `offset`, then given thickness"""
	b = bmesh.new()
	grid = []
	for j in range(nv + 1):
		row = []
		for i in range(nu + (0 if wrap else 1)):
			o, d = ray(i / nu, j / nv)
			loc, nrm = hit(o, d)
			if loc is None: loc, nrm = G(*o) + Gv(*d).normalized() * 0.3, -Gv(*d).normalized()
			row.append(b.verts.new(loc + nrm * offset))
		grid.append(row)
	cols = nu if wrap else nu + 1
	for j in range(nv):
		for i in range(nu):
			i2 = (i + 1) % cols
			b.faces.new((grid[j][i], grid[j][i2], grid[j + 1][i2], grid[j + 1][i]))
	bmesh.ops.recalc_face_normals(b, faces=b.faces)
	bmesh.ops.solidify(b, geom=list(b.faces), thickness=thick)
	me = bpy.data.meshes.new(name); b.to_mesh(me); b.free()
	return paint(me, lambda c, n: color)

def front(x0, x1, y0, y1, z=0.6): return lambda u, v: ((x0 + (x1 - x0) * u, y0 + (y1 - y0) * v, z), (0, 0, -1))
def back(x0, x1, y0, y1): return lambda u, v: ((x0 + (x1 - x0) * u, y0 + (y1 - y0) * v, -0.6), (0, 0, 1))
def ring_y(y0, y1, cx=0.0, cz=0.0):
	# cast from the middle of the trunk outward: lands on the trunk's own wall, never on an arm
	return lambda u, v: ((cx, y0 + (y1 - y0) * v, cz), (math.sin(u * 2 * math.pi), 0, math.cos(u * 2 * math.pi)))
def ring_axis(a, d, t0, t1):
	d = d.normalized(); side = d.cross(Vector((0, 0, 1))).normalized(); fwd = side.cross(d).normalized()
	def f(u, v):
		t = t0 + (t1 - t0) * v; ang = u * 2 * math.pi
		out = fwd * math.cos(ang) + side * math.sin(ang)
		o = a + d * t
		return ((o.x, o.y, o.z), (out.x, out.y, out.z))
	return f

pieces = []        # (mesh, bone or None for computed weights)
pieces.append((body, None))
# the bib, its pocket and patch, sitting on the chest
pieces.append((drape("bib", 10, 10, front(-0.165, 0.165, 1.05, 1.37), 0.004, 0.012, "denim"), "torso"))
pieces.append((drape("bib_pocket", 6, 5, front(-0.075, 0.075, 1.17, 1.29), 0.017, 0.005, "denim_dk"), "torso"))
pieces.append((drape("patch", 2, 2, front(-0.024, 0.024, 1.205, 1.255), 0.023, 0.004, "patch"), "torso"))
pieces.append((drape("patch_leaf", 1, 1, front(-0.008, 0.008, 1.218, 1.242), 0.027, 0.003, "leaf"), "torso"))
# straps: from the bib's top corners, over the shoulders, crossing down the back
def strap(sx):
	# guide points in game space, from the bib's corner up over the shoulder and crossing down the back
	guide = [Vector(p) for p in [(sx * 0.112, 1.36, 0.17), (sx * 0.122, 1.45, 0.14), (sx * 0.13, 1.52, 0.07), (sx * 0.132, 1.55, 0.0),
		(sx * 0.13, 1.52, -0.07), (sx * 0.12, 1.44, -0.13), (sx * 0.06, 1.33, -0.17), (0.0, 1.26, -0.18),
		(-sx * 0.06, 1.19, -0.18), (-sx * 0.105, 1.08, -0.17)]]
	pts = []
	for k in range(len(guide) - 1):
		for q in range(3): pts.append(guide[k].lerp(guide[k + 1], q / 3))
	pts.append(guide[-1])
	def ray(u, v):
		i = min(int(round(v * (len(pts) - 1))), len(pts) - 1)
		p = pts[i]; nxt = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
		ctr = Vector((0, min(p.y, 1.36), 0)); out = (p - ctr).normalized()
		across = nxt.cross(out).normalized()
		q = p + across * (u - 0.5) * 0.046
		o = q + out * 0.35
		return ((o.x, o.y, o.z), (-out.x, -out.y, -out.z))
	return drape("strap", 1, len(pts) - 1, ray, 0.006, 0.008, "denim")
for sx in (1, -1): pieces.append((strap(sx), "torso"))
# belt, back pockets, collar
pieces.append((drape("belt", 32, 2, ring_y(1.035, 1.085), 0.004, 0.012, "leather"), "torso"))
for sx in (1, -1):
	pieces.append((drape("back_pocket", 4, 4, back(sx * 0.035, sx * 0.15, 0.93, 1.03) if sx > 0 else back(sx * 0.15, sx * 0.035, 0.93, 1.03), 0.004, 0.006, "denim_dk"), "torso"))
pieces.append((drape("collar", 20, 2, ring_y(1.5, 1.57, 0.0, 0.004), 0.006, 0.012, "red_dk"), "torso"))
# rolled cuffs: sleeves at the wrist, jeans at the ankle
for s, sx in (("l", 1), ("r", -1)):
	a, d, L = ARM[s]
	pieces.append((drape("sleeve_cuff", 16, 2, ring_axis(a, d, L - 0.09, L - 0.015), 0.008, 0.016, "cuff"), "fore_" + s))
	pieces.append((drape("jean_cuff", 16, 2, ring_axis(Vector((sx * 0.11, 0.5, 0.0)), Vector((0, -1, 0)), 0.29, 0.36), 0.008, 0.018, "denim_lt"), "leg_" + s))

# hardware: brass buttons on the strap ends, side buttons, the buckle, the pouch
def on_body(o, d, lift=0.0):
	loc, nrm = hit(o, d); return gam(loc + nrm * lift)
def hardware(p):
	for sx in (1, -1):
		c = on_body((sx * 0.112, 1.345, 0.6), (0, 0, -1), 0.02)
		p.ball((c.x, c.y, c.z), (0.02, 0.02, 0.011), "brass", 10, 6)
		c = on_body((0.0, 1.0, 0.07), (sx, 0, 0), 0.008)
		p.ball((c.x, c.y, c.z), (0.008, 0.014, 0.012), "brass", 8, 5)
	c = on_body((0, 1.06, 0.6), (0, 0, -1), 0.016)
	p.box((c.x, c.y, c.z), (0.052, 0.044, 0.012), "brass", 0.005)
	p.box((c.x, c.y, c.z + 0.005), (0.03, 0.024, 0.008), "leather_dk", 0.003)
	c = on_body((0.0, 0.98, 0.06), (1, 0, 0), 0.034)
	p.box((c.x, c.y, c.z), (0.06, 0.12, 0.09), "leather", 0.018)
	p.box((c.x, c.y + 0.055, c.z), (0.066, 0.032, 0.096), "leather_dk", 0.01)
	# a shirt placket and collar points above the bib
	c = on_body((0, 1.44, 0.6), (0, 0, -1), 0.003)
	p.box((c.x, c.y, c.z), (0.026, 0.11, 0.008), "red_dk", 0.003)
	for k in range(2): p.ball((c.x, c.y - 0.03 + k * 0.05, c.z + 0.006), (0.008, 0.008, 0.005), "beard", 6, 4)
	for sx in (1, -1):
		c = on_body((sx * 0.045, 1.54, 0.6), (0, 0, -1), 0.012)
		p.box((c.x, c.y, c.z), (0.07, 0.014, 0.05), "red_dk", 0.006, rot=gRz(sx * 0.6) @ gRx(0.6))
pieces.append((plain("hardware", hardware), "torso"))

# ================================================================== 3. gloves: one fused fist each
def glove(sx):
	o = Vector((sx * 0.264, 0.86, 0.022))            # the wrist
	K = 1.3                                            # big work gloves
	def build(p):
		def P(x, y, z): return (o.x + sx * x * K, o.y + y * K, o.z + z * K)
		p.lathe([(o.y + 0.035, 0.06, 0.062), (o.y - 0.03, 0.058, 0.06)], "glove", seg=12, x=o.x, z=o.z, hold=False)  # gauntlet
		p.box(P(0.0, -0.065, 0.004), (0.062 * K, 0.085 * K, 0.096 * K), "glove", 0.022)          # back of the hand / palm
		for i in range(4):                                                                       # curled fingers
			z = -0.034 + i * 0.023
			p.tube(P(0.006, -0.1, z), P(-0.012, -0.125, z), 0.0135 * K, 0.013 * K, "glove", 8, True)
			p.tube(P(-0.012, -0.125, z), P(-0.032, -0.108, z), 0.013 * K, 0.012 * K, "glove", 8, True)
		p.tube(P(-0.022, -0.045, 0.045), P(-0.036, -0.088, 0.05), 0.015 * K, 0.013 * K, "glove", 8, True)   # thumb
	def col(c, n):
		return "glove_dk" if c.y > o.y - 0.02 else "glove"
	return solid("glove", build, 0.005, 0.1, col)
for s, sx in (("l", 1), ("r", -1)): pieces.append((glove(sx), "fore_" + s))

# ================================================================== 4. boots: one fused boot, a sole, laces
def boot(sx):
	x = sx * 0.11
	def build(p):
		p.lathe([(0.06, 0.095, 0.1), (0.17, 0.092, 0.096)], "boot", seg=14, x=x, z=-0.005, hold=False)      # shaft
		p.box((x, 0.06, 0.035), (0.15, 0.11, 0.25), "boot", 0.045)                                          # foot
		p.ball((x, 0.058, 0.135), (0.075, 0.055, 0.08), "boot", 12, 8)                                       # round toe
	def col(c, n):
		return "boot_dk" if (c.z > 0.03 and c.y > 0.07 and abs(c.x - x) < 0.03) else "boot"
	return solid("boot", build, 0.007, 0.12, col)
def soles(p):
	for sx in (1, -1):
		x = sx * 0.105
		p.box((x, 0.016, 0.035), (0.148, 0.032, 0.29), "sole", 0.01)
		for k in range(4): p.box((x, 0.12 - k * 0.016, 0.06 + k * 0.022), (0.074, 0.009, 0.011), "lace", 0.003)
for s, sx in (("l", 1), ("r", -1)): pieces.append((boot(sx), "leg_" + s))
sole_l = plain("soles_l", lambda p: [p.box((0.11, 0.016, 0.04), (0.168, 0.034, 0.32), "sole", 0.01)] + [p.box((0.11, 0.13 - k * 0.017, 0.085 + k * 0.024), (0.08, 0.01, 0.012), "lace", 0.003) for k in range(4)])
sole_r = plain("soles_r", lambda p: [p.box((-0.11, 0.016, 0.04), (0.168, 0.034, 0.32), "sole", 0.01)] + [p.box((-0.11, 0.13 - k * 0.017, 0.085 + k * 0.024), (0.08, 0.01, 0.012), "lace", 0.003) for k in range(4)])
pieces.append((sole_l, "leg_l")); pieces.append((sole_r, "leg_r"))

# ================================================================== 5. head: face, beard, hair, hat
HS = 1.26; HY = 1.49
def H(x, y, z): return (x * HS, HY + y * HS, z * HS)
def HR(r): return (r[0] * HS, r[1] * HS, r[2] * HS)
NOSE = Vector(H(0, 0.146, 0.122)); EARS = [Vector(H(sx * 0.11, 0.163, -0.006)) for sx in (1, -1)]
CHEEKS = [Vector(H(sx * 0.066, 0.15, 0.09)) for sx in (1, -1)]
def face(p):
	p.ball(H(0, 0.168, 0.0), HR((0.114, 0.126, 0.114)), "skin", 16, 10)
	p.tube(H(0, 0.0, 0.0), H(0, 0.09, 0.01), 0.07 * HS, 0.066 * HS, "skin", 10, True)
	p.ball(tuple(NOSE), HR((0.037, 0.035, 0.034)), "nose", 12, 8)
	for e in EARS: p.ball(tuple(e), HR((0.022, 0.037, 0.03)), "skin", 10, 6)
def face_col(c, n):
	if (c - NOSE).length < 0.045 * HS: return "nose"
	for e in EARS:
		if (c - e).length < 0.03 * HS: return "skin_dk"
	for ch in CHEEKS:
		if (c - ch).length < 0.025 * HS and n.z > 0.3: return "cheek"
	return "skin"
pieces.append((solid("face", face, 0.005, 0.12, face_col), "head"))
def beard(p):
	p.ball(H(0, 0.06, 0.05), HR((0.112, 0.105, 0.085)), "beard", 14, 10)
	p.ball(H(0, -0.01, 0.07), HR((0.08, 0.07, 0.065)), "beard", 12, 8)
	for sx in (1, -1):
		p.ball(H(sx * 0.09, 0.11, 0.03), HR((0.034, 0.068, 0.06)), "beard", 10, 6)           # sideburns
		p.ball(H(sx * 0.042, 0.114, 0.112), HR((0.05, 0.022, 0.028)), "beard", 10, 6, rot=gRz(sx * 0.2))   # moustache
pieces.append((solid("beard", beard, 0.006, 0.12, "beard"), "head"))
def hair(p):
	p.ball(H(0, 0.16, -0.045), HR((0.12, 0.09, 0.095)), "hair", 14, 8)
	for sx in (1, -1): p.ball(H(sx * 0.1, 0.16, -0.01), HR((0.035, 0.06, 0.06)), "hair", 10, 6)
pieces.append((solid("hair", hair, 0.007, 0.15, "hair"), "head"))
def eyes(p):
	for sx in (1, -1):
		p.ball(H(sx * 0.043, 0.19, 0.101), HR((0.014, 0.019, 0.01)), "eye", 10, 6)
		p.box(H(sx * 0.045, 0.218, 0.103), (0.055, 0.02, 0.028), "beard", 0.008, rot=gRz(-sx * 0.1))     # brows
pieces.append((plain("eyes", eyes), "head"))
BAND = (HY + 0.24 * HS, HY + 0.275 * HS)
def hat(p):
	p.lathe([(HY + y * HS, rx * HS, rz * HS) for (y, rx, rz) in [(0.228, 0.13, 0.136), (0.3, 0.124, 0.13), (0.356, 0.112, 0.117), (0.386, 0.08, 0.085), (0.396, 0.03, 0.035)]], "hat", seg=16)
	p.lathe([(HY + y * HS, rx * HS, rz * HS) for (y, rx, rz) in [(0.226, 0.13, 0.136), (0.234, 0.2, 0.21), (0.246, 0.2, 0.21), (0.254, 0.13, 0.136)]], "hat", seg=20)
def hat_col(c, n):
	return "hat_dk" if n.y < -0.5 else "hat"
pieces.append((solid("hat", hat, 0.006, 0.09, hat_col), "head"))
def band(p):
	p.lathe([(BAND[0], 0.133 * HS, 0.139 * HS), (BAND[1], 0.128 * HS, 0.134 * HS)], "band", seg=20)
pieces.append((plain("band", band), "head"))
def leaves(p):
	for k, lc in enumerate(("leaf", "leaf2")):
		rot = gRy(-0.5 - k * 0.25) @ gRz(-0.35 - k * 0.3)
		p.ball(H(0.122 - k * 0.012, 0.322 + k * 0.01, 0.035 - k * 0.03), (0.008, 0.046, 0.022), lc, 8, 5, rot=rot)
pieces.append((plain("leaves", leaves), "head"))

# ================================================================== 6. armature (joints as scripts/earl.gd) and skinning
BONES = [("hips", None, (0, 0.92, 0), (0, 0.97, 0)), ("torso", "hips", (0, 0.92, 0), (0, 1.5, 0)), ("head", "torso", (0, 1.5, 0), (0, 1.8, 0))]
for s, sx in (("l", 1), ("r", -1)):
	BONES += [("upper_" + s, "torso", (sx * 0.25, 1.42, 0), (sx * 0.25, 1.12, 0)), ("fore_" + s, "upper_" + s, (sx * 0.25, 1.12, 0), (sx * 0.25, 0.82, 0)),
		("leg_" + s, "hips", (sx * 0.1, 0.92, 0), (sx * 0.1, 0.02, 0))]
arm_data = bpy.data.armatures.new("rig"); rig = link(bpy.data.objects.new("rig", arm_data))
bpy.context.view_layer.objects.active = rig; bpy.ops.object.mode_set(mode="EDIT")
for name, parent, h0, t0 in BONES:
	eb = arm_data.edit_bones.new(name); eb.head = G(*h0); eb.tail = G(*t0); eb.roll = 0.0
	if parent: eb.parent = arm_data.edit_bones[parent]
bpy.ops.object.mode_set(mode="OBJECT")
SEG = {n: (Vector(h0), Vector(t0)) for n, p, h0, t0 in BONES if n != "hips"}
def seg_d(p, a, b):
	ab = b - a; t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared)); return (p - (a + ab * t)).length
def ramp(x, a, b): return max(0.0, min(1.0, (x - a) / (b - a)))
def body_weights(g):
	"""by distance to each bone, but a limb only pulls on what's actually that limb: the arms on what's out
	past the side of the chest (blending in over the shoulder), the legs on what's below the seat"""
	w = {}
	for n, (a, b) in SEG.items():
		x = 1.0 / (seg_d(g, a, b) + 0.012) ** 3
		if n.startswith(("upper", "fore")):
			sx = 1 if n.endswith("_l") else -1
			x *= ramp(g.x * sx, 0.15, 0.215)
		if n.startswith("leg"):
			sx = 1 if n.endswith("_l") else -1
			x *= ramp(0.9 - g.y, 0.0, 0.12) * ramp(g.x * sx, -0.02, 0.04)
		if n == "head": x *= ramp(g.y, 1.5, 1.58)
		w[n] = x
	top = sorted(w.items(), key=lambda kv: -kv[1])[:3]
	tot = sum(x for _, x in top) or 1.0
	return [(n, x / tot) for n, x in top if x > 0]

final = bmesh.new()
uvl = final.loops.layers.uv.new("UV"); dl = final.verts.layers.deform.verify()
groups = [b[0] for b in BONES]
for me_p, bone in pieces:
	start = len(final.verts)
	final.from_mesh(me_p)
	final.verts.ensure_lookup_table()
	for v in final.verts[start:]:
		if bone: v[dl][groups.index(bone)] = 1.0
		else:
			for n, w in body_weights(gam(v.co)): v[dl][groups.index(n)] = w
final.verts.ensure_lookup_table()
me_all = bpy.data.meshes.new("earl"); final.to_mesh(me_all); final.free()
me_all.materials.append(kit.palette); me_all.materials.append(kit.cloth)
earl_ob = link(bpy.data.objects.new("earl", me_all))
for g in groups: earl_ob.vertex_groups.new(name=g)
earl_ob.parent = rig
md = earl_ob.modifiers.new("rig", "ARMATURE"); md.object = rig
bpy.data.objects.remove(body_ob)

# the walking stick: a separate, unskinned mesh with its pivot in the hand
def cane_build(p):
	p.tube((0, 0, 0), (0, -0.9, 0), 0.017, 0.016, "wood", 10)
	p.tube((0, -0.9, 0), (0, -0.96, 0), 0.021, 0.021, "rubber", 10)
	prev = (0, 0, 0)
	for k in range(1, 6):
		a = k * math.pi / 5; q = (0, math.sin(a) * 0.05, 0.05 - math.cos(a) * 0.05)
		p.tube(prev, q, 0.018, 0.018, "wood", 10); prev = q
cme = plain("cane", cane_build); cme.materials.append(kit.palette); cme.materials.append(kit.cloth)
cane_ob = link(bpy.data.objects.new("cane", cme))

me_all.calc_loop_triangles(); print("EARL TRIS", len(me_all.loop_triangles))
for me_p, bone in pieces:
	me_p.calc_loop_triangles(); print("  PIECE", me_p.name, len(me_p.loop_triangles))
if ARGS:
	for o in list(bpy.data.objects):
		if o.name not in ("earl", "rig", "cane"): bpy.data.objects.remove(o)
	bpy.ops.export_scene.gltf(filepath=ARGS[0], export_format="GLB", export_yup=True, export_skins=True,
		export_animations=False, export_texcoords=True, export_normals=True, export_materials="EXPORT")
	print("EXPORTED", ARGS[0])

# ================================================================== previews
if len(ARGS) > 1:
	PREV = ARGS[1]
	cane_ob.hide_render = True
	def pose(arms_out=0.12, wave=False):
		bpy.context.view_layer.objects.active = rig; bpy.ops.object.mode_set(mode="POSE")
		for pb in rig.pose.bones: pb.rotation_mode = "XYZ"; pb.rotation_euler = (0, 0, 0)
		for s, sx in (("l", 1), ("r", -1)):
			rig.pose.bones["upper_" + s].rotation_euler = (0, 0, sx * arms_out)
		if wave:
			rig.pose.bones["upper_l"].rotation_euler = (0, 0, 2.4)
			rig.pose.bones["fore_l"].rotation_euler = (0, 0, 0.6)
			rig.pose.bones["upper_r"].rotation_euler = (-0.7, 0, -0.1)
			rig.pose.bones["fore_r"].rotation_euler = (-1.2, 0, 0)
		bpy.ops.object.mode_set(mode="OBJECT")
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
	sc.cycles.use_denoising = True; sc.view_settings.view_transform = "Standard"
	cam = link(bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))); cam.data.lens = 85; sc.camera = cam
	def snap(name, tgt, pos, wh):
		sc.render.resolution_x, sc.render.resolution_y = wh
		cam.location = G(*pos); cam.rotation_euler = (G(*tgt) - G(*pos)).to_track_quat("-Z", "Y").to_euler()
		sc.render.filepath = os.path.join(PREV, "earl-%s.png" % name); bpy.ops.render.render(write_still=True)
	pose()
	for name, ang in (("front", 0.0), ("34", 0.7), ("side", math.pi / 2), ("back", math.pi)):
		snap(name, (0, 0.95, 0), (math.sin(ang) * 6.0, 1.1, math.cos(ang) * 6.0), (360, 640))
	for name, ang in (("head1", 0.0), ("head2", 0.55), ("head3", 1.25)):
		snap(name, (0, 1.68, 0.04), (math.sin(ang) * 1.6, 1.72, math.cos(ang) * 1.6), (360, 360))
	snap("hands", (0.25, 0.85, 0.02), (1.0, 0.95, 1.1), (360, 360))
	snap("shoulder", (0.2, 1.35, 0.0), (0.9, 1.45, 1.3), (360, 360))
	pose(wave=True)
	snap("wave", (0, 1.1, 0), (0.6, 1.2, 5.0), (360, 640))
	print("PREVIEWS", PREV)
