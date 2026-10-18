## Places the forest around the property: firs, broadleaf trees in autumn colour, birches and snags,
## with ferns, bushes, tall grass, flowers, rocks, fallen logs and old stumps underneath.
## Everything is instanced (MultiMesh) in 40 m cells, with a detailed model up close and a
## lighter one far away, so a whole forest stays cheap to draw. A painted treeline closes the horizon.
class_name Forest
extends RefCounted

const CELL := 40.0
const YARD := Rect2(-46, -48, 92, 100)     # the mown lawn (x, z)

var w: WorldGen
var root: Node3D
var cells := {}                 # Vector2i -> {key -> Array[Transform3D/color pairs]}
var models := {}                # key -> {mesh, range_begin, range_end, shadow}
var rng := RandomNumberGenerator.new()
var trunks: Array = []          # [x, z, r] for collision near the yard
var rocks: Array = []           # [x, z, r, top] for collision near the yard
var occ := {}                   # Vector2i(4 m cell) -> [[x, z, r]]: trunks, rocks, logs and stumps already placed
const OCC := 4.0
const OCC_MAX := 3.2            # the biggest footprint anything records
var _edge := FastNoiseLite.new()
var _patch := FastNoiseLite.new()

func build(world: WorldGen, parent: Node3D) -> void:
	w = world; root = parent
	Nature.init()
	rng.seed = w.seed + 777
	_edge.seed = w.seed + 5; _edge.frequency = 0.035
	_patch.seed = w.seed + 9; _patch.frequency = 0.06
	_models()
	_place_trees()
	_place_floor()
	_place_underbrush()
	_emit()
	_colliders()
	_horizon()
	_light_shafts()

func _models() -> void:
	# three levels of detail: full up close, lighter in the middle distance, a few big cards far off
	for i in range(4):
		_lods("fir%d" % i, func(l: int) -> ArrayMesh: return Nature.fir(100 + i, l))
		_lods("oak%d" % i, func(l: int) -> ArrayMesh: return Nature.broadleaf(200 + i, l))
	for i in range(2):
		_lods("birch%d" % i, func(l: int) -> ArrayMesh: return Nature.broadleaf(300 + i, l, true))
		models["snag%d" % i] = {mesh = Nature.snag(400 + i), end = 300.0, shadow = true}
	for i in range(3):
		models["fern%d" % i] = {mesh = Nature.fern(500 + i), end = 55.0, shadow = false}
		models["rock%d" % i] = {mesh = Nature.rock(600 + i), end = 160.0, shadow = true}
		models["log%d" % i] = {mesh = Nature.fallen_log(700 + i), end = 120.0, shadow = true}
	models.bush0 = {mesh = Nature.bush(800, Color(0.5, 0.66, 0.32)), end = 80.0, shadow = false}
	models.bush1 = {mesh = Nature.bush(801, Color(0.82, 0.5, 0.2)), end = 80.0, shadow = false}
	models.bush2 = {mesh = Nature.bush(802, Color(0.6, 0.7, 0.3)), end = 80.0, shadow = false}
	models.grass0 = {mesh = Nature.grass_clump(900, 1.0), end = 50.0, shadow = false}
	models.grass1 = {mesh = Nature.grass_clump(901, 1.5), end = 50.0, shadow = false}
	models.flower0 = {mesh = Nature.flower(950), end = 45.0, shadow = false}
	models.flower1 = {mesh = Nature.flower(951), end = 45.0, shadow = false}
	models.stump0 = {mesh = Nature.old_stump(990), end = 120.0, shadow = true}
	for i in range(3): models["litter%d" % i] = {mesh = Nature.litter(980 + i), end = 45.0, shadow = false}
	# young firs coming up in the understorey (the far fir model, scaled right down)
	for i in range(2): models["sapling%d" % i] = {mesh = Nature.fir(150 + i, 1), end = 70.0, shadow = true}

const NEAR := 42.0
const MID := 88.0
const FAR := 280.0              # past this the fog and the painted treeline take over

