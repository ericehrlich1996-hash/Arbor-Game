## Low-poly models built in code.
## Truck frame: +Z forward, +X is the driver's (left) side, origin on the ground midway between the axles.
class_name Models
extends RefCounted

const TRUCK_PAINT := [["#8b2a1f", "#ece6d8"], ["#2d4a7a", "#e9e6dc"], ["#6a4a2a", "#d8c49a"], ["#33503a", "#e6e2d4"], ["#a8742a", "#efe7d2"]]
const WHEEL_R := 0.4
const FRONT_AXLE := 1.62
const REAR_AXLE := -1.58
const TRACK := 0.86
const HITCH := Vector3(0, 0.5, -2.95)
const EYE := Vector3(0.40, 1.50, -0.20)

static func h(s: String) -> Color: return Color.html(s)
static func sh(c: Color, k: float) -> Color: return MeshBuilder.shade(c, k)

## returns {body, tailgate, c1, c2}; the model was drawn driver-on-−X, so it is mirrored into the truck frame
static func truck(rng: RandomNumberGenerator) -> Dictionary:
	var paint: Array = TRUCK_PAINT[rng.randi_range(0, TRUCK_PAINT.size() - 1)]
	var c1 := h(paint[0]); var c2 := h(paint[1])
	var mb := MeshBuilder.new(); var tg := MeshBuilder.new()
	var mirror := Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO)
	mb.push(mirror); tg.push(mirror)
	var chrome := h("#c9ccd0"); var black := h("#1c1d1f"); var dark := h("#2a2b2d"); var glassF := h("#1e2830")
	var vinyl := h("#b89a6a"); var dash := h("#3a2e26"); var rubber := h("#151515")
	var W2 := 1.0
	# front clip
	mb.box(0, 1.04, 1.62, 2.0, 0.5, 1.7, c1)
	mb.box(0, 1.31, 1.62, 1.94, 0.05, 1.66, sh(c1, 1.05))
	for sx in [-1.0, 1.0]: mb.box(sx * 0.98, 0.98, 1.62, 0.06, 0.36, 1.72, c2)
	for sx in [-1.0, 1.0]:
		for z in [FRONT_AXLE, REAR_AXLE]: mb.box(sx * 0.97, 0.62, z, 0.1, 0.4, 1.0, black)
	mb.box(0, 1.0, 2.48, 1.86, 0.5, 0.06, chrome); mb.box(0, 1.0, 2.505, 1.5, 0.36, 0.04, dark)
	for k in range(7): mb.box(0, 0.86 + k * 0.045, 2.53, 1.46, 0.012, 0.02, sh(chrome, 0.75))
	for sx in [-1.0, 1.0]:
		for yy in [1.06, 0.94]:
			mb.box(sx * 0.78, yy, 2.52, 0.26, 0.1, 0.04, h("#f4f0d8")); mb.box(sx * 0.78, yy, 2.505, 0.3, 0.13, 0.03, chrome)
	mb.box(0, 1.1, 2.535, 0.22, 0.08, 0.02, sh(c2, 0.9))
	mb.box(0, 0.62, 2.62, 2.06, 0.24, 0.16, chrome); mb.box(0, 0.52, 2.58, 1.7, 0.06, 0.1, dark)
	mb.box(0, 0.9, 2.0, 1.5, 0.8, 1.0, black)
	# cab
	var cz0 := -0.68; var cz1 := 0.78
	for sx in [-1.0, 1.0]:
		mb.box(sx * (W2 - 0.03), 0.98, (cz0 + cz1) / 2, 0.06, 0.66, cz1 - cz0, c1)
		mb.box(sx * (W2 - 0.02), 0.98, (cz0 + cz1) / 2, 0.03, 0.3, cz1 - cz0 - 0.06, c2)
	mb.box(0, 0.98, cz0 + 0.03, 2.0, 0.66, 0.06, c1)
	mb.box(0, 0.68, (cz0 + cz1) / 2, 2.0, 0.08, cz1 - cz0, black)
	var yb := 1.31; var yt := 1.95
	mb.box(0, yt, -0.08, 1.96, 0.07, 1.2, c2)
	for sx in [-1.0, 1.0]:
		mb.tube(Vector3(sx * 0.95, yb, 0.8), Vector3(sx * 0.93, yt - 0.02, 0.5), 0.035, 0.035, c2, 5)
		mb.box(sx * 0.96, (yb + yt) / 2, cz0 + 0.05, 0.08, yt - yb, 0.1, c2)
		mb.box(sx * 0.97, yb + 0.02, 0.06, 0.05, 0.05, 1.45, c1)
	mb.box(0, (yb + yt) / 2, cz0 + 0.03, 1.9, yt - yb, 0.05, c2); mb.box(0, 1.63, cz0 + 0.01, 1.0, 0.36, 0.06, glassF)
	mb.box(0, yt - 0.04, 0.52, 1.9, 0.06, 0.08, c2); mb.box(0, yb + 0.02, 0.8, 1.9, 0.05, 0.08, c2)
	for sx in [-1.0, 1.0]:
		mb.box(sx * 1.0, yt - 0.02, -0.08, 0.03, 0.03, 1.2, chrome)
		mb.tube(Vector3(sx * 0.98, 1.38, 0.66), Vector3(sx * 1.18, 1.48, 0.62), 0.012, 0.012, chrome, 4)
		mb.box(sx * 1.2, 1.52, 0.62, 0.05, 0.24, 0.16, chrome); mb.box(sx * 1.2, 1.52, 0.6, 0.04, 0.2, 0.12, h("#9ab0bf"))
	# interior
	mb.box(0, 1.06, 0.66, 1.9, 0.18, 0.26, dash); mb.box(0, 1.16, 0.6, 1.88, 0.04, 0.34, sh(dash, 1.15))
	mb.box(-0.4, 1.13, 0.5, 0.5, 0.16, 0.08, sh(dash, 0.8))
	for gx in [-0.52, -0.28]:
		mb.push(Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(gx, 1.1, 0.455)))
		mb.cyl(0, 0, 0, 0.07, 0.07, 0.01, h("#e8e2cc"), 14, true)
		mb.pop()
		mb.box(gx, 1.13, 0.445, 0.006, 0.06, 0.004, h("#c0392b"))
	mb.box(0.35, 1.03, 0.53, 0.45, 0.08, 0.02, h("#6a6f75"))
	var cx := -0.4; var cy := 1.12; var cz := 0.38; var r := 0.19
	mb.push(Transform3D(Basis(Vector3.RIGHT, -0.42), Vector3(cx, cy, cz)))
	for k in range(20):
		var a0 := TAU * k / 20; var a1 := TAU * (k + 1) / 20
		mb.tube(Vector3(cos(a0) * r, sin(a0) * r, 0), Vector3(cos(a1) * r, sin(a1) * r, 0), 0.016, 0.016, rubber, 6)
	mb.tube(Vector3.ZERO, Vector3(-r * 0.95, -0.03, 0), 0.014, 0.014, rubber, 5); mb.tube(Vector3.ZERO, Vector3(r * 0.95, -0.03, 0), 0.014, 0.014, rubber, 5)
	mb.pop()
	mb.tube(Vector3(cx, cy - 0.02, cz + 0.02), Vector3(cx, 1.0, 0.62), 0.03, 0.035, dark, 6)
	mb.tube(Vector3(cx + 0.06, 1.06, 0.44), Vector3(cx + 0.2, 1.0, 0.42), 0.008, 0.008, chrome, 4)
	mb.box(0, 0.72, -0.3, 1.84, 0.16, 0.5, vinyl); mb.box(0, 1.05, -0.56, 1.84, 0.62, 0.14, sh(vinyl, 0.95))
	for k in range(6): mb.box(-0.75 + k * 0.3, 1.05, -0.485, 0.02, 0.56, 0.01, sh(vinyl, 0.82))
	mb.box(0, yt - 0.06, -0.08, 1.88, 0.02, 1.18, h("#9a8f80"))
	mb.box(0, 1.86, 0.5, 0.06, 0.08, 0.03, h("#2a2d30")); mb.box(0, 1.79, 0.485, 0.40, 0.14, 0.03, h("#2a2d30"))
	for sx in [-1.0, 1.0]: mb.box(sx * 0.94, 0.98, 0.04, 0.03, 0.5, 1.3, sh(vinyl, 0.8))
	# bed
	var bz0 := -2.62; var bz1 := cz0 - 0.08
	for sx in [-1.0, 1.0]:
		mb.box(sx * 0.97, 1.0, (bz0 + bz1) / 2, 0.07, 0.62, bz1 - bz0, c1)
		mb.box(sx * 0.98, 0.98, (bz0 + bz1) / 2, 0.03, 0.3, bz1 - bz0, c2)
		mb.box(sx * 0.97, 1.33, (bz0 + bz1) / 2, 0.1, 0.04, bz1 - bz0, sh(c1, 1.1))
	mb.box(0, 0.77, (bz0 + bz1) / 2, 1.9, 0.06, bz1 - bz0, h("#3a3632"))
	for k in range(7): mb.box(-0.75 + k * 0.25, 0.805, (bz0 + bz1) / 2, 0.04, 0.02, bz1 - bz0, h("#4a4540"))
	mb.box(0, 1.0, bz1 + 0.02, 1.9, 0.62, 0.05, c1)
	tg.box(0, 1.0, bz0, 2.0, 0.62, 0.07, c1); tg.box(0, 0.98, bz0 - 0.03, 1.6, 0.08, 0.02, chrome)
	for sx in [-1.0, 1.0]: mb.box(sx * 0.92, 0.92, bz0 - 0.04, 0.14, 0.24, 0.03, h("#b8281e"))
	mb.box(0, 0.56, bz0 - 0.14, 2.0, 0.18, 0.14, chrome)
	mb.box(0, 0.5, bz0 - 0.32, 0.1, 0.06, 0.36, dark); mb.sphere(0, 0.58, HITCH.z, 0.05, 0.05, 0.05, chrome, 8, 6)
	mb.box(0, 0.5, 0, 1.1, 0.18, 4.6, black)
	return {body = mb, tailgate = tg, c1 = c1, c2 = c2}

