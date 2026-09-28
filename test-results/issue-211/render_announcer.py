"""Render pickfight announcer lines (issue #211) with a Piper voice.

Usage (from the piper venv):
  python render_announcer.py --model <voice.onnx> --out <dir> [--only fight,ko,...]
                             [--length-scale 0.9] [--echo]

Writes treated mono Ogg Vorbis files named exactly like assets/sfx/announcer/*.ogg
(so phase 2 can drop them straight into the repo). Treatment matches the
existing clips: trim leading/trailing silence, peak-normalise to 0.9,
short fade in/out. Sample rate is the model's (22050 Hz for Piper medium/high),
same as the existing synthesised clips.
"""
import argparse
import os
import sys

import numpy as np
import soundfile as sf
from piper import PiperVoice, SynthesisConfig

# file stem -> text spoken. Texts follow CREDITS.md "Announcer voice", the
# Sfx.gd announce_* keys and RoundModifiers.title_of (modifier titles).
# "K.O." with dots is phonemised as the letters "kay-oh".
LINES = {
    "count_3": "Three!",
    "count_2": "Two!",
    "count_1": "One!",
    "fight": "Fight!",
    "ko": "K.O.!",
    "double_ko": "Double K.O.!",
    "winner": "Winner!",
    "low_gravity": "Low gravity!",
    "heavy_weapons": "Heavy weapons!",
    "big_heads": "Big heads!",
    "fast_lava": "Fast lava!",
    "slippery_floor": "Slippery floor!",
    "tiny_weapons": "Tiny weapons!",
    "weapon_roulette": "Weapon roulette!",
    "meteor_shower": "Meteor shower!",
    "bouncy": "Bouncy!",
    "double_damage": "Double damage!",
}

PEAK = 0.9
FADE_IN_S = 0.008
FADE_OUT_S = 0.04
TRIM_DB = -40.0  # relative to the clip's peak
PAD_S = 0.01
GAP_S = 0.2  # a silence this long after speech ends the line (drops Piper's
             # occasional trailing babble after one-word prompts)


def synth(voice, text, cfg):
    parts = [c.audio_float_array for c in voice.synthesize(text, syn_config=cfg)]
    return np.concatenate(parts).astype(np.float32)


def treat(x, sr, echo=False):
    x = x - float(np.mean(x))
    thr = np.max(np.abs(x)) * (10 ** (TRIM_DB / 20))
    # envelope over 5 ms windows so a single quiet sample doesn't stop the trim
    win = max(1, int(sr * 0.005))
    env = np.convolve(np.abs(x), np.ones(win) / win, mode="same")
    idx = np.where(env > thr)[0]
    if len(idx):
        gaps = np.where(np.diff(idx) > int(sr * GAP_S))[0]
        if len(gaps):
            idx = idx[: gaps[0] + 1]
        pad = int(sr * PAD_S)
        x = x[max(0, idx[0] - pad): min(len(x), idx[-1] + pad)]
    if echo:  # optional two-tap echo, like the old espeak clips
        out = np.zeros(len(x) + int(sr * 0.16), dtype=np.float32)
        out[: len(x)] += x
        for delay, gain in ((0.08, 0.25), (0.16, 0.1)):
            d = int(sr * delay)
            out[d: d + len(x)] += x * gain
        x = out
    x = x / (np.max(np.abs(x)) or 1.0) * PEAK
    fi, fo = int(sr * FADE_IN_S), int(sr * FADE_OUT_S)
    x[:fi] *= np.linspace(0.0, 1.0, fi)
    x[-fo:] *= np.linspace(1.0, 0.0, fo)
    return x


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="", help="comma-separated file stems")
    ap.add_argument("--length-scale", type=float, default=0.9)
    ap.add_argument("--noise-scale", type=float, default=0.667)
    ap.add_argument("--noise-w", type=float, default=0.8)
    ap.add_argument("--echo", action="store_true")
    a = ap.parse_args()

    voice = PiperVoice.load(a.model)
    sr = voice.config.sample_rate
    cfg = SynthesisConfig(length_scale=a.length_scale, noise_scale=a.noise_scale,
                          noise_w_scale=a.noise_w)
    stems = [s for s in a.only.split(",") if s] or list(LINES)
    os.makedirs(a.out, exist_ok=True)
    for stem in stems:
        if stem not in LINES:
            sys.exit(f"unknown line {stem!r}")
        y = treat(synth(voice, LINES[stem], cfg), sr, a.echo)
        path = os.path.join(a.out, stem + ".ogg")
        sf.write(path, y, sr, format="OGG", subtype="VORBIS")
        print(f"{path}  {len(y) / sr:.3f}s  {sr}Hz")


if __name__ == "__main__":
    main()
