extends Control

## The kill feed (issue #148): a ticker of KOs down the top right of the
## shared screen, below the join QR code, and a banner across the middle for
## the big moments (first blood, a double KO, the last one standing).
##
## Display only: `RoundManager` decides who got a KO (`MatchStats.gd`) and
## tells this node what to show, with names and colours already resolved.
## Lives on the HUD canvas layer in scenes/Main.tscn. Also builds the award
## cards the victory screen shows under the podium (`award_cards()`).

## Most entries on the ticker at once; the oldest goes when a new one arrives.
## Eight players make at most seven KOs a round, and five fit between the QR
## code and the round-end scoreboard.
const MAX_ENTRIES: int = 5
## How long an entry stays, the last `ENTRY_FADE_SEC` of it fading out.
const ENTRY_SEC: float = 6.0
const ENTRY_FADE_SEC: float = 1.0
## How long one banner stays up. Banners that arrive together queue.
const BANNER_SEC: float = 1.8
## Most banners waiting at once; older ones are dropped past this.
const MAX_QUEUED_BANNERS: int = 3
## Most entries `banner_log` keeps (issue #200): the newest this many, so a
## long session's log cannot grow without limit.
const MAX_BANNER_LOG: int = 32
## Gap above the ticker. The in-round join corner is gone (#430), so it hugs
## the top of the screen (issue #444).
const FEED_TOP_PX: float = 20.0
const FEED_MARGIN_PX: float = 16.0
const FEED_FONT: int = 20
## The banner's top edge, as a fraction of the screen's height: under the
## round-end scoreboard (centred) and clear of the modifier banner and the
## stage title card higher up.
const BANNER_ANCHOR: float = 0.63
const BANNER_HEADLINE_FONT: int = 64
const BANNER_NAME_FONT: int = 40
const ACCENT: Color = Color(1.0, 0.85, 0.2, 1.0)
## The theme look (#548): ticker entries and victory cards sit on indigo plates
## with an ink outline and a hard shadow; text is cream, the accent or the
## player's colour.
const UiThemeScript := preload("res://scripts/UiTheme.gd")
const PLATE_FILL: Color = UiThemeScript.INDIGO_PANEL
## Victory cards and the stats table hold small coloured text, so they take a
## darker plate than the ticker for contrast against every player colour.
const CARD_FILL: Color = Color("171B2E")
const MUTED_TEXT: Color = Color("C9CCE0")

var _feed: VBoxContainer
var _banner: VBoxContainer
var _banner_headline: Label
var _banner_name: Label
var _banner_left: float = 0.0
var _banner_queue: Array[Dictionary] = []
## The banners asked for, as "HEADLINE|name", oldest first, for the
## scenarios: the last MAX_BANNER_LOG of them.
var banner_log: PackedStringArray = PackedStringArray()

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed = VBoxContainer.new()
	_feed.name = "Feed"
	_feed.anchor_left = 1.0
	_feed.anchor_right = 1.0
	_feed.offset_left = -FEED_MARGIN_PX
	_feed.offset_right = -FEED_MARGIN_PX
	_feed.offset_top = FEED_TOP_PX
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_theme_constant_override("separation", 4)
	add_child(_feed)
	_banner = VBoxContainer.new()
	_banner.name = "Banner"
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.anchor_top = BANNER_ANCHOR
	_banner.anchor_bottom = BANNER_ANCHOR
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_constant_override("separation", 0)
	_banner_headline = _label("", BANNER_HEADLINE_FONT, ACCENT, true)
	_banner_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_headline)
	_banner_name = _label("", BANNER_NAME_FONT, UiThemeScript.CREAM, true)
	_banner_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_name)
	_banner.visible = false
	add_child(_banner)

func _process(delta: float) -> void:
	for entry: Node in _feed.get_children():
		var age: float = float(entry.get_meta("age", 0.0)) + delta
		entry.set_meta("age", age)
		if age >= ENTRY_SEC:
			_feed.remove_child(entry)
			entry.queue_free()
		elif age > ENTRY_SEC - ENTRY_FADE_SEC:
			(entry as CanvasItem).modulate.a = (ENTRY_SEC - age) / ENTRY_FADE_SEC
	if _banner.visible:
		_banner_left -= delta
		if _banner_left <= 0.0:
			_banner.visible = false
	if not _banner.visible and not _banner_queue.is_empty():
		_show_next_banner()

## A KO on the ticker: "killer KO victim", or "victim self-KO" when
## `killer_name` is empty.
func push_ko(killer_name: String, killer_color: Color, victim_name: String, victim_color: Color) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiThemeScript.plate(PLATE_FILL, 12, 1, true, 8))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	if killer_name.is_empty():
		row.add_child(_label(victim_name, FEED_FONT, victim_color, true))
		row.add_child(_label(tr("FEED_SELF_KO"), FEED_FONT, MUTED_TEXT))
	else:
		row.add_child(_label(killer_name, FEED_FONT, killer_color, true))
		row.add_child(_label(tr("FEED_KO"), FEED_FONT, ACCENT, true))
		row.add_child(_label(victim_name, FEED_FONT, victim_color, true))
	panel.set_meta("age", 0.0)
	_feed.add_child(panel)
	while _feed.get_child_count() > MAX_ENTRIES:
		var oldest: Node = _feed.get_child(0)
		_feed.remove_child(oldest)
		oldest.queue_free()

