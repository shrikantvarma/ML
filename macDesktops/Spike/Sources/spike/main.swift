import Foundation
import AppKit

// ---------------------------------------------------------------------------
// U1 de-risk spike — interactive probe. Run on the target Mac and drive it by
// hand to fill in SPIKE.md. THROWAWAY (plan U1).
//
// Architecture note: NSWorkspace's space-change notification must be delivered
// on a run loop, so the run loop owns the main thread (CFRunLoopRun) and the
// interactive menu (blocking readLine) runs on a background queue.
// ---------------------------------------------------------------------------

func short(_ uuid: String) -> String { String(uuid.prefix(8)) }

var muteWatch = false  // silence auto-prints during the run-N burst

/// Always-on watcher: prints add/remove/reorder diffs as you change desktops
/// (spike step: drift detection).
final class Watcher {
    private var lastUUIDs: [String] = []

    func snapshot() -> [String] { CGS.primaryDisplay()?.userSpaces.map { $0.uuid } ?? [] }

    func start() {
        lastUUIDs = snapshot()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.onChange() }
    }

    private func onChange() {
        guard !muteWatch else { return }
        let now = snapshot()
        let cur = Switcher.currentUUID().map(short) ?? "?"
        print("\n[space change] current=\(cur)")
        diff(old: lastUUIDs, new: now)
        lastUUIDs = now
        prompt()
    }

    private func diff(old: [String], new: [String]) {
        let oldSet = Set(old), newSet = Set(new)
        let added = new.filter { !oldSet.contains($0) }
        let removed = old.filter { !newSet.contains($0) }
        if !added.isEmpty { print("  + added:    \(added.map(short))") }
        if !removed.isEmpty { print("  - removed:  \(removed.map(short))") }
        if added.isEmpty, removed.isEmpty {
            print(old == new ? "  (active space changed; topology same)"
                             : "  ~ reordered: \(old.map(short)) -> \(new.map(short))")
        }
    }
}

let watcher = Watcher()

// --- command handlers ------------------------------------------------------

func cmdDiagnostics() { print(CGS.diagnostics()) }

func cmdList() {
    guard let displays = CGS.managedDisplaySpaces() else {
        print("ERROR: could not read managed display spaces (private symbol failure?). Run [1].")
        return
    }
    for (di, d) in displays.enumerated() {
        print("Display \(di): \(d.displayIdentifier)")
        for (i, s) in d.userSpaces.enumerated() {
            let mark = (s.uuid == d.currentSpaceUUID) ? "  *current*" : ""
            print("  [\(i + 1)] \(short(s.uuid))  id=\(s.managedSpaceID)\(mark)")
        }
        let other = d.spaces.filter { $0.type != 0 }
        if !other.isEmpty { print("  (\(other.count) non-desktop space(s): fullscreen/other)") }
    }
}

func cmdBind() {
    guard let d = CGS.primaryDisplay(), let cur = d.currentSpaceUUID,
          let s = d.userSpaces.first(where: { $0.uuid == cur }) else {
        print("ERROR: no current user space found."); return
    }
    print("Name this target (e.g., 'Sales'): ", terminator: ""); fflush(stdout)
    let raw = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
    let name = raw.isEmpty ? "target" : raw
    let b = Binding(name: name, uuid: cur, managedSpaceID: s.managedSpaceID, boundAt: Date())
    Store.save(b)
    print("Bound '\(b.name)' → space \(short(cur)) (id \(s.managedSpaceID)).")
    print("Saved to \(Store.fileURL.path)")
}

func describe(_ o: SwitchOutcome) -> String {
    switch o {
    case .switched(let ms):  return "SWITCHED & VERIFIED in \(ms)ms"
    case .driftDetected:     return "DRIFT — bound UUID not in current ordered list (recalibrate)"
    case .notKeyable(let i): return "NOT KEYABLE — index \(i) > 9, no single Ctrl+number"
    case .blocked(let r):    return "BLOCKED — \(r)"
    case .verificationFailed:return "VERIFICATION FAILED — posted Ctrl+N but did not land in time"
    }
}