static func wheel() -> MeshBuilder:
	var mb := MeshBuilder.new()
	mb.push(Transform3D(Basis(Vector3.BACK, PI / 2), Vector3.ZERO))
	mb.cyl(0, -0.14, 0, 0.4, 0.4, 0.28, h("#1a1a1a"), 18, true)
	mb.cyl(0, 0.141, 0, 0.24, 0.24, 0.005, h("#d8dadc"), 14, true)
	mb.cyl(0, 0.146, 0, 0.1, 0.1, 0.01, h("#9aa0a6"), 10, true)
	for k in range(6):
		var a := TAU * k / 6
		mb.box(cos(a) * 0.17, 0.149, sin(a) * 0.17, 0.03, 0.01, 0.03, h("#5a5f64"))
	mb.pop()
	return mb

## chipper frame: origin at the tongue coupler, body toward −Z, infeed faces −Z
const CHIP_AXLE := -2.3
static func chipper() -> MeshBuilder:
	var mb := MeshBuilder.new()
	var body := h("#d9861c"); var dk := h("#262729"); var steel := h("#6a6e72"); var yel := h("#e8c23a")
	mb.tube(Vector3(0, 0, 0), Vector3(-0.5, -0.08, -1.3), 0.04, 0.04, dk, 6); mb.tube(Vector3(0, 0, 0), Vector3(0.5, -0.08, -1.3), 0.04, 0.04, dk, 6)
	mb.box(0, 0, -0.05, 0.12, 0.08, 0.2, dk)
	mb.box(0, -0.05, -2.2, 1.1, 0.12, 2.0, dk)
	mb.box(0, 0.25, -0.4, 0.12, 0.5, 0.12, dk)
	mb.box(0, 0.5, -1.55, 1.1, 0.9, 1.0, body); mb.box(0, 0.98, -1.55, 1.0, 0.08, 0.9, sh(body, 1.1))
	for k in range(6): mb.box(0.56, 0.5, -1.25 - k * 0.1, 0.02, 0.5, 0.04, dk)
	mb.cyl(-0.3, 1.02, -1.3, 0.05, 0.05, 0.35, dk, 8)
	mb.box(0, 0.55, -2.45, 1.0, 1.1, 0.9, sh(body, 0.9))
	var hz := -2.9; var hz2 := -3.9
	mb.box(0, 0.5, hz - 0.05, 0.8, 0.7, 0.1, steel)
	mb.face([Vector3(-0.4, 0.15, hz), Vector3(0.4, 0.15, hz), Vector3(0.62, 0.05, hz2), Vector3(-0.62, 0.05, hz2)], steel)
	mb.face([Vector3(-0.4, 0.85, hz), Vector3(-0.62, 1.0, hz2), Vector3(0.62, 1.0, hz2), Vector3(0.4, 0.85, hz)], sh(steel, 0.9))
	mb.face([Vector3(-0.4, 0.15, hz), Vector3(-0.62, 0.05, hz2), Vector3(-0.62, 1.0, hz2), Vector3(-0.4, 0.85, hz)], sh(steel, 1.1))
	mb.face([Vector3(0.4, 0.15, hz), Vector3(0.4, 0.85, hz), Vector3(0.62, 1.0, hz2), Vector3(0.62, 0.05, hz2)], sh(steel, 1.1))
	mb.box(0, 0.5, hz + 0.02, 0.7, 0.6, 0.04, h("#111214"))
	mb.box(0, 1.06, hz2 + 0.06, 1.3, 0.05, 0.06, yel); mb.box(-0.66, 0.5, hz2 + 0.06, 0.05, 0.95, 0.06, yel); mb.box(0.66, 0.5, hz2 + 0.06, 0.05, 0.95, 0.06, yel)
	var p := Vector3(0, 1.05, -2.45)
	for k in range(6):
		var t := (k + 1) / 6.0
		var q := Vector3(0, 1.05 + sin(t * 1.4) * 0.95, -2.45 + t * 1.5)
		mb.tube(p, q, 0.15, 0.15, body, 8); p = q
	mb.box(0, p.y, p.z + 0.08, 0.32, 0.2, 0.16, sh(body, 0.85))
	for sx in [-1.0, 1.0]: mb.box(sx * 0.78, 0.32, CHIP_AXLE, 0.3, 0.06, 0.95, dk)
	for z in [-1.62, -2.5]:
		mb.box(-0.6, 0.28, z, 0.08, 0.42, 0.05, dk); mb.box(-0.7, 0.1, z, 0.2, 0.05, 0.05, dk)
	mb.box(-0.78, 0.12, -2.06, 0.04, 0.08, 1.0, steel); mb.box(-0.66, 0.12, -2.06, 0.04, 0.04, 1.0, steel); mb.box(-0.79, 0.19, -2.06, 0.02, 0.08, 1.0, yel)
	mb.box(0.551, 0.65, -2.45, 0.01, 0.18, 0.5, yel); mb.box(-0.551, 0.65, -2.45, 0.01, 0.18, 0.5, yel)
	return mb

