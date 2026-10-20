#!/bin/bash
# Builds TeamsAwake.app. Needs only the Xcode Command Line Tools.
#
#   ./scripts/build.sh                    build into ./build
#   ./scripts/build.sh --install          build, install to /Applications, launch
#
# Most people should run ./install.sh instead, which wraps this.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="TeamsAwake"
BUNDLE_ID="local.teamsawake"
OUT="build/$APP_NAME.app"
VERSION="${TEAMSAWAKE_VERSION:-1.0}"   # release builds set this from the git tag

command -v swiftc >/dev/null || {
  echo "error: swiftc not found. Install the Xcode Command Line Tools:" >&2
  echo "  xcode-select --install" >&2
  exit 1
}

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" build

echo "==> rendering icon"
swiftc -swift-version 5 -O -framework AppKit src/makeicon.swift -o build/makeicon
(cd build && ./makeicon)
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

# Universal binary, so the same build runs on Apple Silicon and Intel Macs.
# The native architecture must build; the other is best-effort, because
# cross-compiling can fail on an SDK that lacks it.
echo "==> compiling"
build_arch() {
  swiftc -swift-version 5 -O -target "$1-apple-macos13.0" \
    -framework AppKit -framework ServiceManagement \
    src/governor.swift src/main.swift -o "build/$APP_NAME.$1"
}
NATIVE="$(uname -m)"
if [ "$NATIVE" = "arm64" ]; then OTHER="x86_64"; else OTHER="arm64"; fi
BIN="$OUT/Contents/MacOS/$APP_NAME"
build_arch "$NATIVE"
if build_arch "$OTHER" 2>/dev/null; then
  lipo -create "build/$APP_NAME.arm64" "build/$APP_NAME.x86_64" -output "$BIN"
  echo "    architectures: $(lipo -archs "$BIN")"
else
  cp "build/$APP_NAME.$NATIVE" "$BIN"
  echo "    warning: could not also build $OTHER; this build runs on $NATIVE only."
fi

cp build/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"

cat > "$OUT/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>        <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key>           <string>$VERSION</string>
  <key>CFBundleIconFile</key>          <string>AppIcon</string>
  <key>CFBundleIconName</key>          <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>    <string>13.0</string>
  <key>LSUIElement</key>               <true/>
</dict>
</plist>
PL

# A local certificate is optional and only useful to people editing the code:
# it keeps the Accessibility grant alive across rebuilds. Plain ad-hoc signing
# is correct for everyone else.
IDENTITY="TeamsAwake Local Signing"
# TEAMSAWAKE_ADHOC=1 forces ad-hoc signing, so a release build never depends on
# (or leaks the name of) whatever certificate happens to be in a keychain.
if [ "${TEAMSAWAKE_ADHOC:-0}" != "1" ] && \
   security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "==> signing with local certificate identity"
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$OUT"
  CERT_SIGNED=1
else
  echo "==> signing ad-hoc"
  codesign --force --sign - --identifier "$BUNDLE_ID" --timestamp=none "$OUT"
  CERT_SIGNED=0
fi
codesign --verify "$OUT"
echo "==> built $OUT"

if [ "${1:-}" = "--install" ]; then
  PREV_ADHOC=0
  if [ -d "/Applications/$APP_NAME.app" ]; then
    codesign -dvv "/Applications/$APP_NAME.app" 2>&1 | grep -q adhoc && PREV_ADHOC=1
  fi

  osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 1
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$OUT" "/Applications/$APP_NAME.app"

  # macOS ties an Accessibility grant to the code signature. Ad-hoc signatures
  # have no certificate, so the grant is keyed to the binary hash and dies on
  # every rebuild — leaving a row in System Settings that looks enabled but is
  # inert. Clearing it is the only way to get a real prompt back.
  if [ "$CERT_SIGNED" = "0" ] || [ "$PREV_ADHOC" = "1" ]; then
    tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
    REGRANT=1
  else
    REGRANT=0
  fi

  open "/Applications/$APP_NAME.app"
  echo "==> installed to /Applications and launched"
  if [ "$REGRANT" = "1" ]; then
    echo "==> you will need to grant Accessibility access"
  fi
fi

# Always exit 0 on success. A bare `[ ... ] && echo` as the final statement
# would make this script's exit status reflect the test, which aborts any
# caller running under `set -e`.
exit 0
