# Parallel Project Desktops — Backlog

Open work after the v1 MVP build + code review (2026-06-21). Nothing here is
blocking daily use. Plan: `docs/plans/2026-06-21-001-feat-parallel-project-desktops-plan.md`.

## From the code review (P2/P3 — reported, not yet applied)

- **Switch correctness (P2)** — `RealDesktopEngine`: verify loop can credit a
  *concurrent user* switch as success; Secure Input checked once (TOCTOU).
  Fix: assert `previous != target` before posting; re-check `IsSecureEventInputEnabled()`
  on `verificationFailed` and downgrade to the secureInput branch.
- **Reachability (P2)** — a project whose desktop ordinal has no enabled Ctrl+N
  shortcut shows "ready" but fails on click; desktops 10+ are unswitchable.
  Fix: per-project keyability badge (like the drift triangle); cap or warn at ordinal 9.
- **Drift scope (P2)** — `recomputeDrift` only catches *removed* desktops; reorder/added
  shifts and the type-0-only ordinal assumption (fullscreen / multi-display) go
  undetected. Verify the OS's "Switch to Desktop N" ordering basis, then handle reorder.
- **Testability (P2)** — extract `AppModel.bringUpApps` launch/reopen/report routing
  into Core so it's unit-testable (it's in the executable target today); add
  `ProjectStore.update`/`remove`/`project(forSpaceUUID:)` tests.
- **Hygiene (P3)** — `GlobalHotKey` leaks its static `instances` entry, never
  `RemoveEventHandler`, and ignores `InstallEventHandler` status + nil-on-failure
  (search hotkey could be silently dead — surface to status). Unstructured
  `enter()`/`bringUpApps()` Tasks race on `status` (cancel in-flight before new).

## Known feature gaps (v1 scope)

- **Note-on-leave (R11)** — the resume card *displays* a note, but there's no UI to
  *type* "where I stopped" on leaving. Plumbing exists; input field doesn't.
- **Label picker (R1)** — projects default to 🗂; no emoji/color chooser.
- **Reliability gates a/b/c/e/f** — measure via the spike's run-N (see `Spike/SPIKE.md`);
  only gate (d), UUID-survives-reboot, has been verified.

## Known macOS quirks (not app bugs — parked)

- **Mission-Control Space-drag strands windows off-screen (P3, macOS bug).** Dragging a
  desktop between displays in Mission Control with "Displays have separate Spaces" ON
  moves the Space but can fail to re-clamp its windows — observed a window flung to
  x≈−1062 (off-screen left), exactly a full virtual-desktop-width shift (`placedX − totalSpan`).
  The app's code never runs during a native MC drag, so this is pure macOS behavior, not
  our placement logic (verified 2026-06-26 alongside the cross-display open fix). Optional
  future defense: on `didChangeScreenParameters`/`activeSpaceDidChange`, scan the project's
  windows and AX-clamp any that landed off-screen back onto a visible display (we now have
  the AX primitives via `WindowPlacer`). Workaround today: use the app's relocate action
  instead of dragging, or re-position the window manually.

## Deferred (plan Scope Boundaries / macOS limits)

- Window-layout restore & moving a window across Spaces (needs SIP-off on macOS 26 —
  confirmed infeasible for a normal app; see `docs/solutions/integration-issues/`).
- Overview wall, park/unpark shelf, auto-learn app set, widget, EmulatedWorkspaceEngine,
  multi-display.

## Distribution / hardening (when ready)

- Developer ID cert + `notarytool` creds → `./make-dmg.sh` for a downloadable DMG (see `BUILD.md`).
- Swift 6 strict concurrency (currently language mode v5); migrate to an Xcode project for signing.