static func jack() -> MeshBuilder:
	var mb := MeshBuilder.new()
	mb.cyl(0, -0.5, -0.4, 0.06, 0.06, 0.5, h("#6a6e72"), 8)
	mb.box(0, -0.48, -0.4, 0.2, 0.04, 0.2, h("#262729"))
	return mb

## Earl, in parts so he can be posed. Returns {torso, head, upper, fore, leg, cane}
static func old_man() -> Dictionary:
	var P := {}
	var skin := h("#e0b090"); var denim := h("#3d5a80"); var shirt := h("#b0302a"); var dkC := h("#262626"); var boot := h("#4a3626"); var white := h("#efede6"); var cap := h("#3e6a3a")
	var mb := MeshBuilder.new()
	mb.box(0, 0.28, 0, 0.42, 0.56, 0.25, shirt)
	for k in range(5): mb.box(0, 0.04 + k * 0.12, 0, 0.425, 0.025, 0.255, dkC)
	for k in range(4): mb.box(-0.15 + k * 0.1, 0.28, 0, 0.025, 0.56, 0.255, sh(shirt, 0.6))
	mb.box(0, 0.17, 0.13, 0.32, 0.36, 0.02, denim); mb.box(0, -0.02, 0, 0.43, 0.16, 0.26, denim)
	for sx in [-1.0, 1.0]: mb.box(sx * 0.11, 0.4, 0.13, 0.05, 0.3, 0.02, denim)
	mb.sphere(0, 0.38, 0, 0.24, 0.26, 0.15, shirt, 8, 5)
	P.torso = mb
	# head faces +Z
	mb = MeshBuilder.new()
	mb.cyl(0, 0, 0, 0.06, 0.06, 0.08, skin, 8); mb.sphere(0, 0.16, 0, 0.11, 0.13, 0.115, skin, 10, 7)
	mb.sphere(0, 0.08, 0.06, 0.1, 0.1, 0.08, white, 8, 6); mb.sphere(0, 0.12, 0.11, 0.09, 0.035, 0.04, white, 8, 4)
	mb.sphere(0, 0.16, 0.12, 0.025, 0.03, 0.03, sh(skin, 0.9), 6, 4)
	for sx in [-1.0, 1.0]:
		mb.sphere(sx * 0.045, 0.19, 0.1, 0.016, 0.012, 0.01, dkC, 6, 4); mb.box(sx * 0.045, 0.215, 0.105, 0.04, 0.012, 0.01, white)
	mb.box(0, 0.19, 0.112, 0.15, 0.008, 0.008, h("#8a8a8a"))
	mb.sphere(0, 0.25, 0, 0.12, 0.07, 0.12, cap, 10, 5); mb.box(0, 0.235, 0.14, 0.18, 0.02, 0.12, cap); mb.box(0, 0.29, 0, 0.2, 0.07, 0.2, cap); mb.box(0, 0.29, 0.101, 0.12, 0.06, 0.002, white)
	for k in range(7):
		var a := -1.2 + k * 0.4
		mb.tube(Vector3(sin(a) * 0.1, 0.2, -cos(a) * 0.1), Vector3(sin(a) * 0.18, 0.22 + (k % 2) * 0.04, -cos(a) * 0.17), 0.02, 0.004, white, 4)
	P.head = mb
	mb = MeshBuilder.new()
	mb.tube(Vector3.ZERO, Vector3(0, -0.3, 0), 0.055, 0.05, shirt, 7)
	for k in range(3): mb.cyl(0, -0.08 - k * 0.08, 0, 0.057, 0.057, 0.02, dkC, 7, false)
	P.upper = mb
	mb = MeshBuilder.new()
	mb.tube(Vector3.ZERO, Vector3(0, -0.26, 0), 0.048, 0.04, shirt, 7); mb.sphere(0, -0.31, 0, 0.05, 0.06, 0.035, skin, 7, 5)
	P.fore = mb
	mb = MeshBuilder.new()
	mb.tube(Vector3.ZERO, Vector3(0, -0.84, 0), 0.08, 0.07, denim, 8); mb.box(0, -0.86, 0.04, 0.12, 0.09, 0.26, boot)
	P.leg = mb
	mb = MeshBuilder.new()
	mb.tube(Vector3.ZERO, Vector3(0, -0.9, 0), 0.015, 0.015, h("#6a4a2a"), 5); mb.tube(Vector3.ZERO, Vector3(0, 0.04, 0.1), 0.015, 0.015, h("#6a4a2a"), 5)
	P.cane = mb
	return P

