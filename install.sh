#!/bin/bash
# Construit Respire, l'installe dans Applications et la lance.
# Autre dossier de destination : ./install.sh ~/Applications
set -euo pipefail
cd "$(dirname "$0")"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Installe d'abord les outils Apple : xcode-select --install" >&2
  exit 1
fi

DEST="${1:-/Applications}"
BUILD="${RESPIRE_BUILD:-$HOME/Library/Caches/respire-build}"

./build.sh

mkdir -p "$DEST"
# Quitte proprement l'ancienne version (elle rend alors la main à macOS).
osascript -e 'if application id "be.gravisterie.respire" is running then tell application id "be.gravisterie.respire" to quit' >/dev/null 2>&1 || true
rm -rf "$DEST/Respire.app"
ditto "$BUILD/Respire.app" "$DEST/Respire.app"
rm -rf "$BUILD/Respire.app"
open "$DEST/Respire.app"

echo "Respire est installée dans $DEST."
echo "Pour l'ouvrir au démarrage : Réglages Système > Général > Ouverture et extensions > « + » > Respire."
