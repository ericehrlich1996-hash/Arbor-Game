## The living forest: textures painted in code at startup (leaf clusters, fir sprays, fern fronds,
## grass, bark) and the plant models built from them (firs, broadleaf trees, birches, snags, ferns,
## bushes, saplings, fallen logs, stumps, rocks, flowers). Stylised, not photoreal: soft round
## foliage lighting, cards with alpha cut-outs, everything swaying a little in the wind.
class_name Nature
extends RefCounted

static var tex := {}
static var mats := {}
static var _ready := false

# ================================================================ painted textures
static func _img(w: int, h: int, bg: Color) -> Image:
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	im.fill(Color(bg.r, bg.g, bg.b, 0.0))
	return im

static func _blend(im: Image, x: int, y: int, c: Color, a: float) -> void:
	if x < 0 or y < 0 or x >= im.get_width() or y >= im.get_height(): return
	var o := im.get_pixel(x, y)
	var na := a + o.a * (1.0 - a)
	if na <= 0.0: return
	var r := (c.r * a + o.r * o.a * (1.0 - a)) / na
	var g := (c.g * a + o.g * o.a * (1.0 - a)) / na
	var b := (c.b * a + o.b * o.a * (1.0 - a)) / na
	im.set_pixel(x, y, Color(r, g, b, na))

## a filled leaf: an ellipse pointed at both ends, with a darker midrib
static func _leaf(im: Image, cx: float, cy: float, ang: float, L: float, W: float, c: Color) -> void:
	var ca := cos(ang); var sa := sin(ang)
	var R := int(L) + 2
	for yy in range(int(cy) - R, int(cy) + R + 1):
		for xx in range(int(cx) - R, int(cx) + R + 1):
			var dx := xx - cx; var dy := yy - cy
			var u := (dx * ca + dy * sa) / L          # along the leaf, -1..1
			var v := (-dx * sa + dy * ca) / W
			var wv := 1.0 - u * u
			if wv <= 0: continue
			var shape := wv * (1.0 - 0.25 * u)        # a bit fuller toward the stem
			var e := absf(v) - shape
			if e > 0.08: continue
			var a := clampf(0.5 - e / 0.16, 0, 1)
			var shadeb := 0.86 + 0.14 * (1.0 - absf(v) / maxf(shape, 0.01)) + 0.06 * u
			var col := c * shadeb
			if absf(v) < 0.09 and absf(u) < 0.9: col = c * 0.72        # midrib
			_blend(im, xx, yy, Color(col.r, col.g, col.b), a)

static func _line(im: Image, x0: float, y0: float, x1: float, y1: float, w0: float, w1: float, c0: Color, c1: Color) -> void:
	var L := maxf(1.0, Vector2(x1 - x0, y1 - y0).length())
	var steps := int(L * 1.5) + 1
	for i in range(steps + 1):
		var t := float(i) / steps
		var x := lerpf(x0, x1, t); var y := lerpf(y0, y1, t); var w := lerpf(w0, w1, t)
		var c := c0.lerp(c1, t)
		var R := int(ceil(w))
		for yy in range(int(y) - R, int(y) + R + 1):
			for xx in range(int(x) - R, int(x) + R + 1):
				var d := Vector2(xx - x, yy - y).length()
				if d <= w: _blend(im, xx, yy, c, clampf(w - d + 0.5, 0, 1))

static func _finish(im: Image, fill: Color) -> ImageTexture:
	# bleed colour into the transparent texels so mipmaps don't grow dark fringes
	for y in range(im.get_height()):
		for x in range(im.get_width()):
			var p := im.get_pixel(x, y)
			if p.a < 0.02: im.set_pixel(x, y, Color(fill.r, fill.g, fill.b, 0.0))
	im.generate_mipmaps()
	return ImageTexture.create_from_image(im)

## a cluster of broad leaves (tinted per tree: green, orange, gold)
static func _paint_leaves(rng: RandomNumberGenerator, size: int, n: int, small: bool) -> ImageTexture:
	var im := _img(size, size, Color(0.6, 0.7, 0.4))
	var C := size * 0.5
	for i in range(n):
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * C * 0.78
		var x := C + cos(a) * r; var y := C + sin(a) * r
		var ang := a + rng.randf_range(-0.6, 0.6)
		var L := rng.randf_range(0.1, 0.15) * size * (0.6 if small else 1.0)
		var tone := rng.randf_range(0.72, 1.0)
		var hue := Color(tone * rng.randf_range(0.92, 1.0), tone, tone * rng.randf_range(0.85, 0.95))
		_leaf(im, x, y, ang, L, L * rng.randf_range(0.38, 0.5), hue)
	return _finish(im, Color(0.75, 0.75, 0.7))

