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
