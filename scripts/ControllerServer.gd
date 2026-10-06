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
## Teams mode (issue #236, ADR-0018): from the host phone only,
## `{"t":"gamemode","v":<GameModes id>}` (issue #352) picks the game mode the
## same way, and is refused for Hot Potato while Teams is chosen. `{"t":"mode","v":"ffa"|"teams"}` picks the next match's mode, heeded only
## outside a match (MODE_PHASES); and from any phone, `{"t":"team","v":0|1|-1}`
## picks Red, Blue or "auto", heeded only in the lobby or countdown
## (TEAM_PICK_PHASES). Both are additions: a page that never sends them plays
## free-for-all exactly as before, and the lobby state's "teams" and per-player
## "team" and "pick" fields are sent only while Teams is chosen.
## Online play (issue #239, ADR-0019): from the host phone only, a local one,
## `{"t":"host","cmd":"online","v":<bool>}` opens or closes the relay room
## (a remote seat's request is ignored), heeded only in the lobby. The lobby
## state then carries "online" (the link status: "off", "connecting", "online"
## or "unreachable"), "room" (the relay's room code, "" when not online) and
## "pc_seat" (whether the host PC plays from its own mouse).
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
## `host_slot()` changed, to `slot` (-1 with no phone connected). Checked every
## frame, paused or not, so a paused game still tells the phones who holds the
## host menu when the host's phone drops (issue #165).
signal host_changed(slot: int)

## The host phone asked for `cmd` (issue #149): "pause", "resume" or "end",
## with `slot` -1; or "kick", emitted after `slot` has been removed from the
## roster. Only ever emitted for a request from `host_slot()`, except "kick"
## for a dropped remote seat whose hold lapsed mid-match (issue #459), which
## leaves the roster the same way. RoundManager decides what each means.
signal host_command(cmd: String, slot: int)

## A phone tapped "Steal a life" (Stock in Teams, #354). RoundManager forwards
## it to the mode, which decides whether it is allowed.
signal steal_requested(slot: int)

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
const GameModesScript := preload("res://scripts/GameModes.gd")
const HostSettingsScript := preload("res://scripts/HostSettings.gd")
## The eye styles a phone may pick (issue #297), by path (CLAUDE.md).
const PlayerFaceScript := preload("res://scripts/PlayerFace.gd")
const QrEncoderScript := preload("res://scripts/QrEncoder.gd")

const PAGE_PATH: String = "res://controller/index.html"
## The only other files the HTTP server hands out: the controller page's fonts,
## by exact URL path (an allowlist, so no path can reach anything else).
const CONTROLLER_FONTS: Dictionary = {
	"/fonts/LilitaOne-Latin.woff2": "res://controller/fonts/LilitaOne-Latin.woff2",
	"/fonts/Nunito-Latin.woff2": "res://controller/fonts/Nunito-Latin.woff2",
}
const WS_PORT_TOKEN: String = "__WS_PORT__"
const MAX_HEADER_BYTES: int = 8192
const PACKET_SIZE: int = 8
## Issue #463, ADR-0022: a client that is holding "released" (a PC client after
## a Space tap, say) appends one byte, nonzero, to the vector packet. A packet
## without it -- every phone, every older client -- means not released.
const RELEASE_PACKET_SIZE: int = 9
## Issue #481: a newer client appends a second byte, a wrapping count of its
## action presses (Space, L3/R3). A count that moved since the last packet is a
## press, so one is not lost between packets. Older packets carry no count.
const ACTION_PACKET_SIZE: int = 10
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
## Issue #579: a remote seat (relay peer) goes quiet for longer than a phone before
## it is dropped -- a window drag or a hitch on a PC stalls its input past 2 s. The
## dropped seat is held (#459) and its client rejoins by itself.
@export var remote_timeout_sec: float = 10.0
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
var _slot_peers: Array = [] # WebSocketPeer (a phone), RemoteSeat (a relay peer, #239) or LocalSeat (the host PC, #239)
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
## Each claimed slot's eye style (issue #297), a `PlayerFace.gd` EYE_IDS entry.
var _slot_eyes: PackedStringArray = PackedStringArray()
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
const RelayLinkScript: GDScript = preload("res://scripts/RelayLink.gd")
const HostMouseScript: GDScript = preload("res://scripts/HostMouse.gd")
const DemoBuildScript := preload("res://scripts/DemoBuild.gd")

## Issue #239: the remote-seat protocol version. A remote client's hello must
## carry `"proto": PROTOCOL_VERSION`; phones are exempt (the page comes from
## this host, so it always matches).
const PROTOCOL_VERSION: int = 1

## One remote client's seat over the relay (#239): quacks like the
## WebSocketPeer a phone slot holds, so the claim, input and text paths are
## shared. Frames in arrive through `push()`; frames out go via the link.
class RemoteSeat extends RefCounted:
	const MAX_QUEUED: int = 64
	var peer: int = 0
	var link: Node = null
	var open: bool = true
	var deadline_msec: int = 0
	var _inbox: Array = [] # [is_text, PackedByteArray]
	## Issue #446: the last measured round trip in ms (-1 until a pong
	## arrives), the ping in flight and when it left.
	var rtt_msec: int = -1
	var ping_n: int = 0
	var ping_sent_msec: int = 0
	var ping_sent: Dictionary = {} # ping n -> msec it left
	var _last_was_text: bool = false

	func push(kind: int, payload: PackedByteArray) -> void:
		if open and _inbox.size() < MAX_QUEUED:
			_inbox.append([kind == RelayLinkScript.KIND_TEXT, payload])

	func poll() -> void:
		pass

	func get_ready_state() -> int:
		return WebSocketPeer.STATE_OPEN if open else WebSocketPeer.STATE_CLOSED

	func get_available_packet_count() -> int:
		return _inbox.size()

	func get_packet() -> PackedByteArray:
		var item: Array = _inbox.pop_front()
		_last_was_text = item[0]
		return item[1]

	func was_string_packet() -> bool:
		return _last_was_text

	func send_text(text: String) -> void:
		if open:
			link.send_text_to(peer, text)

	## Tells the client why, then drops the seat.
	func close(code: int = 1000, reason: String = "") -> void:
		if open:
			link.send_text_to(peer, JSON.stringify({"t": "closed", "code": code, "reason": reason}))
			link.drop_peer(peer) # free the relay slot too (#580)
			open = false

## The host PC's own seat (issue #239, "Play on this PC"): a transport with
## nothing on the wire. It is not a bot (`_slot_virtual` stays 0), so it is
## never yielded or replaced; everything else treats it as a connected phone.
class LocalSeat extends RefCounted:
	var open: bool = true
	var last_text: String = ""

	func poll() -> void:
		pass

	func get_ready_state() -> int:
		return WebSocketPeer.STATE_OPEN if open else WebSocketPeer.STATE_CLOSED

	func get_available_packet_count() -> int:
		return 0

	func get_packet() -> PackedByteArray:
		return PackedByteArray()

	func was_string_packet() -> bool:
		return false

	func send_text(text: String) -> void:
		last_text = text

	func close(_code: int = 1000, _reason: String = "") -> void:
		open = false

## A gamepad's seat (#261): a LocalSeat for one joypad device. Unlike the host
## PC's seat it is not auto-ready, and unplugging closes it (the claim is held).
class PadSeat extends LocalSeat:
	var device: int = -1

## The link to the relay that remote seats join through (#239).
var relay_link: Node = null
var _remote_seats: Dictionary = {} # relay peer id -> RemoteSeat
var _remote_awaiting: Array[RemoteSeat] = []
## The bots' owner, built in `_ready()` so no scene has to add it.
var bot_director: Node = null
## The Solo practice button is heeded only in these lobby phases (issue #165):
## mid-match, removing the bots would leave their bodies in the round.
const SOLO_PHASES: PackedStringArray = ["lobby", "countdown"]
## Where an Online late joiner may take a bot's seat in a full room (#445).
const BETWEEN_ROUNDS_PHASES: PackedStringArray = ["round_end", "victory"]
## Issue #236: the mode can change only between matches, never mid-match.
const MODE_PHASES: PackedStringArray = ["lobby", "countdown", "victory"]
## Issue #236: a phone picks its team in the lobby (or its countdown, which a
## new pick cancels, as an un-ready does).
const TEAM_PICK_PHASES: PackedStringArray = ["lobby", "countdown"]
## The number the Host panel's target row shows and steps (#544): the round
## target, or the mode's own lives / goals / captures.
func mode_target() -> int:
	var picked: int = GameModesScript.target_setting(_game_mode)
	return picked if picked >= 0 else _match_target

## Issue #236: whether the host phone chose Teams for the next match.
var _team_mode: bool = false
## Issue #352: the `GameModes` id the host phone chose ("" is Classic), kept in
## `HostSettings` so it survives a relaunch. Hot Potato never stands with Teams.
var _game_mode: String = ""
## Issue #236: each slot's team pick (0 red, 1 blue), -1 for "auto" -- the
## default, and what a fresh or released claim goes back to.
var _slot_team_pick: PackedInt32Array = PackedInt32Array()
var _last_host: int = -1
## The join URL and QR the lobby screen shows (#120). The QR is built
## in-process by QrEncoder.gd (#214); it is null only when no join URL was
## found.
var join_url: String = ""
var join_qr_texture: ImageTexture = null
## Issue #230. Whether the in-round join corner (the JoinLabel top left and
## the small JoinQrCode top right) is hidden: RoundManager hides it while the
## lobby, countdown or victory screen is up, which show their own big QR and
## URL, so the corner never bleeds through their backdrop. Issue #430: the
## join QR and room code show in the lobby only, so the corner starts hidden
## and RoundManager never shows it in a round either.
var _join_corner_hidden: bool = true
## The join label's text before the room code is added (issue #239).
var _join_label_base: String = ""

## Shows or hides the in-round join corner (issue #230). The QR shows only
## once it has a texture.
func set_join_corner_visible(on: bool) -> void:
	_join_corner_hidden = not on
	var label: Label = join_label()
	if label != null:
		label.visible = on
	var qr_rect: TextureRect = join_qr_rect()
	if qr_rect != null:
		qr_rect.visible = on and qr_rect.texture != null and not room_code_hidden()

## What the shared screen shows in place of the room code, URL and QR in
## streamer mode (#369).

## Streamer mode (#369): the host's saved "Hide room code" setting.
func room_code_hidden() -> bool:
	var sfx: Node = get_node_or_null("/root/Sfx")
	return sfx != null and bool(sfx.get("hide_room_code"))

## The in-round join label and QR, or null (issue #230).
func join_label() -> Label:
	return get_node_or_null(join_label_path) as Label

func join_qr_rect() -> TextureRect:
	return get_node_or_null(qr_texture_path) as TextureRect

