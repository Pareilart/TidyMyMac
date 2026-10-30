#!/bin/sh
# Compile TidyMyMac et assemble build/TidyMyMac.app (signature ad hoc) ainsi que son archive .zip.
# La version vient du fichier VERSION ; le numéro de build est le nombre de commits git.
set -e
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/TidyMyMac.app"
ZIP="build/TidyMyMac-$VERSION.zip"

rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TidyMyMac" "$APP/Contents/MacOS/TidyMyMac"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Traductions : français (langue source), anglais, espagnol, allemand.
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"
# Règles de nettoyage intégrées (docs/RULES.md).
cp -R Resources/Rules "$APP/Contents/Resources/Rules"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $VERSION" \
    -c "Set :CFBundleVersion $BUILD" \
    "$APP/Contents/Info.plist"
# Identité stable si elle existe (scripts/setup-signing.sh) : macOS garde alors les autorisations
# accordées à l'app d'une compilation à l'autre. Sinon, signature ad hoc.
IDENTITY="-"
if security find-certificate -c "TidyMyMac Local" >/dev/null 2>&1; then
    IDENTITY="TidyMyMac Local"
fi
codesign --force --sign "$IDENTITY" "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Application prête : $APP (version $VERSION, build $BUILD)"
echo "Archive : $ZIP"