## chainsaw in saw space: −Z forward along the bar, origin at the rear handle; bar tip near (0,0,−0.83)
static func chainsaw() -> MeshBuilder:
	var mb := MeshBuilder.new()
	var orange := h("#e8661c"); var white := h("#ecebe6"); var dk := h("#232426"); var steel := h("#8a8e92")
	mb.box(0, 0.05, -0.16, 0.11, 0.15, 0.26, orange); mb.box(0, 0.135, -0.16, 0.105, 0.03, 0.22, white)
	mb.box(0.06, 0.04, -0.12, 0.02, 0.1, 0.14, dk); mb.box(-0.062, 0.05, -0.2, 0.02, 0.08, 0.12, steel)
	mb.box(0, 0.07, -0.02, 0.05, 0.06, 0.06, dk)
	mb.tube(Vector3(0, 0.02, 0.02), Vector3(0, 0.02, 0.09), 0.022, 0.022, dk, 6); mb.tube(Vector3(0, 0.02, 0.09), Vector3(0, 0.09, 0.07), 0.02, 0.02, dk, 6); mb.tube(Vector3(0, 0.09, 0.07), Vector3(0, 0.1, -0.01), 0.02, 0.02, dk, 6)
	mb.tube(Vector3(-0.07, -0.02, -0.24), Vector3(-0.07, 0.17, -0.24), 0.015, 0.015, dk, 6); mb.tube(Vector3(-0.07, 0.17, -0.24), Vector3(0.06, 0.17, -0.2), 0.015, 0.015, dk, 6); mb.tube(Vector3(0.06, 0.17, -0.2), Vector3(0.06, 0.05, -0.18), 0.015, 0.015, dk, 6)
	mb.box(0, 0.19, -0.27, 0.09, 0.07, 0.012, dk)
	mb.box(0.03, 0.13, -0.05, 0.03, 0.025, 0.04, h("#eeeeee")); mb.box(0.06, 0.08, -0.08, 0.025, 0.02, 0.03, dk)
	mb.box(0, 0, -0.52, 0.012, 0.07, 0.62, steel); mb.box(0, 0, -0.52, 0.016, 0.075, 0.6, dk); mb.box(0, 0, -0.52, 0.013, 0.055, 0.62, steel)
	mb.sphere(0, 0, -0.83, 0.012, 0.037, 0.02, steel, 6, 4)
	for k in range(26):
		var z := -0.24 - k * 0.023
		mb.box(0, 0.04, z, 0.016, 0.012, 0.012, dk); mb.box(0, -0.04, z, 0.016, 0.012, 0.012, dk)
	mb.box(0, 0, -0.22, 0.06, 0.09, 0.04, dk)
	return mb

