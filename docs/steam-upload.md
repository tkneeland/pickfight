# Steam upload setup

The `steam` job in `.github/workflows/release.yml` (#722) uploads each tagged
build to Steam's `beta` branch. It never sets a build live; promote by hand in
Steamworks. Until the secrets and variables below exist, the job prints which
one is missing and skips, so tags still pass.

## One-time owner setup

1. In Steamworks, create the app and one depot per OS (Windows, macOS, Linux).
   Note the app ID and the three depot IDs (see #540).
2. Make a build-only Steamworks account with the "Edit App Metadata" and
   "Publish App Changes To Steam" permissions on the app (a dedicated account,
   not your main one).
3. On your own machine, log that account in once with steamcmd so it writes the
   session file, answering the Steam Guard prompt:
   `steamcmd +login <build_account> +quit`
4. Base64 the resulting `config.vdf` (macOS: `~/Library/Application Support/Steam/config/config.vdf`;
   Linux: `~/Steam/config/config.vdf`): `base64 -i config.vdf | pbcopy` (Linux: `base64 -w0 config.vdf`).
5. In the GitHub repo settings add:
   - Secrets: `STEAM_USERNAME` (the build account name), `STEAM_CONFIG_VDF` (the base64 text).
   - Variables: `STEAM_APP_ID`, `STEAM_DEPOT_WIN`, `STEAM_DEPOT_MAC`, `STEAM_DEPOT_LINUX`.
6. Push a `v*` tag (or run the workflow by hand). The build appears on the
   `beta` branch in Steamworks; promote it to `default` there when ready.

The session in `config.vdf` can expire; if the upload fails on login, repeat
steps 3 to 5.

## How it works

- `steam/*.vdf.template` hold `${...}` placeholders; the job fills them with
  `envsubst` from the variables. No IDs live in the repo.
- The job downloads the `pickfight-builds` artifact, unzips each OS into
  `steam/content/<os>` (the depot content roots; the macOS inner export zip is
  unpacked too, so Steam receives the `.app`), and runs steamcmd from the
  `steamcmd/steamcmd` Docker image.
- The app build sets `SetLive` to `beta`.

## Notes

- Export presets carry the Windows company and product and the macOS bundle id.
  The version is stamped into `project.godot` from the tag by the `export` job;
  it is not copied into the Windows file version (needs a four-part number).
- The `steamcmd/steamcmd:latest` image is not pinned by digest; pin it if
  reproducible uploads matter.