## the three models cross-fade (a dithered blend in the foliage shader) instead of popping
func _lods(key: String, make: Callable) -> void:
	var near: ArrayMesh = make.call(0); var mid: ArrayMesh = make.call(1); var far: ArrayMesh = make.call(2)
	_fade(near, Vector4(-2, -1, NEAR - 7.0, NEAR), false)
	_fade(mid, Vector4(NEAR - 7.0, NEAR, MID - 9.0, MID), true)
	_fade(far, Vector4(MID - 9.0, MID, 1e5, 1e5 + 1.0), true)
	# up close the detailed tree is drawn, but its shadow comes from the lighter model (a fraction of the cost)
	models[key] = {mesh = near, end = NEAR + 1.0, shadow = false}
	models[key + "_shadow"] = {mesh = make.call(1), end = 60.0, shadow = true, shadow_only = true}
	models[key + "_mid"] = {mesh = mid, begin = NEAR - 8.0, end = MID + 1.0, shadow = false}
	models[key + "_far"] = {mesh = far, begin = MID - 10.0, end = FAR, shadow = false}

static func _fade(m: ArrayMesh, f: Vector4, inv: bool) -> void:
	for i in range(m.get_surface_count()):
		var mat := m.surface_get_material(i)
		if mat is ShaderMaterial:
			var d: ShaderMaterial = mat.duplicate()
			d.set_shader_parameter("fade", f)
			d.set_shader_parameter("fade_inv", inv)
			m.surface_set_material(i, d)

func _tree(key: String, x: float, z: float, yaw: float, s: float) -> void:
	_add(key, x, z, yaw, s); _add(key + "_mid", x, z, yaw, s); _add(key + "_far", x, z, yaw, s); _add(key + "_shadow", x, z, yaw, s)

func _add(key: String, x: float, z: float, yaw: float, s: float, tint := Color.WHITE, sink := 0.0) -> void:
	if w.lake_d(x, z) < 0.6: return          # nothing of the forest floor grows in (or under) the lake
	var c := Vector2i(floori(x / CELL), floori(z / CELL))
	if not cells.has(c): cells[c] = {}
	var cell: Dictionary = cells[c]
	if not cell.has(key): cell[key] = []
	var y := w.H(x, z) - sink
	cell[key].append([Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(x, y, z)), tint])

## how "forest" a spot is: 0 on the lawn, 1 deep in the woods; the edge wanders
func forestness(x: float, z: float) -> float:
	return w.forestness(x, z)

func _clear(x: float, z: float, pad: float) -> bool:
	if w.creek_d(x, z) < 3.6 + maxf(pad, 0.0): return false
	if w.lake_d(x, z) < 1.5 + maxf(pad, 0.0): return false
	if absf(z - w.road_z) < 6.5 + pad: return false
	for i in range(0, w.drive_path.size(), 2):
		if Vector2(x, z).distance_to(w.drive_path[i]) < 3.0 + pad: return false
	if w._box_dist(x, z, w.house) < 4 + pad or w._box_dist(x, z, w.shed) < 3 + pad: return false
	if Vector2(x, z).distance_to(Vector2(w.pile.x, w.pile.z)) < 4 + pad: return false
	if Vector2(x, z).distance_to(Vector2(w.tree.x, w.tree.z)) < w.tree.h + 4 + pad: return false
	if Vector2(x, z).distance_to(Vector2(w.mailbox.x, w.mailbox.y)) < 2 + pad: return false
	return true

## remember a round footprint so later things keep out of it
func _occupy(x: float, z: float, r: float) -> void:
	var c := Vector2i(floori(x / OCC), floori(z / OCC))
	if not occ.has(c): occ[c] = []
	occ[c].append([x, z, minf(r, OCC_MAX)])