## gloved fist around a bar that runs along local X; knuckles toward −Z
static func fist(side: float) -> MeshBuilder:
	var mb := MeshBuilder.new()
	var glove := h("#c9a46a"); var gD := h("#a8844c"); var cuff := h("#8a6a3a")
	mb.sphere(0, 0.028, 0.012, 0.042, 0.022, 0.036, glove, 10, 6)
	for k in range(4):
		var x := -0.033 + k * 0.022
		var a := Vector3(x, 0.03, -0.022); var b := Vector3(x, 0.004, -0.03); var c := Vector3(x, -0.022, -0.012); var d := Vector3(x, -0.018, 0.012)
		mb.tube(a, b, 0.0105, 0.0102, sh(glove, 0.97), 6); mb.tube(b, c, 0.0102, 0.0098, glove, 6); mb.tube(c, d, 0.0098, 0.009, sh(glove, 0.94), 6)
		mb.sphere(x, 0.03, -0.02, 0.012, 0.012, 0.012, gD, 6, 4)
	mb.tube(Vector3(side * 0.045, 0.02, 0.01), Vector3(side * 0.05, -0.005, -0.02), 0.012, 0.011, glove, 6)
	mb.tube(Vector3(side * 0.05, -0.005, -0.02), Vector3(side * 0.03, -0.022, -0.028), 0.011, 0.01, glove, 6)
	mb.tube(Vector3(0, 0.026, 0.03), Vector3(0, 0.02, 0.07), 0.036, 0.04, cuff, 9)
	return mb