func _ready() -> void:
	var saved: String = HostSettingsScript.shared().game_mode
	_game_mode = saved if GameModesScript.is_valid(saved) else ""
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
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
	_damage_sent.resize(_players.size())
	_damage_sent.fill(-1)
	_damage_sent_msec.resize(_players.size())
	_lives_sent.resize(_players.size())
	_lives_sent.fill("")
	_slot_claimed.resize(_players.size())
	_slot_client_id.resize(_players.size())
	_slot_ready.resize(_players.size())
	_slot_release_remote.resize(_players.size())
	_slot_release_toggle.resize(_players.size())
	_slot_release_held.resize(_players.size())
	_slot_press_seen.resize(_players.size())
	_slot_press_seen.fill(-1)
	_slot_action_down.resize(_players.size())
	_slot_action_down.fill(-1)
	_slot_bumper_down.resize(_players.size())
	_slot_bumper_down.fill(-1)
	_slot_was_alive.resize(_players.size())
	_slot_name.resize(_players.size())
	_slot_hat.resize(_players.size())
	_slot_eyes.resize(_players.size())
	_slot_color.resize(_players.size())
	for i in _players.size():
		_slot_hat[i] = HatScript.NONE
		_slot_eyes[i] = PlayerFaceScript.EYE_ROUND
		_slot_color[i] = -1
		_palette.append(_players[i].identity_color if _players[i] != null else Color(0, 0, 0, 0))
	_slot_virtual.resize(_players.size())
	_slot_claim_serial.resize(_players.size())
	_slot_text_window_msec.resize(_players.size())
	_slot_text_count.resize(_players.size())
	_slot_join_rank.resize(_players.size())
	_slot_team_pick.resize(_players.size())
	_slot_team_pick.fill(-1)
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
		label.text = tr("JOIN_ON_PHONE") + "\n" + (urls[0] if not urls.is_empty() else "http://127.0.0.1:%d/" % http_port)
		label.visible = not _join_corner_hidden

	var qr_rect: TextureRect = get_node_or_null(qr_texture_path) as TextureRect
	if qr_rect != null:
		if urls.is_empty():
			qr_rect.visible = false
		else:
			var qr_texture: ImageTexture = _generate_qr_texture(urls[0])
			join_qr_texture = qr_texture
			qr_rect.visible = qr_texture != null and not _join_corner_hidden
			if qr_texture != null:
				qr_rect.texture = qr_texture

	bot_director = BotDirectorScript.new()
	bot_director.name = "BotDirector"
	bot_director.server = self
	# Bots stop thinking while the host phone has the game paused (#165).
	bot_director.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(bot_director)

	_join_label_base = label.text if label != null else ""

func _process(delta: float) -> void:
	_sync_room_code_hidden()
	_process_http()
	_process_websocket()
	_process_remote()
	_ping_remote_seats()
	_check_host_pc_seat()
	_lapse_remote_holds()
	_stream_snapshots(delta)
	if host_slot() != _last_host:
		_last_host = host_slot()
		host_changed.emit(_last_host)
	_apply_smoothed_input(delta)

## Issue #463, ADR-0022: per slot, the "released" a controller reports besides
## its vector. `remote` is the flag byte of a remote client's packet; `toggle`
## is a host-side Space tap or stick click that flips it; `held` is a shoulder
## button held down. Any one of the three releases the slot's weapon.
var _slot_release_remote: PackedByteArray = PackedByteArray()
var _slot_release_toggle: PackedByteArray = PackedByteArray()
var _slot_release_held: PackedByteArray = PackedByteArray()
var _slot_was_alive: PackedByteArray = PackedByteArray()
## Last action-press count seen from each remote client; -1 = adopt the next.
var _slot_press_seen: PackedInt32Array = PackedInt32Array()

func _clear_release(slot: int) -> void:
	_slot_release_remote[slot] = 0
	_slot_release_toggle[slot] = 0
	_slot_release_held[slot] = 0
	_slot_press_seen[slot] = -1
	_slot_action_down[slot] = -1
	_slot_bumper_down[slot] = -1

## Issue #485: an action button (Space, L3/R3) is a tap when it comes up within
## TAP_MAX_SEC of going down, and a hold when it is still down after that. A
## tap fires on key-up; a hold counts as released while held and never fires.
## Game-clock msec the seat's action button went down, -1 when up.
const TAP_MAX_SEC: float = 0.25
var _slot_action_down: PackedInt64Array = PackedInt64Array()
## Same for a bumper, which is released while held from the moment it goes down.
var _slot_bumper_down: PackedInt64Array = PackedInt64Array()

func _is_tap(down_msec: int) -> bool:
	return float(GameClockScript459.now_msec() - down_msec) <= TAP_MAX_SEC * 1000.0

func _action_down(slot: int) -> void:
	if slot >= 0 and slot < _slot_action_down.size():
		_slot_action_down[slot] = GameClockScript459.now_msec()

## The button came up: a tap does the weapon's job, a hold already did its work.
func _action_up(slot: int) -> void:
	if slot < 0 or slot >= _slot_action_down.size() or _slot_action_down[slot] == -1:
		return
	var tap: bool = _is_tap(_slot_action_down[slot])
	_slot_action_down[slot] = -1
	if tap:
		_action_press(slot)

func _action_held_long(slot: int) -> bool:
	return slot >= 0 and slot < _slot_action_down.size() and _slot_action_down[slot] != -1 \
		and not _is_tap(_slot_action_down[slot])

## Whether `slot` is letting go right now (a test seam, like `pad_slot`).
func slot_released(slot: int) -> bool:
	return slot >= 0 and slot < _slot_release_toggle.size() \
		and (_slot_release_remote[slot] == 1 or _slot_release_toggle[slot] == 1 or _slot_release_held[slot] == 1 or _action_held_long(slot))

## Issue #481: an action press throws a held boomerang, else toggles release.
func _action_press(slot: int) -> void:
	if _try_throw(slot):
		return
	_toggle_release(slot)

## An action throw; a fresh throw starts held, not released: an earlier retract
## tap left the toggle on, which would pull the new hook home at once (#513).
func _try_throw(slot: int) -> bool:
	if slot < 0 or slot >= _players.size() or _players[slot] == null \
			or not _players[slot].try_action_throw():
		return false
	_slot_release_toggle[slot] = 0
	return true

func _toggle_release(slot: int) -> void:
	if slot >= 0 and slot < _slot_release_toggle.size():
		_slot_release_toggle[slot] = 1 - _slot_release_toggle[slot]

## A fresh round or a respawn starts not released (ADR-0022); a remote client
## holds its own toggle, so it is told to clear it.
func _reset_release_on_respawn(slot: int) -> void:
	var now_alive: int = 1 if _players[slot].alive else 0
	if now_alive == 1 and _slot_was_alive[slot] == 0:
		_slot_release_toggle[slot] = 0
		_slot_release_remote[slot] = 0
		if _slot_peers[slot] is RemoteSeat:
			_slot_peers[slot].send_text(JSON.stringify({"t": "release", "v": false}))
	_slot_was_alive[slot] = now_alive

## Step every bound slot's ease and hand the result to its player (issue #113).
func _apply_smoothed_input(delta: float) -> void:
	for slot in _slot_peers.size():
		if (_slot_peers[slot] == null and _slot_virtual[slot] == 0) or _players[slot] == null:
			continue
		_reset_release_on_respawn(slot)
		_players[slot].set_input_vector(_smoothers[slot].step(delta))
		_players[slot].set_input_released(slot_released(slot))

## Weapon diagnostics run on the physics tick because that is the rate the weapon is
## actually integrated at, which makes "held steady for N frames" meaningful.
##
## A slot is reported while a controller is bound, and afterwards until its weapon
## has settled back to rest -- otherwise the easing that follows a disconnect
## would happen entirely off the record.
func _physics_process(delta: float) -> void:
	_push_pad_sticks()
	_step_pad_pickers(delta)
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

## The join QR, encoded in-process by scripts/QrEncoder.gd (#214) and drawn
## 8 px a module with a 2-module quiet zone. It used to shell out to
## `qrencode`, so a host without it (any Windows PC, a fresh Mac) showed no QR.
## The encoder is checked module for module against a reference encoder
## (`qr_encoder_matches_reference_matrices`), since a subtly wrong matrix still
## looks like a QR code but does not scan. `null` only if the text is too long
## for the encoder (far beyond any `http://<ipv4>:<port>/`) -- the join
## label's text URL still covers that.
const QR_MODULE_PX: int = 8
const QR_QUIET_ZONE_MODULES: int = 2

func _generate_qr_texture(text: String) -> ImageTexture:
	var qr: Dictionary = QrEncoderScript.encode(text, QrEncoderScript.ECL_M)
	if qr.is_empty():
		push_warning("ControllerServer: join URL too long for a QR code: %s" % text)
		return null
	return ImageTexture.create_from_image(QrEncoderScript.to_image(qr, QR_MODULE_PX, QR_QUIET_ZONE_MODULES))

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

	if method == "GET" and CONTROLLER_FONTS.has(path):
		var font: FileAccess = FileAccess.open(CONTROLLER_FONTS[path], FileAccess.READ)
		if font != null:
			var bytes: PackedByteArray = font.get_buffer(font.get_length())
			font.close()
			_send_http(conn, 200, "OK", "font/woff2", bytes, "public, max-age=86400")
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

func _send_http(conn: HttpConn, code: int, reason: String, content_type: String, body: PackedByteArray, cache_control: String = "no-store") -> void:
	var header: String = "HTTP/1.1 %d %s\r\n" % [code, reason]
	header += "Content-Type: %s\r\n" % content_type
	header += "Content-Length: %d\r\n" % body.size()
	header += "Cache-Control: %s\r\n" % cache_control
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
		var peer: Variant = _slot_peers[slot]
		if peer == null:
			continue
		peer.poll()
		if peer is LocalSeat:
			# No socket to go silent: the host PC's seat never times out.
			_slot_last_packet_msec[slot] = now
		elif peer is RemoteSeat and relay_state() == RelayLinkScript.STATE_RECONNECTING:
			# The host's own link is down, not the player's: pause the clock (#249).
			_slot_last_packet_msec[slot] = now
		var state: int = peer.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			_drain(slot, peer)
			var silent_for: int = now - _slot_last_packet_msec[slot]
			if silent_for > (int(remote_timeout_sec * 1000.0) if peer is RemoteSeat else timeout_msec):
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
func _read_client_id(peer: Variant) -> Variant:
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
func _bind_with_id(peer: Variant, id: String) -> void:
	if id.is_empty():
		_last_generated_id += 1
		id = "host-assigned-%d-%d" % [_last_generated_id, randi()]
	if _refused_by_match_kind(peer):
		return # #435: a phone in an Online match, a remote seat in a Couch one
	if _kicked_ids.has(id):
		peer.close(4001, KICKED_REASON)
		if _log_input:
			print("controller refused: kicked by the host")
		return
	for slot in _slot_peers.size():
		if _slot_claimed[slot] != 1 or _slot_virtual[slot] == 1 or _slot_client_id[slot] != id:
			continue
		var old: Variant = _slot_peers[slot]
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
func _claim_for_phone(slot: int, id: String, peer: Variant) -> void:
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

