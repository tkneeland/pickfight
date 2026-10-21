# #762 verification

- `bash -n tools/export.sh`: OK.
- `tools/export.sh demo` on macOS, Godot 4.6.2:
  - `build/demo/macos/Pickfight Demo.app`: 202 MB.
  - `build/demo/windows/Pickfight Demo.exe`: 119 MB.
- Demo Linux failed on this Mac: `No export template found at .../export_templates/4.6.2.stable/linux_release.x86_64`.
  - This is a local-template gap, not a script error.
  - The release workflow already exports the "Linux" preset with the full template set.
- The font errors in the first run come from the script's existing first-time `--import` pass. Exports still completed.
