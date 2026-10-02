#!/usr/bin/env python3
"""Writes the PICKFIGHT logo and the Steam capsule SVGs (issue #359) into art/logo/.

The logo is hand-built flat shapes in the Palette.gd colours (#255): chunky
letters each in a player colour, an ink outline and a hard offset shadow, and
the first I is a pickaxe. Run from the repo root:  python3 tools/gen_logo_art.py
then rasterise with:  godot --headless --path . -s tools/export_logo_pngs.gd
"""
import os

INK = "#14181d"
PLAYERS = ["#E69F00", "#3D8FD1", "#009E73", "#D55E00", "#CC79A7", "#56B4E9", "#F5E24A", "#E8E6F0"]
PLATFORM = "#2a3440"
SKY_TOP, SKY_BOTTOM, FAR, MID = "#bfe3f0", "#e6f4f7", "#9fcbdc", "#7fb6c9"
WOOD = "#8a5a33"
STEEL = "#E8E6F0"

# (width, path d in a 240-tall cell, fill)
LETTERS = [
    ("P", 150, "M0,0H110L150,40V110L110,150H50V240H0ZM50,45V105H100V45Z", PLAYERS[0]),
    ("PICK", 150, None, None),  # the pickaxe I, drawn by hand below
    ("C", 150, "M40,0H150V50H50V190H150V240H40L0,200V40Z", PLAYERS[2]),
    ("K", 155, "M0,0H50V100L100,0H155L90,115L155,240H100L50,135V240H0Z", PLAYERS[3]),
    ("F", 150, "M0,0H150V50H50V95H125V140H50V240H0Z", PLAYERS[1]),
    ("I", 50, "M0,0H50V240H0Z", PLAYERS[6]),
    ("G", 150, "M40,0H150V50H50V190H100V140H75V100H150V240H40L0,200V40Z", PLAYERS[4]),
    ("H", 150, "M0,0H50V90H100V0H150V240H100V140H50V240H0Z", PLAYERS[5]),
    ("T", 150, "M0,0H150V50H100V240H50V50H0Z", PLAYERS[0]),
]
GAP = 24
SW = 10  # outline width


def pick_cell():
    shaft = f'<path d="M52,70H98V200H52Z" fill="{WOOD}"/><path d="M10,196H140V240H10Z" fill="{PLAYERS[6]}"/>'
    head = f'<path d="M0,78Q75,-48 150,78L150,118Q75,12 0,118Z" fill="{STEEL}"/>'
    return head, shaft


def logo_group(x0=0, y0=0):
    """The wordmark in a 1600x400 box, as an svg <g>."""
    out = [f'<g transform="translate({x0},{y0})">']
    x = 45
    top = 70
    for name, w, d, fill in LETTERS:
        out.append(f'<g transform="translate({x},{top})">')
        if d is None:
            head, shaft = pick_cell()
            shadow = (head + shaft).replace(f'fill="{STEEL}"', f'fill="{INK}"').replace(f'fill="{WOOD}"', f'fill="{INK}"').replace(f'fill="{PLAYERS[6]}"', f'fill="{INK}"')
            out.append(f'<g transform="translate(12,14)" stroke="{INK}" stroke-width="{SW}" stroke-linejoin="round">{shadow}</g>')
            out.append(f'<g stroke="{INK}" stroke-width="{SW}" stroke-linejoin="round">{shaft}{head}</g>')
        else:
            out.append(f'<path d="{d}" transform="translate(12,14)" fill="{INK}" stroke="{INK}" stroke-width="{SW}" stroke-linejoin="round" fill-rule="evenodd"/>')
            out.append(f'<path d="{d}" fill="{fill}" stroke="{INK}" stroke-width="{SW}" stroke-linejoin="round" fill-rule="evenodd"/>')
        out.append('</g>')
        x += w + GAP
    out.append('</g>')
    return "\n".join(o for o in out if o)


def write(path, text):
    with open(path, "w") as f:
        f.write(text)


