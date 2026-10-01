# Deploy

Relay on Fly.io (region iad); PC builds on itch.io (unsigned; one build serves host and client).

## Relay

1. `fly auth signup` (or `fly auth login`).
2. From the repository root: `fly launch --no-deploy --copy-config --config relay/fly.toml --dockerfile relay/Dockerfile`. If `pickfight-relay` is taken, pick another app name.
3. `fly deploy --config relay/fly.toml --dockerfile relay/Dockerfile`. The Dockerfile copies the whole repo, so build context is the root.
4. Set `[pickfight] relay_url` in `project.godot` to `wss://<app>.fly.dev` (Fly terminates TLS). Live: `wss://pickfight-relay.fly.dev` (deployed 2026-10-01). Run the local dev relay with `--relay=ws://127.0.0.1:9080`.

## PC builds

1. Create the itch.io project.
2. In GitHub, add the secret `BUTLER_API_KEY` (itch.io API key) and the variable `ITCH_TARGET` (e.g. `user/pickfight`).
3. Tag to release: `git tag v0.1 && git push origin v0.1`. The `release` workflow exports Windows, macOS and Linux and pushes channels `windows`, `mac` and `linux`. Without the secret it only uploads artifacts.

## Unsigned macOS

Gatekeeper blocks the unsigned app on first launch: right-click the app, choose Open, then Open again.
