#!/usr/bin/env python3
"""Generates the per-player voice grunts under assets/sfx/voice/ (issue #290).

These are placeholder sounds, synthesised from scratch: a pitched glottal
pulse train plus a little breath noise, shaped by three vowel formants, with a
short soft envelope. No recordings or third-party assets are used, so the
output is CC0 like the rest of assets/sfx/ (see CREDITS.md). They are meant to
be subtle: short, quiet, low-pitched, no pitch swoops or vowel yells.

    pip install numpy soundfile
    python tools/gen_voice_grunts.py

Output is deterministic (fixed seeds). Per slot 0..7: hit_<slot>_0/1.ogg (a
short "hnh") and ko_<slot>.ogg (a longer falling "uhh").
"""
import math
import os

import numpy as np
import soundfile as sf

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx", "voice")

# One voice per player slot: base pitch (Hz) and a vocal-tract scale that
# moves every formant (smaller = a bigger, deeper-sounding voice).
VOICES = [
    (98, 1.00), (118, 0.94), (136, 1.06), (108, 1.12),
    (150, 0.90), (88, 0.96), (128, 1.16), (165, 1.02),
]
# Vowel formants (F1, F2, F3) of a relaxed "uh" and a more open "aw".
UH = (600.0, 1040.0, 2250.0)
AW = (730.0, 1090.0, 2440.0)


def resonator(x, freq, bw):
    """Two-pole band-pass resonator."""
    r = math.exp(-math.pi * bw / RATE)
    theta = 2.0 * math.pi * freq / RATE
    a1, a2 = -2.0 * r * math.cos(theta), r * r
    gain = 1.0 - r
    y = np.zeros_like(x)
    y1 = y2 = 0.0
    for i, s in enumerate(x):
        v = gain * s - a1 * y1 - a2 * y2
        y[i] = v
        y2, y1 = y1, v
    return y


def grunt(f0, scale, formants, dur, glide, breath, seed):
    rng = np.random.default_rng(seed)
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    # Falling pitch: f0*(1+glide) down to f0, with a touch of slow jitter.
    freq = f0 * (1.0 + glide * (1.0 - t / dur) ** 2)
    freq *= 1.0 + 0.012 * np.sin(2 * math.pi * 5.0 * t + rng.uniform(0, 6))
    phase = np.cumsum(freq) / RATE
    # Glottal-ish source: a few decaying harmonics.
    src = np.zeros(n)
    for k in range(1, 18):
        src += np.sin(2 * math.pi * k * phase) / (k ** 1.4)
    src += breath * rng.standard_normal(n) * 0.35
    out = np.zeros(n)
    for i, f in enumerate(formants):
        out += resonator(src, f * scale, 90.0 + 60.0 * i) * (1.0, 0.7, 0.35)[i]
    # Soft attack, quick decay: a puff, not a held note.
    env = np.minimum(1.0, t / 0.012) * np.exp(-t / (dur * 0.38))
    env *= np.minimum(1.0, (dur - t) / 0.03)
    out *= env
    out /= max(1e-9, np.max(np.abs(out)))
    return (out * 0.8).astype(np.float32)


def main():
    os.makedirs(OUT, exist_ok=True)
    for slot, (f0, scale) in enumerate(VOICES):
        for v in range(2):
            clip = grunt(f0 * (1.0 + 0.05 * v), scale, UH, 0.14 + 0.03 * v,
                         0.10, 0.5, 1000 + slot * 10 + v)
            sf.write(os.path.join(OUT, "hit_%d_%d.ogg" % (slot, v)), clip, RATE,
                     format="OGG", subtype="VORBIS")
        clip = grunt(f0 * 1.1, scale, AW, 0.42, 0.22, 0.4, 2000 + slot)
        sf.write(os.path.join(OUT, "ko_%d.ogg" % slot), clip, RATE,
                 format="OGG", subtype="VORBIS")


if __name__ == "__main__":
    main()