## The slot of the bot that makes way when a human finds every slot claimed
## (issues #193, #445): the most recent bot, in the lobby (SOLO_PHASES) and, in
## an Online match, between rounds too (BETWEEN_ROUNDS_PHASES) -- mid-round a
## bot's body is in the fight. -1 for none.
func _yielding_bot_slot() -> int:
	if bot_director == null:
		return -1
	var phase: String = str(_lobby_state.get("phase", "lobby"))
	if not SOLO_PHASES.has(phase) and not (_match_kind == KIND_ONLINE and BETWEEN_ROUNDS_PHASES.has(phase)):
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
	_slot_team_pick[slot] = -1
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
		_slot_eyes[slot] = str(left.get("eyes", PlayerFaceScript.EYE_ROUND))
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
	_slot_team_pick[slot] = -1
	_slot_claim_serial[slot] = 0
	_join_order.erase(slot)
	_release_look(slot)
	_remote_claim.erase(slot)
	_remote_dropped_msec.erase(slot)

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
		"hat": _slot_hat[slot], "eyes": _slot_eyes[slot], "name": _slot_name[slot], "msec": now}

## Bind `peer` to `slot`: the slot frame, the current lobby state, and the full
## looks frame -- hat drawings included, which only a newly bound phone needs
## (issue #164). The caller tells every other phone with `_broadcast_looks(peer)`.
func _attach(slot: int, peer: Variant) -> void:
	_slot_peers[slot] = peer
	_lives_sent[slot] = ""
	_damage_sent[slot] = -1  # a newly bound page has no bar yet: the next call sends it
	_slot_last_packet_msec[slot] = Time.get_ticks_msec()
	_last_weapon[slot] = Vector2(NAN, NAN)
	_steady_frames[slot] = 0
	_bound_once[slot] = 1
	_slot_text_count[slot] = 0
	_slot_text_window_msec[slot] = 0
	_smoothers[slot].reset()
	_players[slot].bind_controller()
	# Issue #487: only a phone (no action button) flicks to launch.
	_players[slot].flick_launch_enabled = peer is not LocalSeat and peer is not RemoteSeat
	_note_remote_attach(slot, peer)
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
	_clear_release(slot)
	_slot_was_alive[slot] = 0
	_last_weapon[slot] = Vector2(NAN, NAN)
	_steady_frames[slot] = 0
	if _players[slot] != null:
		_players[slot].set_input_vector(Vector2.ZERO)
		_players[slot].unbind_controller()
		_players[slot].flick_launch_enabled = true
	_note_remote_drop(slot)
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
	var peer: Variant = _slot_peers[slot]
	if peer is PadSeat and peer.open:
		_rumble_pad(peer.device, kind)
		return
	if peer == null or not peer is WebSocketPeer or peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	peer.send_text(JSON.stringify({"t": "buzz", "kind": kind}))
	if _log_input:
		print("slot %d buzz %s" % [slot, kind])

## Minimum gap between two `dmg` frames to one seat, and the steps (percent)
## the bar is sent in. Cheap by construction (issue #331): only on change.
const DAMAGE_SEND_GAP_MSEC: int = 100
var _damage_sent: Array[int] = []  # last percent sent per slot, -1 = nothing yet
var _damage_sent_msec: Array[int] = []

## Tell the phone on `slot` how close its player is to a KO (issue #331): one
## `{"t":"dmg","v":<0..1>}` frame, which the page draws as a bar. `fraction` is
## damage / DEATH_DAMAGE. Sent only when the rounded percent changed since the
## last frame and at least `DAMAGE_SEND_GAP_MSEC` has passed; a change held back
## by the throttle goes out on a later call, so callers just report every tick.
func send_damage(slot: int, fraction: float) -> void:
	if not slot_has_controller(slot) or _slot_peers[slot] is PadSeat:
		return # a gamepad has no screen for the bar (#442)
	var percent: int = roundi(clampf(fraction, 0.0, 1.0) * 100.0)
	if percent == _damage_sent[slot]:
		return
	var now: int = Time.get_ticks_msec()
	if _damage_sent[slot] != -1 and now - _damage_sent_msec[slot] < DAMAGE_SEND_GAP_MSEC:
		return
	var peer: Variant = _slot_peers[slot]
	if peer == null or not (peer is WebSocketPeer or peer.has_method("send_text")) or peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_damage_sent[slot] = percent
	_damage_sent_msec[slot] = now
	peer.send_text(JSON.stringify({"t": "dmg", "v": percent / 100.0}))

var _lives_sent: Array[String] = []

## Tell the phone on `slot` its player's lives (Stock, #354): one
## `{"t":"lives","v":<n>,"steal":<bool>}` frame, `n` -1 to hide the counter.
## Sent only when it changed since the last frame to that seat.
func send_lives(slot: int, count: int, can_steal: bool) -> void:
	if not slot_has_controller(slot):
		return
	var key: String = "%d:%s" % [count, can_steal]
	if _lives_sent[slot] == key:
		return
	var peer: Variant = _slot_peers[slot]
	if peer == null or not (peer is WebSocketPeer or peer.has_method("send_text")) or peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_lives_sent[slot] = key
	peer.send_text(JSON.stringify({"t": "lives", "v": count, "steal": can_steal}))

## Hand the person on `slot` their lifetime-stat deltas (#503): one
## `{"t":"career","d":{...}}` frame that their device adds to its own totals.
## Only phones and Online PC clients keep a career: a gamepad seat, the host
## PC's own seat and a bot are not a person with a device, so they get nothing.
## Returns whether a frame went out; an empty `deltas` sends nothing.
func send_career(slot: int, deltas: Dictionary) -> bool:
	if deltas.is_empty() or not slot_has_controller(slot) or _slot_virtual[slot] == 1:
		return false
	var peer: Variant = _slot_peers[slot]
	if peer == null or peer is LocalSeat or not peer.has_method("send_text") or peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	peer.send_text(JSON.stringify({"t": "career", "d": deltas}))
	return true

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
## Issue #459: a remote seat that dropped mid-match is kept while its hold runs.
func expire_disconnected_claims() -> void:
	var released: bool = false
	for slot in _slot_claimed.size():
		if _slot_claimed[slot] == 1 and not slot_has_controller(slot) and not remote_seat_held(slot):
			_release_claim(slot)
			released = true
	if released:
		_broadcast_looks()

## Latest value wins: drain everything queued this frame and keep only the last
## well-formed packet, so a burst never replays stale input. The packet sets
## the slot's smoothing target; `_apply_smoothed_input` applies it (#113).
func _drain(slot: int, peer: Variant) -> void:
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
		if pkt.size() != PACKET_SIZE and pkt.size() != RELEASE_PACKET_SIZE and pkt.size() != ACTION_PACKET_SIZE:
			continue
		latest = pkt
		got = true
	if not got:
		return
	_slot_last_packet_msec[slot] = Time.get_ticks_msec()
	var v: Vector2 = Vector2(latest.decode_float(0), latest.decode_float(4))
	_smoothers[slot].push(v)
	_slot_release_remote[slot] = 1 if latest.size() >= RELEASE_PACKET_SIZE and latest[PACKET_SIZE] != 0 else 0
	if latest.size() == ACTION_PACKET_SIZE:
		var count: int = latest[RELEASE_PACKET_SIZE] & 0x7F
		var hold: bool = latest[RELEASE_PACKET_SIZE] & 0x80 != 0
		if _slot_press_seen[slot] != -1 and count != _slot_press_seen[slot]:
			if not hold:
				# #601: a burst keeps only the last packet; fire once per
				# counter step (7-bit, wraps), capped at 3.
				for _i in mini((count - _slot_press_seen[slot]) & 0x7F, 3):
					_action_press(slot)
			else:
				_try_throw(slot)
		_slot_press_seen[slot] = count
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
				apply_host_command("target", n)
				if _log_input:
					print("slot %d set match target %d" % [slot, _match_target])
		"host":
			_handle_host_command(slot, msg)
		"hat":
			var hat: Variant = msg.get("v")
			if hat is String:
				set_slot_hat(slot, hat)
		"eyes":
			var eyes: Variant = msg.get("v")
			if eyes is String:
				set_slot_eyes(slot, eyes)
		"color":
			var c: Variant = msg.get("v")
			if _is_number(c):
				request_color(slot, int(c))
		"mode":
			var mode: Variant = msg.get("v")
			if slot == host_slot() and mode is String and (mode == "ffa" or mode == "teams"):
				if apply_host_command("mode", mode) and _log_input:
					print("slot %d set mode %s" % [slot, mode])
		"gamemode":
			var picked: Variant = msg.get("v")
			if slot == host_slot() and picked is String:
				if apply_host_command("gamemode", picked) and _log_input:
					print("slot %d set game mode '%s'" % [slot, picked])
		"steal":
			steal_requested.emit(slot)
		"stock":
			# The host phone's Stock lobby controls (#354): lives and/or time limit.
			if slot == host_slot():
				if _is_number(msg.get("lives")):
					apply_host_command("stock_lives", msg.get("lives"))
				if _is_number(msg.get("time")):
					apply_host_command("stock_time", msg.get("time"))
				if msg.get("stage") is String:
					apply_host_command("stock_stage", msg.get("stage"))
		"pong":
			_on_pong(slot, msg)
		"team":
			var team: Variant = msg.get("v")
			var phase: String = str(_lobby_state.get("phase", "lobby"))
			if _is_number(team) and float(team) in [-1.0, 0.0, 1.0] and TEAM_PICK_PHASES.has(phase):
				_slot_team_pick[slot] = int(team)
				if _log_input:
					print("slot %d picked team %d" % [slot, _slot_team_pick[slot]])

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
	elif cmd == "online":
		var on: Variant = msg.get("v")
		if _slot_peers[slot] is RemoteSeat:
			if _log_input:
				print("slot %d host command 'online' ignored: a remote host cannot change the relay" % slot)
		elif on is bool:
			apply_host_command("online", on)
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
## Issue #458: `by_host_pc` is the host PC's own kick, for which the earliest
## phone or remote seat is not the host; only the host PC's seat is refused.
func kick(slot: int, by_host_pc: bool = false) -> bool:
	if slot < 0 or slot >= _slot_claimed.size() or _slot_claimed[slot] != 1:
		return false
	if slot == (_host_pc_slot if by_host_pc else host_slot()):
		return false
	if slot == _host_pc_slot:
		return false # #545: the host PC's own seat is never kickable
	if is_virtual(slot):
		# A bot (issue #152): its director sends it away.
		bot_director.remove_bot(slot)
		return true
	var peer: Variant = _slot_peers[slot]
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
	return slot >= 0 and slot < _slot_ready.size() and (_slot_ready[slot] == 1 or _slot_virtual[slot] == 1 or (slot == _host_pc_slot and not _solo_host_must_ready()))

