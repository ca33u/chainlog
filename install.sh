#!/bin/zsh
# Copies the addon into the WoW Forever AddOns directory. Run after every
# edit, then /reload in game.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
DST="/Applications/World of Warcraft/_forever_/Interface/AddOns/Chainlog"
mkdir -p "$DST"
cp "$SRC/Chainlog.toc" "$SRC/LICENSE" "$SRC/README.md" "$SRC/README.ru.md" "$DST/"
mkdir -p "$DST/Media" && cp "$SRC/Media/icon.tga" "$DST/Media/"
grep -v '^##' "$SRC/Chainlog.toc" | tr -d '\r' | while read -r file; do
  [ -z "$file" ] && continue
  cp "$SRC/$file" "$DST/$file"
done
echo "Chainlog installed to $DST. Type /reload in the game."
