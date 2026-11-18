#!/bin/bash
# Open the built No-halla app.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Build/Products/Release/No-halla.app"
if [ ! -d "$APP" ]; then
  echo "No-halla.app not found. Run ./scripts/build.sh first." >&2
  exit 1
fi
open "$APP"