---
title: "NSWorkspace.openApplication on an app running elsewhere yanks you to its Space"
module: "macOS Spaces / app launching"
date: 2026-06-21
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
