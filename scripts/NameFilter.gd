extends RefCounted
## Issue #732: masks clearly offensive words in a player's nickname, so the
## shared screen, scoreboard and Steam timeline never show them. Static funcs
## only; consumers preload this script by path (no class_name).
##
## The word lists are base64 so the plain words are not in the repo text.
## Latin-script entries match a WHOLE word only (so "Scunthorpe", "Cassandra"
## and "Dickens" pass); entries in other scripts match as substrings, since
## those languages do not separate words with spaces. Matching looks at a
## normalised copy (lower case, leetspeak undone, accents dropped, repeated
## letters collapsed); the mask replaces the offending word with asterisks of
## the word's original length.

const WORDS_B64: String = "ZnVjawpmdWNrZXIKZnVja2VycwpmdWNraW5nCmZ1Y2tlZAptb3RoZXJmdWNrZXIKc2hpdApzaGl0dHkKYnVsbHNoaXQKYml0Y2gKYml0Y2hlcwpjdW50CmN1bnRzCm5pZ2dlcgpuaWdnZXJzCm5pZ2dhCm5pZ2dhcwpmYWdnb3QKZmFnZ290cwpmYWcKcmV0YXJkCnJldGFyZGVkCndob3JlCnNsdXQKYXNzaG9sZQpyYXBpc3QKc2NoZWlzc2UKYXJzY2hsb2NoCmZvdHplCmh1cmVuc29obgp3aWNoc2VyCm1lcmRlCnB1dGFpbgpjb25uYXJkCmNvbm5hc3NlCnNhbG9wZQplbmN1bGUKcGVuZGVqbwpjYWJyb24KbWllcmRhCmpvZGVyCnB1dGEKcHV0bwpjYXJhbGhvCmJ1Y2V0YQo="
const SUBSTRING_WORDS_B64: String = "0LHQu9GP0YLRjArRgdGD0LrQsArRhdGD0LkK0L/QuNC30LTQsArslKjrsJwK6rCc7IOI64G8CuWCu+mAvArmk43kvaDlpogK44Gh44KT44G9Cg=="

const LEET: Dictionary = {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s"}
const ACCENTS: Dictionary = {"é": "e", "è": "e", "ê": "e", "ë": "e", "á": "a", "à": "a", "â": "a", "ä": "a", "ã": "a", "í": "i", "ï": "i", "ó": "o", "ö": "o", "ô": "o", "õ": "o", "ú": "u", "ü": "u", "ñ": "n", "ç": "c", "ß": "ss"}

static var _latin: PackedStringArray = PackedStringArray()
static var _other: PackedStringArray = PackedStringArray()

static func _load() -> void:
	if not _latin.is_empty():
		return
	for w: String in Marshalls.base64_to_utf8(WORDS_B64).split("\n", false):
		_latin.append(_squash(_normalise(w)))
	for w: String in Marshalls.base64_to_utf8(SUBSTRING_WORDS_B64).split("\n", false):
		_other.append(w)

## Lower case, leetspeak and accents undone. For matching only.
static func _normalise(word: String) -> String:
	var out: String = ""
	for ch: String in word.to_lower():
		if LEET.has(ch):
			out += LEET[ch]
		elif ACCENTS.has(ch):
			out += ACCENTS[ch]
		else:
			out += ch
	return out

## Runs of one letter collapsed to a single letter.
static func _squash(word: String) -> String:
	var out: String = ""
	for ch: String in word:
		if out.is_empty() or out[out.length() - 1] != ch:
			out += ch
	return out

static func _is_word_char(ch: String) -> bool:
	return ch == "@" or ch == "$" or ch.unicode_at(0) > 127 or (ch >= "0" and ch <= "9") or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z")

## True when `name` holds a listed word.
static func is_offensive(name: String) -> bool:
	return mask(name) != name

## `name` with each offending word replaced by asterisks of its length.
static func mask(name: String) -> String:
	_load()
	var out: String = ""
	var word: String = ""
	for i in name.length() + 1:
		var ch: String = name[i] if i < name.length() else " "
		if i < name.length() and _is_word_char(ch):
			word += ch
			continue
		out += _mask_word(word) + (ch if i < name.length() else "")
		word = ""
	return out

static func _mask_word(word: String) -> String:
	if word.is_empty():
		return word
	if _latin.has(_squash(_normalise(word))):
		return "*".repeat(word.length())
	var lowered: String = word.to_lower()
	for bad: String in _other:
		if lowered.contains(bad):
			lowered = lowered.replace(bad, "*".repeat(bad.length()))
	if lowered == word.to_lower():
		return word
	var result: String = ""
	for j in word.length():
		result += "*" if lowered[j] == "*" else word[j]
	return result
