extends RefCounted

## In-process QR code encoder (issue #214), so the lobby's join QR no longer
## needs the `qrencode` tool on the host.
##
## ISO/IEC 18004 model 2, byte mode only, versions 1-10, error correction L or
## M. That covers any join URL many times over: the longest realistic one,
## `http://255.255.255.255:65535/` (29 bytes), is a version 3 symbol at M.
## The structure follows Project Nayuki's QR Code generator (MIT, see
## CREDITS.md); the mask penalty follows ISO 18004 section 7.8.3 as
## python-qrcode 8.2 scores it, so both pick the same mask.
##
## A subtly wrong matrix still looks like a QR code but does not scan, so the
## scenario `qr_encoder_matches_reference_matrices` checks whole matrices
## against fixtures captured from python-qrcode (tools/qr_fixtures.txt,
## made by tools/gen_qr_fixtures.py).
##
## Static only; load it by path (never `class_name`):
##   const QrEncoderScript := preload("res://scripts/QrEncoder.gd")
##   var qr: Dictionary = QrEncoderScript.encode("http://192.168.1.42:8080/")
##   var image: Image = QrEncoderScript.to_image(qr, 8, 2)

const ECL_L: int = 0
const ECL_M: int = 1
const MIN_VERSION: int = 1
const MAX_VERSION: int = 10

## Indexed [ecl][version]; index 0 unused. ISO 18004 table 9.
const ECC_CODEWORDS_PER_BLOCK: Array = [
	[-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18],
	[-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26],
]
const NUM_ERROR_CORRECTION_BLOCKS: Array = [
	[-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4],
	[-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5],
]
## The two format-information bits for each level (L = 01, M = 00).
const ECL_FORMAT_BITS: PackedInt32Array = [1, 0]

## Encodes `text` as UTF-8 bytes in the smallest version that fits at `ecl`.
## Returns {"version", "size", "mask", "ecl", "modules"}, `modules` being
## row-major, 1 = dark; or an empty Dictionary when the text is too long.
## `force_mask` 0-7 skips the penalty search (for tests).
static func encode(text: String, ecl: int = ECL_M, force_mask: int = -1) -> Dictionary:
	var data: PackedByteArray = text.to_utf8_buffer()
	var version: int = -1
	for v in range(MIN_VERSION, MAX_VERSION + 1):
		var count_bits: int = 8 if v < 10 else 16
		if 4 + count_bits + data.size() * 8 <= _num_data_codewords(v, ecl) * 8:
			version = v
			break
	if version < 0:
		return {}

	# Segment: byte mode (0100), character count, the bytes.
	var bits: PackedByteArray = PackedByteArray()
	_append_bits(bits, 0x4, 4)
	_append_bits(bits, data.size(), 8 if version < 10 else 16)
	for b in data:
		_append_bits(bits, b, 8)
	var capacity_bits: int = _num_data_codewords(version, ecl) * 8
	_append_bits(bits, 0, mini(4, capacity_bits - bits.size())) # terminator
	_append_bits(bits, 0, (8 - bits.size() % 8) % 8)
	var pad: int = 0xEC
	while bits.size() < capacity_bits:
		_append_bits(bits, pad, 8)
		pad ^= 0xEC ^ 0x11
	var codewords: PackedByteArray = PackedByteArray()
	codewords.resize(bits.size() / 8)
	for i in bits.size():
		codewords[i >> 3] |= bits[i] << (7 - (i & 7))

	var size: int = version * 4 + 17
	var modules: PackedByteArray = PackedByteArray()
	modules.resize(size * size)
	var is_function: PackedByteArray = PackedByteArray()
	is_function.resize(size * size)
	_draw_function_patterns(modules, is_function, size, version, ecl)
	_draw_codewords(modules, is_function, size, _add_ecc_and_interleave(codewords, version, ecl))

	var mask: int = force_mask
	if mask < 0:
		# Scored with the format and version areas (and the dark module) all
		# light, as python-qrcode scores them, so both pick the same mask.
		_draw_format_bits(modules, is_function, size, ecl, 0, true)
		_draw_version_bits(modules, is_function, size, version, true)
		var best_penalty: int = -1
		for m in 8:
			_apply_mask(modules, is_function, size, m)
			var penalty: int = penalty_score(modules, size)
			if best_penalty < 0 or penalty < best_penalty:
				best_penalty = penalty
				mask = m
			_apply_mask(modules, is_function, size, m) # XOR again undoes it
	_apply_mask(modules, is_function, size, mask)
	_draw_format_bits(modules, is_function, size, ecl, mask)
	_draw_version_bits(modules, is_function, size, version)
	return {"version": version, "size": size, "mask": mask, "ecl": ecl, "modules": modules}

