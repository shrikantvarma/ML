# feat: Capture open browser tabs into a project

**Branch:** `feat/multi-display-spaces` (or a fresh `feat/capture-tabs`) · **Package:** `ParallelDesktops/`
**Depth:** Standard · Paths relative to the `macDesktops/` project root.
**Authored in ce-plan format directly (context-budget); execute with `/ce-work`.**

## Problem Frame

A project is only as recoverable as its **saved links**. Today links are added manually, so
when a desktop's live windows are lost (iPad/Sidecar disconnect, reboot, churned Space UUID)
the open tabs that *defined* the project are gone — the app can only re-open what was already
saved as a `Link`. Users expect "my project's tabs" to survive. We need a way to **capture the
currently-open browser tabs into a project's blueprint** so the recipe stays complete.

(macOS reality, unchanged: we cannot move/restore live windows — see the all-desktops spec's
hard constraints. This plan makes the *recipe* complete so reconstruction is faithful, which is
the only durable path available.)

## Key Technical Decisions

- **Capture is explicit (opt-in) in v1, not automatic.** A "Capture open tabs" action on a
  project, not a silent on-switch-away grab. Rationale: auto-capturing every URL you visit is a
  privacy surface and a surprise; explicit capture is predictable and permission-friendly.
  Auto-capture-on-leave is a deferred follow-up gated behind a setting.
- **Chrome only in v1** (the app is already Chrome-centric: profiles, the launch recipe). Safari/
  Arc/Edge are deferred — each needs its own scripting bridge.
- **Read tabs via AppleScript** (`tell application "Google Chrome" to get {URL, title} of tabs …`)
  through `NSAppleScript`/`osascript`. This requires the **Automation (Apple Events) TCC
  permission** to control Chrome — a new first-use prompt. Handle denial gracefully with an
  actionable message (like the Accessibility/shortcut hints).
- **Scope = all Chrome windows of the matching profile, deduped.** AppleScript can't map a window
  to a macOS Space, so we can't reliably capture "only this desktop's" tabs. v1 captures the
  project's-profile Chrome tabs (or all Chrome tabs if no profile pinned), deduped against
  existing links, capped. Document the limitation.
- **Merge into `blueprint.links`** as `Link(url:title:)`, reusing the existing `LinkURL.isAllowed`
  filter (so only http/https get captured) and dedup by URL; respect a sane cap (e.g. 50).

## Implementation Units

### U1. ChromeTabReader — read open Chrome tabs (IO wrapper)
**Goal:** A `System/` wrapper that returns open Chrome tabs as `[(url, title)]` via AppleScript,
graceful when Chrome isn't running or Automation permission is denied (returns empty + a
distinguishable "permission denied" signal).
**Files:** Create `ParallelDesktops/Sources/ParallelDesktopsCore/System/ChromeTabReader.swift`.
**Approach:** `NSAppleScript` querying `URL`/`title of tabs of windows`; optional profile filter
if feasible (Chrome AppleScript exposes window/tab, not profile — likely capture all and note it).
Mirror `BrowserLauncher`/`SystemURLOpener` IO style; behind a protocol so AppModel can fake it.
**Test expectation:** none for the AppleScript call (IO, manual). If result *parsing* is factored
into a pure function, unit-test that against sample AppleScript descriptor output.
**Verification:** with Chrome open, returns the live tab URLs; denied permission → empty + flag.

### U2. Merge logic — capture tabs into a project's links (pure)
**Goal:** A pure `BlueprintLinks.merge(existing:captured:)` that filters via `LinkURL.isAllowed`,
dedups by URL (case-insensitive, normalized), preserves order (existing first, then new), and
caps the total.
**Files:** Create a pure helper (e.g. `Model/LinkCapture.swift`); Test: `CoreTests.swift`.
**Approach:** pure function over `[Link]` + `[(url,title)]` → `[Link]`.
**Test scenarios:** dedup against existing; drop disallowed schemes (`javascript:`, `chrome://`);
preserve order; cap at N; empty captured → unchanged; title fallback to host when blank.
**Verification:** `LinkCaptureTests` green.

### U3. AppModel + UI — the capture action
**Goal:** `captureOpenTabs(into:)` on AppModel (reads via U1, merges via U2, persists,
reloadProjects); a "Capture open tabs" item in the project `•••` menu; actionable status on
permission-denied (deep-link to Privacy & Security → Automation).
**Files:** Modify `AppModel.swift`, `MenuBarListView.swift`.
**Test expectation:** none (IO/UI, manual); the merge it relies on is covered by U2.
**Verification:** click "Capture open tabs" → project's links gain the open Chrome tabs (deduped);
denied permission shows the actionable hint.

### U4. (Deferred) auto-capture on switch-away + setting
Capture into the outgoing project's blueprint in the existing `activeSpaceDidChange` persist path,
behind an opt-in toggle. Deferred: privacy + needs a settings surface.

### U5. Manual acceptance
Chrome open with several tabs → capture → links populated, deduped, http/https only; works with
a pinned profile; Automation-permission prompt appears first time and denial is handled; reopen
the project later (Open links) reconstructs the captured tabs on the target desktop.

## Scope Boundaries
**In:** explicit Chrome tab capture (U1–U3, U5). **Deferred:** auto-capture-on-leave + setting
(U4); non-Chrome browsers; per-desktop tab scoping (AppleScript can't map windows to Spaces);
restoring live window layout (macOS can't).

## Risks
- **Automation TCC permission** is a new prompt; if denied, capture silently returns nothing —
  must be surfaced actionably (reuse the hint pattern).
- **Privacy:** capturing URLs is sensitive; explicit-only in v1 mitigates. Document that captured
  URLs are stored in `projects.json` (same store, same local trust boundary).
- **Profile scoping** imperfect — may capture tabs from the wrong Chrome profile/window set;
  document and revisit if it bites.
- **AppleScript fragility** across Chrome versions; guard all descriptor access, fail soft.
