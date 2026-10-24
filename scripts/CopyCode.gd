extends RefCounted
## The Copy code button's shared logic (#863 host, #1033 joiner): what a press
## does, how long it reads "Copied", and which translation key it shows. The
## host lobby (`HostControls.gd`) and the PC client's lobby (`RemoteClient.gd`)
## both call it, so label, timing and keys never drift. No `class_name`:
## consumers preload this by path.

## How long Copy code reads "Copied" after a press.
const COPIED_MSEC: int = 1500

## Puts `code` on the clipboard through `setter` (a seam so scenarios never
## touch the real one) and schedules `refresh` for when "Copied" lapses.
## Returns the tick (msec) until which the button reads "Copied".
static func press(code: String, setter: Callable, tree: SceneTree, refresh: Callable) -> int:
	setter.call(code)
	tree.create_timer(COPIED_MSEC / 1000.0 + 0.05).timeout.connect(refresh)
	return Time.get_ticks_msec() + COPIED_MSEC

## The translation key the button's caption uses now. `key_hint` is the host's
## "(K)" variant; the joiner has no key for it and passes false.
static func caption_key(copied_until_msec: int, key_hint: bool) -> String:
	if Time.get_ticks_msec() < copied_until_msec:
		return "LOBBY_COPIED"
	return "LOBBY_COPY_CODE" if key_hint else "LOBBY_COPY_CODE_PAD"
