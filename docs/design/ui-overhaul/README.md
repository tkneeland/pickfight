# UI overhaul mockup (#507)

The owner-approved reference for the title screen and lobby redesign, 2026-10-03. The spec of record is the body and comments of [#507](https://github.com/tkneeland/pickfight/issues/507). These files show what it should look like and how it should behave. Where a file and #507 disagree, #507 wins.

| File | What it is |
|---|---|
| `Main.dc.html` | Title screen: logo, "How are you playing?", Couch / Online / Solo cards, settings gear. |
| `Lobby.dc.html` | Lobby (it switches between Couch, Online and Solo): QR / room code / Solo panel, mode cards, 4x2 player cards with the in-card look picker, Host panel, How to play and Your look popups, START. |
| `canvas.json` | Board layout of the two screens (1600x900 each). |

## Reading the files

They are claude.ai design-canvas boards, not standalone pages. The markup uses the canvas runtime (`<x-dc>`, `<sc-for>`, `<sc-if>`, `{{bindings}}`) and a `DCLogic` component class at the bottom of each file, so opening one directly in a browser won't render the interactive mock. Read them as source:

- **Layout and sizes:** the inline `style` attributes (px at 1600x900).
- **Colours:** Okabe-Ito player colours `#E69F00 #56B4E9 #009E73 #F5E24A #CC79A7 #D55E00 #3D8FD1`, ink `#14181d`, cream `#FBF6EA`, background `#232A4A`, muted `#5A628C` / `#C9CCE0`.
- **Type:** Lilita One for headings and buttons, Nunito 800/900 for body text.
- **Style:** 4-5px ink outlines, hard offset shadows (`6px 6px 0 #14181d`), 14-22px corner radii.
- **Behaviour:** `renderVals()` in each file's script (mode list, per-mode Host target row, ready toggling, picker rows).
- **How to play:** four animated demos rebuilt as SVG + CSS keyframes (`.h1*`..`.h4*`) from `scripts/HowToPlayDemo.gd`. The game keeps using the real HowToPlayDemo. The mock only shows how it is framed in the new panel.

The logo `<img>` points at `art/logo/logo.svg`, the real game logo.