## a fir spray: a twig with side twigs, all thick with needles, filling most of the card
static func _paint_fir(rng: RandomNumberGenerator, size: int) -> ImageTexture:
	var im := _img(size, size, Color(0.4, 0.5, 0.35))
	var spine := func(x0: float, y0: float, x1: float, y1: float, needle: float) -> void:
		var L := Vector2(x1 - x0, y1 - y0).length()
		var dir := Vector2(x1 - x0, y1 - y0) / L
		var nrm := Vector2(-dir.y, dir.x)
		var k := 0.0
		while k < L:
			var t := k / L
			var p := Vector2(x0, y0) + dir * k
			var nl := needle * (1.0 - t * 0.5) * rng.randf_range(0.8, 1.15)
			for s: float in [-1.0, 1.0]:
				var q := p + (nrm * s * 0.85 + dir * 0.55).normalized() * nl
				var tone := rng.randf_range(0.7, 1.0)
				_line(im, p.x, p.y, q.x, q.y, 1.3, 0.6, Color(0.55, 0.62, 0.55) * tone, Color(0.95, 1.0, 0.88) * tone)
			# needles on top of the twig too, pointing forward
			if rng.randf() < 0.6:
				var q2 := p + (dir + nrm * rng.randf_range(-0.4, 0.4)).normalized() * nl * 0.7
				_line(im, p.x, p.y, q2.x, q2.y, 1.2, 0.6, Color(0.6, 0.66, 0.58), Color(0.9, 0.95, 0.85))
			k += rng.randf_range(1.2, 1.9)
		_line(im, x0, y0, x1, y1, 1.6, 0.7, Color(0.38, 0.32, 0.26), Color(0.48, 0.42, 0.34))
	var y0 := size * 0.5
	var tipx := size * 0.97
	# side twigs first (behind), then the main twig
	for i in range(7):
		var t := 0.08 + i * 0.125
		var px := 4.0 + t * (tipx - 4.0); var py := y0 + sin(t * 2.0) * size * 0.03
		for s: float in [-1.0, 1.0]:
			var len := size * rng.randf_range(0.26, 0.34) * (1.0 - t * 0.6)
			var ang := s * rng.randf_range(0.7, 1.0)
			spine.call(px, py, px + cos(ang) * len, py + sin(ang) * len, size * 0.075)
	spine.call(4.0, y0, tipx, y0 + size * 0.03, size * 0.095)
	return _finish(im, Color(0.6, 0.66, 0.58))

## a fern frond: rachis with leaflets that shrink toward the tip (stem at the bottom)
static func _paint_fern(rng: RandomNumberGenerator, w: int, h: int) -> ImageTexture:
	var im := _img(w, h, Color(0.5, 0.6, 0.4))
	var cx := w * 0.5
	_line(im, cx, h - 2.0, cx, 4.0, 1.4, 0.5, Color(0.55, 0.6, 0.45), Color(0.7, 0.75, 0.6))
	var y := float(h) - 10.0
	while y > 8:
		var t := 1.0 - y / h
		var L := w * 0.46 * sin(clampf(t * 1.15, 0.05, 1.0) * PI) * (1.0 - t * 0.25) + 2
		for s: float in [-1.0, 1.0]:
			var tone := rng.randf_range(0.8, 1.0)
			var ang := (PI * 0.5 - 0.35) * s + PI * 0.5 - PI * 0.5 * s * 0.0
			var dx := cos(-0.28) * L * s; var dy := sin(-0.28) * L
			_leaf(im, cx + dx * 0.5, y + dy * 0.5, atan2(dy, dx), L * 0.5, maxf(2.0, L * 0.16), Color(tone, tone, tone * 0.92))
		y -= maxf(3.0, 5.0 - t * 2.0)
	return _finish(im, Color(0.75, 0.8, 0.7))

## a clump of grass blades (base at the bottom)
static func _paint_grass(rng: RandomNumberGenerator, w: int, h: int) -> ImageTexture:
	var im := _img(w, h, Color(0.5, 0.6, 0.35))
	for i in range(34):
		var x0 := w * (0.2 + rng.randf() * 0.6)
		var lean := rng.randf_range(-0.35, 0.35)
		var hh := h * rng.randf_range(0.45, 0.97)
		var x1 := x0 + lean * hh
		var tone := rng.randf_range(0.7, 1.0)
		_line(im, x0, h - 1.0, x1, h - hh, 1.6, 0.4, Color(0.55, 0.6, 0.5) * tone, Color(1.0, 1.0, 0.92) * tone)
	return _finish(im, Color(0.75, 0.8, 0.65))

