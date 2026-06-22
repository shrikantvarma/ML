---
title: "Per-Space URL opening: a verified Space switch + per-profile new window lands the page correctly"
module: "macOS Spaces / browser URL opening"
date: 2026-06-21
last_updated: 2026-06-22
problem_type: integration_issue
component: tooling
severity: high
symptoms:
  - "Opening a project's URL while on its desktop sent the tab to a different desktop"
  - "A raw `open <url>` followed the browser's existing window instead of landing on the current Space"
root_cause: macos_window_space_placement
resolution_type: design_decision
tags:
  - macos
  - spaces
  - browser
  - chrome
  - url-opening
  - applespacesswitchonactivate
  - window-management
---

# Per-Space URL opening: a verified Space switch + per-profile new window lands the page correctly

Sibling finding to [`macos-openapplication-activates-app-on-other-space.md`](./macos-openapplication-activates-app-on-other-space.md).
That note covers *app* windows; this one covers *browser tabs/URLs*. Same root
cause (you cannot place a window on a Space it wasn't born on), different — and
more favorable — common case.

**Update (2026-06-22):** the original "you need a *dedicated/windowless* profile"
conclusion has been **loosened**. An existing, actively-used profile lands the page
correctly when opened via the **verified-switch + `--new-window --profile-directory`
recipe**, even when that profile already has windows on other desktops. Title and
recommendations below reflect the update.

## Problem

The "per-Space important webpages" feature wants to enter a project's desktop and
open its webpages *there* (Comms = LinkedIn + Gmail + …). A naive
`open <url>` does **not** open the page on the desktop you're standing on — it
opens it wherever the browser already has a window.

## What was tested (on-device, macOS, Chrome)

- **Bounce repro.** On desktop "Build", Chrome had a window on "Comms" and **none**
  on Build. `open -a "Google Chrome" <url>` opened the tab on **Comms** — followed
  the existing window, not the current Space.
- **Fresh-profile window lands here.** Sitting on Build, with a brand-new Chrome
  profile (no window open anywhere):
  `open -na "Google Chrome" --args --profile-directory="X" --new-window <url>`
  → the window was **born on Build**. ✓
- **Confirmed on a second desktop ("Latest").** Same command, fresh profile, after
  *settling* on Latest → window born on **Latest**. ✓
- **Timing caveat (important).** An earlier Latest attempt landed on Build because
  the command fired *before* the Space switch completed — the window is born on
  whatever Space is active **at creation time**, so the switch must finish first.
- **Warm common case works with the shared profile.** Sitting on a desktop that
  *already had its own Chrome window* (default profile, frontmost), a plain
  `open <url>` opened the tab **in that local window** — no bounce. A click-to-open
  *launcher* therefore works in everyday use whenever the current Space already holds
  the profile's frontmost window.
- **Toggle is a dead end.** With `AppleSpacesSwitchOnActivate` off, both a plain
  `open` and a forced `--new-window` on the default profile still landed on the
  profile's existing-window Space — the setting moves your *view*, not where windows
  are *born*.
- **Existing profile lands correctly after a *verified switch* (2026-06-22).** A synthetic
  Ctrl+number switch (the kind the app's engine posts) → ~1.5s settle →
  `open -na "Google Chrome" --args --new-window --profile-directory="Profile 3" <url>` put
  the new window on the **switched-to** desktop, **even though that profile already had a
  window on another desktop.** Reproduced with the user's real, actively-used profile. This
  contrasts with the earlier bare-`--new-window`-on-default bounce (see toggle bullet) — that
  was the confounded case: no explicit profile flag, manual position, toggle off.

## The rule

For **plain** `open <url>` and bare new-window calls: a new window for a browser
**profile** is born on the Space where **that profile already has a window**; only if the
profile has no window open anywhere is it born on the currently-active Space. A plain
`open <url>` simply drops the tab into the profile's existing window wherever it lives.
`AppleSpacesSwitchOnActivate` ("switch to a Space with open windows") only controls whether
your *view travels* when an app is activated — it does **not** change where a window is *born*.

**Refinement (2026-06-22) — the validated recipe.** An explicit
`open -na "Google Chrome" --args --new-window --profile-directory=<folder> <url>`, fired
while you are genuinely **settled on the target Space** (after a verified switch + brief
settle), births the window on the **current** Space — **even when that profile has windows
on other desktops.** Validated with a real, actively-used profile that had a window
elsewhere. Which factor is decisive (the explicit new-window+profile flags vs. the settled
switch) was not fully isolated, so treat the *recipe* as the validated unit.

You still **cannot relocate an already-open window** onto another Space (needs private
`CGSMoveWindowsToManagedSpace` → scripting addition / SIP off — a non-starter). The recipe
does not move a window; it *creates a new one on the Space you are already standing on.*

## What this means for the feature

- **An existing profile works — no dedicated/throwaway profile needed.** The recipe lands
  the page on the switched-to Space using the user's *own* profile, even when that profile
  has windows elsewhere. "Profile" demotes from something you *create per project* to a
  per-project **setting** — "Comms opens in my Shrikant profile."
- **The cold-Space bounce is solved by the recipe, not by profile isolation.** Per-project
  login isolation (Comms = personal Gmail, Sales = work Gmail) is still a nice *option*, but
  is no longer *required* for correct placement.
- **The plain (no-flags) path still has two regimes** — relevant for a bare "just open the
  URL" click: **warm** (a browser window is already on this Space → the tab lands there) vs.
  **cold** (none here → plain `open` bounces). The recipe is what makes the cold case reliable.

## Prevention / how to apply

- **The validated recipe:** `switch (and verify it landed) → open -na "Google Chrome"
  --args --new-window --profile-directory=<folder> <url>`. The window is born on the Space
  you settled on, regardless of where that profile has other windows.
- **Sequence after the verified switch.** Use the switch engine's confirmed `.switched`
  result before opening — opening before the switch settles births the window on the *old*
  Space (the failed early "Latest" attempt).
- **The flags matter, not raw `open`.** Plain `open <url>` drops a tab into the profile's
  existing window wherever it lives; the explicit `--new-window --profile-directory` is what
  forces a fresh window on the current Space.
- **Target the profile by on-disk folder, not display name** (see gotcha below).

## Residual edges

- **`--profile-directory` takes the on-disk *folder* name** (`Default`, `Profile 1`,
  `Profile 2`…), **not the profile's *display* name.** They frequently differ (folder
  `Default` displayed as "Person 3" on the test machine) and two profiles can share a
  display name. Map folder→name from
  `~/Library/Application Support/Google/Chrome/Local State` (`profile.info_cache`) before
  targeting one — this mismatch caused real test confusion.
- **Untested edge.** The recipe was validated with a ~1.5s settle after the switch. The
  "you were *actively in* that profile's window an instant before switching" (no cool-off)
  case is not yet confirmed. Validated *for now*; confirm before relying on it on a hot path.
- If the user manually **drags a project's window to another Space**, placement can still
  surprise; re-running the recipe (which creates a new window on the current Space) is the
  recovery.
- **Chromium-cleanest.** `--profile-directory` is clean on Chrome/Brave/Edge; Safari 17+
  profiles have no clean CLI selection and Firefox uses `-P <profile>`. Scope the recipe to
  Chromium first; the plain warm-case path works in any browser.
- `AppleSpacesSwitchOnActivate=off` was **tested and does NOT help** — it moves your *view*,
  not where windows are *born*.

## Why — confirmed by the macOS window-manager community (2026-06)

This is not a gap in cleverness; it is the designed security boundary, confirmed by
the projects that have pushed Spaces manipulation the furthest:

- **The WindowServer owns window↔Space placement, and the Dock holds the *sole
  privileged ("universal owner") connection* to it.** That is exactly why a human
  Dock "New Window" lands on the current Space and any out-of-process synthetic path
  cannot. To move arbitrary windows across Spaces you must inject a scripting addition
  **into Dock.app**, which requires **partial SIP disable** — yabai's whole model.
- **No public Spaces API exists; Apple has no plans for one.**
- **Apple keeps closing the non-SIP holes.** macOS **14.5** broke cross-Space window
  moves for yabai without the scripting addition; **Sequoia 15.0** broke Hammerspoon's
  `hs.spaces.moveWindowToSpace` entirely (returns `true`, moves nothing).

**Conclusion:** cross-Space window *relocation* is not viable for a notarized consumer app
(can't require SIP-off; can't depend on APIs Apple is removing). But you don't need it: the
verified-switch + `--new-window --profile-directory` recipe *creates* a correctly-placed
window using the user's existing profile, and the manual launcher covers the warm case —
that combination is the correct architecture, not a compromise.

Sources:
- yabai — SIP and the absence of a real Spaces API: <https://github.com/koekeishiya/yabai/discussions/2274>
- yabai — "Move window to space without disabling SIP": <https://github.com/koekeishiya/yabai/issues/795>
- yabai — "Can't move window to another space in macOS 14.5": <https://github.com/koekeishiya/yabai/issues/2272>
- Hammerspoon — `hs.spaces.moveWindowToSpace` broken on macOS 15.0 Sequoia: <https://github.com/Hammerspoon/hammerspoon/issues/3698>
- alt-tab-macos — accessing other-Space windows: <https://github.com/lwouis/alt-tab-macos/issues/447>

## Commands used (reference)

```bash
# Bounces to wherever Chrome already has a window:
open -a "Google Chrome" "https://example.com"

# VALIDATED RECIPE (2026-06-22): lands on the CURRENT Space even if the profile has
# windows on other desktops — run only AFTER a verified Space switch + brief settle.
# Use the on-disk FOLDER name for --profile-directory ("Default", "Profile 3", …),
# not the profile's display name.
open -na "Google Chrome" --args --new-window --profile-directory="Profile 3" "https://example.com"
```
