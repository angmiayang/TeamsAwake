#!/bin/bash
# Removes TeamsAwake completely: app, launch agent, support files, preferences
# and the Accessibility permission entry.

set -uo pipefail

APP="TeamsAwake"
BUNDLE_ID="local.teamsawake"
SUPPORT="$HOME/Library/Application Support/TeamsAwake"
AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.launcher.plist"

echo "Removing TeamsAwake."
echo

osascript -e "tell application \"$APP\" to quit" 2>/dev/null || true
pkill -x "$APP" 2>/dev/null || true

# Launcher agents from older versions (the launcher no longer exists, but an
# earlier install may have left one behind).
for A in "$AGENT" "$HOME/Library/LaunchAgents/local.$(id -un).teamsawake.launcher.plist"; do
  if [ -f "$A" ]; then
    launchctl unload "$A" 2>/dev/null || true
    rm -f "$A"
    echo "  removed launch agent $(basename "$A")"
  fi
done

if [ -d "/Applications/$APP.app" ]; then
  rm -rf "/Applications/$APP.app"
  echo "  removed /Applications/$APP.app"
fi

# Keep the signing folder: it holds a certificate the user may have chosen to
# trust, and removing that needs their explicit action (see the note below).
if [ -d "$SUPPORT" ]; then
  rm -f "$SUPPORT/launcher.sh" "$SUPPORT/teamsawake-launcher.sh"
  rmdir "$SUPPORT" 2>/dev/null && echo "  removed $SUPPORT"
fi

for D in "$BUNDLE_ID" "local.$(id -un).teamsawake"; do
  if defaults read "$D" >/dev/null 2>&1; then
    defaults delete "$D" 2>/dev/null && echo "  removed preferences ($D)"
  fi
  tccutil reset Accessibility "$D" >/dev/null 2>&1 && echo "  cleared Accessibility entry ($D)"
done

echo
echo "Done."

if [ -d "$SUPPORT/signing" ]; then
  cat <<MSG

One thing left, only if you ran scripts/setup-signing.sh:

  A code-signing certificate named "TeamsAwake Local Signing" is still
  trusted on this Mac. To remove it:

    1. open -a "Keychain Access"
    2. Select the "System" keychain, find "TeamsAwake Local Signing",
       and delete it.
    3. rm -rf "$SUPPORT/signing"

  This script does not do it for you, because deleting from the System
  keychain requires your password and should be a deliberate choice.
MSG
fi
