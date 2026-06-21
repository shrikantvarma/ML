---
title: "NSWorkspace.openApplication on an app running elsewhere yanks you to its Space"
module: "macOS Spaces / app launching"
date: 2026-06-21
last_updated: 2026-06-21
problem_type: integration_issue
component: tooling
severity: high
symptoms:
  - "Entering a project alternately switched between its desktop and another desktop"
  - "Focus jumped to an app's desktop instead of staying on the one just switched to"
root_cause: wrong_api
resolution_type: code_fix
tags:
  - macos
  - spaces
  - nsworkspace
  - openapplication
  - window-management
---

# NSWorkspace.openApplication on an app running elsewhere yanks you to its Space

## Problem

A "boot this project's apps" feature switched to the project's desktop, then
immediately bounced to a different desktop — appearing to ping-pong between two
Spaces on a single click.

## Symptoms

- After switching to desktop A, the view jerked to desktop B.
- Repeated/alternating switching on a single "enter" action.

## What Didn't Work

Defining "apps to launch" as *blueprint − apps with a window on the current
desktop*. An app already running on **another** desktop counts as "missing" under
that rule, so the code called `NSWorkspace.openApplication(activates: true)` on it.

## Solution

Define "apps to launch" as *blueprint − apps running anywhere* (system-wide
`NSWorkspace.runningApplications`). Only genuinely not-running apps are launched
(onto the current desktop); already-running apps are left untouched.

```swift
// before: presentHere = windows on THIS desktop  → relaunches apps living elsewhere
// after:  alreadyRunning = every running bundle id (system-wide)
let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
let toLaunch = blueprint.filter { !running.contains($0) }
```

## Why This Works

`openApplication(activates:true)` on an already-running app does **not** open a
window on the current desktop — it activates the existing instance. With the
macOS setting *Desktop & Dock ▸ Mission Control ▸ "When switching to an
application, switch to a Space with open windows for the application"*, activating
that instance switches you to **its** Space — the bounce. You cannot move a
running app's window onto the current desktop without window management, so the
correct v1 behavior is to leave running apps where they are.

## Prevention

- Treat `openApplication` as "launch if not running / activate where it already
  is" — never as "bring a window here."
- For Space/desktop logic, dedupe launches against *running anywhere*, not
  *visible on this Space*.
- Test the dedupe as a pure function:
  `toLaunch(blueprint:["a","b"], alreadyRunning:["a","b"]) == []`.

## Refinement (2026-06-21): separate navigate from set-up

Using the app revealed that auto-launching on *every* desktop switch is wrong —
you navigate constantly, and it relaunches apps you closed on purpose. The shipped
model now splits the two:

- **Navigation = switch only.** Clicking a project just switches Spaces; no apps
  touched. (This refines the origin's "entering launches apps" — R4.)
- **Set-up = explicit, on demand.** A separate "Bring up apps here" action does the
  boot, deciding per app by **window presence** (via AX `kAXWindowsAttribute`, which
  counts an app's windows across all Spaces):
  - not running → launch (window opens here);
  - running but **windowless** (closed its windows, not quit) → reopen → window opens
    here (no bounce — there's no existing window to anchor to);
  - already windowed here → skip (no duplicate);
  - **windows on another desktop → report only, do NOT act.**

**Hard constraint (tested 3 ways, do not retry):** you cannot place a window of an
already-windowed app onto a *different* Space programmatically. All three bounce
(activate the app and travel to its existing window's Space):
1. `NSWorkspace.openApplication(activates:true)` — activates the existing window.
2. AppleScript `tell app to make new window` — new window born on the app's Space.
3. **AX-driving the Dock's "New Window" menu item** — even replicating the exact
   manual gesture via Accessibility bounces (the synthetic press still activates +
   travels), though the *human* mouse gesture does not. Confirmed for Chrome and Safari.

So "bring it here" only works for **quit** (launch) or **windowless** (reopen) apps —
both land on the current Space because there's no existing window to anchor to.
Relocating/duplicating a window onto another Space needs window management (private
CGS `CGSMoveWindowsToManagedSpace`), which on **macOS 14.5+ requires a scripting
addition / SIP disabled** — a non-starter for a normal notarized app. Treat
cross-Space window placement as genuinely out of reach without SIP-off.

## Capture hygiene: filter to .regular apps

When enumerating "the apps on this desktop" from `CGWindowListCopyWindowInfo`, the
list includes system agents (Control Center, Notification Center, menu-bar
utilities) and your own agent app — `.excludeDesktopElements` does NOT drop them.
Filter each window's owner to `NSRunningApplication.activationPolicy == .regular`:
that single check keeps only normal Dock-having apps and drops the agents *and*
your own `.accessory` menu-bar app, so blueprints capture only real user apps.
