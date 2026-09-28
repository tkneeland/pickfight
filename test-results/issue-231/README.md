# Issue #231 evidence

Branch `fix/issue-231-phone-gear`, rebased onto main `0580531`. The browser probe (before/after screenshots and JSON) was run on main `f4e5982`; the rebase touched no controller-page code, so it still stands.

## Root cause

- **Gear does nothing mid-round.** Nothing blocked it. At the gear's centre, `document.elementFromPoint` returns `#gear` in every phase. By design (#149), the gear's `pointerdown` handler opened the menu on a tap only outside play. During an unpaused round it started a 700 ms hold timer (`GEAR_HOLD_MS`) and the timer was cancelled on `pointerup`, so a normal tap did nothing. Holding it for 900 ms did open it (`holdOpens: true` in `before.json`).
- **Overlap.** `#hud` is `align-items: baseline`, so `#status` sat on the baseline of the 15vmin "P1" badge, at y ≈ 49-75 px. The gear sits at y 44-88 px, so the two overlapped at 375, 390 and 430 px.

## Browser method

`probe.js` (Node, Playwright 1.x) serves `controller/index.html` with a stub WebSocket host. The stub gives the phone slot 0 and makes it the host, then sends the lobby and then the `playing` state. The probe runs in:
- installed Chrome (`channel: "chrome"`, `isMobile`, `hasTouch`)
- Playwright WebKit with an iPhone Safari UA and `hasTouch`

It runs at 375×812, 390×812 and 430×932 portrait, DPR 3. In play it:
1. measures the gear and status boxes and hit-tests the gear's centre;
2. taps the gear with `page.tap` (CDP `Input.dispatchTouchEvent` in Chrome);
3. checks that the menu opens and that no non-zero input frame or text frame was sent;
4. taps Pause, then Resume, and checks that the menu closes;
5. in Chrome only, also:
   - drags the pad afterwards, to check that it still swings;
   - lands a second finger on the gear mid-drag, to check that it is ignored;
   - lands a finger on the gear and slides it onto the pad, to check that it neither opens the menu nor swings.

| | before (main) | after |
|---|---|---|
| tap on gear mid-round opens menu | no (Chrome + WebKit, all widths) | yes (Chrome + WebKit, all widths) |
| swing frames sent by the tap | 0 | 0 |
| Pause → Resume closes the menu | n/a | yes |
| gear / status overlap | yes: status 294-359 × 49-67, gear 319-363 × 44-88 at 375 px | no: status y 12-30, gear y 44-88 |

The raw results are in `before.json` and `after.json`. The screenshots are `<before|after>-<chromium|webkit>-<375|430>-<playing|after-gear-tap>.png`.

## Scenarios

On main `0580531`, the run ends with **270 passed, 0 failed, 270 total** (`full-suite.txt`, `shard.sh 231 5`, `--fixed-fps 60`). The fresh-clone boot shows no ERROR lines.

On main's page, the new scenarios and the updated `controller_page_host_menu_is_guarded` fail (`new-scenarios-on-main.txt`). They pass with the fix. That check was run by checking out `origin/main`'s `controller/index.html` into the worktree and then restoring it. No `git stash` was used.
