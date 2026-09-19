#!/bin/zsh
# Renders Resources/AppIcon.icns and docs/icon.png from scripts/make-icon.swift
set -euo pipefail
cd "$(dirname "$0")/.."

swift scripts/make-icon.swift
cd Resources/AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s icon_512x512@2x.png --out icon_${s}x${s}.png >/dev/null
  [[ $s -lt 512 ]] && sips -z $((s*2)) $((s*2)) icon_512x512@2x.png --out icon_${s}x${s}@2x.png >/dev/null
done
cd ..
iconutil -c icns AppIcon.iconset -o AppIcon.icns
rm -rf AppIcon.iconset
sips -s format png -Z 256 AppIcon.icns --out ../docs/icon.png >/dev/null
echo "Hotovo: Resources/AppIcon.icns, docs/icon.png"
