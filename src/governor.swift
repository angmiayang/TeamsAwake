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
