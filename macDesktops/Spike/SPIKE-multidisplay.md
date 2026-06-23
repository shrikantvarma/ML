# Multi-Display Switch Spike — Results (macOS 26.4.1, separate Spaces ON)

Run `swift run --package-path macDesktops/Spike spike` with TWO displays connected.
Grant Accessibility to the terminal first.

Run on 2026-06-23, macOS 26.4.1, separate Spaces ON, 3 display entries reported by CGS.

## Symbol availability (command 1)
- CGSGetActiveSpace: found
- CGSManagedDisplaySetCurrentSpace: found

## Direct switch (command 8 — window-delta verification)
Decisive run:
```
> 0.1
Direct-switching Display 0 ('37D8832A-2D66-02CA-B9F7-8F30A301B230') → C8202DB4 (id 4)…
  internal current: ✓ updated to target (C8202DB4)
  ✓ VISIBLE SWITCH — appeared: ["Calculator"]; disappeared: []
```
- `internal current` updated to target: YES (every attempt).
- Visible redraw confirmed via on-screen window delta (Calculator appeared): YES.
- Note: switches between EMPTY desktops report `UNCHANGED` (nothing to detect) but the
  internal current still updates — not a failure, just no window delta to observe.

## GATE DECISION
- [x] PASS → Part 2 uses **Approach A** (direct CGS switch)
- Working signature: `void CGSManagedDisplaySetCurrentSpace(CGSConnectionID, CFString display, size_t spaceID)`,
  called with the display's "Display Identifier" UUID string and the space's `ManagedSpaceID`.
- Verification strategy for the app: poll the target display's `currentSpaceUUID` until it
  equals the target (bounded timeout) — the internal-current read proved reliable.
- Reliability burst across many switches: TODO during Part 2 manual acceptance.
