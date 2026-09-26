#!/usr/bin/env python3
"""Issue #137, as run: widen every stage's terrain across the fixed 1600x900
view and give every stage 8 spawn points. One-shot against origin/main's
stages (f3d1e91); kept as the record of what changed and why. Uses
tools/stage_tscn.py.

    python3 widen_stages.py <repo>
"""
import re
import sys
from pathlib import Path

REPO = Path(sys.argv[1])
sys.path.insert(0, str(REPO / "tools"))
from stage_tscn import Scene as _Scene, body, marker, add_spawns, fmt, shape_of  # noqa: E402

STAGES = REPO / "scenes" / "stages"


def Scene(name):
    return _Scene(STAGES / f"{name}.tscn")

EIGHT = ("Spawns 4-7 (issue #137): eight players. {}")


# ---------------------------------------------------------------- stages
def flatlands():
    s = Scene("Flatlands")
    s.set_sub("RectangleShape2D_ground", "size", "Vector2(1440, 40)")
    s.rect_visual("GroundVisual", 1440, 40)
    add_spawns(s, {0: (-60, 0), 1: (60, 0), 4: (-640, 0), 5: (640, 0), 6: (-150, 0), 7: (150, 0)},
               EIGHT.format("Two more out on each end of the widened floor, two more in the middle;\n"
                            "none drops onto a platform, so every pickup is still a climb away."))
    s.comment_before("Ground", "Widened for issue #137: the floor ran x=+-600, leaving 200 px of open air\n"
                     "at each side of the view to be knocked into; it now runs +-720, 80 px short\n"
                     "of each edge. The open ends are still the ring-outs, just further out.")
    s.save()


def pillars():
    s = Scene("Pillars")
    s.insert_after("PillarRight", body("PillarFarLeft", -640, 270, "RectangleShape2D_pillar", 140, 300) + "\n" +
                   body("PillarFarRight", 640, 270, "RectangleShape2D_pillar", 140, 300))
    s.comment_before("PillarFarLeft", "Outer columns (issue #137): the same 140 px column and the same 180 px gap\n"
                     "again outboard of each side, so the row of tops runs x=+-710 across the view.\n"
                     "Still no floor anywhere: every gap is still a committed swing over a fall,\n"
                     "but a player knocked off the end column lands on another top more often.")
    add_spawns(s, {4: (-675, 60), 5: (675, 60), 6: (-605, 60), 7: (605, 60)},
               EIGHT.format("Two on each new outer column, side by side like 2 and 3."))
    s.save()


def ferry():
    s = Scene("Ferry")
    s.set_sub(pad_shape(s), "size", "Vector2(420, 24)")
    s.pos("PadLeft", -510, 380)
    s.pos("PadRight", 510, 380)
    s.rect_visual("PadLeftVisual", 420, 24)
    s.rect_visual("PadRightVisual", 420, 24)
    s.comment_before("PadLeft", "Widened for issue #137: each pad ran out to x=+-600; now +-720. The inner\n"
                     "edges (and so the 600 px of water and the barge's run-in) are untouched.")
    add_spawns(s, {4: (-650, 300), 5: (650, 300), 6: (-360, 300), 7: (360, 300)},
               EIGHT.format("Outboard on the widened pads, and at each dock's lip."))
    s.save()


def pad_shape(s):
    h = s.node("PadLeftShape")
    return re.search(r'SubResource\("([^"]+)"\)', s.lines[h + 1]).group(1)





def highrise():
    s = Scene("Highrise")
    s.set_sub(shape_of(s, "GroundShape"), "size", "Vector2(1440, 40)")
    s.rect_visual("GroundVisual", 1440, 40)
    s.comment_before("Ground", "Widened for issue #137: the ground strip was 800 px (x=+-400); it now runs\n"
                     "+-720, so the climb starts from a floor that is hard to be knocked off\n"
                     "rather than a short strip. The rungs above are untouched.")
    add_spawns(s, {4: (-420, 340), 5: (420, 340), 6: (-560, 340), 7: (560, 340)},
               EIGHT.format("On the widened ground, outboard of the rungs, so nobody starts a rung up."))
    s.save()


