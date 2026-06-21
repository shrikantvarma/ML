---
title: "Protocol seams make OS/system-call logic unit-testable"
module: "app architecture"
date: 2026-06-21
problem_type: architecture_pattern
component: tooling
severity: medium
tags:
  - architecture
  - testing
  - dependency-injection
  - protocols
  - macos
applies_when:
  - "Building on platform/system APIs that can't run in CI (Spaces, key events, Accessibility, hardware)"
  - "Wanting unit tests for logic that sits on top of untestable side effects"
  - "Designing a boundary you expect to swap later (e.g., a second engine)"
---

# Protocol seams make OS/system-call logic unit-testable

## Context

Much of an OS-integration app is glue around side-effecting system calls that
cannot run in CI — switching Spaces, posting key events, reading Accessibility,
launching apps. Left inline, none of the surrounding *logic* (index resolution,
dedupe, drift diffing, fuzzy match, timeout/verify control flow) is testable.

## Guidance

Put **every** system call behind a small protocol and inject it. Keep the real
implementation thin; move the decisions into pure code that depends only on the
protocols. Then drive tests with fakes — including an injected clock for
time-based control flow.

## Why This Matters

The system stays untestable (it always was), but the *logic around it* gets full
coverage. In this project that yielded 26 fast unit tests with zero WindowServer
access: every switch outcome (drift / blocked / timeout / success / not-keyable),
the launch dedupe, drift classification, and search ranking. A bounded-wait verify
loop that "must not hang" was proven with an injected timeout in 40 ms instead of
a real 1.5 s wall-clock wait. The same seam also lets a second implementation drop
in later (e.g., an alternate switch engine) with no UI changes.

## When to Apply

- Any logic layered on non-deterministic or CI-hostile side effects.
- Any boundary you expect to have a second implementation behind it.

## Examples

```swift
protocol SpacesProvider {              // real impl calls private CGS; fake returns arrays
    func orderedUserSpaceUUIDs() -> [String]
    func currentSpaceUUID() -> String?
}
protocol KeyPosting { func postControlNumber(_ n: Int) }       // fake records calls
protocol SecureInputChecking { func isActive() -> Bool }       // fake returns a bool

struct RealDesktopEngine {
    let spaces: SpacesProvider
    let poster: KeyPosting
    let now: () -> Date          // inject the clock → test timeouts without waiting
    // ...resolve → post → bounded-verify, all branches unit-tested via fakes
}
```

Heuristic: if a function calls a `CGS*`/`NSWorkspace`/`AX*`/`CGEvent` symbol
directly, the logic around it isn't testable — push the symbol behind a protocol.