func cmdSwitch() {
    guard let b = Store.load() else { print("No binding. Use [3] first."); return }
    print("Switching to '\(b.name)' (\(short(b.uuid)))…")
    print("  → \(describe(Switcher.switchTo(uuid: b.uuid)))")
}

func cmdRunN() {
    guard let b = Store.load() else { print("No binding. Use [3] first."); return }
    guard let d = CGS.primaryDisplay() else { print("No spaces."); return }
    guard let other = d.userSpaces.map({ $0.uuid }).first(where: { $0 != b.uuid }) else {
        print("Need ≥2 desktops to bounce between."); return
    }
    print("How many round-trips? (default 50): ", terminator: ""); fflush(stdout)
    let n = Int(readLine()?.trimmingCharacters(in: .whitespaces) ?? "") ?? 50

    var successes = 0, failures = 0
    var latencies: [Int] = []
    var failModes: [String: Int] = [:]

    func record(_ o: SwitchOutcome) {
        switch o {
        case .switched(let ms):   successes += 1; latencies.append(ms)
        case .driftDetected:      failures += 1; failModes["drift", default: 0] += 1
        case .notKeyable:         failures += 1; failModes["notKeyable", default: 0] += 1
        case .blocked(let r):     failures += 1; failModes[r, default: 0] += 1
        case .verificationFailed: failures += 1; failModes["verificationFailed", default: 0] += 1
        }
    }

    muteWatch = true
    defer { muteWatch = false }
    print("Running \(n) round-trips (\(n * 2) switches)… do not touch the keyboard/desktops.")
    for i in 1...n {
        record(Switcher.switchTo(uuid: b.uuid));  usleep(150_000)
        record(Switcher.switchTo(uuid: other));   usleep(150_000)
        if i % 10 == 0 { print("  …\(i * 2) switches done") }
    }

    let total = successes + failures
    let sorted = latencies.sorted()
    let median = sorted.isEmpty ? -1 : sorted[sorted.count / 2]
    let worst = sorted.last ?? -1
    print("""
    --- RESULTS ---
    total switches:           \(total)
    verified success:         \(successes) (\(total > 0 ? successes * 100 / total : 0)%)
    failures:                 \(failures)
    median success latency:   \(median)ms
    worst success latency:    \(worst)ms
    failure breakdown:        \(failModes.isEmpty ? "none" : failModes.description)
    GATE: needs ≥99% success, 0 silent wrong-landings, median ≤1500ms
    """)
}

func cmdFailureChecks() {
    print("Accessibility trusted: \(Probes.accessibilityTrusted())")
    print("Secure Input active:   \(Probes.secureInputEnabled())")
    if let d = CGS.primaryDisplay() {
        for i in 1...min(d.userSpaces.count, 9) {
            let state = Probes.shortcutEnabled(desktop: i).map { String($0) } ?? "unknown"
            print("Switch-to-Desktop \(i) shortcut enabled: \(state)")
        }
    }
    print("(Tip: toggle Secure Input by focusing a password field, then re-run [6].)")
}

func cmdShowBinding() {
    guard let b = Store.load() else { print("No persisted binding."); return }
    let resolved = Switcher.resolveIndex(uuid: b.uuid).map { "index \($0)" }
        ?? "NOT FOUND — UUID did not survive / desktop removed"
    print("""
    persisted binding: '\(b.name)'
      uuid:            \(b.uuid)
      managedSpaceID:  \(b.managedSpaceID)
      bound at:        \(b.boundAt)
      resolves now to: \(resolved)
    """)
}

