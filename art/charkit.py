# Shared kit for building the game's characters in Blender (see hale.py; earl.py is the original).
# Characters are written in GAME space (Godot: x right, y up, +z the way they face) and exported as one
# mesh per posable part, origins at the joints scripts/earl.gd turns them about:
#   torso: pivot at the hips; neck at y 0.58; shoulders at (+-0.25, 0.5)
#   head: pivot at the base of the neck, faces +z
#   upper: pivot at the shoulder, elbow at y -0.3;  fore: pivot at the elbow, hand at y -0.3
#   leg: pivot at the hip joint, sole at y -0.92;  cane: what they hold, pivot in the hand
# Two materials: "palette" (flat colours: each face's UVs sit on one swatch of a small atlas) and
# "cloth" (a tiling fabric texture - check, knit... - wrapped round the body and sleeves).
import bpy, bmesh, math, sys, os, random
from mathutils import Vector, Matrix

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
HERE = os.path.dirname(os.path.abspath(__file__))
DECIMATE = float(os.environ.get("CHAR_DECIMATE", "0.6"))     # how much of the smoothed mesh to keep

def G(x, y, z):            # game space -> Blender space
	return Vector((x, -z, y))

def hex2rgb(h):
	h = h.lstrip("#"); return [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
def srgb2lin(c):
	return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

# game-space rotations: about game x = blender x; about game y (up) = blender z; about game z = blender -y
def gRx(a): return Matrix.Rotation(a, 4, "X")
def gRy(a): return Matrix.Rotation(a, 4, "Z")
def gRz(a): return Matrix.Rotation(-a, 4, "Y")

class Kit:
	"""name: file prefix; pal: {swatch: '#rrggbb'}; cloth(x, y, n) -> (r, g, b) paints the fabric texture"""
	def __init__(self, name, pal, cloth, cloth_n=128, seed=7):
		bpy.ops.wm.read_factory_settings(use_empty=True)
		random.seed(seed)
		self.name = name; self.pal = pal; self.names = list(pal.keys()); self.sw = 8
		self.palette = self._mat("palette", self._palette_img(), "Closest")
		self.cloth = self._mat("cloth", self._cloth_img(cloth, cloth_n), "Linear")
		self.parts = {}

	def _palette_img(self):
		n = 8 * self.sw; img = bpy.data.images.new(self.name + "_palette", n, n, alpha=False)
		px = [0.0] * (n * n * 4)
		for i, k in enumerate(self.names):
			cx, cy = i % self.sw, i // self.sw
			r, g, b = hex2rgb(self.pal[k])
			for y in range(cy * 8, cy * 8 + 8):
				for x in range(cx * 8, cx * 8 + 8):
					o = (y * n + x) * 4; px[o:o + 4] = [r, g, b, 1.0]
		img.pixels = px
		img.filepath_raw = os.path.join(HERE, self.name + "_palette.png"); img.file_format = "PNG"; img.save()
		return img

	def _cloth_img(self, fn, n):
		img = bpy.data.images.new(self.name + "_cloth", n, n, alpha=False)
		px = [0.0] * (n * n * 4)
		for y in range(n):
			for x in range(n):
				c = fn(x, y, n); o = (y * n + x) * 4; px[o:o + 4] = [c[0], c[1], c[2], 1.0]
		img.pixels = px
		img.filepath_raw = os.path.join(HERE, self.name + "_cloth.png"); img.file_format = "PNG"; img.save()
		return img

	def _mat(self, name, img, interp):
		m = bpy.data.materials.new(name); m.use_nodes = True
		nt = m.node_tree; bsdf = nt.nodes["Principled BSDF"]
		tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img; tex.interpolation = interp
		nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
		bsdf.inputs["Roughness"].default_value = 0.9
		bsdf.inputs["Specular IOR Level"].default_value = 0.2
		return m

	def swatch_uv(self, name):
		i = self.names.index(name); n = 8 * self.sw
		return ((i % self.sw) * 8 + 4) / n, ((i // self.sw) * 8 + 4) / n

	def part(self, name):
		return Part(self, name)

	# ------------------------------------------------------------------ export
	def export(self, out):
		tris = 0
		dg = bpy.context.evaluated_depsgraph_get()
		for k, ob in self.parts.items():
			me = ob.evaluated_get(dg).to_mesh(); me.calc_loop_triangles(); n = len(me.loop_triangles)
			tris += n * (2 if k in ("upper", "fore", "leg") else 1)
			print("PART", k, n, "tris")
		print("WHOLE FIGURE ~%d tris" % tris)
		bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=False, export_apply=True,
			export_yup=True, export_texcoords=True, export_normals=True, export_materials="EXPORT")
		print("EXPORTED", out)

	# ------------------------------------------------------------------ previews: stand them up and render a turnaround
	def preview(self, prev, hold_cane=True, hip=0.92):
		P = self.parts
		def place(ob, m):
			d = ob.copy(); d.data = ob.data; d.hide_render = False; bpy.context.collection.objects.link(d)
			d.matrix_world = m; return d
		for ob in P.values(): ob.hide_render = True
		T = lambda x, y, z: Matrix.Translation(G(x, y, z))
		torso_m = T(0, hip, 0) @ gRx(0.08)
		place(P["torso"], torso_m)
		place(P["head"], torso_m @ T(0, 0.58, 0) @ gRx(-0.13))
		for sx in (-1, 1):
			place(P["leg"], T(sx * 0.1, hip, 0))
			up = torso_m @ T(sx * 0.25, 0.5, 0) @ gRz(sx * 0.12) @ gRx(0.04)
			place(P["upper"], up)
			fo = up @ T(0, -0.3, 0) @ gRx(-0.25)
			place(P["fore"], fo)
			if sx < 0 and hold_cane and "cane" in P: place(P["cane"], fo @ T(0, -0.3, 0))
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
		cam_data = bpy.data.cameras.new("cam"); cam_data.lens = 85
		cam = bpy.data.objects.new("cam", cam_data); bpy.context.collection.objects.link(cam); sc.camera = cam
		def snap(name, tgt, pos, wh):
			sc.render.resolution_x, sc.render.resolution_y = wh
			cam.location = pos; cam.rotation_euler = (tgt - pos).to_track_quat("-Z", "Y").to_euler()
			sc.render.filepath = os.path.join(prev, "%s-%s.png" % (self.name, name))
			bpy.ops.render.render(write_still=True)
		for name, ang in (("front", 0.0), ("34", 0.7), ("side", math.pi / 2), ("back", math.pi)):
			snap(name, G(0, 0.95, 0), G(math.sin(ang) * 6.0, 1.1, math.cos(ang) * 6.0), (360, 640))
		for name, ang in (("head1", 0.0), ("head2", 0.55), ("head3", 1.25)):
			snap(name, G(0, hip + 0.75, 0.04), G(math.sin(ang) * 1.6, hip + 0.8, math.cos(ang) * 1.6), (360, 360))
		print("PREVIEWS", prev)

class Part:
	def __init__(self, kit, name):
		self.kit = kit; self.name = name; self.bm = bmesh.new(); self.uv = self.bm.loops.layers.uv.new("UV")
		self.cr = self.bm.edges.layers.float.new("crease_edge")      # 1 = keep this edge crisp through the smoothing

	def _paint(self, faces, color, cloth):
		uv = self.uv
		if cloth is None:
			u, v = self.kit.swatch_uv(color)
			for f in faces:
				f.material_index = 0
				for l in f.loops: l[uv].uv = (u, v)
			return
		o, (su, sv) = cloth
		for f in faces:
			f.material_index = 1
			for l in f.loops:
				p = l.vert.co
				gx, gy, gz = p.x - o.x, p.z - o.z, -(p.y - o.y)
				l[uv].uv = (math.atan2(gx, gz) / (2 * math.pi) * su, gy * sv)
			us = [l[uv].uv.x for l in f.loops]
			if max(us) - min(us) > su * 0.5:            # straddling the seam at the back: unwrap
				for l in f.loops:
					if l[uv].uv.x < 0: l[uv].uv.x += su

	def _merge(self, fn, color, m, cloth, crease=0.0):
		tmp = bmesh.new(); fn(tmp)
		bmesh.ops.transform(tmp, matrix=m, verts=tmp.verts)
		me = bpy.data.meshes.new("tmp"); tmp.to_mesh(me); tmp.free()
		before = set(self.bm.faces)
		self.bm.from_mesh(me); bpy.data.meshes.remove(me)
		new = [f for f in self.bm.faces if f not in before]
		self._paint(new, color, cloth)
		if crease:
			for f in new:
				for e in f.edges: e[self.cr] = crease
		return new

	def ball(self, c, r, color, seg=12, rings=8, rot=None, cloth=None, jitter=0.0):
		def fn(b):
			bmesh.ops.create_uvsphere(b, u_segments=seg, v_segments=rings, radius=1.0)
			if jitter:
				for v in b.verts: v.co *= 1.0 + random.uniform(-jitter, jitter)
		m = Matrix.Translation(G(*c)) @ (rot or Matrix()) @ Matrix.Diagonal((r[0], r[2], r[1], 1.0))
		return self._merge(fn, color, m, cloth)

	def icob(self, c, r, color, subdiv=1, rot=None, jitter=0.0):
		def fn(b):
			bmesh.ops.create_icosphere(b, subdivisions=subdiv, radius=1.0)
			if jitter:
				for v in b.verts: v.co *= 1.0 + random.uniform(-jitter, jitter)
		m = Matrix.Translation(G(*c)) @ (rot or Matrix()) @ Matrix.Diagonal((r[0], r[2], r[1], 1.0))
		return self._merge(fn, color, m, None)

	def box(self, c, s, color, bevel=0.0, rot=None, segs=1, crease=0.0):
		def fn(b):
			bmesh.ops.create_cube(b, size=1.0)
			bmesh.ops.scale(b, vec=Vector((s[0], s[2], s[1])), verts=b.verts)
			if bevel > 0:
				bmesh.ops.bevel(b, geom=list(b.edges), offset=min(bevel, min(s) * 0.45), offset_type="OFFSET",
					segments=segs, profile=0.5, affect="EDGES", clamp_overlap=True)
		return self._merge(fn, color, Matrix.Translation(G(*c)) @ (rot or Matrix()), None, crease)

	def tube(self, a, b, r0, r1, color, seg=10, caps=True, cloth=None, squash=1.0):
		A = G(*a); B = G(*b); d = B - A; L = d.length
		def fn(bb):
			bmesh.ops.create_cone(bb, cap_ends=caps, cap_tris=False, segments=seg, radius1=r0, radius2=r1, depth=L)
			bmesh.ops.scale(bb, vec=Vector((1.0, squash, 1.0)), verts=bb.verts)
			bmesh.ops.translate(bb, vec=Vector((0, 0, L / 2)), verts=bb.verts)
		q = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
		return self._merge(fn, color, Matrix.Translation(A) @ q, cloth)

	def lathe(self, prof, color, seg=20, cloth=None, cap_top=True, cap_bot=True, x=0.0, z=0.0, wave=None, crease=0.0, hold=True):
		"""body of revolution from [(y, rx, rz), ...]; wave=(count, depth) ripples the radius (pleats, ribs).
		hold: extra rings just inside each end (and a flat inset on each cap) so the smoothing rounds the
		edges without pinching the ends or ballooning the middle"""
		prof = [tuple(p) for p in prof]
		if hold and len(prof) >= 2:
			def mix(p, q, t): return tuple(p[i] + (q[i] - p[i]) * t for i in range(3))
			prof = [prof[0], mix(prof[0], prof[1], 0.15)] + prof[1:-1] + [mix(prof[-1], prof[-2], 0.15), prof[-1]]
			if cap_bot: prof = [(prof[0][0], prof[0][1] * 0.82, prof[0][2] * 0.82)] + prof
			if cap_top: prof = prof + [(prof[-1][0], prof[-1][1] * 0.82, prof[-1][2] * 0.82)]
		def fn(b):
			rings = []
			for (y, rx, rz) in prof:
				ring = []
				for i in range(seg):
					a = 2 * math.pi * i / seg
					k = 1.0 + (wave[1] * (1 if i % 2 == 0 else -1) if wave else 0.0)
					ring.append(b.verts.new(G(x + math.sin(a) * rx * k, y, z + math.cos(a) * rz * k)))
				rings.append(ring)
			for j in range(len(rings) - 1):
				for i in range(seg):
					b.faces.new((rings[j][i], rings[j][(i + 1) % seg], rings[j + 1][(i + 1) % seg], rings[j + 1][i]))
			if cap_bot: b.faces.new(list(reversed(rings[0])))
			if cap_top: b.faces.new(rings[-1])
			bmesh.ops.recalc_face_normals(b, faces=b.faces)
		return self._merge(fn, color, Matrix(), cloth, crease)

	def ring(self, c, r, thick, color, seg=12, sides=4):
		"""a closed loop facing +z (glasses rims): one clean torus, elliptical radii r=(rx, ry)"""
		def fn(b):
			rings = []
			for i in range(seg):
				a = 2 * math.pi * i / seg
				ctr = Vector((math.cos(a) * r[0], math.sin(a) * r[1], 0.0))
				out = Vector((math.cos(a), math.sin(a), 0.0))
				ring = []
				for j in range(sides):
					t = 2 * math.pi * j / sides
					p = ctr + out * math.cos(t) * thick + Vector((0, 0, 1)) * math.sin(t) * thick
					ring.append(b.verts.new(G(p.x, p.y, p.z)))
				rings.append(ring)
			for i in range(seg):
				for j in range(sides):
					b.faces.new((rings[i][j], rings[(i + 1) % seg][j], rings[(i + 1) % seg][(j + 1) % sides], rings[i][(j + 1) % sides]))
			bmesh.ops.recalc_face_normals(b, faces=b.faces)
		return self._merge(fn, color, Matrix.Translation(G(*c)), None)

	def finish(self, subdiv=1, keep=None):
		"""smooth shading all over and a level of subdivision: every corner, cap and edge rounds off like
		clay (creased edges stay crisp). Build the base shapes coarse: subdivision multiplies them by 4"""
		bm = self.bm
		# (no welding: the pieces are separate closed shapes; welding where they touch makes bad faces)

		for f in bm.faces: f.smooth = True
		me = bpy.data.meshes.new(self.name); bm.to_mesh(me); bm.free()
		if me.validate(verbose=False): print("REPAIRED", self.name)     # drop any bad faces before smoothing
		me.materials.append(self.kit.palette); me.materials.append(self.kit.cloth)
		ob = bpy.data.objects.new(self.name, me); bpy.context.collection.objects.link(ob)
		if self.name in os.environ.get("CHAR_FLAT", "").split(","): subdiv = 0     # debugging: leave these unsmoothed
		if subdiv:
			m = ob.modifiers.new("round", "SUBSURF"); m.levels = subdiv; m.render_levels = subdiv
			m.uv_smooth = "PRESERVE_BOUNDARIES"; m.use_creases = True; m.quality = 3
			k = keep if keep is not None else DECIMATE
			if k < 1.0:
				# then thin the smoothed mesh back down (keeps the shape; flat areas lose the most)
				d = ob.modifiers.new("thin", "DECIMATE"); d.decimate_type = "COLLAPSE"; d.ratio = k
				d.use_collapse_triangulate = True
		self.kit.parts[self.name] = ob
		return ob