## Solo (#505): the host PC seat is the only human, so it readies up itself (Start,
## Enter) in the lobby rather than starting the match by existing. Everywhere
## else, and in a Solo match once it is running, the seat counts as ready. On the
## victory screen the Solo host must Continue (key, or the timeout) like any human.
func _solo_host_must_ready() -> bool:
	var phase: String = str(_lobby_state.get("phase", "lobby"))
	return room_closed() and (SOLO_PHASES.has(phase) or phase == "victory") # the lone human must Continue too, or the podium never shows (#522)

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
## connected right now (never the host-PC seat or a remote seat), or -1 with no phones at all.
func host_slot() -> int:
	for slot: int in _join_order:
		if _slot_peers[slot] != null and not _slot_peers[slot] is LocalSeat and not _slot_peers[slot] is RemoteSeat:
			return slot # #578: a remote seat never hosts; the host PC runs an Online room
	return -1

## The match length the host phone chose ("first to N"), 5 by default.
func match_target() -> int:
	return _match_target

## Issue #236: whether the host phone chose Teams for the next match.
func team_mode() -> bool:
	return _team_mode

## Issue #236: set the mode as the host phone's menu would (a test seam).
func set_team_mode(on: bool) -> void:
	_team_mode = on
	_drop_ffa_only_mode()

## Issue #352: the `GameModes` id chosen for the next match, "" for Classic.
func game_mode() -> String:
	return _game_mode

## Issue #352: set the game mode as the host phone's picker would (a test
## seam). Returns false, changing nothing, for an unknown id or one the Teams
## format rules out.
func set_game_mode(id: String) -> bool:
	if not GameModesScript.is_valid(id) or not GameModesScript.fits_format(id, _team_mode):
		return false
	_game_mode = id
	HostSettingsScript.shared().set_game_mode(id)
	return true

## The format was switched with a mode it rules out chosen (Hot Potato with
## Teams on, Soccer with Teams off): fall back to Classic.
func _drop_ffa_only_mode() -> void:
	if not GameModesScript.fits_format(_game_mode, _team_mode):
		_game_mode = GameModesScript.CLASSIC
		HostSettingsScript.shared().set_game_mode(_game_mode)

## Issue #236: `slot`'s team pick, 0 red or 1 blue, or -1 for "auto".
func slot_team_pick(slot: int) -> int:
	return _slot_team_pick[slot] if slot >= 0 and slot < _slot_team_pick.size() else -1

## Send the lobby state to every connected phone, and keep it for any phone
## that binds later. Issue #164: entering a match phase from any other phase
## starts a new match serial.
func set_lobby_state(state: Dictionary) -> void:
	var was: String = str(_lobby_state.get("phase", ""))
	_lobby_state = state.duplicate(true)
	_lobby_state["t"] = "lobby"
	if MATCH_PHASES.has(str(_lobby_state.get("phase", ""))) and not MATCH_PHASES.has(was):
		_match_serial += 1
	_send_lobby_to_all()
	_update_mouse_capture()

func _send_lobby_to_all() -> void:
	var text: String = _lobby_text()
	for peer: Variant in _slot_peers:
		if peer != null and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			peer.send_text(text)

## The stored lobby state as sent to a phone, marked up as it stands right
## now: each bot's entry flagged "bot" (issue #152), each entry's "claim"
## serial and the "match" serial (issue #164), which the host menu echoes
## back so the host can tell a stale kick or End match from a current one.
func _lobby_text() -> String:
	_lobby_state["match"] = _match_serial
	# Issue #239: the host menu's Go online option and the host screen's.
	_lobby_state["online"] = online_status()
	_lobby_state["room"] = online_room_code() if relay_link != null else ""
	_lobby_state["pc_seat"] = _host_pc_slot != -1
	_lobby_state["kind"] = _match_kind # #435: "local", "online" or "" (not picked)
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
	_slot_eyes[slot] = PlayerFaceScript.EYE_ROUND
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
	_slot_eyes[slot] = PlayerFaceScript.EYE_ROUND
	_slot_color[slot] = -1
	var player: Variant = _players[slot]
	if player != null and player.has_method("set_identity_color"):
		player.set_hat(HatScript.NONE)
		player.set_eyes(PlayerFaceScript.EYE_ROUND)
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
	player.set_eyes(_slot_eyes[slot])
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

## `slot` wears eye style `id`, one of `PlayerFace.gd`'s EYE_IDS (issue #297).
## Same path as the hat: unknown id or unclaimed slot is ignored.
func set_slot_eyes(slot: int, id: String) -> bool:
	if slot < 0 or slot >= _slot_eyes.size() or _slot_claimed[slot] != 1 or not PlayerFaceScript.EYE_IDS.has(id):
		return false
	_slot_eyes[slot] = id
	_apply_look(slot)
	_broadcast_looks()
	return true

func slot_eyes(slot: int) -> String:
	return _slot_eyes[slot] if slot >= 0 and slot < _slot_eyes.size() else PlayerFaceScript.EYE_ROUND

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
	var eyes_list: Array = []
	for id: String in PlayerFaceScript.EYE_IDS:
		eyes_list.append({"id": id, "label": PlayerFaceScript.EYE_LABELS.get(id, id)})
	msg["eyes"] = eyes_list
	msg["art"] = _hat_art
	return msg

## What every phone is told when someone's looks change (issue #164): just
## each claimed slot's colour and hat.
func looks_update_message() -> Dictionary:
	var looks: Array = []
	for slot in _slot_claimed.size():
		if _slot_claimed[slot] == 1:
			looks.append({"slot": slot, "color": _slot_color[slot], "hat": _slot_hat[slot], "eyes": _slot_eyes[slot]})
	return {"t": "looks", "looks": looks}

## Tell every connected phone but `except` (one that has just been sent the
## full looks frame on binding) who wears what.
func _broadcast_looks(except: Variant = null) -> void:
	var text: String = JSON.stringify(looks_update_message())
	for peer: Variant in _slot_peers:
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

# --- Remote seats over the relay (issue #239) --------------------------------

## Connects to the relay at `url` and opens the room; returns an Error code.
func go_online(url: String) -> int:
	if _match_kind == KIND_SOLO:
		return ERR_UNAVAILABLE # Solo never contacts the relay (#522, ADR-0023)
	return _ensure_relay_link().go_online(url)

## The relay link, made the first time a match goes online: a Couch or Solo
## match never creates one (#522).
func _ensure_relay_link() -> Node:
	if relay_link == null:
		relay_link = RelayLinkScript.new()
		relay_link.name = "RelayLink"
		add_child(relay_link)
		relay_link.peer_joined.connect(_on_relay_peer_joined)
		relay_link.peer_left.connect(_on_relay_peer_left)
		relay_link.frame_received.connect(_on_relay_frame)
		relay_link.room_code_changed.connect(_on_room_code_changed)
		relay_link.link_state_changed.connect(_on_link_state_changed)
	return relay_link

## The relay link's state; "offline" while there is no link at all.
func relay_state() -> String:
	return relay_link.link_state() if relay_link != null else RelayLinkScript.STATE_OFFLINE

## Leaves the relay and closes the room.
func go_offline() -> void:
	if relay_link != null:
		relay_link.go_offline()

## The room code the relay gave this host, or "" when not online.
func online_room_code() -> String:
	return relay_link.room_code() if relay_link != null else ""

## Whether the relay link is up and the room open.
func is_online() -> bool:
	return relay_state() == "online"

func _on_relay_peer_joined(peer: int) -> void:
	var seat := RemoteSeat.new()
	seat.peer = peer
	seat.link = relay_link
	seat.deadline_msec = Time.get_ticks_msec() + int(connection_timeout_sec * 1000.0)
	_remote_seats[peer] = seat
	_remote_awaiting.append(seat)

## A relay peer leaving is a phone socket closing: its slot is unbound and the
## claim held (ADR-0007).
func _on_relay_peer_left(peer: int) -> void:
	var seat: RemoteSeat = _remote_seats.get(peer)
	if seat == null:
		return
	seat.open = false
	_remote_seats.erase(peer)
	_remote_awaiting.erase(seat)

func _on_relay_frame(peer: int, kind: int, payload: PackedByteArray) -> void:
	var seat: RemoteSeat = _remote_seats.get(peer)
	if seat != null:
		seat.push(kind, payload)

## The remote twin of the hello stage in `_process_websocket()`: the first text
## frame must be `{"id": ..., "proto": PROTOCOL_VERSION}`, then the seat goes
## through `_bind_with_id()` exactly as a phone does.
func _process_remote() -> void:
	for peer: int in _remote_seats.keys():
		if not _remote_seats[peer].open:
			_remote_seats.erase(peer)
	var now: int = Time.get_ticks_msec()
	var reconnecting: bool = relay_state() == RelayLinkScript.STATE_RECONNECTING
	for seat: RemoteSeat in _remote_awaiting.duplicate():
		if reconnecting:
			seat.deadline_msec = now + int(connection_timeout_sec * 1000.0)
		if not seat.open:
			_remote_awaiting.erase(seat)
			continue
		var hello: Variant = _read_remote_hello(seat)
		if hello != null:
			_remote_awaiting.erase(seat)
			if not _is_number(hello.get("proto")) or int(hello["proto"]) != PROTOCOL_VERSION:
				seat.send_text(JSON.stringify({"t": "error", "reason": "version"}))
				relay_link.drop_peer(seat.peer)
				seat.open = false
				_remote_seats.erase(seat.peer)
				if _log_input:
					print("remote %d refused: protocol version" % seat.peer)
				continue
			var build_reason: String = build_mismatch_reason(hello)
			if not build_reason.is_empty():
				seat.send_text(JSON.stringify({"t": "error", "reason": build_reason}))
				relay_link.drop_peer(seat.peer)
				seat.open = false
				_remote_seats.erase(seat.peer)
				if _log_input:
					print("remote %d refused: %s" % [seat.peer, build_reason])
				continue
			_bind_with_id(seat, (hello["id"] as String).left(MAX_CLIENT_ID_LENGTH))
		elif now > seat.deadline_msec:
			_remote_awaiting.erase(seat)
			seat.close(1008, "no hello")
			_remote_seats.erase(seat.peer)

## Issue #447: the demo joins only the demo, the full game only the full game.
## A remote hello carries `"demo": <bool>` (missing reads as the full game).
## "" when the builds match; else the refusal reason sent to the client:
## "full_only" (a demo client at a full host) or "demo_only" (the reverse).
static func build_mismatch_reason(hello: Dictionary) -> String:
	var host_demo: bool = DemoBuildScript.is_active()
	var client_demo: bool = hello.get("demo", false) == true
	if client_demo == host_demo:
		return ""
	return "demo_only" if host_demo else "full_only"

