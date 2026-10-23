extends RefCounted
## The "Phones can't join?" popup's contents (#680): a short checklist of the
## usual reasons a phone cannot reach the host, and every address the host
## serves on, so a player can type another one when the QR's first address does
## not work. Static text only: nothing here probes the network.
##
## Built into the card `LobbyPopups` gives it; `set_urls()` refreshes the list
## and hides it while streamer mode (Hide room code) is on.

const ScreenKitScript := preload("res://scripts/ScreenKit.gd")
const UiThemeScript := preload("res://scripts/UiTheme.gd")

const CARD_WIDTH_PX: float = 920.0
## The checklist, one line per cause (translation keys).
const CHECK_KEYS: PackedStringArray = [
	"JOIN_HELP_FIREWALL",
	"JOIN_HELP_ISOLATION",
	"JOIN_HELP_ADAPTER",
	"JOIN_HELP_PHONE_NETWORK",
	"JOIN_HELP_HOTSPOT",
]

var _screen # the LobbyScreen, for tr()
var _built: bool = false
var _close_button: Button
var _url_box: VBoxContainer
var _url_head: Label
var _url_labels: Array[Label] = []
var _urls: PackedStringArray = PackedStringArray()
var _hidden: bool = false
## The "Join over the internet instead" fallback (#683, ADR-0025).
var _net_button: Button
var _net_stop: Button
var _net_live: HBoxContainer
var _net_qr: TextureRect
var _net_status: Label
var _net_url: Label
var _net_room: Label

func _init(screen) -> void:
	_screen = screen

func is_built() -> bool:
	return _built

## Builds the contents into `card`. `on_close` runs when the X is pressed.
func build(card: Control, on_close: Callable) -> void:
	if _built:
		return
	_built = true
	var box := VBoxContainer.new()
	box.name = "JoinHelp"
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)
	var head := HBoxContainer.new()
	head.name = "Head"
	box.add_child(head)
	var title: Label = ScreenKitScript.themed_label(_screen.tr("JOIN_HELP_TITLE"), 46, UiThemeScript.INK_HEADING_LABEL)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_close_button = ScreenKitScript.themed_button("X", UiThemeScript.YELLOW_BUTTON, "Close")
	_close_button.custom_minimum_size = Vector2(56, 56)
	_close_button.focus_mode = Control.FOCUS_ALL
	_close_button.pressed.connect(on_close)
	head.add_child(_close_button)
	for i in CHECK_KEYS.size():
		var line: Label = ScreenKitScript.themed_label(_screen.tr(CHECK_KEYS[i]), 22, UiThemeScript.INK_BOLD_LABEL)
		line.name = "Check%d" % i
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(line)
	var rule_box := PanelContainer.new()
	rule_box.name = "UrlBox"
	rule_box.theme_type_variation = UiThemeScript.RULE_BOX
	box.add_child(rule_box)
	_url_box = VBoxContainer.new()
	_url_box.name = "Urls"
	_url_box.add_theme_constant_override("separation", 4)
	rule_box.add_child(_url_box)
	_url_head = ScreenKitScript.themed_label("", 22, UiThemeScript.INK_BOLD_LABEL)
	_url_head.name = "UrlHead"
	_url_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_url_box.add_child(_url_head)
	_rebuild_urls()
	_build_internet(box)

## The internet fallback: a button, then (once pressed) the QR, the short link,
## the room code and a Stop control. Every button takes focus for the pad.
func _build_internet(box: VBoxContainer) -> void:
	var net := VBoxContainer.new()
	net.name = "Internet"
	net.add_theme_constant_override("separation", 10)
	box.add_child(net)
	var note: Label = ScreenKitScript.themed_label(_screen.tr("JOIN_NET_NOTE"), 22, UiThemeScript.INK_BOLD_LABEL)
	note.name = "NetNote"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	net.add_child(note)
	_net_button = ScreenKitScript.themed_button(_screen.tr("JOIN_NET_BUTTON"), UiThemeScript.ACTION_BUTTON, "JoinInternetButton")
	_net_button.focus_mode = Control.FOCUS_ALL
	_net_button.pressed.connect(_set_internet.bind(true))
	net.add_child(_net_button)
	_net_live = HBoxContainer.new()
	_net_live.name = "NetLive"
	_net_live.add_theme_constant_override("separation", 20)
	_net_live.visible = false
	net.add_child(_net_live)
	_net_qr = TextureRect.new()
	_net_qr.name = "NetQr"
	_net_qr.custom_minimum_size = Vector2(220, 220)
	_net_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_net_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_net_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_net_live.add_child(_net_qr)
	var side := VBoxContainer.new()
	side.name = "NetSide"
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 6)
	_net_live.add_child(side)
	_net_status = ScreenKitScript.themed_label("", 22, UiThemeScript.INK_BOLD_LABEL)
	_net_status.name = "NetStatus"
	side.add_child(_net_status)
	_net_url = ScreenKitScript.themed_label("", 20, UiThemeScript.INK_HEADING_LABEL)
	_net_url.name = "NetUrl"
	_net_url.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	side.add_child(_net_url)
	_net_room = ScreenKitScript.themed_label("", 40, UiThemeScript.INK_HEADING_LABEL)
	_net_room.name = "NetRoom"
	side.add_child(_net_room)
	_net_stop = ScreenKitScript.themed_button(_screen.tr("JOIN_NET_STOP"), UiThemeScript.ACTION_BUTTON, "StopInternetButton")
	_net_stop.focus_mode = Control.FOCUS_ALL
	_net_stop.pressed.connect(_set_internet.bind(false))
	side.add_child(_net_stop)