def erosion():
    s = Scene("Erosion")
    s.set_sub(shape_of(s, "IslandShape"), "size", "Vector2(448, 24)")
    s.rect_visual("IslandVisual", 448, 24)
    # island +-224; 32 px gap; inner ledges 160 wide; 40 px gaps outward.
    s.pos("LedgeB", -336, 300)
    s.pos("LedgeC", 336, 300)
    s.pos("LedgeA", -536, 300)
    s.pos("LedgeD", 536, 300)
    s.insert_after("LedgeD", ledge_block("LedgeE", -700) + "\n" + ledge_block("LedgeF", 700))
    s.comment_before("LedgeE", "Outer ledges (issue #137): 120 px, 24 px outboard of A and D, so the\n"
                     "crumbling floor runs x=+-760. Crumbling like the rest -- the outer rim of\n"
                     "the stage is ground that goes away, not ground to camp on.")
    s.comment_before("Island", "Widened for issue #137 from 216 to 448 px so eight spawns fit on permanent\n"
                     "ground (none on a crumbling ledge, per US-7); every ledge moved out with it,\n"
                     "gaps unchanged (32 px island-to-ledge, 40 px ledge-to-ledge).")
    add_spawns(s, {0: (-28, 220), 1: (28, 220), 2: (-84, 220), 3: (84, 220),
                   4: (-140, 220), 5: (140, 220), 6: (-196, 220), 7: (196, 220)},
               EIGHT.format("All eight on the widened island, 56 px apart."))
    s.pos("PickupSpawn0", -336, 240)
    s.pos("PickupSpawn1", 336, 240)
    s.save()


def ledge_block(name, x, w=120):
    return (f'[node name="{name}" parent="." instance=ExtResource("3")]\n'
            f"position = Vector2({fmt(x)}, 300)\nsize = Vector2({fmt(w)}, 24)\nwarn_sec = 1.0\n")


def islands():
    s = Scene("Islands")
    shape = shape_of(s, "IslandAShape")
    s.add_sub_rect("RectangleShape2D_islet", 120, 24)
    s.insert_after("IslandD", body("IslandE", -670, 300, "RectangleShape2D_islet", 120, 24) + "\n" +
                   body("IslandF", 670, 300, "RectangleShape2D_islet", 120, 24))
    s.comment_before("IslandE", "Outer islets (issue #137): 120 px, one each side, 100 px off IslandA and\n"
                     "IslandD -- the same gap as A to B -- so the chain runs x=+-730 and a player\n"
                     "knocked off an end island has somewhere to land. Same height as the rest.")
    add_spawns(s, {4: (-670, 220), 5: (670, 220), 6: (-480, 220), 7: (480, 220)},
               EIGHT.format("One on each outer islet, and a second on IslandA and IslandD."))
    s.save()


def furnace():
    s = Scene("Furnace")
    s.set_sub(shape_of(s, "GroundShape"), "size", "Vector2(1300, 40)")
    s.rect_visual("GroundVisual", 1300, 40)
    for side, sign in (("Left", -1), ("Right", 1)):
        for i in range(9):
            s.pos(f"WallHazard{side}{i}", sign * 730, -16 + 48 * i)
    s.comment_before("Ground", "Widened for issue #137: the floor was 400 px (x=+-200), too short to hold\n"
                     "eight players; it now runs +-650 and the two hazard columns moved out with it\n"
                     "(centres +-730, inner faces flush with the floor's ends at +-650, outer faces\n"
                     "at the view's edge). Still sealed wall to wall: the hazard is still the wall,\n"
                     "and reaching the edge is still the mistake -- there is just more floor first.")
    add_spawns(s, {4: (-300, 100), 5: (300, 100), 6: (-480, 100), 7: (480, 100)},
               EIGHT.format("Out on the widened floor, well short of the hazard walls."))
    s.save()


def gauntlet():
    s = Scene("Gauntlet")
    s.set_sub("RectangleShape2D_bank", "size", "Vector2(430, 40)")
    s.pos("BankLeft", -505, 320)
    s.pos("BankRight", 505, 320)
    s.rect_visual("BankLeftVisual", 430, 40)
    s.rect_visual("BankRightVisual", 430, 40)
    s.comment_before("BankLeft", "Banks widened outward for issue #137: x=+-290..+-660 -> +-290..+-720,\n"
                     "running on under the low ledges. The gaps under the ceiling are untouched.")
    add_spawns(s, {4: (-600, 250), 5: (600, 250), 6: (-445, 250), 7: (445, 250)},
               EIGHT.format("Two more on each widened bank, under open sky or the low ledge."))
    s.save()


