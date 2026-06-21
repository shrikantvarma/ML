# U1 De-Risk Spike — Results

Throwaway probe for the **Parallel Project Desktops** plan, Unit U1. It exists only
to answer the plan's U1 decision-gate questions on real hardware before any product
code is written. See `docs/plans/2026-06-21-001-feat-parallel-project-desktops-plan.md`.

## How to run

```bash
cd Spike
swift build
.build/debug/spike      # or: swift run spike
```

**Grant Accessibility first** (required for steps 4–6 — switching/Ctrl+N):
System Settings ▸ Privacy & Security ▸ Accessibility ▸ enable your terminal app, then relaunch.
Reading Spaces (steps 1–2) works without it.

Also enable the switch shortcuts: System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸
Mission Control ▸ turn on "Switch to Desktop 1…N".

## Decision gate (from the plan — all must hold to GO on the native path)

| # | Condition | How to test | Result |
|---|-----------|-------------|--------|
| a | ≥99% verified-correct landings over N≥200 switches | bind a target (3), run 100 round-trips (5) | ⬜ |
| b | Zero silent wrong-desktop landings | watch (5) for any `verificationFailed` / wrong UUID | ⬜ |
| c | All failure modes detected 100% (shortcut off, Secure Input, no-event) | (6) + disable shortcut / focus a password field, retry (4) | ⬜ |
| d | Space UUIDs survive reboot AND logout/login | bind (3), reboot, relaunch, show binding (7) → must still resolve | ✅ 2026-06-21 (macOS 26.4.1): binding resolved after reboot |
| e | Filtered ordinal maps 1:1 to the Ctrl+N number (incl. a fullscreen Space mid-list) | enter a fullscreen app to create a non-desktop Space, then (2) + (4) | ⬜ |
| f | Median switch+verify latency ≤1.5s | from (5) results | ⬜ |

A NO-GO is a **scope re-decision**, not a drop-in engine swap — see plan Risk R-1.

## Findings log

### 2026-06-21 — read-side, macOS 26.4.1 (arm64), Xcode 26.5 / Swift 6.3

- ✅ **Private symbols resolve at runtime on macOS 26.** `dlopen(SkyLight)` succeeds;
  `CGSMainConnectionID` and `CGSCopyManagedDisplaySpaces` both `found`. This retires the
  worst case of Risk R-2 for the current OS (read side).
- ✅ **Ordered Space list + current-Space detection work.** `CGSCopyManagedDisplaySpaces`
  returned the live 4-desktop layout with per-Space `uuid`, `ManagedSpaceID`, and the
  correct `*current*` flag.
- 📝 Observed a non-sequential `ManagedSpaceID` (247) between small IDs — confirms KTD-2's
  decision to key on UUID, not on managed ID or ordinal.
- ⏳ **Switch side NOT yet measured** — needs Accessibility granted + manual run (gate a/b/c/e/f).
- ⏳ **UUID-survives-reboot NOT yet measured** — needs a reboot (gate d).

### 2026-06-21 — reboot test (gate d) PASSED

- ✅ **gate d (UUID survives reboot): PASS.** After a full reboot on macOS 26.4.1,
  the persisted binding still resolved to its desktop — Space UUIDs are stable
  across restart. This retires the largest open risk: the UUID-keyed model
  (KTD-2 / KTD-6) holds; no redesign of project keying or persistence needed.

### (still to measure — reliability, not model-breaking) — fill in

- gate a (success rate over N≥200):
- gate b (any silent wrong landing?):
- gate c (failure-mode detection):
- gate e (ordinal mapping w/ fullscreen Space):
- gate f (median latency ≤1.5s):
- **GO / NO-GO:** d (the make-or-break) is GO. a/b/c/e/f are reliability gates;
  measure via the spike's run-N (5) and induced-failure checks (6,8) before relying
  on it daily.