## The symbol as `size` strings of '1' (dark) and '0', top row first.
static func matrix_rows(qr: Dictionary) -> PackedStringArray:
	var rows: PackedStringArray = PackedStringArray()
	var size: int = qr["size"]
	var modules: PackedByteArray = qr["modules"]
	for y in size:
		var row: String = ""
		for x in size:
			row += "1" if modules[y * size + x] != 0 else "0"
		rows.append(row)
	return rows

## Black on white, `scale` pixels a module, with a `margin`-module light
## quiet zone all round (the same look as the old `qrencode -s 8 -m 2`).
static func to_image(qr: Dictionary, scale: int = 8, margin: int = 2) -> Image:
	var size: int = qr["size"]
	var modules: PackedByteArray = qr["modules"]
	var side: int = (size + margin * 2) * scale
	var image: Image = Image.create_empty(side, side, false, Image.FORMAT_RGB8)
	image.fill(Color.WHITE)
	for y in size:
		for x in size:
			if modules[y * size + x] != 0:
				image.fill_rect(Rect2i((x + margin) * scale, (y + margin) * scale, scale, scale), Color.BLACK)
	return image

# --- Layout -----------------------------------------------------------------

static func _num_raw_data_modules(version: int) -> int:
	var result: int = (16 * version + 128) * version + 64
	if version >= 2:
		var num_align: int = version / 7 + 2
		result -= (25 * num_align - 10) * num_align - 55
		if version >= 7:
			result -= 36
	return result

static func _num_data_codewords(version: int, ecl: int) -> int:
	return _num_raw_data_modules(version) / 8 \
		- ECC_CODEWORDS_PER_BLOCK[ecl][version] * NUM_ERROR_CORRECTION_BLOCKS[ecl][version]

static func _alignment_positions(version: int) -> PackedInt32Array:
	if version == 1:
		return PackedInt32Array()
	var num_align: int = version / 7 + 2
	var size: int = version * 4 + 17
	var step: int = int(ceil(float(version * 4 + 4) / float(num_align * 2 - 2))) * 2
	var result: PackedInt32Array = PackedInt32Array()
	result.resize(num_align)
	result[0] = 6
	var pos: int = size - 7
	for i in range(num_align - 1, 0, -1):
		result[i] = pos
		pos -= step
	return result

static func _set_function(modules: PackedByteArray, is_function: PackedByteArray, size: int, x: int, y: int, dark: bool) -> void:
	modules[y * size + x] = 1 if dark else 0
	is_function[y * size + x] = 1

static func _draw_function_patterns(modules: PackedByteArray, is_function: PackedByteArray, size: int, version: int, ecl: int) -> void:
	for i in size: # timing patterns
		_set_function(modules, is_function, size, 6, i, i % 2 == 0)
		_set_function(modules, is_function, size, i, 6, i % 2 == 0)
	for centre: Vector2i in [Vector2i(3, 3), Vector2i(size - 4, 3), Vector2i(3, size - 4)]:
		for dy in range(-4, 5): # finder plus its light separator
			for dx in range(-4, 5):
				var x: int = centre.x + dx
				var y: int = centre.y + dy
				if x >= 0 and x < size and y >= 0 and y < size:
					var dist: int = maxi(absi(dx), absi(dy))
					_set_function(modules, is_function, size, x, y, dist != 2 and dist != 4)
	var align: PackedInt32Array = _alignment_positions(version)
	var last: int = align.size() - 1
	for i in align.size():
		for j in align.size():
			if (i == 0 and j == 0) or (i == 0 and j == last) or (i == last and j == 0):
				continue # those corners hold finders
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					_set_function(modules, is_function, size, align[i] + dx, align[j] + dy, maxi(absi(dx), absi(dy)) != 1)
	# Reserved here; drawn for real once the mask is chosen.
	_draw_format_bits(modules, is_function, size, ecl, 0, true)
	_draw_version_bits(modules, is_function, size, version, true)

