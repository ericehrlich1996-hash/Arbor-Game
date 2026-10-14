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

## the '80s square-body, built as separate surfaces: paint, chrome, dark trim/interior, glass, lamps,
## and the see-through tailgate. Returns {paint, chrome, dark, glass, lamps, tailgate, c1, c2}
static func truck(rng: RandomNumberGenerator) -> Dictionary:
	var paint_pair: Array = TRUCK_PAINT[rng.randi_range(0, TRUCK_PAINT.size() - 1)]
	var c1 := h(paint_pair[0]); var c2 := h(paint_pair[1])
	var P := MeshBuilder.new(); var C := MeshBuilder.new(); var D := MeshBuilder.new()
	var G := MeshBuilder.new(); var L := MeshBuilder.new(); var TG := MeshBuilder.new()
	var mirror := Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO)
	for m in [P, C, D, G, L, TG]: m.push(mirror)
	var chrome := h("#d4d8dc"); var black := h("#17181a"); var dark := h("#26272a"); var rubber := h("#121212")
	var vinyl := h("#b89a6a"); var dash := h("#3a2e26")
	var W2 := 1.0
	var cz0 := -0.68; var cz1 := 0.78           # cab
	var bz0 := -2.62; var bz1 := cz0 - 0.08     # bed
	var fz1 := 2.46                             # front of the fenders
	# ---------------- body sides with real wheel arches
	var arch := func(z: float, axle: float) -> float:
		var dz := absf(z - axle)
		return maxf(0.56, 0.42 + sqrt(maxf(0.0, 0.25 - dz * dz))) if dz < 0.5 else 0.56
	for sx in [-1.0, 1.0]:
		for seg in [[cz1, fz1, Models.FRONT_AXLE, 1.29], [cz0, cz1, 99.0, 1.31], [bz0, bz1, Models.REAR_AXLE, 1.31]]:
			var z0: float = seg[0]; var z1: float = seg[1]; var ax: float = seg[2]; var top: float = seg[3]
			var n := maxi(2, int((z1 - z0) / 0.05))
			for i in range(n):
				var za := lerpf(z0, z1, float(i) / n); var zb := lerpf(z0, z1, float(i + 1) / n)
				var ya: float = arch.call(za, ax); var yb: float = arch.call(zb, ax)
				var nrm := Vector3(sx, 0, 0)
				# lower body in the main colour, a two-tone band through the middle
				for band in [[ya, 0.86, c1], [0.86, 1.06, c2], [1.06, top, c1]]:
					var lo: float = maxf(band[0], ya if band[0] == ya else band[0]); var hi: float = band[1]
					var lo_b: float = yb if band[0] == ya else band[0]
					if hi <= lo and hi <= lo_b: continue
					var i0 := P.v(Vector3(sx * W2, maxf(lo, minf(ya, hi)), za), nrm, band[2]); var i1 := P.v(Vector3(sx * W2, maxf(lo_b, minf(yb, hi)), zb), nrm, band[2])
					var i2 := P.v(Vector3(sx * W2, hi, zb), nrm, band[2]); var i3 := P.v(Vector3(sx * W2, hi, za), nrm, band[2])
					if sx > 0: P.quad(i0, i1, i2, i3)
					else: P.quad(i0, i3, i2, i1)
			# wheel well liner and a rubber lip around the arch
			if ax < 90:
				# only the arch above the sill line, so nothing hangs down below the body
				var t0 := asin((0.56 - 0.42) / 0.5)
				for k in range(12):
					var ta := lerpf(t0, PI - t0, k / 12.0); var tb := lerpf(t0, PI - t0, (k + 1) / 12.0)
					var pa := Vector3(0, 0.42 + sin(ta) * 0.5, ax + cos(ta) * 0.5); var pb := Vector3(0, 0.42 + sin(tb) * 0.5, ax + cos(tb) * 0.5)
					var nn := -Vector3(0, sin(ta), cos(ta))
					var q0 := D.v(pa + Vector3(sx * 0.6, 0, 0), nn, black); var q1 := D.v(pb + Vector3(sx * 0.6, 0, 0), nn, black)
					var q2 := D.v(pb + Vector3(sx * 0.99, 0, 0), nn, black); var q3 := D.v(pa + Vector3(sx * 0.99, 0, 0), nn, black)
					D.quad(q0, q1, q2, q3); D.quad(q0, q3, q2, q1)
				var prev := Vector3.ZERO
				for k in range(13):
					var t := PI * k / 12.0
					var q := Vector3(sx * (W2 + 0.012), 0.42 + sin(t) * 0.5, ax + cos(t) * 0.5)
					if q.y >= 0.55 and k > 0 and prev.y >= 0.55: D.tube(prev, q, 0.022, 0.022, rubber, 5)
					prev = q
		# chrome side trim along the two-tone band and the bed rail cap
		C.box(sx * (W2 + 0.006), 0.86, (bz0 + fz1) / 2, 0.012, 0.018, fz1 - bz0 - 0.1, chrome)
		C.box(sx * (W2 + 0.006), 1.06, (bz0 + fz1) / 2, 0.012, 0.018, fz1 - bz0 - 0.1, chrome)
		P.bevel_box(sx * 0.955, 1.33, (bz0 + bz1) / 2, 0.11, 0.05, bz1 - bz0, MeshBuilder.shade(c1, 1.08), 0.015)
		for z in [-2.45, -1.25]: D.box(sx * 0.955, 1.36, z, 0.05, 0.01, 0.07, black)          # stake pockets
		# rocker panel and door seams, handle
		D.box(sx * (W2 - 0.01), 0.58, (cz0 + cz1) / 2, 0.03, 0.06, cz1 - cz0, dark)
		for z in [cz0 + 0.02, cz1 - 0.02]: D.box(sx * (W2 + 0.004), 0.98, z, 0.008, 0.66, 0.008, black)
		C.bevel_box(sx * (W2 + 0.015), 1.2, cz0 + 0.22, 0.02, 0.035, 0.13, chrome, 0.008)
		# fuel filler on the bed side
		D.cyl(sx * (W2 + 0.002), 1.1, -1.0, 0.05, 0.05, 0.0, dark, 10, false)
	# ---------------- front end
	P.bevel_box(0, 1.27, (cz1 + fz1) / 2 + 0.01, 1.98, 0.06, fz1 - cz1, c1, 0.025)                  # hood
	P.bevel_box(0, 1.305, (cz1 + fz1) / 2 + 0.05, 1.1, 0.02, fz1 - cz1 - 0.15, MeshBuilder.shade(c1, 1.04), 0.01)   # hood crown
	D.box(0, 0.95, 1.65, 1.95, 0.6, 1.6, black)                                                       # engine bay fill
	C.bevel_box(0, 1.02, fz1 + 0.02, 1.92, 0.5, 0.05, chrome, 0.02)                                   # grille surround
	D.box(0, 1.02, fz1 + 0.04, 1.5, 0.36, 0.04, dark)
	for k in range(6): C.box(0, 0.88 + k * 0.056, fz1 + 0.065, 1.48, 0.012, 0.012, MeshBuilder.shade(chrome, 0.8))
	for k in range(7): C.box(-0.6 + k * 0.2, 1.02, fz1 + 0.066, 0.012, 0.34, 0.012, MeshBuilder.shade(chrome, 0.8))
	for sx in [-1.0, 1.0]:
		for yy in [1.085, 0.955]:
			C.bevel_box(sx * 0.82, yy, fz1 + 0.05, 0.3, 0.12, 0.04, chrome, 0.01)
			L.box(sx * 0.82, yy, fz1 + 0.075, 0.24, 0.085, 0.02, h("#fff6d8"))
		L.box(sx * 0.82, 0.8, fz1 + 0.05, 0.22, 0.05, 0.03, h("#e89a2a"))        # turn signals
		L.box(sx * 1.003, 1.0, 2.25, 0.01, 0.06, 0.12, h("#e89a2a"))              # side markers
	C.bevel_box(0, 0.64, 2.6, 2.08, 0.22, 0.16, chrome, 0.04)                                        # bumper
	D.box(0, 0.64, 2.685, 1.9, 0.04, 0.01, rubber)
	D.box(0, 0.5, 2.52, 1.8, 0.1, 0.12, dark)                                                         # valance
	# ---------------- cab
	P.bevel_box(0, 1.95, -0.06, 1.98, 0.08, 1.28, c2, 0.03)                                           # roof
	D.box(0, 1.89, -0.06, 1.88, 0.02, 1.2, h("#9a8f80"))                                              # headliner
	P.box(0, 0.98, cz0 + 0.03, 2.0, 0.66, 0.06, c1)                                                   # back wall (lower)
	var yb := 1.31; var yt := 1.92
	for sx in [-1.0, 1.0]:
		P.tube(Vector3(sx * 0.95, yb, 0.8), Vector3(sx * 0.93, yt, 0.5), 0.04, 0.035, c2, 6)            # A pillars
		P.bevel_box(sx * 0.955, (yb + yt) / 2, cz0 + 0.06, 0.09, yt - yb, 0.12, c2, 0.02)             # B pillars
		C.box(sx * 1.0, yt + 0.02, -0.06, 0.025, 0.025, 1.24, chrome)                                  # drip rails
		# side glass and its frame
		G.box(sx * 0.955, (yb + yt) / 2, 0.06, 0.01, yt - yb - 0.04, 1.2, Color(0.55, 0.68, 0.78))
		C.box(sx * 0.97, yb + 0.012, 0.06, 0.03, 0.02, 1.32, chrome)
		# mirrors
		C.tube(Vector3(sx * 0.99, 1.38, 0.66), Vector3(sx * 1.17, 1.48, 0.62), 0.012, 0.012, chrome, 5)
		C.bevel_box(sx * 1.2, 1.52, 0.62, 0.05, 0.24, 0.16, chrome, 0.015)
		G.box(sx * 1.2, 1.52, 0.6, 0.04, 0.2, 0.12, h("#9ab0bf"))
	# back wall around the rear window
	P.box(0, (yb + 1.45) / 2, cz0 + 0.03, 1.9, 1.45 - yb, 0.05, c2); P.box(0, (1.81 + yt) / 2, cz0 + 0.03, 1.9, yt - 1.81, 0.05, c2)
	for sx in [-1.0, 1.0]: P.box(sx * 0.725, 1.63, cz0 + 0.03, 0.45, 0.36, 0.05, c2)
	G.box(0, 1.63, cz0 + 0.03, 1.0, 0.36, 0.012, Color(0.55, 0.68, 0.78))
	# windshield (slanted) and wipers
	var ws := Basis(Vector3.RIGHT, -0.42)
	G.push(Transform3D(ws, Vector3(0, (yb + yt) / 2, 0.66)))
	G.box(0, 0, 0, 1.84, (yt - yb) / cos(0.42), 0.01, Color(0.55, 0.68, 0.78))
	G.pop()
	P.bevel_box(0, yt - 0.03, 0.52, 1.9, 0.06, 0.08, c2, 0.02)
	P.box(0, yb + 0.02, 0.82, 1.92, 0.04, 0.1, c1)                                                    # cowl
	for sx in [-0.45, 0.35]: D.tube(Vector3(sx, yb + 0.05, 0.84), Vector3(sx + 0.4, yb + 0.12, 0.78), 0.008, 0.008, black, 4)
	# ---------------- interior (the dash, gauges, wheel, bench seat)
	D.box(0, 1.06, 0.66, 1.9, 0.18, 0.26, dash); D.bevel_box(0, 1.16, 0.6, 1.88, 0.05, 0.34, MeshBuilder.shade(dash, 1.15), 0.02)
	D.bevel_box(-0.4, 1.13, 0.5, 0.5, 0.16, 0.08, MeshBuilder.shade(dash, 0.8), 0.02)
	for gx in [-0.52, -0.28]:
		D.push(Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(gx, 1.1, 0.455)))
		D.cyl(0, 0, 0, 0.07, 0.07, 0.01, h("#e8e2cc"), 16, true)
		D.pop()
		D.box(gx, 1.13, 0.445, 0.006, 0.06, 0.004, h("#c0392b"))
	D.box(0.35, 1.03, 0.53, 0.45, 0.08, 0.02, h("#6a6f75"))
	var cx := -0.4; var cy := 1.12; var czw := 0.38; var r := 0.19
	D.push(Transform3D(Basis(Vector3.RIGHT, -0.42), Vector3(cx, cy, czw)))
	for k in range(24):
		var a0 := TAU * k / 24; var a1 := TAU * (k + 1) / 24
		D.tube(Vector3(cos(a0) * r, sin(a0) * r, 0), Vector3(cos(a1) * r, sin(a1) * r, 0), 0.017, 0.017, rubber, 6)
	D.tube(Vector3.ZERO, Vector3(-r * 0.95, -0.03, 0), 0.014, 0.014, rubber, 5); D.tube(Vector3.ZERO, Vector3(r * 0.95, -0.03, 0), 0.014, 0.014, rubber, 5)
	D.cyl(0, -0.02, 0, 0.05, 0.05, 0.04, dark, 10)
	D.pop()
	D.tube(Vector3(cx, cy - 0.02, czw + 0.02), Vector3(cx, 1.0, 0.62), 0.03, 0.035, dark, 6)
	C.tube(Vector3(cx + 0.06, 1.06, 0.44), Vector3(cx + 0.2, 1.0, 0.42), 0.008, 0.008, chrome, 4)
	D.bevel_box(0, 0.72, -0.3, 1.84, 0.16, 0.5, vinyl, 0.04); D.bevel_box(0, 1.05, -0.56, 1.84, 0.62, 0.14, MeshBuilder.shade(vinyl, 0.95), 0.04)
	for k in range(6): D.box(-0.75 + k * 0.3, 1.05, -0.485, 0.02, 0.56, 0.01, MeshBuilder.shade(vinyl, 0.82))
	D.box(0, 1.86, 0.5, 0.06, 0.08, 0.03, h("#2a2d30")); D.bevel_box(0, 1.79, 0.485, 0.40, 0.14, 0.03, h("#2a2d30"), 0.01)
	for sx in [-1.0, 1.0]: D.box(sx * 0.94, 0.98, 0.04, 0.03, 0.5, 1.3, MeshBuilder.shade(vinyl, 0.8))
	D.box(0, 0.68, (cz0 + cz1) / 2, 1.96, 0.06, cz1 - cz0, h("#2a2622"))                              # floor mat
	# ---------------- bed
	for sx in [-1.0, 1.0]: P.box(sx * 0.915, 1.03, (bz0 + bz1) / 2, 0.02, 0.56, bz1 - bz0, MeshBuilder.shade(c1, 0.85))   # inner walls
	D.box(0, 0.77, (bz0 + bz1) / 2, 1.84, 0.06, bz1 - bz0, h("#3a3632"))
	for k in range(7): D.box(-0.75 + k * 0.25, 0.805, (bz0 + bz1) / 2, 0.05, 0.025, bz1 - bz0, h("#4a4540"))
	P.box(0, 1.03, bz1 + 0.02, 1.84, 0.56, 0.05, MeshBuilder.shade(c1, 0.9))
	TG.box(0, 1.0, bz0, 2.0, 0.62, 0.07, c1); TG.box(0, 1.28, bz0, 2.0, 0.05, 0.08, MeshBuilder.shade(c1, 1.08))
	TG.box(0, 0.98, bz0 - 0.04, 1.4, 0.16, 0.01, MeshBuilder.shade(c1, 0.9))
	for sx in [-1.0, 1.0]:
		C.bevel_box(sx * 0.93, 0.98, bz0 - 0.03, 0.15, 0.34, 0.04, chrome, 0.01)
		L.box(sx * 0.93, 1.02, bz0 - 0.05, 0.11, 0.18, 0.02, h("#c22a1e")); L.box(sx * 0.93, 0.9, bz0 - 0.05, 0.11, 0.07, 0.02, h("#f2f2ec"))
	C.bevel_box(0, 0.56, bz0 - 0.16, 2.04, 0.18, 0.16, chrome, 0.04)                                 # rear bumper
	D.box(0, 0.6, bz0 - 0.245, 0.3, 0.06, 0.02, h("#e8e4d0"))                                          # licence plate
	D.box(0, 0.5, bz0 - 0.32, 0.1, 0.06, 0.36, dark); C.sphere(0, 0.58, HITCH.z, 0.05, 0.05, 0.05, chrome, 10, 7)
	# ---------------- under the truck
	for sx in [-1.0, 1.0]: D.box(sx * 0.48, 0.48, 0, 0.1, 0.16, 4.8, black)
	D.box(0, 0.45, 1.9, 1.0, 0.08, 0.1, black); D.box(0, 0.45, -2.4, 1.0, 0.08, 0.1, black)
	D.push(Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(0, 0.42, Models.REAR_AXLE)))
	D.cyl(0, -0.8, 0, 0.05, 0.05, 1.6, dark, 8, true)
	D.pop()
	D.sphere(0, 0.42, Models.REAR_AXLE, 0.16, 0.14, 0.16, dark, 10, 6)
	D.bevel_box(0.62, 0.52, -0.9, 0.3, 0.26, 0.7, dark, 0.05)                                         # fuel tank
	D.tube(Vector3(-0.3, 0.42, 1.2), Vector3(-0.35, 0.36, -2.5), 0.03, 0.03, h("#5a5652"), 6)           # exhaust
	return {paint = P, chrome = C, dark = D, glass = G, lamps = L, tailgate = TG, c1 = c1, c2 = c2}

