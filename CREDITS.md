# Credits

## Sound effects

Every sound under `assets/sfx/` is by **Kenney** (https://kenney.nl). Each
one is released under **Creative Commons Zero (CC0 1.0)**:
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
