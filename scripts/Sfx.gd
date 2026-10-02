extends Node

## Sound effects on the shared screen (issue #75, ADR-0016). An autoload, so
## the one entry point -- `play(name, position, strength)` -- is there for
## every scene and every scenario without anything having to be wired to it.
##
## What it owns, and nothing else:
##
## - **The sound table.** `SOUNDS` names every sound the game can make and the
##   pool of variant files it picks from, so repeated hits do not all sound
##   the same. Adding a sound is one entry here plus one `play()` call (or one
##   line in `SfxHooks.gd`).
## - **Strength.** 0..1: how hard the thing that made the sound was. It scales
##   volume (`MIN_GAIN` at 0, full at 1) and pitch (a harder hit sits a little
##   lower, which reads as weight).
## - **Placement.** A sound with a position plays through an
##   `AudioStreamPlayer2D`, so it pans left or right with where it happened
##   on screen. UI sounds (`"positional": false`) play flat.
## - **Mixing.** Everything plays on the `SFX` bus, created here if the
##   project has no bus layout, and no one sound has more than its
##   `overlap` copies playing at once: past the cap the oldest copy is cut
##   and reused, so a flurry stays a flurry and not a wall of noise.
## - **Master volume and mute**, applied to the Master bus, the **SFX volume**,
##   applied to the SFX bus, and the **fullscreen** toggle (#118), all
##   remembered in `user://audio.cfg`. `SfxSettings.gd` is the on-screen
##   settings menu for them and for `Music`'s volume.
##
## Which game events make which sound is not here: `SfxHooks.gd` listens to
## the signals the game already emits and calls `play()`. Nothing in the game
## calls this autoload by name, so a scene or script never breaks for want of
## it, and the phones never hear anything (ADR-0013 keeps them to the buzz).
##
## **Headless.** Godot's dummy audio driver takes the same calls, so the
## scenario suite runs this for real. Sound files are read straight off disk
## when the raw file is present, so a fresh clone that has never been
## imported still plays (and still boots clean); an exported build, which
## carries only the imported copy, loads that instead.

const HooksScript := preload("res://scripts/SfxHooks.gd")
const AnnouncerScript := preload("res://scripts/Announcer.gd")
const SettingsScript := preload("res://scripts/SfxSettings.gd")

const BUS_NAME: StringName = &"SFX"
const SETTINGS_PATH: String = "user://audio.cfg"
const DIR: String = "res://assets/sfx/"

