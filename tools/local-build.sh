#!/usr/bin/env bash
# Build a local unsigned IPA using the latest release tag for the version.
# Requires xtool's Darwin SDK and a Swift toolchain matching that SDK.
set -euo pipefail
cd "$(dirname "$0")/.."

git fetch --tags --quiet 2>/dev/null || true
TAG=$(git tag --list 'v1.0.*' --sort=-v:refname | head -n 1 || true)

if [ -n "$TAG" ]; then
    VERSION=${TAG#v}
    BUILD=${VERSION##*.}
    BACKUP=$(mktemp)
    cp Info.plist "$BACKUP"
    trap 'mv "$BACKUP" Info.plist' EXIT
    python3 - "$VERSION" "$BUILD" <<'PY'
import plistlib
import sys

with open("Info.plist", "rb") as handle:
    info = plistlib.load(handle)
info["CFBundleShortVersionString"] = sys.argv[1]
info["CFBundleVersion"] = sys.argv[2]
with open("Info.plist", "wb") as handle:
    plistlib.dump(info, handle)
PY
    echo "Building ShortSign $VERSION ($BUILD)"
else
    echo "No v1.0.* tag found; keeping the current Info.plist version" >&2
fi

xtool dev build -c release --ipa
