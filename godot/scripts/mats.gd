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
	glass = vcol.duplicate()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(1, 1, 1, 0.22)
	glass.roughness = 0.1; glass.metallic_specular = 0.9
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
uniform float wind = 0.09;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = VERTEX.y;
	VERTEX.x += sin(TIME * 1.7 + w.x * 0.35 + w.z * 0.21) * wind * h;
	VERTEX.z += cos(TIME * 1.3 + w.x * 0.27 - w.z * 0.3) * wind * h * 0.6;
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = 0.95;
}
"""
	grass.shader = sh
