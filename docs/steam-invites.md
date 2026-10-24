# Steam friend invites (#298)

Online matches only (ADR-0021). While the host PC hosts an Online room with Steam running, Steam rich presence carries `connect` = `+pickfight_room <CODE>` and a `status` ("In the lobby" / "In a match"); it is cleared when the room closes. Game traffic stays on our relay. All Steam calls live in `scripts/SteamPlatform.gd`.

## Owner test (two Steam accounts, app 480)

1. Two machines (or one machine plus a second PC), each with its own Steam account that are friends, each with `steam_appid.txt` containing `480`.
2. Machine A: launch the game, pick Online in the lobby. An "Invite Steam friends" button shows under the room code.
3. Press it: Steam's overlay invite dialog opens. Invite account B.
4. Machine B, game closed: accept the invite in Steam. The game launches with `+pickfight_room <CODE>` and lands in that room.
5. Machine B, game already running on the title screen: B right-clicks A in the friends list and picks "Join Game". B goes straight into the join flow with that room code.
6. Close the room on A: A's friends list entry loses "Join Game".
7. A Couch match shows no button and no Join Game.

## Invites are never ignored (#1075)

A Steam invite skips the title screen's Host-or-Join fork and is always acted on:

- **Host alone or with only bots** (lobby or match): Join Game goes straight to the join screen with the friend's code.
- **Host with another human seated** (a phone-less Online player, a gamepad, a remote player; lobby, countdown or mid-match): a prompt asks "A friend invited you to a room. Leave yours? This ends it for everyone in it." Join (Enter, Y, or gamepad A) closes the room, so the others see "Host left.", and opens the join screen with the code. Stay (Esc, N, or gamepad B) keeps the room and drops the invite. There is no timeout and the match keeps running behind the prompt. A second invite while it is open replaces the pending code, and if the room empties meanwhile the prompt just joins.
- **Already a client in another room**: the invite makes the client leave that room and join the friend's.

Owner test: with a second human in machine A's lobby, have a third account invite A; check the prompt, then Join and Stay. Repeat mid-match, and with A alone (no prompt).
