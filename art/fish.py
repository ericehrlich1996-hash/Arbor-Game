# The fish: every species as one continuous, lofted body with a hand-painted skin (its real markings),
# proper fins with rays, and eyes. Exported as one mesh per species, 1 m long (nose at +x 0.48, tail fin
# tip near -0.6), lying side-on along x, back up: the game scales each by the fish's length.
# Run: blender -b --factory-startup -P fish.py -- <out.glb> [preview_dir]
import bpy, bmesh, math, os, sys, random
import numpy as np
from mathutils import Vector, Matrix

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
HERE = os.path.dirname(os.path.abspath(__file__))
bpy.ops.wm.read_factory_settings(use_empty=True)

def G(x, y, z): return Vector((x, -z, y))          # game space -> Blender
def hexc(h): h = h.lstrip("#"); return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])
def smooth(a, b, x):
	t = np.clip((x - a) / (b - a), 0.0, 1.0); return t * t * (3 - 2 * t)

# ------------------------------------------------------------------ the species
# shape: deep = body height at its deepest (fraction of length), um = where (0 tail .. 1 nose), ped = tail
# root height, snout = height at the nose, wr = width/height, hump = how much the back arches
# fins: tail ("fork"/"round"/"pike"), dorsal ("bass" spiny+soft joined, "split" two, "perch" two apart,
# "back" one far back (pike), "trout" one + adipose, "chub" one), eye size, colours
S = {
	"Largemouth bass": dict(deep=0.27, um=0.58, ped=0.075, snout=0.09, wr=0.42, hump=0.2, tail="fork", dorsal="bass", eye=0.03,
		back="#2e4426", flank="#6f8a4a", belly="#e8e6cc", fin="#6a7a48", iris="#c9a640"),
	"Smallmouth bass": dict(deep=0.25, um=0.58, ped=0.075, snout=0.085, wr=0.42, hump=0.2, tail="fork", dorsal="bass", eye=0.03,
		back="#4a3e1e", flank="#8a7238", belly="#e2d6a8", fin="#7a6838", iris="#c83020"),
	"Bluegill": dict(deep=0.46, um=0.55, ped=0.09, snout=0.1, wr=0.3, hump=0.1, tail="fork", dorsal="bass", eye=0.035,
		back="#2c3e2e", flank="#5c7450", belly="#e8a040", fin="#4e5e44", iris="#3a3a30"),
	"Black crappie": dict(deep=0.42, um=0.52, ped=0.08, snout=0.08, wr=0.28, hump=0.25, tail="fork", dorsal="bass", eye=0.036,
		back="#3c3e36", flank="#a8a894", belly="#e6e6d8", fin="#4a4a40", iris="#c8b060"),
	"Rock bass": dict(deep=0.36, um=0.58, ped=0.09, snout=0.1, wr=0.36, hump=0.15, tail="fork", dorsal="bass", eye=0.038,
		back="#3a3020", flank="#7a6640", belly="#cdbb90", fin="#5a4a30", iris="#c02018"),
	"Yellow perch": dict(deep=0.23, um=0.6, ped=0.065, snout=0.065, wr=0.45, hump=0.35, tail="fork", dorsal="perch", eye=0.032,
		back="#4a5222", flank="#c8b440", belly="#ece6c8", fin="#d87830", iris="#c8b040"),
	"Walleye": dict(deep=0.19, um=0.6, ped=0.06, snout=0.06, wr=0.5, hump=0.1, tail="fork", dorsal="perch", eye=0.036,
		back="#4a4220", flank="#a08a48", belly="#ece8d8", fin="#7a6a3a", iris="#e8e0b8"),
	"Northern pike": dict(deep=0.14, um=0.4, ped=0.07, snout=0.035, wr=0.62, hump=0.0, tail="fork", dorsal="back", eye=0.026,
		back="#2c4024", flank="#5a7440", belly="#ece8c8", fin="#7a6838", iris="#c8b040"),
	"Muskellunge": dict(deep=0.14, um=0.4, ped=0.07, snout=0.035, wr=0.62, hump=0.0, tail="fork", dorsal="back", eye=0.024,
		back="#4a5236", flank="#9a9c74", belly="#ece6d4", fin="#8a6a40", iris="#c8b060"),
	"Brook trout": dict(deep=0.21, um=0.55, ped=0.08, snout=0.08, wr=0.5, hump=0.05, tail="round", dorsal="trout", eye=0.03,
		back="#2c3a24", flank="#5a6a3e", belly="#e07436", fin="#d06a30", iris="#c8b040"),
	"Creek chub": dict(deep=0.19, um=0.55, ped=0.07, snout=0.08, wr=0.55, hump=0.05, tail="fork", dorsal="chub", eye=0.028,
		back="#4a4e3e", flank="#8e9280", belly="#e4e2d6", fin="#8a8a76", iris="#c8c0a0"),
	"Gerald": dict(deep=0.29, um=0.58, ped=0.08, snout=0.095, wr=0.45, hump=0.25, tail="fork", dorsal="bass", eye=0.028,
		back="#1e2e1a", flank="#4a6234", belly="#ddd8bc", fin="#4a5434", iris="#d8b030"),
}
X0, X1 = -0.40, 0.48                      # peduncle .. nose along x

