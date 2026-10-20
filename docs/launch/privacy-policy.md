# PickFight privacy policy

**DRAFT — needs owner approval.** Not legal advice; have it read before it goes on the store page. Facts come from `docs/FEATURES.md`, `docs/steam-readiness.md` (telemetry paragraph), `docs/crash-reporting.md`, the in-game notice text and the sender scripts. Re-check each statement against the code before publishing.

Effective date: [effective date]
Contact: [contact email]

PickFight is made by SQL Monkey Studios. We want to know as little about you as we can. This page says what the game sends, what it keeps on your device, and how to turn things off.

## The short version

- We do not ask you to make an account.
- We do not collect your name, email, address, or any ID for ourselves.
- Match stats and crash reports are anonymous. You can turn both off in Settings.
- The one thing you type that leaves your device is the feedback box, and only when you press Send.

## What the game sends

### 1. Relay traffic (Online matches, and phones that cannot reach the host)

An Online match, and a Couch match where a phone cannot reach the host over Wi-Fi, runs through our relay server (hosted on Fly.io). It passes along what your controller or client sends (your stick movement, your chosen player name, hat and colour) and the host's game snapshots, so the players in the room can see each other. The relay needs your network address to make the connection work. We do not store or log addresses, and we do not keep the match. Solo play uses no relay. A Couch match where every phone reaches the host directly stays on your own network.

### 2. Anonymous match stats (on by default)

At the end of each match the host sends one record to the relay: damage, hits and knockouts per weapon by real players, the game mode, the stages played, whether it was free-for-all or teams, the match length, the winning weapon, and whether the match finished. It contains no names, colours, devices, Steam IDs or any other player ID. Bots are left out. The relay does not store or log the sender's IP address. It keeps only a salted hash in memory, to limit how often one sender can post, and that is lost when the relay restarts. Stored times are rounded to the hour. We use the stats only to balance weapons, modes and stages.

The first time you launch the game, a notice says this and offers "Got it" or "Turn off". Nothing is sent before you have dismissed it. You can change your mind any time in Settings > More options > Share anonymous match stats.

### 3. Crash reports (on by default, opt-out)

If the game crashes, it can send a crash report to Sentry (our crash reporting service): what crashed (the stack), the game version, the platform and system, whether it is the demo or full game, and the game mode and stage. It does not send your name, room codes, network addresses, logs or screenshots. Turn it off in Settings > More options > Send crash reports; the change applies from the next launch. The first-launch notice mentions it too. Reports are only sent from a real game launch, never from the editor or test runs. (Owner: also tick "Prevent storing IP addresses" in the Sentry project, per `docs/crash-reporting.md`.)

### 4. The feedback button

The Feedback button in the host's Settings panel sends the text you type, plus the game version, your operating system and the current stage, to our relay. The relay posts it as an issue on our public GitHub project so we can read and answer it. **Anything you type there is public. Do not put personal information in it.** It only sends when you press Send. We limit it to 2000 characters and five messages per address per hour.

### 5. Steam features

If you run the game through Steam, it uses these Steam features:

- **Rich presence and friend invites:** in an Online room, your Steam friends can see that you are in a lobby or a match and can join with Join Game. Invites carry a room code. Steam handles the friends list; we do not see it.
- **Achievements:** unlocked achievements are reported to Steam under your Steam account.
- **Steam Timeline:** each knockout, round win and match win adds a marker to your Steam Timeline, named with the player involved. The markers stay on your own account in Steam.
- **Steam name:** the game can read your Steam display name to use as your player name.

Steam's own privacy policy applies to what Steam does with this. We do not send your Steam ID to our servers.

## What is stored on your device

- **Settings:** volume, window size, comfort options, bot difficulty, which stages and weapons are on, and the stats and crash-report choices (`user://audio.cfg`).
- **Online name:** the last name you used on the PC join screen (`user://remote_client.cfg`).
- **Lifetime stats:** matches, wins, KOs and favourite weapon, kept on your own device only (`user://career.cfg` on PC; browser local storage on a phone). Clearing a phone browser's site data resets it.
- **Achievements:** `user://achievements.cfg`.
- **Clips and balance log:** pressing F9 saves a short replay clip in `user://clips/`. The host also appends a local damage log (`user://balance_stats.jsonl`) that is never sent anywhere.

"user://" is the game's own folder in your operating system's application data. Delete it to remove all of this.

## Children

PickFight is not aimed at children under 13 and we do not knowingly collect data from them. The game collects no personal data beyond what you choose to type in the feedback box and your player name.

## How to opt out

| What | How |
| --- | --- |
| Match stats | Settings > More options > Share anonymous match stats (or "Turn off" on the first-launch notice) |
| Crash reports | Settings > More options > Send crash reports (applies from next launch) |
| Feedback box | Do not press Send |
| Relay | Play Couch with phones on the same Wi-Fi, or Solo |
| Steam features | Run the game outside Steam, or change Steam's own privacy settings |
| Stored data | Delete the game's "user://" folder |

## Changes and contact

If we change what the game sends, we will update this page and the in-game notice. Questions or deletion requests: [contact email].
