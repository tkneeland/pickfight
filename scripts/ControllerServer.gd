extends Node

## Host-side input transport for phone controllers (ADR-0001, ADR-0002).
##
## Runs two TCP listeners, polled from `_process`:
##
##   * `http_port` (8080) serves `res://controller/index.html` — the controller
##     page a player opens on their phone.
##   * `ws_port` (8081) accepts WebSocket connections from that page and binds
##     each one to a player slot in join order.
##
## Two ports rather than one because `StreamPeerTCP` cannot peek: once bytes
## are read to route an HTTP request they are consumed, and
## `WebSocketPeer.accept_stream` has to read the handshake itself.
##
## Wire format phone -> host: one binary frame per controller frame, exactly
## 8 bytes, `float32 x` then `float32 y`, little-endian, unit-disc normalised.
## Wire format host -> phone: one text frame `{"slot":<i>,"id":<claim id>}`
## sent on bind (the id is the one the phone sent, or one the host made up for
## a client that sent none (issue #164), so it can present it next time), and
## a `{"t":"buzz","kind":<kind>}` text frame per `send_buzz()` (issue #34,
## ADR-0013), and a `{"t":"lobby",...}` text frame per `set_lobby_state()`
## (issue #120). Phone -> host text frames (#120): `{"t":"ready","v":<bool>}`
## and, from the host phone only, `{"t":"target","n":<int>}`; and the
## phone's nickname, `{"t":"name","v":<string>}` (issue #121); and, from the
## host phone only, `{"t":"host","cmd":"pause"|"resume"|"end"}` and
## `{"t":"host","cmd":"kick","slot":<int>}` (issue #149); and the phone's
## look (issue #151), `{"t":"hat","v":<hat id>}` and `{"t":"color","v":<int>}`,
## answered by a `{"t":"looks",...}` frame (see `looks_message()`).
## From the host phone only, `{"t":"solo","v":<bool>}` asks for bots, or
## for them to go (issue #152).
##
## Hardening (issue #164): a kick may carry the `"claim"` serial the lobby
## state gave the target, and End match the `"match"` serial it gave the
## match; a command whose serial is out of date -- a confirm left open while
## the slot changed hands or the next match began -- is ignored. Text frames
## are limited to `TEXT_FRAMES_PER_SEC` per slot, and a malformed one is
## dropped quietly. A phone that connects with the id of a slot whose socket
## is still open (a quick reconnect, the QR opened in a second tab) takes that
## slot over, and the old socket is closed with `REPLACED_REASON`.
##
## Virtual controllers (issue #152): a bot holds a slot the way a phone does,
## but with no socket. `add_virtual_controller()` claims it, and
## `push_virtual_input()` is its packet: the vector goes through the same
## smoothing as a phone's and on to `Player.set_input_vector()`. A virtual
## slot counts as connected and always ready; it is never the host, never
## buzzed and never expires. `BotDirector`, built here, owns the bots.
##
## Liveness: a phone that screen-locks or leaves Wi-Fi mid-drag stops sending
## without ever closing the socket, and the last frame it sent was non-zero.
## Two defences, because neither alone is enough:
##
##   * WebSocket heartbeat (ping/pong) so a half-open TCP connection is
##     eventually detected by the socket layer.
##   * A per-slot input deadline (`controller_timeout_sec`): no well-formed
##     packet for that long and the controller is treated as gone — the
##     player's vector is zeroed so the weapon eases to rest and the socket is
##     closed. The slot's claim is held, as for any disconnect (ADR-0007),
##     until the phone reclaims it or `expire_disconnected_claims()` drops it.
##
## Sockets that connect and never finish a request (speculative preconnect,
## port scanners, stalled handshakes) are dropped after
## `connection_timeout_sec` rather than being polled forever.
##
## Smoothing (issue #113): Wi-Fi delivers the phone's steady 60 Hz stream in
## clumps -- nothing for a frame, then two or three packets at once -- and
## "latest value wins" turns every clump into a jump, which makes the weapon
## twitch. Each slot's packets therefore set a target that the input vector
## follows with a short exponential ease (`INPUT_SMOOTHING_SEC`), stepped every
## frame. A release (a (0,0) packet) and a deliberate flick (a jump of at least
## `INPUT_FLICK_SNAP`) are passed through at once, never eased. Only packets
## go through this: a direct `Player.set_input_vector()` call is unsmoothed.
##
## Run the host with `-- --log-input` to print every decoded packet, every
## bind/unbind/timeout, and a periodic "weapon steady" line while a bound weapon is
## unchanged; the automated checks assert on those lines.

## A phone claimed `slot` fresh -- not a reconnect to a slot it already held.
## RoundManager clears the slot's match numbers on it (issue #161) and
## SfxHooks plays the join sound (issue #75, ADR-0016).
signal player_joined(slot: int)
## The host phone pressed "Solo practice" (`on`) or "Remove bots" (issue #152).
signal solo_requested(on: bool)
## `host_slot()` changed, to `slot` (-1 with no phone connected). Checked every
## frame, paused or not, so a paused game still tells the phones who holds the
## host menu when the host's phone drops (issue #165).
signal host_changed(slot: int)

## The host phone asked for `cmd` (issue #149): "pause", "resume" or "end",
## with `slot` -1; or "kick", emitted after `slot` has been removed from the
## roster. Only ever emitted for a request from `host_slot()`. RoundManager
## decides what each means.
signal host_command(cmd: String, slot: int)

## The close reason a kicked phone is shown, and refused with if it comes back.
const KICKED_REASON: String = "removed by the host"
## Commands the host phone may send besides "kick".
const HOST_COMMANDS: PackedStringArray = ["pause", "resume", "end"]
## The close reason (code 4002) an older socket gets when the same phone
## connects again before it timed out (issue #164). The page does not retry
## on it, so two tabs sharing one id cannot keep taking the slot off each other.
const REPLACED_REASON: String = "opened somewhere else"
## At most this many text frames per slot per second are acted on (issue
## #164); the rest are dropped. A phone sends a handful on join and one per tap.
const TEXT_FRAMES_PER_SEC: int = 20
## Combining marks kept on one character of a nickname (issue #164): enough
## for real accents, not for a tower of them.
const MAX_STACKED_MARKS: int = 2
## Issue #193: a text frame longer than this many bytes is dropped unread.
## Every frame a phone sends is well under it; a 60 KB nickname is not.
const MAX_TEXT_FRAME_BYTES: int = 1024
## Issue #193: each socket's inbound buffer. WebSocketPeer's default (64 KB)
## admits a frame far larger than anything a phone has a reason to send.
const INBOUND_BUFFER_BYTES: int = 16384
## Issue #193: a nickname is cut to this many characters before it is
## cleaned, so cleaning costs the same however long the raw text was.
const MAX_RAW_NAME_LENGTH: int = 64
## Issue #193: client ids longer than this are cut to it. The page's are
## 36-character UUIDs.
const MAX_CLIENT_ID_LENGTH: int = 64
## Issue #193: a phone whose claim was released (a reload or a screen lock in
## the lobby lets it go at once) and that comes back within this long gets its
## old place in the join order back -- so the host is host again -- along
## with its slot, colour, hat and nickname where still free.
const REJOIN_GRACE_MSEC: int = 10000
## Issue #193: at most this many recently released claims are remembered.
const MAX_RECENT_LEAVERS: int = 32
## The lobby phases a match is being played in; entering one from any other
## phase starts a new match serial (issue #164).
const MATCH_PHASES: PackedStringArray = ["playing", "round_end"]

## The hats a phone may pick (issue #151), by path (CLAUDE.md).
const HatScript := preload("res://scripts/Hat.gd")