def prof(sp, u):
	"""body height and width at u (0 tail root .. 1 nose), and where the section's centre sits"""
	um, deep, ped, snout = sp["um"], sp["deep"], sp["ped"], sp["snout"]
	if u < um: h = ped + (deep - ped) * (1 - (1 - u / um) ** 2.2)
	else: h = deep - (deep - snout) * ((u - um) / (1 - um)) ** 1.7
	w = h * sp["wr"] * (1.0 + 0.25 * smooth(0.55, 0.85, u))          # a broad head
	if sp["dorsal"] == "back": w = max(w, 0.05 * (1 - (1 - u) ** 4) + h * 0.3 if u > 0.88 else w)   # a pike's flat bill
	cy = sp["hump"] * deep * 0.12 * math.sin(math.pi * u)             # the back arches more than the belly
	return h, w, cy

# ------------------------------------------------------------------ skin textures (u along the body, v round it)
TW, TH = 512, 256
FIN_V = 0.86                              # the bottom of the texture holds the fin rays and the eye
def paint(name, sp):
	rng = np.random.default_rng(abs(hash(name)) % 2 ** 31)
	u = np.linspace(0, 1, TW)[None, :]                        # 0 tail .. 1 nose
	v = np.linspace(0, 1, TH)[:, None]                        # 0 back (top), 0.5 belly, 1 back again
	vv = np.clip(v / FIN_V, 0, 1)
	hgt = np.cos(vv * 2 * math.pi)                            # +1 back .. -1 belly
	back, flank, belly = hexc(sp["back"]), hexc(sp["flank"]), hexc(sp["belly"])
	t1 = smooth(-0.75, 0.1, hgt)[..., None]; t2 = smooth(0.1, 0.85, hgt)[..., None]
	img = belly * (1 - t1) + flank * t1
	img = img * (1 - t2) + back * t2
	dark = back * 0.55
	def blend(mask, col, k=1.0):
		nonlocal img
		m = np.clip(mask, 0, 1)[..., None] * k
		img = img * (1 - m) + np.array(col) * m
	n = name if name != "Gerald" else "Largemouth bass"
	if n == "Largemouth bass":
		jag = 0.06 * np.sin(u * 60) + 0.04 * np.sin(u * 23 + 1)
		blend(smooth(0.2, 0.12, np.abs(hgt - 0.05 - jag)) * smooth(0.05, 0.15, u) * smooth(0.92, 0.78, u), hexc("#1a2414"), 0.85)
	if n == "Smallmouth bass":
		blend((np.sin(u * 70) > 0.45) * smooth(-0.4, -0.1, hgt) * smooth(0.9, 0.75, u), hexc("#3a2c14"), 0.6)
		blend(smooth(0.05, 0.0, np.abs(hgt + 0.0 - 0.2 * np.sin(u * 3))) * (u > 0.8), hexc("#3a2c14"), 0.5)
	if n in ("Bluegill",):
		blend((np.sin(u * 55) > 0.3) * smooth(-0.5, 0.0, hgt) * smooth(0.82, 0.7, u), dark, 0.35)
		blend(smooth(0.06, 0.03, np.hypot((u - 0.75) * 2.0, (hgt - 0.25) * 0.5)), hexc("#101018"))   # the black ear flap
	if n == "Black crappie":
		noise = rng.random((TH, TW)); from_bl = np.clip(noise * 1.0, 0, 1)
		blots = np.zeros((TH, TW))
		for k in range(90):
			cu, ch = rng.random(), rng.uniform(-0.6, 1.0); r = rng.uniform(0.012, 0.03)
			blots += smooth(r, r * 0.4, np.hypot(u - cu, (hgt - ch) * 0.12))
		blend(blots, hexc("#1e1e1a"), 0.85)
	if n == "Rock bass":
		for row in np.linspace(-0.5, 0.7, 6):
			blend(smooth(0.06, 0.02, np.abs(hgt - row)) * (np.sin(u * 90) > 0.2) * smooth(0.85, 0.7, u), hexc("#1e1810"), 0.7)
	if n == "Yellow perch":
		blend((np.sin(u * 44 + 1.0) > 0.2) * smooth(-0.6, -0.2, hgt) * smooth(0.04, 0.1, u) * smooth(0.82, 0.72, u), hexc("#2e3214"), 0.75)
	if n == "Walleye":
		noise = np.sin(u * 140 + np.sin(hgt * 9) * 3) * np.sin(hgt * 20 + u * 30)
		blend((noise > 0.4) * smooth(-0.3, 0.2, hgt), hexc("#3a3418"), 0.4)
		blend((np.sin(u * 30) > 0.6) * smooth(0.0, 0.4, hgt) * smooth(0.85, 0.7, u), hexc("#3a3418"), 0.45)
	if n == "Northern pike":
		spots = np.zeros((TH, TW))
		for row in np.linspace(-0.35, 0.65, 6):
			for cu in np.arange(0.02, 0.86, 0.045):
				cu2 = cu + rng.uniform(-0.01, 0.01) + (0.02 if int(row * 10) % 2 else 0)
				spots += smooth(0.016, 0.008, np.hypot((u - cu2) * 1.0, (hgt - row) * 0.09))
		blend(spots, hexc("#e8e0a0"), 0.9)
	if n == "Muskellunge":
		blend((np.sin(u * 70 + np.sin(hgt * 6) * 2) > 0.35) * smooth(-0.5, 0.0, hgt) * smooth(0.88, 0.75, u), hexc("#3e4228"), 0.65)
	if n == "Brook trout":
		worms = (np.sin(u * 180 + np.sin(hgt * 30) * 4) * np.sin(hgt * 40 + np.sin(u * 50) * 3)) > 0.45
		blend(worms * smooth(0.1, 0.4, hgt), hexc("#b8b070"), 0.7)
		for k in range(70):
			cu, ch = rng.uniform(0.08, 0.85), rng.uniform(-0.45, 0.25)
			blend(smooth(0.016, 0.01, np.hypot(u - cu, (hgt - ch) * 0.1)), hexc("#8ab0d0"), 0.9)
			blend(smooth(0.009, 0.004, np.hypot(u - cu, (hgt - ch) * 0.1)), hexc("#d02818"), 1.0)
	if n == "Creek chub":
		blend(smooth(0.1, 0.04, np.abs(hgt - 0.05)) * smooth(0.05, 0.15, u) * smooth(0.95, 0.85, u), hexc("#3a3c30"), 0.6)
	# gill cover line, a darker mouth line, a little shine down the back
	blend(smooth(0.008, 0.002, np.abs(u - (0.76 + 0.03 * np.cos(hgt * 1.4)))) * smooth(0.0, -0.8, -hgt * 0), hexc("#1a1a14"), 0.45)
	blend(smooth(0.05, 0.0, np.abs(hgt + 0.05)) * smooth(0.94, 0.98, u), hexc("#1a1410"), 0.6)
	if name == "Gerald":                                           # the old legend: a few pale scars
		for k in range(6):
			cu, ch = rng.uniform(0.3, 0.8), rng.uniform(-0.2, 0.6)
			blend(smooth(0.006, 0.0, np.abs((u - cu) * 0.8 + (hgt - ch) * 0.05)) * smooth(0.06, 0.03, np.abs(u - cu)), hexc("#c8c8b0"), 0.7)
	# fin band (rays) and the eye swatches, in the strip below FIN_V
	fin = hexc(sp["fin"])
	ray = 0.75 + 0.25 * (np.sin(u * 160) > 0)
	band = (v >= FIN_V)
	finimg = fin * ray[..., None] * np.ones((TH, TW, 1))
	if name == "Brook trout": finimg = np.where((u < 0.06)[..., None], hexc("#f4f0e8"), finimg)       # white leading edges
	img = np.where(band[..., None], finimg, img)
	img[-12:, :40] = hexc(sp["iris"]); img[-12:, 40:80] = hexc("#0c0c0c"); img[-12:, 80:120] = hexc("#f0ecdc")
	img = np.clip(img, 0, 1)
	im = bpy.data.images.new("fish_" + name.replace(" ", "_").lower(), TW, TH, alpha=False)
	rgba = np.concatenate([img, np.ones((TH, TW, 1))], axis=2)[::-1]     # Blender images start at the bottom row
	im.pixels = rgba.astype(np.float32).ravel()
	im.filepath_raw = os.path.join(HERE, "fish_tex", im.name + ".png"); im.file_format = "PNG"
	os.makedirs(os.path.join(HERE, "fish_tex"), exist_ok=True); im.save()
	return im