func cmdActiveSpaceProbe() {
    guard let active = CGS.activeSpaceID() else {
        print("CGSGetActiveSpace MISSING — focused-display read unavailable (Part 2 must use a fallback).")
        return
    }
    print("CGSGetActiveSpace → \(active)")
    guard let displays = CGS.managedDisplaySpaces() else { print("no displays"); return }
    var matched = false
    for (di, d) in displays.enumerated() {
        for s in d.spaces where Int(s.managedSpaceID) == active {
            print("  ✓ matches Display \(di) space \(short(s.uuid)) (managedSpaceID \(s.managedSpaceID))")
            matched = true
        }
    }
    if !matched { print("  ✗ no managedSpaceID matched \(active) — active-id is a DIFFERENT id space; record this.") }
}

/// Apps with a normal (layer-0) window currently composited ON SCREEN. A real
/// visible space switch changes this set (windows appear/disappear); the internal
/// "current space" record updating alone does not. Owner names need no screen-
/// recording permission. This is the decisive, no-eyeball switch signal.
func onScreenApps() -> Set<String> {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let arr = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
    return Set(arr.compactMap { w -> String? in
        guard (w[kCGWindowLayer as String] as? Int) == 0 else { return nil }
        return w[kCGWindowOwnerName as String] as? String
    })
}

func cmdDirectSwitch() {
    guard let displays = CGS.managedDisplaySpaces() else { print("no displays"); return }
    // Pick ANY desktop by <display>.<space> — no binding, no "current", no focus
    // dependency. Keep the Terminal on one screen and target a desktop on the OTHER.
    print("DIRECT-switch — pick a desktop as <display>.<space> (e.g. 1.2):")
    for (di, d) in displays.enumerated() {
        for (si, s) in d.userSpaces.enumerated() {
            let mark = (s.uuid == d.currentSpaceUUID) ? "  *current*" : ""
            print("  \(di).\(si + 1)  \(short(s.uuid))  id=\(s.managedSpaceID)\(mark)")
        }
    }
    print("> ", terminator: ""); fflush(stdout)
    let parts = (readLine() ?? "").split(separator: ".").compactMap { Int($0) }
    guard parts.count == 2, parts[0] >= 0, parts[0] < displays.count else { print("bad input — use <display>.<space>"); return }
    let d = displays[parts[0]]
    let userSpaces = d.userSpaces
    guard parts[1] >= 1, parts[1] <= userSpaces.count else { print("bad space index for that display"); return }
    let s = userSpaces[parts[1] - 1]
    print("Direct-switching Display \(parts[0]) ('\(d.displayIdentifier)') → \(short(s.uuid)) (id \(s.managedSpaceID))…")
    let before = onScreenApps()
    let ok = CGS.directSetCurrentSpace(displayID: d.displayIdentifier, spaceID: s.managedSpaceID)
    guard ok else { print("  ✗ CGSManagedDisplaySetCurrentSpace MISSING — Approach A not possible (use Approach B)."); return }
    usleep(400_000)
    let after = onScreenApps()
    let nowCurrent = CGS.managedDisplaySpaces()?.first(where: { $0.displayIdentifier == d.displayIdentifier })?.currentSpaceUUID
    print("  internal current: \(nowCurrent == s.uuid ? "✓ updated to target" : "✗ NOT updated") (\(nowCurrent.map(short) ?? "?"))")
    let appeared = after.subtracting(before), gone = before.subtracting(after)
    if appeared.isEmpty && gone.isEmpty {
        print("  on-screen apps UNCHANGED → screen did NOT visibly switch (failure mode).")
    } else {
        print("  ✓ VISIBLE SWITCH — appeared: \(appeared.sorted()); disappeared: \(gone.sorted())")
    }
}

// --- messy-state gate commands (exit checklist) ----------------------------

func uuidShown(_ u: String) -> String {
    u.isEmpty ? "<EMPTY>" : (u == "?" ? "<MISSING>" : short(u))
}