const PAGE_PATH: String = "res://controller/index.html"
const WS_PORT_TOKEN: String = "__WS_PORT__"
const MAX_HEADER_BYTES: int = 8192
const PACKET_SIZE: int = 8
## Every `kind` `send_buzz()` is sent with, strongest first; the controller
## page has a vibration pattern and a flash for each.
const BUZZ_KINDS: PackedStringArray = ["win", "eliminated", "struck", "hit"]
const ANGLE_LOG_EPSILON: float = 0.0005
const LENGTH_LOG_EPSILON: float = 0.05
## Time constant of the ease from the last applied input vector to the newest
## packet (issue #113). About 1.5 frames at 60 Hz: long enough to spread a
## clump of late packets over the frames they should have arrived in, short
## enough that a steady drag lags by only that much.
const INPUT_SMOOTHING_SEC: float = 0.025
## A packet at least this far (unit-disc units) from the current input is a
## deliberate flick and is applied at once rather than eased into.
const INPUT_FLICK_SNAP: float = 0.5
## Within this distance of its target the eased input snaps onto it, so a
## held drag reaches exactly what the phone sends.
const INPUT_SETTLE_EPSILON: float = 0.001
## Physics frames between "weapon steady" lines. Steadiness has to be provable
## from a line that is present, not from the absence of change lines.
const STEADY_LOG_FRAMES: int = 30
## Lower-cased substrings of an adapter's name that mark it as virtual, so its
## address is listed after real ones (see `_join_urls`).
const VIRTUAL_ADAPTER_HINTS: PackedStringArray = [
	"vethernet", "wsl", "hyper-v", "docker", "virtualbox", "vmware", "vbox",
	"tailscale", "zerotier", "wireguard", "openvpn", "tap-", "tun", "utun",
	"bridge", "virbr", "loopback",
]

## 0 on either port asks the OS for a free one; `_ready()` then writes the port
## it got back here, so readers (the join URL, the served page) see the real
## one. The scenario suite does this so parallel runs never collide (#73).
@export var http_port: int = 8080
@export var ws_port: int = 8081
@export var player_paths: Array[NodePath] = []
@export var join_label_path: NodePath
@export var qr_texture_path: NodePath
## No well-formed packet for this long and the bound controller is considered
## gone. Sized above a few dropped frames but well below "a player noticed".
@export var controller_timeout_sec: float = 2.0
## How long a socket may sit without completing an HTTP request or a WebSocket
## handshake before it is dropped.
@export var connection_timeout_sec: float = 5.0
## WebSocket ping interval. `WebSocketPeer` defaults this to 0.0 (no ping/pong
## at all), which is what lets a half-open connection look open forever.
@export var heartbeat_interval_sec: float = 1.0

## One pending HTTP request: the socket, the bytes read so far, and the point
## in time after which an unfinished request is abandoned.
class HttpConn extends RefCounted:
	var tcp: StreamPeerTCP
	var buf: PackedByteArray = PackedByteArray()
	var deadline_msec: int

	func _init(p_tcp: StreamPeerTCP, p_deadline_msec: int) -> void:
		tcp = p_tcp
		deadline_msec = p_deadline_msec

## One WebSocket connection between `accept_stream` and `STATE_OPEN`, with the
## point in time after which an unfinished handshake is abandoned.
class PendingConn extends RefCounted:
	var peer: WebSocketPeer
	var deadline_msec: int

	func _init(p_peer: WebSocketPeer, p_deadline_msec: int) -> void:
		peer = p_peer
		deadline_msec = p_deadline_msec

## One slot's input smoothing (issue #113; see the header). `push()` takes a
## packet, `step()` advances the ease by `delta` seconds and returns the input
## vector to apply. Pure, so a scenario can feed it a jitter pattern directly.
class InputSmoother extends RefCounted:
	var target: Vector2 = Vector2.ZERO
	var value: Vector2 = Vector2.ZERO

	func push(v: Vector2) -> void:
		# A NaN target would poison the ease for good, not just one frame.
		target = v.limit_length(1.0) if is_finite(v.x) and is_finite(v.y) else Vector2.ZERO
		if target == Vector2.ZERO or value.distance_to(target) >= INPUT_FLICK_SNAP:
			value = target

	func step(delta: float) -> Vector2:
		if value.distance_to(target) <= INPUT_SETTLE_EPSILON:
			value = target
		else:
			value = value.lerp(target, 1.0 - exp(-delta / INPUT_SMOOTHING_SEC))
		return value

	func reset() -> void:
		target = Vector2.ZERO
		value = Vector2.ZERO

var _log_input: bool = false

var _http_server: TCPServer = TCPServer.new()
var _ws_server: TCPServer = TCPServer.new()
var _http_clients: Array[HttpConn] = []
var _pending: Array[PendingConn] = []
## A socket that has finished the WebSocket handshake but has not yet sent
## its identifying first frame -- see `_process_websocket`'s second stage.
## Reuses `PendingConn`: the shape (peer, deadline) is the same.
var _awaiting_id: Array[PendingConn] = []

# Untyped on purpose: elements are `Player` nodes and GDScript's analyser
# would reject `set_input_vector` on a statically typed `Node`.
var _players: Array = []
var _slot_peers: Array[WebSocketPeer] = []
var _slot_last_packet_msec: PackedInt64Array = PackedInt64Array()
var _smoothers: Array[InputSmoother] = []
var _last_weapon: PackedVector2Array = PackedVector2Array()
var _steady_frames: PackedInt32Array = PackedInt32Array()
# 1 once a slot has ever held a controller: keeps the startup settle of an
# untouched weapon out of the diagnostics.
var _bound_once: PackedByteArray = PackedByteArray()
## Whether a slot has an open roster entry (ADR-0007): set by `_fresh_claim()`,
## cleared by `_release_claim()` -- when `expire_disconnected_claims()` runs at
## a round boundary, on a kick, or when a bot leaves -- and never by an
## ordinary disconnect, which is the whole point. A round loop
## reads `claimed_slots()` to know who is in the roster and calls
## `expire_disconnected_claims()` before every attempt to start a round.
var _slot_claimed: PackedByteArray = PackedByteArray()
## The id that claimed each slot, so a reconnecting phone can be matched back
## to the same slot instead of taking whatever is free. Empty for an
## unclaimed slot.
var _slot_client_id: PackedStringArray = PackedStringArray()

## Lobby (issue #120). Whether each slot's phone has pressed Ready; cleared
## when its controller drops, so a phone that walked away is never counted.
var _slot_ready: PackedByteArray = PackedByteArray()
## Claimed slots in the order they were first claimed. The host is the first
## of them with a controller connected right now, so if the host leaves, the
## next phone to have joined takes over.
var _join_order: Array[int] = []
## "First to N": set by the host phone, read by RoundManager.
var _match_target: int = 5
const MIN_MATCH_TARGET: int = 1
const MAX_MATCH_TARGET: int = 99
## Each slot's nickname (issue #121), as the phone last sent it, trimmed to
## MAX_NAME_LENGTH. Empty until the phone sends one.
var _slot_name: PackedStringArray = PackedStringArray()
const MAX_NAME_LENGTH: int = 12
## Client ids the host phone kicked (issue #149): refused for the rest of the
## session, so a kicked page's automatic reconnect cannot walk back in.
var _kicked_ids: PackedStringArray = PackedStringArray()
## Looks (issue #151). Each claimed slot's hat (a `Hat.gd` id) and the colour
## it holds, as an index into `_palette`; -1 for an unclaimed slot. No two
## claimed slots ever hold the same colour.
var _slot_hat: PackedStringArray = PackedStringArray()
var _slot_color: PackedInt32Array = PackedInt32Array()
## The colours on offer: each player's `identity_color` as the scene set it,
## so colour i is slot i's automatic colour. Transparent for a missing player.
var _palette: Array[Color] = []
## The last lobby state RoundManager set, re-sent to every phone that binds.
var _lobby_state: Dictionary = {}
## 1 where a bot holds the slot (issue #152), with no socket behind it.
var _slot_virtual: PackedByteArray = PackedByteArray()
## Issue #164. A serial per fresh claim, so a kick aimed at "whoever held slot
## 2 when the confirm opened" cannot land on the next player in slot 2; 0 for
## an unclaimed slot. Sent to the phones in the lobby state's player entries.
var _slot_claim_serial: PackedInt32Array = PackedInt32Array()
var _last_claim_serial: int = 0
## Issue #164. Bumped each time a match starts (see MATCH_PHASES), and sent as
## the lobby state's "match", so an old End match cannot end the next one.
var _match_serial: int = 0
## Issue #164. Each slot's text-frame budget: when its one-second window
## began, and how many text frames arrived in it.
var _slot_text_window_msec: PackedInt64Array = PackedInt64Array()
var _slot_text_count: PackedInt32Array = PackedInt32Array()
## Issue #164. Ids made up for clients that never sent one.
var _last_generated_id: int = 0
## Issue #193. Each claimed slot's place in the join order: `_join_order` is
## kept sorted by it. A phone that comes back within REJOIN_GRACE_MSEC of
## losing its claim reuses its old rank; everyone else gets the next one.
var _slot_join_rank: PackedInt32Array = PackedInt32Array()
var _last_join_rank: int = 0
## Issue #193. Client id -> what its released claim held: {"rank", "slot",
## "color", "hat", "name", "msec"}. Entries older than REJOIN_GRACE_MSEC are
## ignored and pruned.
var _recent_leavers: Dictionary = {}
const BotDirectorScript: GDScript = preload("res://scripts/BotDirector.gd")
## The bots' owner, built in `_ready()` so no scene has to add it.
var bot_director: Node = null
## The Solo practice button is heeded only in these lobby phases (issue #165):
## mid-match, removing the bots would leave their bodies in the round.
const SOLO_PHASES: PackedStringArray = ["lobby", "countdown"]
var _last_host: int = -1
## The join URL and QR the lobby screen shows (#120). The QR is null when
## `qrencode` is unavailable.
var join_url: String = ""
var join_qr_texture: ImageTexture = null

