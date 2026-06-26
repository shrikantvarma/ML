---
title: "Multi-display: a new browser window is born on its app's FRONTMOST window's display — place cross-display opens explicitly"
module: "Per-Space Links — multi-display open"
date: 2026-06-26
problem_type: integration_issue
component: spaces-engine
related_components:
  - browser-launcher
  - architecture
tags:
  - macos
  - spaces
  - multi-display
  - chrome
  - window-placement
  - accessibility
  - cgs
  - skylight
applies_when:
  - "Opening a window onto a Space that lives on a display you are NOT focused on"
  - "A 'open these links on the project's desktop' recipe validated single-monitor misbehaves on multi-display"
  - "Deciding whether keyboard/display focus can be used to steer where a new window lands"
---

# Multi-display: a new browser window follows its app's frontmost window, not focus

## Context

Per-Space Links opens a project's web links on the project's macOS desktop via
`open -na "Google Chrome" --args --new-window --profile-directory=<folder> <urls>`.
The "the window is born on the Space you're standing on" recipe was validated
**single-monitor** (across Spaces on one display, 2026-06-22). On a two-display rig
(MacBook + iPad as a second display, "Displays have separate Spaces" ON) "Open all"
on a project living on the iPad opened the links on the **laptop** instead — even when
the user was focused on the iPad.

## Guidance

### 1. A new Chrome window is born on the display where Chrome's FRONTMOST window already is — not the focused display, not the current Space, not always-primary.

Headless probes on the live rig (window x ≥ 1512 ⇒ on the iPad):

| Probe | Result |
|---|---|
| New window, Chrome frontmost on laptop | → laptop |
| New window, Chrome frontmost moved to iPad | → iPad |
| `CGWarpMouseCursorPosition` to iPad, then open | → laptop (focus/cursor irrelevant) |
| `--window-position=1650,300` on a *running* Chrome | ignored → laptop (only honored on cold start) |
| AX `kAXPositionAttribute` move to iPad after open | (1650,300) ✓ — works, no new permission |

So **focus is the wrong primitive** — neither necessary nor sufficient. The single-monitor
recipe held only because, within one display, "frontmost window's display" and "the display
you're on" coincide. They diverge across physical displays.

### 2. First-principles fix = two independent atoms; keyboard focus is in neither.

The job is "put a window onto a specific Space on a specific display." Decompose:

- **Atom 1 — make the target Space current on its display.** `SLSManagedDisplaySetCurrentSpace`
  (CGS mirror `CGSManagedDisplaySetCurrentSpace`) sets ONE display's current Space directly —
  no Ctrl+N, no focus move, no SIP (see the SIP-boundary prior-art). Ctrl+N can't do this:
  it only switches the *focused* display.
- **Atom 2 — place the window on that display.** Open the window (it's born on the wrong
  display), then move it onto the target display's `CGDisplayBounds` via the Accessibility
  API (`AXUIElementSetAttributeValue` / `kAXPositionAttribute`) — the permission the app
  already holds, so no new Automation/TCC prompt. Moving across *displays* is a plain
  coordinate change; only moving across *Spaces on one display* is SIP-gated. Because Atom 1
  made the target Space current on that display, the window lands on the right Space.

This is browser-agnostic (Atoms 1+2 move any app's window); only the per-project
`--profile-directory` profile selection is Chromium-specific.

### 3. Identify the just-opened window by frontmost-after-count-grows; don't trust focus or position.

`--new-window` makes the new window frontmost. The placer (`AXWindowPlacer`) snapshots the
app's AX window count before `open`, polls until it grows, then moves `windows[0]`. Simple
and permission-free; good enough for a menu-bar one-click (no private `_AXUIElementGetWindow`).

## Why This Matters

- It explains a "validated recipe" silently breaking on multi-display: the validation never
  exercised a target Space on a *different physical display* than the focused one.
- It kills the tempting dead-end of "make the other screen the focused screen" — proven
  (cursor-warp probe) not to move the window; the direct per-display space-set is the right lever.
- **Focus behavior (tested 2026-06-26, clamshell + two external displays):** Atom 1 and the
  `open` step both *preserve* focus, but **Atom 2 (the AX window-move) relocates the active
  window to the target display and keyboard focus follows it there** — so the cross-display
  open is **NOT** focus-preserving, despite Atom 1 being so. That is acceptable if you want
  focus to follow the links you just opened; if you need to stay put, re-assert focus on the
  original display after the move. Either way it avoids the buggy Ctrl+N-on-the-wrong-display
  path. (Empirically isolated: `after Atom1` focus unchanged, `after open` unchanged, `after
  AX move` focus moved to the target display.)

## When to Apply

- Any "open/place a window on a specific desktop" feature the moment a second display exists.
- Before reaching for focus/cursor manipulation to steer window placement — it won't work for
  Chrome (and likely other apps that anchor new windows to their frontmost window).

## Related

- [The macOS Spaces SIP boundary + multi-display prior art](../tooling-decisions/macos-spaces-sip-boundary-and-multidisplay-prior-art.md) — confirms `*ManagedDisplaySetCurrentSpace` is SIP-free (Atom 1).
- [Accessing macOS Spaces via private CGS/SkyLight symbols](../tooling-decisions/macos-private-cgs-spaces-access.md) — the `dlsym` access pattern Atom 1 graduates into the app.
- [macOS per-space URL opening needs a windowless browser profile](macos-per-space-url-opening-needs-windowless-browser-profile.md) — the single-monitor recipe this generalizes.
- [NSWorkspace.openApplication activates an app on another Space](macos-openapplication-activates-app-on-other-space.md) — sibling finding, same root cause (windows anchor to where the app already lives), the native-app branch instead of the browser branch.
- Known macOS quirk (NOT this fix): Mission-Control Space-drag can strand windows off-screen — see `docs/BACKLOG.md` › Known macOS quirks.
- Code: `ParallelDesktopsCore/SpacesEngine/CGSPrivate.swift` (`directSetCurrentSpace`, `cgBounds`), `SpacesProvider.swift` (`setDisplayCurrentSpace`, `displayBounds`), `System/WindowPlacer.swift`, `Model/LinkOpenPlan.swift` (`DisplayPlacement`), `ParallelDesktops/AppModel.swift` (`switchSettleOpen`, `performOpen`).
</content>