def cascade():
    s = Scene("Cascade")
    s.set_sub("RectangleShape2D_floor", "size", "Vector2(1440, 40)")
    s.rect_visual("FloorVisual", 1440, 40)
    s.add_sub_rect("RectangleShape2D_balcony", 200, 24)
    s.insert_after("TopPlatform", body("BalconyLeft", -560, -260, "RectangleShape2D_balcony", 200, 24) + "\n" +
                   body("BalconyRight", 560, -260, "RectangleShape2D_balcony", 200, 24))
    s.comment_before("BalconyLeft", "Balconies (issue #137): two more static tops at TopPlatform's height, far\n"
                     "out to each side, so eight players can all start high. They are off the\n"
                     "staircase: the way down from one is a drop to the widened floor, and the\n"
                     "way back up is the same ping-pong run as from anywhere else.")
    s.comment_before("Floor", "Widened for issue #137 from 800 px (x=+-400) to +-720, so a rider thrown\n"
                     "off the staircase, or dropping off a balcony, lands on it.")
    add_spawns(s, {4: (-600, -352), 5: (600, -352), 6: (-520, -352), 7: (520, -352)},
               EIGHT.format("Two on each balcony, level with Spawn0-3, so the highest spawn -- which\n"
                            "sets the lava's rise -- is unchanged."))
    s.save()


def slant():
    s = Scene("Slant")
    pts = [(-720, 380), (-360, 380), (300, 180), (720, 180), (720, 440), (-720, 440)]
    s.poly("LandmassShape", pts)
    s.poly("LandmassVisual", pts)
    s.comment_before("Landmass", "Widened for issue #137: both flats run out to x=+-720 (they stopped at\n"
                     "+-560). The slope between them is untouched.")
    add_spawns(s, {4: (-560, 300), 5: (520, 100), 6: (-650, 300), 7: (620, 100)},
               EIGHT.format("Further out along each widened flat."))
    s.save()


def bowl():
    s = Scene("Bowl")
    left = [(-660, 208), (-300, 208), (-300, 288), (-60, 288), (-60, 440), (-660, 440)]
    right = [(-x, y) for x, y in left]
    s.poly("LandLeftShape", left)
    s.poly("LandLeftVisual", left)
    s.poly("LandRightShape", right)
    s.poly("LandRightVisual", right)
    s.pos("WallLeft", -680, s_wall_y(s))
    s.pos("WallRight", 680, s_wall_y(s))
    s.comment_before("LandLeft", "Widened for issue #137: each upper step runs out to x=+-660 (was +-500),\n"
                     "with the walls moved out to match (+-660..+-700). Still sealed at the sides;\n"
                     "the drain is still the only way out.")
    add_spawns(s, {4: (-490, 140), 5: (490, 140), 6: (-580, 140), 7: (580, 140)},
               EIGHT.format("On the widened upper steps, outboard of Spawn0 and 1."))
    s.save()


def s_wall_y(s):
    h = s.node("WallLeft")
    m = re.search(r"Vector2\([^,]+, ([^)]+)\)", s.lines[h + 1])
    return float(m.group(1))


def springboard():
    s = Scene("Springboard")
    shape = shape_of(s, "BankLeftShape")
    s.set_sub(shape, "size", "Vector2(430, 40)")
    s.pos("BankLeft", -505, 320)
    s.pos("BankRight", 505, 320)
    s.rect_visual("BankLeftVisual", 430, 40)
    s.rect_visual("BankRightVisual", 430, 40)
    s.comment_before("BankLeft", "Banks widened outward for issue #137: x=+-290..+-660 -> +-290..+-720.\n"
                     "The pit and the pad are untouched.")
    add_spawns(s, {0: (-490, 250), 1: (490, 250), 2: (-415, 250), 3: (415, 250),
                   4: (-565, 250), 5: (565, 250), 6: (-340, 250), 7: (340, 250)},
               EIGHT.format("Four on each bank, 75 px apart; the bank pickups moved out to the\n"
                            "widened ends to stay 120 px clear of them (#111)."))
    s.pos("PickupSpawn2", -690, 260)
    s.pos("PickupSpawn3", 690, 260)
    s.save()


def gale():
    s = Scene("Gale")
    s.set_sub(shape_of(s, "BankLeftShape"), "size", "Vector2(430, 40)")
    s.pos("BankLeft", -505, 320)
    s.pos("BankRight", 505, 320)
    s.rect_visual("BankLeftVisual", 430, 40)
    s.rect_visual("BankRightVisual", 430, 40)
    s.comment_before("BankLeft", "Banks widened outward for issue #137: x=+-290..+-660 -> +-290..+-720.\n"
                     "The gaps and the gusts over them are untouched.")
    add_spawns(s, {4: (-600, 250), 5: (600, 250), 6: (-445, 250), 7: (445, 250)},
               EIGHT.format("Two more on each widened bank, still outside both gusts."))
    s.save()


