// Pure decision logic for TeamsAwake. No AppKit, no clocks of its own — time is
// passed in, so it can be tested without waiting for real minutes to pass.

import Foundation

/// Decides whether a nudge is due, and stops nudging after a continuous run.
///
/// Our own nudge resets the system idle timer, so "idle" alone cannot tell a
/// present user from an absent one. The trick: the last input event happened at
/// `now - idle`. If that matches the moment of our last nudge, nobody has touched
/// the machine since; if it is later, a real person has.
struct NudgeGovernor {
    enum Decision { case wait, nudge, capped }

    private(set) var lastNudgeAt: Date?
    private(set) var streakStart: Date?

    /// Tolerance between the time we posted a nudge and the time implied by a
    /// later idle reading. Real input inside this window is indistinguishable.
    private let slack: TimeInterval = 3

    /// - Parameters:
    ///   - threshold: idle seconds at which to nudge.
    ///   - cap: stop once there has been no real input for this long; nil = never.
    mutating func observe(now: Date, idle: TimeInterval,
                          threshold: TimeInterval, cap: TimeInterval?) -> Decision {
        if let nudge = lastNudgeAt {
            let lastEvent = now.addingTimeInterval(-idle)
            if lastEvent.timeIntervalSince(nudge) > slack {
                // Something other than us moved the pointer: the person is back.
                lastNudgeAt = nil
                streakStart = nil
            }
        }
        guard idle >= threshold else { return .wait }
        if let cap = cap, let start = streakStart, now.timeIntervalSince(start) >= cap {
            return .capped
        }
        return .nudge
    }

    /// Call right after a nudge was actually posted.
    mutating func didNudge(at now: Date, idleBefore idle: TimeInterval) {
        // The streak began at the last REAL input, which is `idle` seconds ago.
        if streakStart == nil { streakStart = now.addingTimeInterval(-idle) }
        lastNudgeAt = now
    }
}

/// A daily window during which nudging is allowed.
enum ActiveHours {
    /// `startMinute`/`endMinute` are minutes since midnight. A window with
    /// start > end spans midnight; the weekday test then applies to the
    /// calendar day the instant falls on, which is good enough for a presence tool.
    static func contains(_ date: Date, startMinute: Int, endMinute: Int,
                         weekdaysOnly: Bool, calendar: Calendar = .current) -> Bool {
        if weekdaysOnly {
            let wd = calendar.component(.weekday, from: date)   // 1 = Sunday, 7 = Saturday
            if wd == 1 || wd == 7 { return false }
        }
        let m = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if startMinute <= endMinute { return m >= startMinute && m < endMinute }
        return m >= startMinute || m < endMinute
    }
}

/// Decides when to interrupt the user about missing Accessibility access.
///
/// A glyph change alone is easy to miss, and the failure is silent: the app keeps
/// running while Teams quietly goes Away. So warn once per "no access" episode,
/// when it matters: access is lost mid-session, or a nudge was needed but blocked.
/// Opening the app untrusted, with nothing to nudge, stays quiet so a fresh
/// install is not nagged before the user has had a chance to grant access.
struct TrustWatcher {
    enum Alert { case lost, blocked }

    private var wasTrusted: Bool?     // nil until the first observation
    private var alerted = false       // already warned during this episode

    mutating func observe(trusted: Bool, nudgeNeeded: Bool) -> Alert? {
        defer { wasTrusted = trusted }
        if trusted { alerted = false; return nil }       // episode over; re-arm
        guard !alerted else { return nil }
        if wasTrusted == true { alerted = true; return .lost }
        if nudgeNeeded { alerted = true; return .blocked }
        return nil
    }
}

/// Recognises Microsoft Teams among running applications.
enum TeamsMatch {
    /// New Teams, then classic Teams. Matched exactly: Teams runs helper
    /// processes under related IDs (notification center, WebView, module host)
    /// that must not count as "Teams is open".
    static let nativeBundleIDs: Set<String> = ["com.microsoft.teams2", "com.microsoft.teams"]

    /// - Parameter isRegularApp: true for an ordinary Dock app. Required for the
    ///   name match, because Teams' helpers are also named "Microsoft Teams ..."
    ///   but run as accessory or background-only processes and can outlive Teams.
    static func isTeams(bundleID: String?, name: String?, isRegularApp: Bool) -> Bool {
        if let b = bundleID, nativeBundleIDs.contains(b) { return true }
        // Teams installed as a web app (Chrome or Edge PWA, Safari "Add to Dock")
        // is its own Dock app with a browser-generated bundle ID, named for the site.
        guard isRegularApp, let n = name else { return false }
        return n.lowercased().hasPrefix("microsoft teams")
    }
}

/// When the menu-bar icon should be visible.
enum IconVisibility {
    /// Hide only when the app is idle *because* Teams is absent. If the user has
    /// turned "Only while Teams is running" off (e.g. they use Teams in a browser
    /// tab, which cannot be detected), the app keeps working, so its icon stays.
    static func shouldShow(trusted: Bool, revealed: Bool, followTeams: Bool,
                           requireTeams: Bool, teamsRunning: Bool) -> Bool {
        if !trusted || revealed { return true }   // never lock the user out of setup
        return !(followTeams && requireTeams && !teamsRunning)
    }
}