func _set_internet(on: bool) -> void:
	var server: Object = _screen._server
	if server != null:
		server.apply_host_command("internet", on)
		refresh_internet(server)

func internet_button() -> Button:
	return _net_button

func internet_stop_button() -> Button:
	return _net_stop

## The shown link, room code and status of the internet fallback ("" when off or hidden).
func internet_url_text() -> String:
	return _net_url.text if _net_url != null else ""

func internet_room_text() -> String:
	return _net_room.text if _net_room != null else ""

func internet_qr_visible() -> bool:
	return _net_qr != null and _net_qr.visible

func internet_live_visible() -> bool:
	return _net_live != null and _net_live.visible

## Redraws the fallback block from `server` (streamer mode hides the link,
## QR and code, as it does the LAN addresses).
func refresh_internet(server: Object) -> void:
	if not _built or server == null or not server.has_method("internet_join_on"):
		return
	var on: bool = server.internet_join_on()
	_net_live.visible = on
	if not on:
		return
	var status: String = server.internet_join_status()
	_net_status.text = {"connecting": _screen.tr("ONLINE_CONNECTING"), "unreachable": _screen.tr("ONLINE_UNREACHABLE")}.get(status, _screen.tr("JOIN_NET_OPEN"))
	var code: String = server.internet_join_room()
	var hidden: bool = _hidden
	_net_qr.texture = server.internet_join_qr_texture() if not hidden else null
	_net_qr.visible = _net_qr.texture != null
	_net_url.text = _screen.tr("ROOM_CODE_HIDDEN") if hidden else server.internet_join_url()
	_net_room.text = "" if hidden or code.is_empty() else _screen.tr("ONLINE_ROOM") % code
	_net_room.visible = _net_room.text != ""

func close_button() -> Button:
	return _close_button

## The address labels showing now (none while hidden or with no address).
func url_labels() -> Array[Label]:
	return _url_labels

## The heading over the address list: how to use it, or why it is empty or hidden.
func url_heading() -> String:
	return _url_head.text if _url_head != null else ""

## Sets the addresses to list (`ControllerServer.join_urls()`) and whether
## streamer mode hides them.
func set_urls(urls: PackedStringArray, hidden: bool) -> void:
	if urls == _urls and hidden == _hidden:
		# The lobby calls this every frame: keep the labels, only refresh the
		# heading (a language change retranslates it).
		if _built:
			_url_head.text = _heading_text()
		return
	_urls = urls
	_hidden = hidden
	if _built:
		_rebuild_urls()

func _rebuild_urls() -> void:
	for label: Label in _url_labels:
		_url_box.remove_child(label)
		label.queue_free()
	_url_labels.clear()
	_url_head.text = _heading_text()
	if _hidden or _urls.is_empty():
		return
	for i in _urls.size():
		var label: Label = ScreenKitScript.themed_label(_urls[i], 24, UiThemeScript.INK_HEADING_LABEL)
		label.name = "Url%d" % i
		_url_box.add_child(label)
		_url_labels.append(label)

## The heading over the address list for the current state.
func _heading_text() -> String:
	if _hidden:
		return _screen.tr("ROOM_CODE_HIDDEN")
	if _urls.is_empty():
		return _screen.tr("JOIN_HELP_NO_ADDRESS")
	return _screen.tr("JOIN_HELP_ADDRESSES")