/// [i] Identity & guard table — surfaces empty-/missing-uuid desktops and the
/// guard's verdict per desktop (checklist item: EMPTY uuid handled, no collision).
func cmdIdentityTable() {
    guard let displays = CGS.managedDisplaySpaces() else { print("no displays"); return }
    var untrackable = 0, empties = 0
    for (di, d) in displays.enumerated() {
        print("Display \(di): \(d.displayIdentifier)  (current \(d.currentSpaceUUID.map(uuidShown) ?? "?"))")
        for (si, s) in d.userSpaces.enumerated() {
            let trackable = SpaceIdentity.isTrackable(s.uuid)
            if !trackable { untrackable += 1 }
            if s.uuid.isEmpty { empties += 1 }
            let cur = (trackable && s.uuid == d.currentSpaceUUID) ? "  *current*" : ""
            print("  \(di).\(si + 1)  uuid=\(uuidShown(s.uuid))  id64=\(s.managedSpaceID)  trackable=\(trackable ? "yes" : "NO")\(cur)")
        }
    }
    print("Summary: \(untrackable) untrackable desktop(s) (\(empties) empty-uuid). These can host NO project until they get a real uuid.")
    if untrackable == 0 {
        print("(No untrackable desktops right now — DRAG a desktop between monitors in Mission Control to try to produce one, then re-run [i].)")
    }
}

/// [r] Recalibrate resolution — proves recalibrate targets the FOCUSED display's
/// current desktop (via CGSGetActiveSpace), not display 0 (checklist item).
func cmdRecalibrateResolve() {
    guard let active = CGS.activeSpaceID() else {
        print("CGSGetActiveSpace MISSING — focused-display read unavailable (needs a fallback)."); return
    }
    guard let displays = CGS.managedDisplaySpaces() else { print("no displays"); return }
    var found: (Int, DisplaySpaces, SpaceInfo)?
    for (di, d) in displays.enumerated() {
        for s in d.spaces where Int(s.managedSpaceID) == active { found = (di, d, s) }
    }
    guard let (di, d, s) = found else {
        print("active id \(active) matched no managedSpaceID — record this (focused read needs a fallback)."); return
    }
    print("CGSGetActiveSpace → \(active)  ⇒ focused display = Display \(di) (\(d.displayIdentifier))")
    print("Focused current desktop: uuid=\(uuidShown(s.uuid)) id64=\(s.managedSpaceID)")
    if SpaceIdentity.isTrackable(s.uuid) {
        print("  → Recalibrate WOULD bind the project to \(short(s.uuid)) on display \(di).")
    } else {
        print("  → Recalibrate WOULD REFUSE — focused desktop is untrackable (empty/missing uuid). Correct guard behavior.")
    }
    if let p = displays.first {
        let same = p.displayIdentifier == d.displayIdentifier
        print("Contrast — Display 0 current: \(p.currentSpaceUUID.map(uuidShown) ?? "?")."
            + (same ? "  (focus IS on display 0; move focus to the secondary screen and re-run to see the difference.)"
                    : "  Differs from focused ⇒ recalibrate correctly followed FOCUS, not display 0."))
    }
}

/// [m] Identity churn — snapshot id64→uuid, then diff after you DRAG desktops
/// between monitors. Answers PROBE #3 (is id64 stable when uuid goes empty?) and
/// sets up the "switch still correct after a drag" check (checklist item).
var lastIdentitySnapshot: [Int64: String] = [:]
func cmdIdentityChurn() {
    guard let displays = CGS.managedDisplaySpaces() else { print("no displays"); return }
    var now: [Int64: (uuid: String, display: Int)] = [:]
    for (di, d) in displays.enumerated() {
        for s in d.userSpaces { now[s.managedSpaceID] = (s.uuid, di) }
    }
    if lastIdentitySnapshot.isEmpty {
        lastIdentitySnapshot = now.mapValues { $0.uuid }
        print("Snapshot: \(now.count) user desktops (id64→uuid). Now DRAG desktops between monitors in Mission Control, then run [m] again.")
        return
    }
    print("Diff vs previous snapshot:")
    var changed = false
    for (id64, cur) in now.sorted(by: { $0.key < $1.key }) {
        guard let prev = lastIdentitySnapshot[id64] else {
            print("  + NEW id64 \(id64): uuid=\(uuidShown(cur.uuid)) (display \(cur.display))"); changed = true; continue
        }
        if prev != cur.uuid {
            let probe = (!prev.isEmpty && cur.uuid.isEmpty)
                ? "   ← PROBE#3: id64 STABLE but uuid went EMPTY → id64 is a session-stable fallback key" : ""
            print("  ~ id64 \(id64): uuid \(uuidShown(prev)) → \(uuidShown(cur.uuid)) (now display \(cur.display))\(probe)")
            changed = true
        }
    }
    for (id64, prev) in lastIdentitySnapshot where now[id64] == nil {
        print("  - GONE id64 \(id64) (was uuid=\(uuidShown(prev)))"); changed = true
    }
    if !changed { print("  (no id64/uuid changes — both stable across the operation)") }
    lastIdentitySnapshot = now.mapValues { $0.uuid }
    print("Now run [8] to confirm a switch STILL lands on the right desktop after the drag.")
}