## does a circle at (x, z) of radius r overlap anything already placed?
func _overlaps(x: float, z: float, r: float) -> bool:
	var c := Vector2i(floori(x / OCC), floori(z / OCC))
	var k := ceili((r + OCC_MAX) / OCC)
	for j in range(-k, k + 1):
		for i in range(-k, k + 1):
			var list = occ.get(c + Vector2i(i, j))
			if list == null: continue
			for o in list:
				var dx: float = o[0] - x; var dz: float = o[1] - z; var rr: float = o[2] + r
				if dx * dx + dz * dz < rr * rr: return true
	return false

## how far a model reaches out from its centre on the ground, at scale 1
func _reach(key: String) -> float:
	var bb: AABB = (models[key].mesh as Mesh).get_aabb()
	return maxf(maxf(absf(bb.position.x), absf(bb.end.x)), maxf(absf(bb.position.z), absf(bb.end.z)))

func _place_trees() -> void:
	var step := 4.6
	var x := -170.0
	while x < 170.0:
		var z := -170.0
		while z < 175.0:
			var px := x + rng.randf_range(-1.8, 1.8); var pz := z + rng.randf_range(-1.8, 1.8)
			z += step
			if Vector2(px, pz).length() > 175: continue
			var f := forestness(px, pz)
			if f <= 0.05 or rng.randf() > f * 0.95: continue
			if not _clear(px, pz, 1.0): continue
			var kind := rng.randf()
			if w.job == "hale": kind = 0.58 * kind / 0.3 if kind < 0.3 else (0.58 + (kind - 0.3) / 0.55 * 0.28 if kind < 0.85 else 0.86 + (kind - 0.85) / 0.15 * 0.1)    # hardwoods: maples and birches round the lake
			var yaw := rng.randf() * TAU
			var s := rng.randf_range(0.85, 1.2)
			var near := Vector2(px, pz).length() < 95
			if kind < 0.58:
				var v := rng.randi() % 4
				_tree("fir%d" % v, px, pz, yaw, s)
				_occupy(px, pz, 0.3 * s + 0.35)
				if near: trunks.append([px, pz, 0.3 * s])
			elif kind < 0.86:
				var v := rng.randi() % 4
				_tree("oak%d" % v, px, pz, yaw, s)
				_occupy(px, pz, 0.25 * s + 0.35)
				if near: trunks.append([px, pz, 0.25 * s])
			elif kind < 0.96:
				var v := rng.randi() % 2
				_tree("birch%d" % v, px, pz, yaw, s)
				_occupy(px, pz, 0.16 * s + 0.35)
				if near: trunks.append([px, pz, 0.16 * s])
			else:
				_add("snag%d" % (rng.randi() % 2), px, pz, yaw, s)
				_occupy(px, pz, 0.25 * s + 0.35)
				if near: trunks.append([px, pz, 0.25 * s])
		x += step
	# a few big yard trees, well away from the work
	for t in w.yard_trees:
		trunks.append([t.x, t.z, 0.28])
		_occupy(t.x, t.z, 0.65)
		var yaw := rng.randf() * TAU
		if t.pine:
			_tree("fir0", t.x, t.z, yaw, 0.8)
		else:
			_tree("oak1", t.x, t.z, yaw, 1.05)

## rocks, fallen logs and old stumps on the forest floor: never through a tree or each other
func _place_floor() -> void:
	for k in range(900):
		var px := rng.randf_range(-160, 160); var pz := rng.randf_range(-150, 165)
		var f := forestness(px, pz)
		if f < 0.3 or not _clear(px, pz, 1.5): continue
		var roll := rng.randf()
		var yaw := rng.randf() * TAU
		var key := "stump0"
		var s := rng.randf_range(0.8, 1.3)
		var sink := 0.0
		if roll < 0.45: key = "rock%d" % (rng.randi() % 3); s = rng.randf_range(0.6, 1.6); sink = 0.15
		elif roll < 0.75: key = "log%d" % (rng.randi() % 3); s = rng.randf_range(0.8, 1.2); sink = 0.12
		var r := _reach(key) * s
		if _overlaps(px, pz, r): continue
		_add(key, px, pz, yaw, s, Color.WHITE, sink)
		_occupy(px, pz, r)
		if key.begins_with("rock") and Vector2(px, pz).length() < 95:
			var bb: AABB = (models[key].mesh as Mesh).get_aabb()
			rocks.append([px, pz, r * 0.8, bb.end.y * s - sink])