## The first text frame of `seat` that is a JSON object with a string "id", or null.
func _read_remote_hello(seat: RemoteSeat) -> Variant:
	while seat.get_available_packet_count() > 0:
		var pkt: PackedByteArray = seat.get_packet()
		if not seat.was_string_packet():
			continue
		var parsed: Variant = _parse_json(pkt.get_string_from_utf8())
		if parsed is Dictionary and typeof(parsed.get("id")) == TYPE_STRING:
			return parsed
	return null

# --- Going online and playing on this PC (issue #239) ---------------------------
#
# Both are host powers of the lobby. The host phone's menu sends them as host
# commands; the host screen's buttons and keys (LobbyScreen.gd) call
# `apply_host_command()` directly -- one path, so nothing is done twice.

const DEFAULT_RELAY_URL: String = "ws://127.0.0.1:9080"
const RELAY_URL_SETTING: String = "pickfight/relay_url"
const RELAY_ARG: String = "--relay="
const HOST_PC_ID: String = "host-pc"
const HOST_PC_NAME: String = "Host"

var _online_requested: bool = false
var _host_pc_slot: int = -1
var _host_pc_seat: LocalSeat = null
var _host_mouse: RefCounted = HostMouseScript.new()
var _mouse_captured: bool = false
## Esc released the mouse; a click in the window takes it back.
var _mouse_escaped: bool = false

## The relay to go online through: a `--relay=<url>` in `args` (the user args),
## else the `pickfight/relay_url` project setting, else the local dev relay.
static func resolve_relay_url(args: PackedStringArray) -> String:
	for arg: String in args:
		if arg.begins_with(RELAY_ARG) and arg.length() > RELAY_ARG.length():
			return arg.trim_prefix(RELAY_ARG)
	var configured: Variant = ProjectSettings.get_setting(RELAY_URL_SETTING, DEFAULT_RELAY_URL)
	return str(configured) if configured is String and not (configured as String).is_empty() else DEFAULT_RELAY_URL

## A host-screen or host-phone lobby command: "online" (bool), "pc_seat" (bool),
## "mode" ("ffa" or "teams"), "gamemode" (a `GameModes` id), "target" (number) or "start" (forces every seat
## ready). Returns whether it was taken. "online", "pc_seat" and "start" are
## heeded only in the lobby (SOLO_PHASES / "lobby"); "mode" and "target" also
## on the victory screen (MODE_PHASES), as the phone's were.
func apply_host_command(cmd: String, arg: Variant = null) -> bool:
	var phase: String = str(_lobby_state.get("phase", "lobby"))
	match cmd:
		"online":
			if not arg is bool or not SOLO_PHASES.has(phase) or _match_kind == KIND_LOCAL or _match_kind == KIND_SOLO:
				return false
			return _set_online_requested(arg)
		"pc_seat":
			if not arg is bool or not SOLO_PHASES.has(phase) or _match_kind != "":
				return false # #435: the match kind owns the host-PC seat now
			return _set_host_pc_seat(arg)
		"kind":
			if not arg is String or not SOLO_PHASES.has(phase):
				return false
			return set_match_kind(arg)
		"bots":
			if not _is_number(arg) or not SOLO_PHASES.has(phase):
				return false
			set_bot_count(int(arg))
			return true
		"mode":
			if not (arg is String and (arg == "ffa" or arg == "teams")) or not MODE_PHASES.has(phase):
				return false
			_team_mode = arg == "teams"
			_drop_ffa_only_mode()
			return true
		"gamemode":
			if not arg is String or not MODE_PHASES.has(phase):
				return false
			return set_game_mode(arg)
		"stock_lives", "stock_time":
			if not _is_number(arg) or not MODE_PHASES.has(phase):
				return false
			var settings: RefCounted = HostSettingsScript.shared()
			if cmd == "stock_lives":
				settings.set_stock_lives(int(arg))
				return true
			return settings.set_stock_time_limit(int(arg))
		"stock_stage":
			if not arg is String or not MODE_PHASES.has(phase):
				return false
			return HostSettingsScript.shared().set_stock_stage(arg)
		"soccer_goals", "ctf_captures":
			if not _is_number(arg) or not MODE_PHASES.has(phase):
				return false
			if cmd == "soccer_goals":
				HostSettingsScript.shared().set_soccer_goals(int(arg))
			else:
				HostSettingsScript.shared().set_ctf_captures(int(arg))
			return true
		"target":
			if not _is_number(arg) or not MODE_PHASES.has(phase):
				return false
			# The row's meaning follows the mode (#544): lives, goals or captures.
			match GameModesScript.target_kind(_game_mode):
				"lives":
					return apply_host_command("stock_lives", arg)
				"goals":
					return apply_host_command("soccer_goals", arg)
				"captures":
					return apply_host_command("ctf_captures", arg)
			_match_target = clampi(int(arg), MIN_MATCH_TARGET, MAX_MATCH_TARGET)
			return true
		"start":
			if phase != "lobby":
				return false
			for slot: int in claimed_slots():
				if slot_has_controller(slot):
					_slot_ready[slot] = 1
			host_command.emit("start", -1)
			return true
	return false

func _set_online_requested(on: bool) -> bool:
	if on == _online_requested and not (on and relay_state() == RelayLinkScript.STATE_ERROR):
		return true
	_online_requested = on
	if on:
		go_online(resolve_relay_url(OS.get_cmdline_user_args()))
	else:
		go_offline()
	_send_lobby_to_all()
	return true

## Whether the host asked to be online (the link may still be coming up).
func online_requested() -> bool:
	return _online_requested

## "off", "connecting", "online" or "unreachable" (asked for and not reached).
func online_status() -> String:
	if not _online_requested or relay_link == null:
		return "off"
	match relay_link.link_state():
		"online":
			return "online"
		"connecting", "reconnecting":
			return "connecting"
	return "unreachable"

func _on_room_code_changed(_code: String) -> void:
	_refresh_join_label()
	_send_lobby_to_all()

## Streamer mode (#369) can be toggled at any time: redraw the corner when it is.
func _sync_room_code_hidden() -> void:
	var hidden: bool = room_code_hidden()
	if hidden == _room_code_was_hidden:
		return
	_room_code_was_hidden = hidden
	if relay_link != null:
		_refresh_join_label()
	set_join_corner_visible(not _join_corner_hidden)

var _room_code_was_hidden: bool = false

func _refresh_join_label() -> void:
	var label: Label = join_label()
	var code: String = online_room_code()
	if label == null:
		return
	if room_code_hidden():
		label.text = tr("ROOM_CODE_HIDDEN")
	elif code.is_empty():
		label.text = _join_label_base
	elif relay_state() == RelayLinkScript.STATE_RECONNECTING:
		label.text = "%s\n%s" % [_join_label_base, tr("ONLINE_ROOM_RECONNECTING") % code]
	else:
		label.text = "%s\n%s" % [_join_label_base, tr("ONLINE_ROOM") % code]

func _on_link_state_changed(_state: String) -> void:
	_refresh_join_label()
	_send_lobby_to_all()

## The slot the host PC's own seat holds, or -1 when "Play on this PC" is off.
func host_pc_slot() -> int:
	return _host_pc_slot

func _set_host_pc_seat(on: bool) -> bool:
	if on == (_host_pc_slot != -1):
		return true
	if not on:
		_release_host_pc_seat()
		return true
	var slot: int = -1
	for s in _slot_peers.size():
		if _slot_claimed[s] != 1 and _players[s] != null:
			slot = s
			break
	if slot == -1:
		slot = _yielding_bot_slot()
		if slot == -1:
			return false
		bot_director.remove_bot(slot)
	_host_pc_seat = LocalSeat.new()
	_host_pc_slot = slot
	_host_mouse.reset()
	_claim_for_phone(_rejoin_slot(HOST_PC_ID, slot), HOST_PC_ID, _host_pc_seat)
	_host_pc_slot = _slot_peers.find(_host_pc_seat)
	_slot_name[_host_pc_slot] = HOST_PC_NAME
	_apply_saved_host_pick()
	_update_mouse_capture()
	_send_lobby_to_all()
	return true

## Issue #441: the host PC's saved look goes on its seat as it is claimed, by the
## phone's own rules (a colour another seat holds is refused, the automatic one stays).
func _apply_saved_host_pick() -> void:
	var pick: Dictionary = CosmeticsPickerScript.clean_pick(HostSettingsScript.shared().cosmetic_pick)
	set_slot_hat(_host_pc_slot, str(pick["hat"]))
	set_slot_eyes(_host_pc_slot, str(pick["eyes"]))
	if int(pick["color"]) >= 0:
		request_color(_host_pc_slot, int(pick["color"]))

## Whether the host PC's own cosmetics panel shows: an Online match with its
## seat on, in the lobby or countdown.
func host_picker_shown() -> bool:
	return (_match_kind == KIND_ONLINE or _match_kind == KIND_SOLO) and _host_pc_slot != -1 and CosmeticsPickerScript.PICK_PHASES.has(str(_lobby_state.get("phase", "lobby")))

func _release_host_pc_seat() -> void:
	var slot: int = _host_pc_slot
	_host_pc_slot = -1
	if _host_pc_seat != null:
		_host_pc_seat.open = false
	_host_pc_seat = null
	if slot != -1 and _slot_claimed[slot] == 1:
		_unbind(slot)
		_release_claim(slot)
		_broadcast_looks()
	_update_mouse_capture()
	_send_lobby_to_all()

## The seat is gone from under the toggle (a kick, say): forget it.
func _check_host_pc_seat() -> void:
	if _host_pc_slot != -1 and (_slot_claimed[_host_pc_slot] != 1 or _slot_peers[_host_pc_slot] != _host_pc_seat):
		_release_host_pc_seat()

## The host PC player's mouse moved by `relative` pixels: the same smoothing
## target a phone's drag packet sets.
func host_pc_mouse_motion(relative: Vector2) -> void:
	if _host_pc_slot == -1:
		return
	var edge: float = minf(get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y)
	var v: Vector2 = _host_mouse.move(relative, HostMouseScript.drag_radius(edge))
	_slot_last_packet_msec[_host_pc_slot] = Time.get_ticks_msec()
	_smoothers[_host_pc_slot].push(v)