EYE_UV = {"iris": (20 / TW, 1 - 6 / TH), "pupil": (60 / TW, 1 - 6 / TH), "white": (100 / TW, 1 - 6 / TH)}

def material(name, img):
	m = bpy.data.materials.new("fish_" + name); m.use_nodes = True
	bsdf = m.node_tree.nodes["Principled BSDF"]
	tex = m.node_tree.nodes.new("ShaderNodeTexImage"); tex.image = img
	m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
	bsdf.inputs["Roughness"].default_value = 0.45
	return m

# ------------------------------------------------------------------ building one fish
def build(name, sp):
	bm = bmesh.new(); uvl = bm.loops.layers.uv.new("UV")
	NU, NV = 30, 18
	rings = []; ruv = []
	for i in range(NU + 1):
		u = i / NU; x = X0 + (X1 - X0) * u
		h, w, cy = prof(sp, u)
		if i == NU: h, w = h * 0.25, w * 0.25                         # close the nose
		ring = []
		for j in range(NV):
			a = 2 * math.pi * j / NV
			y = cy + math.cos(a) * h / 2; z = math.sin(a) * w / 2
			if math.cos(a) < 0: y -= 0.0                                     # (a flatter belly could go here)
			ring.append(bm.verts.new(G(x, y, z)))
		rings.append(ring)
	def face_uv(f, us, vs):
		for l, uu, vv in zip(f.loops, us, vs): l[uvl].uv = (uu, 1 - vv * FIN_V)
	for i in range(NU):
		for j in range(NV):
			j2 = (j + 1) % NV
			f = bm.faces.new((rings[i][j], rings[i + 1][j], rings[i + 1][j2], rings[i][j2]))
			v0, v1 = j / NV, (j + 1) / NV
			face_uv(f, [i / NU, (i + 1) / NU, (i + 1) / NU, i / NU], [v0, v0, v1, v1])
	# the nose cap and the tail-root cap
	for ring, uu in ((rings[-1], 1.0), (rings[0], 0.0)):
		f = bm.faces.new(ring if uu == 1.0 else list(reversed(ring)))
		for l in f.loops: l[uvl].uv = (uu, 1 - 0.25 * FIN_V)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

	def back_y(x):
		u = (x - X0) / (X1 - X0); h, w, cy = prof(sp, max(0.0, min(1.0, u))); return cy + h / 2
	def belly_y(x):
		u = (x - X0) / (X1 - X0); h, w, cy = prof(sp, max(0.0, min(1.0, u))); return cy - h / 2
	def fin(outline, base_inset=0.01, thick=0.006, z=0.0, rot=None):
		"""a flat fin from its outline (game x, y), first and last points on the body; fin rays in the texture"""
		pts = [Vector((x, y, z)) for x, y in outline]
		xs = [p.x for p in pts]; x0, x1 = min(xs), max(xs)
		vs = []
		for side in (-1, 1):
			vs.append([bm.verts.new(G(p.x, p.y, p.z + side * thick / 2) if rot is None else rot(p, side * thick / 2)) for p in pts])
		f1 = bm.faces.new(vs[1]); f0 = bm.faces.new(list(reversed(vs[0])))
		for f in (f0, f1):
			for l in f.loops:
				g = Vector((l.vert.co.x, l.vert.co.z, -l.vert.co.y))
				l[uvl].uv = ((g.x - x0) / max(x1 - x0, 1e-4) * 0.9 + 0.05, 1 - (FIN_V + 0.05 + 0.04 * (g.y % 1)) )
		n = len(pts)
		for k in range(n - 1):
			f = bm.faces.new((vs[0][k], vs[0][k + 1], vs[1][k + 1], vs[1][k]))
			for l in f.loops: l[uvl].uv = (0.5, 1 - (FIN_V + 0.06))
	# tail
	ped = sp["ped"]; tx = X0 + 0.02
	if sp["tail"] == "round":
		out = [(tx, ped * 0.45), (X0 - 0.09, ped * 1.5), (X0 - 0.17, ped * 1.4), (X0 - 0.19, 0.0), (X0 - 0.17, -ped * 1.4), (X0 - 0.09, -ped * 1.5), (tx, -ped * 0.45)]
	else:
		k = 1.0 if sp["tail"] == "fork" else 1.2
		out = [(tx, ped * 0.45), (X0 - 0.12, ped * 1.6 * k), (X0 - 0.2, ped * 2.1 * k), (X0 - 0.15, ped * 0.4), (X0 - 0.13, 0.0),
			(X0 - 0.15, -ped * 0.4), (X0 - 0.2, -ped * 2.1 * k), (X0 - 0.12, -ped * 1.6 * k), (tx, -ped * 0.45)]
	fin(out, thick=0.007)
	# dorsal fins along the back, the anal fin underneath
	def top_fin(xa, xb, height, spiny=False, n=7):
		pts = [(xa, back_y(xa) - 0.01)]
		for k in range(n + 1):
			t = k / n; x = xa + (xb - xa) * t
			hh = height * (math.sin(math.pi * (0.15 + 0.85 * t)) ** 0.6 if not spiny else (0.9 - 0.3 * t) * (1.0 if k % 2 == 0 else 0.75))
			pts.append((x, back_y(x) + hh))
		pts.append((xb, back_y(xb) - 0.01))
		fin(list(reversed(pts)))
	def bottom_fin(xa, xb, height, n=6):
		pts = [(xa, belly_y(xa) + 0.01)]
		for k in range(n + 1):
			t = k / n; x = xa + (xb - xa) * t
			pts.append((x, belly_y(x) - height * math.sin(math.pi * (0.2 + 0.8 * t)) ** 0.7))
		pts.append((xb, belly_y(xb) + 0.01))
		fin(pts)
	L = X1 - X0
	d = sp["dorsal"]; dp = sp["deep"]
	if d == "bass":
		top_fin(X0 + L * 0.45, X0 + L * 0.66, dp * 0.32, spiny=True, n=9); top_fin(X0 + L * 0.22, X0 + L * 0.47, dp * 0.38)
	elif d == "perch":
		top_fin(X0 + L * 0.48, X0 + L * 0.68, dp * 0.42, spiny=True, n=11); top_fin(X0 + L * 0.2, X0 + L * 0.42, dp * 0.36)
	elif d == "back":
		top_fin(X0 + L * 0.06, X0 + L * 0.22, dp * 0.5)
	elif d == "trout":
		top_fin(X0 + L * 0.42, X0 + L * 0.6, dp * 0.42); top_fin(X0 + L * 0.1, X0 + L * 0.15, dp * 0.15, n=3)
	else:
		top_fin(X0 + L * 0.4, X0 + L * 0.56, dp * 0.45)
	if d == "back": bottom_fin(X0 + L * 0.06, X0 + L * 0.2, dp * 0.4)
	else: bottom_fin(X0 + L * 0.16, X0 + L * 0.34, dp * 0.3)
	# pectorals (behind the gill, on the sides) and pelvics (under the chest), swept back
	for side in (1, -1):
		hp, wp, cyp = prof(sp, 0.72); xg = X0 + L * 0.72
		base = Vector((xg, cyp - hp * 0.12, side * wp * 0.46))
		def rot_side(p, off, base=base, side=side):
			q = Vector((p.x, p.y, 0)) - Vector((base.x, base.y, 0))
			return G(base.x + q.x, base.y + q.y * 0.9, base.z + side * (abs(q.x) * 0.35) + off)
		fin([(xg, cyp - hp * 0.08), (xg - 0.06, cyp - hp * 0.02), (xg - 0.1, cyp - hp * 0.12), (xg - 0.08, cyp - hp * 0.22), (xg, cyp - hp * 0.16)], rot=rot_side)
		hp2, wp2, cyp2 = prof(sp, 0.62); xp = X0 + L * 0.62
		base2 = Vector((xp, cyp2 - hp2 * 0.45, side * wp2 * 0.28))
		def rot_side2(p, off, base=base2, side=side):
			return G(p.x, p.y, base.z + side * abs(p.x - base.x) * 0.3 + off)
		fin([(xp, cyp2 - hp2 * 0.42), (xp - 0.07, cyp2 - hp2 * 0.5 - 0.035), (xp - 0.09, cyp2 - hp2 * 0.5 - 0.02), (xp - 0.02, cyp2 - hp2 * 0.44)], rot=rot_side2)
	# eyes: a gold (or red) iris with a black pupil, on each side of the head
	ue = 0.9; he, we, cye = prof(sp, ue); xe = X0 + L * ue
	r = sp["eye"]
	for side in (1, -1):
		for rr, key, push in ((r, "iris", 0.0), (r * 0.55, "pupil", r * 0.5)):
			tmp = bmesh.new()
			bmesh.ops.create_uvsphere(tmp, u_segments=12, v_segments=8, radius=1.0)
			bmesh.ops.transform(tmp, matrix=Matrix.Translation(G(xe, cye + he * 0.17, side * (we * 0.42 + push))) @ Matrix.Diagonal((rr, rr * 0.5, rr, 1)), verts=tmp.verts)
			me = bpy.data.meshes.new("e"); tmp.to_mesh(me); tmp.free()
			before = set(bm.faces); bm.from_mesh(me); bpy.data.meshes.remove(me)
			for f in bm.faces:
				if f not in before:
					for l in f.loops: l[uvl].uv = EYE_UV[key]
	for f in bm.faces: f.smooth = True
	me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
	ob = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(ob)
	me.materials.append(material(name, paint(name, sp)))
	return ob