/// [s] Stale/empty binding → "current project" resolution, NAIVE vs GUARDED.
/// Proves a stale or empty-uuid binding never yields a wrong current project
/// (checklist item: stale bindings don't cause wrong "current project").
func cmdStaleBindingCheck() {
    guard let displays = CGS.managedDisplaySpaces() else { print("no displays"); return }
    print("Bind a TEST project to:  e=empty-uuid (the trap)   k=keep persisted binding   <display>.<space> (e.g. 1.2)")
    print("> ", terminator: ""); fflush(stdout)
    let choice = (readLine() ?? "").trimmingCharacters(in: .whitespaces)
    var testUUID = "", label = "test"
    switch choice {
    case "e": testUUID = ""
    case "k":
        guard let b = Store.load() else { print("no persisted binding."); return }
        testUUID = b.uuid; label = b.name
    default:
        let parts = choice.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 2, parts[0] >= 0, parts[0] < displays.count else { print("bad input."); return }
        let us = displays[parts[0]].userSpaces
        guard parts[1] >= 1, parts[1] <= us.count else { print("bad space index."); return }
        testUUID = us[parts[1] - 1].uuid
    }
    print("Test project '\(label)' bound to uuid=\(uuidShown(testUUID))")
    print("Is it 'current' on each display?  naive = raw==  |  guarded = isTrackable(both) && ==")
    for (di, d) in displays.enumerated() {
        let cur = d.currentSpaceUUID ?? ""
        let naive = (cur == testUUID)
        let guarded = SpaceIdentity.isTrackable(testUUID) && SpaceIdentity.isTrackable(cur) && cur == testUUID
        let flag = (naive && !guarded) ? "   ⚠️ COLLISION the guard PREVENTS" : ""
        print("  Display \(di): naive=\(naive ? "CURRENT" : "no")  guarded=\(guarded ? "CURRENT" : "no")\(flag)")
    }
    print("Verdict: an empty/missing-uuid binding is NEVER 'current' (no false project); a real binding is current only on the display actually showing it.")
}