func _input(event: InputEvent) -> void:
	var pad_button := event as InputEventJoypadButton
	if pad_button != null:
		_pad_release_button(pad_button.device, pad_button.button_index, pad_button.pressed)
		if pad_button.pressed:
			_pad_button_pressed(pad_button.device, pad_button.button_index)
		return
	if _host_pc_slot == -1 and not _mouse_captured:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _mouse_captured:
			host_pc_mouse_motion(motion.relative)
		return
	var key := event as InputEventKey
	# Issue #463, ADR-0022: a Space tap is the host PC's finger lifting (and
	# touching again), since a mouse never sends a zero vector.
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_SPACE \
			and _host_pc_slot != -1 and MATCH_PHASES.has(str(_lobby_state.get("phase", "lobby"))) \
			and not _input_gated() and not _host_menu_open():
		_action_down(_host_pc_slot)
		return
	if key != null and not key.pressed and key.physical_keycode == KEY_SPACE and _host_pc_slot != -1:
		_action_up(_host_pc_slot)
		return
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE and _mouse_captured:
		_mouse_escaped = true
		_update_mouse_capture()
		# Issue #458: running the room, the same Esc opens the host's menu too.
		if not pc_runs_room():
			get_viewport().set_input_as_handled()
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed and _mouse_escaped and _host_pc_slot != -1 and not _host_menu_open():
		_mouse_escaped = false
		_update_mouse_capture()

## The mouse is captured while the host PC plays a live match, and free in the
## lobby, while paused, after Esc, and once the seat is off.
func _update_mouse_capture() -> void:
	var phase: String = str(_lobby_state.get("phase", "lobby"))
	if not MATCH_PHASES.has(phase):
		_mouse_escaped = false
	var want: bool = _host_pc_slot != -1 and MATCH_PHASES.has(phase) and not _mouse_escaped \
		and not bool(_lobby_state.get("paused", false))
	if want == _mouse_captured:
		return
	_mouse_captured = want
	_host_mouse.reset()
	if not want and _host_pc_slot != -1:
		_smoothers[_host_pc_slot].push(Vector2.ZERO)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if want else Input.MOUSE_MODE_VISIBLE

# --- Gamepad seats (issue #261) ----------------------------------------------

const PadMenuScript := preload("res://scripts/PadMenu.gd")
const PAD_ID_PREFIX: String = "pad-"
const PAD_DEADZONE: float = 0.2
## device -> PadSeat for every pad whose seat is bound.
var _pad_seats: Dictionary = {}
## Tests set a device's right stick here; headless has no real joypads.
var _test_pad_axes: Dictionary = {}

## The right stick of `device` as the relative vector a phone drag sends: a
## radial deadzone, rescaled so the edge of the dead zone reads 0 and full
## deflection 1 (ADR-0003).
func _pad_axis(device: int) -> Vector2:
	var raw := Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
	if _test_pad_axes.has(device):
		raw = _test_pad_axes[device]
	var left := Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
	if _test_pad_left_axes.has(device):
		left = _test_pad_left_axes[device]
	if pad_picker_shown(pad_slot(device)):
		left = Vector2.ZERO # the left stick drives the picker there, not the arm (#611)
	return pad_stick(raw, left)

## #600: the right stick swings the arm; a lone Joy-Con reports its one stick as
## the left, so the left takes over only while the right reads idle.
static func pad_stick(right: Vector2, left: Vector2) -> Vector2:
	var v: Vector2 = stick_vector(right)
	return v if v != Vector2.ZERO else stick_vector(left)

## A raw right stick as that vector; the PC client's gamepad uses it too (#435).
static func stick_vector(raw: Vector2) -> Vector2:
	var mag: float = raw.length()
	if mag <= PAD_DEADZONE:
		return Vector2.ZERO
	return raw.normalized() * minf((mag - PAD_DEADZONE) / (1.0 - PAD_DEADZONE), 1.0)

## The slot gamepad `device` holds right now, or -1.
func pad_slot(device: int) -> int:
	var seat: Variant = _pad_seats.get(device)
	var slot: int = _slot_peers.find(seat) if seat != null else -1
	if slot == -1 and seat != null:
		_pad_seats.erase(device)
	return slot

## Test seam: a pad's left stick, by device, in place of the real one.
var _test_pad_left_axes: Dictionary = {}

## #547: the left stick drives a pad's lobby picker like the D-pad (up and down
## pick the row, left and right change the value, with a repeat delay), for a
## single Joy-Con held sideways, which has no D-pad. The stick is read only while
## the picker shows and no host menu is open; otherwise its state is let go.
func _step_pad_pickers(delta: float) -> void:
	for device: int in _pad_seats.keys():
		var slot: int = pad_slot(device)
		if slot == -1:
			continue
		var axis := Vector2.ZERO
		if pad_picker_shown(slot) and not PadMenuScript.is_open():
			axis = Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
			if _test_pad_left_axes.has(device):
				axis = _test_pad_left_axes[device]
		cosmetics_picker.stick(self, slot, axis, delta)

## Issue #599: a pause or an open host menu owns the pads; presses and stick
## pushes are dropped (releases are not, so nothing sticks).
func _input_gated() -> bool:
	return bool(_lobby_state.get("paused", false)) or PadMenuScript.is_open()

func _push_pad_sticks() -> void:
	var gated: bool = _input_gated()
	for device: int in _pad_seats.keys():
		var slot: int = pad_slot(device)
		if slot == -1:
			continue
		if gated:
			_smoothers[slot].push(Vector2.ZERO)
			continue
		if _pad_axis(device) != Vector2.ZERO:
			_pad_tip_done[str(_slot_client_id[slot])] = true # it found the stick (#442)
		_slot_last_packet_msec[slot] = Time.get_ticks_msec()
		_smoothers[slot].push(_pad_axis(device))

## Issue #430: the host's controller, whose Start pauses and resumes a match.
## Joypad 0: the Steam Deck's own built-in controls (docs/steam-deck-readiness.md
## D16), and a PC host's first pad. Seated or not, it never makes its seat host.
const HOST_PAD_DEVICE: int = 0

## Issue #463, ADR-0022: either shoulder button held lets the pad's weapon go;
## clicking either stick toggles it, like Space on a PC.
func _pad_release_button(device: int, button: int, pressed: bool) -> void:
	var slot: int = pad_slot(device)
	if slot == -1:
		return
	if button == JOY_BUTTON_LEFT_SHOULDER or button == JOY_BUTTON_RIGHT_SHOULDER:
		# Released while held; a tap (up within TAP_MAX_SEC) throws the boomerang.
		if pressed:
			# Issue #511: the host menu owns the bumper right now. (The lobby picker
			# no longer does: it uses the D-pad and the left stick, #547.)
			if _input_gated():
				return
			_slot_release_held[slot] = 1
			_slot_bumper_down[slot] = GameClockScript459.now_msec()
		else:
			_slot_release_held[slot] = 0
			var down: int = _slot_bumper_down[slot]
			_slot_bumper_down[slot] = -1
			if down != -1 and _is_tap(down):
				_try_throw(slot)
	elif button == JOY_BUTTON_LEFT_STICK or button == JOY_BUTTON_RIGHT_STICK:
		if pressed:
			if not _input_gated():
				_action_down(slot)
		else:
			_action_up(slot)

## A or Start joins (in the lobby) or readies; B un-readies. Issue #430: in a
## match (or paused), Start from the host's pad sends the host phone's Pause or
## Resume, and from any other pad does nothing.
func _pad_button_pressed(device: int, button: int) -> void:
	if PadMenuScript.is_open():
		return # a host menu owns A and B right now (#368)
	var slot: int = pad_slot(device)
	var paused: bool = bool(_lobby_state.get("paused", false))
	if button == JOY_BUTTON_START and (paused or MATCH_PHASES.has(str(_lobby_state.get("phase", "lobby")))):
		if device == HOST_PAD_DEVICE:
			host_command.emit("resume" if paused else "pause", -1)
		return
	# Issue #441: in the lobby the D-pad drives the seat's cosmetics picker (#547: not the bumpers).
	if slot != -1 and pad_picker_shown(slot) and cosmetics_picker.pad_button(self, slot, button):
		return
	if button == JOY_BUTTON_A or button == JOY_BUTTON_START:
		if slot == -1:
			if SOLO_PHASES.has(str(_lobby_state.get("phase", "lobby"))):
				_bind_pad(device)
		else:
			_slot_ready[slot] = 1
	elif button == JOY_BUTTON_B and slot != -1:
		_slot_ready[slot] = 0

## Seat `device` under the id "pad-<device>": a replugged pad takes its held
## claim back through `_bind_with_id` (ADR-0007).
func _bind_pad(device: int, id: String = "") -> void:
	var seat := PadSeat.new()
	seat.device = device
	if id.is_empty():
		id = _pad_claim_id(device)
	_bind_with_id(seat, id)
	var slot: int = _slot_peers.find(seat)
	if slot == -1:
		return # full or kicked: the seat was closed
	_pad_seats[device] = seat
	if _slot_name[slot].is_empty():
		_slot_name[slot] = "Pad %d" % (device + 1)
	_send_lobby_to_all()

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected:
		var seat: Variant = _pad_seats.get(device)
		if seat != null:
			seat.open = false # the poll loop unbinds it and holds the claim
			_pad_seats.erase(device)
		return
	# Replugged: take a held claim back; a new pad waits for A.
	if pad_slot(device) != -1:
		return
	var held_id: String = _held_pad_claim_id(device)
	if not held_id.is_empty():
		_bind_pad(device, held_id)

## Gamepad parity (#442). A pad's claim id is "pad-<device>" plus its GUID when
## the OS reports one, so a replug on another port still finds its own seat, and
## a different pad that lands on the same index does not take it.
var _pad_guids: Dictionary = {} # claim id -> GUID of the pad that holds it
## Tests set a device's GUID here; headless has no real joypads.
var _test_pad_guids: Dictionary = {}
## Claim ids whose pad has already been told "right stick swings".
var _pad_tip_done: Dictionary = {}
## Rumbles started, newest last: {"device", "kind"} (diagnostic, for scenarios).
var pad_rumbles: Array = []

func _pad_guid(device: int) -> String:
	if _test_pad_guids.has(device):
		return str(_test_pad_guids[device])
	if not Input.get_connected_joypads().has(device):
		return ""
	return Input.get_joy_guid(device)

func _pad_claim_id(device: int) -> String:
	var guid: String = _pad_guid(device)
	var id: String = PAD_ID_PREFIX + str(device) + ("-" + guid if not guid.is_empty() else "")
	_pad_guids[id] = guid
	return id

## Whether another connected pad (not `device`) reports `guid`.
func _other_pad_has_guid(device: int, guid: String) -> bool:
	if guid.is_empty():
		return false
	var devices: Array = Input.get_connected_joypads()
	for d in _pad_seats.keys():
		if not devices.has(d):
			devices.append(d)
	for d in devices:
		if d != device and _pad_guid(d) == guid:
			return true
	return false

