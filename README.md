# TeamsAwake

A macOS menu-bar app that stops Microsoft Teams from setting you to **Away**
when you step away from the keyboard — without touching your status.

Teams decides you are inactive from the macOS idle timer, and flips you to Away
after about five minutes. There is no setting to turn that off. TeamsAwake does
not set your status; it keeps the system from reporting you as idle, so Teams'
own logic stays in charge:

| Situation | What Teams shows |
|---|---|
| Working, nothing set | Available |
| You set Busy or Do Not Disturb | Busy / DND, untouched |
| Calendar meeting | In a meeting |
| On a call | In a call |

Because it never calls a presence API, it cannot overwrite Busy or a call.

## Install

Requires macOS 13 or later and the Xcode Command Line Tools
(`xcode-select --install` if you do not have them).

```bash
git clone https://github.com/angmiayang/TeamsAwake.git
cd TeamsAwake
./install.sh
```

Add `--with-launcher` if you want TeamsAwake to start automatically whenever
Teams opens and quit when Teams quits.

The installer builds from source deliberately. A locally built app is not
quarantined by Gatekeeper, so you never see an "unidentified developer" wall —
which a downloaded, un-notarised binary would hit on every Mac.

### The one manual step

macOS requires explicit permission to reset the idle timer, so after installing:

1. Quit System Settings completely if it is open (Cmd-Q).
2. Click the TeamsAwake icon in your menu bar.
3. Choose **Grant Accessibility access…** and approve the prompt.
4. Click the icon again, choose **Reset idle timer now**, and confirm it says
   "Working".

Until you do this the app runs but does nothing, and shows a warning triangle.

## The menu

| Control | Does |
|---|---|
| **Keep me Available** | Master on/off switch |
| Idle now / Status / Resets | Live diagnostics |
| **Go active after** | 2, 3 or 4 minutes. Teams flips to Away at about 5. |
| **Pause while screen is locked** | On by default, so locking your Mac still shows Away |
| **Only while Teams is running** | On by default |
| **Hide icon when Teams is closed** | Icon appears and disappears with Teams |
| **Quit when Teams quits** | Off by default; needs `--with-launcher` to come back |
| **Icon size** | 15, 17 or 19pt |
| **Open at login** | Registers a login item |
| **Reset idle timer now** | One-shot test with a pass/fail alert |

Icon: filled bolt = active, slashed bolt = paused, warning triangle = needs
Accessibility access.

If the icon is hidden and you need the menu, reopen TeamsAwake from
`/Applications`; that reveals it for 60 seconds. The icon is never hidden while
Accessibility access is missing, so you cannot lock yourself out.

## How it works

Teams is an Electron app, and reads inactivity from
`CGEventSourceSecondsSinceLastEventType`, the seconds since the last real
keyboard or mouse event. Once per 20 seconds TeamsAwake checks that value, and
if it exceeds your threshold it posts a single mouse-moved event at the
cursor's current position — resetting the timer while moving the pointer zero
pixels.

`caffeinate` does not work for this. It asserts `UserIsActive` and prevents
display sleep, but does not reset the idle timer, which is the value Teams
actually reads.

Your display will not sleep while this is running, because the nudge counts as
activity. On battery, lower the brightness or turn the switch off when you do
not need it.

## Uninstall

```bash
./uninstall.sh
```

Removes the app, the launch agent, support files, preferences and the
Accessibility entry. If you ran the optional signing script, it tells you how
to remove that certificate too.

## Caveats

- **Screen lock still wins.** Locking your Mac or closing the lid sets Away
  regardless. That is deliberate.
- If your employer's acceptable-use policy treats presence as an activity
  signal, this changes that signal. Worth a thought before installing it
  permanently.
- Not affiliated with or endorsed by Microsoft.

## Extras

`extras/keep-teams-online.sh` is the same idea as a shell script plus a launchd
agent, with no GUI. Useful headless or over SSH. It needs `cliclick`
(`brew install cliclick`); the app does not.

## Working on the code

`./scripts/build.sh` builds into `./build` without installing.

Each rebuild re-signs the app, and macOS ties an Accessibility grant to the
code signature, so you will be asked to grant permission again every time.
`scripts/setup-signing.sh` fixes that by creating a local code-signing
certificate, which makes the grant survive rebuilds.

**Read that script before running it.** It adds a self-signed certificate to
your System keychain as a trusted root, scoped to code signing only, which
means any binary signed with that key is treated as validly signed on your
machine. The private key is deleted from disk after import and kept only in
your keychain. If you would rather not touch your trust store, skip it and
accept one grant per rebuild. `build.sh` detects the identity automatically and
falls back to ad-hoc signing when it is absent.
