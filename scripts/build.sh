#!/bin/bash
# Builds TeamsAwake.app. Needs only the Xcode Command Line Tools.
#
#   ./scripts/build.sh                    build into ./build
#   ./scripts/build.sh --install          build, install to /Applications, launch
#   ./scripts/build.sh --install-launcher install the 30s "start with Teams" agent
#
# Most people should run ./install.sh instead, which wraps this.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="TeamsAwake"
BUNDLE_ID="local.teamsawake"
OUT="build/$APP_NAME.app"
VERSION="1.0"
SUPPORT="$HOME/Library/Application Support/TeamsAwake"
AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.launcher.plist"

command -v swiftc >/dev/null || {
  echo "error: swiftc not found. Install the Xcode Command Line Tools:" >&2
  echo "  xcode-select --install" >&2
  exit 1
}

if [ "${1:-}" = "--install-launcher" ]; then
  mkdir -p "$SUPPORT" "$(dirname "$AGENT")"
  # Run the poller from a stable private location, never from the source tree:
  # launchd executes it every 30s as you, so it must not live anywhere a git
  # checkout, clone or editor tooling could rewrite it.
  install -m 700 src/launcher.sh "$SUPPORT/launcher.sh"
  cat > "$AGENT" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$BUNDLE_ID.launcher</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$SUPPORT/launcher.sh</string></array>
  <key>StartInterval</key><integer>30</integer>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
PL
  launchctl unload "$AGENT" 2>/dev/null || true
  launchctl load "$AGENT"
  echo "Launcher installed. TeamsAwake will start within 30s of Teams opening."
  exit 0
fi

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" build

echo "==> rendering icon"
swiftc -swift-version 5 -O -framework AppKit src/makeicon.swift -o build/makeicon
(cd build && ./makeicon)
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

echo "==> compiling"
swiftc -swift-version 5 -O -target arm64-apple-macos13.0 \
  -framework AppKit -framework ServiceManagement \
  src/main.swift -o "$OUT/Contents/MacOS/$APP_NAME"

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
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
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
