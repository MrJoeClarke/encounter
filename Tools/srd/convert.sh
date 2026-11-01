#!/bin/sh
# Builds a content pack from an official SRD PDF. See convert-srd51.swift for details.
#   sh Tools/srd/convert.sh 51 <srd.pdf> <pack.json>
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
TMP=$(mktemp -d)
cp "$DIR/convert-srd$1.swift" "$TMP/main.swift"
swiftc -O -o "$TMP/convert" "$TMP/main.swift" "$DIR/PageReading.swift" "$DIR/ClassTables.swift"
"$TMP/convert" "$2" "$3"
rm -rf "$TMP"