def scene(w, h, ground_y, seed_players):
    """Flat stage-style backdrop: gradient sky, two hill layers, a platform and square players."""
    s = [f'<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{SKY_TOP}"/><stop offset="1" stop-color="{SKY_BOTTOM}"/></linearGradient></defs>',
         f'<rect width="{w}" height="{h}" fill="url(#sky)"/>']
    far_y, mid_y = ground_y - h * 0.22, ground_y - h * 0.10
    for color, base, amp in ((FAR, far_y, h * 0.12), (MID, mid_y, h * 0.08)):
        pts = [f"0,{h}"]
        n = 8
        for i in range(n + 1):
            px = w * i / n
            py = base - (amp if i % 2 else 0) - (amp * 0.5 if i % 3 == 0 else 0)
            pts.append(f"{px:.0f},{py:.0f}")
        pts.append(f"{w},{h}")
        s.append(f'<polygon points="{" ".join(pts)}" fill="{color}"/>')
    s.append(f'<rect x="0" y="{ground_y:.0f}" width="{w}" height="{h - ground_y:.0f}" fill="{PLATFORM}"/>')
    s.append(f'<rect x="0" y="{ground_y:.0f}" width="{w}" height="{max(4, h * 0.012):.0f}" fill="#ffffff" fill-opacity="0.18"/>')
    for (fx, color) in seed_players:
        size = h * 0.085
        bx, by = w * fx, ground_y - size
        s.append(f'<rect x="{bx:.0f}" y="{by:.0f}" width="{size:.0f}" height="{size:.0f}" fill="{color}" stroke="{INK}" stroke-width="{max(3, size * 0.07):.0f}" stroke-linejoin="round"/>')
        e = size * 0.16
        for ex in (0.28, 0.62):
            s.append(f'<rect x="{bx + size * ex:.0f}" y="{by + size * 0.3:.0f}" width="{e:.0f}" height="{e * 1.2:.0f}" fill="#ffffff"/>')
            s.append(f'<rect x="{bx + size * ex + e * 0.45:.0f}" y="{by + size * 0.36:.0f}" width="{e * 0.5:.0f}" height="{e * 0.7:.0f}" fill="{INK}"/>')
    return "\n".join(s)


def svg(w, h, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">\n{body}\n</svg>\n'


LOGO_W, LOGO_H = 1600, 400


def logo_fit(w, h, box_frac, y_frac):
    """The logo scaled to box_frac of the width, centred horizontally, its centre at y_frac of the height."""
    scale = min(w * box_frac / LOGO_W, h * 0.6 / LOGO_H)
    lw, lh = LOGO_W * scale, LOGO_H * scale
    x, y = (w - lw) / 2, h * y_frac - lh / 2
    return f'<g transform="translate({x:.1f},{y:.1f}) scale({scale:.4f})">{logo_group()}</g>'


CAPSULES = {  # name: (w, h, logo width fraction, logo centre y, ground y fraction)
    "header_920x430": (920, 430, 0.86, 0.38, 0.80),
    "small_462x174": (462, 174, 0.90, 0.42, 0.82),
    "main_1232x706": (1232, 706, 0.86, 0.38, 0.82),
    "vertical_748x896": (748, 896, 0.94, 0.30, 0.86),
    "library_600x900": (600, 900, 0.94, 0.30, 0.86),
}

if __name__ == "__main__":
    here = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "logo")
    os.makedirs(os.path.join(here, "capsules"), exist_ok=True)
    write(os.path.join(here, "logo.svg"),
          svg(LOGO_W, LOGO_H, f'<title>Pickfight</title>\n{logo_group()}'))
    cast = [(0.12, PLAYERS[0]), (0.30, PLAYERS[1]), (0.55, PLAYERS[2]), (0.72, PLAYERS[3]), (0.86, PLAYERS[4])]
    for name, (w, h, frac, cy, gy) in CAPSULES.items():
        players = cast if w > 700 or h < 500 else cast[::2]
        write(os.path.join(here, "capsules", name + ".svg"),
              svg(w, h, scene(w, h, h * gy, players) + "\n" + logo_fit(w, h, frac, cy)))
    hw, hh = 3840, 1240
    write(os.path.join(here, "capsules", "library_hero_3840x1240.svg"),
          svg(hw, hh, logo_fit(hw, hh, 0.7, 0.5)))
