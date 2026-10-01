#!/bin/bash
# Publish a Wylde package repository: index.tsv plus binary tarballs.
#
#   repository/
#     index.tsv                       name<TAB>version<TAB>size<TAB>sha256
#     packages/<name>-<version>.tar.gz   prebuilt binary package (the $PKG tree)
#
# The output is a static directory: GitHub Pages, or any web server. `wld sync`
# downloads index.tsv; `wld upgrade` downloads a package and verifies its sha256.
set -e

STAGE=${1:?usage: publish-repo.sh <staging-dir> [output-dir]}
OUT=${2:-/mnt/wylde/repo}
DB=${WLD_ROOT:-/var/lib/wld}

[ -d "$STAGE" ] || { echo "$STAGE is not a directory" >&2; exit 1; }

mkdir -p "$OUT/packages"
: > "$OUT/index.tsv"

echo "# Wylde package repository" >> "$OUT/index.tsv"
echo "# name<TAB>version<TAB>size<TAB>sha256" >> "$OUT/index.tsv"

count=0
for info in "$DB"/db/*.info; do
    [ -f "$info" ] || continue
    name=$(sed -n 's/^name=//p' "$info")
    version=$(sed -n 's/^version=//p' "$info")
    [ -n "$name" ] && [ -n "$version" ] || continue

    tree="$STAGE/$name-$version"
    if [ ! -d "$tree" ]; then
        echo "  skipping $name-$version: no staged tree in $STAGE" >&2
        continue
    fi

    archive="$OUT/packages/$name-$version.tar.gz"
    tar -czf "$archive" -C "$tree" .
    size=$(stat -c %s "$archive")
    sha=$(sha256sum "$archive" | cut -d' ' -f1)
    printf '%s\t%s\t%s\t%s\n' "$name" "$version" "$size" "$sha" >> "$OUT/index.tsv"
    printf '  %-20s %-12s %10s bytes\n' "$name" "$version" "$size"
    count=$((count + 1))
done

echo
echo "$count packages published to $OUT"
echo "serve it with:  python3 -m http.server -d $OUT 8000"
echo "point wld at it with:  echo 'url=http://<host>:8000' > $DB/repository"