## Version information, versions 7 and up: all light when `blank`.
static func _draw_version_bits(modules: PackedByteArray, is_function: PackedByteArray, size: int, version: int, blank: bool = false) -> void:
	if version < 7:
		return
	var rem: int = version
	for i in 12:
		rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
	var bits: int = 0 if blank else (version << 12) | rem
	for i in 18:
		var dark: bool = ((bits >> i) & 1) != 0
		var a: int = size - 11 + i % 3
		var b: int = i / 3
		_set_function(modules, is_function, size, a, b, dark)
		_set_function(modules, is_function, size, b, a, dark)

## Both copies of the format information and the dark module: all light when
## `blank`.
static func _draw_format_bits(modules: PackedByteArray, is_function: PackedByteArray, size: int, ecl: int, mask: int, blank: bool = false) -> void:
	var data: int = (ECL_FORMAT_BITS[ecl] << 3) | mask
	var rem: int = data
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits: int = 0 if blank else ((data << 10) | rem) ^ 0x5412
	for i in 6:
		_set_function(modules, is_function, size, 8, i, ((bits >> i) & 1) != 0)
	_set_function(modules, is_function, size, 8, 7, ((bits >> 6) & 1) != 0)
	_set_function(modules, is_function, size, 8, 8, ((bits >> 7) & 1) != 0)
	_set_function(modules, is_function, size, 7, 8, ((bits >> 8) & 1) != 0)
	for i in range(9, 15):
		_set_function(modules, is_function, size, 14 - i, 8, ((bits >> i) & 1) != 0)
	for i in 8:
		_set_function(modules, is_function, size, size - 1 - i, 8, ((bits >> i) & 1) != 0)
	for i in range(8, 15):
		_set_function(modules, is_function, size, 8, size - 15 + i, ((bits >> i) & 1) != 0)
	_set_function(modules, is_function, size, 8, size - 8, not blank) # the dark module

# --- Data and error correction ----------------------------------------------

static func _append_bits(bits: PackedByteArray, value: int, count: int) -> void:
	for i in range(count - 1, -1, -1):
		bits.append((value >> i) & 1)

static func _add_ecc_and_interleave(data: PackedByteArray, version: int, ecl: int) -> PackedByteArray:
	var num_blocks: int = NUM_ERROR_CORRECTION_BLOCKS[ecl][version]
	var block_ecc_len: int = ECC_CODEWORDS_PER_BLOCK[ecl][version]
	var raw_codewords: int = _num_raw_data_modules(version) / 8
	var num_short_blocks: int = num_blocks - raw_codewords % num_blocks
	var short_block_len: int = raw_codewords / num_blocks
	var divisor: PackedByteArray = _rs_divisor(block_ecc_len)
	var blocks: Array[PackedByteArray] = []
	var k: int = 0
	for i in num_blocks:
		var data_len: int = short_block_len - block_ecc_len + (0 if i < num_short_blocks else 1)
		var block: PackedByteArray = data.slice(k, k + data_len)
		k += data_len
		var ecc: PackedByteArray = _rs_remainder(block, divisor)
		if i < num_short_blocks:
			block.append(0) # placeholder, skipped when interleaving
		block.append_array(ecc)
		blocks.append(block)
	var result: PackedByteArray = PackedByteArray()
	for i in blocks[0].size():
		for j in blocks.size():
			if i != short_block_len - block_ecc_len or j >= num_short_blocks:
				result.append(blocks[j][i])
	return result

## Reed-Solomon generator polynomial of `degree` over GF(2^8)/0x11D, highest
## coefficient first with the leading 1 dropped.
static func _rs_divisor(degree: int) -> PackedByteArray:
	var result: PackedByteArray = PackedByteArray()
	result.resize(degree)
	result[degree - 1] = 1
	var root: int = 1
	for i in degree:
		for j in degree:
			result[j] = _gf_mul(result[j], root)
			if j + 1 < degree:
				result[j] ^= result[j + 1]
		root = _gf_mul(root, 0x02)
	return result

