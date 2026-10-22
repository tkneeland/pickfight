extends RefCounted

## The languages the host screen speaks (issue #688), and how the Language
## setting in the Settings panel turns into a `TranslationServer` locale.
##
## `OPTIONS` is the whole list: the picker shows each entry's own `name` and
## `HostSettings.language` stores its `code`. A new language is one more entry
## here, one more column in `translations/strings.csv` headed by the same
## `code`, and its `.translation` file in `project.godot`'s
## `internationalization/locale/translations`. The phone page keeps its own
## table (`controller/index.html`). Preloaded by path, never `class_name`.

## The stored value for "follow the operating system".
const AUTO: String = "auto"
## Used when the system language is not on offer.
const FALLBACK: String = "en"
## `code` is a Godot locale code and the strings.csv column header; `name` is
## the language written in itself, so it reads in any current language.
const OPTIONS: Array[Dictionary] = [
	{"code": "en", "name": "English"},
	{"code": "de", "name": "Deutsch"},
	{"code": "fr", "name": "Français"},
	{"code": "es", "name": "Español (Latinoamérica)"},
	{"code": "pt_BR", "name": "Português (Brasil)"},
	{"code": "zh_CN", "name": "简体中文"},
	{"code": "ja", "name": "日本語"},
	{"code": "ko", "name": "한국어"},
	{"code": "ru", "name": "Русский"},
]

static func codes() -> PackedStringArray:
	var out := PackedStringArray()
	for option: Dictionary in OPTIONS:
		out.append(str(option["code"]))
	return out

## Whether `setting` is a value the store accepts: Auto or one of the options.
static func is_valid(setting: String) -> bool:
	return setting == AUTO or codes().has(setting)

## The option code `setting` means, given the operating system's locale
## (`OS.get_locale()`, e.g. "de_AT" or "pt-PT"). Auto matches on the language
## part alone and falls back to English. Chinese is Simplified only: zh_CN,
## zh_SG and zh_Hans* match; zh_TW, zh_HK and zh_Hant* fall back to English.
static func resolve(setting: String, os_locale: String) -> String:
	if setting != AUTO:
		return setting if codes().has(setting) else FALLBACK
	var parts: PackedStringArray = os_locale.replace("-", "_").split("_")
	var language: String = parts[0].to_lower()
	if language == "zh":
		var region: String = parts[1].to_lower() if parts.size() > 1 else ""
		var simplified: bool = region == "cn" or region == "sg" or region == "hans"
		for part: String in parts:
			if part.to_lower() == "hans":
				simplified = true
			elif part.to_lower() == "hant":
				simplified = false
		return "zh_CN" if simplified else FALLBACK
	for code: String in codes():
		if code.split("_")[0].to_lower() == language:
			return code
	return FALLBACK

## The bundled UI fonts (Lilita One, Nunito) have no CJK glyphs. Godot's own
## system-font fallback finds kana and Hangul but not Han characters, so each
## bundled font gets an explicit chain of system fonts, the current language's
## first (the same Han character is drawn differently in zh and ja). macOS's
## PingFang SC cannot be loaded by name (FreeType errors), so it is left out.
## Ahead of the system fonts sits the language's own bundled Noto Sans subset
## (built by tools/subset_cjk_font.py from strings.csv, #849), so a machine with
## no CJK system font still draws every translated string; the system chain stays
## after it for player names typed on phones, which can hold any character.
const BUNDLED_FONTS: PackedStringArray = [
	"res://art/fonts/LilitaOne-Regular.ttf",
	"res://art/fonts/Nunito-Variable.ttf",
]
const CJK_SUBSETS: Dictionary = {
	"zh_CN": "res://art/fonts/NotoSansSC-Subset.ttf",
	"ja": "res://art/fonts/NotoSansJP-Subset.ttf",
	"ko": "res://art/fonts/NotoSansKR-Subset.ttf",
}
const FALLBACK_NAMES_ZH: PackedStringArray = ["Hiragino Sans GB", "Microsoft YaHei", "Noto Sans CJK SC", "Noto Sans SC", "WenQuanYi Micro Hei", "Heiti SC", "Arial Unicode MS"]
const FALLBACK_NAMES_JA: PackedStringArray = ["Hiragino Sans", "Yu Gothic", "Meiryo", "Noto Sans CJK JP", "Noto Sans JP", "TakaoPGothic"]
const FALLBACK_NAMES_KO: PackedStringArray = ["Apple SD Gothic Neo", "Malgun Gothic", "Noto Sans CJK KR", "Noto Sans KR", "NanumGothic"]

## System font names to try for `code`, its own language first. Empty for the
## languages the bundled fonts and Godot's own fallback already cover (a chain
## adds line height, so it is only worth having where Han characters appear).
static func fallback_font_names(code: String) -> PackedStringArray:
	if code != "zh_CN" and code != "ja" and code != "ko":
		return PackedStringArray()
	var order: Array[PackedStringArray] = [FALLBACK_NAMES_JA, FALLBACK_NAMES_ZH, FALLBACK_NAMES_KO]
	if code == "zh_CN":
		order = [FALLBACK_NAMES_ZH, FALLBACK_NAMES_JA, FALLBACK_NAMES_KO]
	elif code == "ko":
		order = [FALLBACK_NAMES_KO, FALLBACK_NAMES_ZH, FALLBACK_NAMES_JA]
	var out := PackedStringArray()
	for names: PackedStringArray in order:
		out.append_array(names)
	return out

## The fallback chain for `code`: its bundled CJK subset (if any), then the
## installed system fonts from `fallback_font_names`. Empty for non-CJK codes.
static func fallback_chain(code: String) -> Array[Font]:
	var chain: Array[Font] = []
	var subset: FontFile = _cjk_subset(code)
	if subset != null:
		chain.append(subset)
	var installed: PackedStringArray = OS.get_system_fonts()
	for font_name: String in fallback_font_names(code):
		if not installed.has(font_name):
			continue # a SystemFont with no match errors on every use
		var system := SystemFont.new()
		system.font_names = PackedStringArray([font_name])
		chain.append(system)
	return chain

static func _cjk_subset(code: String) -> FontFile:
	return load(CJK_SUBSETS[code]) if CJK_SUBSETS.has(code) else null

## Points the bundled fonts' fallbacks at the bundled CJK subset and the system
## fonts for `code`.
static func apply_fonts(code: String) -> void:
	var chain: Array[Font] = fallback_chain(code)
	for path: String in BUNDLED_FONTS:
		var font: FontFile = load(path)
		if font != null:
			font.allow_system_fallback = true
			font.fallbacks = chain

## A font for the Language picker's popup, which lists 简体中文, 日本語 and 한국어
## in every locale: `base` with the current language's chain (`code`), then the
## other bundled subsets, Japanese first so 日本語 is drawn in one style. A
## FontVariation's own fallbacks replace its base's, hence the full chain here.
## Only the popup uses it (the closed row shows the current language's own name,
## which its chain already covers), so other text keeps its line height.
static func picker_font(base: Font, code: String) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = base
	var chain: Array[Font] = fallback_chain(code)
	for other: String in ["ja", "zh_CN", "ko"]:
		var subset: FontFile = _cjk_subset(other)
		if subset != null and not chain.has(subset):
			chain.append(subset)
	font.fallbacks = chain
	return font

## Sets the live locale from `setting`. Returns the locale it chose.
static func apply(setting: String) -> String:
	var code: String = resolve(setting, OS.get_locale())
	TranslationServer.set_locale(code)
	apply_fonts(code)
	return code
