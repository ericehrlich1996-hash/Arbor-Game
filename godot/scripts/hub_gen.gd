## The land round home: a clearing in deep woods with the cabin in the middle and a dirt track
## winding off through the trees. Reuses the level generator's terrain, forest and grass, with no
## road, neighbour's house, shed or creek.
class_name HubGen
extends WorldGen

const CLEAR_R := 15.0          # the clearing round the cabin

func setup(sd: int) -> void:
	seed = sd
	rng.seed = sd
	s = 1.0
	mown = false
	for n in [_nA, _nB, _nC]:
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 1.0
	_nA.seed = sd; _nB.seed = sd + 7; _nC.seed = sd + 3
	road_z = -900.0
	park = Vector3(7.0, 0, -9.5)
	drive = [Vector2(7.0, -6.5), Vector2(7.5, -14), Vector2(5.5, -30), Vector2(-3, -52), Vector2(-14, -80), Vector2(-20, -120), Vector2(-24, -150)]
	# the cabin stands in for the "house"; nothing else on the property but woods
	house = {x = 0.0, z = 0.0, w = 9.6, d = 8.6, wall = 2.4, siding = Color.WHITE, roof = Color.WHITE, door = Color.WHITE}
	shed = {x = 0.0, z = -900.0, w = 1.0, d = 1.0}
	pile = {x = 0.0, z = -900.0, w = 1.0, d = 1.0}
	tree = {x = 0.0, z = -900.0, h = 0.0}
	mailbox = Vector2(0, -900)
	old_man = Vector2(0, -900)
	flat = [{x = 0.0, z = 0.0, r = 9.0}, {x = park.x, z = park.z, r = 5.0}]
	_base = _raw(0, 0)
	var st := S / N
	_grid.resize((N + 1) * (N + 1))
	for j in range(N + 1):
		for i in range(N + 1):
			_grid[j * (N + 1) + i] = _smooth_h(-S / 2 + i * st, -S / 2 + j * st)
	drive_path = _spline(drive, 6)

## 0 in the clearing, rising quickly to 1 in the trees (with a ragged edge); the track keeps a gap
func forestness(x: float, z: float) -> float:
	if _edge.seed != seed + 5: _edge.seed = seed + 5; _edge.frequency = 0.05
	var d := Vector2(x, z).length() + _edge.get_noise_2d(x, z) * 5.0
	return clampf((d - CLEAR_R) / 9.0, 0.0, 1.0)

func creek_z(_x: float) -> float: return -2000.0
func creek_d(_x: float, _z: float) -> float: return 1e6
func floor_h(x: float, z: float) -> float: return H(x, z)

func build(root: Node3D) -> void:
	_build_terrain(root)
	var mb := MeshBuilder.new()
	_ribbon(mb, drive_path, 3.0, Color.html("#6e5f48"), 0.05)
	var mi := mb.instance(); mi.name = "Track"; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var forest := Forest.new(); forest.build(self, root)
	_build_grass(root)
