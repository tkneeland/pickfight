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
## part alone and falls back to English.
static func resolve(setting: String, os_locale: String) -> String:
	if setting != AUTO:
		return setting if codes().has(setting) else FALLBACK
	var language: String = os_locale.replace("-", "_").split("_")[0].to_lower()
	for code: String in codes():
		if code.split("_")[0].to_lower() == language:
			return code
	return FALLBACK

## Sets the live locale from `setting`. Returns the locale it chose.
static func apply(setting: String) -> String:
	var code: String = resolve(setting, OS.get_locale())
	TranslationServer.set_locale(code)
	return code
