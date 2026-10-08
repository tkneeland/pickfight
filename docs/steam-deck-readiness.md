# Steam Deck Verified readiness (#368)

Our model: the Deck (or any PC) is the **host**. It simulates and renders the shared screen, usually on a TV; phones join over the LAN with the QR code. Players on the Deck itself use gamepad seats (right stick drives the arm, #261). So the question is whether the host screen is playable end to end with only the Deck's controls.

## Valve's criteria

Source: Valve, "Steam Deck Compatibility: Verified criteria", https://partner.steamgames.com/doc/steamdeck/compat, read 2026-10-02. The page carries no revision date. A web search summary and a page fetch were used; both agree on the points below. **Re-read the page before submitting**, because the fetch tool paraphrases.

| Area | Criterion (as read) |
|---|---|
| Input | The game supports Deck's physical controls. The default controller configuration lets the player reach all content without changing in-game settings. On-screen glyphs match the inputs in use (Deck or Xbox button names), and keyboard or mouse glyphs are not shown while a controller is the active input. Text entry uses a Steamworks API to open the on-screen keyboard, or a built-in entry usable with only a controller. |
| Display | Runs at a Deck resolution, 1280x800 preferred (1280x720 accepted). Good default settings. The smallest on-screen font character is never below 9 px high at 1280x800 and is readable at about 30 cm. |
| Seamlessness | No message that Deck hardware or software is unsupported. A launcher, if any, meets the same rules including controller navigation. |
| System support | Under Proton, the game and its middleware (and anti-cheat) work. We ship a native Linux export, so Proton matters only if Valve tests the Windows build. |
| Performance | The default configuration reaches 30 fps at 800p without the player changing settings. |

Not found on the page in the read: any rule that a EULA must be controller-navigable beyond the launcher rule above. We have no launcher, no EULA screen and no login.

## Audit

Status column: **fixed** = fixed in this PR with a scenario; **needs-human** = needs real Deck hardware, Steamworks configuration or an owner decision; **n/a** = does not apply to our build.

| # | Area | Finding | Status |
|---|---|---|---|
| D1 | Input | The lobby's host controls (Go online, Play on this PC, Mode, First to, Start, Join online) were buttons and keys (O, P, T, minus, equals, Enter, J) only. Since #435 Go online is the Match kind control (O) and Play on this PC is gone: the Online host-PC seat is automatic, and the title screen's Couch / Online / Solo buttons take the D-pad and A. A gamepad could join and ready, but never change the mode or target. | **fixed**: Y opens the host menu; D-pad moves between the buttons, A presses, B or Y closes. Scenario `deck_gamepad_reaches_every_lobby_control` |
| D2 | Input | The Settings panel (volume, mute, fullscreen, window size, comfort, stats toggle; the stage and weapon lists and the rules moved to the Stages & Rules screen, #647, row D21) opened only by mouse click or Esc, and every control had focus switched off. Unreachable by gamepad. | **fixed**: View opens it with focus on the first slider; a top-to-bottom focus chain covers the scrolling lists; D-pad left and right turn sliders; A presses; B closes (or closes the feedback box first). Scenario `deck_gamepad_operates_the_settings_panel` |
| D3 | Input | The first-launch stats notice (Turn off / OK) could only be clicked. | **fixed**: View focuses its OK button while it is up. Scenario `deck_gamepad_can_dismiss_the_first_launch_notice` |
| D4 | Input | A and B join, ready and un-ready a gamepad seat. With a menu open, pressing A on a checkbox would also ready the player. | **fixed**: `PadMenu` makes the seat code ignore A and B while a gamepad menu is open (covered in the D1 and D2 scenarios, which assert no seat was claimed) |
| D5 | Input | Godot 4.6's built-in `ui_accept` has no gamepad button in this project (measured: Enter, Kp Enter, Space), so a focused button ignored A. | **fixed**: `PadMenu.ensure_accept_binding()` adds A when a gamepad menu opens |
| D6 | Glyphs | The Start button read "Start match (Enter)": a keyboard glyph with a gamepad in use. No caption told a gamepad player how to reach the menus. | **fixed**: captions follow the active input (gamepad connected, or last event from a gamepad); the gamepad hint line reads "Press A to join, Y for menu"; View for Settings is not named in the lobby (no room, the right column is full) and is documented here and in FEATURES.md. Y, A and B are Xbox names; View is the Deck's name for the same button. Scenario `deck_captions_drop_keyboard_glyphs_for_a_gamepad` |
| D7 | Display | Lobby mode cards were 12 px, which is 9.6 px at 1280x800 (the 1600x900 canvas scales by 0.8): em size, so letters are well under 9 px high. | **fixed**: raised to 16. Scenario `deck_text_is_legible_at_1280x800` walks 127 text controls in the lobby and Settings and requires at least 12.7 px em (16 design px). The only text found below the line before the fix was the mode cards |
| D8 | Display | 12.7 px comes from assuming Godot's default font has a cap height of about 0.71 em, so 9 px of height needs about 12.7 px of em. That ratio is an estimate, not a measurement. | **needs-human**: check the smallest glyph on a real Deck screen |
| D9 | Display | Resolution: the project is 1600x900 with `canvas_items` stretch, so a 1280x800 window letterboxes at 0.8 scale. Layout is verified at 1600x900 canvas coordinates only. | Layout fits (`deck_lobby_join_qr_and_url_fit_the_deck_screen`); looking right on the panel is **needs-human** |
| D10 | Display | World-space text (floating damage numbers start at 16, remote puppet labels at 16) scales with the camera, not the canvas. | Damage-number floor checked in D7's scenario; the camera zoom on 8-player stages is **needs-human** |
| D11 | Join info | The join QR, URL and online room code sit together in the lobby and fit the screen at 1280x800 scale (the QR is 272 px wide there). | **fixed**: the QR shrank from 372 to 340 design px to make room for the 16 px mode cards (D7); asserted by `deck_lobby_join_qr_and_url_fit_the_deck_screen` |
| D12 | Join info | During a match nothing join-related is on screen: no QR, room code or join line. A phone that arrives mid-match needs the QR from the lobby, countdown or victory screen. | **fixed** (#430, owner decision: the QR and room code show in the lobby only): the in-round join corner starts hidden and `RoundManager._begin_match` keeps it hidden. Scenario `round_never_shows_join_corner` |
| D13 | Text entry | The feedback box needs a keyboard. A gamepad can open it but not type. The PC client's room-code entry (RemoteClient) is also keyboard text. | **needs-human**: needs the Steamworks floating gamepad text input, i.e. GodotSteam (steam-readiness 6.1). Neither is on the main play path, so either could stay mouse and keyboard with the Deck simply showing no text-entry prompts until then; Valve's rule asks for an on-screen keyboard wherever text is required |
| D14 | Input | Pause was on the host phone only; a gamepad's Start button joined and readied. A Deck player holding only the Deck could not pause. | **fixed** (#430, owner decision: Start pauses only if the host uses it): the host's controller is joypad 0, which is the Deck's built-in controls (D16) and a PC host's first pad, seated or not. In a match (or paused), its Start sends the host phone's Pause or Resume through the same `host_command` path; any other pad's Start does nothing mid-round. In the lobby, countdown and victory screen every pad's Start keeps its join and ready meaning. A pad seat never becomes the host phone's host (`host_slot`). Scenario `host_pad_start_pauses_and_resumes_other_pads_do_not` |
| D15 | Input | The default controller configuration: Steam Input must present the Deck as a gamepad with the right stick as stick (not mouse). The game reads raw joypad events and axes. | **needs-human**: set and test the default layout in the Steamworks Steam Input config on a Deck |
| D16 | Input | Deck's built-in controls when nothing else is connected: the Deck appears as joypad 0. `LobbyScreen` treats a connected joypad as the active input at boot. | **needs-human**: confirm on hardware |
| D17 | Performance | 30 fps at 800p by default. The game uses the Compatibility renderer and 2D physics; a perf probe exists (`tools/perf_probe.gd`) but was not run on Deck-class hardware. | **needs-human** |
| D18 | Seamlessness | No launcher, EULA, login or "unsupported" message. | **n/a** |
| D19 | System | Native Linux x86_64 export exists (steam-readiness section 5); not run on a Deck or under Proton. | **needs-human** |
| D21 | Input | The Stages & Rules screen (#647) is a popup with a tile grid and LB / RB tabs; a gamepad needs a way in, between tabs, to toggle a stage and out again, and focus must survive a tab change (the grid is rebuilt). | **fixed**: Y menu entry "Stages & Rules", A opens it with focus on the first tile; LB / RB step the tabs and refocus the new tab's first tile; D-pad moves, A toggles; B closes and returns to the menu. Scenario `stages_rules_gamepad_opens_navigates_and_closes_647` |
| D20 | Network | Deck as host on a TV with phones on the same Wi-Fi: the existing LAN server (ADR-0002) works wherever the Deck has a LAN address, in desktop mode or game mode. The host prints the join URL and QR in the lobby; the Deck's Wi-Fi must allow device-to-device traffic (guest networks often do not). | **needs-human**: test on a real Deck and a real router |

## What changed in the code

- `scripts/PadMenu.gd` (new): the shared "a gamepad menu is open" flag, the A binding fix and the button helper.
- `scripts/LobbyScreen.gd`: Y menu, explicit D-pad links, active-input tracking, glyph and hint captions, 16 px mode cards.
- `scripts/SfxSettings.gd`: View and B handling, focus switching and the top-to-bottom chain.
- `scripts/ControllerServer.gd`: `_pad_button_pressed` returns early while a gamepad menu is open; since #430, Start from `HOST_PAD_DEVICE` (joypad 0) pauses and resumes a match, and Start from other pads does nothing mid-round.
- `translations/strings.csv` (and the regenerated `strings.en.translation`): `HOST_GAMEPAD_HINT` (reworded), `HOST_START_MATCH_PAD`.
- `tools/scenario_runner.gd`: six `deck_*` scenarios, appended.

## Left for a person with a Deck

Everything marked needs-human above. In order of effort: D15 and D16 (Steam Input default config), D17 and D19 (run a Linux build and measure), D20 (LAN test), then D8, D9 and D10 (look at the screen), then D13 with the GodotSteam work.
