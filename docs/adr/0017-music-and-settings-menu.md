# 17. Music and a settings menu on the shared screen

- Status: Accepted
- Date: 2026-09-25

## Context

ADR-0016 added sound effects and left music out. Issue #118 adds it. The
owner decided the scope:

- CC0 music loops: one chill track for the lobby and menus, and one or two
  upbeat fight tracks. Each is credited in CREDITS.md.
- The music ducks briefly under the round-win sound, and has its own volume.
- A settings menu, opened by a key or a button on the shared screen. It has
  master, SFX and music volume, mute, and a fullscreen toggle. The settings
  are saved with ConfigFile.
- The lobby and match flow (#120) is being built in parallel, on the other
  dev's machine. It needs a simple `Music.play_lobby()` / `play_fight()`
  API. Until it lands, rounds default to fight music.

The constraints from ADR-0016 still apply. `RoundManager.gd` and
`Main.tscn` are hot shared files, so this issue does not touch them. There
is no `class_name`, and nothing may need the `.godot/` import cache.

## Decision

- **A second autoload, `Music`** (`scripts/Music.gd`), registered after
  `Sfx`. It is the only thing that plays music.
  - `TRACKS` lists each loop with its `kind` (`lobby` or `fight`) and its
    base level.
  - `play_lobby()` and `play_fight()` crossfade over 1 s between two voices.
    Asking for what is already playing does nothing, so the lobby flow can
    call either one freely. Each `play_fight()` that comes from anything
    other than fight music starts the next fight track in the rotation.
  - `stop()` fades out, and `duck()` dips the music.
- **Following the rounds, by signals.** Like `SfxHooks`, `Music` watches
  `SceneTree.node_added`. A node with `round_started` and `round_won` is a
  RoundManager.
  - A round start calls `play_fight()`, unless `follow_rounds` is off, which
    #120 can switch off if it wants to drive the music itself.
  - A round win calls `duck()`: -14 dB within 0.05 s, held for 0.6 s (the
    round-win sound lasts 0.54 s), then back to 0 dB over 0.5 s.
  - Once the game's own scene is up, the lobby track plays until the first
    round. The scenario runner has no current scene, so it starts in
    silence.
- **Buses.** `Music` makes a `Music` bus that sends to Master, just as `Sfx`
  makes `SFX`. The music volume is the Music bus's volume. The new SFX volume
  is the SFX bus's volume. Master volume and mute stay on Master, on top of
  both.
- **One settings file**, `user://audio.cfg`, as in ADR-0016.
  - `Sfx` writes `audio/master_volume`, `audio/muted`, `audio/sfx_volume` and
    `display/fullscreen`. `Music` writes `music/volume`.
  - Each one loads the file, changes its own keys and saves, so neither one
    wipes the other's keys.
  - Both have a `settings_path`, which the scenarios point at a temp file.
- **Fullscreen** lives in `Sfx` beside the other settings, because the one
  menu drives `Sfx`.
  - `set_fullscreen(on)` asks `DisplayServer.window_set_mode()` for
    `WINDOW_MODE_FULLSCREEN`, or for the project's own window mode
    (maximized) when it is off.
  - Each mode it asks for is logged in `window_mode_requests()`. Headless has
    no window, so the scenario checks what was asked for.
  - A saved fullscreen is only applied when the game's scene is running, so
    a scenario run never resizes a window.
- **The settings menu** is the #75 corner control, grown.
  - `SfxSettings.gd` is now a "Settings" button in the bottom-right corner. It
    opens master, SFX and music sliders, a mute box and a fullscreen box.
  - Keys: `Esc` opens or closes the menu, `M` mutes, and `F11` toggles
    fullscreen.
  - It holds no settings of its own.
- **Loading and headless.** Tracks are read with
  `AudioStreamOggVorbis.load_from_file()` when the raw file is there, and set
  to loop. An exported build falls back to `load()`, and the `.import` files
  set `loop=true` for it. The scenario runner awaits `Music.release()` before
  it quits, as well as `Sfx.release()`, so no playback leaks at exit.
- **Assets.** Three CC0 tracks from OpenGameArt, about 1.6 MB, sit under
  `assets/music/`. Each one's source, author and licence page is listed in
  CREDITS.md. A scenario fails if a track is missing, is not credited as
  CC0, or is shipped but unused.

## Consequences

- #120 calls `Music.play_lobby()` when it shows the lobby or the victory
  screen, and `Music.play_fight()` when a match starts. Both are safe to
  call repeatedly.
- Adding a track means a `TRACKS` entry, a file, and a CREDITS.md row.
- The headless suite cannot judge how the music sounds, or whether a loop
  seam clicks. Two of the files are OpenGameArt's OGG copies of WAV
  uploads, which may pad the loop point. Choosing the tracks and their levels
  (-8 / -9 dB) needs a listen test on the host.
