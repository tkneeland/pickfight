#!/usr/bin/env python3
"""Writes the three large stages for issue #144 as hand-style .tscn text."""
import sys
from pathlib import Path

OUT = Path(sys.argv[1]) / "scenes/stages"
TERRAIN = "Color(0.35, 0.35, 0.4, 1)"


def fmt(v):
    v = float(v)
    return str(int(v)) if v == int(v) else ("%g" % v)


def vec(x, y):
    return "Vector2(%s, %s)" % (fmt(x), fmt(y))


class Stage:
    def __init__(self, name):
        self.name = name
        self.ext = []  # (type, path)
        self.subs = {}  # id -> size
        self.body = []

    def ext_id(self, typ, path):
        for i, (t, p) in enumerate(self.ext):
            if p == path:
                return str(i + 1)
        self.ext.append((typ, path))
        return str(len(self.ext))

    def rect_id(self, key, w, h):
        rid = "RectangleShape2D_%s" % key
        self.subs[rid] = (w, h)
        return rid

    def comment(self, text):
        self.body.append("\n".join("; " + l if l else ";" for l in text.strip("\n").split("\n")))

    def root(self, props):
        sid = self.ext_id("Script", "res://scripts/Stage.gd")
        lines = ['[node name="%s" type="Node2D"]' % self.name, 'script = ExtResource("%s")' % sid]
        lines += ["%s = %s" % kv for kv in props]
        self.body.append("\n".join(lines))

    def block(self, name, x, y, w, h, shape_key, comment=None):
        rid = self.rect_id(shape_key, w, h)
        if comment:
            self.comment(comment)
        self.body.append('[node name="%s" type="StaticBody2D" parent="."]\nposition = %s' % (name, vec(x, y)))
        self.body.append('[node name="%sShape" type="CollisionShape2D" parent="%s"]\nshape = SubResource("%s")' % (name, name, rid))
        hw, hh = w / 2, h / 2
        self.body.append('[node name="%sVisual" type="Polygon2D" parent="%s"]\ncolor = %s\npolygon = PackedVector2Array(%s, %s, %s, %s, %s, %s, %s, %s)' % (
            name, name, TERRAIN, fmt(-hw), fmt(-hh), fmt(hw), fmt(-hh), fmt(hw), fmt(hh), fmt(-hw), fmt(hh)))

    def part(self, name, scene, x, y, props, comment=None):
        pid = self.ext_id("PackedScene", "res://scenes/parts/%s.tscn" % scene)
        if comment:
            self.comment(comment)
        lines = ['[node name="%s" parent="." instance=ExtResource("%s")]' % (name, pid), "position = %s" % vec(x, y)]
        lines += ["%s = %s" % kv for kv in props]
        self.body.append("\n".join(lines))

    def marker(self, name, x, y, comment=None):
        if comment:
            self.comment(comment)
        self.body.append('[node name="%s" type="Marker2D" parent="."]\nposition = %s' % (name, vec(x, y)))

    def kill_zone(self, y):
        kid = self.ext_id("Script", "res://scripts/KillZone.gd")
        rid = self.rect_id("kill", 8000, 40)
        self.body.append('[node name="KillZone" type="Area2D" parent="."]\nposition = %s\nscript = ExtResource("%s")' % (vec(0, y), kid))
        self.body.append('[node name="KillZoneShape" type="CollisionShape2D" parent="KillZone"]\nshape = SubResource("%s")' % rid)

    def write(self, header_comment):
        out = ["[gd_scene load_steps=%d format=3]" % (len(self.ext) + len(self.subs) + 1), ""]
        for i, (t, p) in enumerate(self.ext):
            out.append('[ext_resource type="%s" path="%s" id="%d"]' % (t, p, i + 1))
        out.append("")
        for rid, (w, h) in self.subs.items():
            out.append('[sub_resource type="RectangleShape2D" id="%s"]\nsize = %s\n' % (rid, vec(w, h)))
        out.append("\n".join("; " + l if l else ";" for l in header_comment.strip("\n").split("\n")))
        out.append("")
        out.append("\n\n".join(self.body))
        (OUT / ("%s.tscn" % self.name)).write_text("\n".join(out) + "\n")


def spawns(s, pts, comment):
    for i, (x, y) in enumerate(pts):
        s.marker("Spawn%d" % i, x, y, comment if i == 0 else None)


def pickups(s, pts, comment):
    for i, (x, y) in enumerate(pts):
        s.marker("PickupSpawn%d" % i, x, y, comment if i == 0 else None)


