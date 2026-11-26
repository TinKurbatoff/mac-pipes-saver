#!/bin/bash
# Builds Pipes.saver (universal: Apple Silicon + Intel) with the Command Line Tools.
# Usage: ./build.sh            build into ./build/Pipes.saver
#        ./build.sh install    build, then install to ~/Library/Screen Savers
#        ARCHS=arm64 ./build.sh   Apple Silicon only (default: "arm64 x86_64")
set -euo pipefail
cd "$(dirname "$0")"

NAME=Pipes
OUT=build
BUNDLE="$OUT/$NAME.saver"

rm -rf "$OUT"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

ARCHS="${ARCHS:-arm64 x86_64}"
for ARCH in $ARCHS; do
  swiftc -O -whole-module-optimization \
    -emit-library -module-name PipesSaver \
    -target "$ARCH-apple-macos12.0" \
    -framework ScreenSaver -framework SceneKit -framework SpriteKit -framework AppKit \
    -o "$OUT/$NAME-$ARCH" Sources/*.swift
done
lipo -create $(for A in $ARCHS; do echo "$OUT/$NAME-$A"; done) -output "$BUNDLE/Contents/MacOS/$NAME"
for A in $ARCHS; do rm "$OUT/$NAME-$A"; done

cp Info.plist "$BUNDLE/Contents/Info.plist"
for f in Resources/*; do [ -e "$f" ] && cp "$f" "$BUNDLE/Contents/Resources/"; done
cp THIRD_PARTY_NOTICES.md "$BUNDLE/Contents/Resources/"

# Ad-hoc signature (local use; no developer account needed).
codesign --force --sign - --timestamp=none "$BUNDLE"
codesign --verify --strict "$BUNDLE"
echo "Built $BUNDLE"

if [ "${1:-}" = "install" ]; then
  DEST="$HOME/Library/Screen Savers"
  mkdir -p "$DEST"
  rm -rf "$DEST/$NAME.saver"
  cp -R "$BUNDLE" "$DEST/"
  # Make the system host pick up the new build.
  killall legacyScreenSaver 2>/dev/null || true
  echo "Installed to $DEST/$NAME.saver"
fi
