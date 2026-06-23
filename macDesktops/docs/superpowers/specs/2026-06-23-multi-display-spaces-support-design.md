# Multi-Display Spaces Support — Design

**Date:** 2026-06-23
**Status:** Approved (brainstorm) — pending spec review
**Branch:** `full-app-mvp`
**Related:** `docs/plans/2026-06-21-001-feat-parallel-project-desktops-plan.md` (Risk R-4 deferred multi-display)

## Problem

When a second display is connected with macOS **"Displays have separate Spaces" ON**
(`com.apple.spaces spans-displays = 0`, confirmed on this machine), the app breaks:

- Desktops moved to the secondary display are **falsely flagged as drifted**
  ("desktop has moved — Recalibrate").
- The Ctrl+N **desktop numbers shift and stop matching** the bound spaces.
- **Recalibrate binds to the wrong screen**, making things worse.

### Root cause

The entire read/switch layer is scoped to a single display by construction. Three chokepoints:

- `CGSPrivate.swift:62` — `primaryDisplay()` returns only `managedDisplaySpaces()?.first`,
  discarding every other display (CGS already returns all of them).
- `SpacesProvider.swift:27,30` — `orderedUserSpaceUUIDs()` / `currentSpaceUUID()` read only
  the primary display.
- Switching posts **Ctrl+digit** (`KeyEventPoster.swift:24`). With separate Spaces, the CGS
  per-display ordering no longer matches Mission Control's global Ctrl+N numbering, so even a
  correctly computed index can target the wrong desktop.

The **data model is sound** — project→UUID bindings are intact and UUIDs are stable (U1 reboot
gate). The bug lives entirely in the read/switch layer.

## Goal

A project can live on **any desktop on any display**. Switching, drift detection, and
recalibration all work correctly regardless of which display a desktop is on — including the
"Project A on the external monitor while Project B stays on the laptop" workflow that *requires*
separate Spaces to remain ON (so disabling the OS setting is explicitly **not** an acceptable fix).

## Non-goals

- Moving desktops/windows *between* displays programmatically (that needs a scripting addition / SIP changes).
- Mirrored-display or "one big spanning desktop" (`spans-displays = 1`) handling — that case already
  collapses to the working single-display model.
- UI redesign beyond minimal multi-display affordances.

## Load-bearing risk & decision

The chosen approach (**A: direct CGS space-switch**) depends on a private SkyLight symbol that
sets the active space on a given display (e.g. `CGSManagedDisplaySetCurrentSpace` /
`SLSSpaceSetCurrentSpace`). Apple has progressively locked Spaces manipulation down on modern
macOS; whether a *no-SIP, synthetic-key-free* direct switch still works on **macOS 26.4.1** is
unproven. The U1 spike validated the *read* symbols only.

**Therefore the work is spike-gated** (Phase 0). The gate outcome selects the implementation:

| | Approach A — direct CGS switch (preferred) | Approach B — focus-display + Ctrl+N (fallback) |
|---|---|---|
| Switch mechanism | Call private "set current space" by managed space ID | Programmatically focus the target display, then post Ctrl+N within its ordering |
| Numbering problem | Eliminated (no index/Ctrl+N) | Still present; mitigated by per-display indexing |
| 9-desktop limit | Removed | Retained |
| Risk | New private symbol may not work on macOS 26 | "Focus a display" is itself a hack; Ctrl+N across separate Spaces is unreliable |
| Selected when | Phase 0 gate **passes** | Phase 0 gate **fails** |

## Architecture

Existing protocol seams (`SpacesProvider`, `SwitchEngine`) already isolate the single-display
assumption to two implementations plus a few AppModel call sites. The change is contained.

### 1. CGS layer — `CGSPrivate.swift`
- Replace `primaryDisplay()` with `allDisplays() -> [DisplaySpaces]` (data already gathered by
  `managedDisplaySpaces()`).
- Add the direct space-switch symbol resolved via `dlsym`, plus a
  `setCurrentSpace(managedSpaceID:onDisplay:) -> Bool` wrapper. Missing symbol ⇒ graceful
  failure, never a link error (same pattern as existing read symbols).
- Add a way to identify the **focused display** (the display the user is currently interacting
  with) so "current desktop" is well-defined on multi-display.