static func wheel() -> MeshBuilder:
	var mb := MeshBuilder.new()
	mb.push(Transform3D(Basis(Vector3.BACK, PI / 2), Vector3.ZERO))
	var tire := h("#1a1a1a"); var side := h("#262626")
	# a closed tire: inner sidewall, tread, outer sidewall with a raised bead
	plaid(mb, [[-0.125, 0.2, 0.2], [-0.135, 0.3, 0.3], [-0.12, 0.375, 0.375], [0.12, 0.375, 0.375], [0.135, 0.3, 0.3], [0.13, 0.26, 0.26], [0.13, 0.2, 0.2]], tire, side, 24, 1)
	mb.cyl(0, -0.126, 0, 0.21, 0.21, 0.0, side, 16, true)
	# tread blocks
	for k in range(28):
		var a := TAU * k / 28
		mb.push(Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * 0.39, 0, sin(a) * 0.39)))
		mb.box(0, (0.06 if k % 2 else -0.06), 0, 0.03, 0.11, 0.05, tire)
		mb.pop()
	# steel wheel, chrome hubcap, lug nuts
	mb.cyl(0, 0.14, 0, 0.25, 0.23, 0.012, h("#c9ccd0"), 20, true)
	mb.cyl(0, 0.152, 0, 0.17, 0.12, 0.03, h("#e2e4e6"), 20, true)
	mb.cyl(0, 0.18, 0, 0.05, 0.04, 0.012, h("#9aa0a6"), 12, true)
	for k in range(6):
		var a := TAU * k / 6
		mb.cyl(cos(a) * 0.2, 0.15, sin(a) * 0.2, 0.014, 0.012, 0.018, h("#5a5f64"), 6, true)
	mb.pop()
	return mb