func _ready() -> void:
	_log_input = OS.get_cmdline_user_args().has("--log-input")
	# The host phone's Resume has to reach a paused game (issue #149).
	process_mode = Node.PROCESS_MODE_ALWAYS

	for path in player_paths:
		_players.append(get_node_or_null(path))
	_slot_peers.resize(_players.size())
	_slot_last_packet_msec.resize(_players.size())
	_last_weapon.resize(_players.size())
	_steady_frames.resize(_players.size())
	_bound_once.resize(_players.size())
	_slot_claimed.resize(_players.size())
	_slot_client_id.resize(_players.size())
	_slot_ready.resize(_players.size())
	_slot_name.resize(_players.size())
	_slot_hat.resize(_players.size())
	_slot_color.resize(_players.size())
	for i in _players.size():
		_slot_hat[i] = HatScript.NONE
		_slot_color[i] = -1
		_palette.append(_players[i].identity_color if _players[i] != null else Color(0, 0, 0, 0))
	_slot_virtual.resize(_players.size())
	_slot_claim_serial.resize(_players.size())
	_slot_text_window_msec.resize(_players.size())
	_slot_text_count.resize(_players.size())
	_slot_join_rank.resize(_players.size())
	for i in _last_weapon.size():
		_last_weapon[i] = Vector2(NAN, NAN)
		_smoothers.append(InputSmoother.new())

	var http_err: int = _http_server.listen(http_port)
	if http_err != OK:
		push_error("ControllerServer: cannot listen on HTTP port %d (error %d)" % [http_port, http_err])
	var ws_err: int = _ws_server.listen(ws_port)
	if ws_err != OK:
		push_error("ControllerServer: cannot listen on WebSocket port %d (error %d)" % [ws_port, ws_err])
	if http_err == OK and http_port == 0:
		http_port = _http_server.get_local_port()
	if ws_err == OK and ws_port == 0:
		ws_port = _ws_server.get_local_port()

	var urls: PackedStringArray = _join_urls()
	if urls.is_empty():
		print("ControllerServer: no non-loopback IPv4 address found; try http://127.0.0.1:%d/" % http_port)
	for url in urls:
		print("Controller page: %s" % url)

	join_url = urls[0] if not urls.is_empty() else "http://127.0.0.1:%d/" % http_port
	var label: Label = get_node_or_null(join_label_path) as Label
	if label != null:
		# One URL only: the label sits directly above the score line, and every
		# address is already printed to the console for the rare case the
		# first one isn't the room's network.
		label.text = "Join on your phone:\n" + (urls[0] if not urls.is_empty() else "http://127.0.0.1:%d/" % http_port)

	var qr_rect: TextureRect = get_node_or_null(qr_texture_path) as TextureRect
	if qr_rect != null:
		if urls.is_empty():
			qr_rect.visible = false
		else:
			var qr_texture: ImageTexture = _generate_qr_texture(urls[0])
			join_qr_texture = qr_texture
			qr_rect.visible = qr_texture != null
			if qr_texture != null:
				qr_rect.texture = qr_texture

	bot_director = BotDirectorScript.new()
	bot_director.name = "BotDirector"
	bot_director.server = self
	# Bots stop thinking while the host phone has the game paused (#165).
	bot_director.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(bot_director)

func _process(delta: float) -> void:
	_process_http()
	_process_websocket()
	if host_slot() != _last_host:
		_last_host = host_slot()
		host_changed.emit(_last_host)
	_apply_smoothed_input(delta)

## Step every bound slot's ease and hand the result to its player (issue #113).
func _apply_smoothed_input(delta: float) -> void:
	for slot in _slot_peers.size():
		if (_slot_peers[slot] == null and _slot_virtual[slot] == 0) or _players[slot] == null:
			continue
		_players[slot].set_input_vector(_smoothers[slot].step(delta))

## Weapon diagnostics run on the physics tick because that is the rate the weapon is
## actually integrated at, which makes "held steady for N frames" meaningful.
##
## A slot is reported while a controller is bound, and afterwards until its weapon
## has settled back to rest -- otherwise the easing that follows a disconnect
## would happen entirely off the record.
func _physics_process(_delta: float) -> void:
	for slot in _slot_peers.size():
		if _slot_peers[slot] == null and not _weapon_away_from_rest(slot):
			continue
		_log_weapon(slot)

## True while an unbound slot still owes the log an easing line. The last
## reported length counts too, so the frame the weapon actually reaches rest is
## reported before logging stops.
func _weapon_away_from_rest(slot: int) -> bool:
	if _bound_once[slot] == 0:
		return false
	var player: Variant = _players[slot]
	if player == null:
		return false
	var rest: float = player.weapon_min_length + LENGTH_LOG_EPSILON
	if player.weapon_length > rest:
		return true
	return is_finite(_last_weapon[slot].y) and _last_weapon[slot].y > rest

# --- HTTP -------------------------------------------------------------------

## Join URLs, best first: the QR code and the on-screen label only show the
## first one, so it has to be the address a phone on the room's Wi-Fi can
## actually reach.
##
## Link-local `169.254.*` addresses are dropped outright -- a disconnected or
## unconfigured adapter self-assigns one, and no phone can reach it. Adapters
## whose names mark them as virtual (WSL, Hyper-V, Docker, VPNs) are kept but
## sorted last. Deliberately not ranked by address range: a real Wi-Fi network
## can hand out 172.16/12 or 10/8 just as happily as 192.168/16.
func _join_urls() -> PackedStringArray:
	var preferred: PackedStringArray = PackedStringArray()
	var virtual: PackedStringArray = PackedStringArray()
	for iface: Dictionary in IP.get_local_interfaces():
		var adapter: String = (str(iface.get("friendly", "")) + " " + str(iface.get("name", ""))).to_lower()
		var is_virtual: bool = false
		for hint: String in VIRTUAL_ADAPTER_HINTS:
			if adapter.contains(hint):
				is_virtual = true
				break
		for addr: String in iface.get("addresses", []):
			if addr.contains(":") or addr.begins_with("127.") or addr.begins_with("169.254."):
				continue # IPv6, loopback, link-local
			var url: String = "http://%s:%d/" % [addr, http_port]
			if url in preferred or url in virtual:
				continue
			if is_virtual:
				virtual.append(url)
			else:
				preferred.append(url)
	preferred.append_array(virtual)
	return preferred

## Shells out to `qrencode` rather than generating QR modules in GDScript:
## the ISO 18004 module-placement/masking rules are easy to get subtly wrong
## in a way that still looks like a QR code but does not scan, and this
## engine's install has no QR library. `null` on any failure (tool missing,
## nonzero exit, unreadable output) -- the join label's text URL already
## covers that case, so a phone can still join by typing it.
const QRENCODE_CANDIDATES: PackedStringArray = [
	"/opt/homebrew/bin/qrencode", "/usr/local/bin/qrencode", "qrencode"]