## a foxglove-ish flower spike
static func _paint_flower(rng: RandomNumberGenerator, w: int, h: int) -> ImageTexture:
	var im := _img(w, h, Color(0.6, 0.6, 0.5))
	var cx := w * 0.5
	_line(im, cx, h - 1.0, cx, h * 0.08, 1.2, 0.6, Color(0.35, 0.5, 0.25), Color(0.4, 0.55, 0.3))
	var y := h * 0.15
	while y < h * 0.62:
		var s := 1.0 if int(y) % 2 == 0 else -1.0
		var r := 3.0 + (y / h) * 4.0
		_leaf(im, cx + s * r * 0.8, y, PI * 0.5, r, r * 0.7, Color(1, 1, 1))
		y += r * 0.9
	for i in range(5):
		_leaf(im, cx + rng.randf_range(-6, 6), h * rng.randf_range(0.72, 0.95), rng.randf_range(-1, 1) - PI * 0.5, w * 0.22, w * 0.07, Color(0.45, 0.62, 0.32))
	return _finish(im, Color(0.8, 0.7, 0.8))

const TEX_VERSION := 2
static func _cached(name: String, paint: Callable) -> Texture2D:
	var path := "user://tex_%s_v%d.png" % [name, TEX_VERSION]
	if FileAccess.file_exists(path):
		var im := Image.load_from_file(path)
		if im:
			im.generate_mipmaps()
			return ImageTexture.create_from_image(im)
	var t: ImageTexture = paint.call()
	var src := t.get_image()
	src.clear_mipmaps()
	src.save_png(path)
	return t

## a strip of distant fir silhouettes for the horizon ring
static func _paint_treeline(rng: RandomNumberGenerator, w: int, h: int) -> ImageTexture:
	var im := _img(w, h, Color(0.3, 0.4, 0.35))
	var x := 0.0
	while x < w:
		var th := h * rng.randf_range(0.45, 0.98); var bw := th * rng.randf_range(0.18, 0.28)
		var tone := rng.randf_range(0.8, 1.0)
		for yy in range(int(h - th), h):
			var t := float(yy - (h - th)) / th
			var half := bw * t + 1.0
			for xx in range(int(x - half), int(x + half) + 1):
				_blend(im, (xx + w) % w, yy, Color(tone, tone, tone), 1.0)
		x += rng.randf_range(4, 14)
	return _finish(im, Color(0.9, 0.9, 0.9))

static func _noise_tex(freq: float, octaves: int, c0: Color, c1: Color, stretch := Vector2.ONE, cellular := false, size := 256) -> NoiseTexture2D:
	var nz := FastNoiseLite.new()
	nz.frequency = freq; nz.fractal_octaves = octaves
	if cellular:
		nz.noise_type = FastNoiseLite.TYPE_CELLULAR
		nz.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	var g := Gradient.new(); g.set_color(0, c0); g.set_color(1, c1)
	var t := NoiseTexture2D.new(); t.noise = nz; t.color_ramp = g; t.width = size; t.height = size; t.seamless = true
	return t

static func init() -> void:
	if _ready: return
	_ready = true
	var rng := RandomNumberGenerator.new(); rng.seed = 4242
	# painting is slow in script, so the result is cached on disk after the first run
	tex.leaves = _cached("leaves", func(): return _paint_leaves(rng, 256, 70, false))
	tex.leaves_small = _cached("leaves_small", func(): return _paint_leaves(rng, 256, 120, true))
	tex.fir = _cached("fir", func(): return _paint_fir(rng, 256))
	tex.fern = _cached("fern", func(): return _paint_fern(rng, 128, 256))
	tex.grass = _cached("grass", func(): return _paint_grass(rng, 128, 128))
	tex.flower = _cached("flower", func(): return _paint_flower(rng, 64, 128))
	tex.treeline = _cached("treeline", func(): return _paint_treeline(rng, 1024, 128))
	# materials
	mats.leaves = _foliage(tex.leaves, 1.0)
	mats.leaves_small = _foliage(tex.leaves_small, 1.0)
	mats.fir = _foliage(tex.fir, 0.6)
	mats.fern = _foliage(tex.fern, 1.4)
	mats.grass = _foliage(tex.grass, 1.6)
	mats.flower = _foliage(tex.flower, 1.2)
	mats.bush = _foliage(tex.leaves_small, 1.0)
	mats.litter = _foliage(tex.leaves, 0.0)
	for k in [["fern", 55.0], ["grass", 50.0], ["flower", 45.0], ["bush", 80.0], ["litter", 45.0]]:
		(mats[k[0]] as ShaderMaterial).set_shader_parameter("shrink_end", k[1])
	mats.bark_fir = _bark(_noise_tex(0.06, 3, Color("#3a2b22"), Color("#7a5a44"), Vector2.ONE, true), Vector3(6, 0.5, 6))
	mats.bark_oak = _bark(_noise_tex(0.05, 3, Color("#2e2925"), Color("#5f574c"), Vector2.ONE, true), Vector3(5, 0.7, 5))
	mats.bark_birch = _bark(_noise_tex(0.04, 2, Color("#2a2826"), Color("#ecebe4"), Vector2.ONE, false), Vector3(2, 6, 2))
	mats.rock = _bark(_noise_tex(0.03, 4, Color("#6a6862"), Color("#a6a49c"), Vector2.ONE, false), Vector3(0.6, 0.6, 0.6))
	mats.rock.cull_mode = BaseMaterial3D.CULL_DISABLED      # the blob's faces wind inward: draw both sides so it reads solid

