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

var bark: StandardMaterial3D        # weathered grey bark, mapped in the piece's own frame so it rides with it
var sap: StandardMaterial3D         # fresh-cut wood
var sap_v: StandardMaterial3D       # fresh-cut wood, vertex coloured (limb ends)

func _ready() -> void:
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_CELLULAR
	nz.frequency = 0.035
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM; nz.fractal_octaves = 3
	var g := Gradient.new()
	g.set_color(0, Color("#3a3631")); g.set_color(1, Color("#8f897d"))
	g.add_point(0.5, Color("#615b52"))
	var tex := NoiseTexture2D.new(); tex.noise = nz; tex.color_ramp = g; tex.width = 256; tex.height = 256; tex.seamless = true
	bark = StandardMaterial3D.new()
	bark.albedo_texture = tex
	bark.uv1_triplanar = true
	bark.uv1_scale = Vector3(3.5, 0.9, 3.5)
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