## The claim id of a held (unplugged) pad seat that `device` should take back:
## the same GUID (the same index first), else the same index with no GUID.
func _held_pad_claim_id(device: int) -> String:
	var guid: String = _pad_guid(device)
	var own: String = PAD_ID_PREFIX + str(device) + ("-" + guid if not guid.is_empty() else "")
	var found: String = ""
	var twin: bool = _other_pad_has_guid(device, guid)
	for slot in _slot_peers.size():
		var id: String = str(_slot_client_id[slot])
		if _slot_claimed[slot] != 1 or _slot_peers[slot] != null or not id.begins_with(PAD_ID_PREFIX):
			continue
		if id == own:
			return id
		# An identical pad that is still connected means a GUID alone cannot say
		# whose seat this is (#512): then only the same index reclaims.
		if not twin and not guid.is_empty() and _pad_guids.get(id, "") == guid and found.is_empty():
			found = id
	return found

## Whether the "right stick swings" hint should show on `slot`'s lobby card.
func pad_tip_pending(slot: int) -> bool:
	return slot >= 0 and slot < _slot_peers.size() and _slot_peers[slot] is PadSeat \
		and not _pad_tip_done.has(str(_slot_client_id[slot]))

## A buzz as controller rumble (ADR-0013): the same kinds, a pulse each.
func _rumble_pad(device: int, kind: String) -> void:
	var weak: float = 0.4
	var strong: float = 0.4
	var seconds: float = 0.15
	match kind:
		"win":
			strong = 1.0
			seconds = 0.5
		"eliminated":
			strong = 0.9
			seconds = 0.35
		"hit":
			weak = 0.7
			strong = 0.0
			seconds = 0.1
	Input.start_joy_vibration(device, weak, strong, seconds)
	pad_rumbles.append({"device": device, "kind": kind})

# --- Snapshot stream to remote seats (issue #251) ----------------------------

const SnapshotScript: GDScript = preload("res://scripts/Snapshot.gd")
const SnapshotCaptureScript: GDScript = preload("res://scripts/SnapshotCapture.gd")
const RemoteHudScript: GDScript = preload("res://scripts/RemoteHud.gd")
const SNAPSHOT_HZ: float = 30.0
## A full snapshot every this many frames (about a second); deltas between.
const SNAPSHOT_FULL_EVERY: int = 30

## Frames sent since the first of this stream (diagnostic, for scenarios).
var snapshot_frames_sent: int = 0
var _snapshot_accum: float = 0.0
var _snapshot_frame: int = 0
var _snapshot_bound: Dictionary = {} # RemoteSeat -> true, the seats already sent a full frame
var _snapshot_previous: Dictionary = {}
var _hud_last: Dictionary = {}
var _stream_link_was_up: bool = false
var _hud_tick: int = 0
## Hud text frames sent to remote seats (issue #436), for scenarios.
var hud_frames_sent: int = 0

## Streams the world to the remote seats at 30 Hz while at least one is bound;
## a seat that just bound gets a full snapshot at once. Captures nothing, and
## costs one loop over the seats, when none is bound.
func _stream_snapshots(delta: float) -> void:
	var bound: Array = []
	for seat: RemoteSeat in _remote_seats.values():
		if seat.open and _slot_peers.has(seat):
			bound.append(seat)
	if bound.is_empty():
		_snapshot_bound.clear()
		_snapshot_accum = 0.0
		_snapshot_frame = 0
		_listen_for_sounds(false)
		return
	_listen_for_sounds(true)
	var fresh: bool = false
	# Issue #579: frames sent while the host's link was down were dropped, so the
	# link coming back sends a full frame and the HUD again.
	var link_up: bool = is_online()
	fresh = link_up and not _stream_link_was_up
	_stream_link_was_up = link_up
	for seat: RemoteSeat in bound:
		fresh = fresh or not _snapshot_bound.has(seat)
	_snapshot_bound.clear()
	for seat: RemoteSeat in bound:
		_snapshot_bound[seat] = true
	_snapshot_accum = minf(_snapshot_accum + delta, 2.0 / SNAPSHOT_HZ)
	if not fresh and _snapshot_accum < 1.0 / SNAPSHOT_HZ:
		return
	_snapshot_accum = maxf(0.0, _snapshot_accum - 1.0 / SNAPSHOT_HZ)
	var round_manager: Node = get_parent().get_node_or_null("RoundManager") if get_parent() != null else null
	if round_manager == null or not round_manager.has_method("score_of"):
		return
	var world: Dictionary = SnapshotCaptureScript.capture(round_manager)
	# Issue #436/#429: a delta cannot say a body left, so a removal (or a new
	# round or stage) goes out as a full snapshot at once, not up to 1 s later.
	var full: bool = fresh or _snapshot_frame % SNAPSHOT_FULL_EVERY == 0 \
		or SnapshotCaptureScript.structure_changed(world, _snapshot_previous)
	var frame: Dictionary = world if full else SnapshotCaptureScript.delta(world, _snapshot_previous)
	_snapshot_previous = world
	_snapshot_frame = 1 if full else _snapshot_frame + 1
	var payload: PackedByteArray = SnapshotScript.encode(frame)
	payload.append_array(SnapshotCaptureScript.encode_sound_trailer(_snapshot_sounds, _music_track()))
	_snapshot_sounds.clear()
	_ensure_relay_link().send_to(0, RelayLinkScript.KIND_SNAPSHOT, payload)
	snapshot_frames_sent += 1
	_hud_tick += 1
	if fresh:
		_hud_last = {}
	if fresh or _hud_tick % 4 == 0:
		var hud: Dictionary = RemoteHudScript.capture(round_manager)
		if hud != _hud_last:
			_hud_last = hud
			_ensure_relay_link().send_text_to(0, JSON.stringify(hud))
			hud_frames_sent += 1

var _snapshot_sounds: Array = [] # sounds played since the last frame (see SnapshotCapture's trailer)
var _sound_source: Node = null

## Records the Sfx autoload's plays while a remote seat is bound, and only then.
func _listen_for_sounds(on: bool) -> void:
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx == null or on == (_sound_source != null):
		return
	if on:
		sfx.played.connect(_on_sound_played)
		_sound_source = sfx
	else:
		sfx.played.disconnect(_on_sound_played)
		_sound_source = null
		_snapshot_sounds.clear()

func _on_sound_played(sound: StringName, position: Variant, strength: float) -> void:
	if _snapshot_sounds.size() < SnapshotCaptureScript.MAX_SOUND_EVENTS:
		_snapshot_sounds.append({"name": String(sound), "position": position, "strength": strength})

func _music_track() -> String:
	var music: Node = get_node_or_null("/root/Music")
	return music.current_track() if music != null else ""

# --- Ping over the remote-seat channel (issue #446) ---------------------------
#
# About once a second the host sends each bound remote seat {"t":"ping","n":N};
# the client echoes {"t":"pong","n":N}. The round trip is shown beside the
# player in the Online lobby and on the scoreboard. It never kicks anyone.

## How often a remote seat is pinged, and the round trip above which it is
## shown in a warning colour.
var ping_interval_msec: int = 1000
const PING_WARN_MSEC: int = 150

func _ping_remote_seats() -> void:
	var now: int = Time.get_ticks_msec()
	for slot in _slot_peers.size():
		var seat: Variant = _slot_peers[slot]
		if not seat is RemoteSeat or not seat.open:
			continue
		if seat.ping_n != 0 and now - seat.ping_sent_msec < ping_interval_msec:
			continue
		seat.ping_n += 1
		seat.ping_sent_msec = now
		seat.ping_sent[seat.ping_n] = now
		seat.ping_sent.erase(seat.ping_n - 10)
		seat.send_text(JSON.stringify({"t": "ping", "n": seat.ping_n}))

func _on_pong(slot: int, msg: Dictionary) -> void:
	var seat: Variant = _slot_peers[slot] if slot >= 0 and slot < _slot_peers.size() else null
	if not seat is RemoteSeat or not _is_number(msg.get("n")) or not seat.ping_sent.has(int(msg["n"])):
		return
	seat.rtt_msec = maxi(0, Time.get_ticks_msec() - int(seat.ping_sent[int(msg["n"])]))

## The last round trip to the remote seat in `slot`, in ms; -1 for a phone,
## the host PC, a bot, or a seat that has not answered a ping yet.
func slot_ping_msec(slot: int) -> int:
	if slot < 0 or slot >= _slot_peers.size() or not _slot_peers[slot] is RemoteSeat:
		return -1
	return _slot_peers[slot].rtt_msec

# --- In-game cosmetics picker (issue #441, ADR-0021) --------------------------
#
# The shared picker model is CosmeticsPicker.gd; these are what its layouts read.

const CosmeticsPickerScript: GDScript = preload("res://scripts/CosmeticsPicker.gd")
## Each pad seat's picker cursor (the model's per-seat state).
var cosmetics_picker: RefCounted = CosmeticsPickerScript.new()

## Whether colour `index` could be worn by `slot` now: the phone's own rule.
func color_free(index: int, slot: int) -> bool:
	return _color_free(index, slot)

## How many colours are on offer, and colour `index` (white for none).
func palette_size() -> int:
	return _palette.size()

func palette_color(index: int) -> Color:
	return _palette[index] if index >= 0 and index < _palette.size() else Color.WHITE

## Whether `slot` is a gamepad's claim, plugged in or held (#442): its lobby
## card carries the picker.
func pad_claim(slot: int) -> bool:
	return slot >= 0 and slot < _slot_client_id.size() and _slot_claimed[slot] == 1 		and str(_slot_client_id[slot]).begins_with(PAD_ID_PREFIX)

## Whether `slot`'s gamepad picker shows: a gamepad holds the seat right now
## and it is the lobby (cosmetics change in the lobby only).
func pad_picker_shown(slot: int) -> bool:
	return slot >= 0 and slot < _slot_peers.size() and _slot_peers[slot] is PadSeat and _slot_peers[slot].open 		and CosmeticsPickerScript.PICK_PHASES.has(str(_lobby_state.get("phase", "lobby")))
# --- Couch or Online, never mixed (issue #435, ADR-0021) -------------------------
#
# The host picks the match kind on the title screen (LobbyScreen.gd): Couch (the
# Local match: phones, the browser controller page, gamepads), Online (remote
# seats, the host-PC seat always on, gamepads) or Solo (Online with the room
# closed and bots in the empty seats). Each kind refuses the other's seats, and
# switching kind in the lobby drops them. Until a kind is picked ("") no rule
# applies, as before #435: the title screen always picks one in the game, and
# scenarios that drive the server directly start there.

const KIND_LOCAL: String = "local"
const KIND_ONLINE: String = "online"
const KIND_SOLO: String = "solo"
## How many bots Solo seats beside the host (#435, owner's Q13).
const SOLO_BOTS: int = 3
## What a refused phone and a refused remote seat are told.
const ONLINE_MATCH_REASON: String = "online match: join from the game on a computer"
const COUCH_MATCH_REASON: String = "couch match"
const SOLO_MATCH_REASON: String = "solo match: nobody else can join"
const ROOM_CLOSED_REASON: String = "room closed"
const REFUSED_CODE: int = 4003
## How long the lobby shows "N players were dropped" after a switch.
const KIND_NOTICE_MSEC: int = 4000