static func _rs_remainder(data: PackedByteArray, divisor: PackedByteArray) -> PackedByteArray:
	var result: PackedByteArray = PackedByteArray()
	result.resize(divisor.size())
	for b in data:
		var factor: int = b ^ result[0]
		result.remove_at(0)
		result.append(0)
		for i in result.size():
			result[i] ^= _gf_mul(divisor[i], factor)
	return result

static func _gf_mul(x: int, y: int) -> int:
	var z: int = 0
	for i in range(7, -1, -1):
		z = (z << 1) ^ ((z >> 7) * 0x11D)
		z ^= ((y >> i) & 1) * x
	return z & 0xFF

## Zigzags the codeword bits up and down two-column strips, right to left,
## stepping over the vertical timing column.
static func _draw_codewords(modules: PackedByteArray, is_function: PackedByteArray, size: int, codewords: PackedByteArray) -> void:
	var i: int = 0
	var total: int = codewords.size() * 8
	var right: int = size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x: int = right - j
				var upward: bool = ((right + 1) & 2) == 0
				var y: int = size - 1 - vert if upward else vert
				if is_function[y * size + x] == 0 and i < total:
					modules[y * size + x] = (codewords[i >> 3] >> (7 - (i & 7))) & 1
					i += 1
		right -= 2

# --- Masking ----------------------------------------------------------------

static func _apply_mask(modules: PackedByteArray, is_function: PackedByteArray, size: int, mask: int) -> void:
	for y in size:
		for x in size:
			if is_function[y * size + x] != 0:
				continue
			var invert: bool
			match mask:
				0: invert = (x + y) % 2 == 0
				1: invert = y % 2 == 0
				2: invert = x % 3 == 0
				3: invert = (x + y) % 3 == 0
				4: invert = (x / 3 + y / 2) % 2 == 0
				5: invert = x * y % 2 + x * y % 3 == 0
				6: invert = (x * y % 2 + x * y % 3) % 2 == 0
				_: invert = ((x + y) % 2 + x * y % 3) % 2 == 0
			if invert:
				modules[y * size + x] ^= 1

## ISO 18004 7.8.3 penalty (N1 runs, N2 2x2 blocks, N3 finder-like
## 1:1:3:1:1 runs with 4 light modules on a side, N4 dark balance), scored
## the way python-qrcode 8.2 does. Lower is better.
static func penalty_score(modules: PackedByteArray, size: int) -> int:
	var score: int = 0
	var dark: int = 0
	for i in size:
		var row: PackedByteArray = modules.slice(i * size, i * size + size)
		var col: PackedByteArray = PackedByteArray()
		col.resize(size)
		for j in size:
			col[j] = modules[j * size + i]
		score += _run_penalty(row) + _run_penalty(col)
		score += _finder_like_penalty(row) + _finder_like_penalty(col)
		for j in size:
			dark += row[j]
			if i > 0 and j > 0:
				var c: int = row[j]
				if c == row[j - 1] and c == modules[(i - 1) * size + j] and c == modules[(i - 1) * size + j - 1]:
					score += 3
	var total: int = size * size
	score += 10 * (absi(dark * 100 - total * 50) / (total * 5))
	return score

static func _run_penalty(line: PackedByteArray) -> int:
	var score: int = 0
	var run: int = 1
	for j in range(1, line.size()):
		if line[j] == line[j - 1]:
			run += 1
		else:
			if run >= 5:
				score += run - 2
			run = 1
	if run >= 5:
		score += run - 2
	return score

## N3's two 11-module windows: 1:1:3:1:1 then 4 light, or 4 light then
## 1:1:3:1:1. Only windows wholly inside the symbol count.
const FINDER_LIKE_A: PackedByteArray = [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0]
const FINDER_LIKE_B: PackedByteArray = [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1]

static func _finder_like_penalty(line: PackedByteArray) -> int:
	var score: int = 0
	for s in line.size() - 10:
		if _window_is(line, s, FINDER_LIKE_A) or _window_is(line, s, FINDER_LIKE_B):
			score += 40
	return score

static func _window_is(line: PackedByteArray, from: int, pattern: PackedByteArray) -> bool:
	for k in pattern.size():
		if line[from + k] != pattern[k]:
			return false
	return true