## alpha cut-out foliage with soft lighting and wind; vertex/instance colour tints, vertex alpha = how much it sways
static func _foliage(t: Texture2D, wind: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _foliage_shader()
	m.set_shader_parameter("tex", t)
	m.set_shader_parameter("wind", wind)
	return m

static var _fsh: Shader
static func _foliage_shader() -> Shader:
	if _fsh: return _fsh
	_fsh = Shader.new()
	_fsh.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;
global uniform float detail_k;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float wind = 1.0;
uniform float cut = 0.45;
// level-of-detail blending: x..y fade in, z..w fade out (metres from the camera, per plant)
uniform vec4 fade = vec4(-2.0, -1.0, 100000.0, 100001.0);
uniform bool fade_inv = false;
// small plants shrink into the ground near this distance instead of popping out
uniform float shrink_end = -1.0;
varying float vfade;
void vertex() {
	vec3 org = MODEL_MATRIX[3].xyz;
	float d = distance(org, CAMERA_POSITION_WORLD) / max(detail_k, 0.05);
	vfade = smoothstep(fade.x, fade.y, d) * (1.0 - smoothstep(fade.z, fade.w, d));
	// small plants shrink away by distance, each at its own range (55-100% of shrink_end), so the edge of
	// the planted area thins out gradually instead of ending in a ring
	if (shrink_end > 0.0) {
		float r = fract(sin(dot(org.xz, vec2(12.9898, 78.233))) * 43758.5453);
		float e = shrink_end * mix(0.55, 1.0, r);
		VERTEX *= 1.0 - smoothstep(e * 0.75, e, d);
	}
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = COLOR.a * wind;
	float t = TIME;
	float gust = 0.6 + 0.4 * sin(t * 0.35 + wp.x * 0.02);
	VERTEX.x += (sin(t * 1.3 + wp.x * 0.21 + wp.z * 0.13) * 0.7 + sin(t * 3.9 + wp.y * 0.9 + wp.x) * 0.3) * 0.07 * w * gust;
	VERTEX.z += (cos(t * 1.1 + wp.z * 0.19 - wp.x * 0.1) * 0.7 + sin(t * 4.3 + wp.y * 0.8) * 0.3) * 0.07 * w * gust;
	VERTEX.y += sin(t * 2.7 + wp.x * 0.5 + wp.z * 0.4) * 0.025 * w;
	// fully faded out (another level of detail is showing): collapse it so it costs no pixels at all
	if (vfade <= 0.0) VERTEX = vec3(0.0);
}
void fragment() {
	if (vfade < 0.999) {
		// screen-door dither: the outgoing and incoming models use complementary pixels, so they cross-fade
		float h = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (fade_inv) h = 1.0 - h;
		if (h >= vfade) discard;
	}
	vec4 tx = texture(tex, UV);
	// keep leaves full at a distance: the blurrier mip levels average the leaf edges into the
	// background, so fewer pixels pass the cut-out and canopies thin out, then "pop" thick up close.
	// Boosting alpha by the mip level being read keeps the coverage about the same (Golus's trick)
	vec2 tuv = UV * vec2(textureSize(tex, 0));
	float mip = max(0.0, 0.5 * log2(max(dot(dFdx(tuv), dFdx(tuv)), dot(dFdy(tuv), dFdy(tuv)))));
	tx.a *= 1.0 + mip * 0.25;
	ALBEDO = tx.rgb * pow(COLOR.rgb, vec3(2.2));
	// the further off, the more the colour drains into the haze (foreground stays rich)
	float far_k = smoothstep(28.0, 190.0, length(VERTEX)) * 0.45;
	ALBEDO = mix(ALBEDO, vec3(dot(ALBEDO, vec3(0.3, 0.59, 0.11))) * vec3(0.94, 1.0, 1.06), far_k);
	ALPHA = tx.a;
	ALPHA_SCISSOR_THRESHOLD = cut;
	ROUGHNESS = 0.85;
}
"""
	return _fsh

static func _bark(t: Texture2D, scale: Vector3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.uv1_triplanar = true
	m.uv1_scale = scale
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	m.metallic_specular = 0.15
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	return m

# ================================================================ plant models
## mesh with a wood surface and one or more foliage surfaces
static func _mesh(parts: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	for p in parts:
		var mb: MeshBuilder = p[0]
		if mb.is_empty(): continue
		mb.commit(m)
		m.surface_set_material(m.get_surface_count() - 1, p[1])
	return m

static func _soft_normal(p: Vector3, center: Vector3) -> Vector3:
	return ((p - center).normalized() + Vector3(0, 0.6, 0)).normalized()

## a fir (Douglas-fir-like): straight trunk, whorls of drooping branches heavy with needle sprays,
## and a core of sprays round the trunk so you can't see straight through it. lod 0 = close-up, 1 = far
static func fir(seed: int, lod: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new(); r.seed = seed
	var H := r.randf_range(18.0, 26.0)
	var R0 := r.randf_range(0.24, 0.34)
	var wood := MeshBuilder.new(); var leaf := MeshBuilder.new()
	var wc := Color(1, 1, 1)
	var segs := 9 if lod == 0 else (6 if lod == 1 else 4)
	var n := 8 if lod < 2 else 2
	for i in range(n):
		var a := float(i) / n; var b := float(i + 1) / n
		var ra := R0 * (1.0 - a * 0.92) * (1.0 + 0.7 * exp(-a * H / 0.5)); var rb := R0 * (1.0 - b * 0.92) * (1.0 + 0.7 * exp(-b * H / 0.5))
		wood.tube(Vector3(0, a * H - (0.3 if i == 0 else 0.0), 0), Vector3(0, b * H, 0), ra, rb, wc, segs, false)
	var base := H * r.randf_range(0.28, 0.38)
	var ctr := Vector3(0, H * 0.6, 0)
	var green := Color(0.42, 0.57, 0.36)
	var y := base
	while y < H - 0.4:
		var t := (y - base) / (H - base)
		var spread := (1.0 - t) * r.randf_range(2.8, 3.6) + 0.5
		var nb := 6 if lod == 0 else (5 if lod == 1 else 3)
		var rot := r.randf() * TAU
		for k in range(nb):
			var az := rot + TAU * k / nb + r.randf_range(-0.25, 0.25)
			var d := Vector3(cos(az), 0, sin(az))
			var droop := r.randf_range(-0.38, -0.12) - t * 0.08
			var root := Vector3(0, y, 0)
			var tip := root + d * spread + Vector3(0, droop * spread, 0)
			if lod == 0 and spread > 0.9: wood.tube(root, tip, 0.04 * (1.0 - t) + 0.012, 0.008, wc, 4, false)
			var along := (tip - root).normalized()
			var side := along.cross(Vector3.UP).normalized()
			var up := side.cross(along).normalized()
			var cards := 2 if lod == 0 else 1
			for c in range(cards):
				var f := (c + 0.5) / cards if lod == 0 else 0.5
				var p := root.lerp(tip, f * 0.9 + 0.05)
				var sz := spread * (0.68 if lod == 0 else (0.95 if lod == 1 else 1.3)) + (0.3 if lod < 2 else 0.8)
				var tone := green * r.randf_range(0.78, 1.15)
				var nrm := _soft_normal(p, ctr)
				var sag := along.lerp(Vector3.DOWN, 0.18 + f * 0.25).normalized()
				leaf.card(p, sag * sz * 0.6, side * sz * 0.55, tone, nrm, Vector4(0, 0, 1, 1), 0.2, 0.9)
				if lod < 2: leaf.card(p, sag * sz * 0.6, (side * 0.4 + up * 0.9).normalized() * sz * 0.4, tone * 0.9, nrm, Vector4(0, 0, 1, 1), 0.2, 0.9)
		y += r.randf_range(0.42, 0.62) if lod == 0 else (r.randf_range(0.85, 1.1) if lod == 1 else r.randf_range(2.3, 2.7))
	# core: vertical crossed sprays hugging the trunk through the crown
	var cy := base + 0.6
	while cy < H - 0.5:
		var t := (cy - base) / (H - base)
		var cs := (1.0 - t) * 1.6 + 0.5
		for k in range(3 if lod == 0 else (2 if lod == 1 else 1)):
			var az := r.randf() * TAU
			var ax := Vector3(cos(az), 0, sin(az)) * cs
			leaf.card(Vector3(0, cy, 0), ax, Vector3(0, 0.9, 0), green * r.randf_range(0.7, 0.9), _soft_normal(Vector3(ax.x, cy, ax.z), ctr), Vector4(0, 0, 1, 1), 0.1, 0.5)
		cy += 1.6 if lod < 2 else 4.5
	leaf.card(Vector3(0, H - 0.3, 0), Vector3(0.0, 0.55, 0.0), Vector3(0.3, 0, 0), green, Vector3.UP, Vector4(0, 0, 1, 1), 0.3, 1.0)
	return _mesh([[wood, mats.bark_fir], [leaf, mats.fir]])

## a broadleaf tree: trunk splits into limbs and sub-limbs, leaf clusters at the ends
static func broadleaf(seed: int, lod: int, birch := false) -> ArrayMesh:
	var r := RandomNumberGenerator.new(); r.seed = seed
	var H := r.randf_range(9.0, 15.0) if not birch else r.randf_range(10.0, 16.0)
	var R0 := r.randf_range(0.18, 0.3) if not birch else r.randf_range(0.12, 0.18)
	var wood := MeshBuilder.new(); var leaf := MeshBuilder.new()
	var wc := Color(1, 1, 1)
	var segs := 7 if lod == 0 else (5 if lod == 1 else 4)
	var fork := H * r.randf_range(0.38, 0.52)
	wood.tube(Vector3(0, -0.2, 0), Vector3(0, fork, 0), R0 * 1.25, R0 * 0.8, wc, segs, false)
	var ctr := Vector3(0, H * 0.7, 0)
	var ends := []
	var grow := func(self_ref: Callable, from: Vector3, dir: Vector3, len: float, rad: float, depth: int) -> void:
		var to := from + dir * len
		if lod == 0 or depth < 2: wood.tube(from, to, rad, rad * 0.62, wc, maxi(3, segs - depth * 2), false)
		if depth >= 1: ends.append(from.lerp(to, 0.6))      # leaves along the outer limbs too, not just at the tips
		if depth >= (3 if lod == 0 else (2 if lod == 1 else 1)):
			ends.append(to); return
		var kids := r.randi_range(2, 3)
		for k in range(kids):
			var nd := (dir + Vector3(r.randf_range(-0.9, 0.9), r.randf_range(0.1, 0.6), r.randf_range(-0.9, 0.9))).normalized()
			self_ref.call(self_ref, to, nd, len * r.randf_range(0.6, 0.78), rad * 0.62, depth + 1)
	var limbs := r.randi_range(3, 4)
	for k in range(limbs):
		var az := TAU * k / limbs + r.randf_range(-0.4, 0.4)
		var d := Vector3(cos(az) * 0.55, 0.85, sin(az) * 0.55).normalized()
		grow.call(grow, Vector3(0, fork, 0), d, (H - fork) * r.randf_range(0.38, 0.5), R0 * 0.7, 0)
	# leaf clusters: crossed cards at the twig ends, plus fill toward the crown centre
	var tint: Color
	var pick := r.randf()
	if birch: tint = Color(0.86, 0.85, 0.42) if pick < 0.6 else Color(0.62, 0.72, 0.36)
	elif pick < 0.35: tint = Color(0.95, 0.55, 0.18)       # autumn orange
	elif pick < 0.55: tint = Color(0.92, 0.72, 0.25)       # gold
	elif pick < 0.7: tint = Color(0.75, 0.3, 0.18)         # red
	else: tint = Color(0.48, 0.65, 0.3)                    # still green
	var mat: Material = mats.leaves_small if birch else mats.leaves
	for e in ends:
		var count := 3 if lod == 0 else 1
		if lod == 2 and r.randf() < 0.5: continue
		for c in range(count):
			var p: Vector3 = e + Vector3(r.randf_range(-0.8, 0.8), r.randf_range(-0.4, 0.6), r.randf_range(-0.8, 0.8))
			var sz := r.randf_range(1.0, 1.45) * (1.0 if lod == 0 else (1.8 if lod == 1 else 3.1))
			var nrm := _soft_normal(p, ctr)
			var a := r.randf() * TAU
			var ax := Vector3(cos(a), 0, sin(a)) * sz; var ay := Vector3(0, sz * 0.9, 0)
			var col := tint * r.randf_range(0.82, 1.1)
			leaf.card(p, ax, ay, col, nrm, Vector4(0, 0, 1, 1), 0.5, 1.0)
			leaf.card(p, Vector3(-ax.z, 0, ax.x), ay, col * 0.95, nrm, Vector4(0, 0, 1, 1), 0.5, 1.0)
			if lod == 0: leaf.card(p, ax * 0.9, Vector3(-ax.z, 0, ax.x) * 0.9, col * 1.05, nrm, Vector4(0, 0, 1, 1), 0.5, 1.0)
	return _mesh([[wood, mats.bark_birch if birch else mats.bark_oak], [leaf, mat]])

## a dead snag: bare trunk, broken top, a few stubs
static func snag(seed: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new(); r.seed = seed
	var H := r.randf_range(6.0, 12.0); var R0 := r.randf_range(0.2, 0.3)
	var wood := MeshBuilder.new()
	wood.tube(Vector3(0, -0.2, 0), Vector3(r.randf_range(-0.3, 0.3), H, r.randf_range(-0.3, 0.3)), R0, R0 * 0.45, Color(0.85, 0.82, 0.78), 7, true)
	for k in range(5):
		var y := H * r.randf_range(0.4, 0.9); var az := r.randf() * TAU
		wood.tube(Vector3(0, y, 0), Vector3(cos(az) * 1.2, y + r.randf_range(-0.2, 0.6), sin(az) * 1.2), 0.05, 0.015, Color(0.8, 0.78, 0.74), 4)
	return _mesh([[wood, mats.bark_oak]])

## a fern: fronds radiating and arching over, each bent in three segments
static func fern(seed: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new(); r.seed = seed
	var mb := MeshBuilder.new()
	var n := r.randi_range(7, 11)
	var col := Color(0.66, 0.84, 0.42)
	for i in range(n):
		var az := TAU * i / n + r.randf_range(-0.2, 0.2)
		var d := Vector3(cos(az), 0, sin(az))
		var side := d.cross(Vector3.UP).normalized()
		var L := r.randf_range(0.7, 1.15)
		var rise := r.randf_range(0.55, 0.95)
		var pts := [Vector3.ZERO, d * L * 0.25 + Vector3(0, L * 0.45 * rise, 0), d * L * 0.62 + Vector3(0, L * 0.55 * rise, 0), d * L + Vector3(0, L * 0.28 * rise, 0)]
		var w := L * 0.28
		var tone := col * r.randf_range(0.8, 1.15)
		for s in range(3):
			var a: Vector3 = pts[s]; var b: Vector3 = pts[s + 1]
			var v0 := 1.0 - float(s) / 3.0; var v1 := 1.0 - float(s + 1) / 3.0
			var nrm := (Vector3.UP + d * 0.3).normalized()
			var i0 := mb.v(a - side * w, nrm, Color(tone.r, tone.g, tone.b, s / 3.0), Vector2(0, v0))
			var i1 := mb.v(a + side * w, nrm, Color(tone.r, tone.g, tone.b, s / 3.0), Vector2(1, v0))
			var i2 := mb.v(b + side * w, nrm, Color(tone.r, tone.g, tone.b, (s + 1) / 3.0), Vector2(1, v1))
			var i3 := mb.v(b - side * w, nrm, Color(tone.r, tone.g, tone.b, (s + 1) / 3.0), Vector2(0, v1))
			mb.quad(i0, i1, i2, i3)
	return _mesh([[mb, mats.fern]])

## fallen leaves: a few flat cards of autumn leaves lying on the forest floor
static func litter(seed: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new(); r.seed = seed
	var mb := MeshBuilder.new()
	for k in range(4):
		var p := Vector3(r.randf_range(-0.8, 0.8), 0.03 + k * 0.004, r.randf_range(-0.8, 0.8))
		var a := r.randf() * TAU; var sz := r.randf_range(0.5, 0.9)
		var col: Color = [Color(0.85, 0.5, 0.2), Color(0.7, 0.32, 0.16), Color(0.82, 0.66, 0.3), Color(0.55, 0.42, 0.25)][r.randi() % 4]
		mb.card(p, Vector3(cos(a), 0, sin(a)) * sz, Vector3(-sin(a), 0, cos(a)) * sz, col, Vector3.UP, Vector4(0, 0, 1, 1), 0.0, 0.0)
	return _mesh([[mb, mats.litter]])

## a leafy bush: a dome of leaf cards
static func bush(seed: int, tint: Color) -> ArrayMesh:
	var r := RandomNumberGenerator.new(); r.seed = seed
	var mb := MeshBuilder.new()
	var rad := r.randf_range(0.7, 1.3)
	var ctr := Vector3(0, rad * 0.5, 0)
	for i in range(18):
		var u := r.randf() * TAU; var vv := r.randf_range(0.0, 1.0)
		var p := ctr + Vector3(cos(u) * rad * (1 - vv * 0.5), vv * rad * 0.7 - 0.1, sin(u) * rad * (1 - vv * 0.5))
		var sz := r.randf_range(0.45, 0.7)
		var a := r.randf() * TAU
		var ax := Vector3(cos(a), r.randf_range(-0.3, 0.3), sin(a)).normalized() * sz
		var ay := ax.cross(Vector3(r.randf() - 0.5, 1, r.randf() - 0.5)).normalized() * sz
		mb.card(p, ax, ay, tint * r.randf_range(0.8, 1.1), _soft_normal(p, ctr - Vector3(0, 0.4, 0)), Vector4(0, 0, 1, 1), 0.3, 0.7)
	return _mesh([[mb, mats.bush]])

## a clump of tall grass (crossed cards) and a flower spike
static func grass_clump(seed: int, tall: float) -> ArrayMesh:
	var r := RandomNumberGenerator.new(); r.seed = seed
	var mb := MeshBuilder.new()
	for k in range(3):
		var a := TAU * k / 3 + r.randf_range(-0.3, 0.3)
		var ax := Vector3(cos(a), 0, sin(a)) * 0.35 * tall
		mb.card(Vector3(0, 0.33 * tall, 0), ax, Vector3(0, 0.34 * tall, 0), Color(0.62, 0.74, 0.4) * r.randf_range(0.85, 1.1), Vector3.UP, Vector4(0, 0, 1, 1), 0.0, 1.0)
	return _mesh([[mb, mats.grass]])

static func flower(seed: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new(); r.seed = seed
	var mb := MeshBuilder.new()
	var col: Color = [Color(0.9, 0.5, 0.75), Color(0.95, 0.95, 0.9), Color(0.75, 0.55, 0.9)][r.randi() % 3]
	for k in range(2):
		var a := PI * 0.5 * k + r.randf()
		mb.card(Vector3(0, 0.45, 0), Vector3(cos(a), 0, sin(a)) * 0.22, Vector3(0, 0.46, 0), col, Vector3.UP, Vector4(0, 0, 1, 1), 0.0, 1.0)
	return _mesh([[mb, mats.flower]])

## a mossy rock: a lumpy blob, grey with green on top
static func rock(seed: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new(); r.seed = seed
	var mb := MeshBuilder.new()
	var s := r.randf_range(0.4, 1.3)
	mb.push(Transform3D(Basis.from_scale(Vector3(1.3, 0.6, 1.0)), Vector3(0, s * 0.15, 0)))
	mb.blob(0, 0, 0, s, Color(0.85, 0.85, 0.8), r, 1.2)
	mb.pop()
	# moss: tint the upward-facing vertices green
	for i in range(mb.cols.size()):
		var up := mb.norms[i].y
		if up > 0.35: mb.cols[i] = mb.cols[i].lerp(Color(0.45, 0.58, 0.28), clampf((up - 0.35) * 1.8, 0, 0.85))
	return _mesh([[mb, mats.rock]])

## a fallen log, half sunk, mossy on top, with a broken end
static func fallen_log(seed: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new(); r.seed = seed
	var mb := MeshBuilder.new()
	var L := r.randf_range(3.0, 7.0); var R := r.randf_range(0.18, 0.32)
	mb.tube(Vector3(-L / 2, R * 0.6, 0), Vector3(L / 2, R * 0.55, 0), R, R * 0.8, Color(0.9, 0.88, 0.82), 9, true, Color(0.7, 0.55, 0.38))
	for i in range(mb.cols.size()):
		var up := mb.norms[i].y
		if up > 0.4: mb.cols[i] = mb.cols[i].lerp(Color(0.42, 0.55, 0.25), 0.8)
	for k in range(3):
		var x := r.randf_range(-L * 0.4, L * 0.4); var az := r.randf_range(-1, 1)
		mb.tube(Vector3(x, R * 0.9, 0), Vector3(x + 0.2, R * 0.9 + 0.5, sin(az) * 0.4), 0.04, 0.01, Color(0.8, 0.78, 0.72), 4)
	return _mesh([[mb, mats.bark_oak]])

static func old_stump(seed: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new(); r.seed = seed
	var mb := MeshBuilder.new()
	var R := r.randf_range(0.3, 0.55); var h := r.randf_range(0.3, 0.8)
	mb.cyl(0, -0.2, 0, R * 1.3, R, h + 0.2, Color(0.9, 0.88, 0.82), 10, true, Color(0.62, 0.5, 0.36))
	for i in range(mb.cols.size()):
		if mb.norms[i].y > 0.5: mb.cols[i] = Color(0.55, 0.45, 0.32)
	return _mesh([[mb, mats.bark_fir]])
