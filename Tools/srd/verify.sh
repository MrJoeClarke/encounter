#!/bin/sh
# Verifies a content pack against its official SRD PDF. See verify-pack.swift for details.
#   sh Tools/srd/verify.sh <pack.json> <srd.pdf>
set -e
TMP=$(mktemp -d)
swiftc -O -o "$TMP/verify-pack" "$(dirname "$0")/verify-pack.swift"
"$TMP/verify-pack" "$1" "$2"
STATUS=$?
rm -rf "$TMP"
exit $STATUS
