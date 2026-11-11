# V15: Nagle on the client and host WebSocket sockets (#1195)

Checked 2026-11-10 against Godot `4.6.2-stable`,
`modules/websocket/wsl_peer.cpp` (fetched with
`gh api "repos/godotengine/godot/contents/modules/websocket/wsl_peer.cpp?ref=4.6.2-stable"`).

**Result: Nagle is already off on every socket the game opens. No follow-up.**

- Outgoing sockets (`WebSocketPeer.connect_to_url`, used by `RemoteClient`
  and the host's `RelayLink`): `WSLPeer::Resolver::try_next_candidate` sets
  it once the TCP connection is up, line 103:
  `p_tcp->set_no_delay(true);` (with the comment "On Windows, setting
  TCP_NODELAY may fail if the socket is still connecting", which is why it is
  set on `STATUS_CONNECTED` and not before).
- Accepted sockets (`WebSocketPeer.accept_stream`, the relay): line 146,
  `tcp->set_no_delay(true);` (the relay's own call at `Relay.gd:245` is
  therefore redundant but harmless).
- `WebSocketPeer.set_no_delay(bool)` is also exposed (line 889), so the plan's
  note that it is not exposed was wrong; nothing needs it.

So the joiner's input-to-screen budget carries no Nagle delay (up to ~40 ms
on some stacks) on the client or host leg; the remaining game-added parts are
the input smoother, the snapshot wait and the interpolation buffer (plan,
section 1).
