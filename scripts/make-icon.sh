#!/bin/sh
# Régénère Resources/AppIcon.icns à partir de l'icône dessinée dans l'app (AppIconArt, UI/BrandGlyph.swift).
set -e
cd "$(dirname "$0")/.."

./build.sh >/dev/null
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

build/TidyMyMac.app/Contents/MacOS/TidyMyMac --app-icon "$WORK/icon.png"
ICONSET="$WORK/AppIcon.iconset"
mkdir "$ICONSET"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$WORK/icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$WORK/icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Icône générée : Resources/AppIcon.icns (relancez ./build.sh pour l'inclure)"
