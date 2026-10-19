# Earl, "classic logger" (from the concept sheet): green crusher hat with a band and a leaf, big round
# nose, full white beard, red buffalo-check shirt with rolled cuffs, blue bib overalls (patch pocket,
# brass buttons, straps crossed at the back, back pockets), a leather tool belt and pouch, mustard work
# gloves, rolled jeans, lace-up boots, and his walking stick.
# Shapes are built coarse and soft, then smoothed (charkit subdivides every part) so he reads as a person,
# not a stack of cylinders.
# Run: blender -b --factory-startup -P earl.py -- <out.glb> [preview_dir]
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from charkit import *

PAL = {
	"skin": "#eab08c", "skin_dk": "#d89878", "nose": "#e5876a", "cheek": "#e9967f", "eye": "#141414",
	"beard": "#ece8de", "beard_dk": "#d6d1c4", "hair": "#cfcabf",
	"hat": "#3f5626", "hat_dk": "#31441d", "band": "#5a3a22", "leaf": "#d88a2a", "leaf2": "#e2b03a",
	"denim": "#34507c", "denim_dk": "#2b4268", "denim_lt": "#5f7ba6",
	"brass": "#c9a24a", "leather": "#6a4426", "leather_dk": "#53341c", "patch": "#8a5a30",
	"glove": "#a07c32", "glove_dk": "#7f6226", "cuff": "#a8342c", "cuff_lt": "#b8443a",
	"boot": "#6c4425", "boot_dk": "#53331b", "sole": "#2a2420", "lace": "#d8bf86",
	"wood": "#6a4a2a", "rubber": "#1e1e1e", "red_dk": "#6e1e1a",
}
RED = hex2rgb("#a32a25"); BLK = hex2rgb("#1c1416"); MID = [RED[i] * 0.42 + BLK[i] * 0.58 for i in range(3)]
def buffalo(x, y, n):
	sx = (x // 32) % 2 == 0; sy = (y // 32) % 2 == 0
	c = BLK if (sx and sy) else (MID if (sx or sy) else RED)
	k = 0.94 + 0.06 * (((x + y) // 2) % 2)              # twill
	return [c[0] * k, c[1] * k, c[2] * k]

kit = Kit("earl", PAL, buffalo, cloth_n=128)
CHECK_BODY = (G(0, 0, 0), (5.0, 7.5))      # 5 checks round the body, ~7.5 a metre up
CHECK_ARM = (G(0, 0, 0), (2.0, 7.5))

# ------------------------------------------------------------------ torso (pivot: hips)
t = kit.part("torso")
# shirt: one smooth body from the belly up through sloping shoulders to the neck
t.lathe([(0.04, 0.2, 0.156), (0.17, 0.226, 0.18), (0.3, 0.232, 0.182), (0.42, 0.234, 0.17), (0.5, 0.228, 0.152),
	(0.55, 0.18, 0.12), (0.58, 0.1, 0.085), (0.6, 0.068, 0.068)], None, seg=12, cloth=CHECK_BODY)
# collar and a placket peeking above the bib
t.lathe([(0.55, 0.086, 0.08), (0.605, 0.076, 0.072)], "red_dk", seg=10, cap_bot=False)
for sx in (-1, 1):
	t.box((sx * 0.046, 0.585, 0.07), (0.07, 0.016, 0.06), "red_dk", 0.006, rot=gRz(sx * 0.6) @ gRx(0.5))
t.box((0, 0.48, 0.15), (0.026, 0.12, 0.012), "red_dk", 0.004)
for k in range(2): t.ball((0, 0.455 + k * 0.05, 0.158), (0.009, 0.009, 0.006), "beard", 6, 4)
# overalls: the seat (rounded under, like a person sits), the bib, its pocket and patch, brass buttons
t.lathe([(-0.17, 0.2, 0.158), (-0.06, 0.218, 0.172), (0.07, 0.232, 0.184), (0.16, 0.238, 0.19)],
	"denim", seg=12, cap_top=False)
t.box((0, 0.285, 0.168), (0.31, 0.27, 0.04), "denim", 0.015)
t.box((0, 0.297, 0.19), (0.16, 0.12, 0.012), "denim_dk", 0.004)
t.box((0, 0.297, 0.197), (0.05, 0.05, 0.008), "patch", 0.003)
t.box((0, 0.297, 0.201), (0.018, 0.024, 0.006), "leaf", 0.002)
for sx in (-1, 1):
	# straps: up over the shoulder, then crossing down the back
	t.tube((sx * 0.115, 0.4, 0.178), (sx * 0.135, 0.568, 0.07), 0.026, 0.026, "denim", 6, squash=0.4)
	t.tube((sx * 0.135, 0.568, 0.07), (sx * 0.13, 0.553, -0.135), 0.026, 0.026, "denim", 6, squash=0.4)
	t.tube((sx * 0.13, 0.553, -0.135), (0.0, 0.36, -0.195), 0.028, 0.028, "denim", 6, squash=0.4)
	t.tube((0.0, 0.36, -0.195), (-sx * 0.11, 0.17, -0.2), 0.028, 0.028, "denim", 6, squash=0.4)
	t.ball((sx * 0.115, 0.392, 0.196), (0.024, 0.024, 0.014), "brass", 8, 5)
	t.ball((sx * 0.224, 0.13, 0.08), (0.013, 0.017, 0.013), "brass", 6, 4)
	t.box((sx * 0.09, -0.04, -0.178), (0.11, 0.12, 0.016), "denim_dk", 0.005)        # back pockets
# tool belt, buckle, and the pouch on his left hip
t.lathe([(0.1, 0.244, 0.194), (0.155, 0.246, 0.196)], "leather", seg=12, cap_top=False, cap_bot=False)
t.box((0, 0.128, 0.2), (0.054, 0.046, 0.016), "brass", 0.006)
t.box((0, 0.128, 0.206), (0.03, 0.024, 0.008), "leather_dk", 0.003)
t.box((0.222, 0.04, 0.06), (0.07, 0.13, 0.1), "leather", 0.02)
t.box((0.222, 0.097, 0.062), (0.076, 0.035, 0.106), "leather_dk", 0.012)
torso = t.finish()

# ------------------------------------------------------------------ head (pivot: base of the neck); a touch large
h = kit.part("head")
S = 1.12
def hs(c): return (c[0] * S, c[1] * S, c[2] * S)
def hr(r): return (r[0] * S, r[1] * S, r[2] * S)
h.tube((0, -0.03, 0), (0, 0.08, 0.012), 0.064, 0.06, "skin_dk", 8, False)
h.ball(hs((0, 0.168, 0.0)), hr((0.114, 0.126, 0.114)), "skin", 12, 8)
for sx in (-1, 1):
	h.ball(hs((sx * 0.112, 0.163, -0.006)), hr((0.022, 0.036, 0.028)), "skin_dk", 6, 5)          # ears
	h.ball(hs((sx * 0.064, 0.152, 0.088)), hr((0.024, 0.017, 0.013)), "cheek", 6, 5)             # cheeks
	h.ball(hs((sx * 0.043, 0.188, 0.1)), hr((0.0135, 0.018, 0.01)), "eye", 6, 5)                # dot eyes
	h.box(hs((sx * 0.045, 0.216, 0.102)), (0.054, 0.02, 0.026), "beard", 0.008, rot=gRz(-sx * 0.1))   # brows
h.ball(hs((0, 0.146, 0.122)), hr((0.036, 0.034, 0.032)), "nose", 8, 6)                         # the nose
# beard: full and soft, from the cheeks down over the collar; moustache on top
h.icob(hs((0, 0.06, 0.05)), hr((0.115, 0.112, 0.088)), "beard", 1, jitter=0.07)
h.icob(hs((0, -0.005, 0.062)), hr((0.088, 0.075, 0.07)), "beard", 1, jitter=0.07)
for sx in (-1, 1):
	h.icob(hs((sx * 0.09, 0.105, 0.035)), hr((0.036, 0.072, 0.062)), "beard", 1, jitter=0.05)      # sideburns
	h.icob(hs((sx * 0.04, 0.114, 0.112)), hr((0.05, 0.024, 0.028)), "beard", 1, rot=gRz(sx * 0.2), jitter=0.04)   # moustache
h.icob(hs((0, 0.16, -0.045)), hr((0.12, 0.088, 0.092)), "hair", 1, jitter=0.06)                 # grey hair, round the back
# crusher hat: soft crown with a dent, leather band, a brim with some thickness, a leaf in the band
h.lathe([(y * S, rx * S, rz * S) for (y, rx, rz) in [(0.232, 0.128, 0.134), (0.3, 0.124, 0.13), (0.355, 0.112, 0.117), (0.385, 0.08, 0.085), (0.394, 0.035, 0.04)]], "hat", seg=12)
h.box(hs((0, 0.39, 0)), (0.032, 0.022, 0.15 * S), "hat_dk", 0.009)
h.lathe([(0.24 * S, 0.131 * S, 0.137 * S), (0.275 * S, 0.127 * S, 0.133 * S)], "band", seg=12, cap_top=False, cap_bot=False)
h.lathe([(y * S, rx * S, rz * S) for (y, rx, rz) in [(0.252, 0.125, 0.131), (0.24, 0.185, 0.195), (0.244, 0.2, 0.21), (0.228, 0.198, 0.208), (0.226, 0.125, 0.131)]], "hat", seg=16, cap_top=False, cap_bot=False)
for k, lc in enumerate(("leaf", "leaf2")):
	rot = gRy(-0.5 - k * 0.25) @ gRz(-0.35 - k * 0.3)
	h.ball(hs((0.12 - k * 0.012, 0.322 + k * 0.01, 0.035 - k * 0.03)), (0.008, 0.044, 0.022), lc, 6, 4, rot=rot)
head = h.finish()

# ------------------------------------------------------------------ upper arm (pivot: shoulder): rounded top, tapering to the elbow
u = kit.part("upper")
u.lathe([(-0.35, 0.058, 0.06), (-0.15, 0.066, 0.068), (0.0, 0.074, 0.078), (0.045, 0.058, 0.062)], None, seg=10, cloth=CHECK_ARM, hold=False)    # runs past the elbow so the sleeve reads as one
upper = u.finish()

# ------------------------------------------------------------------ forearm + glove (pivot: elbow; the hand at y -0.3)
f = kit.part("fore")
f.lathe([(-0.17, 0.054, 0.056), (-0.08, 0.06, 0.062), (0.03, 0.058, 0.06)], None, seg=10, cloth=CHECK_ARM, cap_bot=False)
f.lathe([(-0.228, 0.066, 0.068), (-0.172, 0.07, 0.072)], "cuff", seg=10)                       # rolled cuff
f.lathe([(-0.268, 0.05, 0.052), (-0.222, 0.054, 0.056)], "glove_dk", seg=10)                   # gauntlet
f.box((0, -0.312, 0.006), (0.094, 0.086, 0.066), "glove", 0.02)                                # the hand: chunky
for i in range(4):                                                                             # curled fingers
	x = -0.034 + i * 0.0225
	f.box((x, -0.36, 0.022), (0.022, 0.04, 0.05), "glove", 0.008, rot=gRx(0.3))
f.box((0.05, -0.305, 0.03), (0.028, 0.058, 0.032), "glove", 0.01, rot=gRz(0.45) @ gRx(0.3))   # thumb
fore = f.finish()

# ------------------------------------------------------------------ leg (pivot: hip joint): jeans, a rolled cuff, lace-up boots
l = kit.part("leg")
l.lathe([(-0.74, 0.09, 0.092), (-0.5, 0.093, 0.095), (-0.2, 0.1, 0.1), (0.06, 0.108, 0.108)], "denim", seg=10, cap_top=False, cap_bot=False)
l.lathe([(-0.795, 0.098, 0.1), (-0.725, 0.102, 0.104)], "denim_lt", seg=10)                    # rolled cuff
l.ball((0, -0.83, -0.005), (0.072, 0.065, 0.088), "boot", 8, 6)                                # ankle and heel
l.ball((0, -0.857, 0.085), (0.07, 0.048, 0.085), "boot", 8, 6)                                 # rounded toe
l.box((0, -0.895, 0.03), (0.15, 0.032, 0.3), "sole", 0.012, crease=0.6)
l.box((0, -0.81, 0.06), (0.06, 0.06, 0.03), "boot_dk", 0.01, rot=gRx(-0.4))                    # tongue
for k in range(3):
	l.box((0, -0.8 - k * 0.018, 0.078 + k * 0.022), (0.07, 0.01, 0.012), "lace", 0.003)
leg = l.finish()

# ------------------------------------------------------------------ walking stick (pivot: in the hand)
c = kit.part("cane")
c.tube((0, 0, 0), (0, -0.9, 0), 0.017, 0.016, "wood", 10)
c.tube((0, -0.9, 0), (0, -0.96, 0), 0.021, 0.021, "rubber", 10)
prev = (0, 0, 0)
for k in range(1, 6):
	a = k * math.pi / 5
	q = (0, math.sin(a) * 0.05, 0.05 - math.cos(a) * 0.05)
	c.tube(prev, q, 0.018, 0.018, "wood", 10); prev = q
cane = c.finish(subdiv=0)

kit.export(ARGV[0] if ARGV else "/tmp/earl.glb")
if len(ARGV) > 1: kit.preview(ARGV[1])
