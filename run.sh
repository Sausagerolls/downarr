#!/bin/bash
# Build then (re)launch Downarr.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh "${1:-Debug}"
pkill -f "build/Downarr.app/Contents/MacOS/Downarr" 2>/dev/null || true
open build/Downarr.app
