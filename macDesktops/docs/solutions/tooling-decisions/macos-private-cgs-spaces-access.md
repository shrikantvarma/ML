---
title: "Accessing macOS Spaces via private CGS/SkyLight symbols safely"
module: "macOS Spaces (virtual desktops)"
date: 2026-06-21
last_updated: 2026-06-23
problem_type: tooling_decision
component: tooling
severity: medium
tags:
  - macos
  - spaces
  - cgs
  - skylight
  - private-api
  - dlsym
  - notarization
applies_when:
  - "Reading or switching macOS Spaces / virtual desktops programmatically"
  - "Needing the ordered list of desktops or a stable per-desktop identifier"
  - "Persisting state keyed to a specific desktop across launches/reboots"
---

# Accessing macOS Spaces via private CGS/SkyLight symbols safely

## Context

macOS exposes **no public API** for enumerating or switching Spaces (virtual
desktops). The only practical route is private CoreGraphics/SkyLight symbols —
which raises three fears: do they still exist on the latest OS, will they break
notarization, and is any derived identifier stable enough to persist?

## Guidance

- **Load private symbols at runtime via `dlopen`/`dlsym`, not link-time.**
  `dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight")` then
  `dlsym` each symbol (`CGSMainConnectionID`, `CGSCopyManagedDisplaySpaces`, …).
  This keeps them invisible to link-time tooling and lets you **report** a
  missing/renamed symbol gracefully on a future OS instead of failing to launch.
- **Isolate all private symbols behind one wrapper/protocol.** OS breakage then
  becomes a one-file fix and the rest of the app is testable against a fake.
- **Key persistent per-desktop state on the Space UUID**, not the ordinal index
  (changes on reorder) or `ManagedSpaceID` (undocumented). `CGSCopyManagedDisplaySpaces`
  returns, per display, an ordered `Spaces` array with `uuid`, `ManagedSpaceID`,
  and `type` (0 = user desktop), plus a `Current Space`.
  **Caveat (multi-display):** macOS returns an **empty `uuid`** for some real
  desktops — seen for desktops churned by dragging between monitors — making them
  untrackable by UUID. Guard empties out (never bind/match `""`). See
  [Multi-display macOS Spaces: empty-UUID identity gaps](../architecture-patterns/multi-display-spaces-identity-and-spike-strategy.md).

## Why This Matters

- **Verified on macOS 26.4.1:** both `CGSMainConnectionID` and
  `CGSCopyManagedDisplaySpaces` still resolve, and **Space UUIDs survive a full
  reboot** — so UUID-keyed persistence is sound (this was the make-or-break test).
- **Notarization is not blocked** by this approach: Apple's notary service does
  not reject private-symbol use, `dlsym` avoids link-time detection, and the
  hardened runtime's library validation passes because SkyLight is **Apple-signed**
  (no `disable-library-validation` entitlement needed).
- App Store is still out (private API), so plan for notarized direct download.

## When to Apply

- Any tool that switches/reads native Spaces (project switchers, window managers).
- Reach for `dlsym` + a wrapper whenever you must touch unsupported system symbols.

## Examples

```swift
typealias CopyManagedDisplaySpacesFn =
    @convention(c) (Int32) -> Unmanaged<CFArray>?
let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
let fn = dlsym(h, "CGSCopyManagedDisplaySpaces")
    .map { unsafeBitCast($0, to: CopyManagedDisplaySpacesFn.self) }
// fn == nil  →  symbol gone on this OS: degrade gracefully, don't crash.
// Each space dict: ["uuid": String, "ManagedSpaceID": Int64, "type": Int]
// Persist the project→desktop binding by `uuid` (stable across reboot).
```

Switching, single-display (shipped v1): synthesize the user's "Switch to Desktop N"
(Ctrl+number) shortcut (off by default; capped ~9–16); the private read API gives
you the ordered UUID list to resolve N at switch time.

Switching, multi-display (macOS 26 — **corrected by the 2026-06-24 gate**): the direct call
`CGSManagedDisplaySetCurrentSpace` switches a non-focused display's *content* but leaves an
**unfixable-no-SIP menu-bar overlap**, so it is NOT the switch mechanism. Synthesized **Ctrl+N**
is — and its numbering is **not** unreliable as once feared: it is **global across displays,
matches the `CGSCopyManagedDisplaySpaces` order, and tracks reorders**, so switch by the target
UUID's global index (Ctrl+N goes through the OS path → overlap-free). `CGSGetActiveSpace()`
resolves the focused display (recalibrate). Full reasoning + the menu-bar finding:
[Multi-display macOS Spaces: empty-UUID identity gaps and spiking the messy state](../architecture-patterns/multi-display-spaces-identity-and-spike-strategy.md).
