---
date: 2026-06-22
type: feat
title: "Per-Space Links v1"
origin: docs/brainstorms/2026-06-22-per-space-links-requirements.md
status: ready
depth: standard
---

# feat: Per-Space Links v1

## Summary

Give each project (macOS Space) a small, ordered list of **links** — important webpages it
should always have open — and a one-click launcher that lands them on that project's desktop,
in a Chrome profile chosen per project, using the on-device-validated switch→verify→settle→open
recipe. The feature extends the existing `Blueprint`, reuses the existing switch engine's
"verify it landed" gate, and adds four surfaces inside the existing menu-bar popover. No new
windows, daemons, or permissions for the page-open itself.

The one architectural first: the validated recipe needs `open -na "Google Chrome" --args
--new-window --profile-directory=<folder> <url>`, which `NSWorkspace.openApplication` cannot
faithfully reproduce — so this is the **first `Process`/`/usr/bin/open` shell-out in a
codebase that is otherwise pure AppKit**. The plan isolates it behind a pure, unit-tested
command builder plus a thin runner, mirroring the existing `AppLauncher` split.

---

## Problem Frame

A solo founder runs several project desktops. Each has a handful of pages they always want
open there (Comms = LinkedIn + Gmail + Calendar). Today there is no system: you re-navigate
from memory, and macOS will not let an app drop a page onto a specific Space programmatically
(SIP-reserved — confirmed by the WindowServer community, see origin feasibility doc). The job
is "pull up this project's pages, here, in one click."

The hard placement unknown is already solved: a **verified Space switch + brief settle +
`--new-window --profile-directory`** births a fresh window on the Space you are standing on,
*even when that profile has windows on other desktops* (validated on-device 2026-06-22). This
plan is therefore about wiring a known-good recipe cleanly into the existing model, switch
engine, and menu surfaces — not about proving feasibility.

---

## Requirements

Traced to the origin spec's decisions (D1–D6) and open flow.

- **R1 — Links on the blueprint** (D1). Each project carries an ordered list of `{url, title}`
  links, persisted alongside its apps.
- **R2 — Validated open recipe** (D2). Opening a link first switches to the project's Space if
  needed, **verifies the switch landed** (engine `.switched`), settles briefly, then opens via
  `--new-window --profile-directory=<folder>`. Never opens on a failed/drifted switch.
- **R3 — Per-project Chrome profile setting** (D3). Each project optionally binds one of the
  user's **existing** Chrome profiles, stored by on-disk **folder** name, shown by **display
  name**. Default = system default browser.
- **R4 — Manual link authoring** (D4). Add a link by pasting a URL; title auto-fills and is
  editable. No tab-snapshot capture.
- **R5 — Folds into bring-up** (D5). "Bring up apps here" becomes **"Bring up here"** (apps +
  links); individual links and "Open all here" are also directly clickable.
- **R6 — Permission-free page open** (D6). The page open itself needs no new permission and
  works in any browser; only the profile-placement recipe is Chromium-specific.
- **R7 — Status feedback.** Every open path surfaces a brief outcome on the existing
  `model.status` line (e.g. "Opened 3 pages in Comms"), and switch failures reuse the existing
  `describeSwitch` copy.

---

## Key Technical Decisions

- **KTD1 — Additive, defaulted persistence; no schema bump.** Add `links: [Link] = []` to
  `Blueprint` (and to its explicit memberwise init) and `chromeProfileFolder: String? = nil` to
  `Project`. Swift's synthesized decode substitutes the default for a missing key, so existing
  `projects.json` files decode cleanly. *Rationale:* `ProjectStore.read` treats **any** decode
  failure as corrupt and quarantines the file — a non-defaulted field would silently destroy
  every user's saved projects. This matches how `frames`/`resume`/`drifted` were already added.
  `schemaVersion` stays at `1`. (see origin: D1)
- **KTD2 — Profile setting lives on `Project`, not `Blueprint`.** The profile is per-*project*
  (D3), and `Blueprint` is the app/link recipe; a `Project`-level `chromeProfileFolder` is the
  cleaner home and keeps `Blueprint` about *what to open*, not *where*.