## true if a plant at (x, z) would poke through a rock, log, stump or trunk
func _crowded(x: float, z: float, pad: float) -> bool:
	return _overlaps(x, z, pad)

func _place_underbrush() -> void:
	# ferns, bushes, tall grass and flowers: thick in the woods and along the edge
	var x := -110.0
	while x < 110.0:
		var z := -100.0
		while z < 120.0:
			var px := x + rng.randf_range(-0.9, 0.9); var pz := z + rng.randf_range(-0.9, 0.9)
			z += 1.7
			var f := forestness(px, pz)
			if f <= 0.0 or not _clear(px, pz, -0.5): continue
			var patch := _patch.get_noise_2d(px, pz) * 0.5 + 0.5
			var yaw := rng.randf() * TAU
			var roll := rng.randf()
			var edge := 1.0 - absf(f - 0.35) * 2.0       # strongest right at the woods' edge
			if f > 0.05 and _crowded(px, pz, 0.3): continue   # nothing growing up through a rock or a trunk
			if f > 0.3 and rng.randf() < 0.22 * f: _add("litter%d" % (rng.randi() % 3), px + 0.4, pz - 0.3, yaw, rng.randf_range(0.8, 1.4))
			if f > 0.5 and rng.randf() < 0.035 * f: _add("sapling%d" % (rng.randi() % 2), px - 0.5, pz + 0.4, yaw, rng.randf_range(0.1, 0.26))
			if roll < 0.5 * f * (0.5 + patch):
				_add("fern%d" % (rng.randi() % 3), px, pz, yaw, rng.randf_range(0.8, 1.5))
			elif roll < 0.5 * f + 0.12 * maxf(edge, 0.25) * (0.6 + patch):
				if not _crowded(px, pz, 0.85): _add("bush%d" % (rng.randi() % 3), px, pz, yaw, rng.randf_range(0.7, 1.3), Color.WHITE, 0.1)
			elif roll < 0.5 and f < 0.75:
				_add("grass%d" % (rng.randi() % 2), px, pz, yaw, rng.randf_range(0.8, 1.3))
			elif roll < 0.53 and f < 0.6:
				_add("flower%d" % (rng.randi() % 2), px, pz, yaw, rng.randf_range(0.8, 1.3))
		x += 1.7
	# stones and ferns crowding the creek banks (if there is a creek)
	var cx := -150.0 if w.creek_d(0.0, w.creek_z(0.0)) < 1e5 else 1e9
	while cx < 150.0:
		cx += rng.randf_range(1.2, 3.0)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var cz := w.creek_z(cx) + side * rng.randf_range(2.6, 4.2)
		_add("rock%d" % (rng.randi() % 3), cx, cz, rng.randf() * TAU, rng.randf_range(0.6, 1.4), Color.WHITE, 0.1)
		if rng.randf() < 0.25: _add("rock%d" % (rng.randi() % 3), cx + 0.5, w.creek_z(cx) + rng.randf_range(-1.5, 1.5), rng.randf() * TAU, rng.randf_range(0.4, 0.8), Color.WHITE, 0.05)
		var fz := w.creek_z(cx) + side * rng.randf_range(4.2, 7.5)
		if rng.randf() < 0.8: _add("fern%d" % (rng.randi() % 3), cx, fz, rng.randf() * TAU, rng.randf_range(1.0, 1.6))
	# autumn at the lake house: maple leaves drifted all over the lawn
	if w.job == "hale":
		for k in range(1400):
			var lx := rng.randf_range(-46, 46); var lz := rng.randf_range(-44, 66)
			if forestness(lx, lz) > 0.2 or w.lake_d(lx, lz) < 2.0 or absf(lz - w.road_z) < 6.0: continue
			if w._box_dist(lx, lz, w.house) < 1.5 or w._box_dist(lx, lz, w.garage) < 1.0: continue
			var on_drive := false
			for i in range(0, w.drive_path.size(), 2):
				if Vector2(lx, lz).distance_to(w.drive_path[i]) < 2.2: on_drive = true; break
			if on_drive: continue
			_add("litter%d" % (rng.randi() % 3), lx, lz, rng.randf() * TAU, rng.randf_range(0.45, 0.8))
	# long grass and wildflowers in the meadow strip along the road
	for k in range(2500):
		var px := rng.randf_range(-150, 150); var pz := w.road_z + rng.randf_range(-14, 14) * (1 if rng.randf() < 0.5 else -1)
		if not _clear(px, pz, -2.0): continue
		_add("grass%d" % (rng.randi() % 2), px, pz, rng.randf() * TAU, rng.randf_range(0.9, 1.6))
		if rng.randf() < 0.08: _add("flower%d" % (rng.randi() % 2), px + 0.4, pz, rng.randf() * TAU, 1.0)