# --- Pistons ------------------------------------------------------------------
def pistons():
    s = Stage("Pistons")
    s.root([
        ("background_sky_top", "Color(0.14, 0.09, 0.08, 1)"),
        ("background_sky_bottom", "Color(0.3, 0.18, 0.12, 1)"),
        ("background_silhouette", "Color(0.1, 0.08, 0.08, 1)"),
        ("background_layers", 'PackedStringArray("clouds", "city", "rocks")'),
        ("view_size", "Vector2(2240, 1260)"),
    ])
    top = 360  # bastion tops
    s.block("BastionLeft", -780, top + 20, 400, 40, "bastion", comment="""
The two still ends. Everyone starts here, four a side, and the open ends
past them (x = +-980) are the ring-out.""")
    s.block("BastionRight", 780, top + 20, 400, 40, "bastion")
    # Seven pistons, 160 wide, 5 px seams, across x = -575..575.
    # Column bodies 320 tall so their sides read as pistons, not slabs.
    # Pattern mirrored left/right. (name, x, top_y, travel_y, one_way_sec)
    cols = [
        ("PistonCentre", 0, 310, 100, 2.4),
        ("PistonInnerLeft", -165, 410, -100, 2.4),
        ("PistonInnerRight", 165, 410, -100, 2.4),
        ("PistonMidLeft", -330, 310, 100, 3.0),
        ("PistonMidRight", 330, 310, 100, 3.0),
        ("PistonOuterLeft", -495, 410, -100, 1.9),
        ("PistonOuterRight", 495, 410, -100, 1.9),
    ]
    first = True
    for name, x, t, dy, sec in cols:
        s.part(name, "MovingPlatform", x, t + 160, [
            ("size", "Vector2(160, 320)"),
            ("travel", vec(0, dy)),
            ("one_way_sec", fmt(sec)),
        ], comment="""
The pistons: seven columns, 160 wide with 5 px seams (far narrower than a
body), each rising and falling 100 px between a top at y=310 and one at
y=410 -- 50 above and below the bastions. Neighbours start at opposite ends
of their stroke, and the three pairs run at different speeds (2.4 s, 3 s and
1.9 s a stroke), so the floor never repeats the same shape for long: a step
up becomes a step down, a pit opens between two risers and closes again. A
100 px step is a hook every weapon makes (Flatlands' low platform is 112).
Mirrored, so neither side is favoured.""" if first else None)
        first = False
    s.block("GantryLeft", -410, 222, 220, 24, "gantry", comment="""
Two gantries hung over the pistons, 100 px above a piston at the top of its
stroke and 200 above one at the bottom: a climb that is easy or hard
depending on when you make it. Each carries a pickup.""")
    s.block("GantryRight", 410, 222, 220, 24, "gantry")
    spawns(s, [(-680, 300), (680, 300), (-820, 300), (820, 300),
               (-750, 300), (750, 300), (-890, 300), (890, 300)], """
Spawns, all eight on the bastions (never on a piston: it moves), 70 px
apart, 90 px short of each outer edge. Spawn0-3 are the fair four.""")
    s.kill_zone(700)
    pickups(s, [(0, 240), (-410, 160), (410, 160)], """
Pickup spawn points: over the centre piston (a pickup any rider at the top
of its stroke collects) and on the two gantries. All well clear of the
bastion spawns.""")
    s.write("""
A foundry floor that will not hold still (issue #144, a large stage for five
to eight players). Two still bastions at the ends, and between them seven
pistons -- #18's MovingPlatform, stood on end -- heaving up and down out of
step, so the ground between the two camps is a moving staircase nobody gets
to settle on. Height changes hands every couple of seconds: whoever is on a
riser has the high ground until it sinks under them.

Large: the view is 2240 x 1260 (Stage.view_size), and the Main camera zooms
out to fit it. The floor spans x = -980..980, 88% of that view.""")


