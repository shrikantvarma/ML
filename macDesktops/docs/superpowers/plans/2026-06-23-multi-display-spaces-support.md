# Multi-Display Spaces Support — Implementation Plan (Part 1: Spike Gate + Drift Fix)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate (on the real two-display Mac) whether a private CGS call can switch the active space on a non-primary display, and immediately fix the false "desktop moved — Recalibrate" drift flag that fires whenever a desktop is moved to a second screen.

**Architecture:** The app's read/switch layer is scoped to `CGS.primaryDisplay()` only. This plan (a) adds a spike command that probes the direct space-switch + active-space-read private symbols on macOS 26.4.1 to select Approach A vs B for Part 2, and (b) changes drift detection to treat a desktop as "present" if it exists on *any* display — a contained, non-regressing change behind the existing `SpacesProvider` seam.

**Tech Stack:** Swift 6, SwiftPM, XCTest, private SkyLight (WindowServer) symbols via `dlsym`.

## Global Constraints

- Target OS: macOS 26.4.1 (the only on-device-validated version). "Displays have separate Spaces" is ON (`com.apple.spaces spans-displays = 0`).
- All private symbols MUST be resolved at runtime via `dlsym` and degrade gracefully when missing (never a link error). Same pattern as existing `CGSPrivate.swift` / spike `CGSBridge.swift`.
- Use `str | None`-style optionals idiomatically; full types on all signatures (Swift requires this anyway).
- TDD: failing test first for all non-spike code. The spike is a manual probe — its "test" is observation against explicit pass criteria.
- Do NOT change the `RealDesktopEngine` / Ctrl+N switch path in this plan (that is Part 2, gated by Task 1's result). Nothing here may regress current single-display switching.
- Conventional commits. Do not push. Branch: `full-app-mvp`.
- Run all commands from the package directory shown in each step (the git root is `~/Code`; the SwiftPM packages are under `macDesktops/`).

---

### Task 1: Spike — probe direct CGS space-switch + active-space read (GATE)

This task produces a Go/No-Go for **Approach A** (direct CGS switch) and validates the active-space read used by Part 2's recalibrate fix. It is run by hand on the two-display Mac; results decide Part 2.

**Files:**
- Modify: `Spike/Sources/spike/CGSBridge.swift` (add two symbols + wrappers + diagnostics)
- Modify: `Spike/Sources/spike/main.swift` (add menu commands `8` and `9`)
- Create: `Spike/SPIKE-multidisplay.md` (results template, filled in during the run)

**Interfaces:**
- Consumes: existing `CGS.connectionID`, `CGS.managedDisplaySpaces()`, `Store.load()` (the persisted `Binding`).
- Produces: empirical findings recorded in `Spike/SPIKE-multidisplay.md` — the exact working symbol name + call signature for the direct switch, and whether `CGSGetActiveSpace` returns an id matching a known space. Part 2 reads this file.

- [ ] **Step 1: Add the two private symbols and wrappers to `CGSBridge.swift`**

Add these typealiases next to the existing ones (after line 11):

```swift
private typealias GetActiveSpaceFn = @convention(c) (CGSConnectionID) -> Int
private typealias SetCurrentSpaceFn = @convention(c) (CGSConnectionID, CFString, Int) -> Void
```

Add inside `enum CGS`, after the `copyManaged` symbol (after line 39):

```swift
    // Part 2 candidates — probed by the spike, NOT yet used by the app.
    private static let getActiveSpace = sym("CGSGetActiveSpace", as: GetActiveSpaceFn.self)
    private static let setCurrentSpace = sym("CGSManagedDisplaySetCurrentSpace", as: SetCurrentSpaceFn.self)

    /// Globally-active space id (the space on the focused display). nil if symbol absent.
    static func activeSpaceID() -> Int? {
        guard let conn = connectionID, let fn = getActiveSpace else { return nil }
        return fn(conn)
    }

    /// Attempt a DIRECT switch (no Ctrl+N) of `displayID`'s current space to `spaceID`.
    /// Returns false if the symbol is unavailable. Landing must be VERIFIED by the caller.
    @discardableResult
    static func directSetCurrentSpace(displayID: String, spaceID: Int64) -> Bool {
        guard let conn = connectionID, let fn = setCurrentSpace else { return false }
        fn(conn, displayID as CFString, Int(spaceID))
        return true
    }
```

Extend `diagnostics()` — add before `return lines.joined(...)`:

```swift
        lines.append("CGSGetActiveSpace:            \(getActiveSpace != nil ? "found" : "MISSING")")
        lines.append("CGSManagedDisplaySetCurrentSpace: \(setCurrentSpace != nil ? "found" : "MISSING")")
```

- [ ] **Step 2: Add menu commands `8` (direct switch) and `9` (active-space probe) to `main.swift`**

Add these handlers before `// --- menu loop ---` (before line 180):

```swift
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

func cmdDirectSwitch() {
    guard let b = Store.load() else { print("No binding. Use [3] first."); return }
    guard let displays = CGS.managedDisplaySpaces() else { print("no displays"); return }
    guard let (d, s) = displays.lazy.compactMap({ disp -> (DisplaySpaces, SpaceInfo)? in
        disp.userSpaces.first(where: { $0.uuid == b.uuid }).map { (disp, $0) }
    }).first else {
        print("bound uuid \(short(b.uuid)) not found on any display — move to it or rebind [3]."); return
    }
    print("Direct-switching Display '\(d.displayIdentifier)' to '\(b.name)' (\(short(b.uuid)), id \(s.managedSpaceID))…")
    let ok = CGS.directSetCurrentSpace(displayID: d.displayIdentifier, spaceID: s.managedSpaceID)
    guard ok else { print("  ✗ CGSManagedDisplaySetCurrentSpace MISSING — Approach A not possible, use Approach B."); return }
    usleep(300_000)
    let nowCurrent = CGS.managedDisplaySpaces()?.first(where: { $0.displayIdentifier == d.displayIdentifier })?.currentSpaceUUID
    let landed = (nowCurrent == b.uuid)
    print("  \(landed ? "✓ LANDED" : "✗ DID NOT LAND") — display current is now \(nowCurrent.map(short) ?? "?")")
    print("  Observe by eye: did that screen actually switch, and is keyboard focus correct?")
}
```

Add to `printMenu()` (after the `7  show persisted binding` line):

```swift
    8  DIRECT-switch to bound target via CGS (no Ctrl+N) — Approach A probe
    9  probe active space (CGSGetActiveSpace) vs per-display current
```

Add to the `switch` in `menuLoop()` (after `case "7"`):

```swift
        case "8": cmdDirectSwitch()
        case "9": cmdActiveSpaceProbe()
```

- [ ] **Step 3: Build the spike**

Run: `swift build --package-path macDesktops/Spike`
Expected: builds with no errors. (A `MISSING` symbol is a runtime finding, not a build failure.)

- [ ] **Step 4: Create the results template `Spike/SPIKE-multidisplay.md`**

```markdown
# Multi-Display Switch Spike — Results (macOS 26.4.1, separate Spaces ON)

Run `swift run --package-path macDesktops/Spike spike` with TWO displays connected.
Grant Accessibility to the terminal first.

## Symbol availability (command 1)
- CGSGetActiveSpace: [found / MISSING]
- CGSManagedDisplaySetCurrentSpace: [found / MISSING]

## Active-space read (command 9)
- CGSGetActiveSpace returned: __
- Matched a known managedSpaceID? [yes → which display / no]
- Conclusion: focused-display read is [usable / needs fallback]

## Direct switch (command 3 to bind a desktop on the SECONDARY display, then command 8)
- Display current updated to target? [yes / no]
- Screen visibly switched? [yes / no]
- Keyboard focus correct after switch? [yes / no]
- Repeated 10× — any failures or wrong landings? __

## GATE DECISION
- [ ] PASS → Part 2 uses **Approach A** (direct CGS switch)
- [ ] FAIL → Part 2 uses **Approach B** (focus display + Ctrl+N)
- Notes / exact working signature: __
```

- [ ] **Step 5: Run the spike on the two-display Mac and fill in the results**

Run: `swift run --package-path macDesktops/Spike spike`
Drive: `1` (symbols) → connect/confirm 2 displays → `2` (list, confirm spaces on both displays) → `9` (active-space) → move to a desktop on the **secondary** display, `3` (bind it) → `8` (direct switch) ×10. Record every line in `SPIKE-multidisplay.md` and tick the GATE DECISION.

Pass criteria: command `8` lands the bound secondary-display space (display current == target), the screen visibly switches, focus is correct, 10/10 with no wrong landings.

- [ ] **Step 6: Commit**

```bash
cd /Users/shrikantvarma/Code
git add macDesktops/Spike/Sources/spike/CGSBridge.swift macDesktops/Spike/Sources/spike/main.swift macDesktops/Spike/SPIKE-multidisplay.md
git commit -m "spike: probe direct CGS space-switch + active-space read on multi-display

Adds spike commands 8 (direct CGSManagedDisplaySetCurrentSpace switch,
no Ctrl+N) and 9 (CGSGetActiveSpace vs per-display current) to gate
Approach A vs B for multi-display Part 2. Results in SPIKE-multidisplay.md.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XqLfZbZRyHRKWXdw5csiVB"
```

---

### Task 2: Drift treats a desktop on ANY display as present (kills false "desktop moved")

**Files:**
- Modify: `ParallelDesktops/Sources/ParallelDesktopsCore/SpacesEngine/CGSPrivate.swift` (add `allDisplays()`)
- Modify: `ParallelDesktops/Sources/ParallelDesktopsCore/SpacesEngine/SpacesProvider.swift` (add `allUserSpaceUUIDs()` to protocol + default + CGS impl)
- Modify: `ParallelDesktops/Sources/ParallelDesktops/AppModel.swift:151-159` (`recomputeDrift` uses the union)
- Test: `ParallelDesktops/Tests/ParallelDesktopsCoreTests/CoreTests.swift` (multi-display fake + tests)

**Interfaces:**
- Consumes: `DriftDetector.driftedUUIDs(bound: [String], in ordered: [String]) -> [String]` (existing, unchanged).
- Produces: `SpacesProvider.allUserSpaceUUIDs() -> [String]` — union of user-desktop UUIDs across all displays. Default impl returns `orderedUserSpaceUUIDs()` (single-display callers unaffected). `CGSSpacesProvider` overrides with the real union. Part 2 consumes this too.

- [ ] **Step 1: Write the failing tests**

Add to `CoreTests.swift` (after the `DriftDetectorTests` class, around line 400):

```swift
// MARK: - Multi-display read (drift across displays)

final class FakeMultiDisplaySpaces: SpacesProvider {
    let perDisplay: [[String]]   // perDisplay[0] = "primary"
    let current: String?
    init(perDisplay: [[String]], current: String?) { self.perDisplay = perDisplay; self.current = current }
    func orderedUserSpaceUUIDs() -> [String] { perDisplay.first ?? [] }
    func currentSpaceUUID() -> String? { current }
    func allUserSpaceUUIDs() -> [String] { perDisplay.flatMap { $0 } }
}

final class MultiDisplaySpacesTests: XCTestCase {
    func testAllUserSpaceUUIDsUnionsAcrossDisplays() {
        let s = FakeMultiDisplaySpaces(perDisplay: [["A", "B"], ["C", "D"]], current: "A")
        XCTAssertEqual(Set(s.allUserSpaceUUIDs()), ["A", "B", "C", "D"])
    }
    func testSpaceMovedToSecondaryDisplayIsNotDrifted() {
        // "C" now lives on display 2; bound A and C must NOT be flagged drifted.
        let s = FakeMultiDisplaySpaces(perDisplay: [["A", "B"], ["C"]], current: "A")
        XCTAssertEqual(DriftDetector.driftedUUIDs(bound: ["A", "C"], in: s.allUserSpaceUUIDs()), [])
    }
    func testTrulyDeletedSpaceStillDrifts() {
        let s = FakeMultiDisplaySpaces(perDisplay: [["A"], ["C"]], current: "A")
        XCTAssertEqual(DriftDetector.driftedUUIDs(bound: ["A", "Z"], in: s.allUserSpaceUUIDs()), ["Z"])
    }
    func testDefaultAllUserSpacesFallsBackToOrdered() {
        // The existing single-display fake gets the union for free via the default impl.
        let s = FakeSpaces(ordered: ["A", "B"], current: "A")
        XCTAssertEqual(s.allUserSpaceUUIDs(), ["A", "B"])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path macDesktops/ParallelDesktops --filter MultiDisplaySpacesTests`
Expected: FAIL to compile — `FakeMultiDisplaySpaces` does not conform (`allUserSpaceUUIDs` not in protocol) and `FakeSpaces` has no `allUserSpaceUUIDs`.

- [ ] **Step 3: Add `allUserSpaceUUIDs()` to the protocol with a default**

In `SpacesProvider.swift`, add to the protocol (after `currentSpaceUUID()` on line 10):

```swift
    /// Union of user-desktop UUIDs across ALL displays. A desktop moved to a
    /// second screen is still "present" here — so it is NOT drift (multi-display).
    func allUserSpaceUUIDs() -> [String]
```

Add a default to the existing `public extension SpacesProvider` (alongside `resolveIndex`):

```swift
    /// Default: single-display behaviour. `CGSSpacesProvider` overrides with the
    /// real cross-display union; existing single-display fakes inherit this.
    func allUserSpaceUUIDs() -> [String] { orderedUserSpaceUUIDs() }
```

- [ ] **Step 4: Implement `allDisplays()` and the CGS override**

In `CGSPrivate.swift`, add after `primaryDisplay()` (after line 62):

```swift
    /// All displays with their ordered Spaces (empty if a symbol is unavailable).
    static func allDisplays() -> [DisplaySpaces] { managedDisplaySpaces() ?? [] }
```

In `SpacesProvider.swift`, add to `struct CGSSpacesProvider`:

```swift
    public func allUserSpaceUUIDs() -> [String] {
        CGS.allDisplays().flatMap { $0.userSpaces.map { $0.uuid } }
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path macDesktops/ParallelDesktops --filter MultiDisplaySpacesTests`
Expected: PASS (4 tests).

- [ ] **Step 6: Wire `recomputeDrift` to the union**

In `AppModel.swift`, replace the body of `recomputeDrift()` (lines 151-159) with:

```swift
    private func recomputeDrift() {
        let ordered = spaces.orderedUserSpaceUUIDs()
        orderedSnapshot = ordered
        // Drift = bound desktop absent from EVERY display (truly deleted), not merely
        // moved to another screen. Using the cross-display union fixes the false
        // "desktop moved — Recalibrate" flag on multi-display setups.
        let present = spaces.allUserSpaceUUIDs()
        let drifted = Set(DriftDetector.driftedUUIDs(bound: projects.map { $0.spaceUUID }, in: present))
        for i in projects.indices where projects[i].drifted != drifted.contains(projects[i].spaceUUID) {
            projects[i].drifted = drifted.contains(projects[i].spaceUUID)
            store.update(projects[i])
        }
    }
```

- [ ] **Step 7: Run the full suite to confirm no regression**

Run: `swift test --package-path macDesktops/ParallelDesktops`
Expected: PASS (existing 26 tests + 4 new = 30).

- [ ] **Step 8: Commit**

```bash
cd /Users/shrikantvarma/Code
git add macDesktops/ParallelDesktops/Sources/ParallelDesktopsCore/SpacesEngine/CGSPrivate.swift \
        macDesktops/ParallelDesktops/Sources/ParallelDesktopsCore/SpacesEngine/SpacesProvider.swift \
        macDesktops/ParallelDesktops/Sources/ParallelDesktops/AppModel.swift \
        macDesktops/ParallelDesktops/Tests/ParallelDesktopsCoreTests/CoreTests.swift
git commit -m "fix(spaces): treat a desktop on any display as present (no false drift)

Drift now uses the union of user spaces across ALL displays, so moving a
desktop to a second screen no longer false-flags the project as drifted.
Adds SpacesProvider.allUserSpaceUUIDs() (default = single-display) behind
the existing read seam; CGSSpacesProvider unions CGS.allDisplays().

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XqLfZbZRyHRKWXdw5csiVB"
```

---

## Part 2 (authored after Task 1's gate result)

Written from `Spike/SPIKE-multidisplay.md`. Scope:
- **Focused-display current space** — `SpacesProvider.focusedCurrentSpaceUUID()` via `CGSGetActiveSpace` (matched to a UUID), with a primary-display fallback. Fixes `recalibrate` / `recomputeCurrent` binding to the wrong screen.
- **Switch engine** — resolve UUID → `(display, managedSpaceID)`; **Approach A** (direct `CGSManagedDisplaySetCurrentSpace` + per-display verification, drops `notKeyable`/Ctrl+N) if the gate PASSED, else **Approach B** (focus target display, then Ctrl+N within its ordering).
- Multi-display acceptance pass on the two-display Mac.

## Self-review notes
- Spec coverage: §"Drift" + the false-drift symptom → Task 2. §"Load-bearing risk" / Phase 0 → Task 1. §"Read seam" `currentSpaceUUID` focused-display, §"Switch engine", §"AppModel recalibrate" → Part 2 (gated, intentionally deferred). §"CGS layer allDisplays()" → Task 2 Step 4.
- No placeholders: every code step shows full content; the only "fill-in" is the spike *results* file, which is data the run produces, not code.
- Type consistency: `allUserSpaceUUIDs() -> [String]` defined once (protocol) and used identically in fake, default, CGS impl, and `recomputeDrift`. `directSetCurrentSpace(displayID:spaceID:)` / `activeSpaceID()` are spike-only and not referenced by app tasks.