func _emit() -> void:
	for c in cells:
		var cell: Dictionary = cells[c]
		for key in cell:
			var list: Array = cell[key]
			var md: Dictionary = models[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = md.mesh
			mm.instance_count = list.size()
			for i in range(list.size()):
				mm.set_instance_transform(i, list[i][0])
				var tc: Color = list[i][1]
				mm.set_instance_color(i, Color(tc.r, tc.g, tc.b, 1.0))
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.name = key
			mi.set_meta("key", key)
			# small plants live on render layer 2, which the truck mirror skips
			if key.begins_with("fern") or key.begins_with("grass") or key.begins_with("flower") or key.begins_with("litter") or key.begins_with("bush"):
				mi.layers = 2
			mi.visibility_range_begin = md.get("begin", 0.0)
			mi.visibility_range_end = md.end
			mi.visibility_range_end_margin = 1.0
			mi.visibility_range_begin_margin = 1.0 if md.has("begin") else 0.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			mi.set_meta("vr", Vector2(mi.visibility_range_begin, mi.visibility_range_end))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if md.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if md.get("shadow_only", false): mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			root.add_child(mi)

func _colliders() -> void:
	var sb := StaticBody3D.new(); sb.name = "ForestTrunks"
	for t in trunks:
		var cs := CollisionShape3D.new(); var cy := CylinderShape3D.new()
		cy.radius = t[2]; cy.height = 6.0
		cs.shape = cy; cs.position = Vector3(t[0], w.H(t[0], t[1]) + 2.5, t[1])
		sb.add_child(cs)
	for rk in rocks:
		var top: float = rk[3]
		if top < 0.25: continue                   # low enough to just walk over
		var cs := CollisionShape3D.new(); var cy := CylinderShape3D.new()
		cy.radius = rk[2]; cy.height = top + 0.3
		cs.shape = cy; cs.position = Vector3(rk[0], w.H(rk[0], rk[1]) + (top - 0.3) / 2, rk[1])
		sb.add_child(cs)
	root.add_child(sb)

## a painted ring of distant firs, and ground running out under it, so the world has no edge
func _horizon() -> void:
	var mb := MeshBuilder.new()
	var R := 240.0; var segs := 48; var hgt := 38.0
	var base := w.H(0, 0) - 4.0
	for i in range(segs):
		var a0 := TAU * i / segs; var a1 := TAU * (i + 1) / segs
		var p0 := Vector3(cos(a0) * R, base, sin(a0) * R); var p1 := Vector3(cos(a1) * R, base, sin(a1) * R)
		var u0 := float(i) / segs * 6.0; var u1 := float(i + 1) / segs * 6.0
		var n0 := -p0.normalized()
		var c := Color(0.42, 0.5, 0.44, 0.0)
		var i0 := mb.v(p0, n0, c, Vector2(u0, 1)); var i1 := mb.v(p1, n0, c, Vector2(u1, 1))
		var i2 := mb.v(p1 + Vector3(0, hgt, 0), n0, c, Vector2(u1, 0.001)); var i3 := mb.v(p0 + Vector3(0, hgt, 0), n0, c, Vector2(u0, 0.001))
		mb.quad(i0, i1, i2, i3)
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, unshaded, fog_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.47, 0.56, 0.58);
void fragment() {
	vec4 t = texture(tex, vec2(fract(UV.x), UV.y));
	ALBEDO = tint * (0.85 + 0.15 * t.r);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""
	mat.shader = sh
	mat.set_shader_parameter("tex", Nature.tex.treeline)
	var mi := mb.instance(mat); mi.name = "Treeline"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# ground beyond the terrain: a frame around the terrain square, just under its lowest edge
	var lo := 1e9
	var e := -149.0
	while e <= 149.0:
		lo = minf(lo, minf(minf(w.H(e, -149), w.H(e, 149)), minf(w.H(-149, e), w.H(149, e))))
		e += 6.0
	var g := MeshBuilder.new()
	var cg := Color("#4e5a36")
	var y := lo - 0.25
	var I := 149.5; var O := 900.0
	for q in [[Vector2(-O, -O), Vector2(O, -I)], [Vector2(-O, I), Vector2(O, O)], [Vector2(-O, -I), Vector2(-I, I)], [Vector2(I, -I), Vector2(O, I)]]:
		var p0: Vector2 = q[0]; var p1: Vector2 = q[1]
		var a0 := g.v(Vector3(p0.x, y, p0.y), Vector3.UP, cg); var b0 := g.v(Vector3(p1.x, y, p0.y), Vector3.UP, cg)
		var c0 := g.v(Vector3(p1.x, y, p1.y), Vector3.UP, cg); var d0 := g.v(Vector3(p0.x, y, p1.y), Vector3.UP, cg)
		g.quad(a0, d0, c0, b0)
	var gm := g.instance(); gm.name = "FarGround"; gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(gm)

## soft beams of sunlight slanting down through the canopy at the edge of the woods
func _light_shafts() -> void:
	var sun_dir := Vector3(0, -1, 0)
	var sun: DirectionalLight3D = null
	for c in root.get_parent().get_children():
		if c is DirectionalLight3D: sun = c
	if sun: sun_dir = -sun.global_transform.basis.z
	var mb := MeshBuilder.new()
	var placed := 0
	for k in range(600):
		if placed >= 46: break
		var x := rng.randf_range(-110, 110); var z := rng.randf_range(-100, 120)
		var f := forestness(x, z)
		if f < 0.45 or f > 0.95 or not _clear(x, z, 0.0): continue
		placed += 1
		var top := Vector3(x, w.H(x, z) + 16.0, z) - sun_dir * 2.0
		var bot := top + sun_dir * (16.0 / maxf(-sun_dir.y, 0.2))
		var along := (bot - top).normalized()
		var wdt := rng.randf_range(0.8, 2.2)
		for k2 in range(2):
			var side := along.cross(Vector3.UP if k2 == 0 else Vector3.RIGHT).normalized() * wdt
			var c := Color(1, 1, 1, rng.randf_range(0.5, 1.0))
			var i0 := mb.v(top - side, Vector3.UP, c, Vector2(0, 0)); var i1 := mb.v(top + side, Vector3.UP, c, Vector2(1, 0))
			var i2 := mb.v(bot + side, Vector3.UP, c, Vector2(1, 1)); var i3 := mb.v(bot - side, Vector3.UP, c, Vector2(0, 1))
			mb.quad(i0, i1, i2, i3)
	if mb.is_empty(): return
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 tint : source_color = vec3(1.0, 0.86, 0.6);
void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float down = smoothstep(0.0, 0.25, UV.y) * (1.0 - smoothstep(0.7, 1.0, UV.y));
	float near = smoothstep(2.0, 9.0, -VERTEX.z);
	ALBEDO = tint * across * across * down * near * COLOR.a * 0.09;
}
"""
	mat.shader = sh
	var mi := mb.instance(mat); mi.name = "LightShafts"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
