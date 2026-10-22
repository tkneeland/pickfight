"""Builds the bundled CJK font subsets in art/fonts/ (#849).

The UI fonts (Lilita One, Nunito) have no CJK glyphs, so Simplified Chinese,
Japanese and Korean each get a subset of Noto Sans SC / JP / KR holding only the
characters the game uses: every character of that language's column in
translations/strings.csv and its own name in the Language picker, plus ASCII, Latin-1, general punctuation, CJK
symbols, kana (ja) and the full-width forms. The full fonts (9 to 18 MB each)
are fetched from a pinned google/fonts commit, checked against a pinned sha256
and never committed. Each is pinned to one weight first (dropping the variable
tables), then subset. Re-run it whenever strings.csv changes; the scenario
cjk_subsets_cover_every_translated_character_849 fails until you do.

Needs fontTools, which is not part of the repo. Install it in a venv outside the
repo and run the script with -I so nothing in the working directory is imported:
    python3 -m venv /tmp/pf-venv && /tmp/pf-venv/bin/pip install fonttools
    /tmp/pf-venv/bin/python3 -I tools/subset_cjk_font.py            (from the repo root)
    /tmp/pf-venv/bin/python3 -I tools/subset_cjk_font.py --src DIR  (DIR already holds the
        downloaded NotoSans{SC,JP,KR}.ttf; their sha256 is still checked)
"""
import argparse
import csv
import hashlib
import os
import re
import shutil
import sys
import tempfile
import urllib.request

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

COMMIT = "45e3d5269e4a17d823f6d84470bc084dc5ae46f6"
BASE = "https://raw.githubusercontent.com/google/fonts/" + COMMIT + "/ofl/"
# language column -> (source file, url, sha256, output file)
FONTS = {
	"zh_CN": ("NotoSansSC.ttf", BASE + "notosanssc/NotoSansSC%5Bwght%5D.ttf",
		"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da", "NotoSansSC-Subset.ttf"),
	"ja": ("NotoSansJP.ttf", BASE + "notosansjp/NotoSansJP%5Bwght%5D.ttf",
		"c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f", "NotoSansJP-Subset.ttf"),
	"ko": ("NotoSansKR.ttf", BASE + "notosanskr/NotoSansKR%5Bwght%5D.ttf",
		"194018e6b2b293a7964f037b25c0249ce1418bc9ab3c971060a03aa57861e252", "NotoSansKR-Subset.ttf"),
}
OFL = ("OFL.txt", BASE + "notosanssc/OFL.txt",
	"1c05c68c34f9708415aada51f17e1b0092d2cea709bf4a94cd38114f9e73d7d9", "OFL-NotoSansCJK.txt")
WEIGHT = 700 # bold, to sit with the chunky Lilita One / ExtraBold Nunito UI
MAX_BYTES = 600 * 1024 # also checked by cjk_subsets_cover_every_translated_character_849
MAX_TOTAL_BYTES = 1536 * 1024
COMMON_RANGES = [(0x20, 0x7E), (0xA0, 0xFF), (0x2000, 0x206F), (0x3000, 0x303F), (0xFF00, 0xFFEF)]
EXTRA_RANGES = {"ja": [(0x3040, 0x30FF)]}


def sha256(path):
	h = hashlib.sha256()
	with open(path, "rb") as f:
		for block in iter(lambda: f.read(1 << 20), b""):
			h.update(block)
	return h.hexdigest()


def fetch(src_dir, name, url, digest):
	path = os.path.join(src_dir, name)
	if not os.path.exists(path):
		urllib.request.urlretrieve(url, path)
	if sha256(path) != digest:
		sys.exit("sha256 mismatch for %s (expected %s)" % (path, digest))
	return path


def used_chars(csv_path, column):
	chars = set()
	with open(csv_path, encoding="utf-8", newline="") as f:
		reader = csv.reader(f)
		header = next(reader)
		col = header.index(column)
		for row in reader:
			if col < len(row):
				chars.update(row[col])
	return chars


def picker_names(languages_gd):
	"""{code: name} from Languages.OPTIONS: the picker shows each language's own
	name in every locale, so each name goes into its own language's subset."""
	with open(languages_gd, encoding="utf-8") as f:
		return dict(re.findall(r'\{"code": "(\w+)", "name": "([^"]+)"\}', f.read()))


def main():
	parser = argparse.ArgumentParser()
	parser.add_argument("--src", help="existing directory holding (or receiving) the full source fonts")
	args = parser.parse_args()
	root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
	out_dir = os.path.join(root, "art", "fonts")
	csv_path = os.path.join(root, "translations", "strings.csv")
	names = picker_names(os.path.join(root, "scripts", "Languages.gd"))
	tmp = None
	src_dir = args.src
	if src_dir is None:
		tmp = tempfile.mkdtemp()
		src_dir = tmp
	try:
		shutil.copyfile(fetch(src_dir, OFL[0], OFL[1], OFL[2]), os.path.join(out_dir, OFL[3]))
		total = 0
		for column, (name, url, digest, out_name) in FONTS.items():
			if column not in names:
				sys.exit("no %s entry in Languages.OPTIONS" % column)
			chars = used_chars(csv_path, column) | set(names[column])
			codepoints = {ord(c) for c in chars if ord(c) >= 0x20}
			for lo, hi in COMMON_RANGES + EXTRA_RANGES.get(column, []):
				codepoints.update(range(lo, hi + 1))
			font = TTFont(fetch(src_dir, name, url, digest))
			font = instancer.instantiateVariableFont(font, {"wght": WEIGHT})
			options = subset.Options()
			options.layout_features = ["*"]
			options.name_IDs = ["*"]
			options.notdef_outline = True
			subsetter = subset.Subsetter(options)
			subsetter.populate(unicodes=codepoints)
			subsetter.subset(font)
			out_path = os.path.join(out_dir, out_name)
			font.save(out_path)
			size = os.path.getsize(out_path)
			total += size
			print("%s: %d codepoints, %d KB" % (out_name, len(codepoints), size // 1024))
			if size > MAX_BYTES:
				sys.exit("%s is %d bytes, over the %d limit" % (out_name, size, MAX_BYTES))
		print("total: %d KB" % (total // 1024))
		if total > MAX_TOTAL_BYTES:
			sys.exit("the subsets total %d bytes, over the %d limit" % (total, MAX_TOTAL_BYTES))
	finally:
		if tmp is not None:
			shutil.rmtree(tmp)


if __name__ == "__main__":
	main()
