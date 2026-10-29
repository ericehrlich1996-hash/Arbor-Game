## Co-op crews over the network. One player hosts: their game runs the shared world (the tree, every
## piece of wood, the truck, the chipper, the customer). Up to three more dial in from the phone in the
## cabin. Everybody walks and looks for themselves; whatever they do to the shared world goes to the
## host, and the host sends the world back out to the crew.
## For now the line is direct (an address and a port, ENet). Steam lobbies can come in later as another
## MultiplayerPeer behind these same calls.
## Autoloaded as "Net".
extends Node

signal roster_changed
signal status(text: String)

const PORT := 24565
const MAX_CREW := 4
const VERSION := 1
## hard hat colours, one per crew slot (the host is always orange)
const HATS := [Color("#ff7a12"), Color("#f2d21a"), Color("#f4f4ee"), Color("#2f7ad8")]
const POSE_HZ := 15.0
const CFG := "user://crew.cfg"

var role := ""                 # "" (on your own) | "host" | "dialing" | "guest"
var my_name := ""
var last_addr := ""
var roster := {}               # peer id -> {name, hat}
var game = null                # the running game scene (set by game.gd)
var job = null                 # NetJob while a job's going (host or guest)
var avatars := {}              # peer id -> Avatar (the other players)
var _pose_t := 0.0
var _my_scene := ""            # "hub" or the job (plus its variant): avatars only show for people in the same place

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_peer_joined)
	multiplayer.peer_disconnected.connect(_peer_left)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_failed)
	multiplayer.server_disconnected.connect(_server_gone)
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		my_name = str(cf.get_value("crew", "name", ""))
		last_addr = str(cf.get_value("crew", "addr", ""))
	if my_name == "":
		my_name = OS.get_environment("USERNAME") if OS.get_environment("USERNAME") != "" else OS.get_environment("USER")
		if my_name == "" or my_name == "root": my_name = "Arborist"
	my_name = clean_name(my_name)

static func clean_name(s: String) -> String:
	var out := ""
	for ch in s.strip_edges():
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) < 127: out += ch
	out = out.substr(0, 14).strip_edges()
	return out if out != "" else "Arborist"

func save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("crew", "name", my_name)
	cf.set_value("crew", "addr", last_addr)
	cf.save(CFG)

# ================================================================ who's who
func active() -> bool: return role == "host" or role == "guest"
func is_host() -> bool: return role == "host"
func is_guest() -> bool: return role == "guest"
func me() -> int: return multiplayer.get_unique_id() if active() else 1
func crew_size() -> int: return maxi(1, roster.size()) if active() else 1

func name_of(id: int) -> String:
	if roster.has(id): return str(roster[id].name)
	return "Someone"

func hat_of(id: int) -> Color:
	var slot: int = int(roster[id].hat) if roster.has(id) else 0
	return HATS[clampi(slot, 0, HATS.size() - 1)]

func boss_name() -> String:
	return name_of(1)

## the addresses other people can dial to reach this computer on your own network
static func local_addresses() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		if a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."): continue
		out.append(a)
	out.sort()
	return out

# ================================================================ hosting, dialing, hanging up
## open the line: returns "" or what went wrong
func host() -> String:
	if OS.has_feature("web"): return "CREW PLAY NEEDS THE PC GAME"
	leave(true)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CREW - 1)
	if err != OK: return "COULDN'T OPEN THE LINE (PORT %d BUSY?)" % PORT
	multiplayer.multiplayer_peer = peer
	role = "host"
	roster = {1: {name = my_name, hat = 0}}
	save_cfg()
	roster_changed.emit()
	status.emit("WAITING FOR CALLS")
	return ""

## dial a crew boss: an address, optionally with :port
func join(addr: String) -> String:
	addr = addr.strip_edges()
	if OS.has_feature("web"): return "CREW PLAY NEEDS THE PC GAME"
	if addr == "": return "DIAL A NUMBER FIRST"
	leave(true)
	var host_part := addr; var port := PORT
	var colon := addr.rfind(":")
	if colon > 0 and addr.count(":") == 1:
		host_part = addr.substr(0, colon)
		port = int(addr.substr(colon + 1))
		if port <= 0: port = PORT
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host_part, port)
	if err != OK: return "BAD NUMBER"
	multiplayer.multiplayer_peer = peer
	role = "dialing"
	last_addr = addr
	save_cfg()
	status.emit("RINGING...")
	# nobody picks up in 8 seconds: give up
	get_tree().create_timer(8.0).timeout.connect(func():
		if role == "dialing":
			leave(true); status.emit("NO ANSWER"))
	return ""

## hang up: drop the crew (if you're the boss) or leave it
func leave(quiet := false) -> void:
	var was := role
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = ""
	roster = {}
	_clear_avatars()
	if job and is_instance_valid(job): job.on_crew_gone()
	roster_changed.emit()
	if not quiet and was != "": status.emit("HUNG UP")

func _connected() -> void:
	_hello.rpc_id(1, my_name, VERSION)

func _failed() -> void:
	if role == "dialing":
		leave(true)
		status.emit("NO ANSWER")

func _server_gone() -> void:
	var was_job: bool = job != null and is_instance_valid(job)
	var boss := boss_name()
	leave(true)
	status.emit("THE LINE WENT DEAD")
	if game and is_instance_valid(game):
		game.hud.toast("%s hung up. You're on your own now." % boss, 4.0)
		if was_job: game.call_deferred("go_home_now")

func _peer_joined(_id: int) -> void:
	pass                         # they say hello first; until then they're just a line ringing

