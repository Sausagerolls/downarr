#!/bin/bash
# Archive a signed, sandboxed Release build and export a Mac App Store .pkg into build/AppStore/.
#   ./archive.sh          archive + export the .pkg (nothing leaves this Mac)
#   ./archive.sh upload   archive + upload straight to App Store Connect
# Needs Xcode signed in to the J4UJD4Z33J team (Xcode > Settings > Accounts). Bump
# CURRENT_PROJECT_VERSION in project.yml before every upload; App Store Connect rejects repeats.
set -euo pipefail
cd "$(dirname "$0")"

DEST="${1:-export}"
ARCHIVE="build/Downarr.xcarchive"
OUT="build/AppStore"
LOG="build/last-archive.log"
mkdir -p build

command -v xcodegen >/dev/null || { echo "xcodegen not installed (brew install xcodegen)"; exit 1; }
xcodegen generate --quiet

cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>${DEST}</string>
  <key>teamID</key><string>J4UJD4Z33J</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

rm -rf "$ARCHIVE" "$OUT"
echo "Archiving…"
xcodebuild archive \
  -project Downarr.xcodeproj \
  -scheme Downarr \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates > "$LOG" 2>&1 || { grep -E "error:" "$LOG" | sort -u | head -40; echo "ARCHIVE FAILED (see $LOG)"; exit 1; }

echo "Exporting ($DEST)…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath "$OUT" \
  -allowProvisioningUpdates >> "$LOG" 2>&1 || { grep -E "error" "$LOG" | sort -u | head -40; echo "EXPORT FAILED (see $LOG)"; exit 1; }

APP="$ARCHIVE/Products/Applications/Downarr.app"
echo "Entitlements:"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - | grep -E "sandbox|network|files" || true
if [ "$DEST" = upload ]; then
  echo "UPLOADED -> App Store Connect (processing takes a few minutes)"
else
  echo "ARCHIVE OK -> $OUT/$(ls "$OUT" | grep -m1 '\.pkg$')"
fi
