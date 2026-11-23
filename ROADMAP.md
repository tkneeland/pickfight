# PickFight roadmap

Where PickFight is going, in order, and who moves each step. Shipped features
are in [`docs/FEATURES.md`](docs/FEATURES.md). Launch research and every owner
decision are in [`docs/launch/`](docs/launch/README.md). The Steam checklist is
[`docs/steam-readiness.md`](docs/steam-readiness.md). Each milestone below is
an `epic` issue whose sub-issues track its progress (the hub's studio view
reads them). Money details for the studio stay on #1313 and #685, not here.

Last updated 2026-11-22 (#1313).

## Where we are

- **The game is playtest-ready.** Up to eight players, Local (phones or
  gamepads, QR join) or Online (PCs, room codes over our relay), 47 stages and
  15 weapons, bots for solo practice, 9 languages (English plus 8), achievements. Art is still
  placeholder.
- **In flight now:** bot polish from the Summit Stock research: route
  planning (#1299), bots propped on their own weapon (#1311), the sword's reach
  (#1309), and an owner call on which pickups bots take (#1310).
- **Dates the plan works back from:** Steam "Coming Soon" page mid-December
  2026 (#540 aimed for early December), Steam Playtest in the Couch Co-Op Fest (Feb 8–15 2027), Steam Next Fest
  (Jun 14–21 2027), and **1.0 on Thu Jul 22 2027** (no Early Access).

## Milestones

Each step can start once the one it is blocked by is done. Owners are the
people who have to act; agents draft everything they can.

| # | Milestone | Epic | Blocked by | Owner | Target | Priority |
|---|---|---|---|---|---|---|
| 1 | Studio set-up: SQL Monkey Studios LLC | #1325 | none | all three | Dec 2026 | p1 |
| 2 | Steamworks account and app ID | #1326 | #1249 (in 1) | Tommy | Dec 2026 | p1 |
| 3 | Online play ready for strangers | #1327 | none | Tommy | Dec 2026 | p1 |
| 4 | Steam "Coming Soon" store page live | #1328 | 2 | Tommy (agents draft) | mid-Dec 2026 | p1 |
| 5 | Steam Playtest at the Couch Co-Op Fest | #1329 | 3, 4 | Tommy, Austin | Feb 8–15 2027 | p2 |
| 6 | Steam Next Fest demo | #1330 | 5 | Tommy, Austin | Jun 14–21 2027 | p2 |
| 7 | 1.0 launch on Steam | #1331 | 6 | all three | Jul 22 2027 | p2 |
| 8 | After launch | #1332 | 7 | all | later | p3 |

### 1. Studio set-up: SQL Monkey Studios LLC

The company that signs with Steam, owns the code, art and music, and holds the
bank account. The partner meeting (2026-11-11, #685) set the steps.

- PO box, Articles of Organization, EIN, operating agreement (all three sign
  within 90 days), bank, newspaper notices and the state affidavits (#1249).
  Filing, the EIN and the bank account (steps 2, 3 and 5) gate the Steamworks
  signup.
- Company domain and email forwarding, sqlmonkeystudios.com (#1248).

### 2. Steamworks account and app ID

- Partner signup as the LLC, tax and bank forms (they can take up to 30 days)
  (#1229, readiness 1.1–1.2).
- Pay the $100 app fee, record the AppID and depot IDs as repo variables so
  builds stop using the test app 480 (#1316, readiness 1.3–1.4; the builds side
  is done in #1289).

### 3. Online play ready for strangers

Strangers play online through our relay in the Steam Playtest, so this gates
milestone 5.

- Relay deploys from CI: the Fly deploy token as a repo secret (#1244).
- The internet playtest with PC builds on itch (#242).
- Latency for players far from the one Fly region (#1274).

### 4. Steam "Coming Soon" store page live

Wishlists bank from this date, so it is the first public milestone.

- Owner approves the drafted store text, privacy policy and content survey
  (#1317; readiness 2.1, 2.5, 2.6, 3.1, 3.2; drafts in `docs/launch/`).
- Store art: page background and icons (#1318, readiness 2.2; art budget with
  the partners).
- Trademark clearance search and name lock: "PickFight" (#1319, readiness 4.4).
- Submit the page for Valve review and set it to Coming Soon (readiness 2.7,
  #540).
- The soundtrack's main theme by **Nov 30 2026**, for the Coming Soon trailer
  (#684).

### 5. Steam Playtest at the Couch Co-Op Fest (Feb 2027)

- Register the Playtest by about Dec 28 2026 and run it from
  `docs/launch/playtest-plan.md` (#1320).
- Steam friend invites and lobbies over our relay are already shipped (#298);
  check them on the real app ID.
- The soundtrack's lobby loop and two fight loops by **Jan 31 2027**, in the
  Playtest builds (#684).
- Pitch publishers with the Playtest build (owner decision 2026-10-18).

### 6. Steam Next Fest demo (Jun 14–21 2027)

- Register by Apr 25, trailer cut from the shot list by May 3 (readiness 2.4),
  demo build (its own app ID) by May 17, everything due May 31, press preview
  Jun 3 (#1321).
- Lock the demo content (slice or full game) by about **mid-April 2027**, before
  the demo build (#448; its body still says early January, but the 2026-10-18
  timeline update moved it to mid-April).
- The remaining soundtrack loops and stingers by **Apr 1 2027**, mixed in before
  the trailer and the demo build (#684).
- Steam Deck checks on real hardware and the open Deck decisions (#427).

### 7. 1.0 launch on Steam (Thu Jul 22 2027)

- Builds and depots through SteamPipe, a builder account for CI (#1322,
  readiness 5).
- macOS signing and notarization (#1323, Apple developer account, readiness
  5.8).
- The soundtrack DLC ($2.99) from Sam's original soundtrack (#684).
- Release gates: Steam overlay check, achievements defined in Steamworks, Deck
  Verified, final build through Valve review, price $6.99 with $4.99 for the
  first 14 days, press Release (#1324; readiness 6.4, 6.5, 7.5, 9).

### 8. After launch

Parked until 1.0 ships; picked up from sales and playtest data.

- Steam Workshop for custom stages (#1048); the stage editor itself has
  shipped (see FEATURES.md).
- Online: host migration (#1076), public rooms and matchmaking (#357).
- Audience mode for phones past eight seats (#504).
- Nintendo Switch (#268).

## Open owner decisions that block the plan

- **Steamworks signup entity and timing.** #1229's title says sign up as the
  LLC once it is filed; its body (11-11) says sign up as an individual now and
  transfer later, because the tax checks take up to 30 days. This roadmap
  follows the partner plan (the LLC gates the signup); if the individual route
  is taken instead, milestone 2 no longer waits on milestone 1.
- **Next Fest demo content** (#448), by about mid-April 2027.
- **Store art budget** (#685).
- **Steam Deck:** show the QR or room code during a match, and whether Start
  pauses (#427).
- **Bots:** take every pickup for variety, or only weapons they win with
  (#1310); and #1299's acceptance target.
