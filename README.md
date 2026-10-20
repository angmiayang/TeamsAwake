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

Requires macOS 13 or later (Apple Silicon or Intel) and the Xcode Command Line Tools
(`xcode-select --install` if you do not have them).

```bash
git clone https://github.com/angmiayang/TeamsAwake.git
cd TeamsAwake
./install.sh
```

TeamsAwake stays running and hides its menu-bar icon while Teams is closed, so
there is nothing to start when Teams opens. To have it running after a restart,
turn on **Open at login** in its menu.

The installer builds from source deliberately. A locally built app is not
quarantined by Gatekeeper, so you never see an "unidentified developer" wall —
which a downloaded, un-notarised binary would hit on every Mac.

### The one manual step

macOS requires explicit permission to reset the idle timer, so after installing:

1. Quit System Settings completely if it is open (Cmd-Q).
2. Click the TeamsAwake icon in your menu bar.
3. Choose **Grant Accessibility access…** and approve the prompt.
4. Click the icon again and choose **Reset idle timer now**. "Working" means
   Accessibility access is granted and a test event was posted; "Not working"
   means it is not granted yet.

Until you do this the app runs but does nothing, and shows a warning triangle.

TeamsAwake also warns you with an alert, once per episode, if access is lost
while it is running (for example after an update), or if you are idle long
enough to need a nudge and access is missing. Freshly installed and not yet
granted, with nothing to nudge, it stays quiet until then.

### Without the Xcode tools: install a release

If you would rather not install the Command Line Tools (a large download), take
the prebuilt app from the [Releases page](https://github.com/angmiayang/TeamsAwake/releases).
It is a universal build, so it runs on Apple Silicon and Intel.

1. Download `TeamsAwake-vX.Y.Z.zip` and its `.sha256` file into one folder, then
   check the download: `shasum -a 256 -c TeamsAwake-vX.Y.Z.zip.sha256`
2. Unzip it and move `TeamsAwake.app` to `/Applications`.
3. Open it. macOS will block the first launch, because the app is not notarised
   (that requires a paid Apple Developer account). Either open System Settings →
   Privacy & Security and choose **Open Anyway**, or run:
   `xattr -dr com.apple.quarantine /Applications/TeamsAwake.app`
4. Then follow "The one manual step" above.

Trade-offs, so you can choose knowingly:

- You are running a binary from the internet. The checksum proves the file was not
  corrupted in transit; it does not prove what the code does. Building from source
  lets you read it first, and the code is short.
- The release is signed ad-hoc, and macOS ties an Accessibility grant to the exact
  signature. **Every update therefore needs the permission granted again.** After
  replacing the app, run `tccutil reset Accessibility local.teamsawake`, then
  grant access from the menu. Otherwise System Settings keeps showing an enabled
  row that does nothing.

## The menu

| Control | Does |
|---|---|
| **Keep me Available** | Master on/off switch |
| Idle now / Status / Resets | Live diagnostics |
| **Pause…** | 30 min, 1 h, 2 h, or until 06:00 tomorrow. Resumes by itself; **Resume now** appears while paused. |
| **Go active after** | 2, 3 or 4 minutes. Teams usually goes Away after about 5. The nudge fires at exactly this idle time. |
| **Limits & schedule → Stop after no input for** | Never, 30 min, 1 h, 2 h or 4 h (default 1 h). See below. |
| **Limits & schedule → Active hours** | Always (default), or a weekday or daily window. |
| **Pause while screen is locked** | On by default, so locking your Mac still shows Away |
| **Only while Teams app is running** | On by default. Turn it off if you use Teams in a browser tab. See below. |
| **Hide icon when Teams is closed** | Icon appears and disappears with Teams |
| **Icon size** | 15, 17 or 19pt |
| **Open at login** | Registers a login item |
| **Reset idle timer now** | One-shot test with a pass/fail alert |

Icon: filled bolt = active, slashed bolt = paused, warning triangle = needs
Accessibility access.

If the icon is hidden and you need the menu, reopen TeamsAwake from
`/Applications`; that reveals it for 60 seconds. The icon is never hidden while
Accessibility access is missing, so you cannot lock yourself out.

## Teams in a browser

TeamsAwake detects the Teams desktop app, and also Teams installed as a web app
(a Chrome or Edge app, or Safari's "Add to Dock"), because those run as their own
Dock app named "Microsoft Teams". Teams helper processes are ignored.

A plain browser tab cannot be detected without reading your tab titles, which
needs Automation permission and which TeamsAwake deliberately does not ask for.
If you use Teams that way, turn **Only while Teams app is running** off. The icon
then stays visible and nudging no longer depends on Teams being detected. Pair it
with **Active hours** so it is not running all evening.

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

Because the nudge counts as activity, your display will not sleep, the screen
saver will not start, and a "require password after screen saver" setting will
never trigger while TeamsAwake is nudging. Two settings bound that:

- **Stop after no input for** (default 1 hour): once nobody has touched the Mac
  for that long, TeamsAwake stops nudging and your Mac idles, sleeps and locks
  normally. Real input resets it. It detects real input by comparing the last
  input time with the moment of its own last nudge.
- **Active hours**: outside the window it does nothing, so evenings and
  weekends behave as if it were not installed.

Custom active hours, in minutes since midnight (here 07:00 to 19:00, weekdays):

```bash
defaults write local.teamsawake activeHoursEnabled -bool true
defaults write local.teamsawake activeStart -int 420
defaults write local.teamsawake activeEnd -int 1140
defaults write local.teamsawake activeWeekdaysOnly -bool true
```

On battery, lower the brightness or pause it when you do not need it.

## Uninstall

```bash
./uninstall.sh
```

Removes the app, any old launch agent, support files, preferences and the
Accessibility entry. If you ran the optional signing script, it tells you how
to remove that certificate too.

Installed from a release and have no repo? Quit TeamsAwake, delete
`/Applications/TeamsAwake.app`, then run:

```bash
tccutil reset Accessibility local.teamsawake
defaults delete local.teamsawake
```

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

`./scripts/build.sh` builds a universal binary into `./build` without installing.
`./scripts/test.sh` runs the unit tests for the decision logic.

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

### Publishing a release

Pushing a version tag builds and publishes it, via `.github/workflows/release.yml`:

```bash
git tag v1.2.0 && git push origin v1.2.0
```

The workflow runs the tests, builds a universal ad-hoc-signed app (version taken
from the tag), refuses to publish unless both architectures are present, and
attaches a zip and a SHA-256 file to a new release. It uses only
`actions/checkout`, pinned to a commit, and the preinstalled `gh`.

## License

MIT — see [LICENSE](LICENSE).
