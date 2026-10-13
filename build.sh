#!/bin/bash
# Regenerate the Xcode project and build Downarr.app into build/.
# Falls back to ./build-clt.sh when xcodebuild is blocked by the Xcode licence agreement.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-Debug}"
LOG="build/last-build.log"
mkdir -p build

command -v xcodegen >/dev/null || { echo "xcodegen not installed (brew install xcodegen)"; exit 1; }
xcodegen generate --quiet

set +e
xcodebuild \
  -project Downarr.xcodeproj \
  -scheme Downarr \
  -configuration "$CONFIG" \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build > "$LOG" 2>&1
STATUS=$?
set -e

grep -E "error:" "$LOG" | sort -u | head -40 || true

if [ $STATUS -ne 0 ]; then
  if grep -q "not agreed to the Xcode license" "$LOG"; then
    echo "xcodebuild is blocked by the Xcode licence agreement."
    echo "Run 'sudo xcodebuild -license accept' once to build with Xcode directly."
    echo "Falling back to the Command Line Tools builder..."
    if [ "$CONFIG" = "Release" ]; then exec ./build-clt.sh release; else exec ./build-clt.sh debug; fi
  fi
  echo "BUILD FAILED (full log: $LOG)"
  exit 1
fi

APP="build/DerivedData/Build/Products/$CONFIG/Downarr.app"
rm -rf build/Downarr.app
cp -R "$APP" build/Downarr.app
codesign --force --deep --sign - build/Downarr.app 2>/dev/null || true
echo "BUILD OK -> build/Downarr.app"