### 2. Read seam — `SpacesProvider`
- `orderedUserSpaceUUIDs()` returns the **union of user spaces across all displays** (so a
  desktop that moved screens is still "present").
- Add lookup: UUID → `(displayID, managedSpaceID)`.
- `currentSpaceUUID()` returns the **focused display's** current space (per-display semantics).
- Default `resolveIndex` stays for display/labels but is no longer the switch mechanism under A.

### 3. Drift — `DriftDetector`
- No logic change; it already operates on a flat UUID list. Feeding it the all-displays union
  makes "moved to another screen" stop registering as drift. This alone removes the false
  "desktop moved" flags. Drift now means a space was genuinely **deleted**.

### 4. Switch engine — `RealDesktopEngine` / `SwitchEngine`
- **Approach A:** resolve UUID → `(display, managedSpaceID)`; call the direct switch; verify by
  polling **that display's** current space against the target within the bounded timeout. The
  `index ≤ 9` / `notKeyable` / Ctrl+N branches are removed.
- **Approach B:** focus the target display, then post Ctrl+N using the index *within that
  display's* ordering; verify as today.
- `SwitchResult` keeps `.driftDetected`, `.blocked`, `.verificationFailed`. `.notKeyable` is
  retained only if Approach B is selected.

### 5. AppModel
- `recomputeCurrent`, `recomputeDrift`, and `recalibrate` switch to the **focused display's**
  current space. This stops recalibrate from binding a project to the wrong screen — the most
  damaging current symptom.
- "Current project" is resolved against the focused display.

### 6. UI (minimal)
- Drift badge logic unchanged but now fires only on real deletions.
- Optional: indicate which screen a project's desktop lives on. Deferred unless trivial.

## Data flow (Approach A, happy path)

1. User picks Project X (bound to `uuid`).
2. `SpacesProvider` resolves `uuid → (displayID, managedSpaceID)` from the all-displays snapshot.
3. `RealDesktopEngine` calls `CGS.setCurrentSpace(managedSpaceID:onDisplay:)`.
4. Engine polls that display's current space; exact UUID match ⇒ `.switched(latencyMs:)`.
5. Timeout ⇒ re-check secure input, else `.verificationFailed`.

## Error handling

- Missing/renamed private symbol ⇒ `setCurrentSpace` returns false ⇒ surface a clear status,
  no crash (graceful degradation, like the read side).
- UUID not found in any display ⇒ `.driftDetected` (true deletion).
- Switch posted but space didn't land within timeout ⇒ `.verificationFailed`.
- Secure Input active ⇒ `.blocked(.secureInput)` (TOCTOU re-check retained).

## Testing

- **Pure units (no system access):** `DriftDetector` against multi-display unions; UUID→
  `(display, space)` resolution; engine branch selection with injected fakes (switched / drift /
  verification-failed / blocked). Extend the existing fakes to model multiple displays.
- **Spike (Phase 0):** manual/scripted verification in `Spike/` that the direct switch lands on
  the secondary display on macOS 26.4.1.
- **Manual acceptance:** two displays, separate Spaces ON — bind a project on each screen; verify
  switch, no false drift, and correct recalibrate on the focused screen.

## Phasing

- **Phase 0 — Switch-symbol spike (GATE):** prove (or disprove) direct space-switch on the
  secondary display on macOS 26.4.1. Selects Approach A vs B.
- **Phase 1 — Multi-display read:** `allDisplays()`, union ordering, focused-display current,
  UUID→`(display,space)` lookup. Kills false drift.
- **Phase 2 — Switch engine:** direct-switch (A) or focus+Ctrl+N (B), with verification.
- **Phase 3 — AppModel semantics:** focused-display current/drift/recalibrate.
- **Phase 4 — Tests + manual acceptance pass.**

## Success criteria

- With two displays and separate Spaces ON: no project on the secondary display is falsely
  flagged as drifted.
- Switching to a project reliably lands on its desktop on whichever display it lives on.
- Recalibrate binds to the desktop on the screen the user is actually focused on.
- Ctrl+N numbering changes no longer affect correctness (Approach A) or are correctly
  per-display (Approach B).
- Private-symbol absence degrades gracefully (clear status, no crash).
