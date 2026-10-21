# steam/

SteamPipe build templates. The `steam` job in `.github/workflows/release.yml`
fills the `${...}` placeholders with `envsubst` from GitHub variables, then runs
steamcmd. Nothing here holds an ID or credential. Setup: `docs/steam-upload.md`.

- `app_build.vdf.template`: the app build; uploads to the `beta` branch, never live.
- `depot_windows|macos|linux.vdf.template`: one depot per OS; content roots are the unzipped export folders.