- **KTD3 — First shell-out, isolated behind a pure builder + thin runner.** A new
  `ChromeCommand.arguments(profileFolder:urls:) -> [String]` (pure, in Core, unit-tested) builds
  the `open` argument vector; a thin `SystemURLOpener` runs it via `Process`. *Rationale:*
  `NSWorkspace.openApplication`'s `OpenConfiguration.arguments` does not reproduce the validated
  `open -na --args --profile-directory` behavior. Mirrors `AppLauncher`'s "pure logic split from
  the system call" so the testable part lands in Core. (see origin: D2)
- **KTD4 — One window, URLs as tabs (lead approach; confirm in U3).** "Open all here" leads
  with a single `open` invocation carrying `--new-window` and all URLs as trailing args, on the
  expectation that Chrome opens them as tabs in one new window born on the current Space (avoids
  N windows and N born-on-Space races). *This is the one link in the recipe the feasibility doc
  did **not** validate — every on-device test used a single URL* — so it is a lead approach to
  **confirm during U3**, not a settled fact. **Fallback** if multi-URL-in-one-window does not
  hold: open the first URL with `--new-window --profile-directory=<folder>`, then add the
  remaining URLs as plain `open`s into that window (the origin's open-flow step 3 mechanism).
  U3's on-device verification is the decision point. (resolves Q2 by lead + fallback)
- **KTD5 — Fixed post-switch settle.** After a confirmed `.switched`, wait a fixed settle
  (named constant) before firing Chrome — the recipe is only valid once genuinely settled on the
  target Space. Firing early births the window on the *old* Space (validated failure mode). Use
  the **only validated value, ~1.5s**, as the default; the switch engine's verify-poll confirms
  the Space UUID flipped, but the settle compensates for born-on-Space lag *after* the flip,
  which is the regime the 1.5s figure measured. Name the constant so it is tunable in one place;
  confirm/trim on-device alongside Q3.
- **KTD6 — Profile picker reads Chrome `Local State`.** Folder→display-name mapping comes from
  `~/Library/Application Support/Google/Chrome/Local State` → `profile.info_cache`. The UI shows
  display names; the recipe always targets the on-disk folder. (see origin: D3)
- **KTD7 — Two open regimes by profile presence** (D6). With a profile set → the Chromium
  recipe. With no profile → `NSWorkspace.shared.open(url)` via the system default browser (warm
  case lands locally; cold case may bounce — acceptable for the no-profile path).
- **KTD8 — `http`/`https` scheme allowlist on links.** Links are restricted to `http`/`https`
  at both authoring (U6 add-link form) and open time. *Rationale:* `NSWorkspace.shared.open` and
  `open` resolve any registered scheme handler, so a `file://`, `javascript:`, or custom-scheme
  string (pasted by mistake, or arriving via a synced `projects.json`) would otherwise launch an
  unintended/privileged handler. The check is a pure, unit-tested guard in Core (rejected URLs
  surface an error status, never silently dropped).
- **KTD9 — Profile folder values validated against Chrome's naming pattern.** `ChromeProfiles`
  accepts only folder names matching `Default | Profile \d+`; anything else is dropped during
  parse. Keeps the `--profile-directory=<folder>` token from ever carrying an unexpected path
  from a corrupted or externally-written `Local State`. (defense-in-depth; one regex in the pure
  parser)

---

## High-Level Technical Design

**Component map** (new = ✚, modified = ✎):

| Component | Target / file | Role |
|---|---|---|
| `Link` ✚ | `ParallelDesktopsCore/Model/Project.swift` | `{id, url, title}` value type |
| `Blueprint.links` ✎ | `ParallelDesktopsCore/Model/Project.swift` | ordered links, defaulted `[]` |
| `Project.chromeProfileFolder` ✎ | `ParallelDesktopsCore/Model/Project.swift` | per-project profile, defaulted `nil` |
| `ChromeProfiles` ✚ | `ParallelDesktopsCore/System/ChromeProfiles.swift` | parse `Local State` → `[ {folder, displayName} ]` |
| `ChromeCommand` ✚ (pure) | `ParallelDesktopsCore/System/BrowserLauncher.swift` | build `open` arg vector |
| `URLOpening` / `SystemURLOpener` ✚ | `ParallelDesktopsCore/System/BrowserLauncher.swift` | protocol seam + `Process` runner |
| `LinkOpenPlan` ✚ (pure) | `ParallelDesktopsCore/Model/Project.swift` or new file | decide needsSwitch / profile / urls |
| `openLinks` / `bringUpApps` ✎ | `ParallelDesktops/AppModel.swift` | switch→verify→settle→open orchestration |
| link rows + `•••` items ✎ | `ParallelDesktops/MenuBarListView.swift` | inline-expandable UI surfaces |

**The open flow** (R2, reusing the `bringUpApps` switch+verify gate):

```mermaid
sequenceDiagram
    participant U as User (menu-bar)
    participant M as AppModel
    participant E as SwitchEngine
    participant O as SystemURLOpener (open)
    U->>M: click link / "Open all here" / "Bring up here"
    M->>M: currentSpaceUUID == project.spaceUUID?
    alt not on the project's Space
        M->>E: switch(toSpaceUUID:)
        E-->>M: SwitchResult
        Note over M: guard case .switched else<br/>status = describeSwitch(...); return
        M->>M: settle ~1.5s (KTD5)
    end
    alt profile set (Chromium)
        M->>O: open -na "Google Chrome" --args --new-window<br/>--profile-directory=<folder> url1 url2 …
        O-->>M: ok / fail
    else no profile
        M->>O: NSWorkspace.open(url) (system default)
    end
    M->>U: status = "Opened N pages in <project>"
```

The decision data (does it need a switch? which profile folder? which URLs?) is computed by a
pure `LinkOpenPlan` helper in Core so the branching is unit-testable; `AppModel` performs the
awaited switch, the settle, and the open. Directional — not implementation specification.

---

## Implementation Units

### U1. Link model + blueprint/project fields + migration-safe persistence

- **Goal:** Introduce the `Link` type and persist links + the per-project profile without
  breaking existing saved files.
- **Requirements:** R1, R3; KTD1, KTD2.
- **Dependencies:** none.
- **Files:**
  - `ParallelDesktops/Sources/ParallelDesktopsCore/Model/Project.swift` (add `Link`; add
    `links: [Link] = []` to `Blueprint` + its memberwise init; add `chromeProfileFolder:
    String? = nil` to `Project` + its init)
  - `ParallelDesktops/Tests/ParallelDesktopsCoreTests/CoreTests.swift` (extend `ProjectStoreTests`)
- **Approach:** `public struct Link: Identifiable, Codable, Equatable { public var id: UUID =
  UUID(); public var url: String; public var title: String }`. Keep `Blueprint`/`Project`
  `Equatable` synthesizable. **Do not** bump `ProjectStore.currentSchemaVersion`; rely on
  defaulted decode (KTD1). Array order is the user's order — no index field.
- **Patterns to follow:** the existing `WindowFrame`/`ResumeContext` value types and the
  defaulted memberwise inits in this file; `Project: Identifiable` for the `id: UUID = UUID()`
  pattern.
- **Test scenarios:**
  - `links` and `chromeProfileFolder` survive a write→reopen round-trip across two
    `ProjectStore` instances (mirror `testRoundTripAcrossInstances`), asserting order preserved.
  - **Migration safety:** a `projects.json` written *without* a `links` key (and without
    `chromeProfileFolder`) decodes to an empty `links`/`nil` profile and is **not** quarantined
    to `projects.json.corrupt` (mirror `testCorruptFileIsPreservedNotClobbered` for the raw-bytes
    setup, asserting the opposite outcome).
  - `Link` Equatable: two links with same fields compare equal; differing `url` compares unequal.
  - **Decode boundary:** missing `links` key → defaulted to `[]` (the migration case, not
    quarantined); `links` present but wrong-typed (e.g. a JSON string where an array is expected)
    → still quarantined to `.corrupt`. This asserts the exact semantic the default introduces —
    missing-key is safe, malformed-value is not.
- **Verification:** existing `ProjectStoreTests` pass; new round-trip and migration tests pass;
  no change to `schemaVersion`.

### U2. Chrome profile enumeration (`Local State` parser)

- **Goal:** Produce the folder→display-name list that backs the "Open links in profile…" picker.
- **Requirements:** R3; KTD6.
- **Dependencies:** none (independent of U1).
- **Files:**
  - `ParallelDesktops/Sources/ParallelDesktopsCore/System/ChromeProfiles.swift` (new)
  - `ParallelDesktops/Tests/ParallelDesktopsCoreTests/CoreTests.swift` (new `ChromeProfilesTests`)
- **Approach:** Split a **pure** parser from the file read. `parseProfiles(localStateJSON: Data)
  -> [ChromeProfile]` decodes `profile.info_cache` into `[{folder: String, displayName: String}]`
  (folder = the dictionary key, displayName = each entry's `name`). **Drop any entry whose folder
  does not match `Default | Profile \d+`** (KTD9), and **cap the result** at a sane bound (e.g.
  20). A thin `loadProfiles(from url:)` reads `~/Library/Application Support/Google/Chrome/Local
  State` and delegates to the pure parser. Return empty (not throw) when the file is
  absent/unreadable — Chrome may not be installed. Read off the main thread and cache the result;
  the picker (U6) reads the cache, not the disk, on open.
- **Patterns to follow:** `AppLauncher`'s pure-helper-plus-thin-system-call split.
- **Test scenarios:**
  - Pure parse of a representative `Local State` fixture yields the expected folder→name pairs,
    including the known mismatch case (folder `Default` displayed as a custom name).
  - Multiple profiles parse in a stable order; two profiles sharing a display name both appear
    with distinct folders.
  - Malformed / missing `profile.info_cache` → empty list, no throw.
  - Empty `Data` → empty list, no throw.
  - Folder-pattern guard: an entry with folder `../evil` or `System Profile` is dropped; only
    `Default` / `Profile N` entries survive (KTD9).
- **Verification:** parser tests pass; manual check on-device that real profiles enumerate with
  correct display names.

### U3. Browser launcher — pure command builder + thin `Process` runner

- **Goal:** Build and run the validated Chrome open command; provide the no-profile fallback.
- **Requirements:** R2, R6, R7; KTD3, KTD4, KTD7.
- **Dependencies:** none (pure builder); used by U4.
- **Files:**
  - `ParallelDesktops/Sources/ParallelDesktopsCore/System/BrowserLauncher.swift` (new)
  - `ParallelDesktops/Tests/ParallelDesktopsCoreTests/CoreTests.swift` (new `BrowserLauncherTests`)
- **Approach:** `enum ChromeCommand { static func arguments(profileFolder: String, urls:
  [String]) -> [String] }` returns the exact `/usr/bin/open` argv:
  `["-na", "Google Chrome", "--args", "--new-window", "--profile-directory=<folder>", url1,
  url2, …]` (one window, URLs as tabs — KTD4, lead approach). Add a pure
  `LinkURL.isAllowed(_ raw: String) -> Bool` (scheme is `http`/`https`, case-insensitive — KTD8)
  in Core; the open paths filter through it and never pass a rejected URL to `open` or
  `NSWorkspace`. Define a `protocol URLOpening` with
  `openChrome(profileFolder:urls:) -> Bool` and `openDefault(url:) -> Bool`; `SystemURLOpener`
  implements it (`Process` for the Chrome path, `NSWorkspace.shared.open` for the default path).
  The protocol seam lets U4's orchestration inject a fake.
- **Patterns to follow:** `AppLauncher` (pure `toLaunch` + thin `launch`); the protocol-seam
  convention (`docs/solutions/architecture-patterns/protocol-seams-for-untestable-system-calls.md`).
- **Test scenarios:**
  - `ChromeCommand.arguments` with one URL → exact argv incl. `--new-window` and
    `--profile-directory=Profile 3` in order.
  - With multiple URLs → all appended after the flags, order preserved (one-window-tabs contract).
  - Folder names with a space (`"Profile 3"`) are passed as a single `--profile-directory=` token
    (not split) — guards the residual folder-vs-display-name edge.
  - Empty `urls` → builder returns a vector with no trailing URL args (caller treats as no-op).
  - `LinkURL.isAllowed`: `https://x.com` / `http://x.com` → true; `file:///etc/hosts`,
    `javascript:alert(1)`, `x-apple.systempreferences://`, bare `x.com` (no scheme) → false.
- **Verification:** builder tests pass; manual on-device run confirms a new Chrome window with
  the URLs as tabs, born on the current Space.

### U4. AppModel open-links orchestration + fold into bring-up

- **Goal:** Wire switch→verify→settle→open, reusing the `bringUpApps` gate, and make "Bring up
  here" open apps **and** links.
- **Requirements:** R2, R5, R7; KTD5, KTD7, KTD8.
- **Dependencies:** U1, U3 (and the pure `LinkOpenPlan` helper).
- **Files:**
  - `ParallelDesktops/Sources/ParallelDesktops/AppModel.swift` (add `openLinks(_:)` and
    `openLink(_:in:)`; relabel/extend `bringUpApps`; inject `URLOpening`)
  - `ParallelDesktopsCore/Model/Project.swift` *(or a small new file)* — pure `LinkOpenPlan`
    helper: given current space UUID + project, returns `(needsSwitch, profileFolder?, urls)`
  - `ParallelDesktops/Tests/ParallelDesktopsCoreTests/CoreTests.swift` (test `LinkOpenPlan`)
- **Approach:** Mirror the `bringUpApps` skeleton exactly: `Task`, `if currentSpaceUUID !=
  project.spaceUUID { switch; guard case .switched else { status = describeSwitch; if
  .driftDetected { recomputeDrift() }; return } }`. **New for links:** the open is async and the
  switch+settle takes ~1.5s+, so set a **transitional** status the instant the action fires
  (e.g. `"Switching to <name>…"`) so the click isn't a dead ~1.5s. After `.switched`, await the
  fixed settle (KTD5), then **filter URLs through `LinkURL.isAllowed`** (KTD8) and branch on
  `chromeProfileFolder` (KTD7): profile set → `urlOpener.openChrome(...)`; else →
  `openDefault(url:)`. **Status outcomes:** success → `"Opened N pages in <name>"`; Chrome path
  returns `false` → `"Couldn't open links — Chrome may not be installed."`; default path fails →
  `"Couldn't open link."`; switch failure → existing `describeSwitch` copy (no open). Never
  swallow a failure silently. `bringUpApps` runs its existing app loop, then calls the
  links-open (R5). Construct `SystemURLOpener` in `AppModel.init` alongside `engine`, stored as
  `URLOpening`.
- **Execution note:** keep the testable decision logic (`LinkOpenPlan`) in Core; the
  `AppModel` orchestration itself is verified on-device, consistent with `bringUpApps` (the app
  target is not unit-tested).
- **Patterns to follow:** `bringUpApps`, `describeSwitch`, the `engine`/`SwitchResult` gate in
  `AppModel.swift`.
- **Test scenarios** (on the pure `LinkOpenPlan` helper):
  - On the project's Space already → plan reports `needsSwitch == false`.
  - On a different Space → `needsSwitch == true`.
  - Profile set → plan carries the folder and the Chrome path; profile `nil` → default path.
  - URLs preserved in blueprint order; empty links → empty plan (no-op).
  - `Test expectation: AppModel orchestration is verified on-device, not unit-tested` (matches
    `bringUpApps` convention).
- **Verification:** `LinkOpenPlan` tests pass; on-device, clicking from a cold Space switches,
  settles, and opens the pages on the right desktop; a forced switch failure surfaces the
  existing failure copy and does **not** open.

### U5. Menu-bar inline link rows (expand, count badge, Open all here)

- **Goal:** Reveal a project's links inline with a chevron + count badge; each link clickable;
  "Open all here" beneath.
- **Requirements:** R1, R5; UI mock.
- **Dependencies:** U1, U4.
- **Files:**
  - `ParallelDesktops/Sources/ParallelDesktops/MenuBarListView.swift`
- **Approach:** Turn each `projectRow`'s outer container into a `VStack` holding the existing
  `HStack` plus a conditional expanded links block. Add a chevron + count badge (count of
  `project.blueprint.links`, `—` when none) as a row element. Add `@State private var
  expandedIDs: Set<UUID>`; seed the **current** project as expanded by default (derive from
  `model.currentProject?.id`), others collapsed. Each link row = favicon dot + title, a `.plain`
  Button → `model.openLink(...)`; "Open all here" → `model.openLinks(project)`. Carry the mock's
  palette (accent blue, soft tints, inline-link treatment) rather than default styling.
- **Interaction states (specify, don't leave to guesswork):**
  - **Chevron is the sole expand/collapse control** — a dedicated `.plain` Button placed between
    the count badge and the `•••` menu, min 28×28pt tap frame. The rest of the row HStack keeps
    its existing `model.enter(project)` behavior; do not conflate "enter" with "expand."
  - **Zero links:** badge shows `—`; the chevron is non-interactive (or, if expanded, the area
    shows a single muted hint row "Add a link via ••• → Add link…"). "Open all here" does **not**
    render when `links.isEmpty`.
- **Patterns to follow:** the existing `projectRow` `HStack`, the `renamingID`-keyed `@State`
  pattern, `.menuStyle(.borderlessButton)`; the mock `docs/mocks/2026-06-22-per-space-links-ui-mock.html`.
- **Test scenarios:** `Test expectation: none — SwiftUI view wiring in the app target; not
  unit-testable per the existing convention. Verified by on-device interaction.`
- **Verification:** on-device — current project auto-expands; chevron toggles; badge shows the
  right count; clicking a link / "Open all here" triggers the open flow; layout matches the mock.

### U6. `•••` menu items — Add link, Open links in profile, relabel

- **Goal:** Add link authoring, the profile picker, and the "Bring up here" relabel to the
  per-row `•••` menu.
- **Requirements:** R3, R4, R5; KTD8, KTD9.
- **Dependencies:** U1, U2, U4.
- **Files:**
  - `ParallelDesktops/Sources/ParallelDesktops/MenuBarListView.swift`
  - `ParallelDesktops/Sources/ParallelDesktops/AppModel.swift` (mutators: `addLink(_:to:)`,
    `setChromeProfile(_:for:)`, persisting via `ProjectStore.update`)
- **Approach:** In `projectRow`'s `Menu`: relabel "Bring up apps here" → **"Bring up here"**
  (R5); add **"Add link…"** (inline paste-URL form, mirroring the rename `TextField` pattern —
  title auto-fills from the URL host, editable) and **"Open links in profile…"** (picker listing
  `ChromeProfiles.loadProfiles()` display names + folder note, plus "System default browser";
  one choice per project, persisted to `chromeProfileFolder`). New `AppModel` mutators append the
  link / set the folder and call `store.update(project)`, surfacing disk-error status on failure
  (existing pattern).
- **Interaction states (specify, don't leave to guesswork):**
  - **Add-link validation:** the Add button is disabled until `URL(string:)` parses and the
    scheme is `http`/`https` (KTD8); on invalid input show an inline helper ("Enter a URL
    starting with https://"). Duplicates are accepted silently in v1 (user controls order).
  - **Title auto-fill is host-only in v1:** seed the editable title from `url.host` (no network
    fetch). The mock's richer "Intercom — Inbox" is illustrative, not a v1 requirement.
  - **Chrome-not-installed:** when `ChromeProfiles.loadProfiles()` is empty, hide the "Open links
    in profile…" item (or show it disabled with "Chrome not found"); "System default browser"
    remains the implicit default via the no-profile path.
- **Patterns to follow:** the existing `•••` `Menu` items and `model.updateApps`; the inline
  rename `TextField` as the precedent for the Add-link form; `ProjectStore.update` + status on
  failure in `AppModel`.
- **Test scenarios:** `Test expectation: none — view/menu wiring in the app target. The
  underlying persistence (links + profile folder) is covered by U1's round-trip tests; the
  profile list is covered by U2. Verified on-device for the menu interactions.`
- **Verification:** on-device — Add link appends a link with an auto-filled editable title;
  the profile picker lists real Chrome profiles by display name and persists the choice;
  "Bring up here" opens apps and links together; choices survive an app relaunch.

---

## Scope Boundaries

### Deferred for later (from origin — deferred, not rejected)

- **Tab-snapshot capture** ("save my open tabs") — needs the Automation/TCC permission.
- **Dedupe** against already-open tabs — needs tab-reading.
- **Per-link** profiles (v1 is per-project).
- **Auto-learning** a project's pages from usage.
- **Non-Chromium profile placement** — Safari/Firefox links still open (plain `open`), but the
  profile-on-the-right-Space recipe is Chromium-first.

### Outside this product's identity (from origin)

- Exact tab/session restore — already ruled out upstream.

### Deferred to follow-up work (plan-local)

- Drag-and-drop reordering / inline editing/deletion of existing links — v1 ships add + open;
  manage-list affordances can follow once the surface proves out.
- Favicon fetching — v1 uses a simple colored dot per the mock; real favicons are a polish pass.

---

## Open Questions

- **Q1 — No-profile cold-Space copy (approach resolved, copy deferred to U4).** Approach is
  settled: keep a single light note on the **no-profile** path only (e.g. "Opened — may have
  landed on another desktop"); the profile path lands correctly and needs no bounce notice. Only
  the exact wording is deferred to U4.
- **Q3 — Untested hot edge (defer to build).** The "actively in that profile's window an instant
  before switching, no cool-off" case was not validated. Confirm on-device during U4 before
  relying on it on the hot path; the fixed settle (KTD5) is the mitigation if it proves flaky.

---

## Risks & Dependencies

- **Persistence regression (high if mishandled).** A non-defaulted new field would quarantine
  every existing `projects.json`. KTD1 + U1's migration test are the guardrail — do not skip.
- **Settle timing is load-bearing.** Firing Chrome before the Space settles births the window on
  the wrong desktop (validated failure). KTD5's fixed settle + the `.switched` gate mitigate; Q3
  is the residual.
- **First shell-out in the codebase.** `Process`/`/usr/bin/open` is new here; isolating it behind
  `URLOpening` keeps the blast radius to one file and keeps the logic testable (KTD3).
- **App Sandbox stance (state it, even though v1 is unaffected).** A sandboxed app cannot spawn
  `/usr/bin/open`. v1 is a non-sandboxed dev SwiftPM build, and the app already depends on
  private CGS Spaces APIs + synthetic key events that are themselves sandbox-incompatible — so
  the de-facto position is **non-sandboxed**, and the `Process` call is fine. Flagged so that a
  future Xcode/notarization migration knows the Chrome path needs either no-sandbox or a
  temporary-exception entitlement.
- **Folder-vs-display-name mismatch.** Targeting a display name instead of the on-disk folder
  silently opens the wrong profile. KTD6 + U3's space-in-folder test guard this.
- **Dependency:** the synthetic Ctrl+number switch relies on the app's existing Accessibility
  grant and the "Switch to Desktop N" shortcuts (off by default, ~9–16 cap) — pre-existing
  behavior of the switch engine, not new to this feature.

---

## Sources & Research

- **Origin requirements:** `docs/brainstorms/2026-06-22-per-space-links-requirements.md`
- **Validated recipe & feasibility:**
  `docs/solutions/integration-issues/macos-per-space-url-opening-needs-windowless-browser-profile.md`
- **Sibling constraint (app-window placement):**
  `docs/solutions/integration-issues/macos-openapplication-activates-app-on-other-space.md`
- **Spaces UUID keying:** `docs/solutions/tooling-decisions/macos-private-cgs-spaces-access.md`
- **Testing convention:**
  `docs/solutions/architecture-patterns/protocol-seams-for-untestable-system-calls.md`
- **UI mock:** `docs/mocks/2026-06-22-per-space-links-ui-mock.html`
- **Code seams extended:** `ParallelDesktops/Sources/ParallelDesktopsCore/Model/Project.swift`,
  `ParallelDesktops/Sources/ParallelDesktopsCore/Model/ProjectStore.swift`,
  `ParallelDesktops/Sources/ParallelDesktopsCore/System/AppLauncher.swift`,
  `ParallelDesktops/Sources/ParallelDesktops/AppModel.swift`,
  `ParallelDesktops/Sources/ParallelDesktops/MenuBarListView.swift`,
  `ParallelDesktops/Tests/ParallelDesktopsCoreTests/CoreTests.swift`
- External research: **not run** — the placement unknown is already validated on-device and the
  Chrome `Local State` shape is well-understood; local patterns are strong.