var _match_kind: String = ""
## The last switch that dropped seats: {"kind", "count", "msec"}.
var _kind_drop: Dictionary = {}
## Joins refused for the match kind (diagnostic, for scenarios).
var refused_joins: int = 0

## "local", "online", "solo", or "" before the host picked one.
func match_kind() -> String:
	return _match_kind

## Whether this is Solo: its own offline match kind (#522, ADR-0023).
func room_closed() -> bool:
	return _match_kind == KIND_SOLO

## The drop notice to show right now, or {} once it has had its time.
func kind_drop_notice() -> Dictionary:
	if _kind_drop.is_empty() or Time.get_ticks_msec() - int(_kind_drop["msec"]) > KIND_NOTICE_MSEC:
		return {}
	return _kind_drop

## Makes this a "local", "online" or "solo" match (see above). Returns false for
## an unknown kind. The host command "kind" lands here, in the lobby only.
func set_match_kind(kind: String) -> bool:
	if not [KIND_LOCAL, KIND_ONLINE, KIND_SOLO].has(kind):
		return false
	if room_closed() and kind != KIND_SOLO:
		bot_director.remove_bots() # Solo's bots go with it: none is left to play a room alone (#505)
	var target: String = KIND_LOCAL if kind == KIND_LOCAL else KIND_ONLINE
	var dropped: int = _drop_seats_for(target) if target != _match_kind and not (_match_kind == KIND_SOLO and target == KIND_ONLINE) else 0
	if kind == KIND_SOLO and _match_kind == KIND_ONLINE:
		# Solo refuses phones and remote seats alike (#552): drop the live ones and
		# the held claims (#459), which would otherwise eat bot capacity.
		dropped += _drop_seats_for(KIND_LOCAL) + _drop_seats_for(KIND_ONLINE)
	_match_kind = kind
	if target == KIND_LOCAL:
		if _host_pc_slot != -1:
			_release_host_pc_seat()
		_set_online_requested(false)
		if relay_state() != RelayLinkScript.STATE_OFFLINE:
			go_offline() # the relay is never left up in a Couch match
	else:
		_set_host_pc_seat(true)
		_set_online_requested(kind == KIND_ONLINE) # Solo stays off the relay
		if kind == KIND_SOLO:
			bot_director.add_bots(maxi(0, SOLO_BOTS - bot_director.bot_count()))
			bot_director.counter_seated = true
	if dropped > 0:
		_kind_drop = {"kind": target, "count": dropped, "msec": Time.get_ticks_msec()}
	_send_lobby_to_all()
	return true

## How many bots the host's counter can seat right now: every seat that no
## human holds (#445).
func bot_capacity() -> int:
	return _slot_peers.size() - (claimed_slots().size() - bot_director.bot_count())

## Seats exactly `count` bots (clamped to 0..bot_capacity()): the newest go
## first when it is fewer. Returns the number seated (#445).
func set_bot_count(count: int) -> int:
	var wanted: int = clampi(count, 0, bot_capacity())
	var have: int = bot_director.bot_count()
	if wanted > have:
		bot_director.add_bots(wanted - have)
		bot_director.counter_seated = true
	while bot_director.bot_count() > wanted:
		var bots: Array[int] = virtual_slots()
		bot_director.remove_bot(bots[bots.size() - 1])
	_send_lobby_to_all()
	return bot_director.bot_count()

## Whether `peer` may not join this kind of match; a refused peer is closed.
func _refused_by_match_kind(peer: Variant) -> bool:
	var reason: String = ""
	if peer is WebSocketPeer and _match_kind == KIND_SOLO:
		reason = SOLO_MATCH_REASON
	elif peer is WebSocketPeer and _match_kind == KIND_ONLINE:
		reason = ONLINE_MATCH_REASON
	elif peer is RemoteSeat and _match_kind == KIND_LOCAL:
		reason = COUCH_MATCH_REASON
	elif peer is RemoteSeat and room_closed():
		reason = ROOM_CLOSED_REASON
	if reason.is_empty():
		return false
	peer.close(REFUSED_CODE, reason)
	refused_joins += 1
	if _log_input:
		print("controller refused: %s" % reason)
	return true

## Drops every seat the `target` kind refuses, and every held claim that is not a
## gamepad's: phones going Online, remote seats going Couch. Returns how many.
func _drop_seats_for(target: String) -> int:
	var dropped: int = 0
	var reason: String = ONLINE_MATCH_REASON if target == KIND_ONLINE else COUCH_MATCH_REASON
	for slot in _slot_peers.size():
		if _slot_claimed[slot] != 1 or _slot_virtual[slot] == 1:
			continue
		var peer: Variant = _slot_peers[slot]
		if peer is LocalSeat or _slot_client_id[slot].begins_with(PAD_ID_PREFIX) or _slot_client_id[slot] == HOST_PC_ID:
			continue
		if peer != null and not (target == KIND_ONLINE and peer is WebSocketPeer) and not (target == KIND_LOCAL and peer is RemoteSeat):
			continue
		if peer != null:
			peer.close(REFUSED_CODE, reason)
			_unbind(slot)
		_release_claim(slot)
		dropped += 1
	if target == KIND_ONLINE:
		for conn: PendingConn in _pending + _awaiting_id:
			conn.peer.close(REFUSED_CODE, reason)
		_pending.clear()
		_awaiting_id.clear()
	else:
		for seat: RemoteSeat in _remote_awaiting:
			seat.close(REFUSED_CODE, reason)
		_remote_awaiting.clear()
	if dropped > 0:
		_broadcast_looks()
	return dropped

# --- Holding a dropped remote seat (issue #459) -------------------------------
#
# A remote seat whose connection drops mid-match keeps its roster entry for
# REMOTE_SEAT_HOLD_MSEC of game time, across round boundaries too: the body goes
# limp as for any drop (ADR-0007), and the same client id coming back inside the
# window reclaims the slot with its score and looks, through `_bind_with_id()`'s
# ordinary reclaim. When the window lapses the claim is released at once, even
# mid-round: the body leaves the round the way a kicked player's does (the
# `host_command` "kick" signal, with no ban), and the id is not remembered as a
# recent leaver, so a later rejoin is a fresh seat. Game time (GameClock.gd)
# stops while the host has the match paused, so a pause never eats the window.
# Outside a match (lobby, countdown, victory) nothing is held: ADR-0007's "no
# round, no hold" stands, and REJOIN_GRACE_MSEC covers a quick lobby rejoin.

const GameClockScript459 := preload("res://scripts/GameClock.gd")
## How long a dropped remote seat is held mid-match, in game msec (issue #459).
## RemoteClient.gd keeps retrying its rejoin for the same window.
const REMOTE_SEAT_HOLD_MSEC: int = 30000
## The hold this host applies; a scenario whose wall-clock client must outlast
## a fast game clock raises it.
var remote_seat_hold_msec: int = REMOTE_SEAT_HOLD_MSEC

var _remote_claim: Dictionary = {} # slot -> true while its claim belongs to a remote seat
var _remote_dropped_msec: Dictionary = {} # slot -> game msec its remote seat dropped

func _note_remote_attach(slot: int, peer: Variant) -> void:
	_remote_dropped_msec.erase(slot)
	if peer is RemoteSeat:
		_remote_claim[slot] = true
	else:
		_remote_claim.erase(slot)

func _note_remote_drop(slot: int) -> void:
	if _remote_claim.has(slot) and _slot_claimed[slot] == 1:
		_remote_dropped_msec[slot] = GameClockScript459.now_msec()

func _in_match_phase() -> bool:
	return MATCH_PHASES.has(str(_lobby_state.get("phase", "")))

## Whether `slot` is a dropped remote seat still inside its hold (issue #459).
func remote_seat_held(slot: int) -> bool:
	if not _remote_dropped_msec.has(slot) or not _in_match_phase():
		return false
	return GameClockScript459.now_msec() - int(_remote_dropped_msec[slot]) < remote_seat_hold_msec

## Game msec left on `slot`'s hold, or -1 when it is not held.
func remote_seat_hold_left_msec(slot: int) -> int:
	if not remote_seat_held(slot):
		return -1
	return remote_seat_hold_msec - (GameClockScript459.now_msec() - int(_remote_dropped_msec[slot]))

## Every frame: a held seat whose window ran out mid-match is released now.
func _lapse_remote_holds() -> void:
	if _remote_dropped_msec.is_empty():
		return
	for slot: int in _remote_dropped_msec.keys():
		if remote_seat_held(slot):
			continue
		if not _in_match_phase():
			continue # expire_disconnected_claims() decides outside a match
		_remote_dropped_msec.erase(slot)
		if _slot_claimed[slot] != 1 or slot_has_controller(slot):
			continue
		var id: String = _slot_client_id[slot]
		_release_claim(slot)
		_recent_leavers.erase(id)
		_broadcast_looks()
		if _log_input:
			print("slot %d remote seat hold lapsed" % slot)
		host_command.emit("kick", slot)

# --- The host PC's own kick, pause and end match (issue #458) ------------------
#
# An Online host has no host phone (ADR-0021), so its own screen carries what
# the host phone's menu gives: a Kick on each player row (the lobby and the Esc
# menu) and Pause/Resume and End match in the Esc menu (`HostMatchMenu.gd`).
# They go out as the same `host_command`s the host phone's requests do.

## Whether the host PC runs the room itself and so shows those controls: an
## Online match (ADR-0021). For now that is Go online switched on.
func pc_runs_room() -> bool:
	if _match_kind != "":  # #435: a picked kind decides; unpicked keeps Go online
		return _match_kind == KIND_ONLINE or _match_kind == KIND_SOLO
	return _online_requested

## Whether a match is in play or paused: what Pause and End match act on.
func host_pc_match_live() -> bool:
	return MATCH_PHASES.has(str(_lobby_state.get("phase", "lobby"))) or host_pc_paused()

## Whether the match is paused, as the lobby state last said.
func host_pc_paused() -> bool:
	return bool(_lobby_state.get("paused", false))

## The host PC's "pause", "resume", "end" or "kick" of `slot`. Returns whether
## it was taken: Pause, Resume and End only while a match is live; a kick of
## any claimed seat but the host PC's own.
func host_pc_command(cmd: String, slot: int = -1) -> bool:
	match cmd:
		"pause", "resume", "end":
			if not host_pc_match_live():
				return false
			host_command.emit(cmd, -1)
			return true
		"kick":
			if not kick(slot, true):
				return false
			host_command.emit("kick", slot)
			return true
	return false

## Whether the host screen's Esc menu is open, when its clicks must not take
## the mouse back for the host PC's seat.
func _host_menu_open() -> bool:
	var menu: Node = get_node_or_null(^"/root/Sfx/SfxSettings")
	return menu != null and menu.has_method("is_open") and menu.is_open()
