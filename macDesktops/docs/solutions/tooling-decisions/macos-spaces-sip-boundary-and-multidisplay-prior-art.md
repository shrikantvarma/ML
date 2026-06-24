---
title: "The macOS Spaces SIP boundary, and how yabai / AeroSpace / Amethyst handle multi-display"
module: "macOS Spaces (virtual desktops) — multi-display"
date: 2026-06-23
problem_type: tooling_decision
component: tooling
severity: medium
related_components:
  - architecture
tags:
  - macos
  - spaces
  - cgs
  - skylight
  - sip
  - multi-display
  - prior-art
  - yabai
  - aerospace
applies_when:
  - "Deciding whether a native-Spaces operation needs SIP disabled on macOS 26"
  - "Choosing a switch mechanism for a no-SIP consumer Spaces tool"
  - "Designing per-Space identity keying on a multi-display setup"
---

# The macOS Spaces SIP boundary, and how yabai / AeroSpace / Amethyst handle multi-display

## Context

Parallel Project Desktops switches between **existing** native Spaces, per display,
on a multi-display setup with **"Displays have separate Spaces" ON**, and must do so
**without asking users to disable SIP** (consumer app, notarized direct download).
Approach A (direct `CGSManagedDisplaySetCurrentSpace`) was spike-proven on-device on
macOS 26.4.1, but we wanted independent corroboration of *where the SIP line falls per
operation* before building on it — and to learn from the tools that have lived in this
private-API space for years. This is the prior-art research backing the multi-display
design ([empty-UUID identity gaps & spike strategy](../architecture-patterns/multi-display-spaces-identity-and-spike-strategy.md),
[CGS/SkyLight access](macos-private-cgs-spaces-access.md)).

All sources below are **community-reverse-engineered or single-vendor docs** — Apple
documents none of these private symbols. No WWDC/Apple release note speaks to them, so
behavior can change silently across point releases (it did, for window-moves, at Sonoma
14.5). Treat every signature as version-agnostic and verify on-device.

## Guidance

### 1. The SIP boundary splits at READ/SWITCH vs. OWNERSHIP-MUTATION — and we are entirely on the no-SIP side.

| Operation | SIP needed? | Notes |
|---|---|---|
| Read per-display Space list (`CGSCopyManagedDisplaySpaces` / `SLSCopyManagedDisplaySpaces`) | **No** | Used read-only by Hammerspoon, SpaceCommand. We use this. |
| Read focused display's active Space (`CGSGetActiveSpace` / `SLSGetActiveSpace`) | **No** | Takes **no display arg** → returns only the *visible/focused* display's space. This is exactly our focused-display semantics for recalibrate. |
| **Switch** a display's active Space to an existing Space (`CGSManagedDisplaySetCurrentSpace`) | **No** | Our Approach A. Confirmed SIP-free on 26.4.1 (our spike) + header-corroborated. |
| Create / destroy a Space | **SIP** (or AX automation through Mission Control) | No confirmed SIP-free direct-CGS path. We don't need this (non-goal). |
| **Move/duplicate a window** onto another Space | **SIP** | Routed through Dock injection (yabai) or AX/Mission Control (Hammerspoon). Out of scope — already a stated non-goal. |

The clean read: **everything our feature does is on the no-SIP side; everything that
needs SIP is something we explicitly chose not to do.** The design's "no SIP" constraint
and Approach A are mutually consistent with the prior art.

### 2. yabai's "focusing a Space requires SIP" is about *yabai's architecture*, not a universal CGS limit — do not let it scare you off Approach A.

