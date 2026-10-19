# Crash reporting (#681)

Opt-out crash reports through the [Sentry Godot SDK](https://github.com/getsentry/sentry-godot)
2.3.0 (supports Godot 4.5+, so 4.6.2 is fine). Everything is built; it stays off until
a DSN is added.

## What is sent, and what is not

Sent: the crash and its stack, the build version (release `pickfight@<tag>`), the platform
and OS, the environment (`release`, or `demo` for the demo build) and two tags, `mode` and
`stage`.

Never sent: player names, room codes, join URLs or LAN IPs. `scripts/CrashReporting.gd`
turns off default PII, the Godot logger (events, breadcrumbs and logs), the log-file and
scene-tree attachments, screenshots, metrics and breadcrumbs (`max_breadcrumbs = 0`), and
clears the user. In the Sentry project, also tick **Settings > Security & Privacy >
Prevent storing IP addresses** (server-side scrubbing; the game sends no user at all).

It starts only when the addon is installed, `pickfight/sentry_dsn` is non-empty, the run
is not headless, not a scenario or `--bots` run, not the editor, and the player has not
turned off **Settings > More options > Send crash reports** (default on). A change to
that setting applies from the next launch. The first-launch telemetry notice mentions
crash reports in all nine languages.

## Owner steps

1. Create a free project at sentry.io (platform: Godot). Copy its DSN. A DSN is not a
   secret, but keep it out of issues.
2. Paste it into `project.godot`: `[pickfight]` `sentry_dsn="https://..."`.
3. Install the SDK and export: `bash tools/fetch_sentry.sh`, then export as usual
   (`tools/export.sh`, or the release workflow, which also runs the fetch and stamps the
   tag into `application/config/version`; local exports report version `dev`).
4. Run the exported build with the flag `--crash-test`. It captures the message "Pickfight
   crash test", waits two seconds, then crashes on purpose. Both appear in Sentry (the
   crash may be uploaded at the next launch on some platforms) with the build version.
   The flag does nothing when crash reporting is inactive.

Debug builds from the editor never report. Binaries live in the git-ignored
`addons/sentry/`; only macOS (universal), Windows x86_64 and Linux x86_64 are kept.
`always_track_call_stacks` is on in project settings because the SDK needs it for stack
traces.
