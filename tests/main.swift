import Foundation

var failures = 0
func check(_ cond: Bool, _ name: String) {
    print(cond ? "  PASS  \(name)" : "  FAIL  \(name)")
    if !cond { failures += 1 }
}

let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
let thr = 170.0, cap = 3600.0

print("== NudgeGovernor ==")
do {
    var g = NudgeGovernor()
    check(g.observe(now: at(0), idle: 100, threshold: thr, cap: cap) == .wait, "below threshold waits")
    check(g.observe(now: at(0), idle: 170, threshold: thr, cap: cap) == .nudge, "at threshold nudges")
}
do {
    // User walks away at t=0 (last real input), we nudge every 170s thereafter.
    var g = NudgeGovernor()
    var now = 170.0
    var nudges = 0
    var cappedAt: TimeInterval?
    var idle = 170.0                      // idle at the first tick that crosses threshold
    while now < 6000 {
        let d = g.observe(now: at(now), idle: idle, threshold: thr, cap: cap)
        if d == .nudge { g.didNudge(at: at(now), idleBefore: idle); nudges += 1; idle = 170 }
        if d == .capped { cappedAt = now; break }
        now += 170                        // next tick one threshold later; idle since our nudge = 170
        if d == .nudge { idle = 170 } else { idle += 170 }
    }
    check(cappedAt != nil, "absent user: governor eventually caps")
    check((cappedAt ?? 0) >= 3600 && (cappedAt ?? 0) <= 3600 + 170, "cap lands ~60 min after last real input (got \(Int(cappedAt ?? -1))s)")
    check(nudges >= 18 && nudges <= 22, "roughly one nudge per threshold before capping (got \(nudges))")
}
do {
    // Once capped, it stays capped while nobody touches the machine.
    var g = NudgeGovernor()
    g.didNudge(at: at(0), idleBefore: 170)           // streak starts at t=-170
    let a = g.observe(now: at(5000), idle: 5000, threshold: thr, cap: cap)
    let b = g.observe(now: at(5100), idle: 5100, threshold: thr, cap: cap)
    check(a == .capped && b == .capped, "stays capped with no input")
}
do {
    // Real input after capping resets the streak and nudging resumes.
    var g = NudgeGovernor()
    g.didNudge(at: at(0), idleBefore: 170)
    _ = g.observe(now: at(5000), idle: 5000, threshold: thr, cap: cap)       // capped
    // person types at t=5050; by t=5100 idle is 50
    check(g.observe(now: at(5100), idle: 50, threshold: thr, cap: cap) == .wait, "real input after cap: waits")
    check(g.streakStart == nil && g.lastNudgeAt == nil, "real input clears the streak")
    check(g.observe(now: at(5300), idle: 250, threshold: thr, cap: cap) == .nudge, "then nudges again once idle")
}
do {
    // Input shortly after our nudge, within slack, is not mistaken for a person.
    var g = NudgeGovernor()
    g.didNudge(at: at(0), idleBefore: 170)
    _ = g.observe(now: at(0.5), idle: 0.5, threshold: thr, cap: cap)
    check(g.streakStart != nil, "idle ~0 right after our own nudge keeps the streak")
}
do {
    // Real input between two nudges (not just near the cap) resets the streak.
    var g = NudgeGovernor()
    g.didNudge(at: at(0), idleBefore: 170)
    _ = g.observe(now: at(100), idle: 40, threshold: thr, cap: cap)          // typed at t=60
    check(g.streakStart == nil, "typing between nudges clears the streak")
}
do {
    var g = NudgeGovernor()
    g.didNudge(at: at(0), idleBefore: 170)
    check(g.observe(now: at(999_999), idle: 999_999, threshold: thr, cap: nil) == .nudge, "cap = nil never caps")
}

print("== ActiveHours ==")
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}
// 2026-10-19 is a Monday, 2026-10-24 a Saturday, 2026-10-25 a Sunday.
let s = 8*60+30, e = 18*60
check(ActiveHours.contains(date(2026,10,19,9,0),  startMinute: s, endMinute: e, weekdaysOnly: true, calendar: cal), "Mon 09:00 inside")
check(ActiveHours.contains(date(2026,10,19,8,30), startMinute: s, endMinute: e, weekdaysOnly: true, calendar: cal), "Mon 08:30 start is inclusive")
check(!ActiveHours.contains(date(2026,10,19,8,29), startMinute: s, endMinute: e, weekdaysOnly: true, calendar: cal), "Mon 08:29 outside")
check(!ActiveHours.contains(date(2026,10,19,18,0), startMinute: s, endMinute: e, weekdaysOnly: true, calendar: cal), "Mon 18:00 end is exclusive")
check(!ActiveHours.contains(date(2026,10,24,12,0), startMinute: s, endMinute: e, weekdaysOnly: true, calendar: cal), "Saturday excluded (weekdays only)")
check(!ActiveHours.contains(date(2026,10,25,12,0), startMinute: s, endMinute: e, weekdaysOnly: true, calendar: cal), "Sunday excluded (weekdays only)")
check(ActiveHours.contains(date(2026,10,24,12,0), startMinute: s, endMinute: e, weekdaysOnly: false, calendar: cal), "Saturday included when every day")
check(ActiveHours.contains(date(2026,10,19,23,0), startMinute: 22*60, endMinute: 6*60, weekdaysOnly: false, calendar: cal), "overnight window: 23:00 inside")
check(ActiveHours.contains(date(2026,10,20,5,0),  startMinute: 22*60, endMinute: 6*60, weekdaysOnly: false, calendar: cal), "overnight window: 05:00 inside")
check(!ActiveHours.contains(date(2026,10,20,12,0), startMinute: 22*60, endMinute: 6*60, weekdaysOnly: false, calendar: cal), "overnight window: noon outside")

