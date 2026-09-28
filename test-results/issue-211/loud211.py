"""Loudness check for #211: peak / RMS of announcer clips vs the other sfx.

python loud211.py <repo> <new_dir> <old_dir>
Effective level = clip level (dBFS) + its Sfx.gd "db". RMS is over the active
part (50 ms windows within 30 dB of the clip's loudest window).
"""
import glob, os, re, sys
import numpy as np
import soundfile as sf

repo, new_dir, old_dir = sys.argv[1], sys.argv[2], sys.argv[3]
sfx_src = open(os.path.join(repo, "scripts/Sfx.gd"), encoding="utf-8").read()
file_db = {}
for m in re.finditer(r'"files":\s*\[(.*?)\],\s*"db":\s*(-?[\d.]+)', sfx_src, re.S):
    for f in re.findall(r'"([^"]+\.ogg)"', m.group(1)):
        file_db.setdefault(f, float(m.group(2)))


def meas(path):
    x, sr = sf.read(path, dtype="float32", always_2d=True)
    x = x.mean(axis=1)
    peak = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
    w = int(sr * 0.05)
    n = max(1, len(x) // w)
    rms_w = np.array([np.sqrt(np.mean(x[i * w:(i + 1) * w] ** 2) + 1e-12) for i in range(n)])
    db_w = 20 * np.log10(rms_w)
    act = rms_w[db_w > db_w.max() - 30]
    rms = 20 * np.log10(np.sqrt(np.mean(act ** 2)))
    return peak, rms


def table(label, items):
    rows = []
    for name, path, db in items:
        p, r = meas(path)
        rows.append((name, p, r, db, p + db, r + db))
    print(f"\n== {label} ==")
    print(f"{'file':44s} {'peak':>6s} {'rms':>6s} {'db':>5s} {'effPk':>6s} {'effRms':>6s}")
    for row in rows:
        print(f"{row[0]:44s} {row[1]:6.1f} {row[2]:6.1f} {row[3]:5.1f} {row[4]:6.1f} {row[5]:6.1f}")
    a = np.array([r[1:] for r in rows])
    med = np.median(a, axis=0)
    print(f"{'MEDIAN':44s} {med[0]:6.1f} {med[1]:6.1f} {med[2]:5.1f} {med[3]:6.1f} {med[4]:6.1f}")
    return rows

ann = sorted(glob.glob(os.path.join(repo, "assets/sfx/announcer/*.ogg")))
old = [(os.path.basename(p), os.path.join(old_dir, os.path.basename(p)), -15.0) for p in ann]
new = [(os.path.basename(p), os.path.join(new_dir, os.path.basename(p)), -15.0) for p in ann]
others = [(f, os.path.join(repo, "assets/sfx", f), db) for f, db in sorted(file_db.items())
          if not f.startswith("announcer/")]
table("old announcer (main 546f9b7) at -15 dB", old)
table("new john announcer at -15 dB", new)
table("other sfx at their Sfx.gd db", others)
