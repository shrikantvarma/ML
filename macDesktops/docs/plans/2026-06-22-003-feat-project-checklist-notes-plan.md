---
date: 2026-06-22
type: feat
title: "Per-project checklist + content links"
status: ready
depth: standard
---

# feat: Per-project checklist + content links

## Summary

Give each project a glanceable **"what's next"**: a short, checkable list of next-actions shown
inline in the menu-bar popover, with inline quick-add — plus a one-click **"open the real
content"** link to where the depth lives (Obsidian, Google Docs, Notion, a local file, any URL).
The app stays a lightweight index + jump-off; the actual writing happens in your tool of choice.

This is capture-light and reuses patterns shipped this session: the checklist is the links model
+ the Add-link inline form with a done toggle; the content link is the existing per-space links,
extended to non-web schemes. Deliberately **not** an in-app note editor and **not** a macOS
widget in v1 — those need more thought about the app's format and are deferred.

---

## Problem Frame

A project desktop tells you *which apps/links* belong to a project, but nothing about **what you
were doing or what's next** there. The model already carries an unsurfaced per-project `note`
field with no UI to set it. Two small additions close the gap cheaply:

1. **No next-actions.** There's nowhere to jot "reply to investor · ship the fix · review PR" for
   a project and check items off as you go.
2. **No jump to the real doc.** Real planning/notes live in Obsidian/Docs/Notion; today you
   re-navigate from memory. A per-project link that opens the project's home doc in one click
   removes that.

The job: "show me this project's next steps at a glance, let me tick them off, and get me to its
real notes in one click."

---

## Requirements

- **R1 — Per-project checklist.** Each project has an ordered list of short items, each
  toggleable done/not-done, persisted with the project.
- **R2 — Inline quick-add + toggle.** Add an item via a small inline field (mirroring the Add-link
  form) and toggle/remove items directly in the popover, under the project (with its links).
- **R3 — Open the real content.** A project can link to its home doc — `https` (Docs/Notion),
  `obsidian://` (a vault note), or a local `file://` — and open it in one click.
- **R4 — Migration-safe persistence.** New fields don't break existing `projects.json` (a missing
  key migrates; a malformed value quarantines — the shipped `links` guardrail).
- **R5 — Validated open.** Content links are scheme-allowlisted and flag-injection-guarded at the
  open sink, reusing the shipped `LinkURL`/argv discipline; non-web schemes open via `NSWorkspace`,
  not the Chrome desktop-placement recipe.

---

## Key Technical Decisions

- **KTD1 — Checklist lives in-app on the blueprint.** Add `checklist: [ChecklistItem]` to
  `Blueprint` (`ChecklistItem { id, text, done }`), added with the exact `decodeIfPresent ??
  default` + `CodingKeys` pattern `links` used. No `schemaVersion` bump. (see
  `ParallelDesktops/Sources/ParallelDesktopsCore/Model/Project.swift`)
- **KTD2 — Content link reuses the links surface, extended to non-web schemes.** Rather than a new
  model, the project's home doc is an ordinary link; extend `LinkURL` to also allow `obsidian://`
  and `file://`. Web links keep the existing switch→settle→Chrome-profile recipe (place a page on
  the project's desktop); **non-web links open via `NSWorkspace.open`** after the switch — Obsidian
  and Finder route their own windows, and the desktop-placement recipe doesn't apply to them.
- **KTD3 — Glance-and-go surface, depth lives elsewhere.** The popover auto-dismisses on
  outside-click, so it's right for *quick* interactions (toggle a box, add a one-line item, click
  through to the doc) and wrong for long writing. v1 has no in-app rich editor and no WidgetKit
  widget — real notes live in the linked tool. (Deferred, see Scope Boundaries.)
- **KTD4 — Keep the testable logic in Core.** Checklist CRUD is model mutation; the genuinely
  testable new logic is the scheme-allowlist extension + the web/non-web open routing decision,
  which live in Core (`LinkURL`, `LinkOpenPlan`/a routing helper) and are unit-tested. The popover
  UI stays in the app target (verified on-device), per convention.

---

## Implementation Units

### U1. Checklist model + migration-safe persistence

- **Goal:** Introduce `ChecklistItem` and persist a per-project checklist without breaking existing
  saved files (R1, R4).
- **Requirements:** R1, R4; KTD1.
- **Dependencies:** none.
- **Files:**
  - `ParallelDesktops/Sources/ParallelDesktopsCore/Model/Project.swift`
  - `ParallelDesktops/Tests/ParallelDesktopsCoreTests/CoreTests.swift`