/// [n] Direct switch + ACTIVATION NUDGE — mitigation probe for the stale/overlapping
/// menu bar a bare direct switch leaves on the switched display. After switching, we
/// activate (public AppKit, no SIP) the app that appeared on the target space to force
/// the WindowServer to re-evaluate that display's frontmost app / menu bar. We measure
/// whether keyboard FOCUS moved (CGSGetActiveSpace before/after) so we can tell a
/// focus-preserving fix from a focus-stealing one; the menu-bar clear itself is by eye.
func cmdNudgeSwitch() {
    guard let displays = CGS.managedDisplaySpaces() else { print("no displays"); return }
    print("NUDGE-switch — pick a NON-EMPTY desktop on the OTHER display as <display>.<space>:")
    for (di, d) in displays.enumerated() {
        for (si, s) in d.userSpaces.enumerated() {
            let mark = (s.uuid == d.currentSpaceUUID) ? "  *current*" : ""
            print("  \(di).\(si + 1)  \(uuidShown(s.uuid))  id=\(s.managedSpaceID)\(mark)")
        }
    }
    print("> ", terminator: ""); fflush(stdout)
    let parts = (readLine() ?? "").split(separator: ".").compactMap { Int($0) }
    guard parts.count == 2, parts[0] >= 0, parts[0] < displays.count else { print("bad input."); return }
    let d = displays[parts[0]]
    let us = d.userSpaces
    guard parts[1] >= 1, parts[1] <= us.count else { print("bad space index."); return }
    let s = us[parts[1] - 1]

    let activeBefore = CGS.activeSpaceID()
    let before = onScreenApps()
    guard CGS.directSetCurrentSpace(displayID: d.displayIdentifier, spaceID: s.managedSpaceID) else {
        print("  ✗ switch symbol MISSING."); return
    }
    usleep(400_000)
    let appeared = onScreenApps().subtracting(before)
    print("  switched → appeared: \(appeared.sorted().isEmpty ? "[] (empty target — pick a desktop WITH an app to test the menu bar)" : appeared.sorted().description)")
    guard let name = appeared.sorted().first,
          let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) else {
        print("  no appeared app to nudge — can't test the menu-bar refresh."); return
    }
    print("  NUDGE: activating '\(name)' (public NSRunningApplication.activate, no SIP)…")
    app.activate()
    usleep(300_000)
    let activeAfter = CGS.activeSpaceID()
    let focusMoved = activeBefore != activeAfter
    print("  focus: \(focusMoved ? "MOVED to the switched display (activeSpace \(activeBefore ?? -1) → \(activeAfter ?? -1)) — NOT focus-preserving" : "STAYED on the original display (activeSpace \(activeAfter ?? -1)) — focus-preserving ✓")")
    print("  → LOOK at display \(parts[0]): did the menu-bar overlap CLEAR? Record y/n.")
}

/// A layer-0 on-screen window owned by one of `appeared` apps → (pid, windowID, name),
/// the target the SLPS nudge needs to make front+key.
func appearedWindow(_ appeared: Set<String>) -> (pid: pid_t, wid: UInt32, name: String)? {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let arr = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return nil }
    for w in arr {
        guard (w[kCGWindowLayer as String] as? Int) == 0,
              let name = w[kCGWindowOwnerName as String] as? String, appeared.contains(name),
              let pidN = w[kCGWindowOwnerPID as String] as? Int,
              let widN = w[kCGWindowNumber as String] as? Int else { continue }
        return (pid_t(pidN), UInt32(widN), name)
    }
    return nil
}

