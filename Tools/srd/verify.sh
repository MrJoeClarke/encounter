#!/bin/sh
# Verifies a content pack against its official SRD PDF. See verify-pack.swift for details.
#   sh Tools/srd/verify.sh <pack.json> <srd.pdf>
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
TMP=$(mktemp -d)
cp "$DIR/verify-pack.swift" "$TMP/main.swift"
swiftc -O -o "$TMP/verify-pack" "$TMP/main.swift" "$DIR/PageReading.swift"
set +e
"$TMP/verify-pack" "$1" "$2"
STATUS=$?
rm -rf "$TMP"
exit $STATUS
