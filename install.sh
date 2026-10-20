#!/bin/bash
# TeamsAwake installer.
#
#   ./install.sh    build, install to /Applications, launch
#
# Builds from source on purpose. A locally built app is not quarantined by
# Gatekeeper, so there is no "unidentified developer" wall to click through —
# which a downloaded, un-notarised binary would hit.

set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"

APP="TeamsAwake"
BUNDLE_ID="local.teamsawake"

for a in "$@"; do
  case "$a" in
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

echo "TeamsAwake installer"
echo

# --- requirements -----------------------------------------------------------
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MAJOR" -lt 13 ]; then
  echo "error: macOS 13 (Ventura) or later is required. You have $(sw_vers -productVersion)." >&2
  exit 1
fi

if ! command -v swiftc >/dev/null; then
  echo "The Xcode Command Line Tools are required to build the app."
  echo "Run this, let it finish, then run ./install.sh again:"
  echo
  echo "  xcode-select --install"
  exit 1
fi

if [ ! -d "/Applications/Microsoft Teams.app" ]; then
  echo "note: Microsoft Teams was not found in /Applications."
  echo "      TeamsAwake will install fine and stay idle until Teams is running."
  echo
fi

# --- remove the old "start with Teams" launcher, if an earlier version added it --
# It is no longer needed: TeamsAwake stays resident and hides its own icon while
# Teams is closed. Both labels are ours: the current one and the older per-user one.
SUPPORT="$HOME/Library/Application Support/TeamsAwake"
for OLD in "$HOME/Library/LaunchAgents/$BUNDLE_ID.launcher.plist" \
           "$HOME/Library/LaunchAgents/local.$(id -un).teamsawake.launcher.plist"; do
  if [ -f "$OLD" ]; then
    launchctl unload "$OLD" 2>/dev/null || true
    rm -f "$OLD"
    echo "removed the old launcher agent (no longer needed)"
  fi
done
rm -f "$SUPPORT/launcher.sh" "$SUPPORT/teamsawake-launcher.sh"

# --- build and install -------------------------------------------------------
./scripts/build.sh --install

# --- the one manual step -----------------------------------------------------
cat <<'MSG'

------------------------------------------------------------------
One step left: grant Accessibility access.

TeamsAwake works by resetting the system idle timer, and macOS
requires explicit permission for that. Without it the app runs but
does nothing, and its menu bar icon shows a warning triangle.

  1. Quit System Settings completely if it is open (Cmd-Q).
  2. Click the TeamsAwake icon in your menu bar.
  3. Choose "Grant Accessibility access..." and approve the prompt.
  4. Click the icon again and choose "Reset idle timer now".
     It should say "Working".

Opening the settings pane for you now.
------------------------------------------------------------------
MSG

open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
echo
echo "To remove everything later: ./uninstall.sh"