fishes = {}
for i, (name, sp) in enumerate(S.items()):
	ob = build(name, sp)
	fishes[name] = ob
	me = ob.data; me.calc_loop_triangles(); print("FISH", name, len(me.loop_triangles), "tris")

if ARGV:
	bpy.ops.export_scene.gltf(filepath=ARGV[0], export_format="GLB", export_yup=True, export_texcoords=True,
		export_normals=True, export_materials="EXPORT")
	print("EXPORTED", ARGV[0])

if len(ARGV) > 1:
	PREV = ARGV[1]
	sc = bpy.context.scene; sc.render.engine = "CYCLES"; sc.cycles.samples = 24; sc.cycles.device = "CPU"
	sc.cycles.use_denoising = True; sc.view_settings.view_transform = "Standard"
	w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
	w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.62, 0.66, 1)
	bpy.ops.object.light_add(type="SUN", rotation=(math.radians(40), 0, math.radians(20)))
	bpy.context.object.data.energy = 3.0
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); bpy.context.collection.objects.link(cam); sc.camera = cam
	cam.data.lens = 70
	sc.render.resolution_x, sc.render.resolution_y = 520, 300
	for name, ob in fishes.items(): ob.hide_render = True
	for name, ob in fishes.items():
		ob.hide_render = False
		for tag, pos in (("side", G(-0.05, 0.02, 2.0)), ("34", G(0.9, 0.35, 1.6))):
			cam.location = pos; cam.rotation_euler = (G(-0.05, 0, 0) - pos).to_track_quat("-Z", "Y").to_euler()
			sc.render.filepath = os.path.join(PREV, "%s-%s.png" % (name.replace(" ", "_").lower(), tag))
			bpy.ops.render.render(write_still=True)
		ob.hide_render = True
	print("PREVIEWS", PREV)