## chipper frame: origin at the tongue coupler, body toward −Z, infeed faces −Z
const CHIP_AXLE := -2.3
static func chipper() -> MeshBuilder:
	var mb := MeshBuilder.new()
	var body := h("#e08a1e"); var dk := h("#262729"); var steel := h("#6a6e72"); var yel := h("#e8c23a"); var red := h("#c8301e")
	var r := RandomNumberGenerator.new(); r.seed = 77
	# tongue: A-frame, coupler with its latch, safety chains
	mb.tube(Vector3(0, 0, -0.1), Vector3(-0.5, -0.08, -1.3), 0.045, 0.045, dk, 8); mb.tube(Vector3(0, 0, -0.1), Vector3(0.5, -0.08, -1.3), 0.045, 0.045, dk, 8)
	mb.bevel_box(0, 0, -0.08, 0.13, 0.1, 0.26, dk, 0.02)
	mb.box(0, 0.06, -0.06, 0.05, 0.03, 0.14, steel)
	mb.sphere(0, -0.02, 0.0, 0.065, 0.05, 0.065, steel, 10, 5)
	for sx: float in [-1.0, 1.0]:
		var prev := Vector3(sx * 0.06, -0.04, -0.15)
		for k in range(6):
			var q := Vector3(sx * (0.06 + k * 0.012), -0.1 - sin(k / 5.0 * PI) * 0.08, -0.15 + k * 0.06)
			mb.tube(prev, q, 0.008, 0.008, steel, 4); prev = q
	# frame rails and crossmembers
	for sx: float in [-1.0, 1.0]: mb.box(sx * 0.5, -0.06, -2.2, 0.08, 0.12, 2.0, dk)
	for z: float in [-1.3, -1.9, -2.6, -3.15]: mb.box(0, -0.06, z, 1.08, 0.1, 0.08, dk)
	mb.box(0, 0.25, -0.4, 0.12, 0.5, 0.12, dk)
	# engine: hood with louvres, a hinge line, exhaust stack with a rain flap, the control panel
	mb.bevel_box(0, 0.45, -1.55, 1.1, 0.88, 1.0, body, 0.06)
	mb.bevel_box(0, 0.94, -1.55, 1.02, 0.1, 0.92, MeshBuilder.shade(body, 1.08), 0.04)
	mb.box(0, 0.9, -1.55, 1.12, 0.012, 1.02, MeshBuilder.shade(body, 0.7))
	for sx: float in [-1.0, 1.0]:
		for k in range(7): mb.box(sx * 0.556, 0.5, -1.22 - k * 0.09, 0.02, 0.42, 0.035, dk)
		mb.box(sx * 0.556, 0.18, -1.55, 0.01, 0.1, 0.96, yel)                                    # stripe
	mb.cyl(-0.3, 0.98, -1.3, 0.05, 0.05, 0.42, dk, 10, false)
	mb.cyl(-0.3, 1.4, -1.3, 0.055, 0.055, 0.03, steel, 10, false)
	mb.push(Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(-0.3, 1.43, -1.3)))
	mb.cyl(0, 0, 0, 0.06, 0.06, 0.008, steel, 10, true)
	mb.pop()
	mb.cyl(0.32, 0.98, -1.8, 0.05, 0.05, 0.04, dk, 10, true)                                    # fuel cap
	mb.bevel_box(0.35, 0.72, -1.03, 0.36, 0.3, 0.06, dk, 0.02)                                  # control panel
	for k in range(2): mb.cyl(0.27 + k * 0.14, 0.76, -0.995, 0.04, 0.04, 0.012, h("#e8e4d8"), 12, true)
	mb.box(0.35, 0.62, -0.99, 0.06, 0.04, 0.03, red)
	mb.box(0.25, 0.62, -0.99, 0.04, 0.04, 0.03, h("#3aa040"))
	# drum housing and the big flywheel cover on the side
	mb.bevel_box(0, 0.55, -2.45, 1.0, 1.1, 0.9, MeshBuilder.shade(body, 0.92), 0.06)
	mb.push(Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(0.5, 0.62, -2.45)))
	mb.cyl(0, -0.02, 0, 0.44, 0.44, 0.08, MeshBuilder.shade(body, 0.85), 22, true, MeshBuilder.shade(body, 0.95))
	mb.cyl(0, 0.06, 0, 0.12, 0.12, 0.03, dk, 14, true)
	for k in range(8):
		var a := TAU * k / 8.0
		mb.cyl(cos(a) * 0.37, 0.06, sin(a) * 0.37, 0.018, 0.018, 0.02, steel, 6, true)
	mb.pop()
	mb.box(-0.505, 0.65, -2.45, 0.01, 0.2, 0.55, yel)
	mb.box(-0.508, 0.65, -2.45, 0.01, 0.12, 0.42, dk)
	# infeed: steel hopper, dark throat with a feed roller, the red bump bar all the way round
	var hz := -2.9; var hz2 := -3.9
	mb.box(0, 0.5, hz - 0.05, 0.8, 0.7, 0.1, steel)
	mb.face([Vector3(-0.4, 0.15, hz), Vector3(0.4, 0.15, hz), Vector3(0.62, 0.05, hz2), Vector3(-0.62, 0.05, hz2)], steel)
	mb.face([Vector3(-0.4, 0.85, hz), Vector3(-0.62, 1.0, hz2), Vector3(0.62, 1.0, hz2), Vector3(0.4, 0.85, hz)], MeshBuilder.shade(steel, 0.9))
	mb.face([Vector3(-0.4, 0.15, hz), Vector3(-0.62, 0.05, hz2), Vector3(-0.62, 1.0, hz2), Vector3(-0.4, 0.85, hz)], MeshBuilder.shade(steel, 1.1))
	mb.face([Vector3(0.4, 0.15, hz), Vector3(0.4, 0.85, hz), Vector3(0.62, 1.0, hz2), Vector3(0.62, 0.05, hz2)], MeshBuilder.shade(steel, 1.1))
	# the hopper's outside faces (seen from beside it), painted
	mb.face([Vector3(-0.41, 0.15, hz), Vector3(-0.41, 0.85, hz), Vector3(-0.63, 1.0, hz2), Vector3(-0.63, 0.05, hz2)], body)
	mb.face([Vector3(0.41, 0.15, hz), Vector3(0.63, 0.05, hz2), Vector3(0.63, 1.0, hz2), Vector3(0.41, 0.85, hz)], body)
	mb.face([Vector3(-0.4, 0.86, hz), Vector3(0.4, 0.86, hz), Vector3(0.62, 1.01, hz2), Vector3(-0.62, 1.01, hz2)], body)
	mb.box(0, 0.5, hz + 0.02, 0.7, 0.6, 0.04, h("#111214"))
	mb.push(Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(0, 0.62, hz - 0.08)))
	mb.cyl(0, -0.32, 0, 0.09, 0.09, 0.64, h("#3a3c3e"), 12, true)
	for k in range(10):
		var a := TAU * k / 10.0
		mb.box(cos(a) * 0.09, 0, sin(a) * 0.09, 0.025, 0.62, 0.025, steel)
	mb.pop()
	mb.box(0, 1.06, hz2 + 0.06, 1.3, 0.05, 0.06, red); mb.box(-0.66, 0.5, hz2 + 0.06, 0.05, 0.95, 0.06, red); mb.box(0.66, 0.5, hz2 + 0.06, 0.05, 0.95, 0.06, red)
	for k in range(4):
		mb.box(-0.66, 0.15 + k * 0.25, hz2 + 0.06, 0.055, 0.1, 0.065, yel); mb.box(0.66, 0.15 + k * 0.25, hz2 + 0.06, 0.055, 0.1, 0.065, yel)
	for sx: float in [-1.0, 1.0]:
		mb.box(sx * 0.6, 0.12, hz2 + 0.12, 0.08, 0.06, 0.03, red)                                   # tail lights
		mb.box(sx * 0.6, 0.12, hz2 + 0.1, 0.06, 0.04, 0.02, h("#ff5a40"))
		mb.box(sx * 0.53, 0.72, (hz + hz2) / 2, 0.01, 0.16, 0.3, yel)                              # warning decals
	mb.box(0, 0.08, hz2 + 0.1, 0.3, 0.15, 0.01, h("#e8e4d8"))                                     # plate
	# discharge chute: a smooth curve with a deflector at the end and a turning handle
	var p := Vector3(0, 1.05, -2.45)
	for k in range(10):
		var t := (k + 1) / 10.0
		var q := Vector3(0, 1.05 + sin(t * 1.4) * 0.95, -2.45 + t * 1.5)
		mb.tube(p, q, 0.15, 0.15, body, 12); p = q
	mb.cyl(0, 1.0, -2.45, 0.19, 0.19, 0.1, dk, 14, false)
	mb.push(Transform3D(Basis(Vector3.RIGHT, -0.45), p))
	mb.box(0, 0.05, 0.12, 0.34, 0.03, 0.34, MeshBuilder.shade(body, 0.85))
	mb.pop()
	mb.tube(Vector3(0.18, 1.3, -2.3), Vector3(0.32, 1.42, -2.25), 0.015, 0.015, dk, 5)
	# fenders over the wheels, a step plate, the saw rack, a toolbox
	for sx: float in [-1.0, 1.0]:
		var prev := Vector3.ZERO
		for k in range(9):
			var a := PI * k / 8.0
			var q := Vector3(sx * 0.78, 0.02 + sin(a) * 0.5, CHIP_AXLE - cos(a) * 0.52)
			if k > 0:
				mb.push(Transform3D(Basis(), Vector3.ZERO))
				var mid := (prev + q) / 2; var len := prev.distance_to(q)
				var dir := (q - prev).normalized()
				mb.push(Transform3D(Basis(Vector3.RIGHT, atan2(-dir.y, dir.z)), mid))
				mb.box(0, 0, 0, 0.32, 0.03, len + 0.01, dk)
				mb.pop(); mb.pop()
			prev = q
	for z: float in [-1.62, -2.5]:
		mb.box(-0.6, 0.28, z, 0.08, 0.42, 0.05, dk); mb.box(-0.7, 0.1, z, 0.2, 0.05, 0.05, dk)
	mb.box(-0.78, 0.12, -2.06, 0.04, 0.08, 1.0, steel); mb.box(-0.66, 0.12, -2.06, 0.04, 0.04, 1.0, steel); mb.box(-0.79, 0.19, -2.06, 0.02, 0.08, 1.0, yel)
	mb.bevel_box(0.0, 0.08, -1.0, 0.6, 0.22, 0.3, dk, 0.02)
	mb.box(0.0, 0.15, -0.85, 0.1, 0.03, 0.02, steel)
	mb.box(0.551, 0.95, -2.45, 0.01, 0.12, 0.6, yel)
	mb.box(-0.551, 0.95, -2.45, 0.01, 0.12, 0.6, yel)
	return mb

