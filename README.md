# CaelestiaPlugin-Color

Exact Caelestia colour control without hardware-lighting dependencies.

The plugin owns the persistent `~/.config/caelestia/color_overrides.json` workflow and the helpers that reapply those choices after theme or wallpaper changes. It controls the shell accent, exact Material/terminal palette overrides, Hyprland border colour and Papirus folder colour.

**OpenRGB is intentionally not part of this plugin.** Install `CaelestiaPlugin-OpenRGB` only on machines where hardware lighting is wanted.

## Install

Enable `dcqwqc/color` in Caelestia and run `./install.sh` once so existing Caelestia post-hooks point at the plugin-owned helpers. Existing override data is preserved.

## Quick colors in Caelestia

The main **Wallpaper & style → Colours** page now hosts the Color plugin's
`QuickColors.qml` as its first section (with the matching
`kagami-caelestia` shell integration). This is a **single shared component**:
the plugin's own Settings page also embeds it; there are no independent pickers
to drift out of sync. Moving the large white ring previews the new hue/tone
alongside two lighter/darker white rings, with separate **Primary / Accent**
seeds. Release to save.

The quick section shows the wallpaper-linked profile name or the global mode,
offers **Save for wallpaper**, **Unlink**, **Undo**, and a collapsed chooser for
existing saved profiles. The old extensive color-role controls remain under
**Advanced color settings** in the native Colours page. If the Color plugin is
disabled or missing, the native advanced controls are available and no plugin
file is loaded.

## Wallpaper-linked profiles

Color → **Wallpaper-linked profiles** creates a named snapshot of your existing colors and links it to the current wallpaper. The spectrum edits global primary/accent colors directly when there is no wallpaper profile linked; creating/linking a profile redirects edits to the linked profile without modifying the global values. The **Harmony spectrum** is a two-dimensional hue/tone field (rainbow vertical, light-to-dark horizontal). One large, plain white **Base ring** selects the seed color; two smaller white rings follow on either side for Light and Dark. There are no letters, decorative symbols or additional harmony modes. The matching swatches update as you drag, and the seed is saved only on release. Switch between independent Primary and Accent seeds; Material 3 regenerates secondary/tertiary tonal variants and contrast rather than tinting every role identically. The three guide markers approximate tonal relationships in HSL; the rendered Material 3 colors are the source of truth. The picker offers an immediate live preview inside its color swatches; the desktop only changes when you release the pointer. Undo restores the last stored profile operation. The existing exact per-role editor remains available.

Profiles live in `~/.config/caelestia/wallpaper_profiles.json` (portable JSON), distinct from the untouched global `color_overrides.json`. The live apply hook overlays only the active wallpaper's profile in memory, without mutating global defaults. Multiple wallpapers can link to one profile. Unlinking restores the global palette, and corrupted/unknown-format profile stores are never automatically overwritten. The scheme owns light/dark mode; profiles do **not** force mode switching.

CLI examples:

```sh
scripts/color_profiles.py status
scripts/color_profiles.py create --name "Lain"
scripts/color_profiles.py edit --id PROFILE_ID --primary 8763b8 --accent e3a95f
scripts/color_profiles.py link --id PROFILE_ID
scripts/color_profiles.py unlink
scripts/color_profiles.py duplicate --id PROFILE_ID
scripts/color_profiles.py edit --id PROFILE_ID --name "Evening"
scripts/color_profiles.py set-role --id PROFILE_ID --role primaryContainer --color aabbcc
scripts/color_profiles.py reset-role --id PROFILE_ID --role primaryContainer
scripts/color_profiles.py undo
```

Wallpaper Engine preview filenames are identified by Workshop ID, not by the preview title. Normal files are keyed relative to `~/Pictures/Wallpapers` where possible. The first release intentionally does not change the wallpaper renderer, theme mode, or advanced per-role controls. Color profile switching is applied by the existing color post-hook.

## Wallpaper workflow

- **Automatic restore:** Once a profile is linked to a wallpaper, Caelestia's existing wallpaper-change hook reapplies it. Different image paths use their location under `~/Pictures/Wallpapers`; Wallpaper Engine items use their Steam Workshop ID. No forced light/dark mode.
- **Manage:** The native Color settings page shows the selected wallpaper preview and a collapsible library. New profile snapshots current global colors, or link an existing one; rename, duplicate, unlink, or delete with an explicit second click. The last operation is undoable. Multiple wallpapers may reference a single profile.
- **Advanced:** The collapsible exact-role editor can edit or reset any allowlisted Material 3/terminal color (`save_colors.ALLOWED_ROLES`). Global overrides remain separate from profile overlays. Invalid/corrupt stores never get overwritten; a broken profile file degrades to global colors in the wallpaper/theme hook.
- **Sync:** Kagami's `syncColors` category includes `wallpaper_profiles.json` in addition to global overrides. Wallpaper runtime/monitor selection remains device-local; two-way file conflicts follow Kagami's existing conflict workflow. Sync should only run after both peers have the updated Kagami plugin installed.
- **Checks:** `python -m unittest discover -s tests -v`, `python -m py_compile scripts/*.py`, and `/usr/lib/qt6/bin/qmlformat SettingsUi.qml >/dev/null`. The full interactive Qt plugin still needs visual regression testing for each supported display scale.
