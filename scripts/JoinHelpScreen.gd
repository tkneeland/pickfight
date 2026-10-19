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
	_urls = urls
	_hidden = hidden
	if _built:
		_rebuild_urls()

func _rebuild_urls() -> void:
	for label: Label in _url_labels:
		_url_box.remove_child(label)
		label.queue_free()
	_url_labels.clear()
	if _hidden:
		_url_head.text = _screen.tr("ROOM_CODE_HIDDEN")
		return
	if _urls.is_empty():
		_url_head.text = _screen.tr("JOIN_HELP_NO_ADDRESS")
		return
	_url_head.text = _screen.tr("JOIN_HELP_ADDRESSES")
	for i in _urls.size():
		var label: Label = ScreenKitScript.themed_label(_urls[i], 24, UiThemeScript.INK_HEADING_LABEL)
		label.name = "Url%d" % i
		_url_box.add_child(label)
		_url_labels.append(label)