## A big moment across the middle: `headline` in the accent colour over
## `who` in their colour. Queued behind any banner already up.
func show_banner(headline: String, who: String, color: Color) -> void:
	_banner_queue.append({"headline": headline, "who": who, "color": color})
	banner_log.append("%s|%s" % [headline, who])
	if banner_log.size() > MAX_BANNER_LOG:
		banner_log = banner_log.slice(banner_log.size() - MAX_BANNER_LOG)
	while _banner_queue.size() > MAX_QUEUED_BANNERS:
		_banner_queue.pop_front()
	if not _banner.visible:
		_show_next_banner()

## Empties the ticker and the banner (a new match).
func clear() -> void:
	for entry: Node in _feed.get_children():
		_feed.remove_child(entry)
		entry.queue_free()
	_banner_queue.clear()
	_banner.visible = false

## Drops the banner up and any waiting (a new round, the victory screen).
func clear_banners() -> void:
	_banner_queue.clear()
	_banner.visible = false

## The ticker's lines as plain text, oldest first, for the scenarios.
func entries() -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Node in _feed.get_children():
		var words := PackedStringArray()
		for label: Node in entry.get_child(0).get_children():
			words.append((label as Label).text)
		out.append(" ".join(words))
	return out

func feed() -> Control:
	return _feed

func banner() -> Control:
	return _banner

func _show_next_banner() -> void:
	var next: Dictionary = _banner_queue.pop_front()
	_banner_headline.text = next["headline"]
	_punch_banner()
	_banner_name.text = next["who"]
	_banner_name.add_theme_color_override("font_color", next["color"])
	_banner_name.visible = not str(next["who"]).is_empty()
	_banner.visible = true
	_banner_left = BANNER_SEC

## The banner flashes in light (#548): bright, settling over a fifth of a
## second. Colour only: a scale pop would push its rect past the screen edge.
func _punch_banner() -> void:
	if not is_inside_tree():
		return
	_banner.modulate = Color(1.7, 1.7, 1.7, 1.0)
	var tween: Tween = create_tween()
	tween.tween_property(_banner, "modulate", Color.WHITE, 0.2)

## Draws a plate behind `node`, `grow` px past its edges, so a plain container
## gets the panel look without a wrapper node changing its child layout.
static func plate_behind(node: Control, grow: float = 10.0) -> void:
	var style: StyleBoxFlat = UiThemeScript.plate(CARD_FILL, 0, 0, true, 12)
	node.draw.connect(func() -> void:
		node.draw_style_box(style, Rect2(Vector2(-grow, -grow * 0.5), node.size + Vector2(grow * 2.0, grow))))

## One card per award, side by side, for the victory screen: the category
## small, the award's title, then the winner's name in their colour and what
## they did. `name_of` and `color_of` map a slot to its name and colour.
static func award_cards(awards: Array, name_of: Callable, color_of: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Awards"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 48 if awards.size() <= 3 else (32 if awards.size() <= 4 else 12))
	var who_size: int = 20 if awards.size() <= 4 else 14 # six cards must fit 1600 px (#613)
	for award: Dictionary in awards:
		var card := VBoxContainer.new()
		card.name = "Award" + str(award["category"]).capitalize()
		card.add_theme_constant_override("separation", 0)
		plate_behind(card)
		var category: Label = _label(TranslationServer.translate("AWARD_CATEGORY_" + str(award["category"])), 18 if awards.size() <= 4 else 14, MUTED_TEXT)
		category.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(category)
		var title: Label = _label(str(award["title"]), 30 if awards.size() <= 4 else 20, ACCENT, true)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(title)
		var slot: int = int(award["slot"])
		var who: Label = _label("%s  -  %s" % [str(name_of.call(slot)).left(10), award["detail"]], who_size, color_of.call(slot))
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(who)
		row.add_child(card)
	return row

## The per-player stats table for the victory screen (issue #325): one line per
## row of `MatchStats.stat_rows()` -- name, KOs, damage dealt/taken, self-KOs,
## pickups and favourite weapon. Five or more players split into two columns
## so eight still fit under the podium.
static func stat_table(rows: Array, name_of: Callable, color_of: Callable) -> HBoxContainer:
	var table := HBoxContainer.new()
	table.name = "StatRows"
	table.alignment = BoxContainer.ALIGNMENT_CENTER
	table.add_theme_constant_override("separation", 56)
	var per_column: int = rows.size() if rows.size() <= 4 else (rows.size() + 1) / 2
	var column: VBoxContainer = null
	for i in rows.size():
		if i % per_column == 0:
			column = VBoxContainer.new()
			column.add_theme_constant_override("separation", 0)
			plate_behind(column, 12.0)
			table.add_child(column)
		var row: Dictionary = rows[i]
		var slot: int = int(row["slot"])
		var line: Label = _label(TranslationServer.translate("STATS_LINE") % [
			str(name_of.call(slot)).left(10), row["kos"], row["damage_dealt"], row["damage_taken"],
			row["self_kos"], row["pickups"], row["weapon"] if row["weapon"] != "" else "-"], 16, color_of.call(slot))
		line.name = "Stats%d" % slot
		column.add_child(line)
	return table

static func _label(text: String, font_size: int, color: Color, heading: bool = false) -> Label:
	var label := Label.new()
	label.theme_type_variation = UiThemeScript.HUD_HEADING_LABEL if heading else UiThemeScript.HUD_LABEL
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	# Body text sits on a plate, so only headings carry the ink outline.
	label.add_theme_constant_override("outline_size", maxi(3, font_size / 8) if heading else 0)
	return label
