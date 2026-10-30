#!/bin/sh
# Liste, pour chaque langue, les textes de l'app qui n'ont pas encore de traduction.
# Les clés sont les textes français du code ; %@ remplace un texte et %lld un nombre.
set -e
cd "$(dirname "$0")/.."

KEYS="$(mktemp)"
trap 'rm -f "$KEYS"' EXIT
find Sources/TidyMyMac Sources/SemanticSearch -name '*.swift' ! -name 'ScreenshotStudio.swift' | sort \
    | xargs perl scripts/extract-strings.pl | cut -f1 \
    | grep -vxF -e '[UNK]' -e '%lld%' -e '%lld/%lld' -e 'TidyMyMac' > "$KEYS"

STATUS=0
for DIR in Resources/Localization/*.lproj; do
    LANG_CODE="$(basename "$DIR" .lproj)"
    [ "$LANG_CODE" = "fr" ] && continue
    MISSING="$(while IFS= read -r KEY; do
        grep -qF "\"$KEY\" =" "$DIR/Localizable.strings" || printf '  %s\n' "$KEY"
    done < "$KEYS")"
    if [ -n "$MISSING" ]; then
        echo "$LANG_CODE : textes sans traduction"
        echo "$MISSING"
        STATUS=1
    else
        echo "$LANG_CODE : complet ($(wc -l < "$KEYS" | tr -d ' ') textes)"
    fi
done
exit $STATUS
