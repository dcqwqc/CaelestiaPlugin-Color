# CaelestiaPlugin-Color

Exact Caelestia colour control without hardware-lighting dependencies.

The plugin owns the persistent `~/.config/caelestia/color_overrides.json` workflow and the helpers that reapply those choices after theme or wallpaper changes. It controls the shell accent, exact Material/terminal palette overrides, Hyprland border colour and Papirus folder colour.

**OpenRGB is intentionally not part of this plugin.** Install `CaelestiaPlugin-OpenRGB` only on machines where hardware lighting is wanted.

## Install

Enable `dcqwqc/color` in Caelestia and run `./install.sh` once so existing Caelestia post-hooks point at the plugin-owned helpers. Existing override data is preserved.