- **Approach:** `public struct ChecklistItem: Identifiable, Codable, Equatable { id: UUID; text:
  String; done: Bool }`. Add `checklist: [ChecklistItem]` to `Blueprint` with a `CodingKeys` case
  and `decodeIfPresent([ChecklistItem].self, forKey: .checklist) ?? []` in `Blueprint.init(from:)`;
  `encode` stays synthesized. Array order is the user's order.
- **Patterns to follow:** the `Link` type and the `links` migration pair in `Project.swift`.
- **Test scenarios:**
  - Round-trip: a project with checklist items (mixed done/not-done) survives write→reopen across
    two `ProjectStore`s, order + `done` flags preserved.
  - **Migration boundary:** an old `projects.json` with no `checklist` key decodes to `[]` (not
    quarantined); a present-but-malformed `checklist` value still quarantines.
  - `ChecklistItem` equality: same fields equal; differing `done` unequal.
- **Verification:** new round-trip + migration tests pass; existing `ProjectStoreTests` unaffected;
  `schemaVersion` unchanged.

### U2. Content-link scheme extension + web/non-web open routing

- **Goal:** Let a project link to Obsidian / a local file (not just web), and open non-web links
  correctly (R3, R5).
- **Requirements:** R3, R5; KTD2.
- **Dependencies:** none.
- **Files:**
  - `ParallelDesktops/Sources/ParallelDesktopsCore/System/BrowserLauncher.swift` (`LinkURL`)
  - `ParallelDesktops/Sources/ParallelDesktopsCore/Model/LinkOpenPlan.swift` (route web vs non-web)
  - `ParallelDesktops/Sources/ParallelDesktops/AppModel.swift` (execute the non-web branch via
    `NSWorkspace`)
  - `ParallelDesktops/Tests/ParallelDesktopsCoreTests/CoreTests.swift`
