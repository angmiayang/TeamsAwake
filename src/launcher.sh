#!/bin/bash
# Starts TeamsAwake when Microsoft Teams is running. Only needed if you turned
# on "Quit when Teams quits" — otherwise TeamsAwake just stays resident and
# hides its own icon, which costs less than this poller.
APP="/Applications/TeamsAwake.app"
teams_up() { pgrep -x MSTeams >/dev/null 2>&1 || pgrep -f "Microsoft Teams" >/dev/null 2>&1; }
if teams_up && ! pgrep -x TeamsAwake >/dev/null 2>&1; then
  open -g "$APP"   # -g: do not steal focus
fi
