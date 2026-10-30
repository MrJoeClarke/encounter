#!/bin/sh
# Regenerates Samples/Saltmarch Coast.encounterworld. Run from the repository root:
#   sh Samples/make-sample-world/build.sh
set -e
APP=encounter/encounter
TMP=$(mktemp -d)
swiftc -o "$TMP/make-sample-world" \
    Samples/make-sample-world/main.swift \
    "$APP/Transfer/WorldArchive.swift" \
    "$APP/Transfer/WorldPackage.swift" \
    "$APP/Models/AttributeValue.swift" \
    "$APP/Models/InWorldDate.swift"
"$TMP/make-sample-world" Samples
rm -rf "$TMP"
