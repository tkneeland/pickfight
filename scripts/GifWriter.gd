extends RefCounted
## Pure-GDScript animated GIF89a encoder (#502): no external binaries, so it
## runs in every itch build and headless. One global 256-colour palette
## (popularity over 5-5-5 colour bins), variable-width LZW, the NETSCAPE2.0
## infinite-loop extension. Static and thread-safe: it touches no nodes.

const CLEAR_CODE: int = 256
const EOI_CODE: int = 257
const MAX_CODES: int = 4096
## Sample every Nth pixel when building the palette histogram.
const PALETTE_STRIDE: int = 3

## Encode `frames` (all the same size) to GIF bytes. `delay_cs` is the
## per-frame delay in hundredths of a second (12 fps is 8). Returns an empty
## array for no frames.
static func encode(frames: Array, delay_cs: int) -> PackedByteArray:
	var out := PackedByteArray()
	if frames.is_empty():
		return out
	var w: int = frames[0].get_width()
	var h: int = frames[0].get_height()
	var datas: Array[PackedByteArray] = []
	for f in frames:
		var img: Image = f
		if img.get_format() != Image.FORMAT_RGB8:
			img = img.duplicate()
			img.convert(Image.FORMAT_RGB8)
		datas.append(img.get_data())
	var palette := _build_palette(datas)
	var lut := PackedInt32Array()
	lut.resize(32768)
	lut.fill(-1)

	out.append_array("GIF89a".to_ascii_buffer())
	_u16(out, w)
	_u16(out, h)
	out.append(0xF7) # global colour table, 8 bits of colour, 256 entries
	out.append(0)
	out.append(0)
	for c in 256:
		var base := c * 3
		out.append(palette[base] if base < palette.size() else 0)
		out.append(palette[base + 1] if base < palette.size() else 0)
		out.append(palette[base + 2] if base < palette.size() else 0)
	# NETSCAPE2.0: loop forever.
	out.append_array(PackedByteArray([0x21, 0xFF, 0x0B]))
	out.append_array("NETSCAPE2.0".to_ascii_buffer())
	out.append_array(PackedByteArray([0x03, 0x01, 0x00, 0x00, 0x00]))
	for data in datas:
		# Graphic control extension: leave in place, no transparency.
		out.append_array(PackedByteArray([0x21, 0xF9, 0x04, 0x04]))
		_u16(out, delay_cs)
		out.append(0)
		out.append(0)
		out.append(0x2C)
		_u16(out, 0)
		_u16(out, 0)
		_u16(out, w)
		_u16(out, h)
		out.append(0)
		out.append(8) # LZW minimum code size
		var indices := _index_frame(data, palette, lut)
		var lzw := _lzw(indices)
		var pos := 0
		while pos < lzw.size():
			var n: int = mini(255, lzw.size() - pos)
			out.append(n)
			out.append_array(lzw.slice(pos, pos + n))
			pos += n
		out.append(0)
	out.append(0x3B)
	return out

static func _u16(out: PackedByteArray, v: int) -> void:
	out.append(v & 0xFF)
	out.append((v >> 8) & 0xFF)

static func _build_palette(datas: Array[PackedByteArray]) -> PackedByteArray:
	var counts := PackedInt32Array()
	counts.resize(32768)
	var step := 3 * PALETTE_STRIDE
	for data in datas:
		var i := 0
		var n := data.size()
		while i + 2 < n:
			counts[((data[i] >> 3) << 10) | ((data[i + 1] >> 3) << 5) | (data[i + 2] >> 3)] += 1
			i += step
	var bins: Array[int] = []
	for b in 32768:
		if counts[b] > 0:
			bins.append(b)
	bins.sort_custom(func(a: int, b: int) -> bool: return counts[a] > counts[b] or (counts[a] == counts[b] and a < b))
	var palette := PackedByteArray()
	for k in mini(256, bins.size()):
		var b: int = bins[k]
		palette.append((((b >> 10) & 31) << 3) | 4)
		palette.append((((b >> 5) & 31) << 3) | 4)
		palette.append(((b & 31) << 3) | 4)
	return palette

static func _nearest(bin: int, palette: PackedByteArray) -> int:
	var r: int = (((bin >> 10) & 31) << 3) | 4
	var g: int = (((bin >> 5) & 31) << 3) | 4
	var b: int = ((bin & 31) << 3) | 4
	var best := 0
	var best_d := 1 << 30
	for c in palette.size() / 3:
		var dr: int = palette[c * 3] - r
		var dg: int = palette[c * 3 + 1] - g
		var db: int = palette[c * 3 + 2] - b
		var d := dr * dr + dg * dg + db * db
		if d < best_d:
			best_d = d
			best = c
			if d == 0:
				break
	return best

static func _index_frame(data: PackedByteArray, palette: PackedByteArray, lut: PackedInt32Array) -> PackedByteArray:
	var n := data.size() / 3
	var idx := PackedByteArray()
	idx.resize(n)
	for p in n:
		var o := p * 3
		var bin: int = ((data[o] >> 3) << 10) | ((data[o + 1] >> 3) << 5) | (data[o + 2] >> 3)
		var c: int = lut[bin]
		if c < 0:
			c = _nearest(bin, palette)
			lut[bin] = c
		idx[p] = c
	return idx

static func _lzw(indices: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	var acc := 0
	var nbits := 0
	var size := 9
	var free := 258
	var dict := {}
	# Emit CLEAR first.
	acc = CLEAR_CODE
	nbits = size
	var prefix: int = indices[0]
	for i in range(1, indices.size()):
		var c: int = indices[i]
		var key: int = (prefix << 8) | c
		var code: int = dict.get(key, -1)
		if code >= 0:
			prefix = code
			continue
		acc |= prefix << nbits
		nbits += size
		while nbits >= 8:
			out.append(acc & 0xFF)
			acc >>= 8
			nbits -= 8
		if free < MAX_CODES:
			dict[key] = free
			# Entry count before this add decides the next code's width.
			if free >= (1 << size) and size < 12:
				size += 1
			free += 1
		else:
			acc |= CLEAR_CODE << nbits
			nbits += size
			while nbits >= 8:
				out.append(acc & 0xFF)
				acc >>= 8
				nbits -= 8
			dict.clear()
			size = 9
			free = 258
		prefix = c
	acc |= prefix << nbits
	nbits += size
	while nbits >= 8:
		out.append(acc & 0xFF)
		acc >>= 8
		nbits -= 8
	acc |= EOI_CODE << nbits
	nbits += size
	while nbits > 0:
		out.append(acc & 0xFF)
		acc >>= 8
		nbits -= 8
	return out
