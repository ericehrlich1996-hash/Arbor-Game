## Shared materials (autoload "Mats").
extends Node

var vcol: StandardMaterial3D        # opaque, vertex coloured, double sided
var vcol_glass: StandardMaterial3D  # see-through (tailgate)
var terrain: StandardMaterial3D

func _init() -> void:
	vcol = StandardMaterial3D.new()
	vcol.vertex_color_use_as_albedo = true
	vcol.vertex_color_is_srgb = true
	vcol.cull_mode = BaseMaterial3D.CULL_DISABLED
	vcol.roughness = 0.9
	vcol.metallic_specular = 0.2
	vcol.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP        # broad, soft light-to-shadow, like baked lighting
	vcol_glass = vcol.duplicate()
	vcol_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vcol_glass.albedo_color = Color(1, 1, 1, 0.28)
	terrain = vcol.duplicate()
	terrain.roughness = 1.0
	terrain.cull_mode = BaseMaterial3D.CULL_BACK

var bark: StandardMaterial3D        # weathered grey bark, mapped in the piece's own frame so it rides with it
var sap: StandardMaterial3D         # fresh-cut wood
var sap_v: StandardMaterial3D       # fresh-cut wood, vertex coloured (limb ends)
var grass: ShaderMaterial
var glass: StandardMaterial3D
var paint: StandardMaterial3D
var chrome: StandardMaterial3D
var lamp: StandardMaterial3D
var truck_paint: ShaderMaterial    # faded paint eaten through with rust, grime low down
var truck_chrome: ShaderMaterial
var truck_glass: StandardMaterial3D

const RUST_SHADER := """
shader_type spatial;
uniform float rust = 0.75;
uniform float metal = 0.0;
uniform float shine = 0.45;
varying vec3 lp;
float h3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float n3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1,0,0)), f.x), mix(h3(i + vec3(0,1,0)), h3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h3(i + vec3(0,0,1)), h3(i + vec3(1,0,1)), f.x), mix(h3(i + vec3(0,1,1)), h3(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { v += a * n3(p); p = p * 2.07 + 3.1; a *= 0.5; } return v; }
void vertex() { lp = VERTEX; }
void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	// sun-baked paint: chalky and faded
	vec3 faded = mix(base, vec3(dot(base, vec3(0.3, 0.5, 0.2))), 0.3 * rust) * (1.0 - 0.12 * rust) + 0.02 * rust;
	// rust: blooms from the bottom edges up, plus scattered patches and pitting
	float low = 1.0 - smoothstep(0.45, 1.35, lp.y);
	float m = fbm(lp * 2.1) + low * 0.6 * rust + (n3(lp * 22.0) - 0.5) * 0.18;
	float r = smoothstep(0.78 - rust * 0.32, 0.86 - rust * 0.3, m);
	float pit = step(0.975 - rust * 0.03, n3(lp * 48.0)) * rust;
	r = max(r, pit * 0.8) * smoothstep(0.0, 0.15, rust);
	vec3 rc = mix(vec3(0.2, 0.085, 0.035), vec3(0.52, 0.24, 0.08), n3(lp * 9.0));
	rc = mix(rc, vec3(0.45, 0.27, 0.12), smoothstep(0.7, 0.95, n3(lp * 17.0)) * 0.5);
	// a dirty halo where paint meets rust, and road grime along the bottom
	float halo = smoothstep(0.62 - rust * 0.3, 0.78 - rust * 0.3, m) * (1.0 - r) * smoothstep(0.0, 0.15, rust);
	vec3 col = mix(faded, faded * 0.62 + vec3(0.04, 0.025, 0.01), halo * 0.8);
	col = mix(col, rc, r);
	col *= 1.0 - low * 0.2 * rust;
	ALBEDO = col;
	ROUGHNESS = mix(shine, 0.97, max(r, low * 0.5 * rust));
	METALLIC = metal * (1.0 - r);
}
"""

var truck_rust := 1.0

## how rusty the old truck is (1 = as found; fixing it up brings this down)
func set_truck_rust(k: float) -> void:
	truck_rust = k
	truck_paint.set_shader_parameter("rust", 1.0 * k)
	truck_chrome.set_shader_parameter("rust", 0.6 * k)
	# fixed up: glossy fresh paint, bright chrome, clean glass
	truck_paint.set_shader_parameter("shine", lerpf(0.22, 0.45, k))
	truck_chrome.set_shader_parameter("shine", lerpf(0.15, 0.35, k))
	truck_chrome.set_shader_parameter("metal", lerpf(0.85, 0.55, k))
	if truck_glass:
		truck_glass.albedo_color = Color(1, 1, 1, 0.22).lerp(Color(0.82, 0.78, 0.66, 0.34), k)
		truck_glass.roughness = lerpf(0.1, 0.45, k)

