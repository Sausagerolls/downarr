#!/bin/bash
# Fallback builder: compiles Downarr.app with the Command Line Tools toolchain and assembles the
# bundle by hand. Used when xcodebuild refuses to run because the Xcode licence has not been
# accepted for the installed version (`sudo xcodebuild -license accept` fixes that, then use
# ./build.sh instead).
set -euo pipefail
cd "$(dirname "$0")"

CLT=/Library/Developer/CommandLineTools
SDK="$CLT/SDKs/MacOSX26.sdk"
[ -d "$SDK" ] || SDK="$CLT/SDKs/MacOSX.sdk"
SWIFTC="$CLT/usr/bin/swiftc"
APP="build/Downarr.app"
MODE="${1:-debug}"

[ -x "$SWIFTC" ] || { echo "Command Line Tools swiftc not found at $SWIFTC"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

OPT=(-Onone)
[ "$MODE" = "release" ] && OPT=(-O -whole-module-optimization)

echo "Compiling with Command Line Tools ($MODE)…"
# shellcheck disable=SC2046
"$SWIFTC" \
  -sdk "$SDK" \
  -target arm64-apple-macosx14.0 \
  -swift-version 5 \
  -module-name Downarr \
  "${OPT[@]}" \
  -framework AppKit -framework SwiftUI \
  $(find Sources/Downarr -name '*.swift') \
  -o "$APP/Contents/MacOS/Downarr"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>Downarr</string>
    <key>CFBundleExecutable</key><string>Downarr</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.jakewatts.downarr</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Downarr</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Downarr talks to your Sonarr, Radarr, Jellyfin and NZBGet servers on your local network.</string>
    <key>NSBonjourServices</key><array><string>_http._tcp</string></array>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key><true/>
        <key>NSAllowsLocalNetworking</key><true/>
    </dict>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ -f Sources/Resources/AppIcon.icns ]; then
  cp Sources/Resources/AppIcon.icns "$APP/Contents/Resources/"
  :
fi

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "BUILD OK -> $APP"