/// [p] Direct switch + SLPS PROCESS-SERVER nudge — the lower-level activation that
/// underlies a real menu-bar click (NSRunningApplication.activate no-ops post-Sonoma).
/// The decisive menu-bar-overlap mitigation probe for Approach A.
func cmdProcessServerNudge() {
    guard let displays = CGS.managedDisplaySpaces() else { print("no displays"); return }
    print("SLPS-NUDGE switch — pick a NON-EMPTY desktop on the OTHER display as <display>.<space>:")
    for (di, d) in displays.enumerated() {
        for (si, s) in d.userSpaces.enumerated() {
            let mark = (s.uuid == d.currentSpaceUUID) ? "  *current*" : ""
            print("  \(di).\(si + 1)  \(uuidShown(s.uuid))  id=\(s.managedSpaceID)\(mark)")
        }
    }
    print("> ", terminator: ""); fflush(stdout)
    let parts = (readLine() ?? "").split(separator: ".").compactMap { Int($0) }
    guard parts.count == 2, parts[0] >= 0, parts[0] < displays.count else { print("bad input."); return }
    let d = displays[parts[0]]
    let us = d.userSpaces
    guard parts[1] >= 1, parts[1] <= us.count else { print("bad space index."); return }
    let s = us[parts[1] - 1]

    let activeBefore = CGS.activeSpaceID()
    let before = onScreenApps()
    guard CGS.directSetCurrentSpace(displayID: d.displayIdentifier, spaceID: s.managedSpaceID) else {
        print("  ✗ switch symbol MISSING."); return
    }
    usleep(400_000)
    let appeared = onScreenApps().subtracting(before)
    print("  switched → appeared: \(appeared.sorted().isEmpty ? "[] (empty target — pick a desktop WITH an app)" : appeared.sorted().description)")
    guard let win = appearedWindow(appeared) else {
        print("  no appeared window to nudge — can't test the menu-bar refresh."); return
    }
    print("  SLPS nudge: making '\(win.name)' (pid \(win.pid), wid \(win.wid)) front+key via _SLPSSetFrontProcessWithOptions…")
    guard CGS.frontProcessNudge(pid: win.pid, windowID: win.wid) else {
        print("  ✗ SLPS symbols MISSING — process-server nudge unavailable."); return
    }
    usleep(300_000)
    let activeAfter = CGS.activeSpaceID()
    let focusMoved = activeBefore != activeAfter
    print("  focus: \(focusMoved ? "MOVED to the switched display (activeSpace \(activeBefore ?? -1) → \(activeAfter ?? -1)) — NOT focus-preserving" : "STAYED on the original display (activeSpace \(activeAfter ?? -1)) — focus-preserving ✓")")
    print("  → LOOK at display \(parts[0]): did the menu-bar overlap CLEAR? Record y/n.")
}

/// [b] Approach B de-risk — is Ctrl+N a viable switch primitive on THIS multi-display
/// rig? Reports (1) whether "Switch to Desktop N" shortcuts are enabled (default OFF),
/// (2) Secure Input state, then optionally posts Ctrl+<n> and shows WHICH display's
/// current space changed (targeting) + window-delta + a by-eye overlap check.
func cmdApproachBProbe() {
    let displays = CGS.managedDisplaySpaces() ?? []
    // GLOBAL numbering: Ctrl+N indexes desktops across ALL displays (display-then-space
    // order), so probe up to the TOTAL desktop count, not the max on one display.
    let total = displays.reduce(0) { $0 + $1.userSpaces.count }
    let maxN = min(9, max(1, total))
    print("Approach B viability —")
    print("  global desktop map (Ctrl+N → display.space):")
    var g = 0
    for (di, d) in displays.enumerated() {
        for (si, s) in d.userSpaces.enumerated() { g += 1; print("    Ctrl+\(g) → \(di).\(si + 1)  \(uuidShown(s.uuid))") }
    }
    print("  'Switch to Desktop N' shortcuts (com.apple.symbolichotkeys):")
    for i in 1...maxN {
        let st = Probes.shortcutEnabled(desktop: i).map { $0 ? "ENABLED" : "disabled (default)" } ?? "unknown"
        print("    Ctrl+\(i): \(st)")
    }
    print("  Secure Input active: \(Probes.secureInputEnabled())")
    print("  Accessibility trusted (needed to post keys): \(Probes.accessibilityTrusted())")
    print("Post a Ctrl+<n> to test targeting? Focus the display you want to switch FIRST")
    print("(terminal must be ON that display; 'Assign Terminal to All Desktops' so it survives the switch).")
    print("Enter desktop number 1-\(maxN), or blank to skip: ", terminator: ""); fflush(stdout)
    let raw = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
    guard let n = Int(raw), (1...maxN).contains(n) else { print("(skipped the post test.)"); return }

    let beforeApps = onScreenApps()
    let beforeCur = displays.map { ($0.displayIdentifier, $0.currentSpaceUUID) }
    let activeBefore = CGS.activeSpaceID()
    Switcher.postControlNumber(n)
    usleep(400_000)
    let afterApps = onScreenApps()
    let after = CGS.managedDisplaySpaces() ?? []
    var changed: [Int] = []
    for (di, d) in after.enumerated() {
        let prev = beforeCur.first(where: { $0.0 == d.displayIdentifier })?.1 ?? nil
        if prev != d.currentSpaceUUID { changed.append(di) }
    }
    let activeAfter = CGS.activeSpaceID()
    print("  Ctrl+\(n) posted (focused display active space \(activeBefore ?? -1) → \(activeAfter ?? -1)).")
    print("  display(s) whose current space changed: \(changed.isEmpty ? "NONE — no switch (shortcut off / Secure Input / focus elsewhere)" : changed.description)")
    let appeared = afterApps.subtracting(beforeApps), gone = beforeApps.subtracting(afterApps)
    print("  window-delta: appeared \(appeared.sorted()), disappeared \(gone.sorted())")
    print("  → By eye: did the RIGHT display switch to the RIGHT desktop, and is the menu bar CLEAN (no overlap)?")
}

