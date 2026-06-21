---
title: "macOS menu-bar apps need a real .app bundle and stable code signing"
module: "macOS app packaging"
date: 2026-06-21
problem_type: tooling_decision
component: tooling
severity: high
tags:
  - macos
  - swift
  - swiftpm
  - codesigning
  - menubarextra
  - tcc
  - notarization
applies_when:
  - "Building a macOS menu-bar (MenuBarExtra / NSStatusItem) app, especially from a SwiftPM executable"
  - "An app that needs Accessibility or other TCC permissions during iterative development"
  - "Deciding how to distribute a macOS app outside the App Store"
---

# macOS menu-bar apps need a real .app bundle and stable code signing

## Context

Building a SwiftUI menu-bar app (`MenuBarExtra`) as a SwiftPM executable, two
non-obvious platform facts cost real time: the menu-bar icon never appeared, and
the Accessibility permission reset on every rebuild. Both are packaging/signing
issues, not code bugs — the code was correct in both cases.

## Guidance

1. **`MenuBarExtra` / `NSStatusItem` requires a real `.app` bundle with a
   `CFBundleIdentifier`.** A bare `swift run` executable launches and runs its
   event loop fine but registers **no** status item — you get a running process
   with no menu-bar icon. Wrap the built binary in `Foo.app/Contents/{MacOS,Info.plist}`.
   `LSUIElement` (or `NSApp.setActivationPolicy(.accessory)` at runtime) hides the
   Dock icon.

2. **Sign with a stable identity, never ad-hoc, if the app needs TCC permissions.**
   macOS keys an Accessibility/Screen-Recording grant to the code's *designated
   requirement*. For an **ad-hoc** signature (`codesign --sign -`) that's
   essentially the CDHash, which changes on every rebuild — so the grant resets
   every build and the app keeps re-prompting. Signing with any stable cert (even
   a free **Apple Development** cert) makes the DR cert+bundle-id based and stable
   across rebuilds → grant once.

3. **"Apple Development" ≠ "Developer ID Application".** Apple Development is for
   running on your own machines (testing) and **cannot be notarized**. A
   downloadable app that "just works" for others needs a **Developer ID
   Application** cert + **notarization** (`notarytool`) + stapling. Both come from
   the same paid account; they are different certificate types.

## Why This Matters

Without (1) you waste time debugging "correct code that does nothing visible."
Without (2) you (and every contributor) re-grant Accessibility constantly and may
wrongly conclude the permission code is broken. Without (3) you ship a DMG that
hits a hard Gatekeeper block on macOS 15/26 ("app is damaged" for unsigned;
right-click-Open was removed in Sequoia), so downloaders must run
`xattr -dr com.apple.quarantine` by hand.

## When to Apply

- Any menu-bar/agent macOS app, especially SwiftPM-based (no Xcode project).
- Any app requiring Accessibility/Input-Monitoring/Screen-Recording in dev.
- Before publishing a downloadable build to GitHub Releases.

## Examples

Bundle + auto-pick best identity (Developer ID > Apple Development > ad-hoc):

```bash
# wrap the SwiftPM binary into ParallelDesktops.app, then:
SIGN_ID="$(security find-identity -v -p codesigning \
  | awk -F\" '/Developer ID Application/{print $2; exit}')"
[ -z "$SIGN_ID" ] && SIGN_ID="$(security find-identity -v -p codesigning \
  | awk -F\" '/Apple Development/{print $2; exit}')"
codesign --force --deep --options runtime --sign "$SIGN_ID" ParallelDesktops.app
```

Distribution paths:
- **One technical user now:** have them `git clone` + build — a locally-built app
  isn't quarantined, so no notarization needed.
- **Downloadable DMG:** Developer ID sign (with `--timestamp --options runtime`),
  `xcrun notarytool submit … --wait`, `xcrun stapler staple`.
