# Parallel Project Desktops — UX Review

Date: 2026-07-05 · Reviewer: Fable 5 (static review of the SwiftUI surfaces + flows F1–F5; not run on-device).

Mockups for the top proposals: `mocks/01-menu-improved.html`, `mocks/02-switch-toast.html`, `mocks/03-resume-card-v2.html`, `mocks/04-search-panel-v2.html` (PNG renders alongside).

## The single highest-leverage change

**Give switching visible feedback outside the popover.** The product's stated success criterion is *"never silently lands on the wrong one — drift is caught, not ignored."* The engine honors this (six distinct failure modes in `SwitchResult`), but the only display channel is `model.status` — a caption *inside the popover that closed when you clicked* (`MenuBarListView.swift:76-79`). From the user's chair, a blocked switch is indistinguishable from a dead click. One transient toast (the `PanelFactory` floating-panel infrastructure already exists in `FloatingPanels.swift`) converts the app's best engineering into its most trust-building UX. See `mocks/02-switch-toast.html`.

## Flow-by-flow findings

### F2 — Switch to a project (the core loop, evaluated first)

| Friction found | Evidence | Proposed fix | Impact | Effort |
|---|---|---|---|---|
| Failed switch is invisible (heuristic: visibility of system status) | `status` written after popover closes, `AppModel.swift:320-327` | Transient failure toast; success needs nothing (landing on the desktop IS the feedback) | **High** | **Low** |
| Row gives no pre-click readiness signal beyond drift | Drift triangle exists (`MenuBarListView.swift:254`); ordinal >9 / disabled-shortcut rows look identical to healthy ones (BACKLOG knows; building past it:) | Reuse the triangle pattern: gray "no shortcut" dot + tooltip, computed from `resolveIndex` + `SymbolicHotkeys` at popover-open | High | Med |
| Clicking a drifted row is a dead end | `enter()` → status text telling you to find Recalibrate in ••• | On click of a drifted row, swap the row's action row to inline **"Recalibrate to this desktop"** (primary) + "Not now" | High | Low |
| The search panel is undiscoverable | ⌃⌥Space is bound in `AppModel.swift:61-67`; **no UI surface ever mentions it** | Footer hint in the popover: `Jump from anywhere: ⌃⌥Space` | High | **Trivial** |
| Project identity fractures across surfaces | Menu label: `emoji ?? "◳"` (`ParallelDesktopsApp.swift:40`); list row: colored SF symbol; resume card & recap: `emoji ?? "🗂"` (`FloatingPanels.swift:103,164`) — and `emoji` is not settable anywhere in the UI | One `ProjectGlyph` view used by all four surfaces (SF symbol + project color); menu-bar label falls back to the symbol image, not "◳" | Med | Low |
| `shortcutsReady` = *any* shortcut enabled | `Permissions.anySwitchShortcutEnabled` — user with only Ctrl+1 enabled passes onboarding, then desktops 2+ fail one by one | Onboarding checks shortcuts for **bound ordinals**; banner names the missing ones | Med | Med |

### F1 — Create a project

| Friction found | Evidence | Proposed fix | Impact | Effort |
|---|---|---|---|---|
| No preview of what will be captured | You learn the app count *after* saving ("Saved… (5 apps)", `AppModel.swift:186`) | Live line under the field: *"Will capture: VS Code, Terminal, Chrome"* (data already available from `AppInspector`) | Med | Low |
| Saving on desktop 10+ silently creates an unswitchable project | Engine caps at 9 (`RealDesktopEngine.swift:45`), store caps at 16 | Warn inline at save time (see edge-cases #6) | Med | Low |
| Drifted project + new desktop = duplicate-workstream trap | Nothing connects "save this desktop" to the drifted 'Sales' you're rebuilding | When drifted projects exist, offer *"or recalibrate: Sales ⚠"* under the save field | Med | Low |

### F3 — Boot / bring up

| Friction found | Evidence | Proposed fix | Impact | Effort |
|---|---|---|---|---|
| The product's marquee action is buried | "Bring up here" is the first item *inside* ••• (`MenuBarListView.swift:292`) — invisible until the menu is opened | Hover affordance on the row (a `play.fill` button next to the chevron), and a "Bring up" button on the resume card | **High** | Med |
| Outcome report crams into one caption line | `combineBringUp` produces e.g. *"Set up 'X' — 2 opened here; Slack, Figma open on another desktop (can't relocate). Opened 3 links."* in `.caption` gray | Same toast surface as switch feedback; multi-line | Med | Low |

### F4 — Leave & resume

| Friction found | Evidence | Proposed fix | Impact | Effort |
|---|---|---|---|---|
| The note loop is half-built (R11 known gap; the UX shape:) | Card displays `resume.note` (`FloatingPanels.swift:114`) but nothing ever writes one | Put the input **on the resume card itself**: a "note for next time…" field. Writing at *return* time beats an interruptive leave-prompt — you know what matters after re-orienting, and it's zero-friction to skip | **High** | Med |
| Card has no timestamp | "where you left off" — but *when*? 5 minutes or 5 days changes everything | Relative time: *"2h ago"* (`capturedAt` is already stored) | Med | **Trivial** |
| Card fires even on 10-second bounces | `activeSpaceDidChange` shows it on every return (`AppModel.swift:114-117`) | Suppress when away < ~60s | Med | Low |
| Card is display-only | No actions at the exact moment you want them | Add "Bring up apps" / "Open links" buttons | Med | Low |

### F5 — Morning recap

| Friction found | Evidence | Proposed fix | Impact | Effort |
|---|---|---|---|---|
| Never appears on day 2+ while the app keeps running | Called only from `init` (`AppModel.swift:57`) — see edge-cases #2 | Day-change/wake observers | **High** | Low |
| Rows don't show drift or staleness | `RecapView` shows name + app + note only | Reuse row glyph + drift triangle; dim projects with >3-day-old context | Low | Low |

### Cross-cutting

- **The status line is an overloaded channel** — ~15 different messages (saves, renames, link adds, switch failures, boot reports) share one gray caption with no severity or persistence. Splitting *confirmations* (stay in status) from *failures/reports* (toast) resolves most of it.
- **Hover-only destructive controls** (link ×, checklist ×: `opacity(hovered ? 1 : 0)`) are invisible to VoiceOver/keyboard users. Acceptable for a v1 solo tool; note for hardening.
- **What's strong and should not change:** capture-not-configure project creation; navigation-never-launches (`enter()` comment, `AppModel.swift:317-319`); the honest "can't relocate" report instead of focus-yanking; auto-expand of only the current project; the calm identity palette.

## Ranked quick wins (high impact ÷ low effort)

1. Switch-failure toast (`mocks/02`)
2. ⌃⌥Space hint footer (`mocks/01`)
3. Recap day-change fix (one observer)
4. Resume-card timestamp (`mocks/03`)
5. Inline recalibrate on drifted-row click (`mocks/01`)
6. "Will capture: …" preview under the save field (`mocks/01`)
7. Note input on the resume card (`mocks/03`)
