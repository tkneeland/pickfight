# Steam store screenshots

Nine 1920x1080 PNGs of the real game (issue #723, `docs/steam-readiness.md` item 2.3). Regenerate them all with the command below; it opens one window, plays bot matches, saves the shots and quits itself.

```
perl -e 'alarm 180; exec @ARGV' godot --path . -s tools/capture_store_screenshots.gd -- --out=$PWD/docs/launch/screenshots
```

- `03-lobby.png` shows a sample address (`http://192.168.1.20:8080/`) and its QR, set by the capture script, never the capturing machine's own. Regenerating needs an unlocked, logged-in display; a locked screen renders blank grey.

| File | What it shows | Suggested caption |
|---|---|---|
| `01-title.png` | Title screen with the Couch, Online and Solo choices | Pick how you play: one couch, online, or solo against bots |
| `02-brawl.png` | Eight players brawling in the Bowl, pickaxes swinging | Eight players, one screen, one very pointy pickaxe |
| `03-lobby.png` | Couch lobby: join QR code, eight seated player cards, mode list | Scan the QR code with your phone and you are in |
| `04-teams.png` | Red vs Blue Teams match on the Colosseum | Two teams, four players each |
| `05-soccer.png` | Soccer mode: ball, goals and score banner | Soccer, with pickaxes |
| `06-capture-the-flag.png` | Capture the Flag: both bases, flags and the score banner | Steal their flag, defend yours |
| `07-hazard-stage.png` | Furnace stage with lava walls, a kill feed and a fight in the middle | The floor is lava, and so are the walls |
| `08-weapons.png` | A different weapon in every hand: sword, fishing rod, spear and more | Fifteen weapons, picked up on the stage |
| `09-podium.png` | Victory podium for eight players with the match awards | Winner, podium, rematch |