## Every sound the game makes. Per entry:
##   files       -- variant pool, one picked per play (never the same one
##                  twice running when there is a choice)
##   db          -- base volume, before strength
##   overlap     -- most copies playing at once (DEFAULT_OVERLAP if absent)
##   positional  -- false for UI sounds, which play flat (default true)
##   max_sec     -- fade out and stop after this long (for long files)
##   voice       -- true for the announcer's lines (#152): always at natural
##                  pitch, whatever the strength, and never jittered
##
## The `hit_<set>` and `fire_<set>` names are per weapon: a weapon's
## `WeaponStats.sound_set` picks them. See CREDITS.md for every file's source.
const SOUNDS: Dictionary = {
	# --- Strikes, one set per weapon --------------------------------------
	"hit_pickaxe": {"files": [
		"kenney_impact/impactMining_000.ogg",
		"kenney_impact/impactMining_001.ogg",
		"kenney_impact/impactMining_002.ogg"], "db": 0.0},
	"hit_sword": {"files": [
		"kenney_rpg/knifeSlice.ogg",
		"kenney_rpg/knifeSlice2.ogg",
		"kenney_rpg/drawKnife1.ogg"], "db": 0.0},
	"hit_axe": {"files": [
		"kenney_rpg/chop.ogg",
		"kenney_impact/impactWood_heavy_000.ogg",
		"kenney_impact/impactWood_heavy_001.ogg"], "db": 2.0},
	"hit_staff": {"files": [
		"kenney_impact/impactPlank_medium_000.ogg",
		"kenney_impact/impactPlank_medium_001.ogg",
		"kenney_impact/impactPlank_medium_002.ogg"], "db": 0.0},
	"hit_dagger": {"files": [
		"kenney_impact/impactMetal_light_000.ogg",
		"kenney_impact/impactMetal_light_001.ogg",
		"kenney_impact/impactMetal_light_002.ogg"], "db": -2.0},
	"hit_boomstick": {"files": [
		"kenney_impact/impactPunch_heavy_000.ogg",
		"kenney_impact/impactPunch_heavy_001.ogg",
		"kenney_impact/impactPunch_heavy_002.ogg"], "db": 0.0},
	# The three weapons issue #150 added. Their files are shared with stage
	# parts (a wall, a collapsing floor), never with another weapon's hits.
	"hit_grapple": {"files": [
		"kenney_impact/impactGeneric_light_000.ogg",
		"kenney_impact/impactGeneric_light_001.ogg",
		"kenney_impact/impactGeneric_light_002.ogg"], "db": -2.0},
	"hit_flail": {"files": [
		"kenney_impact/impactPlate_heavy_000.ogg",
		"kenney_impact/impactPlate_heavy_001.ogg",
		"kenney_impact/impactWood_heavy_003.ogg"], "db": 2.0},
	"hit_boomerang": {"files": [
		"kenney_impact/impactWood_heavy_002.ogg",
		"kenney_impact/impactWood_heavy_004.ogg"], "db": 0.0},
	# Spear (#272): a dull wooden thunk, a pierce. Pogo (#271): a soft thump.
	# Fishing rod (#273): a light wooden snap. Magnet (#274): a clanky plate tap.
	# All four are own files (#288), never copies under a placeholder name.
	"hit_spear": {"files": [
		"kenney_impact/impactWood_medium_000.ogg",
		"kenney_impact/impactWood_medium_001.ogg"], "db": 1.0},
	"hit_pogo": {"files": [
		"kenney_impact/impactSoft_medium_000.ogg",
		"kenney_impact/impactSoft_medium_001.ogg"], "db": 1.0},
	"hit_fishing_rod": {"files": [
		"kenney_impact/impactWood_light_000.ogg",
		"kenney_impact/impactWood_light_001.ogg"], "db": -2.0},
	# The umbrella (issue #269): a dull fabric thwack (#306).
	"hit_umbrella": {"files": [
		"kenney_impact/impactPunch_medium_000.ogg",
		"kenney_impact/impactPunch_medium_001.ogg"], "db": -2.0},
	# The magnet (issue #274).
	"hit_magnet": {"files": [
		"kenney_impact/impactPlate_light_000.ogg",
		"kenney_impact/impactPlate_light_001.ogg"], "db": -1.0},
	# The plunger (issue #270): a squelchy rubber thwop (#306).
	"hit_plunger": {"files": [
		"kenney_impact/footstep_snow_000.ogg",
		"kenney_impact/footstep_snow_001.ogg"], "db": -1.0},
	# The shield (issue #275): a flat metal clang, own files.
	"hit_shield": {"files": [
		"kenney_impact/impactPlate_shield_000.ogg",
		"kenney_impact/impactPlate_shield_001.ogg"], "db": 0.0},
	# --- Firing -------------------------------------------------------------
	"fire_boomstick": {"files": [
		"kenney_scifi/explosionCrunch_000.ogg",
		"kenney_scifi/explosionCrunch_001.ogg"], "db": -3.0, "overlap": 4},
	# The grapple's hook and the boomerang leaving the hand (issue #150).
	# Each is a node with `impacted` and `setup`, so SfxHooks watches it as it
	# does a bullet and plays `fire_<sound_set>` as it is placed.
	"fire_grapple": {"files": [
		"kenney_interface/pluck_001.ogg"], "db": -4.0, "overlap": 4},
	"fire_boomerang": {"files": [
		"kenney_scifi/forceField_000.ogg",
		"kenney_scifi/forceField_001.ogg"], "db": -8.0, "overlap": 4, "max_sec": 0.4},
	"bullet_impact": {"files": [
		"kenney_impact/impactTin_medium_000.ogg",
		"kenney_impact/impactTin_medium_001.ogg"], "db": -4.0},
	# --- Other combat and movement -----------------------------------------
	"clash": {"files": [
		"kenney_impact/impactMetal_medium_000.ogg",
		"kenney_impact/impactMetal_medium_001.ogg",
		"kenney_impact/impactMetal_medium_002.ogg"], "db": 0.0},
	"head_terrain": {"files": [
		"kenney_impact/footstep_concrete_000.ogg",
		"kenney_impact/footstep_concrete_001.ogg",
		"kenney_impact/footstep_concrete_002.ogg"], "db": -2.0, "overlap": 4},
	"land": {"files": [
		"kenney_impact/impactSoft_heavy_000.ogg",
		"kenney_impact/impactSoft_heavy_001.ogg",
		"kenney_impact/impactSoft_heavy_002.ogg"], "db": -3.0},
	"eliminated": {"files": [
		"kenney_scifi/lowFrequency_explosion_000.ogg"], "db": 0.0, "overlap": 2},
	# --- Lava ---------------------------------------------------------------
	"lava_sizzle": {"files": [
		"kenney_scifi/thrusterFire_000.ogg"], "db": -4.0, "overlap": 2, "max_sec": 1.2},
	"lava_rise": {"files": [
		"kenney_scifi/lowFrequency_explosion_001.ogg"], "db": 0.0, "overlap": 1, "positional": false},
	# --- Stage parts (#76) --------------------------------------------------
	"bounce_launch": {"files": [
		"kenney_scifi/forceField_000.ogg",
		"kenney_scifi/forceField_001.ogg"], "db": -4.0, "max_sec": 0.6},
	"wind_tell": {"files": [
		"kenney_scifi/spaceEngineLow_000.ogg"], "db": -12.0, "overlap": 2, "max_sec": 1.0},
	"wind_gust": {"files": [
		"kenney_scifi/thrusterFire_001.ogg",
		"kenney_scifi/thrusterFire_002.ogg"], "db": -5.0, "overlap": 2, "max_sec": 1.5},
	"rock_warning": {"files": [
		"kenney_scifi/spaceEngineLarge_000.ogg"], "db": -8.0, "overlap": 2, "max_sec": 1.5},
	"rock_impact": {"files": [
		"kenney_scifi/explosionCrunch_002.ogg",
		"kenney_scifi/explosionCrunch_003.ogg",
		"kenney_scifi/explosionCrunch_004.ogg"], "db": -2.0},
	"floor_warning": {"files": [
		"kenney_rpg/creak1.ogg",
		"kenney_rpg/creak2.ogg",
		"kenney_rpg/creak3.ogg"], "db": 0.0},
	"floor_collapse": {"files": [
		"kenney_impact/impactWood_heavy_002.ogg",
		"kenney_impact/impactWood_heavy_003.ogg",
		"kenney_impact/impactWood_heavy_004.ogg"], "db": 2.0},
	"wall_hit": {"files": [
		"kenney_impact/impactGeneric_light_000.ogg",
		"kenney_impact/impactGeneric_light_001.ogg",
		"kenney_impact/impactGeneric_light_002.ogg"], "db": 0.0},
	"wall_break": {"files": [
		"kenney_impact/impactPlate_heavy_000.ogg",
		"kenney_impact/impactPlate_heavy_001.ogg"], "db": 2.0},
	# --- Round and UI -------------------------------------------------------
	"countdown": {"files": [
		"kenney_interface/tick_001.ogg"], "db": 0.0, "overlap": 1, "positional": false},
	"round_start": {"files": [
		"kenney_interface/bong_001.ogg"], "db": 0.0, "overlap": 1, "positional": false},
	"modifier": {"files": [
		"kenney_interface/maximize_006.ogg"], "db": 0.0, "overlap": 1, "positional": false},
	"round_win": {"files": [
		"kenney_interface/confirmation_002.ogg"], "db": -10.0, "overlap": 1, "positional": false},
	"join": {"files": [
		"kenney_interface/pluck_001.ogg"], "db": 0.0, "overlap": 2, "positional": false},
	# --- Announcer (#152); `Announcer.gd` says when ---------------------------
	"announce_3": {"files": ["announcer/count_3.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_2": {"files": ["announcer/count_2.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_1": {"files": ["announcer/count_1.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_fight": {"files": ["announcer/fight.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_ko": {"files": ["announcer/ko.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_double_ko": {"files": ["announcer/double_ko.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_winner": {"files": ["announcer/winner.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_red_team_wins": {"files": ["announcer/red_team_wins.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_blue_team_wins": {"files": ["announcer/blue_team_wins.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_low_gravity": {"files": ["announcer/low_gravity.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_heavy_weapons": {"files": ["announcer/heavy_weapons.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_big_heads": {"files": ["announcer/big_heads.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_fast_lava": {"files": ["announcer/fast_lava.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_slippery_floor": {"files": ["announcer/slippery_floor.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_tiny_weapons": {"files": ["announcer/tiny_weapons.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_weapon_roulette": {"files": ["announcer/weapon_roulette.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_meteor_shower": {"files": ["announcer/meteor_shower.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_bouncy": {"files": ["announcer/bouncy.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_double_damage": {"files": ["announcer/double_damage.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	# Mode callouts (#370), synthesised like the rest (CREDITS.md).
	"announce_king_of_the_hill": {"files": ["announcer/king_of_the_hill.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_hot_potato": {"files": ["announcer/hot_potato.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_sudden_death": {"files": ["announcer/sudden_death.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_stock": {"files": ["announcer/stock.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_last_life": {"files": ["announcer/last_life.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_stolen": {"files": ["announcer/stolen.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_overtime": {"files": ["announcer/overtime.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_soccer": {"files": ["announcer/soccer.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	"announce_goal": {"files": ["announcer/goal.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	# No recorded voice clips for Capture the Flag yet (#403): UI sounds stand in.
	"announce_capture_the_flag": {"files": ["kenney_interface/bong_001.ogg"], "db": -8.0, "overlap": 1, "positional": false, "voice": false},
	"announce_flag_taken": {"files": ["kenney_interface/maximize_006.ogg"], "db": -8.0, "overlap": 1, "positional": false, "voice": false},
	"announce_captured": {"files": ["kenney_interface/confirmation_002.ogg"], "db": -8.0, "overlap": 1, "positional": false, "voice": false},
	"announce_hill_taken": {"files": ["announcer/hill_taken.ogg"], "db": -15.0, "overlap": 1, "positional": false, "voice": true},
	# No recorded voice clip for Gale yet: the wind-up sound stands in (#312).
	"announce_gale": {"files": ["kenney_scifi/spaceEngineLow_000.ogg"], "db": -8.0, "overlap": 1, "positional": false, "voice": false, "max_sec": 1.5},
	# --- Player voice grunts (#290): one voice per slot, placeholder synthesis ---
	# Kept well under the weapon sounds (their `db` is about 0, these -15/-13),
	# and placed on the fighter. `voice` keeps each slot's pitch fixed, so a slot
	# is always recognisably itself. `SfxHooks` says when; CREDITS.md the source.
	"grunt_hit_0": {"files": ["voice/hit_0_0.ogg", "voice/hit_0_1.ogg"], "db": -15.0, "overlap": 2, "voice": true},
	"grunt_hit_1": {"files": ["voice/hit_1_0.ogg", "voice/hit_1_1.ogg"], "db": -15.0, "overlap": 2, "voice": true},
	"grunt_hit_2": {"files": ["voice/hit_2_0.ogg", "voice/hit_2_1.ogg"], "db": -15.0, "overlap": 2, "voice": true},
	"grunt_hit_3": {"files": ["voice/hit_3_0.ogg", "voice/hit_3_1.ogg"], "db": -15.0, "overlap": 2, "voice": true},
	"grunt_hit_4": {"files": ["voice/hit_4_0.ogg", "voice/hit_4_1.ogg"], "db": -15.0, "overlap": 2, "voice": true},
	"grunt_hit_5": {"files": ["voice/hit_5_0.ogg", "voice/hit_5_1.ogg"], "db": -15.0, "overlap": 2, "voice": true},
	"grunt_hit_6": {"files": ["voice/hit_6_0.ogg", "voice/hit_6_1.ogg"], "db": -15.0, "overlap": 2, "voice": true},
	"grunt_hit_7": {"files": ["voice/hit_7_0.ogg", "voice/hit_7_1.ogg"], "db": -15.0, "overlap": 2, "voice": true},
	"grunt_ko_0": {"files": ["voice/ko_0.ogg"], "db": -13.0, "overlap": 1, "voice": true},
	"grunt_ko_1": {"files": ["voice/ko_1.ogg"], "db": -13.0, "overlap": 1, "voice": true},
	"grunt_ko_2": {"files": ["voice/ko_2.ogg"], "db": -13.0, "overlap": 1, "voice": true},
	"grunt_ko_3": {"files": ["voice/ko_3.ogg"], "db": -13.0, "overlap": 1, "voice": true},
	"grunt_ko_4": {"files": ["voice/ko_4.ogg"], "db": -13.0, "overlap": 1, "voice": true},
	"grunt_ko_5": {"files": ["voice/ko_5.ogg"], "db": -13.0, "overlap": 1, "voice": true},
	"grunt_ko_6": {"files": ["voice/ko_6.ogg"], "db": -13.0, "overlap": 1, "voice": true},
	"grunt_ko_7": {"files": ["voice/ko_7.ogg"], "db": -13.0, "overlap": 1, "voice": true},
}

const DEFAULT_OVERLAP: int = 3
## Linear gain at strength 0; strength 1 is full gain. About -9 dB, so the
## softest hit is clearly quieter without vanishing under the rest.
const MIN_GAIN: float = 0.35
## Added to every sound's table `db` (#93, playtest: everything was too
## quiet next to the victory fanfare). The round-win entry is set 10 dB down
## to come out 4 dB quieter than it was, while the rest come out 6 dB louder.
## The master slider and mute still sit on top of this.
const MIX_BOOST_DB: float = 6.0
## Pitch at strength 0 and at strength 1, before jitter.
const PITCH_AT_ZERO: float = 1.08
const PITCH_AT_FULL: float = 0.92
## Random pitch spread per play, as a fraction, so a pool of three does not
## sound like three recordings.
const PITCH_JITTER: float = 0.04
## Positional sounds are for panning, not for fading out with distance: every
## stage fits the screen, and a hit at the far edge must still be heard.
const MAX_DISTANCE: float = 6000.0
const ATTENUATION: float = 0.5
const FADE_SEC: float = 0.15
## How long `release()` waits for the audio server to free stopped playbacks.
const RELEASE_SEC: float = 1.0
## Longest file decoded to PCM (see `_start_decoding`); anything longer stays
## compressed. Every file in the table is well under it.
const MAX_DECODE_SEC: float = 10.0
## What a decoded file is stored as: plain 16-bit PCM, untouched otherwise.
const PCM_OPTIONS: Dictionary = {
	"compress/mode": 0,
	"edit/trim": false,
	"edit/normalize": false,
	"edit/loop_mode": 0,
	"force/8_bit": false,
	"force/mono": false,
	"force/max_rate": false,
}

## The master volume, 0..1, and whether everything is muted. Set through
## `set_master_volume()` / `set_muted()` so they reach the bus.
var master_volume: float = 1.0
var muted: bool = false
## The SFX bus's own volume, 0..1, under the master (#118). Set through
## `set_sfx_volume()`.
var sfx_volume: float = 1.0
## Whether the host window is fullscreen (#118). Set through
## `set_fullscreen()`, which asks `DisplayServer` for the window mode, and
## brought back in line with the real window by `sync_fullscreen()` when the
## window leaves or enters fullscreen some other way (the OS's own button or
## shortcut; issue #167).
var fullscreen: bool = false
## Whether `Juice` shakes the camera on a heavy hit or a kill (#256). On by
## default; set through `set_screen_shake()` and remembered with the rest.
var screen_shake: bool = true
## Comfort option (#317): when on, the white/bright flashes (elimination burst,
## bounce pad, breaking wall) are not drawn. Off by default.
var reduce_flash: bool = false
## Comfort option (#317): how much bigger the name tags over players' heads
## are drawn. One of `UI_SCALES`; 1.0 by default.
const UI_SCALES: Array[float] = [1.0, 1.5, 2.0]
var ui_scale: float = 1.0
## Streamer mode (#369): when on, the shared screen hides the room code, the
## join URL and the join QR ("Code hidden: see host phone"); the host phone's
## menu still shows the code. Off by default.
var hide_room_code: bool = false
## What `sync_fullscreen()` reads the window mode from: a Callable returning a
## `DisplayServer.WINDOW_MODE_*`, or an empty one for the real window. The
## scenarios point it at a fake window, as headless has none.
var window_mode_probe: Callable = Callable()
## How long after asking for a window mode `sync_fullscreen()` leaves the flag
## alone: some platforms (macOS) animate into fullscreen and report the old
## mode until they are done.
var fullscreen_sync_grace_msec: int = 1500
## Where the settings are saved. The scenario suite points it at a temp file
## when it tests saving. A `-s` run (the scenario runner, the probes) starts
## with it on a temp file already, so it never touches the owner's (#195).
var settings_path: String = SETTINGS_PATH
## Whether volume and mute are saved to `settings_path` when changed. Off from
## the start in a `-s` run (#195), so a test run never rewrites the owner's
## settings.
var persist_settings: bool = true

## name -> Array[AudioStream], filled on first play.
var _streams: Dictionary = {}
## name -> Array of the player nodes that sound owns; never more than its cap.
var _voices: Dictionary = {}
## name -> index of the variant played last, to avoid an immediate repeat.
var _last_variant: Dictionary = {}
## Pitch jitter and variant picks. Seeded from the match seed at every match
## start (issue #187, `reseed()`): purely cosmetic, never gameplay, but seeded
## anyway so a replayed seed also replays the sound log (`_requests`) exactly.
var _rng := RandomNumberGenerator.new()
var _recording: bool = false
var _requests: Array[Dictionary] = []
var _warned: Dictionary = {}
var _play_serial: int = 0
var _hooks: Node
## The announcer's voice lines (#152), built beside the hooks.
var announcer: Node
var _settings_ui: CanvasLayer
## Every window mode `set_fullscreen()` has asked `DisplayServer` for, oldest
## first. Headless cannot really go fullscreen, so the scenarios check this.
var _window_mode_requests: Array[int] = []
## When a window mode was last asked for (msec), or -1 for never: the
## fullscreen flag is only synced from the window once the game has put its
## own choice into effect, so a boot never overwrites the saved setting.
var _window_mode_requested_msec: int = -1
## Seconds each sound file runs, res:// path -> float, filled by the decoding
## thread (and by `sound_length()` for a file it has not reached yet), so the
## announcer never reads a file off disk to time a line (issue #167). Guarded
## by `_pcm_mutex`.
var _file_lengths: Dictionary = {}
## How many files `sound_length()` has had to read off disk itself.
var _length_disk_reads: int = 0

## Decoded copies of the sound files, res:// path -> AudioStreamWAV, filled by
## a worker thread; see `_start_decoding`. Guarded by `_pcm_mutex`, as are the
## two flags below it.
var _pcm: Dictionary = {}
var _pcm_mutex := Mutex.new()
var _decode_done: bool = false
var _decode_cancelled: bool = false
var _decode_task: int = -1
## Whether `_streams` has been rebuilt from `_pcm` since decoding finished.
var _streams_decoded: bool = false

## Restart the jitter and variant stream from `seed_value` (issue #187): the
## RoundManager calls this with its match seed's "sfx" stream at match start.
func reseed(seed_value: int) -> void:
	_rng.seed = seed_value
	_last_variant.clear()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ensure_bus()
	if is_script_main_loop(get_tree()):
		# A `-s` run (#195): the owner's saved mute or fullscreen would make
		# the scenarios' assertions hollow, and nothing it does may save
		# over them. Start from the defaults, saving off, on a temp file.
		persist_settings = false
		settings_path = headless_settings_path()
		_apply_master()
		_apply_sfx_volume()
	else:
		load_settings()
	_hooks = HooksScript.new()
	_hooks.name = "Hooks"
	_hooks.sfx = self
	add_child(_hooks)
	announcer = AnnouncerScript.new()
	announcer.name = "Announcer"
	announcer.sfx = self
	add_child(announcer)
	_start_decoding()
	# Leaving fullscreen through the OS resizes the window.
	get_tree().root.size_changed.connect(_on_window_size_changed)
	# The game's own scene is only current once autoloads have all readied.
	# The scenario runner never has one, so it never builds the overlay.
	_build_settings_ui_if_in_game.call_deferred()

## Stop everything and wait until the audio server has let go of it. The
## server frees a stopped playback on its own mix thread, a moment later, so
## a script that quits straight after a sound -- the scenario runner -- gets
## "ObjectDB instances leaked at exit" unless it awaits this first.
func release() -> void:
	_stop_decoding()
	_pcm.clear()
	for key: String in _voices:
		for voice: Node in _voices[key]:
			voice.stop()
			voice.stream = null
	_streams.clear()
	_last_variant.clear()
	# Out of the tree there is no SceneTree to wait on (issue #167).
	if not is_inside_tree():
		return
	# Wall clock, not a SceneTreeTimer (#182): the mix thread lets go in real
	# time, and under `--fixed-fps` a timer counts frames, which can run far
	# faster than that.
	var until: int = Time.get_ticks_msec() + int(RELEASE_SEC * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame

# --- Playing ----------------------------------------------------------------

## A known sound was asked for (issue #251): the host streams these to remote
## clients, which play them locally. `position` is a Vector2 or null.
signal played(sound: StringName, position: Variant, strength: float)

## Play `sound` (a key of `SOUNDS`). `position` is a world position for a sound
## to pan by, or null to play it flat; `strength` 0..1 is how hard the thing
## that made it was. Unknown names warn once and do nothing.
func play(sound: StringName, position: Variant = null, strength: float = 1.0) -> void:
	var key: String = String(sound)
	if not SOUNDS.has(key):
		if not _warned.has(key):
			_warned[key] = true
			push_warning("Sfx: no sound named '%s'" % key)
		return
	played.emit(sound, position, strength)
	var spec: Dictionary = SOUNDS[key]
	var s: float = clampf(strength, 0.0, 1.0) if is_finite(strength) else 1.0
	var volume_db: float = volume_db_for(key, s)
	var pitch: float = lerpf(PITCH_AT_ZERO, PITCH_AT_FULL, s) * (1.0 + _rng.randf_range(-PITCH_JITTER, PITCH_JITTER))
	if bool(spec.get("voice", false)):
		pitch = 1.0
	var positional: bool = bool(spec.get("positional", true)) and position is Vector2
	if _recording:
		_requests.append({
			"name": key,
			"position": position,
			"strength": s,
			"volume_db": volume_db,
			"pitch": pitch,
		})
	# Not yet in the tree (a `-s` script's first frame): nothing can play.
	if not is_inside_tree():
		return
	var stream: AudioStream = _pick_stream(key)
	if stream == null:
		return
	var voice: Node = _claim_voice(key, positional)
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	if voice is AudioStreamPlayer2D:
		(voice as AudioStreamPlayer2D).global_position = position if position is Vector2 else _screen_centre()
	_play_serial += 1
	voice.set_meta(&"sfx_play", _play_serial)
	voice.play()
	if spec.has("max_sec"):
		_fade_out_later(voice, float(spec["max_sec"]))

## The volume a play of `sound` at `strength` gets. Public so the scenarios
## can check the curve without having to catch a play in the act.
func volume_db_for(sound: StringName, strength: float) -> float:
	var spec: Dictionary = SOUNDS.get(String(sound), {})
	var gain: float = lerpf(MIN_GAIN, 1.0, clampf(strength, 0.0, 1.0))
	return float(spec.get("db", 0.0)) + MIX_BOOST_DB + linear_to_db(gain)

func has_sound(sound: StringName) -> bool:
	return SOUNDS.has(String(sound))

## Seconds the longest file of `sound` runs, or 0 when it has none: the
## announcer waits this long before its next line (#152).
func sound_length(sound: StringName) -> float:
	var key: String = String(sound)
	if not SOUNDS.has(key):
		return 0.0
	var longest: float = 0.0
	for file: String in SOUNDS[key]["files"]:
		longest = maxf(longest, _file_length(DIR + file))
	return longest

## How many sound files `sound_length()` has read off disk because decoding
## had not timed them yet.
func length_disk_reads() -> int:
	return _length_disk_reads

## Whether the decoding thread has been through every file.
func decoding_done() -> bool:
	_pcm_mutex.lock()
	var done: bool = _decode_done
	_pcm_mutex.unlock()
	return done

func _file_length(path: String) -> float:
	_pcm_mutex.lock()
	var known: Variant = _file_lengths.get(path)
	_pcm_mutex.unlock()
	if known != null:
		return float(known)
	_length_disk_reads += 1
	var stream: AudioStream = _read_stream(path)
	var length: float = stream.get_length() if stream != null else 0.0
	_pcm_mutex.lock()
	_file_lengths[path] = length
	_pcm_mutex.unlock()
	return length

## Every file `SOUNDS` refers to, as res:// paths.
func all_sound_files() -> PackedStringArray:
	var paths := PackedStringArray()
	for key: String in SOUNDS:
		for file: String in SOUNDS[key]["files"]:
			paths.append(DIR + file)
	return paths

## The most copies of `sound` that may play at once.
func overlap_cap(sound: StringName) -> int:
	return int(SOUNDS.get(String(sound), {}).get("overlap", DEFAULT_OVERLAP))

## How many copies of `sound` are playing right now.
func active_voices(sound: StringName) -> int:
	var count: int = 0
	for voice: Node in _voices.get(String(sound), []):
		if voice.playing:
			count += 1
	return count

## How many player nodes `sound` owns, playing or not. Never above its cap.
func voice_count(sound: StringName) -> int:
	return _voices.get(String(sound), []).size()

## Stop everything playing. The scenarios use it to start from silence.
func stop_all() -> void:
	for key: String in _voices:
		for voice: Node in _voices[key]:
			voice.stop()

# --- Test hook --------------------------------------------------------------
#
# The scenario suite spies on what was asked for rather than on what came out
# of the speakers, which headless cannot hear.

func start_recording() -> void:
	_requests.clear()
	_recording = true

func stop_recording() -> void:
	_recording = false

## Every `play()` since `start_recording()`: `{name, position, strength,
## volume_db, pitch}`, oldest first.
func recorded() -> Array[Dictionary]:
	return _requests.duplicate()

## The names alone, in order.
func recorded_names() -> PackedStringArray:
	var names := PackedStringArray()
	for r: Dictionary in _requests:
		names.append(r["name"])
	return names

# --- Volume and mute --------------------------------------------------------

## `save` false applies the volume without writing the settings file: the
## settings menu's sliders apply every step of a drag live and save once, when
## the drag ends (issue #167).
func set_master_volume(value: float, save: bool = true) -> void:
	master_volume = clampf(value, 0.0, 1.0) if is_finite(value) else 1.0
	_apply_master()
	if save:
		_save_settings()

func set_muted(value: bool) -> void:
	muted = value
	_apply_master()
	_save_settings()

func toggle_muted() -> void:
	set_muted(not muted)

func set_sfx_volume(value: float, save: bool = true) -> void:
	sfx_volume = clampf(value, 0.0, 1.0) if is_finite(value) else 1.0
	_apply_sfx_volume()
	if save:
		_save_settings()

## Turn the camera shake (#256) on or off, and remember the choice.
func set_screen_shake(value: bool) -> void:
	screen_shake = value
	_save_settings()

## Turn the bright flashes (#317) off or on, and remember the choice.
func set_reduce_flash(value: bool) -> void:
	reduce_flash = value
	_save_settings()

## Hide the room code and join QR on the shared screen (#369), and remember it.
func set_hide_room_code(value: bool) -> void:
	hide_room_code = value
	_save_settings()

## Pick the name tag size (#317): snaps to the nearest of `UI_SCALES`.
func set_ui_scale(value: float) -> void:
	ui_scale = _nearest_ui_scale(value)
	_save_settings()

static func _nearest_ui_scale(value: float) -> float:
	var best: float = 1.0
	if not is_finite(value):
		return best
	for option: float in UI_SCALES:
		if absf(option - value) < absf(best - value):
			best = option
	return best

## Write the current settings to `settings_path` (when `persist_settings`).
func save_settings() -> void:
	_save_settings()

## Ask the window to go fullscreen, or back to the project's own window mode
## (maximized), and remember the choice.
func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_window_mode()
	_save_settings()

## Flip fullscreen from what the window really is, so after leaving
## fullscreen through the OS the next F11 goes back in (issue #167).
func toggle_fullscreen() -> void:
	sync_fullscreen()
	set_fullscreen(not fullscreen)

## Bring `fullscreen` in line with the real window mode, and save it if it
## changed. Does nothing until the game has asked for a mode, shortly after
## asking (see `fullscreen_sync_grace_msec`), or with no window to read.
func sync_fullscreen() -> void:
	if _window_mode_requested_msec < 0:
		return
	if Time.get_ticks_msec() - _window_mode_requested_msec < fullscreen_sync_grace_msec:
		return
	var mode: int = -1
	if window_mode_probe.is_valid():
		mode = int(window_mode_probe.call())
	elif DisplayServer.get_name() != "headless":
		mode = int(DisplayServer.window_get_mode())
	if mode < 0:
		return
	var real: bool = mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if real == fullscreen:
		return
	fullscreen = real
	_save_settings()
	if _settings_ui != null:
		_settings_ui.refresh()

func _on_window_size_changed() -> void:
	sync_fullscreen()

## The window modes asked for so far (`DisplayServer.WINDOW_MODE_*`).
func window_mode_requests() -> Array[int]:
	return _window_mode_requests.duplicate()

func _apply_master() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(0, muted)

func _apply_sfx_volume() -> void:
	var index: int = AudioServer.get_bus_index(BUS_NAME)
	if index != -1:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(sfx_volume, 0.0001)))

func _apply_window_mode() -> void:
	var mode: int = DisplayServer.WINDOW_MODE_FULLSCREEN
	if not fullscreen:
		mode = int(ProjectSettings.get_setting("display/window/size/mode", DisplayServer.WINDOW_MODE_WINDOWED))
		if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			mode = DisplayServer.WINDOW_MODE_WINDOWED
	_window_mode_requests.append(mode)
	_window_mode_requested_msec = Time.get_ticks_msec()
	DisplayServer.window_set_mode(mode as DisplayServer.WindowMode)

## Whether `tree` is a `-s` script's main loop (the scenario runner, a probe)
## rather than the game's own plain SceneTree. Music asks too.
static func is_script_main_loop(tree: SceneTree) -> bool:
	return tree != null and tree.get_script() != null

## The settings file a `-s` run uses instead of the owner's: in the OS temp
## folder, per process, so parallel shards never share one.
static func headless_settings_path() -> String:
	return OS.get_temp_dir().path_join("pickfight_headless_audio_%d.cfg" % OS.get_process_id())

## Read volume, mute and fullscreen from `settings_path`. Fullscreen is only
## put into effect with the game's scene (`_build_settings_ui_if_in_game`),
## so a scenario run never resizes a window. A missing file means the
## defaults; any other load error is reported and also leaves the defaults.
func load_settings() -> void:
	var config := ConfigFile.new()
	var err: Error = config.load(settings_path)
	if err == OK:
		master_volume = clampf(float(config.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
		muted = bool(config.get_value("audio", "muted", false))
		sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", 1.0)), 0.0, 1.0)
		fullscreen = bool(config.get_value("display", "fullscreen", false))
		screen_shake = bool(config.get_value("display", "screen_shake", true))
		reduce_flash = bool(config.get_value("display", "reduce_flash", false))
		ui_scale = _nearest_ui_scale(float(config.get_value("display", "ui_scale", 1.0)))
		hide_room_code = bool(config.get_value("display", "hide_room_code", false))
	elif err != ERR_FILE_NOT_FOUND:
		push_warning("Sfx: could not read settings from %s (%s); using the defaults" % [settings_path, error_string(err)])
	_apply_master()
	_apply_sfx_volume()

## Load, change and save, so `Music`'s section of the same file is kept. Only a
## missing file starts from an empty config: a file that exists but will not
## load is left alone rather than overwritten with only this section (#195).
func _save_settings() -> void:
	if not persist_settings:
		return
	var config := ConfigFile.new()
	var err: Error = config.load(settings_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("Sfx: not saving settings: %s would not load (%s)" % [settings_path, error_string(err)])
		return
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "muted", muted)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "screen_shake", screen_shake)
	config.set_value("display", "reduce_flash", reduce_flash)
	config.set_value("display", "ui_scale", ui_scale)
	config.set_value("display", "hide_room_code", hide_room_code)
	err = config.save(settings_path)
	if err != OK:
		push_warning("Sfx: could not save settings to %s (%s)" % [settings_path, error_string(err)])

## The on-screen volume control, built once the game's own scene is up. Also
## public so a scenario can build one and drive it.
func build_settings_ui() -> CanvasLayer:
	if _settings_ui == null:
		_settings_ui = SettingsScript.new()
		_settings_ui.name = "SfxSettings"
		_settings_ui.sfx = self
		_settings_ui.music = get_node_or_null(^"/root/Music")
		add_child(_settings_ui)
	return _settings_ui

func _build_settings_ui_if_in_game() -> void:
	if get_tree().current_scene != null:
		if fullscreen:
			_apply_window_mode()
		else:
			# The project's own window mode is the choice in effect.
			_window_mode_requested_msec = Time.get_ticks_msec()
		build_settings_ui()

# --- Internals --------------------------------------------------------------

## Every sound decoded to PCM once, on a worker thread (issue #108).
##
## Playing an Ogg Vorbis file costs its setup headers parsed again on every
## play -- measured at 0.7-0.8 ms of main thread per `play()`, the same on the
## hundredth play as the first. The head knocks and landings fire several
## times a second each, so in a four-player round that was the largest single
## per-frame cost in the game, and a burst of them in one frame was a dropped
## frame. A PCM stream starts in 0.01-0.03 ms. All of the table decodes in
## about a third of a second (around 10 MB), so it is done up front, off the
## main thread; until a file is ready it plays compressed, as it always did.
func _start_decoding() -> void:
	var paths := PackedStringArray()
	for path: String in all_sound_files():
		if not paths.has(path):
			paths.append(path)
	var rate: int = int(AudioServer.get_mix_rate())
	_decode_task = WorkerThreadPool.add_task(_decode_files.bind(paths, rate), false, "Sfx decode")

func _stop_decoding() -> void:
	if _decode_task == -1:
		return
	_pcm_mutex.lock()
	_decode_cancelled = true
	_pcm_mutex.unlock()
	WorkerThreadPool.wait_for_task_completion(_decode_task)
	_decode_task = -1

func _exit_tree() -> void:
	_stop_decoding()

## Worker thread. Touches nothing of this node's but `_pcm` and the flags,
## and those only under the mutex.
func _decode_files(paths: PackedStringArray, rate: int) -> void:
	for path: String in paths:
		_pcm_mutex.lock()
		var cancelled: bool = _decode_cancelled
		_pcm_mutex.unlock()
		if cancelled:
			break
		var source: AudioStream = _read_stream(path)
		var pcm: AudioStreamWAV = _decode_to_pcm(source, rate) if source != null else null
		_pcm_mutex.lock()
		_file_lengths[path] = source.get_length() if source != null else 0.0
		if pcm != null:
			_pcm[path] = pcm
		_pcm_mutex.unlock()
	_pcm_mutex.lock()
	_decode_done = true
	_pcm_mutex.unlock()

## `source` rendered out at the mix rate, as 16-bit PCM; or null for anything
## that is not worth it or did not decode.
static func _decode_to_pcm(source: AudioStream, rate: int) -> AudioStreamWAV:
	if source is AudioStreamWAV or rate <= 0:
		return null
	var length: float = source.get_length()
	if length <= 0.0 or length > MAX_DECODE_SEC:
		return null
	var playback: AudioStreamPlayback = source.instantiate_playback()
	if playback == null:
		return null
	var wanted: int = ceili(length * rate)
	playback.start(0.0)
	var frames: PackedVector2Array = playback.mix_audio(1.0, wanted)
	playback.stop()
	if frames.is_empty():
		return null
	if frames.size() > wanted:
		frames.resize(wanted)
	# Handed over as a float WAV file in memory, so the conversion to 16-bit
	# is the engine's rather than a GDScript loop over every sample.
	var pcm: PackedByteArray = frames.to_byte_array()
	var wav := PackedByteArray()
	wav.resize(44)
	wav.encode_u32(0, 0x46464952)  # "RIFF"
	wav.encode_u32(4, 36 + pcm.size())
	wav.encode_u32(8, 0x45564157)  # "WAVE"
	wav.encode_u32(12, 0x20746d66)  # "fmt "
	wav.encode_u32(16, 16)
	wav.encode_u16(20, 3)  # IEEE float
	wav.encode_u16(22, 2)  # stereo: mix_audio renders a frame as a Vector2
	wav.encode_u32(24, rate)
	wav.encode_u32(28, rate * 8)
	wav.encode_u16(32, 8)
	wav.encode_u16(34, 32)
	wav.encode_u32(36, 0x61746164)  # "data"
	wav.encode_u32(40, pcm.size())
	wav.append_array(pcm)
	return AudioStreamWAV.load_from_buffer(wav, PCM_OPTIONS)

func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) != -1:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS_NAME)
	AudioServer.set_bus_send(index, &"Master")

func _pick_stream(key: String) -> AudioStream:
	if not _streams_decoded:
		_pcm_mutex.lock()
		var done: bool = _decode_done
		_pcm_mutex.unlock()
		if done:
			# Anything loaded while decoding ran is the compressed copy; load
			# again, from `_pcm`, now that it is complete.
			_streams_decoded = true
			_streams.clear()
	if not _streams.has(key):
		var loaded: Array[AudioStream] = []
		for file: String in SOUNDS[key]["files"]:
			var stream: AudioStream = _load_stream(DIR + file)
			if stream != null:
				loaded.append(stream)
		_streams[key] = loaded
	var pool: Array = _streams[key]
	if pool.is_empty():
		return null
	var index: int = _rng.randi() % pool.size()
	if pool.size() > 1 and index == int(_last_variant.get(key, -1)):
		index = (index + 1) % pool.size()
	_last_variant[key] = index
	return pool[index]

## Straight off disk when the raw file is there (any checkout, imported or
## not), else the imported copy (an exported build ships only that).
func _load_stream(path: String) -> AudioStream:
	_pcm_mutex.lock()
	var pcm: AudioStream = _pcm.get(path)
	_pcm_mutex.unlock()
	if pcm != null:
		return pcm
	var stream: AudioStream = _read_stream(path)
	if stream == null and not _warned.has(path):
		_warned[path] = true
		push_warning("Sfx: missing sound file %s" % path)
	return stream

## The file as it is stored, without warning when it is missing: the decoding
## thread reads through this too.
static func _read_stream(path: String) -> AudioStream:
	if FileAccess.file_exists(path):
		var absolute: String = ProjectSettings.globalize_path(path)
		match path.get_extension().to_lower():
			"ogg":
				return AudioStreamOggVorbis.load_from_file(absolute)
			"wav":
				return AudioStreamWAV.load_from_file(absolute)
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	return null

## A free player node for `key`, making one while under the cap, or else the
## copy that has been playing longest, cut short and reused.
func _claim_voice(key: String, positional: bool) -> Node:
	var pool: Array = _voices.get(key, [])
	_voices[key] = pool
	for voice: Node in pool:
		if not voice.playing and (voice is AudioStreamPlayer2D) == positional:
			return voice
	if pool.size() < overlap_cap(key):
		var fresh: Node = _new_voice(positional)
		pool.append(fresh)
		return fresh
	var oldest: Node = pool[0]
	for voice: Node in pool:
		if voice.get_playback_position() > oldest.get_playback_position():
			oldest = voice
	oldest.stop()
	if (oldest is AudioStreamPlayer2D) != positional:
		# Same sound asked for flat and placed: swap the node's kind in place,
		# keeping the pool at its size.
		var index: int = pool.find(oldest)
		oldest.queue_free()
		pool[index] = _new_voice(positional)
		return pool[index]
	return oldest

func _new_voice(positional: bool) -> Node:
	var voice: Node
	if positional:
		var placed := AudioStreamPlayer2D.new()
		placed.max_distance = MAX_DISTANCE
		placed.attenuation = ATTENUATION
		voice = placed
	else:
		voice = AudioStreamPlayer.new()
	voice.bus = BUS_NAME
	add_child(voice)
	return voice

func _fade_out_later(voice: Node, after_sec: float) -> void:
	# Keyed to this play, so a node reused for a newer play is left alone.
	var serial: int = int(voice.get_meta(&"sfx_play", 0))
	var from_db: float = voice.volume_db
	var still_this_play := func() -> bool:
		return is_instance_valid(voice) and int(voice.get_meta(&"sfx_play", 0)) == serial
	var fade := func(t: float) -> void:
		if still_this_play.call():
			voice.volume_db = lerpf(from_db, -60.0, t)
	var finish := func() -> void:
		if still_this_play.call():
			voice.stop()
	var tween: Tween = create_tween()
	tween.tween_interval(after_sec)
	tween.tween_method(fade, 0.0, 1.0, FADE_SEC)
	tween.tween_callback(finish)

func _screen_centre() -> Vector2:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera != null:
		return camera.get_screen_center_position()
	return get_viewport().get_visible_rect().size * 0.5
