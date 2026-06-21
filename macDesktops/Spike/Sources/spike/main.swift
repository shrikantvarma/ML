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
