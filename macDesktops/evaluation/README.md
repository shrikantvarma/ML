# Product Evaluation — Parallel Project Desktops

Date: 2026-07-05 · Reviewer: Fable 5 · Method: static review of all app + Core sources (~2,300 LOC), grounded in CONCEPTS.md, the v1 requirements doc, and BACKLOG.md. Known BACKLOG items were **not** re-reported; two of them were found already fixed in code (see edge-cases.md header).

Everything in this folder is additive — no original file was touched.

## Contents

| File | What it is |
|---|---|
| `ux-review.md` | Dimension 1 — flow-by-flow UX review (F1–F5) with ranked friction/fix tables |
| `edge-cases.md` | Dimension 2 — 17 new edge cases with trigger, code evidence, severity, fix; plus the "genuinely unsolvable" list |
| `mocks/01-menu-improved.html` + `.png` | Menu popover before/after: inline recalibrate, readiness badge, capture preview, ⌃⌥Space hint |
| `mocks/02-switch-toast.html` + `.png` | Out-of-popover switch-failure toasts (the highest-leverage change) |
| `mocks/03-resume-card-v2.html` + `.png` | Resume card: timestamp, actions, note-input that closes the R11 loop |
| `mocks/04-search-panel-v2.html` + `.png` | Keyboard-first search: ↑/↓ selection, context-rich rows, ⌘⏎ bring-up |

## Executive summary — the 5 highest-leverage moves

1. **[EDGE+UX] Make switch failures visible.** The engine distinguishes six failure modes; the UI shows none of them (status text lives in a popover that closed when you clicked — `AppModel.swift:320`). A transient toast reusing the existing `PanelFactory` turns the product's core promise — *never silently fail* — from engine-true to user-true. (`mocks/02`)

2. **[EDGE] Refuse empty Space UUIDs at the provider boundary.** CONCEPTS.md documents that macOS reports `""` for some desktops, but `CGSSpacesProvider` passes `""`/`"?"` through and save/recalibrate only guard `nil` (`AppModel.swift:167,304`). Two untrackable desktops silently collide into one identity — corrupting binding, resume context, and drift detection at once. One filter fixes a whole failure class.

3. **[EDGE] Fix the three "long-running app" lifecycle holes.** Menu-bar apps run for weeks, but: the morning recap only fires in `init` (day 2+ never sees it, `AppModel.swift:57`); resume context is persisted only on Space change (lost on quit/shutdown, `AppModel.swift:101`); and `ProjectStore.update/remove` swallow disk-write failures (silent revert on relaunch, `ProjectStore.swift:63`). All three are small, none is visible in a demo, all three erode daily trust.

4. **[UX] Put the marquee action where the moment is.** "Bring up here" — the product's differentiator — is buried inside •••. Surface it on row-hover and on the resume card, and let the resume card also *write* the note it displays (closing the half-built R11 loop at return time, when you actually know what to say). (`mocks/01`, `mocks/03`)

5. **[UX] One project identity, four surfaces.** List rows show a colored SF-symbol; the menu-bar label shows `emoji ?? "◳"`; resume card and recap show `emoji ?? "🗂"` — and `emoji` is not settable anywhere. A single shared `ProjectGlyph` view makes the identity system (which is genuinely nice) actually land everywhere the user sees a project.

## Sequencing suggestion

Items 2 and 3 are pure-logic fixes with existing test seams (`SpacesProvider` protocol, `ProjectStore` injectable URL) — good first commits. Item 1 introduces one new UI surface and unlocks item 4's toast reuse. Item 5 is a refactor best done before any new surface is added.
