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

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
