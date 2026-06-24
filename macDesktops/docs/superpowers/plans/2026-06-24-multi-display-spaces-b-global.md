# Multi-Display Spaces (B-global) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans (or `/ce-work`) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make each native macOS desktop (Space) a per-screen, independent Project that works on any display with "Displays have separate Spaces" ON — switch to a Project's desktop on any display, no false drift for secondary-display desktops, and recalibrate to the screen the user is actually on.

**Architecture:** The switch mechanism is **B-global**: keep v1's synthesized "Switch to Desktop N" (Ctrl+N), but compute the target's **global index** = its position in the ordered list of user desktops across ALL displays (Ctrl+N numbering is global on macOS 26 and matches `CGSCopyManagedDisplaySpaces` order — gate-proven). Identity stays the **Space UUID**; the index is re-derived each switch. Everything lives behind the existing `SpacesProvider` (read) and `SwitchEngine` (switch) seams, so the change is contained and unit-testable against fakes.

**Tech Stack:** Swift 6, SwiftPM, XCTest, private SkyLight symbols via `dlsym`.

## WORKSPACE & FALLBACK (read first — fresh session has no prior context)

- **Work in the worktree:** `~/Code-wt/macDesktops-md/macDesktops` — branch `feat/multi-display-spaces` (sparse-checkout of `macDesktops/` only; the git root is the `~/Code` monorepo).
- **SwiftPM package:** `~/Code-wt/macDesktops-md/macDesktops/ParallelDesktops`. Run tests with `swift test --package-path <that path>`.
- **Fallback to the current working v1:** tag `v1-single-display-baseline`, and the untouched `full-app-mvp` checkout at `~/Code/macDesktops`. Never edit `~/Code/macDesktops` for this feature.
- **Baseline is green:** 63 tests pass before any change.
- **Gate evidence & rationale:** `macDesktops/Spike/SPIKE-multidisplay.md` and `docs/solutions/architecture-patterns/multi-display-spaces-identity-and-spike-strategy.md` (guidance #2 = why B-global over direct CGS; #5 = two desktop classes). Design banner: `docs/superpowers/specs/2026-06-23-multi-display-spaces-support-design.md`.

## Global Constraints

- Target OS macOS 26.x; "Displays have separate Spaces" ON. macOS 26 does NOT let you drag a Space between displays — topology churns only on display add/remove.
- All private symbols resolved at runtime via `dlsym`, graceful when missing (existing `CGSPrivate.swift` pattern). No SIP changes required of users.
- **Empty-UUID guard from day one.** macOS returns `uuid: ""` for some real desktops (and this parser maps a missing key to `"?"`). NEVER bind, match, return, or treat as "current" a non-trackable uuid. Single predicate: `SpaceIdentity.isTrackable(uuid) == (!uuid.isEmpty && uuid != "?")`. Empty desktops are untrackable and cannot host Projects (proven: their id64 also churns across reconnect — no fallback key).
- **The global index counts ALL user desktops including empties** (macOS numbers them), but identity/drift only ever match trackable uuids. These are two different lists — keep them distinct.
- TDD: failing test first for every non-IO change. Pure logic (index, drift, engine branches) is fully unit-testable with fakes; the thin CGS wrappers are verified by manual acceptance (Task 6).
- ~9-desktop cap now applies to the TOTAL across displays (Ctrl+1–9). `globalIndex > 9` ⇒ `.notKeyable`. Accepted for MVP.
- Conventional commits. Do NOT push. Branch `feat/multi-display-spaces`.

---

## Current seam signatures (baseline, do not assume otherwise)

```swift
// SpacesProvider.swift
public protocol SpacesProvider {
    func orderedUserSpaceUUIDs() -> [String]   // primary display only, ordered (may contain ""/"?")
    func currentSpaceUUID() -> String?         // primary display's current
}
public extension SpacesProvider {
    func resolveIndex(uuid: String) -> Int? {  // 1-based index within orderedUserSpaceUUIDs
        guard let i = orderedUserSpaceUUIDs().firstIndex(of: uuid) else { return nil }
        return i + 1
    }
}
public struct CGSSpacesProvider: SpacesProvider { /* uses CGS.primaryDisplay() */ }

// CGSPrivate.swift — enum CGS: managedDisplaySpaces() -> [DisplaySpaces]?, primaryDisplay()
//   struct SpaceInfo { let uuid: String; let managedSpaceID: Int64; let type: Int }
//   struct DisplaySpaces { let displayIdentifier: String; let spaces: [SpaceInfo]
//                          let currentSpaceUUID: String?; var userSpaces: [SpaceInfo] }  // type==0

// SwitchEngine.swift
public enum BlockReason: Equatable { case secureInput, shortcutDisabled }
public enum SwitchResult: Equatable {
    case switched(latencyMs: Int); case driftDetected; case notKeyable(index: Int)
    case blocked(BlockReason); case verificationFailed
}
public protocol SwitchEngine { func `switch`(toSpaceUUID uuid: String) async -> SwitchResult }

// RealDesktopEngine.switch: resolveIndex(uuid) → guard ≤9 → secureInput/shortcut checks →
//   poster.postControlNumber(index) → poll currentSpaceUUID()==uuid until timeout.
// KeyPosting.postControlNumber(_ n: Int); DriftDetector.driftedUUIDs(bound:in:) -> [String]
// AppModel: spaces=CGSSpacesProvider(); engine=RealDesktopEngine(spaces:); recomputeCurrent uses
//   currentSpaceUUID(); recomputeDrift uses orderedUserSpaceUUIDs(); recalibrate/capture use currentSpaceUUID().
```

---

### Task 1: Identity guard + multi-display read-seam (pure, fakeable)

Adds the empty-UUID guard and the multi-display read methods to the `SpacesProvider` protocol with single-display defaults, so existing fakes and `CGSSpacesProvider` keep compiling and single-display behavior is unchanged.

**Files:**
- Modify: `ParallelDesktops/Sources/ParallelDesktopsCore/SpacesEngine/SpacesProvider.swift`
- Test: `ParallelDesktops/Tests/ParallelDesktopsCoreTests/CoreTests.swift`

**Interfaces — Produces:**
```swift
public enum SpaceIdentity { public static func isTrackable(_ uuid: String) -> Bool }

public protocol SpacesProvider {
    // existing: orderedUserSpaceUUIDs(), currentSpaceUUID()
    func globalDesktopUUIDs() -> [String]      // ALL displays, ordered, INCLUDING empties (Ctrl+N positions)
    func focusedCurrentSpaceUUID() -> String?  // focused display's current (trackable only)
    func isSpaceCurrent(uuid: String) -> Bool  // is uuid the current space of ANY display
}
public extension SpacesProvider {
    func globalDesktopUUIDs() -> [String] { orderedUserSpaceUUIDs() }       // single-display default
    func focusedCurrentSpaceUUID() -> String? { currentSpaceUUID() }
    func isSpaceCurrent(uuid: String) -> Bool { currentSpaceUUID() == uuid }
    func allTrackableUserSpaceUUIDs() -> [String]                           // drift "present" set
    func globalIndex(uuid: String) -> Int?                                  // Ctrl+N index, counts empties
}
```

- [ ] **Step 1 — failing tests.** Add to `CoreTests.swift`:
```swift
final class SpaceIdentityTests: XCTestCase {
    func testTrackable() {
        XCTAssertTrue(SpaceIdentity.isTrackable("A1B2"))
        XCTAssertFalse(SpaceIdentity.isTrackable(""))
        XCTAssertFalse(SpaceIdentity.isTrackable("?"))
    }
}
// Fake spanning displays; perDisplay rows are ordered, "" marks an empty-uuid desktop.
final class FakeMultiDisplaySpaces: SpacesProvider {
    let perDisplay: [[String]]; let focused: String?; let currents: [String]
    init(perDisplay: [[String]], focused: String?, currents: [String]) {
        self.perDisplay = perDisplay; self.focused = focused; self.currents = currents
    }
    func orderedUserSpaceUUIDs() -> [String] { perDisplay.first ?? [] }
    func currentSpaceUUID() -> String? { currents.first }
    func globalDesktopUUIDs() -> [String] { perDisplay.flatMap { $0 } }
    func focusedCurrentSpaceUUID() -> String? { focused }
    func isSpaceCurrent(uuid: String) -> Bool { SpaceIdentity.isTrackable(uuid) && currents.contains(uuid) }
}
final class MultiDisplayReadTests: XCTestCase {
    func testGlobalIndexCountsEmptiesButOnlyMatchesTrackable() {
        // display 1 has an empty desktop at position 4; "C" is global #5.
        let s = FakeMultiDisplaySpaces(perDisplay: [["A","B","C0"], ["", "C"]], focused: "A", currents: ["A","C"])
        XCTAssertEqual(s.globalIndex(uuid: "C"), 5)   // counts the empty at index 4
        XCTAssertEqual(s.globalIndex(uuid: "A"), 1)
        XCTAssertNil(s.globalIndex(uuid: ""))          // never index an empty
        XCTAssertNil(s.globalIndex(uuid: "ZZ"))        // absent
    }
    func testAllTrackableExcludesEmpties() {
        let s = FakeMultiDisplaySpaces(perDisplay: [["A","B"], ["", "C"]], focused: "A", currents: ["A","C"])
        XCTAssertEqual(s.allTrackableUserSpaceUUIDs(), ["A","B","C"])
    }
    func testDefaultsFallBackToSingleDisplay() {
        let s = FakeSpaces(ordered: ["A","B"], current: "A")   // existing single-display fake
        XCTAssertEqual(s.globalDesktopUUIDs(), ["A","B"])
        XCTAssertEqual(s.focusedCurrentSpaceUUID(), "A")
        XCTAssertTrue(s.isSpaceCurrent(uuid: "A")); XCTAssertFalse(s.isSpaceCurrent(uuid: "B"))
    }
}
```
*(If the existing single-display fake isn't named `FakeSpaces(ordered:current:)`, match its real name/initializer — check `CoreTests.swift`.)*

- [ ] **Step 2 — run, expect FAIL to compile** (`SpaceIdentity` / new methods undefined).
  `swift test --package-path ParallelDesktops --filter "SpaceIdentityTests|MultiDisplayReadTests"`

- [ ] **Step 3 — implement** in `SpacesProvider.swift`:
```swift
public enum SpaceIdentity {
    /// macOS returns "" for some real desktops; this parser maps a missing key to "?".
    /// Binding/matching either sentinel collides across every such desktop — never allow it.
    public static func isTrackable(_ uuid: String) -> Bool { !uuid.isEmpty && uuid != "?" }
}
```
Add to the protocol: `func globalDesktopUUIDs() -> [String]`, `func focusedCurrentSpaceUUID() -> String?`, `func isSpaceCurrent(uuid: String) -> Bool`. Add to the `public extension`:
```swift
func globalDesktopUUIDs() -> [String] { orderedUserSpaceUUIDs() }
func focusedCurrentSpaceUUID() -> String? { currentSpaceUUID() }
func isSpaceCurrent(uuid: String) -> Bool { currentSpaceUUID() == uuid }
/// Trackable user desktops across all displays — the "present" set for drift.
func allTrackableUserSpaceUUIDs() -> [String] { globalDesktopUUIDs().filter { SpaceIdentity.isTrackable($0) } }
/// 1-based Ctrl+N index = position in the FULL ordered list (empties counted, macOS numbers them).
func globalIndex(uuid: String) -> Int? {
    guard SpaceIdentity.isTrackable(uuid), let i = globalDesktopUUIDs().firstIndex(of: uuid) else { return nil }
    return i + 1
}
```

- [ ] **Step 4 — run, expect PASS.** Same filter as Step 2.
- [ ] **Step 5 — commit** `feat(spaces): identity guard + multi-display read seam (defaults preserve single-display)`.

---

### Task 2: CGS multi-display read implementation

Wire the real CGS read for all displays + the focused-display active space, and override the new seam methods in `CGSSpacesProvider`. (Thin IO wrappers — verified by Task 6 manual acceptance; the index/guard logic they feed is already unit-tested in Task 1.)

**Files:**
- Modify: `ParallelDesktops/Sources/ParallelDesktopsCore/SpacesEngine/CGSPrivate.swift`
- Modify: `ParallelDesktops/Sources/ParallelDesktopsCore/SpacesEngine/SpacesProvider.swift` (`CGSSpacesProvider`)

- [ ] **Step 1 — CGS additions** (`CGSPrivate.swift`, mirror the existing `sym(...)` pattern):
```swift
private typealias GetActiveSpaceFn = @convention(c) (CGSConnectionID) -> Int
private static let getActiveSpace = sym("CGSGetActiveSpace", as: GetActiveSpaceFn.self)

/// All displays with their ordered Spaces (empty if a symbol is unavailable).
static func allDisplays() -> [DisplaySpaces] { managedDisplaySpaces() ?? [] }

/// Globally-active space id (focused display). nil if symbol absent.
static func activeSpaceID() -> Int? {
    guard let conn = connectionID, let fn = getActiveSpace else { return nil }
    return fn(conn)
}

/// Focused display's current space uuid (via CGSGetActiveSpace → managedSpaceID match).
/// Falls back to the primary display's current if the symbol is missing. nil if untrackable.
static func focusedCurrentSpaceUUID() -> String? {
    guard let active = activeSpaceID() else { return primaryDisplay()?.currentSpaceUUID }
    for d in allDisplays() {
        for s in d.spaces where Int(s.managedSpaceID) == active {
            return s.uuid.isEmpty || s.uuid == "?" ? nil : s.uuid
        }
    }
    return primaryDisplay()?.currentSpaceUUID
}
```
*(Optional hardening, separate commit if desired: resolve `SLS*` names before `CGS*` — gate-proven they resolve on 26.4.1 and SkyLight is the more future-proof namespace. Not required for MVP.)*

- [ ] **Step 2 — `CGSSpacesProvider` overrides** (`SpacesProvider.swift`):
```swift
public func globalDesktopUUIDs() -> [String] {
    CGS.allDisplays().flatMap { $0.userSpaces.map { $0.uuid } }   // includes ""/"?"; index needs them
}
public func focusedCurrentSpaceUUID() -> String? {
    CGS.focusedCurrentSpaceUUID().flatMap { SpaceIdentity.isTrackable($0) ? $0 : nil }
}
public func isSpaceCurrent(uuid: String) -> Bool {
    guard SpaceIdentity.isTrackable(uuid) else { return false }
    return CGS.allDisplays().contains { $0.currentSpaceUUID == uuid }
}
```

- [ ] **Step 3 — build** `swift build --package-path ParallelDesktops` (expect clean; `MISSING` symbol is a runtime finding, not a build error).
- [ ] **Step 4 — commit** `feat(cgs): all-displays read + focused-display active space (CGSGetActiveSpace)`.

---

### Task 3: Drift uses the all-displays union (kills false "desktop moved")

**Files:**
- Modify: `ParallelDesktops/Sources/ParallelDesktops/AppModel.swift` (`recomputeDrift`, ~line 151)
- Test: `ParallelDesktops/Tests/ParallelDesktopsCoreTests/CoreTests.swift`

- [ ] **Step 1 — failing tests** (DriftDetector against the union; uses `FakeMultiDisplaySpaces` from Task 1):
```swift
final class MultiDisplayDriftTests: XCTestCase {
    func testDesktopOnSecondaryIsNotDrifted() {
        let s = FakeMultiDisplaySpaces(perDisplay: [["A","B"], ["C"]], focused: "A", currents: ["A","C"])
        XCTAssertEqual(DriftDetector.driftedUUIDs(bound: ["A","C"], in: s.allTrackableUserSpaceUUIDs()), [])
    }
    func testDeletedDesktopStillDrifts() {
        let s = FakeMultiDisplaySpaces(perDisplay: [["A"], ["C"]], focused: "A", currents: ["A","C"])
        XCTAssertEqual(DriftDetector.driftedUUIDs(bound: ["A","Z"], in: s.allTrackableUserSpaceUUIDs()), ["Z"])
    }
}
```
- [ ] **Step 2 — run, expect PASS already** (these exercise Task 1's `allTrackableUserSpaceUUIDs`; they lock the contract). If they fail, fix Task 1.
- [ ] **Step 3 — wire `recomputeDrift`** in `AppModel.swift`: replace the `let ordered = spaces.orderedUserSpaceUUIDs()` present-set with `let present = spaces.allTrackableUserSpaceUUIDs()` and pass `present` to `DriftDetector.driftedUUIDs(bound:in:)`. Keep `orderedSnapshot = spaces.orderedUserSpaceUUIDs()` if other code reads it, or update to the union if appropriate (check usages of `orderedSnapshot`).
- [ ] **Step 4 — full suite** `swift test --package-path ParallelDesktops` (expect green).
- [ ] **Step 5 — commit** `fix(drift): treat a desktop on any display as present (no false drift)`.

---

### Task 4: Switch engine → global index + multi-display verification

`RealDesktopEngine` keeps the Ctrl+N mechanism but resolves the **global** index and verifies against **any display's** current space. Single-display behavior is preserved (one display ⇒ `globalIndex == resolveIndex`, `isSpaceCurrent == currentSpaceUUID()==uuid`).

**Files:**
- Modify: `ParallelDesktops/Sources/ParallelDesktopsCore/SpacesEngine/RealDesktopEngine.swift`
- Test: `ParallelDesktops/Tests/ParallelDesktopsCoreTests/CoreTests.swift` (existing `SwitchEngineTests` + new cases)

- [ ] **Step 1 — failing tests.** Extend the switch-engine fake to model multiple displays via `globalDesktopUUIDs`/`isSpaceCurrent` and assert:
```swift
final class MultiDisplaySwitchTests: XCTestCase {
    // Reuse the engine's existing recording poster + injected spaces fake.
    func testSwitchesByGlobalIndexOnSecondaryDisplay() async {
        // target "C" is global #4 (3 on display 0, C is first on display 1)
        // Build a spaces fake where globalDesktopUUIDs()=["A","B","C0","C"], isSpaceCurrent("C") flips true
        // after postControlNumber(4) is recorded. Assert result == .switched and the poster saw index 4.
    }
    func testNotKeyableWhenGlobalIndexBeyondNine() async { /* 10 desktops total ⇒ .notKeyable(10) */ }
    func testDriftWhenUUIDAbsentFromAllDisplays() async { /* globalIndex nil ⇒ .driftDetected, nothing posted */ }
    func testUntrackableTargetIsDrift() async { /* switch(toSpaceUUID: "") ⇒ .driftDetected, nothing posted */ }
}
```
Model the fakes on the existing `SwitchEngineTests` ones (a recording `KeyPosting`, injectable `secureInput`/`shortcutEnabled`, and a `SpacesProvider` whose `isSpaceCurrent` becomes true once the expected index is posted).

- [ ] **Step 2 — run, expect FAIL** (engine still uses `resolveIndex`/`currentSpaceUUID`).
- [ ] **Step 3 — implement.** In `RealDesktopEngine.switch(toSpaceUUID:)`:
  - first line: `guard SpaceIdentity.isTrackable(uuid) else { return .driftDetected }`
  - `guard let index = spaces.globalIndex(uuid: uuid) else { return .driftDetected }`
  - already-on-target: `if spaces.isSpaceCurrent(uuid: uuid) { return .switched(latencyMs: 0) }`
  - keep `guard index <= 9 else { return .notKeyable(index: index) }`, secureInput, shortcutEnabled checks
  - `poster.postControlNumber(index)`
  - poll: `if spaces.isSpaceCurrent(uuid: uuid) { return .switched(...) }`
  - timeout: re-check secureInput, else `.verificationFailed`
- [ ] **Step 4 — run new + existing `SwitchEngineTests`, expect PASS** (single-display tests must still pass — defaults make `globalIndex`/`isSpaceCurrent` equal the old behavior).
- [ ] **Step 5 — commit** `feat(switch): global Ctrl+N index + any-display verification (B-global)`.

---

### Task 5: AppModel focused-display semantics (current + recalibrate + capture)

Resolve "current project", recalibrate, and "save this desktop" against the **focused** display, guarding empties.

**Files:**
- Modify: `ParallelDesktops/Sources/ParallelDesktops/AppModel.swift` (`recomputeCurrent` ~148; `recalibrate` ~303; the capture/save path that reads `currentSpaceUUID()` ~93/167/204)

- [ ] **Step 1 — change reads.** Replace `spaces.currentSpaceUUID()` with `spaces.focusedCurrentSpaceUUID()` in: `recomputeCurrent`, `recalibrate`, and the capture/"save this desktop as a Project" path. At each *bind* site (recalibrate, capture) add an empty guard so an untrackable focused desktop can't become a Project:
```swift
guard let uuid = spaces.focusedCurrentSpaceUUID(), SpaceIdentity.isTrackable(uuid) else {
    // surface a clear "this desktop can't be saved yet (no stable id)" status; do NOT bind.
    return
}
```
  (For `recomputeCurrent`, no guard needed — `focusedCurrentSpaceUUID()` already returns nil for untrackable, so `currentProject` becomes nil.)
- [ ] **Step 2 — verify no behavioral regression on single display.** `focusedCurrentSpaceUUID()` defaults to `currentSpaceUUID()`, and `CGSSpacesProvider.focusedCurrentSpaceUUID()` falls back to the primary display's current when `CGSGetActiveSpace` is absent — so single-display is unchanged.
- [ ] **Step 3 — full suite** `swift test --package-path ParallelDesktops` (green).
- [ ] **Step 4 — commit** `feat(model): focused-display current/recalibrate/capture with empty-uuid guard`.

---

### Task 6: Manual acceptance on the real two-display rig

Not unit-testable (real WindowServer). Drive on the 2-display Mac, separate Spaces ON, "Switch to Desktop N" shortcuts enabled.

- [ ] Build & run the app from the worktree; bind a Project on a desktop on **each** display.
- [ ] **Switch** to each Project from the other screen → lands on the right desktop on the right display (focus follows to that screen — expected).
- [ ] **No false drift**: a Project on the secondary display is never flagged drifted; unplug/replug the second display and confirm its Projects still resolve (found via the all-displays union).
- [ ] **Recalibrate** while focused on the secondary display binds to that screen's desktop, not display 0.
- [ ] **Empty-uuid guard**: produce an empty desktop (reconnect a display) and confirm it can't be saved as a Project and never shows as a wrong "current".
- [ ] **>9 total desktops** ⇒ the 10th surfaces `.notKeyable` cleanly (clear message, no crash).
- [ ] (Pre-ship nicety) confirm the switched display's menu bar is clean on a **physical** monitor (gate de-risked this on Sidecar + via the "normal switching = clean" observation).
- [ ] Commit any fixes; then run `superpowers:verification-before-completion`.

---

## Self-review notes
- **Spec coverage:** read seam union → Tasks 1–2; false-drift fix → Task 3; switch mechanism (B-global global index) → Task 4; focused-display current/recalibrate → Task 5; empty-UUID guard → Tasks 1,4,5 (every bind/match/return/index site); manual acceptance → Task 6.
- **The empties subtlety is explicit:** `globalIndex` counts the full list (incl. empties) to match macOS Ctrl+N; `allTrackableUserSpaceUUIDs` (drift) excludes them. Two lists, defined once in Task 1, used consistently.
- **Type consistency:** `globalDesktopUUIDs`/`focusedCurrentSpaceUUID`/`isSpaceCurrent`/`allTrackableUserSpaceUUIDs`/`globalIndex`/`SpaceIdentity.isTrackable` are defined once (Task 1) and used identically in Tasks 2–5.
- **No regression:** all new protocol methods have single-display defaults; existing `SwitchEngineTests` must stay green after Task 4.
</content>