static func jack() -> MeshBuilder:
	var mb := MeshBuilder.new()
	mb.cyl(0, -0.5, -0.4, 0.06, 0.06, 0.5, h("#6a6e72"), 8)
	mb.box(0, -0.48, -0.4, 0.2, 0.04, 0.2, h("#262729"))
	return mb

## a lathe-turned shape along Y from a profile of [y, rx, rz] rings, each face coloured as tartan:
## every third row and every third column runs darker (flannel), or plain when dark == base
static func plaid(mb: MeshBuilder, prof: Array, base: Color, dark: Color, seg := 18, sub := 2) -> void:
	var rows: Array = []
	for k in range(prof.size() - 1):
		for j in range(sub):
			var t := float(j) / sub
			var p0: Array = prof[k]; var p1: Array = prof[k + 1]
			rows.append([lerpf(p0[0], p1[0], t), lerpf(p0[1], p1[1], t), lerpf(p0[2], p1[2], t)])
	rows.append(prof[prof.size() - 1])
	var pt := func(rw: Array, a: float) -> Vector3: return Vector3(cos(a) * rw[1], rw[0], sin(a) * rw[2])
	for j in range(rows.size() - 1):
		var r0: Array = rows[j]; var r1: Array = rows[j + 1]
		for i in range(seg):
			var a0 := TAU * i / seg; var a1 := TAU * (i + 1) / seg
			var c := base
			if j % 3 == 0: c = c.lerp(dark, 0.5)
			if i % 3 == 0: c = c.lerp(dark, 0.5)
			if j % 3 == 1 and i % 3 == 1: c = c.lerp(Color.WHITE, 0.08)
			var n0 := Vector3(cos(a0), 0, sin(a0)); var n1 := Vector3(cos(a1), 0, sin(a1))
			var q0 := mb.v(pt.call(r0, a0), n0, c); var q1 := mb.v(pt.call(r1, a0), n0, c)
			var q2 := mb.v(pt.call(r1, a1), n1, c); var q3 := mb.v(pt.call(r0, a1), n1, c)
			mb.quad(q0, q1, q2, q3)

