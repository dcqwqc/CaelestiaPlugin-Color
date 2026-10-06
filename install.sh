#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$HOME/.config/caelestia"
mkdir -p "$CFG"
for name in save_colors.py apply_color_overrides.py; do
  target="$CFG/$name"
  source="$ROOT/scripts/$name"
  if [[ -e "$target" && ! -L "$target" ]]; then
    cp -a "$target" "$target.pre-color-plugin"
    rm -f "$target"
  fi
  ln -sfn "$source" "$target"
done
chmod +x "$ROOT/scripts/"*.py
printf 'Color helpers installed into %s\n' "$CFG"
