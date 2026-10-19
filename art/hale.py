# Mrs. Hale (job 2, the leaning maple): a soft teal knit cardigan open over a cream blouse with a rounded
# collar and pearls, a plum pleated skirt, stockings and black low-heeled lace-ups, round gold glasses,
# grey hair swept up into a bun, and a mug of lemonade where Earl has his cane.
# Run: blender -b --factory-startup -P hale.py -- <out.glb> [preview_dir]
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from charkit import *

PAL = {
	"skin": "#efc0a2", "skin_dk": "#dda88a", "nose": "#e7a58c", "cheek": "#eb9e90", "eye": "#1a1614", "lip": "#b8706a",
	"hair": "#cdcac4", "hair_dk": "#b2aea7", "pin": "#8a7a5a",
	"blouse": "#f1ebdc", "blouse_dk": "#ddd5c2", "pearl": "#f2ede2", "gold": "#c9a246", "frame": "#9a7440",
	"cardi": "#4f7480", "cardi_dk": "#3f5e69", "button": "#e8dcc0",
	"skirt": "#6a4660", "skirt_dk": "#553750", "hose": "#d9b39a", "shoe": "#24201e", "sole": "#141210",
	"mug": "#f3f0ea", "lemonade": "#f2d468", "lemon": "#e8c43a",
}
TEAL = hex2rgb("#4f7480")
def knit(x, y, n):
	# ribbed knit: soft vertical ribs, each a little V-stitch row
	rib = (x // 4) % 2 == 0
	v = ((x % 4) - 1.5) * 0.06 * (1 if (y // 2) % 2 == 0 else -1)
	k = (0.9 if rib else 1.0) + v
	return [TEAL[0] * k, TEAL[1] * k, TEAL[2] * k]

kit = Kit("hale", PAL, knit, cloth_n=64)
KNIT_BODY = (G(0, 0, 0), (12.0, 14.0))
KNIT_ARM = (G(0, 0, 0), (4.0, 14.0))

# ------------------------------------------------------------------ torso (pivot: hips)
t = kit.part("torso")
t.lathe([(0.08, 0.185, 0.145), (0.2, 0.2, 0.158), (0.32, 0.206, 0.156), (0.44, 0.2, 0.142), (0.5, 0.19, 0.13),
	(0.545, 0.16, 0.112), (0.575, 0.1, 0.085), (0.59, 0.066, 0.066)], None, seg=20, cloth=KNIT_BODY)
for sx in (-1, 1):
	t.ball((sx * 0.19, 0.49, 0.0), (0.075, 0.062, 0.09), None, 12, 8, cloth=(G(sx * 0.17, 0, 0), (4.0, 14.0)))
# the blouse showing down the open front, its rounded collar, and pearls
t.box((0, 0.36, 0.142), (0.085, 0.36, 0.02), "blouse", 0.008)
for k in range(4): t.ball((0, 0.24 + k * 0.075, 0.154), (0.007, 0.007, 0.004), "blouse_dk", 6, 4)
t.lathe([(0.55, 0.074, 0.07), (0.6, 0.07, 0.066)], "blouse", seg=14, cap_bot=False)
for sx in (-1, 1):
	t.ball((sx * 0.04, 0.585, 0.06), (0.042, 0.012, 0.03), "blouse", 10, 5, rot=gRz(sx * 0.35))
	# the cardigan's front bands either side of the blouse, buttons down one side, patch pockets
	t.box((sx * 0.058, 0.33, 0.15), (0.032, 0.44, 0.02), "cardi_dk", 0.008)
	t.box((sx * 0.105, 0.2, 0.152), (0.07, 0.075, 0.012), "cardi_dk", 0.005)
for k in range(5): t.ball((0.058, 0.17 + k * 0.075, 0.162), (0.011, 0.011, 0.006), "button", 8, 5)
for k in range(13):
	a = -1.25 + k * 0.208
	t.ball((math.sin(a) * 0.082, 0.57 - math.cos(a * 0.85) * 0.03 + 0.03, math.cos(a) * 0.08), (0.011, 0.011, 0.011), "pearl", 6, 4)
# cardigan hem, then a plum pleated skirt to mid-calf
t.lathe([(0.06, 0.192, 0.152), (0.1, 0.19, 0.15)], "cardi_dk", seg=20, cap_top=False, cap_bot=False)
t.lathe([(-0.46, 0.25, 0.22), (-0.2, 0.218, 0.188), (0.0, 0.19, 0.156), (0.075, 0.168, 0.13)], "skirt", seg=28,
	cap_top=False, wave=(28, 0.03))       # its waist tucked up inside the cardigan
t.lathe([(-0.465, 0.252, 0.222), (-0.45, 0.252, 0.222)], "skirt_dk", seg=28, cap_top=False, cap_bot=False, wave=(28, 0.03))
torso = t.finish()

# ------------------------------------------------------------------ head (pivot: base of the neck)
h = kit.part("head")
S = 1.1
def hs(c): return (c[0] * S, c[1] * S, c[2] * S)
def hr(r): return (r[0] * S, r[1] * S, r[2] * S)
h.tube((0, -0.03, 0), (0, 0.07, 0.01), 0.054, 0.05, "skin_dk", 10, False)
h.ball(hs((0, 0.166, 0.0)), hr((0.103, 0.122, 0.108)), "skin", 16, 10)
for sx in (-1, 1):
	h.ball(hs((sx * 0.102, 0.162, -0.006)), hr((0.017, 0.03, 0.022)), "skin_dk", 8, 6)          # ears
	h.ball(hs((sx * 0.103, 0.128, 0.0)), hr((0.01, 0.01, 0.01)), "gold", 6, 4)                  # earrings
	h.ball(hs((sx * 0.058, 0.138, 0.084)), hr((0.024, 0.017, 0.012)), "cheek", 8, 6)
	h.ball(hs((sx * 0.039, 0.178, 0.097)), hr((0.011, 0.014, 0.007)), "eye", 8, 6)
	h.box(hs((sx * 0.04, 0.207, 0.099)), (0.034, 0.008, 0.012), "hair_dk", 0.003, rot=gRz(-sx * 0.12))   # fine brows
	# round glasses: a rim each side, arms back to the ears
	h.ring(hs((sx * 0.041, 0.178, 0.112)), (0.027 * S, 0.023 * S), 0.0028, "frame", 14)
	h.tube(hs((sx * 0.068, 0.182, 0.108)), hs((sx * 0.1, 0.178, 0.02)), 0.0028, 0.0028, "frame", 4, False)
h.tube(hs((-0.014, 0.183, 0.114)), hs((0.014, 0.183, 0.114)), 0.0028, 0.0028, "frame", 4, False)
h.ball(hs((0, 0.148, 0.11)), hr((0.019, 0.022, 0.02)), "nose", 10, 6)
h.ball(hs((0, 0.112, 0.098)), hr((0.024, 0.006, 0.008)), "lip", 8, 4)                          # a small smile
# grey hair: swept back in soft waves over the crown, and a bun at the back of the head with a pin
h.icob(hs((0, 0.205, -0.012)), hr((0.114, 0.1, 0.118)), "hair", 2, jitter=0.03)
for sx in (-1, 1):
	h.icob(hs((sx * 0.082, 0.19, 0.02)), hr((0.034, 0.06, 0.06)), "hair", 1, jitter=0.05)
	for k in range(3):
		h.box(hs((sx * (0.03 + k * 0.03), 0.282 - k * 0.012, 0.03 - k * 0.012)), (0.026, 0.006, 0.05), "hair_dk", 0.003, rot=gRy(sx * 0.3))
h.icob(hs((0, 0.27, -0.08)), hr((0.058, 0.05, 0.05)), "hair", 2, jitter=0.04)
h.tube(hs((-0.05, 0.29, -0.08)), hs((0.05, 0.28, -0.07)), 0.003, 0.003, "pin", 4, True)
head = h.finish(45)

# ------------------------------------------------------------------ arms
u = kit.part("upper")
u.lathe([(-0.02, 0.064, 0.07), (-0.12, 0.06, 0.064), (-0.3, 0.052, 0.055)], None, seg=12, cloth=KNIT_ARM, cap_top=False)
u.ball((0, -0.02, 0), (0.064, 0.06, 0.07), None, 12, 8, cloth=KNIT_ARM)         # a rounded shoulder, not a flat top
u.ball((0, -0.3, 0), (0.052, 0.03, 0.055), "cardi", 10, 6)
upper = u.finish()

f = kit.part("fore")
f.lathe([(0.0, 0.052, 0.054), (-0.19, 0.047, 0.048)], None, seg=12, cloth=KNIT_ARM, cap_top=False)
f.lathe([(-0.185, 0.052, 0.054), (-0.215, 0.052, 0.054)], "cardi_dk", seg=12)              # ribbed cuff
f.lathe([(-0.21, 0.042, 0.044), (-0.235, 0.044, 0.046)], "blouse", seg=12)                 # blouse cuff
f.lathe([(-0.23, 0.03, 0.032), (-0.265, 0.031, 0.033)], "skin_dk", seg=10, cap_top=False)   # wrist
f.box((0, -0.3, 0.004), (0.07, 0.07, 0.04), "skin", 0.016, segs=3)                         # hand
for i in range(4):
	f.box((-0.024 + i * 0.016, -0.343, 0.012), (0.015, 0.035, 0.03), "skin", 0.006, rot=gRx(0.3))
f.box((0.036, -0.298, 0.022), (0.018, 0.045, 0.02), "skin", 0.007, rot=gRz(0.45) @ gRx(0.3))   # thumb
fore = f.finish()

# ------------------------------------------------------------------ legs: stockings and black low-heeled lace-ups
l = kit.part("leg")
l.lathe([(-0.3, 0.064, 0.066), (-0.45, 0.058, 0.062), (-0.6, 0.048, 0.052), (-0.78, 0.04, 0.042)], "hose", seg=12)
l.box((0, -0.83, 0.02), (0.088, 0.08, 0.16), "shoe", 0.03, segs=3)
l.box((0, -0.85, 0.075), (0.085, 0.05, 0.11), "shoe", 0.025, segs=3)
l.box((0, -0.893, 0.04), (0.094, 0.018, 0.22), "sole", 0.006)
l.box((0, -0.885, -0.055), (0.06, 0.04, 0.045), "sole", 0.006)                             # little heel
for k in range(3): l.box((0, -0.805 - k * 0.012, 0.06 + k * 0.016), (0.05, 0.005, 0.005), "blouse_dk")
leg = l.finish()

# ------------------------------------------------------------------ lemonade (pivot in the hand)
c = kit.part("cane")
c.lathe([(-0.12, 0.04, 0.04), (-0.02, 0.042, 0.042)], "mug", seg=14, cap_top=False, z=0.05)
c.lathe([(-0.03, 0.038, 0.038), (-0.028, 0.038, 0.038)], "lemonade", seg=14, z=0.05)
c.ball((0.018, -0.026, 0.06), (0.018, 0.018, 0.004), "lemon", 10, 4, rot=gRz(0.6))
for k in range(4):
	a0 = -1.1 + k * 0.55; a1 = a0 + 0.55
	c.tube((0.04 + math.cos(a0) * 0.028 + 0.002, -0.07 + math.sin(a0) * 0.028, 0.05), (0.04 + math.cos(a1) * 0.028 + 0.002, -0.07 + math.sin(a1) * 0.028, 0.05), 0.007, 0.007, "mug", 6, True)
cane = c.finish()

kit.export(ARGV[0] if ARGV else "/tmp/hale.glb")
if len(ARGV) > 1: kit.preview(ARGV[1])
