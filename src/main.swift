// TeamsAwake — a menu-bar app that stops Microsoft Teams from flipping to "Away".
//
// It never sets your Teams status. It only keeps macOS from reporting you idle,
// so Teams' own logic decides what to show: Available stays Available, a manual
// Busy stays Busy, and calls still show "In a call".

import AppKit
import ServiceManagement

// MARK: - Idle / system probes

enum System {
    /// Seconds since the last real keyboard/mouse/trackpad event — the same
    /// clock Teams reads to decide you are inactive.
    ///
    /// Note: kCGAnyInputEventType (0xFFFFFFFF) collides with the raw value of
    /// .tapDisabledByUserInput, so that case *is* the "any input" constant here.
    static var idleSeconds: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                eventType: .tapDisabledByUserInput)
    }

    static var screenIsLocked: Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (d["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    static var teamsIsRunning: Bool {
        let ids: Set<String> = ["com.microsoft.teams2", "com.microsoft.teams"]
        return NSWorkspace.shared.runningApplications.contains {
            guard let b = $0.bundleIdentifier else { return false }
            return ids.contains(b)
        }
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Post a mouse-moved event at the cursor's current position: resets the
    /// idle timer, moves the pointer zero pixels. Needs Accessibility access.
    @discardableResult
    static func resetIdleTimer() -> Bool {
        guard let probe = CGEvent(source: nil) else { return false }
        guard let move = CGEvent(mouseEventSource: nil,
                                 mouseType: .mouseMoved,
                                 mouseCursorPosition: probe.location,
                                 mouseButton: .left) else { return false }
        move.post(tap: .cghidEventTap)
        return true
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Preferences

enum Prefs {
    private static let d = UserDefaults.standard
    private static let defaults: [String: Any] = [
        "enabled": true, "thresholdSeconds": 170.0,
        "respectLock": true, "requireTeams": true,
        "iconPointSize": 17.0,
        "followTeams": true, "quitWithTeams": false,
    ]
    static func registerDefaults() { d.register(defaults: defaults) }

    static var enabled: Bool {
        get { d.bool(forKey: "enabled") } set { d.set(newValue, forKey: "enabled") } }
    static var thresholdSeconds: Double {
        get { d.double(forKey: "thresholdSeconds") } set { d.set(newValue, forKey: "thresholdSeconds") } }
    static var respectLock: Bool {
        get { d.bool(forKey: "respectLock") } set { d.set(newValue, forKey: "respectLock") } }
    static var requireTeams: Bool {
        get { d.bool(forKey: "requireTeams") } set { d.set(newValue, forKey: "requireTeams") } }
    static var followTeams: Bool {
        get { d.bool(forKey: "followTeams") } set { d.set(newValue, forKey: "followTeams") } }
    static var quitWithTeams: Bool {
        get { d.bool(forKey: "quitWithTeams") } set { d.set(newValue, forKey: "quitWithTeams") } }

    /// Menu-bar glyph size in points. macOS default for status items is ~15.
    static var iconPointSize: Double {
        get { d.double(forKey: "iconPointSize") } set { d.set(newValue, forKey: "iconPointSize") } }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var timer: Timer?
    private var lastAction = "not run yet"
    private var revealUntil: Date?
    private var nudgeCount = 0

    private let pollInterval: TimeInterval = 20

    func applicationDidFinishLaunching(_ n: Notification) {
        Prefs.registerDefaults()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()

        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer?.tolerance = 5

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(appLaunched(_:)),
                       name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appTerminated(_:)),
                       name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        tick()
    }

    // MARK: core loop

    private func tick() {
        // Re-evaluate the icon on EVERY exit path. Trust can be granted or
        // revoked while running, and the early returns below must not strand
        // a stale glyph in the menu bar.
        defer { refreshIcon(); updateVisibility() }

        guard Prefs.enabled else { lastAction = "paused"; return }
        if Prefs.respectLock && System.screenIsLocked { lastAction = "idle — screen locked"; return }
        if Prefs.requireTeams && !System.teamsIsRunning { lastAction = "idle — Teams not running"; return }

        let idle = System.idleSeconds
        guard idle >= Prefs.thresholdSeconds else {
            lastAction = String(format: "watching (idle %.0fs)", idle); return
        }
        if System.resetIdleTimer() && System.hasAccessibility {
            nudgeCount += 1
            lastAction = "reset idle timer at " + Self.clock.string(from: Date())
        } else {
            lastAction = "BLOCKED — needs Accessibility access"
        }
    }

    // MARK: following Teams

    private func isTeams(_ n: Notification) -> Bool {
        guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bid = app.bundleIdentifier else { return false }
        return bid == "com.microsoft.teams2" || bid == "com.microsoft.teams"
    }

    @objc private func appLaunched(_ n: Notification) {
        guard isTeams(n) else { return }
        tick()
    }

    @objc private func appTerminated(_ n: Notification) {
        guard isTeams(n) else { return }
        if Prefs.quitWithTeams { NSApp.terminate(nil); return }
        tick()
    }

    /// Hide the glyph while Teams is closed, but never hide it when setup is
    /// still incomplete or the user has just reopened the app to reach settings.
    private func updateVisibility() {
        if !System.hasAccessibility { statusItem.isVisible = true; return }
        if let until = revealUntil, until > Date() { statusItem.isVisible = true; return }
        statusItem.isVisible = Prefs.followTeams ? System.teamsIsRunning : true
    }

    /// Reopening the app from Finder reveals a hidden icon for a minute.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        revealUntil = Date().addingTimeInterval(60)
        updateVisibility()
        return true
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        let ok = System.hasAccessibility
        let name = !ok ? "exclamationmark.triangle"
                 : Prefs.enabled ? "bolt.circle.fill" : "bolt.slash.circle"
        let label = !ok ? "TeamsAwake — Accessibility access required"
                  : Prefs.enabled ? "TeamsAwake — keeping you Available" : "TeamsAwake — paused"
        let cfg = NSImage.SymbolConfiguration(pointSize: Prefs.iconPointSize, weight: .regular)
        let img = NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(cfg)
        img?.isTemplate = true
        button.image = img
        button.toolTip = label
    }

    // MARK: menu

    func menuWillOpen(_ menu: NSMenu) { refreshIcon(); rebuildMenu() }

    private func rebuildMenu() {
        menu.removeAllItems()

        if !System.hasAccessibility {
            let warn = NSMenuItem(title: "⚠  Grant Accessibility access…",
                                  action: #selector(grantAccess), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
            menu.addItem(info("Required — macOS blocks synthetic input without it."))
            menu.addItem(.separator())
        }

        menu.addItem(toggleRow())

        menu.addItem(.separator())
        menu.addItem(info(String(format: "Idle now: %.0fs", System.idleSeconds)))
        menu.addItem(info("Status: \(lastAction)"))
        menu.addItem(info("Resets this session: \(nudgeCount)"))
        menu.addItem(info("Teams: \(System.teamsIsRunning ? "running" : "not running")"))

        menu.addItem(.separator())

        // Threshold
        let threshItem = NSMenuItem(title: "Go active after", action: nil, keyEquivalent: "")
        let threshMenu = NSMenu()
        for (label, secs) in [("2 minutes", 110.0), ("3 minutes", 170.0), ("4 minutes", 230.0)] {
            let it = NSMenuItem(title: label, action: #selector(setThreshold(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = secs
            it.state = abs(Prefs.thresholdSeconds - secs) < 1 ? .on : .off
            threshMenu.addItem(it)
        }
        threshMenu.addItem(.separator())
        threshMenu.addItem(info("Teams flips to Away at ~5 minutes."))
        threshItem.submenu = threshMenu
        menu.addItem(threshItem)

        let lock = NSMenuItem(title: "Pause while screen is locked",
                              action: #selector(toggleRespectLock), keyEquivalent: "")
        lock.target = self; lock.state = Prefs.respectLock ? .on : .off
        menu.addItem(lock)

        let needTeams = NSMenuItem(title: "Only while Teams is running",
                                   action: #selector(toggleRequireTeams), keyEquivalent: "")
        needTeams.target = self; needTeams.state = Prefs.requireTeams ? .on : .off
        menu.addItem(needTeams)

        let sizeItem = NSMenuItem(title: "Icon size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for (label, pt) in [("Standard", 15.0), ("Larger", 17.0), ("Largest", 19.0)] {
            let it = NSMenuItem(title: label, action: #selector(setIconSize(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = pt
            it.state = abs(Prefs.iconPointSize - pt) < 0.5 ? .on : .off
            sizeMenu.addItem(it)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let follow = NSMenuItem(title: "Hide icon when Teams is closed",
                                action: #selector(toggleFollowTeams), keyEquivalent: "")
        follow.target = self; follow.state = Prefs.followTeams ? .on : .off
        menu.addItem(follow)

        let quitWith = NSMenuItem(title: "Quit when Teams quits",
                                  action: #selector(toggleQuitWithTeams), keyEquivalent: "")
        quitWith.target = self; quitWith.state = Prefs.quitWithTeams ? .on : .off
        menu.addItem(quitWith)

        let login = NSMenuItem(title: "Open at login",
                               action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let now = NSMenuItem(title: "Reset idle timer now",
                             action: #selector(nudgeNow), keyEquivalent: "")
        now.target = self
        menu.addItem(now)

        let quit = NSMenuItem(title: "Quit TeamsAwake",
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    /// A real on/off switch at the top of the menu.
    private func toggleRow() -> NSMenuItem {
        let item = NSMenuItem()
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 34))

        let label = NSTextField(labelWithString: "Keep me Available")
        label.font = NSFont.menuFont(ofSize: 14)
        label.frame = NSRect(x: 14, y: 8, width: 170, height: 18)

        let sw = NSSwitch(frame: NSRect(x: 200, y: 6, width: 40, height: 22))
        sw.state = Prefs.enabled ? .on : .off
        sw.target = self
        sw.action = #selector(switchFlipped(_:))

        row.addSubview(label)
        row.addSubview(sw)
        item.view = row
        return item
    }

    @objc private func switchFlipped(_ sender: NSSwitch) {
        Prefs.enabled = (sender.state == .on)
        refreshIcon()
        tick()
        menu.cancelTracking()
    }

    private func info(_ s: String) -> NSMenuItem {
        let i = NSMenuItem(title: s, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    // MARK: actions

    @objc private func toggleEnabled() {
        Prefs.enabled.toggle(); refreshIcon(); tick()
    }
    @objc private func toggleRespectLock()  { Prefs.respectLock.toggle() }
    @objc private func toggleFollowTeams()  { Prefs.followTeams.toggle(); tick() }

    @objc private func toggleQuitWithTeams() {
        Prefs.quitWithTeams.toggle()
        guard Prefs.quitWithTeams else { return }
        let a = NSAlert()
        a.messageText = "TeamsAwake will now quit with Teams"
        a.informativeText = "Nothing will start it again on its own. To have it come back when Teams opens, install the companion launcher:\n\n./install.sh --with-launcher"
        a.addButton(withTitle: "OK")
        a.runModal()
    }
    @objc private func toggleRequireTeams() { Prefs.requireTeams.toggle() }

    @objc private func setThreshold(_ sender: NSMenuItem) {
        if let s = sender.representedObject as? Double { Prefs.thresholdSeconds = s }
    }

    @objc private func setIconSize(_ sender: NSMenuItem) {
        if let pt = sender.representedObject as? Double {
            Prefs.iconPointSize = pt
            refreshIcon()
        }
    }

    @objc private func grantAccess() {
        // Triggers the system prompt, then opens the settings pane.
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        System.openAccessibilitySettings()
    }

    @objc private func nudgeNow() {
        let before = System.idleSeconds
        System.resetIdleTimer()
        let after = System.idleSeconds
        let a = NSAlert()
        if after < before || before < 2 {
            a.messageText = "Working"
            a.informativeText = String(format: "Idle went from %.0fs to %.0fs. Teams will not see you as idle.", before, after)
        } else {
            a.messageText = "Not working"
            a.informativeText = "The idle timer did not reset. Grant TeamsAwake Accessibility access in System Settings → Privacy & Security → Accessibility."
            a.alertStyle = .warning
        }
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert()
            a.messageText = "Could not change the login item"
            a.informativeText = "\(error.localizedDescription)\n\nThis usually works only once the app is in /Applications."
            a.runModal()
        }
    }
}

// MARK: - main

Prefs.registerDefaults()
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
