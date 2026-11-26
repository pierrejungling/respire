#!/bin/bash
# Compile Respire et crée Respire.app.
# La construction se fait hors du dossier du projet : dans un dossier synchronisé
# (Documents sur iCloud), macOS ajoute des attributs que la signature refuse.
set -euo pipefail
cd "$(dirname "$0")"

BUILD="${RESPIRE_BUILD:-$HOME/Library/Caches/respire-build}"
APP="$BUILD/Respire.app"

swift build -c release --scratch-path "$BUILD/swift"
BIN="$(swift build -c release --scratch-path "$BUILD/swift" --show-bin-path)/Respire"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Respire"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
xattr -cr "$APP"
codesign --force --sign - "$APP"

echo "OK : $APP"
