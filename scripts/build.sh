#!/bin/bash
# Build No-halla (universal, Release, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild -project NoHalla.xcodeproj -scheme NoHalla -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build