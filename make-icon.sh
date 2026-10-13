#!/bin/bash
# Regenerate the app icon from Tools/IconGen/main.swift: Sources/Resources/AppIcon.icns (used by
# ./build-clt.sh) and the AppIcon set in Sources/Resources/Assets.xcassets (used by Xcode builds
# and required by the Mac App Store). Edit the drawing code there, run this, then rebuild the app.
set -euo pipefail
cd "$(dirname "$0")"

CLT=/Library/Developer/CommandLineTools
SDK="$CLT/SDKs/MacOSX26.sdk"
[ -d "$SDK" ] || SDK="$CLT/SDKs/MacOSX.sdk"

mkdir -p build
"$CLT/usr/bin/swiftc" -sdk "$SDK" -target arm64-apple-macosx14.0 -O \
  Tools/IconGen/main.swift -o build/icongen

rm -rf build/AppIcon.iconset
build/icongen build/AppIcon.iconset > /dev/null
iconutil -c icns build/AppIcon.iconset -o Sources/Resources/AppIcon.icns

SET=Sources/Resources/Assets.xcassets/AppIcon.appiconset
rm -rf "$SET"
mkdir -p "$SET"
cp build/AppIcon.iconset/*.png "$SET/"
{
  echo '{'
  echo '  "images" : ['
  first=1
  for size in 16 32 128 256 512; do
    for scale in 1 2; do
      if [ $scale = 1 ]; then name="icon_${size}x${size}.png"; else name="icon_${size}x${size}@2x.png"; fi
      [ $first = 1 ] || echo ','
      first=0
      printf '    { "filename" : "%s", "idiom" : "mac", "scale" : "%sx", "size" : "%sx%s" }' \
        "$name" "$scale" "$size" "$size"
    done
  done
  echo
  echo '  ],'
  echo '  "info" : { "author" : "xcode", "version" : 1 }'
  echo '}'
} > "$SET/Contents.json"
cat > Sources/Resources/Assets.xcassets/Contents.json <<'JSON'
{
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
echo "ICON OK -> Sources/Resources/AppIcon.icns, $SET"
