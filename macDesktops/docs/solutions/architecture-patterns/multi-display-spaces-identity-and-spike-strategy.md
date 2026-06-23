---
title: "Multi-display macOS Spaces: empty-UUID identity gaps and spiking the messy state"
module: "macOS Spaces (virtual desktops) — multi-display"
date: 2026-06-23
problem_type: architecture_pattern
component: tooling
severity: medium
related_components:
  - development_workflow
applies_when:
  - "Adding multi-display support to a Spaces tool with separate Spaces enabled"
  - "Switching or identifying desktops on a non-primary display"
  - "De-risking a private-API capability with a spike before building on it"
tags:
  - macos
  - spaces
  - cgs
  - multi-display
  - spike
  - empty-uuid
---

# Multi-display macOS Spaces: empty-UUID identity gaps and spiking the messy state

## Context

Parallel Project Desktops keys each project to a macOS desktop (Space) by its
**Space UUID** (see [Accessing macOS Spaces via private CGS/SkyLight symbols](../tooling-decisions/macos-private-cgs-spaces-access.md)).
v1 was single-display by design. The first attempt to add multi-display support
(with **"Displays have separate Spaces" ON**) was built end-to-end, failed on
device, and was reverted. Two durable lessons came out of it: a hard macOS
constraint (some real desktops have **no UUID**), and a spike-methodology failure
(a spike that "passed" missed the real blocker because it only tested the happy
path). Capture both before the next attempt.

## Guidance

**1. macOS returns empty UUIDs for some real desktops — guard from day one.**
`CGSCopyManagedDisplaySpaces` sometimes returns `uuid: ""` for a genuine user
desktop (`type: 0`), observed for desktops churned up by **dragging desktops
between monitors**. Raw dict seen on a secondary display:
`{ManagedSpaceID: 497, id64: 497, type: 0, wsid: 1, uuid: ""}`.
A UUID-keyed identity model cannot track these. Treating `""` as a valid key
causes **identity collisions**: a project bound to `""` matches *every* desktop
the app reads as `""` → one screen shows another screen's project, "Save this
desktop as…" is hidden (the app thinks the desktop is already a project), and
switches mis-target. Guard everywhere with a single predicate and never bind to,
match, or return an empty UUID. Empty-UUID desktops then simply can't be projects
until they get a real UUID (recreate the desktop in Mission Control, or a
logout/login regenerates UUIDs for all desktops).

**2. The direct CGS space-switch works — including on a non-focused secondary display.**
`CGSManagedDisplaySetCurrentSpace(conn, displayID: CFString, managedSpaceID)`
**visibly** switches the target display even while keyboard focus is on a
different display — confirmed via window-delta (Calculator + iTerm appeared on
Monitor 2). Verify a switch landed by polling each display's `currentSpaceUUID`;
`CGSGetActiveSpace()` returns a value equal to a `ManagedSpaceID`, so it resolves
the focused display. This **supersedes** the older belief that switching must
synthesize the "Switch to Desktop N" (Ctrl+number) shortcut — Ctrl+N can only
move the *focused* display and its numbering is unreliable across separate-Spaces
displays. Direct switch also removes the ~9-desktop Ctrl+number cap and the
Secure-Input/shortcut-disabled failure modes.

**3. Verify Spaces behavior by window-delta, never by eye.**
Empty desktops are pixel-identical, so "did it switch?" is unanswerable visually —
this wasted multiple debugging rounds. Snapshot on-screen apps before/after the
action via `CGWindowListCopyWindowInfo` (layer-0 owner names; needs **no**
screen-recording permission) and diff the sets. A real visible switch changes the
set; the internal current-space record updating does **not** prove a redraw.

**4. Spikes must exercise the messy real-world state, not the happy path.**
The original spike reported "GATE PASSED," but it only confirmed the **primary**
display visibly switched a **clean** desktop. It never exercised a secondary-display
switch, the empty-UUID desktops, or the actual saved `ProjectStore` data — so the
real blocker only surfaced after a full Part-1/Part-2 build, on device. Before
declaring a gate passed, **enumerate the conditions the production path will
actually hit** (N displays — CGS reported 3 entries for 2 monitors; rearranged
desktops; stale persisted bindings; identical-looking empties) and make the spike
reproduce them.

## Why This Matters

- The entire multi-display feature was reverted because the spike validated the
  wrong thing. A messier spike (secondary-display switch + a churned desktop)
  would have surfaced the empty-UUID blocker in ~20 minutes instead of after a
  full build-and-revert cycle.
- The empty-UUID constraint is **architectural**: the UUID-keyed identity model
  has a gap macOS itself creates. Any future design must decide up front how to
  treat UUID-less desktops — guard them out (they can't be projects), or adopt a
  session-stable fallback (`ManagedSpaceID`, accepting reboot-drift) — rather than
  discovering the gap mid-build.

## When to Apply

- Before architecting multi-display support for any Spaces-based tool.
- Whenever a spike is the gate for a risky private-API capability — design the
  spike around the production mess, and treat a happy-path pass as *incomplete*.
- Any time you need to confirm a Spaces/desktop switch actually happened.

## Examples

Empty-UUID guard (used at every read/bind/match site):

```swift
enum SpaceIdentity {
    /// macOS returns "" (parser maps missing → "?") for some real desktops;
    /// binding to / matching "" collides across every such desktop.
    static func isTrackable(_ uuid: String) -> Bool { !uuid.isEmpty && uuid != "?" }
}
// orderedUserSpaceUUIDs / allUserSpaceUUIDs → .filter(SpaceIdentity.isTrackable)
// spaceLocation(uuid:) / isSpaceCurrent(uuid:) → guard SpaceIdentity.isTrackable(uuid)
// currentSpaceUUID() → return the resolved uuid only if trackable, else nil (never "")
```

Direct switch + window-delta verification (the spike's decisive probe):

```swift
let before = onScreenApps()                                  // CGWindowList, layer-0 owners
CGS.directSetCurrentSpace(displayID: displayID, spaceID: managedSpaceID)
// then poll each display's currentSpaceUUID until it == target (bounded timeout)
let appeared = onScreenApps().subtracting(before)           // non-empty ⇒ real visible switch
```

## Related

- [Accessing macOS Spaces via private CGS/SkyLight symbols safely](../tooling-decisions/macos-private-cgs-spaces-access.md) — base CGS access; **its switching caveat (Ctrl+number only) is now superseded** by guidance #2 here (flagged for refresh).
- [Protocol seams for untestable system calls](protocol-seams-for-untestable-system-calls.md) — why the multi-display change stayed contained to two implementations.
- [NSWorkspace.openApplication yanks you to its Space](../integration-issues/macos-openapplication-activates-app-on-other-space.md) — related cross-Space limitation (window placement needs SIP-off).
- Reference artifacts kept from the reverted attempt: `docs/superpowers/specs/2026-06-23-multi-display-spaces-support-design.md`, `docs/superpowers/plans/2026-06-23-multi-display-spaces-support.md`, and the spike probes + `Spike/SPIKE-multidisplay.md`.
