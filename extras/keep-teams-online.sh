#!/bin/bash
# keep-teams-online.sh — stop Microsoft Teams (macOS) from flipping to "Away".
#
# It does NOT set your Teams status. It only prevents macOS from reporting
# you as idle, so Teams' own logic decides: Available stays Available,
# Busy stays Busy, a call still shows "In a call" / "In a meeting".
#
# Usage:
#   ./keep-teams-online.sh status      # diagnostics, changes nothing
#   ./keep-teams-online.sh test        # prove the nudge resets the idle timer
#   ./keep-teams-online.sh once        # single check (what launchd runs)
#   ./keep-teams-online.sh watch       # foreground loop, Ctrl-C to stop
#   ./keep-teams-online.sh install     # load launchd agent (runs at login)
#   ./keep-teams-online.sh uninstall   # unload launchd agent

set -uo pipefail

# ---------------- settings ----------------
IDLE_THRESHOLD=170     # nudge once idle exceeds this many seconds (Teams: Away at ~300s)
POLL_INTERVAL=60       # seconds between checks in watch/launchd mode
RESPECT_LOCK=1         # 1 = do nothing while the screen is locked
REQUIRE_TEAMS=1        # 1 = do nothing unless Teams is running
LOG="$HOME/Library/Logs/keep-teams-online.log"
# ------------------------------------------

LABEL="com.$(id -un).keepteamsonline"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

# Seconds since the last real HID (keyboard/mouse/trackpad) event.
# This is the same clock Electron's powerMonitor.getSystemIdleTime() reads,
# which is what Teams uses to decide you are inactive.
idle_seconds() {
  ioreg -c IOHIDSystem 2>/dev/null \
    | awk '/HIDIdleTime/ {printf "%d", $NF/1000000000; exit}'
}

screen_locked() {
  ioreg -n Root -d1 -w0 -a 2>/dev/null | plutil -p - 2>/dev/null \
    | grep -q '"IOConsoleLocked" => true'
}

teams_running() {
  pgrep -x MSTeams >/dev/null 2>&1 || pgrep -f "Microsoft Teams" >/dev/null 2>&1
}

# Emit one tiny input event. Needs Accessibility permission (see README).
nudge() {
  if command -v cliclick >/dev/null 2>&1; then
    cliclick -r m:+1,+0 w:20 m:-1,+0 >/dev/null 2>&1
    return $?
  fi
  if python3 -c 'import Quartz' >/dev/null 2>&1; then
    python3 - <<'PY' >/dev/null 2>&1
import Quartz
# Post a mouse-moved event at the cursor's current position: resets the
# idle timer, moves the pointer zero pixels.
loc = Quartz.CGEventGetLocation(Quartz.CGEventCreate(None))
ev  = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, loc, 0)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev)
PY
    return $?
  fi
  return 127
}

backend_name() {
  if command -v cliclick >/dev/null 2>&1; then echo "cliclick ($(command -v cliclick))"
  elif python3 -c 'import Quartz' >/dev/null 2>&1; then echo "python3 + Quartz"
  else echo "NONE — install one (see README)"; fi
}

check_once() {
  local idle; idle=$(idle_seconds)
  [[ -z "$idle" ]] && { log "cannot read HIDIdleTime"; return 1; }

  if (( RESPECT_LOCK )) && screen_locked; then
    log "idle=${idle}s  skip: screen locked"; return 0
  fi
  if (( REQUIRE_TEAMS )) && ! teams_running; then
    log "idle=${idle}s  skip: Teams not running"; return 0
  fi
  if (( idle < IDLE_THRESHOLD )); then
    log "idle=${idle}s  ok (< ${IDLE_THRESHOLD}s)"; return 0
  fi

  if nudge; then
    log "idle=${idle}s  nudged -> $(idle_seconds)s"
  else
    log "idle=${idle}s  NUDGE FAILED (backend missing or Accessibility not granted)"
    return 1
  fi
}

case "${1:-status}" in
  status)
    echo "idle           : $(idle_seconds)s  (nudge threshold ${IDLE_THRESHOLD}s)"
    echo "screen locked  : $(screen_locked && echo yes || echo no)"
    echo "Teams running  : $(teams_running && echo yes || echo no)"
    echo "nudge backend  : $(backend_name)"
    echo "launchd agent  : $(launchctl list 2>/dev/null | grep -q "$LABEL" && echo loaded || echo not loaded)"
    echo "log file       : $LOG"
    ;;
  test)
    before=$(idle_seconds)
    echo "idle before nudge : ${before}s"
    if nudge; then
      after=$(idle_seconds)
      echo "idle after nudge  : ${after}s"
      if (( after <= before )); then
        echo "RESULT: working — the idle timer was reset."
      else
        echo "RESULT: nudge ran but idle did not reset. Grant Accessibility permission."
      fi
    else
      echo "RESULT: no working backend. Run: brew install cliclick"
    fi
    ;;
  once)  check_once ;;
  watch)
    echo "Watching (threshold ${IDLE_THRESHOLD}s, poll ${POLL_INTERVAL}s). Ctrl-C to stop."
    echo "Logging to $LOG"
    trap 'echo; echo "stopped."; exit 0' INT TERM
    while true; do check_once; sleep "$POLL_INTERVAL"; done
    ;;
  install)
    mkdir -p "$HOME/Library/LaunchAgents"
    cat >"$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$SELF</string><string>once</string></array>
  <key>StartInterval</key><integer>$POLL_INTERVAL</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PL
    launchctl unload "$PLIST" 2>/dev/null
    launchctl load "$PLIST" && echo "installed: $PLIST" && echo "runs every ${POLL_INTERVAL}s, and at every login."
    ;;
  uninstall)
    launchctl unload "$PLIST" 2>/dev/null
    rm -f "$PLIST" && echo "uninstalled."
    ;;
  *)
    echo "usage: $0 {status|test|once|watch|install|uninstall}" >&2; exit 2 ;;
esac
