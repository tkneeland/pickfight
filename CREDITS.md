# Credits

## Sound effects

Every sound under `assets/sfx/` is by **Kenney** (https://kenney.nl), except
the synthesised announcer lines listed under "Announcer voice" below. Each
Kenney sound is released under **Creative Commons Zero (CC0 1.0)**:
http://creativecommons.org/publicdomain/zero/1.0/. Each pack's `License.txt`
says so. Credit is not required, but it is given here anyway.

The files are shipped exactly as the packs have them, under the same names.
Each one comes from its pack's `Audio/` folder. `scripts/Sfx.gd` (`SOUNDS`)
maps each game event to its files; ADR-0016 explains the design.

The sources are four Kenney packs, all CC0 1.0:

| Pack | Page | Download | Folder here |
|---|---|---|---|
| Impact Sounds | https://kenney.nl/assets/impact-sounds | https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip | `assets/sfx/kenney_impact/` |
| RPG Audio | https://kenney.nl/assets/rpg-audio | https://kenney.nl/media/pages/assets/rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip | `assets/sfx/kenney_rpg/` |
| Sci-fi Sounds | https://kenney.nl/assets/sci-fi-sounds | https://kenney.nl/media/pages/assets/sci-fi-sounds/6b296f9ecf-1677589334/kenney_sci-fi-sounds.zip | `assets/sfx/kenney_scifi/` |
| Interface Sounds | https://kenney.nl/assets/interface-sounds | https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip | `assets/sfx/kenney_interface/` |

The files:

| File | Pack | Licence | Used for |
|---|---|---|---|
| `kenney_impact/impactMining_000.ogg`, `_001`, `_002` | Impact Sounds | CC0 1.0 | pickaxe hit |
| `kenney_rpg/knifeSlice.ogg`, `knifeSlice2.ogg`, `drawKnife1.ogg` | RPG Audio | CC0 1.0 | sword hit |
| `kenney_rpg/chop.ogg` | RPG Audio | CC0 1.0 | axe hit |
| `kenney_impact/impactWood_heavy_000.ogg`, `_001` | Impact Sounds | CC0 1.0 | axe hit |
| `kenney_impact/impactPlank_medium_000.ogg`, `_001`, `_002` | Impact Sounds | CC0 1.0 | staff hit |
| `kenney_impact/impactMetal_light_000.ogg`, `_001`, `_002` | Impact Sounds | CC0 1.0 | dagger hit |
| `kenney_impact/impactPunch_heavy_000.ogg`, `_001`, `_002` | Impact Sounds | CC0 1.0 | boomstick hit (a close-range strike with the gun) |
| `kenney_scifi/explosionCrunch_000.ogg`, `_001` | Sci-fi Sounds | CC0 1.0 | boomstick shot |
| `kenney_impact/impactTin_medium_000.ogg`, `_001` | Impact Sounds | CC0 1.0 | bullet impact |
| `kenney_impact/impactMetal_medium_000.ogg`, `_001`, `_002` | Impact Sounds | CC0 1.0 | clash (two heads meeting) |
| `kenney_impact/footstep_concrete_000.ogg`, `_001`, `_002` | Impact Sounds | CC0 1.0 | head striking terrain |
| `kenney_impact/impactSoft_heavy_000.ogg`, `_001`, `_002` | Impact Sounds | CC0 1.0 | landing |
| `kenney_scifi/lowFrequency_explosion_000.ogg` | Sci-fi Sounds | CC0 1.0 | elimination |
| `kenney_scifi/lowFrequency_explosion_001.ogg` | Sci-fi Sounds | CC0 1.0 | lava starts to rise |
| `kenney_scifi/thrusterFire_000.ogg` | Sci-fi Sounds | CC0 1.0 | lava sizzle (cut to 1.2 s) |
| `kenney_interface/tick_001.ogg` | Interface Sounds | CC0 1.0 | lava countdown (3, 2, 1) |
| `kenney_interface/bong_001.ogg` | Interface Sounds | CC0 1.0 | round start |
| `kenney_interface/maximize_006.ogg` | Interface Sounds | CC0 1.0 | modifier announced |
| `kenney_interface/confirmation_002.ogg` | Interface Sounds | CC0 1.0 | round win |
| `kenney_interface/pluck_001.ogg` | Interface Sounds | CC0 1.0 | player joined |

That is 39 files, about 0.6 MB in all. The `sfx_sound_files_exist` scenario
fails if a file is missing, or if a shipped file is not used.

Added for the stage parts (issue #76), from the same packs and under the same licence:

| File | Pack | Licence | Used for |
|---|---|---|---|
| `kenney_scifi/forceField_000.ogg`, `_001` | Sci-fi Sounds | CC0 1.0 | bounce pad launch |
| `kenney_scifi/spaceEngineLow_000.ogg` | Sci-fi Sounds | CC0 1.0 | wind tell |
| `kenney_scifi/thrusterFire_001.ogg`, `_002` | Sci-fi Sounds | CC0 1.0 | wind gust |
| `kenney_scifi/spaceEngineLarge_000.ogg` | Sci-fi Sounds | CC0 1.0 | falling rock warning rumble |
| `kenney_scifi/explosionCrunch_002.ogg`, `_003`, `_004` | Sci-fi Sounds | CC0 1.0 | falling rock impact |
| `kenney_rpg/creak1.ogg`, `creak2.ogg`, `creak3.ogg` | RPG Audio | CC0 1.0 | collapsing floor warning |
| `kenney_impact/impactWood_heavy_002.ogg`, `_003`, `_004` | Impact Sounds | CC0 1.0 | collapsing floor collapse |
| `kenney_impact/impactGeneric_light_000.ogg`, `_001`, `_002` | Impact Sounds | CC0 1.0 | breakable wall hit |
| `kenney_impact/impactPlate_heavy_000.ogg`, `_001` | Impact Sounds | CC0 1.0 | breakable wall break |

## Announcer voice

Added for issue #152. `scripts/Sfx.gd` maps each line to its file (the
`announce_*` entries), and `scripts/Announcer.gd` decides when each is said.

Five lines are recordings from Kenney's **Voiceover Pack: Fighter**, released
under **CC0 1.0** (the pack's `License.txt` says so). They are shipped
unchanged, only renamed:

- Page: https://kenney.nl/assets/voiceover-pack-fighter
- Download: https://kenney.nl/media/pages/assets/voiceover-pack-fighter/6ceb77c6f1-1677589837/kenney_voiceover-pack-fighter.zip

| File | Pack file | Licence | Used for |
|---|---|---|---|
| `announcer/count_3.ogg` | `Audio/3.ogg` | CC0 1.0 | "3" |
| `announcer/count_2.ogg` | `Audio/2.ogg` | CC0 1.0 | "2" |
| `announcer/count_1.ogg` | `Audio/1.ogg` | CC0 1.0 | "1" |
| `announcer/fight.ogg` | `Audio/fight.ogg` | CC0 1.0 | "FIGHT!" |
| `announcer/winner.ogg` | `Audio/winner.ogg` | CC0 1.0 | "Winner!" |

No CC0 recording could be found for "KO!", "Double KO!" or the modifier
names, so those were **synthesised** for this repository. The speech engine
is espeak-ng (voice `en-us+m3`, 140 wpm, pitch 30), run through the
`espeakng-loader` Python wheel. Each clip was then trimmed, given a short
two-tap echo, normalised, faded in and out, and encoded as Ogg Vorbis. The
engine's own licence does not cover what it speaks. These clips are
dedicated to the public domain under **CC0 1.0** like the rest.

| File | Text spoken | Licence | Used for |
|---|---|---|---|
| `announcer/ko.ogg` | "Kay, Oh!" | CC0 1.0 (synthesised) | "KO!" |
| `announcer/double_ko.ogg` | "Double, Kay Oh!" | CC0 1.0 (synthesised) | "Double KO!" |
| `announcer/low_gravity.ogg` | "Low gravity!" | CC0 1.0 (synthesised) | modifier LOW GRAVITY |
| `announcer/heavy_weapons.ogg` | "Heavy weapons!" | CC0 1.0 (synthesised) | modifier HEAVY WEAPONS |
| `announcer/big_heads.ogg` | "Big heads!" | CC0 1.0 (synthesised) | modifier BIG HEADS |
| `announcer/fast_lava.ogg` | "Fast lava!" | CC0 1.0 (synthesised) | modifier FAST LAVA |
| `announcer/slippery_floor.ogg` | "Slippery floor!" | CC0 1.0 (synthesised) | modifier SLIPPERY FLOOR |

That is 12 files, about 0.17 MB in all.

## Music

Added for issue #118 (ADR-0017). Every track is from OpenGameArt and each
one's page gives its licence as **CC0** (Creative Commons Zero 1.0,
http://creativecommons.org/publicdomain/zero/1.0/). I checked each licence
page on 2026-09-25. Credit is optional under CC0, but it is given here anyway.

The audio is not changed. Only the file names are, so that they carry no
spaces and say what each track is used for. `scripts/Music.gd` (`TRACKS`)
maps each one to its use.

| File | Track | Author | Licence | Licence page | Downloaded from | Used for |
|---|---|---|---|---|---|---|
| `assets/music/lobby_snowfall_looped.ogg` | Snowfall (Looped ver.) | Kistol | CC0 1.0 | https://opengameart.org/content/snowfall | https://opengameart.org/sites/default/files/Snowfall%20%28Looped%20ver.%29_0.ogg | lobby and menu (chill) |
| `assets/music/fight_fast_fight_looped.ogg` | Fast fight / battle music (looped) | Ville Nousiainen; loop edit by XCVG | CC0 1.0 | https://opengameart.org/content/fast-fight-battle-music-looped | https://opengameart.org/sites/default/files/fight_looped.ogg | fight, first in the rotation |
| `assets/music/fight_nes_shooter_mars.ogg` | Mars, from "NES Shooter Music (5 tracks, 3 jingles)" | SketchyLogic | CC0 1.0 | https://opengameart.org/content/nes-shooter-music-5-tracks-3-jingles | https://opengameart.org/sites/default/files/Mars.ogg | fight, second in the rotation |

Notes:

- Snowfall is the author's own seamless-loop file.
- For the other two, the page lists WAV downloads. The OGG used here is the
  Vorbis copy of the same audio that OpenGameArt serves for the page's
  player. It is much smaller than the WAV.
- The fast-fight page says its licence is "same as the original". The
  original is Ville Nousiainen's "Fast fight / battle music",
  https://opengameart.org/content/fast-fight-battle-music, and its page also
  gives CC0 (checked the same day). Ville Nousiainen asks, as an optional
  credit, for a link to http://soundcloud.com/mutkanto.
- Credit for Snowfall: "Music by Kistol, but credit is not required."

That is three files, about 1.6 MB in all. The `music_tracks_exist_and_credited`
scenario fails if a track is missing, if it is not listed here with CC0, or if
a shipped music file is unused.