print("== TrustWatcher ==")
do {
    var w = TrustWatcher()
    check(w.observe(trusted: true, nudgeNeeded: false) == nil, "trusted: silent")
    check(w.observe(trusted: false, nudgeNeeded: false) == .lost, "trust lost mid-session: alerts")
    check(w.observe(trusted: false, nudgeNeeded: false) == nil, "...only once")
    check(w.observe(trusted: false, nudgeNeeded: true) == nil, "...even when a nudge is then blocked")
    check(w.observe(trusted: true, nudgeNeeded: false) == nil, "regained: silent")
    check(w.observe(trusted: false, nudgeNeeded: false) == .lost, "lost again after regaining: alerts again")
}
do {
    var w = TrustWatcher()
    check(w.observe(trusted: false, nudgeNeeded: false) == nil, "launched untrusted, nothing to nudge: quiet")
    check(w.observe(trusted: false, nudgeNeeded: false) == nil, "...still quiet")
    check(w.observe(trusted: false, nudgeNeeded: true) == .blocked, "launched untrusted, nudge blocked: alerts")
    check(w.observe(trusted: false, nudgeNeeded: true) == nil, "...only once")
}
do {
    var w = TrustWatcher()
    _ = w.observe(trusted: true, nudgeNeeded: false)
    check(w.observe(trusted: false, nudgeNeeded: true) == .lost, "loss and blocked nudge in one tick: single .lost alert")
    check(w.observe(trusted: false, nudgeNeeded: true) == nil, "...no second alert")
}

print("== TeamsMatch ==")
check(TeamsMatch.isTeams(bundleID: "com.microsoft.teams2", name: "Microsoft Teams", isRegularApp: true), "new Teams")
check(TeamsMatch.isTeams(bundleID: "com.microsoft.teams", name: "Microsoft Teams classic", isRegularApp: true), "classic Teams")
check(TeamsMatch.isTeams(bundleID: "com.microsoft.teams2", name: nil, isRegularApp: false), "native ID matches even without a name")
check(TeamsMatch.isTeams(bundleID: "com.google.Chrome.app.abcdef", name: "Microsoft Teams", isRegularApp: true), "Chrome PWA")
check(TeamsMatch.isTeams(bundleID: "com.microsoft.edgemac.app.abcdef", name: "Microsoft Teams (work or school)", isRegularApp: true), "Edge PWA with suffix")
check(TeamsMatch.isTeams(bundleID: "com.apple.Safari.WebApp.UUID", name: "microsoft teams", isRegularApp: true), "Safari web app, case-insensitive")
// The helpers observed on a real Mac: all must be rejected.
check(!TeamsMatch.isTeams(bundleID: "com.microsoft.teams2.notificationcenter", name: "Microsoft Teams (Notification Center)", isRegularApp: false), "helper: notification center")
check(!TeamsMatch.isTeams(bundleID: "com.microsoft.teams2.helper", name: "Microsoft Teams WebView", isRegularApp: false), "helper: WebView")
check(!TeamsMatch.isTeams(bundleID: "com.microsoft.teams2.modulehost", name: "Microsoft Teams ModuleHost", isRegularApp: false), "helper: module host")
check(!TeamsMatch.isTeams(bundleID: "local.teamsawake", name: "TeamsAwake", isRegularApp: false), "TeamsAwake itself is not Teams")
check(!TeamsMatch.isTeams(bundleID: "com.apple.Safari", name: "Safari", isRegularApp: true), "unrelated app")
check(!TeamsMatch.isTeams(bundleID: nil, name: nil, isRegularApp: true), "no identity at all")
check(!TeamsMatch.isTeams(bundleID: "com.example.x", name: "Teams Practice Planner", isRegularApp: true), "another app with 'Teams' in its name")

print("== IconVisibility ==")
func vis(_ t: Bool, _ r: Bool, _ f: Bool, _ q: Bool, _ run: Bool) -> Bool {
    IconVisibility.shouldShow(trusted: t, revealed: r, followTeams: f, requireTeams: q, teamsRunning: run)
}
check(vis(true, false, true, true, true),   "Teams open: shown")
check(!vis(true, false, true, true, false), "Teams closed, follow + require: hidden")
check(vis(true, false, true, false, false), "require off (browser-tab user): stays shown")
check(vis(true, false, false, true, false), "follow off: always shown")
check(vis(false, false, true, true, false), "no Accessibility access: shown so setup is reachable")
check(vis(true, true, true, true, false),   "revealed by reopening the app: shown")

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