def carousel():
    s = Scene("Carousel")
    s.set_sub(shape_of(s, "ShoulderLeftShape"), "size", "Vector2(220, 40)")
    s.pos("ShoulderLeft", -680, 320)
    s.pos("ShoulderRight", 680, 320)
    s.rect_visual("ShoulderLeftVisual", 220, 40)
    s.rect_visual("ShoulderRightVisual", 220, 40)
    s.comment_before("ShoulderLeft", "Shoulders widened inward for issue #137 (x=+-590..+-790 ->\n"
                     "+-570..+-790) to fit four spawns each; the gap to each see-saw is now 40 px.")
    add_spawns(s, {0: (-765, 250), 1: (765, 250), 2: (-705, 250), 3: (705, 250),
                   4: (-645, 250), 5: (645, 250), 6: (-585, 250), 7: (585, 250)},
               EIGHT.format("Four on each shoulder, 60 px apart: still fixed footing for everyone."))
    s.save()


def rockfall():
    s = Scene("Rockfall")
    s.set_sub(shape_of(s, "BankLeftShape"), "size", "Vector2(390, 40)")
    s.pos("BankLeft", -525, 380)
    s.pos("BankRight", 525, 380)
    s.rect_visual("BankLeftVisual", 390, 40)
    s.rect_visual("BankRightVisual", 390, 40)
    s.set_sub(shape_of(s, "HighLedgeLeftShape"), "size", "Vector2(160, 24)")
    s.pos("HighLedgeLeft", -640, 240)
    s.pos("HighLedgeRight", 640, 240)
    s.rect_visual("HighLedgeLeftVisual", 160, 24)
    s.rect_visual("HighLedgeRightVisual", 160, 24)
    s.pos("RockLedgeRight", 640, -430)
    s.comment_before("BankLeft", "Banks widened outward for issue #137: x=+-330..+-630 -> +-330..+-720.\n"
                     "The lookout ledges moved out with the banks' outer shoulders (now\n"
                     "x=+-560..+-720, same height) and RockLedgeRight with its ledge, which\n"
                     "leaves room for four spawns per bank under open sky. The canyon and\n"
                     "bridge are untouched.")
    add_spawns(s, {0: (-415, 320), 1: (415, 320), 2: (-355, 320), 3: (355, 320),
                   4: (-475, 320), 5: (475, 320), 6: (-535, 320), 7: (535, 320)},
               EIGHT.format("Four on each bank, 60 px apart, all inboard of the lookout ledges."))
    s.pos("PickupSpawn1", -640, 200)
    s.pos("PickupSpawn2", 640, 200)
    s.save()


def sinkhole():
    s = Scene("Sinkhole")
    rim = ('[node name="{n}" parent="." instance=ExtResource("3")]\n'
           "position = Vector2({x}, 300)\nsize = Vector2(300, 24)\ntrigger = \"timed\"\n"
           "collapse_after_sec = 15.0\nwarn_sec = 1.5\n")
    s.insert_before("FarLeft", rim.format(n="RimLeft", x=-570))
    s.insert_after("FarRight", rim.format(n="RimRight", x=570))
    s.comment_before("RimLeft", "Rim slabs (issue #137): timed collapsing floor outboard of each Far slab\n"
                     "across the same 20 px seam, x=+-420..+-720, so the strip runs nearly the\n"
                     "view's width at round start. They go at 15 s, five seconds before the Far\n"
                     "slabs: the floor now shrinks in two visible steps (1440 -> 800 -> 480 px),\n"
                     "both on a schedule, both well ahead of the lava.")
    add_spawns(s, {4: (-620, 220), 5: (620, 220), 6: (-520, 220), 7: (520, 220)},
               EIGHT.format("On the rim slabs: eight do not fit on the core, and the rim is timed\n"
                            "(15 s), never stood_on, so nobody starts on ground already ticking."))
    s.save()


def bulwark():
    s = Scene("Bulwark")
    s.set_sub(shape_of(s, "BastionLeftShape"), "size", "Vector2(420, 40)")
    s.pos("BastionLeft", -510, 320)
    s.pos("BastionRight", 510, 320)
    s.rect_visual("BastionLeftVisual", 420, 40)
    s.rect_visual("BastionRightVisual", 420, 40)
    s.comment_before("BastionLeft", "Bastions widened outward for issue #137: x=+-300..+-600 -> +-300..+-720.\n"
                     "Their outer ends are still open sky; the keep and walls are untouched.")
    add_spawns(s, {4: (-530, 250), 5: (530, 250), 6: (-370, 250), 7: (370, 250)},
               EIGHT.format("Three on each bastion with Spawn2/3; the bastion pickups moved out to\n"
                            "the widened ends to stay 120 px clear of them (#111)."))
    s.pos("PickupSpawn3", -660, 264)
    s.pos("PickupSpawn4", 660, 264)
    s.save()


for fn in (flatlands, pillars, ferry, highrise, erosion, islands, furnace, gauntlet, cascade,
           slant, bowl, springboard, gale, carousel, rockfall, sinkhole, bulwark):
    fn()
    print("edited", fn.__name__)