func _generate_qr_texture(text: String) -> ImageTexture:
	var out_path: String = OS.get_user_data_dir() + "/join_qr.png"
	var output: Array = []
	# An app launched from Finder gets launchd's bare PATH (/usr/bin:/bin:...),
	# which has no Homebrew in it, so the exported macOS build never found
	# qrencode (playtest 2026-09-27: no QR on the lobby screen). Try the
	# Homebrew prefixes by absolute path before the bare name.
	var exit_code: int = -1
	for exe: String in QRENCODE_CANDIDATES:
		if exe.begins_with("/") and not FileAccess.file_exists(exe):
			continue
		exit_code = OS.execute(exe, ["-o", out_path, "-s", "8", "-m", "2", text], output, true)
		if exit_code == 0:
			break
	if exit_code != 0:
		push_warning("ControllerServer: qrencode unavailable or failed (exit %d) -- put qrencode on PATH (e.g. `brew install qrencode`, `apt install qrencode`, or a Windows build) to show a join QR code" % exit_code)
		return null
	var image: Image = Image.new()
	if image.load(out_path) != OK:
		push_warning("ControllerServer: failed to load generated QR image at %s" % out_path)
		return null
	return ImageTexture.create_from_image(image)

func _process_http() -> void:
	var now: int = Time.get_ticks_msec()
	var idle_deadline: int = now + int(connection_timeout_sec * 1000.0)

	while _http_server.is_connection_available():
		var tcp: StreamPeerTCP = _http_server.take_connection()
		if tcp == null:
			continue
		tcp.set_no_delay(true)
		_http_clients.append(HttpConn.new(tcp, idle_deadline))

	# `Array[T].duplicate()` returns an untyped Array, so the loop variable has
	# to be typed explicitly or type inference inside the body fails to parse.
	for conn: HttpConn in _http_clients.duplicate():
		conn.tcp.poll()
		if conn.tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_http_clients.erase(conn)
			continue

		var available: int = conn.tcp.get_available_bytes()
		if available > 0:
			var chunk: Array = conn.tcp.get_data(available)
			if chunk[0] == OK:
				conn.buf.append_array(chunk[1])

		if conn.buf.size() > MAX_HEADER_BYTES:
			conn.tcp.disconnect_from_host()
			_http_clients.erase(conn)
			continue

		var text: String = conn.buf.get_string_from_ascii()
		if not text.contains("\r\n\r\n"):
			# A socket that connects and never finishes a request would
			# otherwise be polled for the rest of the session.
			if now > conn.deadline_msec:
				if _log_input:
					print("http connection dropped: idle %.1fs without a complete request" % connection_timeout_sec)
				conn.tcp.disconnect_from_host()
				_http_clients.erase(conn)
			continue

		_answer_http(conn, text.get_slice("\r\n", 0))
		conn.tcp.disconnect_from_host()
		_http_clients.erase(conn)

func _answer_http(conn: HttpConn, request_line: String) -> void:
	var parts: PackedStringArray = request_line.split(" ", false)
	var method: String = parts[0] if parts.size() > 0 else ""
	var target: String = parts[1] if parts.size() > 1 else ""
	var path: String = target.get_slice("?", 0)

	if method == "GET" and (path == "/" or path == "/index.html"):
		var page: String = _load_page()
		if page.is_empty():
			_send_http(conn, 500, "Internal Server Error", "text/plain; charset=utf-8", "controller page missing".to_utf8_buffer())
			return
		_send_http(conn, 200, "OK", "text/html; charset=utf-8", page.to_utf8_buffer())
		return

	_send_http(conn, 404, "Not Found", "text/plain; charset=utf-8", "404 Not Found".to_utf8_buffer())

## Read from disk on every request, so the page can be tuned (drag radius, feel)
## without restarting the host.
func _load_page() -> String:
	var file: FileAccess = FileAccess.open(PAGE_PATH, FileAccess.READ)
	if file == null:
		push_error("ControllerServer: cannot open %s" % PAGE_PATH)
		return ""
	var html: String = file.get_as_text()
	file.close()
	return html.replace(WS_PORT_TOKEN, str(ws_port))

func _send_http(conn: HttpConn, code: int, reason: String, content_type: String, body: PackedByteArray) -> void:
	var header: String = "HTTP/1.1 %d %s\r\n" % [code, reason]
	header += "Content-Type: %s\r\n" % content_type
	header += "Content-Length: %d\r\n" % body.size()
	header += "Cache-Control: no-store\r\n"
	header += "Connection: close\r\n\r\n"
	var out: PackedByteArray = header.to_utf8_buffer()
	out.append_array(body)
	conn.tcp.put_data(out)

# --- WebSocket --------------------------------------------------------------

func _process_websocket() -> void:
	var now: int = Time.get_ticks_msec()

	while _ws_server.is_connection_available():
		var tcp: StreamPeerTCP = _ws_server.take_connection()
		if tcp == null:
			continue
		tcp.set_no_delay(true)
		var peer: WebSocketPeer = WebSocketPeer.new()
		# Defaults to 0.0, i.e. no ping/pong, which is exactly how a dead phone
		# stays STATE_OPEN forever.
		peer.heartbeat_interval = heartbeat_interval_sec
		peer.inbound_buffer_size = INBOUND_BUFFER_BYTES
		if peer.accept_stream(tcp) == OK:
			_pending.append(PendingConn.new(peer, now + int(connection_timeout_sec * 1000.0)))

	for conn: PendingConn in _pending.duplicate():
		conn.peer.poll()
		var state: int = conn.peer.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			_pending.erase(conn)
			_awaiting_id.append(PendingConn.new(conn.peer, now + int(connection_timeout_sec * 1000.0)))
		elif state == WebSocketPeer.STATE_CLOSED:
			_pending.erase(conn)
		elif now > conn.deadline_msec:
			if _log_input:
				print("websocket connection dropped: handshake idle %.1fs" % connection_timeout_sec)
			conn.peer.close(1002, "handshake timeout")
			_pending.erase(conn)

	# Second stage: the socket is open, but a slot is not handed out until the
	# controller page has said who it is (ADR-0007's reclaim needs an id to
	# match against). A page that never sends one -- an old cached copy, a
	# stray client -- is not punished for it; it just binds as a new,
	# unmatched roster entry once its own deadline passes.
	for conn: PendingConn in _awaiting_id.duplicate():
		conn.peer.poll()
		var state: int = conn.peer.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
			_awaiting_id.erase(conn)
			continue
		if state != WebSocketPeer.STATE_OPEN:
			continue
		var id: Variant = _read_client_id(conn.peer)
		if id != null:
			_awaiting_id.erase(conn)
			_bind_with_id(conn.peer, id)
		elif now > conn.deadline_msec:
			_awaiting_id.erase(conn)
			_bind_with_id(conn.peer, "")

	var timeout_msec: int = int(controller_timeout_sec * 1000.0)
	for slot in _slot_peers.size():
		var peer: WebSocketPeer = _slot_peers[slot]
		if peer == null:
			continue
		peer.poll()
		var state: int = peer.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			_drain(slot, peer)
			var silent_for: int = now - _slot_last_packet_msec[slot]
			if silent_for > timeout_msec:
				# The decisive case: the phone screen-locked or left Wi-Fi
				# mid-drag, so the (0,0) release frame never arrived and the
				# socket still looks open. Treat it as gone.
				if _log_input:
					print("slot %d controller timed out after %d ms without input" % [slot, silent_for])
				peer.close(1001, "input timeout")
				_unbind(slot)
		elif state == WebSocketPeer.STATE_CLOSED:
			_unbind(slot)

## Read the id a controller page sends as its first (and only) text frame --
## `{"id":"<string>"}`. Returns null while nothing usable has arrived yet, so
## the caller can keep waiting up to its own deadline; a stray non-JSON or
## binary packet is skipped rather than treated as a failure, since a client
## that only ever sends binary frames (an old cached page) should still bind.
func _read_client_id(peer: WebSocketPeer) -> Variant:
	while peer.get_available_packet_count() > 0:
		var pkt: PackedByteArray = peer.get_packet()
		if not peer.was_string_packet():
			continue
		var parsed: Variant = _parse_json(pkt.get_string_from_utf8())
		if parsed is Dictionary and typeof(parsed.get("id")) == TYPE_STRING:
			return (parsed["id"] as String).left(MAX_CLIENT_ID_LENGTH)
	return null

