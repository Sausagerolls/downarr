#!/bin/bash
# Runs the app's clients against the live servers and prints what fails.
set -euo pipefail
cd "$(dirname "$0")"
CLT=/Library/Developer/CommandLineTools
SDK="$CLT/SDKs/MacOSX26.sdk"; [ -d "$SDK" ] || SDK="$CLT/SDKs/MacOSX.sdk"
mkdir -p build
"$CLT/usr/bin/swiftc" -sdk "$SDK" -target arm64-apple-macosx14.0 -swift-version 5 \
  -framework AppKit -framework SwiftUI \
  Sources/Downarr/Core/Config.swift \
  Sources/Downarr/Core/HTTPClient.swift \
  Sources/Downarr/Core/Formatters.swift \
  Sources/Downarr/Core/LoadState.swift \
  Sources/Downarr/Design/Theme.swift \
  Sources/Downarr/Arr/ArrCommon.swift \
  Sources/Downarr/Sonarr/SonarrModels.swift \
  Sources/Downarr/Sonarr/SonarrClient.swift \
  Sources/Downarr/Radarr/RadarrModels.swift \
  Sources/Downarr/Radarr/RadarrClient.swift \
  Sources/Downarr/Jellyfin/JellyfinModels.swift \
  Sources/Downarr/Jellyfin/JellyfinClient.swift \
  Sources/Downarr/NZBGet/NZBGetModels.swift \
  Sources/Downarr/NZBGet/NZBGetClient.swift \
  Sources/Downarr/Deluge/DelugeModels.swift \
  Sources/Downarr/Deluge/DelugeClient.swift \
  Tools/Diagnose/main.swift \
  -o build/diagnose
./build/diagnose