## Earl, in parts so he can be posed. Returns {torso, head, upper, fore, leg, cane}
## torso origin at the hips, neck at y 0.58, shoulders at (±0.25, 0.5); the head faces +Z
static func old_man() -> Dictionary:
	var P := {}
	var r := RandomNumberGenerator.new(); r.seed = 4242
	var skin := h("#e3b393"); var denim := h("#3f5f88"); var shirt := h("#b3322a"); var plaid_dk := h("#2a1414")
	var dkC := h("#262626"); var boot := h("#5a3e26"); var white := h("#eeece6"); var cap := h("#3e6a3a"); var brass := h("#c9a640")
	var mb := MeshBuilder.new()
	# flannel shirt, a bit of a belly
	plaid(mb, [[0.1, 0.2, 0.15], [0.22, 0.225, 0.175], [0.36, 0.225, 0.16], [0.48, 0.215, 0.14], [0.55, 0.17, 0.12], [0.59, 0.07, 0.07]], shirt, plaid_dk, 20, 2)
	for sx: float in [-1.0, 1.0]:
		mb.sphere(sx * 0.19, 0.5, 0, 0.085, 0.08, 0.1, shirt.lerp(plaid_dk, 0.25), 10, 6)
	mb.cyl(0, 0.54, 0, 0.075, 0.07, 0.05, shirt.lerp(plaid_dk, 0.4), 12, false)       # collar
	for sx: float in [-1.0, 1.0]:
		mb.push(Transform3D(Basis(Vector3.FORWARD, sx * 0.5), Vector3(sx * 0.05, 0.57, 0.065)))
		mb.box(0, 0, 0, 0.07, 0.015, 0.06, shirt.lerp(plaid_dk, 0.3))
		mb.pop()
	# overalls: the seat and the bib, straps and brass buttons
	plaid(mb, [[-0.14, 0.2, 0.15], [0.0, 0.215, 0.165], [0.16, 0.232, 0.182]], denim, MeshBuilder.shade(denim, 0.9), 20, 1)
	mb.bevel_box(0, 0.28, 0.165, 0.3, 0.26, 0.03, denim, 0.012)
	mb.box(0, 0.31, 0.183, 0.14, 0.1, 0.01, MeshBuilder.shade(denim, 1.1))                       # bib pocket
	mb.box(0, 0.36, 0.189, 0.14, 0.008, 0.004, h("#d8b060"))                                   # stitching
	for sx: float in [-1.0, 1.0]:
		mb.tube(Vector3(sx * 0.11, 0.4, 0.17), Vector3(sx * 0.13, 0.56, 0.06), 0.022, 0.022, denim, 5)
		mb.tube(Vector3(sx * 0.13, 0.56, 0.06), Vector3(sx * 0.1, 0.54, -0.11), 0.022, 0.022, denim, 5)
		mb.tube(Vector3(sx * 0.1, 0.54, -0.11), Vector3(0, 0.25, -0.17), 0.022, 0.022, denim, 5)
		mb.sphere(sx * 0.11, 0.39, 0.185, 0.02, 0.02, 0.012, brass, 8, 4)
		mb.box(sx * 0.215, 0.05, 0.02, 0.02, 0.12, 0.1, MeshBuilder.shade(denim, 0.85))     # side pockets
	mb.box(0, 0.1, 0.17, 0.004, 0.18, 0.004, h("#d8b060"))
	# a red rag hanging out of the back pocket
	mb.box(0.09, -0.02, -0.165, 0.08, 0.14, 0.01, h("#c03a2a"))
	P.torso = mb
	# head
	mb = MeshBuilder.new()
	mb.cyl(0, -0.02, 0, 0.06, 0.058, 0.1, skin, 10, false)
	mb.sphere(0, 0.165, 0, 0.108, 0.128, 0.115, skin, 16, 10)
	for sx: float in [-1.0, 1.0]:
		mb.sphere(sx * 0.108, 0.16, -0.005, 0.02, 0.035, 0.025, MeshBuilder.shade(skin, 0.95), 8, 5)      # ears
		mb.sphere(sx * 0.06, 0.135, 0.085, 0.03, 0.022, 0.02, h("#e89a88"), 8, 5)                       # rosy cheeks
		mb.sphere(sx * 0.04, 0.178, 0.1, 0.014, 0.014, 0.01, dkC, 8, 5)                                   # eyes
		mb.sphere(sx * 0.036, 0.181, 0.106, 0.004, 0.004, 0.003, white, 4, 3)
		mb.tube(Vector3(sx * 0.018, 0.2, 0.108), Vector3(sx * 0.068, 0.208, 0.095), 0.009, 0.007, white, 5)   # bushy brows
	mb.sphere(0, 0.15, 0.118, 0.024, 0.026, 0.026, h("#dc9f86"), 10, 6)                                    # nose
	# beard: lumpy and white, and a big moustache
	mb.push(Transform3D(Basis.from_scale(Vector3(1.0, 1.15, 0.75)), Vector3(0, 0.075, 0.055)))
	mb.blob(0, 0, 0, 0.095, white, r, 1.1)
	mb.pop()
	mb.blob(0, 0.03, 0.085, 0.05, MeshBuilder.shade(white, 0.97), r, 1.0)
	for sx: float in [-1.0, 1.0]:
		mb.tube(Vector3(0, 0.122, 0.118), Vector3(sx * 0.055, 0.105, 0.1), 0.017, 0.008, white, 6)
	for k in range(9):
		var a := -1.5 + k * 0.375
		mb.tube(Vector3(sin(a) * 0.1, 0.17, -cos(a) * 0.1), Vector3(sin(a) * 0.125, 0.12 - (k % 2) * 0.02, -cos(a) * 0.12), 0.024, 0.006, white, 5)
	# trucker cap: crown, mesh back, front panel with a patch, curved brim, button
	mb.sphere(0, 0.235, 0, 0.118, 0.085, 0.124, MeshBuilder.shade(cap, 0.9), 14, 7)
	mb.push(Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, 0.255, 0.07)))
	mb.box(0, 0, 0, 0.17, 0.11, 0.02, white)
	mb.box(0, 0.0, 0.012, 0.09, 0.05, 0.004, cap)
	mb.box(0, 0.0, 0.015, 0.05, 0.015, 0.002, h("#e8c23a"))
	mb.pop()
	for k in range(5):
		var a := -0.5 + k * 0.25
		mb.push(Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.12), Vector3(sin(a) * 0.1, 0.205, cos(a) * 0.1)))
		mb.box(0, 0, 0.06, 0.055, 0.012, 0.12, cap)
		mb.pop()
	mb.sphere(0, 0.32, 0, 0.014, 0.008, 0.014, cap, 6, 3)
	P.head = mb
	# arms: flannel sleeves, buttoned cuffs, hands
	mb = MeshBuilder.new()
	plaid(mb, [[0.04, 0.065, 0.07], [-0.12, 0.062, 0.064], [-0.3, 0.054, 0.056]], shirt, plaid_dk, 12, 2)
	mb.sphere(0, -0.3, 0, 0.054, 0.03, 0.056, shirt, 10, 5)
	P.upper = mb
	mb = MeshBuilder.new()
	plaid(mb, [[0.0, 0.055, 0.056], [-0.2, 0.05, 0.05]], shirt, plaid_dk, 12, 3)
	mb.cyl(0, -0.235, 0, 0.052, 0.052, 0.04, shirt.lerp(plaid_dk, 0.35), 12, false)
	mb.sphere(0.04, -0.215, 0.02, 0.008, 0.008, 0.006, white, 4, 3)
	mb.cyl(0, -0.27, 0, 0.032, 0.036, 0.04, skin, 10, false)
	mb.sphere(0, -0.31, 0.005, 0.045, 0.055, 0.035, skin, 10, 6)
	mb.tube(Vector3(0.03, -0.29, 0.02), Vector3(0.045, -0.33, 0.04), 0.014, 0.011, skin, 6)
	P.fore = mb
	# legs: denim with a rolled cuff, work boots with soles and laces
	mb = MeshBuilder.new()
	plaid(mb, [[0.04, 0.09, 0.09], [-0.4, 0.08, 0.08], [-0.7, 0.072, 0.072]], denim, MeshBuilder.shade(denim, 0.92), 12, 2)
	mb.cyl(0, -0.76, 0, 0.078, 0.078, 0.07, MeshBuilder.shade(denim, 1.15), 12, false)
	mb.cyl(0, -0.7, 0, 0.072, 0.07, 0.06, denim, 12, false)
	mb.bevel_box(0, -0.82, 0.0, 0.12, 0.1, 0.16, boot, 0.03)
	mb.sphere(0, -0.84, 0.08, 0.062, 0.05, 0.08, boot, 10, 6)
	mb.box(0, -0.885, 0.04, 0.13, 0.03, 0.29, h("#2a2420"))
	mb.box(0, -0.88, -0.07, 0.125, 0.05, 0.07, h("#2a2420"))
	for k in range(4): mb.box(0, -0.79 + k * -0.015, 0.06 + k * 0.025, 0.07, 0.008, 0.008, h("#d8c890"))
	P.leg = mb
	# a walking stick: crook handle, rubber tip
	mb = MeshBuilder.new()
	var wood := h("#6a4a2a")
	mb.tube(Vector3.ZERO, Vector3(0, -0.9, 0), 0.015, 0.014, wood, 6)
	mb.cyl(0, -0.94, 0, 0.018, 0.018, 0.05, dkC, 6, true)
	var prev := Vector3.ZERO
	for k in range(1, 6):
		var a := k * PI / 5.0
		var q := Vector3(0, sin(a) * 0.05, 0.05 - cos(a) * 0.05)
		mb.tube(prev, q, 0.016, 0.016, wood, 6); prev = q
	P.cane = mb
	return P