Maintainer koekeishiya (Discussion #803, issues #548/#1374) states space-switching is
"a combination of lower-level SkyLight functions **and state stored inside Dock.app**,"
and "the entire workspaces/mission-control functionality is implemented inside Dock.app,"
so yabai must "partially disable SIP to **inject code into the Dock process**." That SIP
requirement is the cost of yabai's *window-ownership manipulation* (it manages windows
*through* Dock's WindowServer connection, the "universal owner"), **not** the cost of a
bare `CGSManagedDisplaySetCurrentSpace` call. Tellingly, in the same tracker yabai says
**display focus works fine without SIP** — display-focus and yabai's space-focus sit on
opposite sides of *its* boundary. A counter-claim that an Übersicht widget calls the
switch API directly was refuted in our verification (0-3). **Staleness flag:** the
strongest yabai SIP quotes are 2020–2022 (macOS 11–12); they predate Tahoe and describe
Dock injection, and were not contradicted by our 26.4.1 result.

### 3. Prefer the SLS* symbol names (with CGS* as the fallback) — SkyLight is the more future-proof namespace.

The symbols exist in two mirrored families: legacy `CGS*` (CoreGraphics) and newer
`SLS*` (SkyLight). Hammerspoon's author migrated to SLS* deliberately: "the SkyLight
Server framework seems to be cropping up more and more… I suspect it may be more future
proof." yabai uses the SLS getter `SLSManagedDisplayGetCurrentSpace(cid, CFStringRef uuid)`.
Our spike resolves the `CGS*` names and they work on 26.4.1 — but since we `dlsym` at
runtime behind a seam already, **resolving the `SLS*` name first and falling back to
`CGS*`** costs nothing and hedges a future rename. (Behavior-identical mirrors; same
signature family `(connectionID, CFStringRef display/uuid, spaceID)`.)

### 4. The "separate Spaces ON" multi-display config is the hard one — AeroSpace refuses it; we can't.

AeroSpace **deliberately abandons native Spaces** and emulates its own "Workspaces" via
public Accessibility APIs (only one private symbol, `_AXUIElementGetWindow`), because:
no public API to create/delete/reorder/switch Spaces or move windows between them; the
switch animation is slow and **un-disableable**; and there's a **~16-Space cap**. It
"will never require disabling SIP." Crucially, AeroSpace **recommends users turn OFF
"Displays have separate Spaces,"** because with it ON, "moving windows between monitors
moves them between Spaces, which the public APIs… are not aware of." That is precisely
**our required configuration** — so the public-AX route AeroSpace took is *not available
to us*; we are committed to the private-CGS route AeroSpace avoided. The upside: our
direct-CGS switch *is* Spaces-aware, so we don't inherit AeroSpace's specific breakage —
but we own the private-API risk. Amethyst (also no-SIP, public-AX only) tells users to
disable **"Automatically rearrange Spaces based on most recent use,"** because native
Space *ordering* is mutable and breaks its keyboard navigation.

### 5. Nobody else publishes the empty-UUID-after-drag symptom; the closest analog says "don't reuse stale Space identity." Our guard is the more robust choice.

No tool's tracker documents `CGSCopyManagedDisplaySpaces` returning `uuid: ""` for a
dragged desktop — it remains **our observation only** (macOS 26.4.1). The nearest
documented analog is yabai #1853: on display disconnect a labeled space becomes an
orphaned **"bad space"** (resolvable by label but absent from the full listing, empty,
`is-visible:false`); on reconnect macOS makes a *new* unlabeled space rather than
restoring it. The community workaround is **strip the stale label and reassign it to a
fresh space** — i.e., *don't key durable identity on a Space that can go stale.* Our
empty-UUID guard (never bind/match/return `""`) is the conservative version of that same
lesson, and stricter than yabai's reuse-by-relabel. **Open probe for the spike:** when a
desktop's `uuid` goes empty after a drag, is its `ManagedSpaceID`/`id64` still stable
(session-scoped)? If so, it's a candidate *session-stable* fallback key for otherwise
untrackable desktops — though `id64` is **not reboot-stable**, so it can never replace
the UUID for persistence, only bridge a single session. (CONCEPTS.md currently treats
empty-UUID desktops as untrackable; this probe could soften that to "session-trackable.")

## Why This Matters

- It converts Approach A from "spike said yes once" to "spike + the entire prior-art
  corpus agree the switch path is SIP-free, and the SIP-gated operations are exactly the
  ones we already excluded." The load-bearing risk in the design is substantially retired.
- It pre-empts a plausible derailment: someone reading yabai's docs would conclude
  "switching Spaces needs SIP" and abandon Approach A. The research shows *why* that's
  yabai-specific and doesn't apply to a bare CGS switch.
- It surfaces two cheap hardening moves (SLS-first symbol resolution; consider advising
  users to disable Space auto-rearrange) and one concrete spike probe (id64 stability
  across the empty-UUID drag) that sharpen the next phase.

## When to Apply

- Before committing to any private-Spaces operation: check which side of the read/switch
  vs. mutate line it's on.
- When a primary source claims an operation "needs SIP," check whether that's the
  *operation* or that *tool's window-ownership design* (the yabai trap).
- When designing per-Space identity on multi-display: assume ordering is mutable and some
  desktops may lose their UUID; never key durable state on a Space that can go stale.

## Open Questions (carried into the spike)

1. Is `ManagedSpaceID`/`id64` stable across the drag that empties a desktop's UUID? (Could
   enable a session-stable fallback for untrackable desktops.)
2. Any Tahoe-specific change to `CGSManagedDisplaySetCurrentSpace` behavior — e.g.
   no-op on certain displays — beyond our single empirical pass?
3. Is there any SIP-free direct path to create/destroy Spaces on 26 (we don't need it,
   but it bounds what "Recalibrate"-adjacent features could ever do)?

## Related

- [Multi-display macOS Spaces: empty-UUID identity gaps and spiking the messy state](../architecture-patterns/multi-display-spaces-identity-and-spike-strategy.md) — the on-device learnings this research backs.
- [Accessing macOS Spaces via private CGS/SkyLight symbols safely](macos-private-cgs-spaces-access.md) — base `dlsym` access pattern; SLS-first resolution (#3 here) is a hardening for it.
- Design + plan: `docs/superpowers/specs/2026-06-23-multi-display-spaces-support-design.md`, `docs/superpowers/plans/2026-06-23-multi-display-spaces-support.md`.

## Primary sources

- yabai — Discussion [#803](https://github.com/koekeishiya/yabai/discussions/803), issues [#548](https://github.com/koekeishiya/yabai/issues/548), [#1374](https://github.com/koekeishiya/yabai/issues/1374), [#1853](https://github.com/koekeishiya/yabai/issues/1853) (orphaned "bad space").
- AeroSpace — [guide](https://nikitabobko.github.io/AeroSpace/guide), [README](https://github.com/nikitabobko/AeroSpace).
- Amethyst — [README](https://github.com/ianyh/Amethyst).
- Reverse-engineered headers — [NUIKit/CGSInternal `CGSSpace.h`](https://github.com/NUIKit/CGSInternal/blob/master/CGSSpace.h), [Hammerspoon `libspaces.m`](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/spaces/libspaces.m) (Sonoma 14.5 window-move gate), [alt-tab-macos PrivateApis.swift](https://github.com/lwouis/alt-tab-macos/blob/master/src/experimentations/PrivateApis.swift), [SpaceCommand](https://github.com/ZimengXiong/SpaceCommand).

> Source quality: all CGS/SLS signatures are community reverse-engineering, not Apple's
> documented contract. yabai SIP quotes are macOS 11–12 era. The empty-UUID-after-drag
> symptom is corroborated only *analogically* (yabai #1853), not by a direct published
> report. Our own 26.4.1 empirical pass remains the most current, most on-point evidence.
</content>
</invoke>
