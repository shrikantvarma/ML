---
date: 2026-06-22
topic: per-space-links
status: design-approved
mock: docs/mocks/2026-06-22-per-space-links-ui-mock.html
feasibility: docs/solutions/integration-issues/macos-per-space-url-opening-needs-windowless-browser-profile.md
ideation: docs/ideation/2026-06-21-per-space-webpages-ideation.html
---

# Per-Space Links — v1 Design Spec

## Summary

Each project (macOS Space) gains a small, ordered list of **important webpages** you
open with a click. They reliably land on that project's desktop, in a browser profile you
choose, using a switch-then-open mechanism validated on-device. It rides the existing
project blueprint and the existing menu-bar surfaces — no new windows or daemons.

## Problem frame

A solo founder runs several project desktops. Each project has a handful of pages they
always want open there (Comms = LinkedIn + Gmail + Calendar). Today there's no system for
it: you re-navigate from memory, and macOS won't let an app drop a page onto a specific
Space programmatically (it's SIP-reserved — see the feasibility doc). The job is "pull up
this project's pages, here, in one click."

## What we're building (v1)

A per-project **link list** plus a **click-to-open launcher** on the existing menu-bar
surfaces, opened via the validated recipe, with the target browser profile as a
per-project setting.

## Key decisions

- **D1 — Links live on the blueprint.** Extend `Blueprint` with an ordered
  `links: [{ url, title }]`, alongside the apps it already holds. (Net-new; the blueprint
  has no URL concept today.)
- **D2 — The validated open recipe.** Opening = switch to the project's Space if needed →
  **verify the switch landed** (the switch engine already does this) → open the links with
  `--new-window --profile-directory=<the project's profile folder>`. The new window is born
  on the Space you're now on, **even when that profile has windows on other desktops**
  (validated 2026-06-22). This solves the "cold Space" case without dedicated profiles.
- **D3 — Profile is a per-project setting, not a created profile.** Each project optionally
  binds to one of the user's **existing** Chrome profiles. Stored by on-disk **folder** name
  (`Default`, `Profile 3`…), shown to the user by **display name** (mapped from Chrome's
  `Local State` → `profile.info_cache`). Default = system default browser. Per-*project*,
  not per-*link*, in v1.
- **D4 — Manual authoring in v1.** Add a link by pasting a URL (title auto-fills, editable).
  No tab-snapshot capture (that needs the Automation permission — deferred).
- **D5 — Folds into the existing bring-up.** "Bring up apps here" becomes "Bring up here"
  (apps + links together), and individual links / "Open all here" are also directly clickable.
- **D6 — Opening is permission-free for the page itself.** `open`/`NSWorkspace.open` needs no
  permission and works in any browser; only the profile-placement recipe is Chromium-specific.

## UI / UX

Reference mock: `docs/mocks/2026-06-22-per-space-links-ui-mock.html` (directional — layout
and flow, not exact styling). Four surfaces, all inside the existing menu-bar popover:

- **Project row → inline links.** A chevron + count badge on each project row; expanding
  reveals its links (favicon dot + title), each clickable, with **"Open all here"** beneath.
  Default expansion: the **current** project auto-expands; others stay collapsed (keeps the
  list short at 7–10 projects). Count badge shows number of links (`—` when none).
- **The `•••` menu** gains: **Add link…**, **Open links in profile…**; and "Bring up apps
  here" is relabeled **"Bring up here"** (apps + links).
- **Add link** — a small paste-URL form; title auto-filled and editable.
- **Open links in profile…** — a picker listing the user's Chrome profiles by display name
  (folder noted), plus "System default browser." One choice per project.

Visual language: carry the mock's palette (accent blue, soft tints, inline-link treatment)
into the SwiftUI implementation rather than default system styling.

## The open flow (behavior)

1. User clicks a link, "Open all here," or "Bring up here."
2. If not already on the project's Space, the switch engine switches and **verifies landing**
   (`.switched`). If the switch fails/drifts, surface the existing status message; do not open.
3. Open the link(s): first URL with `--new-window --profile-directory=<folder>` (creates the
   window on this Space); remaining URLs add tabs to that window.
4. If no profile is set, open via the system default browser (warm-case behavior; may bounce
   on a cold Space — acceptable for the no-profile path).
5. Show a brief status line (e.g., "Opened 3 pages in Comms").

## Out of scope (v1 cuts — deferred, not rejected)

- **Tab-snapshot capture** ("save my open tabs") — needs the Automation/TCC permission.
- **Dedupe** against already-open tabs — needs tab-reading.
- **Per-link** profiles (v1 is per-project).
- **Auto-learning** a project's pages from usage.
- **Non-Chromium profile placement** — Safari/Firefox links still open (plain `open`), but the
  profile-on-the-right-Space recipe is Chromium-first.
- Exact tab/session restore — outside the product's identity (already ruled out).

## Open questions (resolve in planning or build)

- **Q1 — Bounce-inform copy/threshold.** With a profile set + verified switch, the recipe
  lands correctly, so an explicit "it bounced" notice is rarely needed. Decide whether to keep
  a light "opened elsewhere" note only for the no-profile path.
- **Q2 — "Open all" sequencing.** Open all URLs into one new window (first `--new-window`,
  rest as tabs) vs. one window per link. Lean: one window, tabs.
- **Q3 — Untested edge (from feasibility doc).** "Actively in that profile's window an instant
  before switching" wasn't tested; confirm during build before relying on it on the hot path.

## References

- Feasibility & validated recipe: `docs/solutions/integration-issues/macos-per-space-url-opening-needs-windowless-browser-profile.md`
- Ideation (ranked directions): `docs/ideation/2026-06-21-per-space-webpages-ideation.html`
- UI mock: `docs/mocks/2026-06-22-per-space-links-ui-mock.html`
- Existing code this builds on: `ParallelDesktops/Sources/ParallelDesktopsCore/Model/Project.swift` (`Blueprint`), `ParallelDesktops/Sources/ParallelDesktops/AppModel.swift` (`bringUpApps`, switch engine), `ParallelDesktops/Sources/ParallelDesktops/MenuBarListView.swift` (menu surfaces).
