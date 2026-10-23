Stage previews (tools/capture_stage_previews.gd, windowed, 480x270) rendered from
c49d4f8 (`*_before.png`, hand-written platforms) and from the migrated branch
(`*_after.png`, Platform.tscn / KillFloor.tscn instances).

- Bastion and Ziggurat (no animated parts): byte-identical PNGs.
- Flatlands and Gauntlet: same geometry and colours; the PNGs differ only in
  animated parts (conveyor chevrons, lava bubbles), which also differ between
  two renders of the unmigrated stage.

The lossless check itself is the scenario
`stage_platform_geometry_unchanged_refactor_platforms`, which compares every
stage's static bodies, shapes, polygons and tinted colours with
`tools/stage_platform_geometry.txt`, recorded before the migration.