func _peer_left(id: int) -> void:
	var nm := name_of(id)
	if avatars.has(id):
		if is_instance_valid(avatars[id]): avatars[id].queue_free()
		avatars.erase(id)
	if not roster.has(id): return
	roster.erase(id)
	if is_host():
		_set_roster.rpc(roster)
		if job and is_instance_valid(job): job.on_peer_left(id)
	roster_changed.emit()
	if game and is_instance_valid(game): game.hud.toast("%s hung up." % nm, 3.0)

# ---------------------------------------------------------------- the handshake
@rpc("any_peer", "reliable")
func _hello(nm: String, ver: int) -> void:
	if not is_host(): return
	var id := multiplayer.get_remote_sender_id()
	if ver != VERSION: _refuse(id, "WRONG GAME VERSION"); return
	if roster.size() >= MAX_CREW: _refuse(id, "LINE BUSY · CREW'S FULL"); return
	if game == null or not is_instance_valid(game) or not game.in_hub:
		_refuse(id, "CREW'S OUT ON A JOB · CALL BACK"); return
	var used := []
	for k in roster: used.append(int(roster[k].hat))
	var slot := 1
	while used.has(slot) and slot < HATS.size() - 1: slot += 1
	var taken := []
	for k in roster: taken.append(str(roster[k].name).to_lower())
	var nm2 := clean_name(nm)
	var base := nm2; var n := 2
	while taken.has(nm2.to_lower()): nm2 = "%s %d" % [base.substr(0, 11), n]; n += 1
	roster[id] = {name = nm2, hat = slot}
	_set_roster.rpc(roster)
	roster_changed.emit()
	if game and is_instance_valid(game):
		game.hud.toast("%s joined the crew." % nm2, 3.0)
		Sfx.play("ding")

func _refuse(id: int, why: String) -> void:
	_turned_away.rpc_id(id, why)
	get_tree().create_timer(0.6).timeout.connect(func():
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id))

@rpc("authority", "reliable")
func _turned_away(why: String) -> void:
	leave(true)
	status.emit(why)

@rpc("authority", "reliable")
func _set_roster(r: Dictionary) -> void:
	roster = r
	if role == "dialing" and roster.has(me()):
		role = "guest"
		status.emit("CONNECTED · %s'S CREW" % boss_name().to_upper())
		if game and is_instance_valid(game):
			game.hud.toast("You're on %s's crew. They pick the jobs from their computer." % boss_name(), 4.5)
			Sfx.play("ding")
	for id in avatars.keys():
		if not roster.has(id):
			if is_instance_valid(avatars[id]): avatars[id].queue_free()
			avatars.erase(id)
	roster_changed.emit()

# ================================================================ poses: where everybody is
func set_scene(token: String) -> void:
	_my_scene = token

func _physics_process(dt: float) -> void:
	if not active() or game == null or not is_instance_valid(game): return
	_pose_t += dt
	if _pose_t < 1.0 / POSE_HZ: return
	_pose_t = 0.0
	var p = game.net_pose()
	if p == null: return
	p.append(_my_scene)
	_pose.rpc(p)

@rpc("any_peer", "unreliable_ordered")
func _pose(p: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not roster.has(id) or game == null or not is_instance_valid(game): return
	var same: bool = p.size() > 0 and str(p[p.size() - 1]) == _my_scene
	var av = avatars.get(id)
	if av == null or not is_instance_valid(av):
		if not same or game.level_root == null: return
		av = Avatar.new()
		av.name = "Crew_%d" % id
		game.level_root.add_child(av)
		av.setup(name_of(id), hat_of(id))
		avatars[id] = av
	av.visible_here = same
	av.apply(p)
	if is_host() and same and job and is_instance_valid(job): job.on_pose(id, p)

func _clear_avatars() -> void:
	for id in avatars:
		if is_instance_valid(avatars[id]): avatars[id].queue_free()
	avatars = {}

## a fresh scene (home, or a job): everybody's figure gets rebuilt in it
func scene_reset() -> void:
	_clear_avatars()

# ================================================================ messages
## host -> every guest (or one): something happened (reliable)
func tell(name: String, args: Array = [], to := 0) -> void:
	if not is_host(): return
	if to > 0:
		if to == 1: _event(name, args)
		else: _event.rpc_id(to, name, args)
	else:
		_event.rpc(name, args)

## host -> guests: a stream of state (latest wins; may drop)
func stream(name: String, args: Array, to := 0) -> void:
	if not is_host(): return
	if to > 0: _stream.rpc_id(to, name, args)
	else: _stream.rpc(name, args)

## guest -> host: please do this (reliable)
func ask(name: String, args: Array = []) -> void:
	if not is_guest(): return
	_ask.rpc_id(1, name, args)

## guest -> host: a stream (latest wins)
func stream_up(name: String, args: Array) -> void:
	if not is_guest(): return
	_stream_up.rpc_id(1, name, args)

@rpc("authority", "reliable")
func _event(name: String, args: Array) -> void:
	if game == null or not is_instance_valid(game): return
	game.net_event(name, args)

@rpc("authority", "unreliable_ordered")
func _stream(name: String, args: Array) -> void:
	if job and is_instance_valid(job): job.on_stream(name, args)

@rpc("any_peer", "reliable")
func _ask(name: String, args: Array) -> void:
	if not is_host(): return
	var id := multiplayer.get_remote_sender_id()
	if not roster.has(id) or game == null or not is_instance_valid(game): return
	game.net_ask(id, name, args)

@rpc("any_peer", "unreliable_ordered")
func _stream_up(name: String, args: Array) -> void:
	if not is_host(): return
	var id := multiplayer.get_remote_sender_id()
	if not roster.has(id): return
	if job and is_instance_valid(job): job.on_stream_up(id, name, args)