## `text` parsed as JSON, or null. Unlike `JSON.parse_string()` it prints
## nothing for malformed text (issue #164): a phone must not be able to fill
## the host's log with engine errors.
static func _parse_json(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data

## Bind a newly-identified controller (ADR-0007). An id that matches a claimed
## slot takes that exact slot back -- this is the whole reconnect path. If the
## slot's old socket is still open (the phone dropped and came back before the
## old one timed out, or the same page is open in a second tab), the old socket
## is closed with REPLACED_REASON and the new one takes over (issue #164);
## otherwise the phone would be handed a second, ghost slot. With no match the
## lowest unclaimed slot is claimed fresh under this id -- one the host makes
## up if the client sent none (issue #164), so it can still be told apart and
## banned. Refuses the connection once every slot is claimed.
func _bind_with_id(peer: WebSocketPeer, id: String) -> void:
	if id.is_empty():
		_last_generated_id += 1
		id = "host-assigned-%d-%d" % [_last_generated_id, randi()]
	if _kicked_ids.has(id):
		peer.close(4001, KICKED_REASON)
		if _log_input:
			print("controller refused: kicked by the host")
		return
	for slot in _slot_peers.size():
		if _slot_claimed[slot] != 1 or _slot_virtual[slot] == 1 or _slot_client_id[slot] != id:
			continue
		var old: WebSocketPeer = _slot_peers[slot]
		if old != null:
			old.close(4002, REPLACED_REASON)
			_unbind(slot)
		_attach(slot, peer)
		_broadcast_looks(peer)
		if _log_input:
			print("slot %d %s" % [slot, "taken over by a new connection" if old != null else "reclaimed"])
		return
	for slot in _slot_peers.size():
		if _slot_claimed[slot] == 1:
			continue
		if _players[slot] == null:
			continue
		_claim_for_phone(_rejoin_slot(id, slot), id, peer)
		return
	# Issue #193: every slot is claimed, but in the lobby a Solo bot makes
	# way for a real phone.
	var bot_slot: int = _yielding_bot_slot()
	if bot_slot != -1:
		bot_director.remove_bot(bot_slot)
		if _log_input:
			print("slot %d: a Solo bot made way for a phone" % bot_slot)
		_claim_for_phone(bot_slot, id, peer)
		return
	peer.close(1000, "no free player slot")
	if _log_input:
		print("controller refused: no free player slot")

## Claim the free `slot` fresh for a phone with client id `id` and bind `peer`.
func _claim_for_phone(slot: int, id: String, peer: WebSocketPeer) -> void:
	_fresh_claim(slot, id, "")
	_attach(slot, peer)
	_broadcast_looks(peer)
	player_joined.emit(slot)
	if _log_input:
		print("slot %d claimed" % slot)

## The slot a phone with id `id` should claim, given `lowest` is the lowest
## free one (issue #193): the slot its recently released claim held, if that
## is still free, else `lowest`.
func _rejoin_slot(id: String, lowest: int) -> int:
	var left: Dictionary = _recent_leaver(id)
	var slot: int = int(left.get("slot", -1))
	if slot >= 0 and slot < _slot_claimed.size() and _slot_claimed[slot] == 0 and _players[slot] != null:
		return slot
	return lowest

## What `id`'s released claim held, if it was released under
## REJOIN_GRACE_MSEC ago; else empty (issue #193).
func _recent_leaver(id: String) -> Dictionary:
	if id.is_empty() or not _recent_leavers.has(id):
		return {}
	var left: Dictionary = _recent_leavers[id]
	if Time.get_ticks_msec() - int(left["msec"]) > REJOIN_GRACE_MSEC:
		_recent_leavers.erase(id)
		return {}
	return left

## The slot of the Solo bot that makes way when a phone finds every slot
## claimed (issue #193): the most recent Solo bot, and only in the lobby
## (SOLO_PHASES) -- mid-match a bot's body is in the round. -1 for none.
func _yielding_bot_slot() -> int:
	if bot_director == null or not bot_director.solo:
		return -1
	if not SOLO_PHASES.has(str(_lobby_state.get("phase", "lobby"))):
		return -1
	var bots: Array[int] = virtual_slots()
	return bots[bots.size() - 1] if not bots.is_empty() else -1

## Open a roster entry on `slot` (ADR-0007) for a phone with client id `id`
## or, with `virtual`, for a bot: at the back of the join order, under a new
## claim serial, bare-headed in its automatic colour. The one place a claim
## starts (issue #164). Issue #193: a phone whose claim was released under
## REJOIN_GRACE_MSEC ago goes back to its old place in the join order instead,
## with its colour (if still free), hat and nickname.
func _fresh_claim(slot: int, id: String, nickname: String, virtual: bool = false) -> void:
	var left: Dictionary = {} if virtual else _recent_leaver(id)
	_recent_leavers.erase(id)
	_slot_claimed[slot] = 1
	_slot_virtual[slot] = 1 if virtual else 0
	_slot_client_id[slot] = id
	_slot_name[slot] = nickname
	_slot_ready[slot] = 0
	_last_claim_serial += 1
	_slot_claim_serial[slot] = _last_claim_serial
	if left.is_empty():
		_last_join_rank += 1
		_slot_join_rank[slot] = _last_join_rank
	else:
		_slot_join_rank[slot] = int(left["rank"])
	_join_order.erase(slot)
	var at: int = _join_order.size()
	while at > 0 and _slot_join_rank[_join_order[at - 1]] > _slot_join_rank[slot]:
		at -= 1
	_join_order.insert(at, slot)
	_claim_look(slot)
	if not left.is_empty():
		if nickname.is_empty():
			_slot_name[slot] = str(left["name"])
		_slot_hat[slot] = str(left["hat"])
		if _color_free(int(left["color"]), slot):
			_slot_color[slot] = int(left["color"])
		_apply_look(slot)

## Close `slot`'s roster entry: everything `_fresh_claim()` set goes, and its
## colour is free again. The one place a claim ends (issue #164) -- an expired
## claim, a kick and a departing bot all come here. The caller unbinds any
## socket first and broadcasts the looks after.
func _release_claim(slot: int) -> void:
	_remember_leaver(slot)
	_slot_claimed[slot] = 0
	_slot_virtual[slot] = 0
	_slot_client_id[slot] = ""
	_slot_name[slot] = ""
	_slot_ready[slot] = 0
	_slot_claim_serial[slot] = 0
	_join_order.erase(slot)
	_release_look(slot)

## Note what `slot`'s claim holds before it is released, so its phone gets
## it back if it returns within REJOIN_GRACE_MSEC (issue #193). Not for a bot,
## a slot with no id, or a kicked phone, which is never coming back.
func _remember_leaver(slot: int) -> void:
	var id: String = _slot_client_id[slot]
	if _slot_virtual[slot] == 1 or id.is_empty() or _kicked_ids.has(id):
		return
	var now: int = Time.get_ticks_msec()
	for old: String in _recent_leavers.keys():
		if now - int(_recent_leavers[old]["msec"]) > REJOIN_GRACE_MSEC:
			_recent_leavers.erase(old)
	if _recent_leavers.size() >= MAX_RECENT_LEAVERS and not _recent_leavers.has(id):
		var oldest: String = ""
		for old: String in _recent_leavers.keys():
			if oldest.is_empty() or int(_recent_leavers[old]["msec"]) < int(_recent_leavers[oldest]["msec"]):
				oldest = old
		_recent_leavers.erase(oldest)
	_recent_leavers[id] = {
		"rank": _slot_join_rank[slot], "slot": slot, "color": _slot_color[slot],
		"hat": _slot_hat[slot], "name": _slot_name[slot], "msec": now}

## Bind `peer` to `slot`: the slot frame, the current lobby state, and the full
## looks frame -- hat drawings included, which only a newly bound phone needs
## (issue #164). The caller tells every other phone with `_broadcast_looks(peer)`.
func _attach(slot: int, peer: WebSocketPeer) -> void:
	_slot_peers[slot] = peer
	_slot_last_packet_msec[slot] = Time.get_ticks_msec()
	_last_weapon[slot] = Vector2(NAN, NAN)
	_steady_frames[slot] = 0
	_bound_once[slot] = 1
	_slot_text_count[slot] = 0
	_slot_text_window_msec[slot] = 0
	_smoothers[slot].reset()
	_players[slot].bind_controller()
	peer.send_text(JSON.stringify({"slot": slot, "id": _slot_client_id[slot]}))
	if not _lobby_state.is_empty():
		peer.send_text(_lobby_text())
	peer.send_text(JSON.stringify(looks_message()))

## Free the slot and park its player: zeroing the vector first means the weapon
## eases back to rest over several frames instead of holding the controller's
## last angle forever (or snapping to whatever a debug source would say).
##
## Does not touch `_slot_claimed` / `_slot_client_id`: an ordinary disconnect
## keeps the roster entry open for the rest of the round (ADR-0007). Only
## `_release_claim()` clears those.
func _unbind(slot: int) -> void:
	_slot_peers[slot] = null
	_smoothers[slot].reset()
	_slot_ready[slot] = 0
	_last_weapon[slot] = Vector2(NAN, NAN)
	_steady_frames[slot] = 0
	if _players[slot] != null:
		_players[slot].set_input_vector(Vector2.ZERO)
		_players[slot].unbind_controller()
	if _log_input:
		print("slot %d unbound" % slot)

## The slots with an open roster entry right now, in slot order -- what a
## round loop treats as "in the roster" regardless of whether each one's
## controller is currently connected.
func claimed_slots() -> Array[int]:
	var result: Array[int] = []
	for slot in _slot_claimed.size():
		if _slot_claimed[slot] == 1:
			result.append(slot)
	return result

## Buzz the phone bound to `slot` (issue #34, ADR-0013): one
## `{"t":"buzz","kind":<kind>}` text frame, which the page turns into a
## vibration and a flash in the slot's colour. `kind` is one of `BUZZ_KINDS`.
## A no-op when the slot has no connected controller -- a buzz is feedback,
## not state, so one missed while a phone is away is not replayed.
func send_buzz(slot: int, kind: String) -> void:
	if not slot_has_controller(slot):
		return
	var peer: WebSocketPeer = _slot_peers[slot]
	if peer == null or peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	peer.send_text(JSON.stringify({"t": "buzz", "kind": kind}))
	if _log_input:
		print("slot %d buzz %s" % [slot, kind])

## Whether `slot` has a connected controller right now. A claimed slot can be
## without one mid-round (ADR-0007); the round loop uses this to spot a round
## that no one still in it can finish.
func slot_has_controller(slot: int) -> bool:
	return slot >= 0 and slot < _slot_peers.size() and (_slot_peers[slot] != null or _slot_virtual[slot] == 1)

## Drop every claimed slot that has no live controller right now. Called by
## the round loop before every attempt to start a round: a roster entry
## survives a disconnect only until the end of the round it disconnected in
## (ADR-0007) -- an entry not reclaimed by then does not carry into the next
## round, and one that dropped while no round was running is not held at all.
func expire_disconnected_claims() -> void:
	var released: bool = false
	for slot in _slot_claimed.size():
		if _slot_claimed[slot] == 1 and not slot_has_controller(slot):
			_release_claim(slot)
			released = true
	if released:
		_broadcast_looks()

## Latest value wins: drain everything queued this frame and keep only the last
## well-formed packet, so a burst never replays stale input. The packet sets
## the slot's smoothing target; `_apply_smoothed_input` applies it (#113).
func _drain(slot: int, peer: WebSocketPeer) -> void:
	var latest: PackedByteArray = PackedByteArray()
	var got: bool = false
	while peer.get_available_packet_count() > 0:
		var pkt: PackedByteArray = peer.get_packet()
		if peer.was_string_packet():
			# Issue #193: an oversized frame is never parsed; it still
			# counts against the slot's budget.
			if _take_text_budget(slot) and pkt.size() <= MAX_TEXT_FRAME_BYTES:
				_handle_text(slot, pkt.get_string_from_utf8())
			continue
		if pkt.size() != PACKET_SIZE:
			continue
		latest = pkt
		got = true
	if not got:
		return
	_slot_last_packet_msec[slot] = Time.get_ticks_msec()
	var v: Vector2 = Vector2(latest.decode_float(0), latest.decode_float(4))
	_smoothers[slot].push(v)
	if _log_input:
		print("slot=%d v=(%.4f, %.4f)" % [slot, v.x, v.y])

## Report the weapon the host actually commanded, reading only Player's
## public `weapon_angle` / `weapon_length`, so direction/reach/release can be
## observed the way the input pipeline produced them rather than by
## re-deriving them from the packet. These are the setpoints, not the driven
## body's live geometry: a physical weapon under contact jitters, and a
## steadiness log has to be able to say "nothing changed".
##
## Changes print as they happen; an unchanged weapon prints a positive "steady"
## line every `STEADY_LOG_FRAMES` frames, so "it held at rest" is provable from
## a line that exists rather than from silence.
func _log_weapon(slot: int) -> void:
	if not _log_input:
		return
	var player: Variant = _players[slot]
	if player == null:
		return
	var current: Vector2 = Vector2(player.weapon_angle, player.weapon_length)
	var previous: Vector2 = _last_weapon[slot]
	if is_finite(previous.x) and absf(current.x - previous.x) < ANGLE_LOG_EPSILON and absf(current.y - previous.y) < LENGTH_LOG_EPSILON:
		_steady_frames[slot] += 1
		if _steady_frames[slot] % STEADY_LOG_FRAMES == 0:
			print("slot=%d weapon steady angle=%.4f len=%.1f frames=%d" % [slot, previous.x, previous.y, _steady_frames[slot]])
		return
	_last_weapon[slot] = current
	_steady_frames[slot] = 0
	print("slot=%d weapon angle=%.4f len=%.1f" % [slot, current.x, current.y])

# --- Lobby (issue #120) ------------------------------------------------------
#
# Transport only: this node records what phones asked for (ready, the host's
# "first to N") and relays RoundManager's lobby state back to them.
# RoundManager decides what any of it means.

## Whether `slot` may have one more text frame acted on this second (issue
## #164). A phone flooding the host -- malformed or not -- is cut off at
## TEXT_FRAMES_PER_SEC until the next window.
func _take_text_budget(slot: int) -> bool:
	var now: int = Time.get_ticks_msec()
	if now - _slot_text_window_msec[slot] >= 1000:
		_slot_text_window_msec[slot] = now
		_slot_text_count[slot] = 0
	_slot_text_count[slot] += 1
	if _slot_text_count[slot] == TEXT_FRAMES_PER_SEC + 1 and _log_input:
		print("slot %d text frames over %d/s: dropping the rest this second" % [slot, TEXT_FRAMES_PER_SEC])
	return _slot_text_count[slot] <= TEXT_FRAMES_PER_SEC

## A phone's text frame (see the header for the list): Ready, nickname, look,
## Solo practice, the host's match length and host-menu commands. A frame that
## is not a JSON object, has an unknown "t", or carries a value of the wrong
## type (a "v" that is not a bool for Ready and Solo, say) is ignored, as is a
## host-only frame from a phone that is not the host.
func _handle_text(slot: int, text: String) -> void:
	var msg: Variant = _parse_json(text)
	if not msg is Dictionary:
		return
	match str(msg.get("t", "")):
		"ready":
			var on: Variant = msg.get("v")
			if not on is bool:
				return
			_slot_ready[slot] = 1 if on else 0
			if _log_input:
				print("slot %d ready %s" % [slot, _slot_ready[slot] == 1])
		"name":
			var nickname: Variant = msg.get("v")
			if not nickname is String:
				return
			_slot_name[slot] = clean_name(nickname)
			if _log_input:
				print("slot %d name '%s'" % [slot, _slot_name[slot]])
		"target":
			var n: Variant = msg.get("n")
			if slot == host_slot() and _is_number(n):
				_match_target = clampi(int(n), MIN_MATCH_TARGET, MAX_MATCH_TARGET)
				if _log_input:
					print("slot %d set match target %d" % [slot, _match_target])
		"host":
			_handle_host_command(slot, msg)
		"hat":
			var hat: Variant = msg.get("v")
			if hat is String:
				set_slot_hat(slot, hat)
		"color":
			var c: Variant = msg.get("v")
			if _is_number(c):
				request_color(slot, int(c))
		"solo":
			var on: Variant = msg.get("v")
			if slot == host_slot() and on is bool and SOLO_PHASES.has(str(_lobby_state.get("phase", "lobby"))):
				solo_requested.emit(on)

## A finite JSON number (JSON gives floats; a scenario may send ints).
static func _is_number(v: Variant) -> bool:
	return v is int or (v is float and is_finite(v))

## A host-menu request (issue #149). Anything from a phone that is not the host
## right now is ignored, as is an unknown command or a kick aimed at the host
## itself or at a slot nobody holds. Issue #164: a request carrying a "match"
## serial that is not the current match's, or a kick carrying a "claim" serial
## that is not the target slot's current claim, is stale -- a confirm that sat
## open while things changed -- and is ignored too.
func _handle_host_command(slot: int, msg: Dictionary) -> void:
	var cmd: String = str(msg.get("cmd", ""))
	if slot != host_slot():
		if _log_input:
			print("slot %d host command '%s' ignored: not the host" % [slot, cmd])
		return
	if msg.has("match") and (not _is_number(msg["match"]) or int(msg["match"]) != _match_serial):
		if _log_input:
			print("slot %d host command '%s' ignored: stale match %s (now %d)" % [slot, cmd, msg["match"], _match_serial])
		return
	if HOST_COMMANDS.has(cmd):
		if _log_input:
			print("slot %d host command %s" % [slot, cmd])
		host_command.emit(cmd, -1)
	elif cmd == "kick":
		var target: Variant = msg.get("slot")
		if not _is_number(target):
			return
		var t: int = int(target)
		if msg.has("claim") and (not _is_number(msg["claim"]) or int(msg["claim"]) != claim_serial(t)):
			if _log_input:
				print("slot %d kick of slot %d ignored: stale claim %s (now %d)" % [slot, t, msg["claim"], claim_serial(t)])
			return
		if kick(t):
			host_command.emit("kick", t)

## `slot`'s current claim serial (issue #164), or 0 when it is unclaimed.
func claim_serial(slot: int) -> int:
	return _slot_claim_serial[slot] if slot >= 0 and slot < _slot_claim_serial.size() else 0

## The current match serial (issue #164): bumped each time a match starts.
func match_serial() -> int:
	return _match_serial

## Remove `slot` from the roster at once (issue #149): its phone is told why
## and hung up on, its claim is dropped -- not held to the end of the round as
## an ordinary disconnect is (ADR-0007) -- and its id is refused from now on.
## False, doing nothing, for the host's own slot or an unclaimed one.
func kick(slot: int) -> bool:
	if slot < 0 or slot >= _slot_claimed.size() or _slot_claimed[slot] != 1 or slot == host_slot():
		return false
	if is_virtual(slot):
		# A bot (issue #152): its director sends it away.
		bot_director.remove_bot(slot)
		return true
	var peer: WebSocketPeer = _slot_peers[slot]
	if peer != null:
		peer.close(4001, KICKED_REASON)
		_unbind(slot)
	if not _slot_client_id[slot].is_empty() and not _kicked_ids.has(_slot_client_id[slot]):
		_kicked_ids.append(_slot_client_id[slot])
	_release_claim(slot)
	_broadcast_looks()
	if _log_input:
		print("slot %d kicked by the host" % slot)
	return true

## Whether `slot`'s phone has pressed Ready (and not un-readied since).
func slot_ready(slot: int) -> bool:
	return slot >= 0 and slot < _slot_ready.size() and (_slot_ready[slot] == 1 or _slot_virtual[slot] == 1)

## Mark `slot` ready or not, as its phone's Ready button would: Solo
## practice readies the host (issue #152).
func set_slot_ready(slot: int, on: bool) -> void:
	if slot >= 0 and slot < _slot_ready.size():
		_slot_ready[slot] = 1 if on else 0

## Every phone back to not-ready: at the start of a match, so Rematch has to
## be pressed afresh.
func clear_ready() -> void:
	for slot in _slot_ready.size():
		_slot_ready[slot] = 0

## The host phone's slot: the earliest-joined claimed slot with a controller
## connected right now, or -1 with no phones at all.
func host_slot() -> int:
	for slot: int in _join_order:
		if _slot_peers[slot] != null:
			return slot
	return -1

## The match length the host phone chose ("first to N"), 5 by default.
func match_target() -> int:
	return _match_target

## Send the lobby state to every connected phone, and keep it for any phone
## that binds later. Issue #164: entering a match phase from any other phase
## starts a new match serial.
func set_lobby_state(state: Dictionary) -> void:
	var was: String = str(_lobby_state.get("phase", ""))
	_lobby_state = state.duplicate(true)
	_lobby_state["t"] = "lobby"
	if MATCH_PHASES.has(str(_lobby_state.get("phase", ""))) and not MATCH_PHASES.has(was):
		_match_serial += 1
	var text: String = _lobby_text()
	for peer: WebSocketPeer in _slot_peers:
		if peer != null and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			peer.send_text(text)

## The stored lobby state as sent to a phone, marked up as it stands right
## now: each bot's entry flagged "bot" (issue #152), each entry's "claim"
## serial and the "match" serial (issue #164), which the host menu echoes
## back so the host can tell a stale kick or End match from a current one.
func _lobby_text() -> String:
	_lobby_state["match"] = _match_serial
	for entry: Variant in _lobby_state.get("players", []):
		if entry is Dictionary:
			var slot: int = int(entry.get("slot", -1))
			if is_virtual(slot):
				entry["bot"] = true
			else:
				entry.erase("bot")
			entry["claim"] = claim_serial(slot)
	return JSON.stringify(_lobby_state)

## A slot's nickname (issue #121), or "" when its phone has not sent one.
func slot_name(slot: int) -> String:
	return _slot_name[slot] if slot >= 0 and slot < _slot_name.size() else ""

## Code points a nickname may use (issue #164), as inclusive [first, last]
## pairs: printable text in every script, punctuation, symbols and emoji. Left
## out: control and format characters (zero-width ones, bidi embeddings,
## overrides and isolates, the line and paragraph separators), every space but
## the plain one, invisible fillers, private use, variation selectors and tags.
const NAME_CHAR_RANGES: PackedInt32Array = [
	0x20, 0x7E, 0xA1, 0xAC, 0xAE, 0x2FF, 0x370, 0x5FF, 0x606, 0x61B,
	0x61D, 0x6DC, 0x6DE, 0x70E, 0x710, 0x8E1, 0x8E3, 0x115E, 0x1161, 0x167F,
	0x1681, 0x180A, 0x1810, 0x1FFF, 0x2010, 0x2027, 0x2030, 0x205E, 0x2070, 0x2FFF,
	0x3001, 0x3163, 0x3165, 0xD7FF, 0xF900, 0xFDFF, 0xFE10, 0xFEFE, 0xFF00, 0xFF9F,
	0xFFA1, 0xFFEF, 0x10000, 0x1BC9F, 0x1BCA4, 0x1D172, 0x1D17B, 0x2FFFF,
]
## The combining marks a nickname may stack on one character, at most
## MAX_STACKED_MARKS deep (issue #164): the generic diacritic blocks, which is
## what a tower of accents is built from.
const NAME_MARK_RANGES: PackedInt32Array = [
	0x300, 0x36F, 0x1AB0, 0x1AFF, 0x1DC0, 0x1DFF, 0x20D0, 0x20FF, 0xFE20, 0xFE2F,
]

static func _in_ranges(c: int, ranges: PackedInt32Array) -> bool:
	for i in range(0, ranges.size(), 2):
		if c >= ranges[i] and c <= ranges[i + 1]:
			return true
	return false

## A nickname as the shared screen may show it: only whitelisted characters
## (NAME_CHAR_RANGES), at most MAX_STACKED_MARKS combining marks on any one,
## edges trimmed, at most MAX_NAME_LENGTH characters. Only the first
## MAX_RAW_NAME_LENGTH characters of `text` are looked at (issue #193).
static func clean_name(text: String) -> String:
	# Issue #193: cut first, so the loop is bounded however long `text` is.
	var raw: String = text.left(MAX_RAW_NAME_LENGTH)
	var kept: String = ""
	var marks: int = 0
	for i in raw.length():
		var c: int = raw.unicode_at(i)
		if _in_ranges(c, NAME_MARK_RANGES):
			if kept.is_empty() or marks >= MAX_STACKED_MARKS:
				continue
			marks += 1
		elif _in_ranges(c, NAME_CHAR_RANGES):
			marks = 0
		else:
			continue
		kept += raw[i]
	return kept.strip_edges().left(MAX_NAME_LENGTH).strip_edges()

# --- Looks: hat and colour (issue #151) ----------------------------------------
#
# Each phone picks a hat and a colour after its nickname. Colours are first
# come, first served: a colour another claimed slot holds is refused (the
# phones show it as taken), and a slot's colour is released only when its
# claim goes -- an expired claim or a kick -- not by an ordinary disconnect,
# which keeps the roster entry and everything about it (ADR-0007). A slot that
# has not picked one wears today's automatic colour: its own scene colour, or,
# if a player who picked first already holds that, the first colour free.
# Applied straight onto the slot's Player, as `bind_controller()` is: cosmetic
# state that RoundManager never has to decide anything about.

## A fresh claim of `slot`: bare-headed, in its automatic colour.
func _claim_look(slot: int) -> void:
	_slot_hat[slot] = HatScript.NONE
	_slot_color[slot] = -1
	var colour: int = slot if _color_free(slot, slot) else -1
	if colour == -1:
		for i in _palette.size():
			if _color_free(i, slot):
				colour = i
				break
	_slot_color[slot] = colour
	_apply_look(slot)

## `slot`'s claim is gone: its colour is free again, and its player goes back
## to its own scene colour, bare-headed, for whoever claims the slot next.
func _release_look(slot: int) -> void:
	_slot_hat[slot] = HatScript.NONE
	_slot_color[slot] = -1
	var player: Variant = _players[slot]
	if player != null and player.has_method("set_identity_color"):
		player.set_hat(HatScript.NONE)
		player.set_identity_color(_palette[slot])

## Whether colour `index` could be worn by `slot`: a real colour that no other
## claimed slot holds.
func _color_free(index: int, slot: int) -> bool:
	if index < 0 or index >= _palette.size() or _players[index] == null:
		return false
	for other in _slot_color.size():
		if other != slot and _slot_claimed[other] == 1 and _slot_color[other] == index:
			return false
	return true

func _apply_look(slot: int) -> void:
	var player: Variant = _players[slot]
	if player == null or not player.has_method("set_identity_color"):
		return
	player.set_hat(_slot_hat[slot])
	if _slot_color[slot] >= 0:
		player.set_identity_color(_palette[_slot_color[slot]])

## `slot` puts on hat `id`, one of `Hat.gd`'s IDS ("none" for bare). An
## unknown id, or an unclaimed slot, is ignored. False when nothing was set.
func set_slot_hat(slot: int, id: String) -> bool:
	if slot < 0 or slot >= _slot_hat.size() or _slot_claimed[slot] != 1 or not HatScript.IDS.has(id):
		return false
	_slot_hat[slot] = id
	_apply_look(slot)
	if _log_input:
		print("slot %d hat %s" % [slot, id])
	_broadcast_looks()
	return true

## `slot` asks for colour `index`: granted if no other claimed slot holds it.
## Every phone is told the outcome either way, so the asker sees a refusal.
func request_color(slot: int, index: int) -> bool:
	var granted: bool = slot >= 0 and slot < _slot_color.size() and _slot_claimed[slot] == 1 and _color_free(index, slot)
	if granted:
		_slot_color[slot] = index
		_apply_look(slot)
	if _log_input:
		print("slot %d color %d %s" % [slot, index, "granted" if granted else "refused"])
	_broadcast_looks()
	return granted

## The hat `slot` wears ("none" when bare or unclaimed).
func slot_hat(slot: int) -> String:
	return _slot_hat[slot] if slot >= 0 and slot < _slot_hat.size() else HatScript.NONE

## The colour `slot` holds, as an index into the palette; -1 when unclaimed.
func slot_color(slot: int) -> int:
	return _slot_color[slot] if slot >= 0 and slot < _slot_color.size() else -1

## `Hat.gd`'s drawings as the phones get them, built once.
var _hat_art: Dictionary = {}

## What a phone is told about looks when it binds: the palette ("#rrggbb", or
## "" for a colour no player can wear), each hat's id, name and drawing (so
## the picker's previews are exactly what the shared screen draws), and each
## claimed slot's colour and hat -- a colour listed there is taken. None of it
## but the last part ever changes, so after this a phone gets only
## `looks_update_message()` (issue #164): the drawings are a few kilobytes.
func looks_message() -> Dictionary:
	var palette: Array = []
	for i in _palette.size():
		palette.append("#" + _palette[i].to_html(false) if _players[i] != null else "")
	var hats: Array = []
	for id: String in HatScript.IDS:
		hats.append({"id": id, "label": HatScript.LABELS.get(id, id)})
	if _hat_art.is_empty():
		_hat_art = HatScript.art_for_phone()
	var msg: Dictionary = looks_update_message()
	msg["palette"] = palette
	msg["hats"] = hats
	msg["art"] = _hat_art
	return msg

## What every phone is told when someone's looks change (issue #164): just
## each claimed slot's colour and hat.
func looks_update_message() -> Dictionary:
	var looks: Array = []
	for slot in _slot_claimed.size():
		if _slot_claimed[slot] == 1:
			looks.append({"slot": slot, "color": _slot_color[slot], "hat": _slot_hat[slot]})
	return {"t": "looks", "looks": looks}

## Tell every connected phone but `except` (one that has just been sent the
## full looks frame on binding) who wears what.
func _broadcast_looks(except: WebSocketPeer = null) -> void:
	var text: String = JSON.stringify(looks_update_message())
	for peer: WebSocketPeer in _slot_peers:
		if peer != null and peer != except and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			peer.send_text(text)

# --- Virtual controllers (issue #152) ----------------------------------------

## Claim the lowest free slot for a bot, named `bot_name`, and return it; -1
## when every slot is taken. Like a phone's fresh claim (`_bind_with_id`), it
## joins the roster at the back and emits `player_joined`.
func add_virtual_controller(bot_name: String) -> int:
	for slot in _slot_peers.size():
		if _slot_claimed[slot] == 1 or _players[slot] == null:
			continue
		_fresh_claim(slot, "", clean_name(bot_name), true)
		_smoothers[slot].reset()
		_players[slot].bind_controller()
		_broadcast_looks()
		player_joined.emit(slot)
		if _log_input:
			print("slot %d claimed by a bot" % slot)
		return slot
	return -1

## Give a bot's slot back: the roster entry goes at once, as a phone's
## expired claim does, and the player is parked.
func remove_virtual_controller(slot: int) -> void:
	if not is_virtual(slot):
		return
	_smoothers[slot].reset()
	if _players[slot] != null:
		_players[slot].set_input_vector(Vector2.ZERO)
		_players[slot].unbind_controller()
	_release_claim(slot)
	_broadcast_looks()
	if _log_input:
		print("slot %d bot removed" % slot)

## A bot's packet: `v` becomes the slot's smoothing target, as a phone's
## decoded packet does in `_drain()`.
func push_virtual_input(slot: int, v: Vector2) -> void:
	if is_virtual(slot):
		_smoothers[slot].push(v)

func is_virtual(slot: int) -> bool:
	return slot >= 0 and slot < _slot_virtual.size() and _slot_virtual[slot] == 1

## The bots' slots, in slot order.
func virtual_slots() -> Array[int]:
	var result: Array[int] = []
	for slot in _slot_virtual.size():
		if _slot_virtual[slot] == 1:
			result.append(slot)
	return result

## The player node in `slot`, or null.
func player_in_slot(slot: int) -> Node:
	return _players[slot] if slot >= 0 and slot < _players.size() else null