- **Approach:** Extend `LinkURL.isAllowed` to permit `http`/`https` **plus** `obsidian://` and
  `file://` (case-insensitive scheme check). Add a pure classifier (e.g. `LinkURL.isWeb(_:)`) so
  `LinkOpenPlan`/the open path routes: **web** → existing switch→settle→`openChrome`/`openDefault`
  recipe (placed on the project's desktop); **non-web** → switch to the desktop, then
  `NSWorkspace.shared.open(url)` (Obsidian/Finder place their own window). Keep the flag-injection
  guard (reject values that don't parse to a URL with an allowed scheme). `file://` paths are
  opened as-is via `NSWorkspace` (no argv/`open` shell-out, so no `-`-prefix flag risk).
- **Patterns to follow:** the shipped `LinkURL.isAllowed`, `LinkOpenPlan.make`, and the
  `openDefault` path in `SystemURLOpener`.
- **Test scenarios:**
  - `isAllowed`: `https://…`, `http://…`, `obsidian://open?vault=v&file=f`, `file:///a/b.md` → true;
    `javascript:…`, `x-apple.systempreferences://…`, bare `x.com` → false.
  - `isWeb`: `https://…`/`http://…` → true; `obsidian://…`/`file://…` → false.
  - Routing: a web link plans the Chrome/default recipe; an `obsidian://` link plans the
    NSWorkspace path (no Chrome args produced).
  - A malformed/disallowed scheme is filtered out before any open.
- **Verification:** scheme + routing tests pass; on-device, an `obsidian://` link opens the vault
  note and a Google-Docs link still opens on the project's desktop.

### U3. AppModel checklist mutators

- **Goal:** Add/toggle/remove checklist items, persisted (R1, R2).
- **Requirements:** R1, R2; KTD1.
- **Dependencies:** U1.
- **Files:**
  - `ParallelDesktops/Sources/ParallelDesktops/AppModel.swift`
- **Approach:** `addChecklistItem(_ text:to:)` (trim, ignore empty, append), `toggleChecklistItem(_
  id:in:)` (flip `done`), `removeChecklistItem(_ id:from:)`; each finds the project, mutates
  `blueprint.checklist`, calls `store.update`, refreshes `projects`/`recomputeCurrent`, surfacing
  the existing disk-error status pattern on failure. Mirror `addLink`/`setIcon`.
- **Patterns to follow:** the shipped `addLink`, `setChromeProfile`, `setIcon` mutators in
  `AppModel`.
- **Test scenarios:** `Test expectation: none — thin model mutators in the app target; the
  underlying persistence/migration is covered by U1. Verified on-device.`
- **Verification:** on-device, adding/toggling/removing items updates the popover and survives an
  app relaunch.

### U4. Popover checklist section + content-link affordance

- **Goal:** Surface the checklist (toggle + quick-add) and the "open content" link inline under
  each project (R2, R3).
- **Requirements:** R2, R3; KTD3.
- **Dependencies:** U2, U3.
- **Files:**
  - `ParallelDesktops/Sources/ParallelDesktops/MenuBarListView.swift`
- **Approach:** In the project's expanded area (where links render), add a **checklist block**:
  each item a row with a checkbox (`button` toggling `model.toggleChecklistItem`, strikethrough +
  muted when done) and a swipe/`×`/context action to remove; beneath, a **"+ add a next step…"**
  inline field mirroring `addLinkForm`. Surface a project's content link(s) with a clear **"Open"**
  affordance (e.g. a doc-icon row "Open notes →") that calls the U2 open path. Keep the mock's
  palette/treatment; reuse the rail/indent used for links.
- **Patterns to follow:** the shipped inline links block, `addLinkForm`, the expand/`expandedIDs`
  state, and the hover/row styling in `MenuBarListView`.
- **Test scenarios:** `Test expectation: none — SwiftUI view wiring in the app target; not
  unit-testable per convention. Verified on-device: add an item, check it off (strikethrough),
  remove it, and click the content link to open the doc.`
- **Verification:** on-device, the checklist shows under the project, quick-add works, toggling
  persists, and the content link opens the right doc (web on the desktop, Obsidian/file via the OS).

---

## Scope Boundaries

### Deferred to follow-up work

- **In-app note writing / rich format.** No in-app editor for long-form notes in v1 — the popover
  auto-dismisses and is wrong for writing. Needs more thought about the app's note format (your
  call). Depth lives in the linked tool.
- **macOS WidgetKit widget** (desktop / Notification-Center). A real widget is a separate extension
  with its own lifecycle/distribution — deferred; v1 is the inline popover section.
- **Checklist richness** — due dates, ordering drag-reorder, sub-items, per-item links. v1 is flat
  text items with a done toggle + add/remove.
- **Surfacing the note field elsewhere** (morning recap, resume card) — the existing `ResumeContext.note`
  integration is out of scope here.

### Not in scope (identity)

- This is a **glanceable index + jump-off**, not a notes/PKM app. It points at where the real
  content lives; it does not become the place you write.

---

## Open Questions

- **Q1 — `file://` open safety (resolve in U2).** Local-file links open via `NSWorkspace`, which
  routes by file type — opening a `.app`/script could launch it. Decide whether to restrict content
  links to document-like files or accept any (low risk for a local single-user app; the user types
  their own links). Lean: allow, but don't feed `file://` through any `open(1)` argv path (use
  `NSWorkspace` only, so there's no `-`-prefix flag surface).
- **Q2 — One content link or many?** v1 can treat the content doc as just another entry in the
  existing links list (simplest), or designate one "primary" home-doc per project shown
  prominently. Lean: reuse the links list in v1; a dedicated primary slot is a small follow-up.

---

## Risks & Dependencies

- **Persistence regression.** A non-migration-safe `checklist` field would quarantine every
  existing `projects.json`. Mitigation: KTD1 + U1's migration test pair (the `links` guardrail).
- **Scheme surface.** Allowing `obsidian://`/`file://` widens what `NSWorkspace.open` will route.
  Mitigation: keep the scheme allowlist explicit and the parse/validation guard; never route
  non-web schemes through the `open(1)` argv builder.
- **Popover crowding.** Links + checklist + actions under one project can get tall. Mitigation: the
  existing expand/collapse keeps non-current projects compact; keep item rows tight.
- **Dependency:** builds directly on shipped seams — the `links` model + migration pattern, the
  `LinkURL`/`LinkOpenPlan`/`SystemURLOpener` open path, and the inline `addLinkForm`/expand UI.

---

## Sources & Research

- **Patterns reused (shipped this session):** `ParallelDesktops/Sources/ParallelDesktopsCore/Model/{Project,LinkOpenPlan}.swift`
  (Link model + migration + open decision); `ParallelDesktops/Sources/ParallelDesktopsCore/System/BrowserLauncher.swift`
  (`LinkURL`, `URLOpening`, `SystemURLOpener`); `ParallelDesktops/Sources/ParallelDesktops/{AppModel,MenuBarListView}.swift`
  (`addLink`/`setIcon` mutators, inline `addLinkForm`, expand state); `ParallelDesktops/Tests/ParallelDesktopsCoreTests/CoreTests.swift`.
- **Unsurfaced precedent:** `ResumeContext.note` already exists on the model with no UI — evidence
  the per-project-note concept was anticipated.
- External research: not run — the feature is a direct, low-risk extension of patterns shipped and
  reviewed earlier in this session.
