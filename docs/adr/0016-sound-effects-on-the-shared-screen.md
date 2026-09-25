# 16. Sound effects play on the shared screen, driven by signals

- Status: Accepted
- Date: 2026-09-25

## Context

The game had no sound (issue #75). The owner decided the scope:

- sound effects only, no music;
- each weapon has its own hit sound;
- pitch and volume follow how hard the hit was;
- sounds pan in stereo with screen position;
- sounds go through an SFX bus, with a limit on how many copies overlap;
- there is a master volume and a mute.

The owner also listed the events that need a sound:

- combat: clash, hit, kill, a head meeting terrain, a boomstick shot, and a bullet's impact;
- landing;
- lava;
- rounds and the UI: countdown, round start, modifier, round win, and a player joining.

Stage-part sounds come later, in #76, which builds on these hooks.

Several constraints shaped the design:

- The host renders the one shared screen (ADR-0001), and phones only send
  input (ADR-0002). So the host is the only place a sound can play.
- `Player.gd` and `WeaponHead.gd` are being edited by other open issues (#66,
  #71, #72, #73). `RoundManager.gd` and `Main.tscn` are shared hot files.
  Edits to all of them have to be small and additive.
- A fresh clone has no `.godot/` import cache. Scripts must not use
  `class_name` or `preload()` anything that cannot load in that state
  (CLAUDE.md, #21).
- The scenario suite runs `--headless`, where nothing can be heard.

## Decision

- **One autoload, `Sfx`** (`scripts/Sfx.gd`). It is the only thing that plays
  sound. Its API is `play(name, position = null, strength = 1.0)`.
  - `name` is a key of its `SOUNDS` table. Each entry lists 1–3 variant files,
    and can also set a dB offset, an overlap cap, `positional: false` (flat) and
    `max_sec` (fade out early).
  - `position` is a world position. With one, the sound plays through an
    `AudioStreamPlayer2D` and pans with the camera. Round and UI sounds play
    flat through an `AudioStreamPlayer`.
  - `strength` (0..1) scales gain from 0.35 to 1.0, so a soft hit is about
    9 dB quieter than a hard one. It also lowers the pitch from ×1.08 to ×0.92,
    so harder hits sound heavier. Each play adds ±4 % random pitch jitter, and
    the same variant is never picked twice in a row.
- **Hooks watch signals; the game never calls audio.** `scripts/SfxHooks.gd`
  is a child of `Sfx`. It works like `HitFeedback.gd`: it watches
  `SceneTree.node_added` and connects to the signals of the nodes it
  recognises. It recognises a node by the signals it carries, never by
  `class_name`.

  | Node | Signals | Sounds |
  |---|---|---|
  | Player | `strike_landed`, `eliminated`, `body_entered` | `hit_<set>`, `eliminated`, `land` |
  | WeaponHead | `struck_world`, `clashed` (new) | `head_terrain`, `clash` |
  | Projectile | `ready`, `impacted` (new) | `fire_<set>`, `bullet_impact` |
  | KillZone | `rise_countdown`, `rise_began` (new), `body_entered` | `countdown`, `lava_rise`, `lava_sizzle` |
  | RoundManager | `round_started`, `round_won`, `modifier_announced` (new) | `round_start`, `round_win`, `modifier` |
  | ControllerServer | `player_joined` (new) | `join` |

  The game scripts only gained signal declarations and one-line `emit`s. None
  of them knows sound exists. A scenario that builds any of these nodes gets
  its sounds without doing anything.
- **What counts as an event:**
  - **Hit:** only a strike that deals damage. A 0-damage contact is silent, so
    a head dragged along someone does not chatter. Strength is damage / 60.
  - **Head on terrain:** a head arriving at 300 px/s or faster. A clash needs
    150 px/s or faster. Each head has a 5-frame cooldown.
  - **Landing:** judged on the body's velocity before the physics step. By
    the time `body_entered` reports the contact, the solver has already
    stopped the body. So the hooks record each player's `linear_velocity` in
    their own `_physics_process`, which runs first
    (`process_physics_priority = -100`).
  - **Countdown:** the game has no countdown before a round. So "countdown"
    means ticks in the last three seconds of the lava's grace period, then a
    rumble when it starts to rise. Read the lava as the round's clock.
  - **Join:** comes from ControllerServer, because only a first claim of a
    slot is a join. A reconnect is not.
- **Per-weapon sets.** `WeaponStats.sound_set` (a `StringName`) is set in each
  `resources/*.tres`: pickaxe, sword, axe, staff, dagger, boomstick. A strike
  plays `hit_<set>` of the weapon the attacker really holds
  (`Player.weapon_stats`, not a round modifier's copy). A bullet plays
  `fire_<set>` of its shooter's weapon. An unknown set falls back to the
  pickaxe's sound.
- **The SFX bus and the overlap cap.**
  - `Sfx` creates an `SFX` bus that sends to Master, when the bus is missing.
    It is made at runtime, so no `default_bus_layout.tres` is needed.
  - Each sound owns a pool of at most `overlap` players (default 3). When the
    pool is full, the play steals the copy furthest into its playback.
- **Master volume and mute** act on the Master bus. They are saved in
  `user://audio.cfg`. `SfxSettings.gd` is a small "Sound" button in the
  bottom-right corner that opens a volume slider and a mute box. `M` toggles
  mute. `Sfx` builds it only when the game's own scene is running, so the
  scenario runner never has one.
- **Loading works without an import cache.**
  - Nothing `preload()`s audio. When the raw `.ogg` is on disk (a checkout),
    `Sfx` reads it with `AudioStreamOggVorbis.load_from_file()`, which needs
    no `.godot/`.
  - In an exported build the raw file is gone, so it falls back to `load()`.
  - A missing file warns once and plays nothing.
- **Headless is safe.** Godot's dummy audio driver accepts every call. Before
  `Sfx` is in the tree (the first frame of a `-s` script), `play()` only
  records the request.
- **Test hook.** `start_recording()` / `recorded()` log every `play()`
  request (name, position, strength, volume, pitch). The `sfx_*` scenarios
  spy on those requests, not on the speakers.
- **Assets.** Only CC0 files from Kenney's Impact, RPG Audio, Sci-fi and
  Interface packs are used. They live under `assets/sfx/<pack>/`, about
  0.6 MB in all. Every file is listed in `CREDITS.md`. A scenario fails if a
  shipped file is unused or a referenced file is missing.

## Consequences

- Adding a sound source (#76) takes one of two routes:
  - a signal on the part plus one `_watch_*` branch in `SfxHooks`;
  - for a part that already knows when it acts, a direct
    `get_node("/root/Sfx").play(...)`.

  Either way, the part adds a `SOUNDS` entry.
- Signals are only ever added to hot files, never moved. The new emits sit
  next to state changes that already existed, and gameplay does not read them.
- The headless suite cannot tell whether a sound *sounds* right. Every
  asset choice needs a listen test on the host. The likeliest to need
  changes are these stand-ins: the boomstick's sci-fi "explosionCrunch" for a
  gunshot, footsteps for a head on terrain, and a thruster cut to 1.2 s for
  the lava sizzle.
- Phones stay silent. Any audio feedback on a phone would be a separate
  decision, like the buzz in ADR-0013.
