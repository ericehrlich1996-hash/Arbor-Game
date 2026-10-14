## Splitting wood: bucking a trunk piece along a finished cut, taking limbs off, cutting limbs shorter.
## New pieces inherit the parent's transform (the wood frame), velocity and every earlier cut.
class_name Lumber
extends RefCounted

static func _spawn(game, parent: WoodPiece, setup: Callable) -> WoodPiece:
	var p := WoodPiece.new()
	p.T = parent.T
	setup.call(p)
	game.level_root.add_child(p)
	p.global_transform = parent.global_transform
	p.build()
	p.linear_velocity = parent.linear_velocity
	p.angular_velocity = parent.angular_velocity
	return p

static func _retire(game, parent: WoodPiece, replacement: WoodPiece) -> void:
	parent.mode = "gone"
	if game.tree.stem == parent: game.tree.stem = replacement
	parent.queue_free()

## a finished cut through a trunk piece: two pieces, each keeping its own side of the cut plane
static func buck(game, pc: WoodPiece, c: Dictionary) -> void:
	var e: Vector3 = c.e; var nn: Vector3 = c.n
	var rest := pc.ops.filter(func(op): return op != c)
	var A_limbs := []; var B_limbs := []
	for id in pc.limbs:
		if nn.dot(pc.T.limbs[id].base - e) <= 0: A_limbs.append(id)
		else: B_limbs.append(id)
	var mk := func(sgn: float, lb: Array) -> Callable:
		return func(p: WoodPiece) -> void:
			p.kind = pc.kind; p.y0 = pc.y0; p.y1 = pc.y1
			p.ops = rest.duplicate() + [{type = "clip", p = e + nn * Wood.KERF * sgn, n = nn * sgn}]
			p.limbs = lb.duplicate(); p.stubs = pc.stubs.duplicate()
			for id in lb:
				if pc.lt.has(id): p.lt[id] = pc.lt[id]
	var a := _spawn(game, pc, mk.call(1.0, A_limbs))
	var b := _spawn(game, pc, mk.call(-1.0, B_limbs))
	# in-progress cuts follow the wood they're in
	for op in rest:
		if op.type == "kerf" and not op.get("done", false):
			op.piece = a if nn.dot(op.e - e) <= 0 else b
	_retire(game, pc, a if not A_limbs.is_empty() or B_limbs.is_empty() else b)
	Sfx.play("crunch")

## a limb cut flush at the collar: it comes off whole, a stub stays on the stem
static func limb_off(game, pc: WoodPiece, id: int) -> WoodPiece:
	var tb: float = pc.lt.get(id, 1.0)
	var lp := _spawn(game, pc, func(p: WoodPiece) -> void:
		p.kind = "limb"; p.limb = id; p.t0 = 0.0; p.t1 = tb)
	pc.limbs.erase(id); pc.lt.erase(id); pc.stubs.append(id)
	pc.build()
	var L: Dictionary = pc.T.limbs[id]
	lp.linear_velocity += (pc.global_transform.basis * Vector3(L.dir.x, 0, L.dir.z)).normalized() * 0.4
	Sfx.play("crunch")
	return lp

## a limb cut part way out: the stretch beyond t drops, the rest stays on the stem
static func cut_limb_at(game, pc: WoodPiece, id: int, t: float) -> void:
	var tb: float = pc.lt.get(id, 1.0)
	_spawn(game, pc, func(p: WoodPiece) -> void:
		p.kind = "limb"; p.limb = id; p.t0 = t; p.t1 = tb)
	pc.lt[id] = t
	pc.build()
	Sfx.play("crunch")

static func split_limb(game, pc: WoodPiece, t: float) -> void:
	var old_t1 := pc.t1
	_spawn(game, pc, func(p: WoodPiece) -> void:
		p.kind = "limb"; p.limb = pc.limb; p.t0 = t; p.t1 = old_t1)
	pc.t1 = t
	pc.build()
	Sfx.play("crunch")