## chainsaw in saw space: −Z forward along the bar, origin at the rear handle; bar tip near (0,0,−0.83)
static func chainsaw() -> MeshBuilder:
	var mb := MeshBuilder.new()
	var orange := h("#e8661c"); var white := h("#ecebe6"); var dk := h("#232426"); var steel := h("#9a9ea2"); var grey := h("#4a4c50")
	# powerhead: rounded orange housing, white top cover with a vent grille, dark crankcase
	mb.bevel_box(0, 0.035, -0.15, 0.115, 0.13, 0.27, orange, 0.025)
	mb.bevel_box(0, 0.115, -0.15, 0.108, 0.05, 0.23, white, 0.02)
	for k in range(5): mb.box(0, 0.141, -0.07 - k * 0.025, 0.07, 0.006, 0.01, grey)
	mb.bevel_box(0, -0.02, -0.15, 0.118, 0.05, 0.25, dk, 0.012)
	# sprocket cover on the right with the bar nuts, muffler on the front, starter handle on the left
	mb.bevel_box(0.07, 0.01, -0.22, 0.035, 0.1, 0.14, dk, 0.012)
	for k in range(2): mb.cyl(0.088, -0.005 + k * 0.035, -0.2 - k * 0.03, 0.012, 0.012, 0.01, steel, 6, true)
	mb.box(0.07, 0.01, -0.22, 0.038, 0.02, 0.1, orange)
	mb.bevel_box(-0.02, 0.0, -0.29, 0.06, 0.07, 0.035, grey, 0.01)
	for k in range(3): mb.box(-0.02, -0.02 + k * 0.02, -0.31, 0.045, 0.006, 0.006, dk)
	mb.box(-0.064, 0.05, -0.18, 0.012, 0.075, 0.13, dk)
	mb.push(Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(-0.078, 0.06, -0.16)))
	mb.cyl(0, -0.006, 0, 0.012, 0.012, 0.03, dk, 8, true)
	mb.pop()
	mb.box(-0.085, 0.06, -0.16, 0.012, 0.018, 0.06, dk)
	mb.box(0.03, 0.13, -0.04, 0.03, 0.02, 0.03, h("#eeeeee"))                                 # primer bulb / choke
	mb.cyl(0.035, 0.09, -0.27, 0.014, 0.014, 0.04, dk, 8, true)                              # fuel cap
	# rear handle with a trigger, top handle loop, hand guard
	mb.box(0, 0.07, -0.02, 0.05, 0.06, 0.06, dk)
	mb.tube(Vector3(0, 0.02, 0.02), Vector3(0, 0.02, 0.1), 0.022, 0.022, dk, 8); mb.tube(Vector3(0, 0.02, 0.1), Vector3(0, 0.09, 0.08), 0.02, 0.02, dk, 8); mb.tube(Vector3(0, 0.09, 0.08), Vector3(0, 0.1, -0.01), 0.022, 0.022, dk, 8)
	mb.box(0, 0.0, 0.04, 0.012, 0.03, 0.03, orange)
	mb.tube(Vector3(-0.07, -0.02, -0.24), Vector3(-0.07, 0.17, -0.24), 0.016, 0.016, dk, 8); mb.tube(Vector3(-0.07, 0.17, -0.24), Vector3(0.06, 0.17, -0.2), 0.016, 0.016, dk, 8); mb.tube(Vector3(0.06, 0.17, -0.2), Vector3(0.06, 0.05, -0.18), 0.016, 0.016, dk, 8)
	mb.bevel_box(0, 0.19, -0.27, 0.1, 0.075, 0.012, dk, 0.004)
	# bar: steel with a darker rail and a nose sprocket; the chain runs round its edge
	mb.box(0, 0, -0.52, 0.012, 0.07, 0.62, steel); mb.box(0, 0, -0.52, 0.016, 0.075, 0.6, dk); mb.box(0, 0, -0.52, 0.013, 0.055, 0.62, steel)
	mb.box(0.0085, 0.0, -0.5, 0.001, 0.02, 0.3, orange)
	mb.push(Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(0, 0, -0.83)))
	mb.cyl(0, -0.008, 0, 0.037, 0.037, 0.016, steel, 12, true)
	mb.cyl(0, -0.009, 0, 0.012, 0.012, 0.018, grey, 8, true)
	mb.pop()
	for k in range(26):
		var z := -0.24 - k * 0.023
		mb.box(0, 0.04, z, 0.016, 0.012, 0.012, dk); mb.box(0, -0.04, z, 0.016, 0.012, 0.012, dk)
		if k % 2 == 0:
			mb.box(0, 0.047, z - 0.004, 0.018, 0.005, 0.007, steel); mb.box(0, -0.047, z - 0.004, 0.018, 0.005, 0.007, steel)
	for k in range(5):
		var a := -PI / 2 + PI * k / 4.0
		mb.box(0, sin(a) * 0.043, -0.83 - cos(a) * 0.043, 0.016, 0.012, 0.012, dk)
	mb.box(0, 0, -0.22, 0.06, 0.09, 0.04, dk)
	mb.box(0.0, -0.06, -0.3, 0.02, 0.02, 0.02, grey)                                          # bucking spike
	return mb

## a gloved hand, kept simple: a ball with a cuff behind it (the bar it holds runs along local X)
static func fist(_side: float) -> MeshBuilder:
	var mb := MeshBuilder.new()
	var glove := h("#c9a46a"); var cuff := h("#8a6a3a")
	mb.sphere(0, 0.01, 0, 0.045, 0.042, 0.045, glove, 12, 8)
	mb.tube(Vector3(0, 0.015, 0.03), Vector3(0, 0.02, 0.075), 0.034, 0.04, cuff, 10)
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
