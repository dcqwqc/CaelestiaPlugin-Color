# CaelestiaPlugin-Color

Exact Caelestia colour control without hardware-lighting dependencies.

The plugin owns the persistent `~/.config/caelestia/color_overrides.json` workflow and the helpers that reapply those choices after theme or wallpaper changes. It controls the shell accent, exact Material/terminal palette overrides, Hyprland border colour and Papirus folder colour.

**OpenRGB is intentionally not part of this plugin.** Install `CaelestiaPlugin-OpenRGB` only on machines where hardware lighting is wanted.

## Install

Enable `dcqwqc/color` in Caelestia and run `./install.sh` once so existing Caelestia post-hooks point at the plugin-owned helpers. Existing override data is preserved.

## Wallpaper-linked profiles (preview)

Color → **Wallpaper-linked profiles** creates a named snapshot of your existing colors and links it to the current wallpaper. The spectrum edits global primary/accent colors directly when there is no wallpaper profile linked; creating/linking a profile redirects edits to the linked profile without modifying the global values. The **Harmony spectrum** is a two-dimensional hue/tone field (rainbow vertical, light-to-dark horizontal). One large draggable **Base** marker selects the seed color; the smaller **Light** and **Dark** markers follow on either side. The matching swatches update as you drag, and the seed is saved only on release. Switch between independent Primary and Accent seeds; Material 3 regenerates secondary/tertiary tonal variants and contrast rather than tinting every role identically. The three guide markers approximate tonal relationships in HSL; the rendered Material 3 colors are the source of truth. The existing exact per-role editor remains available.

Profiles live in `~/.config/caelestia/wallpaper_profiles.json` (portable JSON), distinct from the untouched global `color_overrides.json`. The live apply hook overlays only the active wallpaper's profile in memory, without mutating global defaults. Multiple wallpapers can link to one profile. Unlinking restores the global palette, and corrupted/unknown-format profile stores are never automatically overwritten. The scheme owns light/dark mode; profiles do **not** force mode switching.

CLI examples:

```sh
scripts/color_profiles.py status
scripts/color_profiles.py create --name "Lain"
scripts/color_profiles.py edit --id PROFILE_ID --primary 8763b8 --accent e3a95f
scripts/color_profiles.py link --id PROFILE_ID
scripts/color_profiles.py unlink
```

Wallpaper Engine preview filenames are identified by Workshop ID, not by the preview title. Normal files are keyed relative to `~/Pictures/Wallpapers` where possible. The first release intentionally does not change the wallpaper renderer, theme mode, or advanced per-role controls. Color profile switching is applied by the existing color post-hook.
