#!/bin/sh
# Publie une nouvelle version de TidyMyMac.
#
#   ./scripts/release.sh patch | minor | major | X.Y.Z
#
# 1. calcule la nouvelle version et l'écrit dans VERSION ;
# 2. rattache la section « Non publié » du CHANGELOG à cette version ;
# 3. compile l'app et son archive build/TidyMyMac-X.Y.Z.zip ;
# 4. crée le commit « Version X.Y.Z » et le tag vX.Y.Z ;
# 5. après confirmation, pousse et publie la release GitHub (CLI gh) avec l'archive jointe.
#    Les apps installées la détectent ensuite au lancement ou dans les 24 heures.
set -e
cd "$(dirname "$0")/.."

if [ $# -ne 1 ]; then
    echo "Usage : $0 patch|minor|major|X.Y.Z"
    exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
    echo "Le dépôt contient des modifications non commitées : commitez-les avant de publier."
    exit 1
fi

CURRENT="$(tr -d '[:space:]' < VERSION)"
MAJOR="$(echo "$CURRENT" | cut -d. -f1)"
MINOR="$(echo "$CURRENT" | cut -d. -f2)"
PATCH="$(echo "$CURRENT" | cut -d. -f3 | cut -d- -f1)"
case "$1" in
    patch) NEXT="$MAJOR.$MINOR.$((PATCH + 1))" ;;
    minor) NEXT="$MAJOR.$((MINOR + 1)).0" ;;
    major) NEXT="$((MAJOR + 1)).0.0" ;;
    *) NEXT="$1" ;;
esac

if ! echo "$NEXT" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'; then
    echo "Version invalide : $NEXT"
    exit 1
fi
if git rev-parse -q --verify "refs/tags/v$NEXT" >/dev/null; then
    echo "Le tag v$NEXT existe déjà."
    exit 1
fi

NOTES="$(awk '/^## \[Non publié\]/ { inside = 1; next } /^## \[/ { inside = 0 } inside' CHANGELOG.md)"
if [ -z "$(echo "$NOTES" | tr -d '[:space:]')" ]; then
    echo "Décrivez les nouveautés sous « ## [Non publié] » dans CHANGELOG.md avant de publier."
    exit 1
fi

echo "Version $CURRENT → $NEXT"
echo "$NEXT" > VERSION
awk -v version="$NEXT" -v date="$(date +%Y-%m-%d)" \
    '{ print } /^## \[Non publié\]/ { print ""; print "## [" version "] - " date }' \
    CHANGELOG.md > CHANGELOG.md.tmp
mv CHANGELOG.md.tmp CHANGELOG.md

./build.sh

git add VERSION CHANGELOG.md
git commit -m "Version $NEXT"
git tag -a "v$NEXT" -m "TidyMyMac $NEXT"

printf "Pousser et publier la release v%s sur GitHub ? [o/N] " "$NEXT"
read -r ANSWER
if [ "$ANSWER" != "o" ] && [ "$ANSWER" != "O" ]; then
    echo "Release préparée localement. Pour publier plus tard :"
    echo "  git push --follow-tags"
    echo "  gh release create v$NEXT build/TidyMyMac-$NEXT.zip --title \"TidyMyMac $NEXT\""
    exit 0
fi
if ! command -v gh >/dev/null 2>&1; then
    echo "La CLI gh est introuvable. Poussez avec « git push --follow-tags »,"
    echo "puis créez la release v$NEXT sur GitHub en joignant build/TidyMyMac-$NEXT.zip."
    exit 1
fi

NOTES_FILE="$(mktemp)"
printf '%s\n' "$NOTES" > "$NOTES_FILE"
git push --follow-tags
gh release create "v$NEXT" "build/TidyMyMac-$NEXT.zip" --title "TidyMyMac $NEXT" --notes-file "$NOTES_FILE"
rm -f "$NOTES_FILE"
echo "TidyMyMac $NEXT est publiée."
