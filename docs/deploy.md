# Deploy

Relay on Fly.io (region iad); PC builds on itch.io (unsigned; one build serves host and client).

## Relay

1. `fly auth signup` (or `fly auth login`).
2. From the repository root: `fly launch --no-deploy --copy-config --config relay/fly.toml --dockerfile relay/Dockerfile`. If `pickfight-relay` is taken, pick another app name.
3. `fly deploy --config relay/fly.toml --dockerfile relay/Dockerfile`. The Dockerfile copies the whole repo, so build context is the root.
4. Set `[pickfight] relay_url` in `project.godot` to `wss://<app>.fly.dev` (Fly terminates TLS). Live: `wss://pickfight-relay.fly.dev` (deployed 2026-10-01). Run the local dev relay with `--relay=ws://127.0.0.1:9080`.

### Enabling in-game feedback (#262)

The Settings panel's Feedback button files GitHub issues through the relay. Until the token exists the relay answers 503 and the game says "Feedback is offline right now". To enable it:

1. `fly secrets set GITHUB_FEEDBACK_TOKEN=<fine-grained token, Issues: write on tkneeland/pickfight> -a pickfight-relay`
2. `fly deploy . --config relay/fly.toml --dockerfile relay/Dockerfile --ha=false --yes`

The token lives only on the relay, never in the game. Limits: 5 filings per IP per hour, 2000 characters. Behind Fly's proxy the relay sees Fly's address, not the player's, so these per-IP limits (and the #580 per-IP seat cap, which only applies when the real IP is known) act roughly globally. The relay can read the real client IP from Fly's PROXY protocol line (#580), but this is **off by default** and untested on Fly. To turn it on: apply `docs/relay-proxy-proto-flytoml.diff` to `relay/fly.toml` (a `[[services]]` block whose port 443 has the handlers `["tls","proxy_proto"]`) **and** set `PICKFIGHT_PROXY_PROTO=1` in the same deploy. Both must ship together, or every connection fails. Afterwards, host a room to confirm it still connects; if not, redeploy the previous commit.

## PC builds

1. Create the itch.io project.
2. In GitHub, add the secret `BUTLER_API_KEY` (itch.io API key) and the variable `ITCH_TARGET` (e.g. `user/pickfight`).
3. Tag to release: `git tag v0.1 && git push origin v0.1`. The `release` workflow exports Windows, macOS and Linux and pushes channels `windows`, `mac` and `linux`. Without the secret it only uploads artifacts.

## Unsigned macOS

Gatekeeper blocks the unsigned app on first launch: right-click the app, choose Open, then Open again.