## open glove + sleeve reaching back toward the camera (idle hands)
static func glove(side: float) -> MeshBuilder:
	var mb := MeshBuilder.new()
	var gl := h("#c9a46a"); var cuff := h("#9c7a44"); var sleeve := h("#5a6a3a")
	mb.sphere(0, 0, 0, 0.05, 0.045, 0.065, gl, 8, 6)
	for k in range(4): mb.tube(Vector3(-0.03 + k * 0.02, 0.02, -0.04), Vector3(-0.03 + k * 0.02, -0.035, -0.06), 0.014, 0.012, sh(gl, 0.95), 5)
	mb.tube(Vector3(side * -0.035, 0, 0.02), Vector3(side * -0.05, -0.03, -0.04), 0.016, 0.014, gl, 5)
	mb.tube(Vector3(0, 0, 0.04), Vector3(side * 0.06, -0.12, 0.3), 0.05, 0.06, cuff, 7)
	mb.tube(Vector3(side * 0.06, -0.12, 0.3), Vector3(side * 0.14, -0.26, 0.62), 0.06, 0.075, sleeve, 8)
	return mb

## sleeve from the origin to (0,1,0); scaled per frame from wrist toward shoulder
static func arm() -> MeshBuilder:
	var mb := MeshBuilder.new()
	var sleeve := h("#5a6a3a")
	mb.cyl(0, 0, 0, 1, 1.15, 1, sleeve, 10, false)
	for k in range(2): mb.cyl(0, 0.12 + k * 0.05, 0, 1.04, 1.04, 0.02, sh(sleeve, 0.75), 10, false)
	return mb

static func can() -> MeshBuilder:
	var mb := MeshBuilder.new()
	var g := h("#1d1f22"); var lime := h("#8be02c"); var al := h("#c8ccd0")
	mb.cyl(0, 0, 0, 0.033, 0.033, 0.16, g, 14, true, al)
	mb.cyl(0, 0.03, 0, 0.0335, 0.0335, 0.03, lime, 14, false); mb.cyl(0, 0.1, 0, 0.0335, 0.0335, 0.015, lime, 14, false)
	mb.cyl(0, 0.16, 0, 0.033, 0.026, 0.012, al, 14, true)
	return mb