func _ready() -> void:
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_CELLULAR
	nz.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	nz.frequency = 0.03
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM; nz.fractal_octaves = 3
	var g := Gradient.new()
	g.set_color(0, Color("#4a443c")); g.set_color(1, Color("#9a9384"))
	g.add_point(0.45, Color("#6e675c"))
	var tex := NoiseTexture2D.new(); tex.noise = nz; tex.color_ramp = g; tex.width = 256; tex.height = 256; tex.seamless = true
	bark = StandardMaterial3D.new()
	bark.albedo_texture = tex
	bark.uv1_triplanar = true
	bark.uv1_scale = Vector3(5.0, 0.7, 5.0)
	bark.roughness = 0.95
	bark.cull_mode = BaseMaterial3D.CULL_DISABLED
	var nz2 := FastNoiseLite.new(); nz2.frequency = 0.08
	var g2 := Gradient.new(); g2.set_color(0, Color("#cdb98e")); g2.set_color(1, Color("#ead9ae"))
	var tex2 := NoiseTexture2D.new(); tex2.noise = nz2; tex2.color_ramp = g2; tex2.width = 128; tex2.height = 128; tex2.seamless = true
	sap = StandardMaterial3D.new()
	sap.albedo_texture = tex2
	sap.uv1_triplanar = true
	sap.uv1_scale = Vector3(6, 6, 6)
	sap.roughness = 0.9
	sap.cull_mode = BaseMaterial3D.CULL_DISABLED
	sap_v = vcol.duplicate()
	paint = vcol.duplicate(); paint.roughness = 0.42; paint.metallic_specular = 0.6
	chrome = vcol.duplicate(); chrome.metallic = 0.85; chrome.roughness = 0.22
	lamp = vcol.duplicate(); lamp.emission_enabled = true; lamp.emission = Color(0.25, 0.22, 0.18); lamp.roughness = 0.2
	var rsh := Shader.new(); rsh.code = RUST_SHADER
	truck_paint = ShaderMaterial.new(); truck_paint.shader = rsh
	truck_chrome = ShaderMaterial.new(); truck_chrome.shader = rsh
	truck_chrome.set_shader_parameter("metal", 0.55); truck_chrome.set_shader_parameter("shine", 0.35)
	set_truck_rust(1.0)
	glass = vcol.duplicate()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(1, 1, 1, 0.22)
	glass.roughness = 0.1; glass.metallic_specular = 0.9
	truck_glass = glass.duplicate()
	truck_glass.albedo_color = Color(0.82, 0.78, 0.66, 0.34)     # years of grime and pollen
	truck_glass.roughness = 0.45
	# ground: a soft mottled detail texture in world space, multiplied over the painted colours
	var gn := FastNoiseLite.new(); gn.frequency = 0.02; gn.fractal_octaves = 4
	var gg := Gradient.new(); gg.set_color(0, Color(0.8, 0.82, 0.78)); gg.set_color(1, Color(1.06, 1.06, 1.0))
	var gt := NoiseTexture2D.new(); gt.noise = gn; gt.color_ramp = gg; gt.width = 512; gt.height = 512; gt.seamless = true
	terrain.albedo_texture = gt
	terrain.uv1_triplanar = true; terrain.uv1_world_triplanar = true
	terrain.uv1_scale = Vector3(0.12, 0.12, 0.12)
	# grass tufts: vertex colours, a little sway in the wind
	grass = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, specular_disabled;
global uniform float detail_k;
uniform float wind = 0.09;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX *= 1.0 - smoothstep(26.0, 37.0, distance(w, CAMERA_POSITION_WORLD) / max(detail_k, 0.05));   // grows in, no popping
	float h = VERTEX.y;
	VERTEX.x += sin(TIME * 1.7 + w.x * 0.35 + w.z * 0.21) * wind * h;
	VERTEX.z += cos(TIME * 1.3 + w.x * 0.27 - w.z * 0.3) * wind * h * 0.6;
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = mix(ALBEDO, vec3(dot(ALBEDO, vec3(0.3, 0.59, 0.11))), smoothstep(20.0, 60.0, length(VERTEX)) * 0.3);
	ROUGHNESS = 0.95;
}
"""
	grass.shader = sh