// --- menu loop -------------------------------------------------------------

func printMenu() {
    print("""

    === Parallel Project Desktops — U1 spike (\(ProcessInfo.processInfo.operatingSystemVersionString)) ===
    1  diagnostics (private symbol availability)
    2  list ordered Space UUIDs (+ current)
    3  bind test target to CURRENT space
    4  switch to bound target (resolve → Ctrl+N → verify)
    5  run N round-trips → success rate + latency
    6  failure-mode checks (secure input / shortcut / accessibility)
    7  show persisted binding (run after reboot to test UUID survival)
    8  DIRECT-switch to a picked desktop via CGS (no Ctrl+N) — Approach A probe
    9  probe active space (CGSGetActiveSpace) vs per-display current
    --- messy-state gate (exit checklist) ---
    i  identity & guard table (surface empty-uuid desktops + guard verdict)
    r  recalibrate resolution (proves focused-display target, not display 0)
    m  identity churn snapshot/diff (drag desktops → PROBE#3 id64 stability)
    s  stale/empty binding → 'current project' resolution (naive vs guarded)
    n  direct switch + ACTIVATION NUDGE (NSRunningApplication) — mitigation probe
    p  direct switch + SLPS PROCESS-SERVER nudge — decisive menu-bar mitigation probe
    b  Approach B de-risk — Ctrl+N shortcut availability + targeting + overlap check
    q  quit
    (space-change events print automatically as you add/remove/reorder desktops)
    """)
}

func prompt() { print("> ", terminator: ""); fflush(stdout) }

func menuLoop() {
    while true {
        printMenu(); prompt()
        guard let line = readLine() else { break }
        switch line.trimmingCharacters(in: .whitespaces).lowercased() {
        case "1": cmdDiagnostics()
        case "2": cmdList()
        case "3": cmdBind()
        case "4": cmdSwitch()
        case "5": cmdRunN()
        case "6": cmdFailureChecks()
        case "7": cmdShowBinding()
        case "8": cmdDirectSwitch()
        case "9": cmdActiveSpaceProbe()
        case "i": cmdIdentityTable()
        case "r": cmdRecalibrateResolve()
        case "m": cmdIdentityChurn()
        case "s": cmdStaleBindingCheck()
        case "n": cmdNudgeSwitch()
        case "p": cmdProcessServerNudge()
        case "b": cmdApproachBProbe()
        case "q", "quit", "exit":
            print("bye"); CFRunLoopStop(CFRunLoopGetMain()); return
        case "": continue
        default: print("unknown command")
        }
    }
}

// --- entry -----------------------------------------------------------------

print("Parallel Project Desktops — U1 de-risk spike\n")
print(CGS.diagnostics())
if !Probes.accessibilityTrusted() {
    print("\n⚠️  Accessibility NOT granted — switching (Ctrl+N) will be ignored.")
    print("   Grant Terminal (or the host app) in System Settings ▸ Privacy & Security ▸ Accessibility,")
    print("   then relaunch. Reading spaces still works without it.")
    _ = Probes.accessibilityTrusted(prompt: true)
}
watcher.start()
DispatchQueue.global(qos: .userInitiated).async { menuLoop() }
CFRunLoopRun()
