# All-Desktops Switcher — Design Spec

**Status:** Approved (brainstormed 2026-06-24). Ready for `/ce-plan`.
**Builds on:** the B-global multi-display work already shipped on `feat/multi-display-spaces`
(identity guard, all-displays read seam, global Ctrl+N switch, focused-display current,
per-project display badge). This spec extends the menu from "saved projects only" into a
full desktop switcher.

## Goal

Make the menu a **switcher over every live desktop across all displays** — so the user can
see what exists on each screen and switch to any of it, including desktops on a secondary
display (iPad / external monitor). A *name* is optional metadata attached to a desktop; a
named desktop is what the app already calls a **Project** (keeps apps / links / checklist).

## Proven facts this design rests on (verified live, 2026-06-24)

- **Global Ctrl+N reaches any display.** Posting the global index switches the correct
  desktop on the correct display, iPad included; focus follows to that screen. (Control:
  Ctrl+2 switched the MacBook; treatment: Ctrl+4 switched the iPad.)
- **The Space UUID is the durable key.** Across a full session the iPad desktop kept the
  same UUID; only the runtime `ManagedSpaceID` churned (761→783→795). The app binds to the
  UUID — correct choice.
- **macOS persists Spaces per display device.** `com.apple.spaces.plist` keys desktops by a
  per-device "Display Identifier" and remembers disconnected displays (10 saved records on
  this machine). So bindings usually survive reconnect; they break only when a display
  returns under a *new* identifier.
- **Empty-UUID desktops are real and persisted** (`Collapsed Space` with `uuid: ""`). The
  empty-UUID guard already built is load-bearing.

## Model

- The menu lists **all live desktops**, obtained from the live CGS read
  (`displaysWithDesktops()` / `globalDesktopUUIDs()`), **never** the persisted plist (which
  is an accumulated mess of stale display records).
- Each desktop row = a **join** of (live desktop UUID) ⋈ (saved Project by UUID):
  - **Named** (a saved Project exists for the UUID) → show project name + icon; keeps all
    existing Project features (links, apps, checklist, profile).
  - **Unnamed** (no Project) → show **"Desktop N"** where N is the global Ctrl+N number.
- A **Project persists independently of whether its desktop is currently live.** A project
  whose UUID matches no live desktop is shown in an **"Not on any display"** group with a
  **Reassign** action; switching is disabled for it.

## Layout (locked)

A single **flat list, global continuous numbering 1…N**, with a light **divider/label where
the display changes**; an **"Not on any display"** group at the bottom.

```
┌ Parallel Project Desktops ─────────────┐
│ ◉ 1  Build                         ⌃1  │   ◉ = current on the FOCUSED display
│ ○ 2  Main                          ⌃2  │   ○ = not current
│ ○ 3  Desktop 3                     ⌃3  │
│ ··············· Display 2 · iPad ······ │   divider names the display
│ ◐ 4  Research                      ⌃4  │   ◐ = current on the OTHER display
│ ○ 5  Desktop 5                     ⌃5  │
│ ─────────────  Not on any display ──── │
│ ⚠     Comms                  [Reassign]│
└─────────────────────────────────────────┘
```

- **Global number** triples as position, name-fallback label, and the actual Ctrl+N switch
  key — one number, no per-display renumbering, matches macOS Mission Control.
- The number is **positional** (recomputed live on menu-open; counts empty-UUID desktops as
  macOS does). A **name** sticks to the UUID; the "Desktop N" fallback does not.
- **Two current markers can show at once** (`◉` focused display, `◐` other display) — the
  thing a single mirrored `MenuBarExtra` label can never show.
- Display divider label: ordinal + friendly name when available (`Display 2 · iPad` via
  `NSScreen.localizedName`), else `Display 2`.

## Behaviors

### Switch (kept simple — decided)
Click a desktop → resolve its **global Ctrl+N index** → **post the shortcut. Done.**
No focus logic, no "which display am I on" branching. Always post for a live trackable
desktop (drop the previous "already-current → skip post" special-case). Whatever macOS does
with focus is accepted.
- Switching the secondary display to a *different* desktop brings it forward (focus follows)
  — proven.
- The single accepted no-op: clicking a desktop that is **already showing** on its display —
  macOS has nothing to transition, so no visible movement. Accepted, no special handling.

### Name / assign (in place)
- Inline name field on a row (mirrors the existing rename pattern). Naming an unnamed desktop
  creates a Project bound to that desktop's UUID.
- You can name a desktop you are **not** currently on (its UUID is known); its **apps** are
  captured only when you are actually on it.

### Reassign
- A Project in the "Not on any display" group can be reassigned to the desktop you are on
  (existing recalibrate, focused-display + `isTrackable` guarded).

## Edge cases (resolved)

| ID | Situation | Resolution |
|----|-----------|------------|
| E1 | Named project's desktop vanished (Comms) | Keep visible in "Not on any display" group, switch disabled, **Reassign** available. |
| E2 | Click a desktop already current on the other display | **Just post the shortcut; ignore focus.** Accept the one no-op case (no visible movement) — no focus-follow machinery in v1. |
| E3 | More than 9 desktops total | 10th+ shown greyed, "can't switch (macOS Ctrl+N stops at 9)". Posts nothing. |
| E4 | Empty-UUID desktop | Shown as "Desktop N — no stable ID"; switching best-effort, **naming disabled** (no stable key to bind). |
| E5 | Secondary display disconnected | Its desktops leave the live list; projects there move to "Not on any display". Usually return intact on reconnect (UUID persists); only need Reassign if the display returns under a new identifier. |
| E6 | Reboot | Built-in display UUIDs stable across reboot (v1 gate). Secondary inherits E5. |
| E7 | Desktop reorder in Mission Control | Global number re-derived each switch and recomputed on menu-open → self-corrects. |

## Scope

**In:** all-desktops list (named + unnamed), flat global numbering + display dividers,
name-in-place, simple click-to-switch (always post), "Not on any display" group + reassign,
empty-UUID and >9 handling, friendly display labels.

**Out (deferred):**
- **Focus-follow across displays** for the E2 no-op case (fast-follow if it ever annoys).
- **Per-project Display-Identifier storage** for smarter reconnect recovery (UUID + Reassign
  covers it for v1).
- **Per-screen overlay** (the original idea — dropped; the all-desktops list is the better
  answer to "what's on which screen").

## Units of work (for planning)

1. **Read seam:** a desktop-list model that joins live desktops (`displaysWithDesktops`) with
   saved Projects by UUID, yielding ordered rows tagged {globalIndex, displayOrdinal,
   displayName, project?|unnamed, isCurrentFocused|isCurrentOther|notCurrent, trackable,
   keyable(≤9)}. Pure, fully unit-testable against fakes.
2. **AppModel:** expose the joined rows + the "Not on any display" projects; refresh on
   menu-open / app-activate / drift (reuse existing refresh hooks).
3. **Switch simplification:** always post the global Ctrl+N for a clicked desktop (drop the
   any-display short-circuit); keep verification + drift for absent/untrackable.
4. **UI:** rebuild the menu list as the flat grouped switcher (dividers, two current markers,
   greyed >9, empty-UUID label, "Not on any display" + Reassign), inline name/assign for
   unnamed rows.
5. **Manual acceptance** on the real 2-display rig.