# --- Overpass -----------------------------------------------------------------
def overpass():
    s = Stage("Overpass")
    s.root([
        ("background_sky_top", "Color(0.05, 0.06, 0.12, 1)"),
        ("background_sky_bottom", "Color(0.14, 0.13, 0.22, 1)"),
        ("background_silhouette", "Color(0.07, 0.07, 0.12, 1)"),
        ("background_layers", 'PackedStringArray("clouds", "mountains", "city")'),
        ("view_size", "Vector2(2400, 1350)"),
    ])
    street = 420
    s.block("StreetLeft", -555, street + 20, 1010, 40, "street", comment="""
The street: two long halves, x = -1060..-50 and 50..1060, with a 100 px drain
between them down the middle -- twice a body's width -- and open ends. Those are the ring-outs; the deck only ever drops you onto the street.""")
    s.block("StreetRight", 555, street + 20, 1010, 40, "street")
    s.block("DeckLeft", -380, 172, 400, 24, "deck", comment="""
The deck: an overpass 260 px above the street, too high to hook from below.
Its ends (x = -580..-180 and 180..580) are solid; its middle is three
crumbling ledges (#18) over the drain, which give under whoever stops on
them and come back three seconds later.""")
    s.block("DeckRight", 380, 172, 400, 24, "deck")
    for name, x in (("SpanLeft", -120), ("SpanMiddle", 0), ("SpanRight", 120)):
        s.part(name, "CrumblingLedge", x, 172, [("size", "Vector2(112, 24)")])
    s.part("PadLeft", "BouncePad", -760, street - 8, [
        ("size", "Vector2(120, 16)"),
        ("launch_speed", "1250.0"),
    ], comment="""
The way up: a bounce pad (#52) on each half of the street, outboard of the
deck's ends. 1250 px/s throws a body about 530 px, clear of the deck's top,
and a swing on the way up steers it on. Standing on the street is safe;
crossing a pad is a ride. Getting down is a step off the deck.""")
    s.part("PadRight", "BouncePad", 760, street - 8, [
        ("size", "Vector2(120, 16)"),
        ("launch_speed", "1250.0"),
    ])
    spawns(s, [(-300, 110), (300, 110), (-360, 360), (360, 360),
               (-440, 110), (440, 110), (-500, 360), (500, 360)], """
Spawns: four on the solid ends of the deck, four on the street under them,
mirrored. None on a crumbling span or a pad.""")
    s.kill_zone(720)
    pickups(s, [(0, 110), (-200, 370), (200, 370), (-900, 370), (900, 370)], """
Pickup spawn points: on the crumbling middle span (stopping to take it starts
it crumbling), by the drain on each side of the street, and out at the
street's open ends, past the pads.""")
    s.write("""
A two-storey interchange (issue #144, a large stage for five to eight
players): a long street with a drain down the middle and open ends, and an
overpass deck above it that only the bounce pads reach. Eight players split
across the two levels, so there are two fights at once, and the crumbling
span in the middle of the deck drops whoever loiters on it onto the street
-- or into the drain under it.

Large: the view is 2400 x 1350 (Stage.view_size), and the Main camera zooms
out to fit it. The street spans x = -1060..1060, 88% of that view.""")


# --- Ziggurat -----------------------------------------------------------------
def ziggurat():
    s = Stage("Ziggurat")
    s.root([
        ("background_sky_top", "Color(0.16, 0.11, 0.1, 1)"),
        ("background_sky_bottom", "Color(0.3, 0.22, 0.16, 1)"),
        ("background_silhouette", "Color(0.14, 0.1, 0.08, 1)"),
        ("background_layers", 'PackedStringArray("clouds", "mountains", "rocks")'),
        ("view_size", "Vector2(2240, 1260)"),
    ])
    s.block("TierBase", 0, 470, 2080, 60, "base", comment="""
Three tiers, each 80 px above the one below (every weapon climbs that), and
a crumbling throne on top. The base runs x = -1040..1040 with open ends: the
only ring-out on the stage, so every fight ends with someone being walked
down the steps and off an edge.""")
    s.block("TierMiddle", 0, 400, 1520, 80, "middle")
    s.block("TierTop", 0, 320, 840, 80, "top")
    s.part("Throne", "CollapsingFloor", 0, 184, [
        ("size", "Vector2(220, 24)"),
        ("stand_sec", "3.0"),
        ("warn_sec", "1.0"),
    ], comment="""
The throne: a slab 108 px over the top tier (#53's collapsing floor, stood
on). Three seconds of anyone standing on it, in total, and it goes for the
round -- the king of the hill gets a short reign.""")
    s.part("RockLeft", "FallingRock", -560, -600, [("interval_sec", "5.0")], comment="""
Two falling rocks (#53) over the middle tier's flanks, between the spawns
and the pickups there. Their knock goes sideways away from the column, and
on a staircase that is downhill: a rock does not ring anyone out, it sends
them a step closer to the edge.""")
    s.part("RockRight", "FallingRock", 560, -600, [("interval_sec", "6.5")])
    spawns(s, [(-480, 300), (480, 300), (-940, 380), (940, 380),
               (-340, 220), (340, 220), (-820, 380), (820, 380)], """
Spawns, mirrored: the middle tier, the base (twice a side) and the top
tier. None on the throne.""")
    s.kill_zone(700)
    pickups(s, [(0, 110), (-640, 310), (640, 310)], """
Pickup spawn points: over the throne, and on the outer end of the middle
tier on each side, under a rock column's reach.""")
    s.write("""
A stepped pyramid (issue #144, a large stage for five to eight players):
king of the hill. Three broad tiers climb to a throne that gives way under
whoever holds it; falling rocks knock people down the flanks; and the only
way out of the round, until the lava, is off the ends of the base.

Large: the view is 2240 x 1260 (Stage.view_size), and the Main camera zooms
out to fit it. The base spans x = -1040..1040, 93% of that view.""")


pistons()
overpass()
ziggurat()
