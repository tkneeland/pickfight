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

The token lives only on the relay, never in the game. Limits: 5 filings per IP per hour, 2000 characters. Behind Fly's proxy the relay may see the proxy address as the IP, so the limit can act per proxy.

## PC builds

1. Create the itch.io project.
2. In GitHub, add the secret `BUTLER_API_KEY` (itch.io API key) and the variable `ITCH_TARGET` (e.g. `user/pickfight`).
3. Tag to release: `git tag v0.1 && git push origin v0.1`. The `release` workflow exports Windows, macOS and Linux and pushes channels `windows`, `mac` and `linux`. Without the secret it only uploads artifacts.

## Unsigned macOS

Gatekeeper blocks the unsigned app on first launch: right-click the app, choose Open, then Open again.
