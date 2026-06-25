# All-Desktops Switcher — Design Spec

**Status:** Approved & locked (brainstormed 2026-06-24). Ready for `/ce-plan`.
**Builds on:** the B-global multi-display work already shipped on `feat/multi-display-spaces`
(identity guard, all-displays read seam, global Ctrl+N switch, focused-display current,
per-project display badge). This spec extends the menu from "saved projects only" into a
full desktop switcher, and adds a relocate-by-reopen capability.

## Goal

Make the menu a **switcher over every live desktop across all displays**, and make the
**Project** (a named recipe of apps/links/checklist) the durable thing the user manages —
instantiated onto whatever display they want. The user clicks a project and lands on it,
on the right screen, whether a secondary display (iPad/external) is attached or not.

## Mental model (the spine of the design)

> **The Project is the durable anchor; the desktop (Space) is a disposable surface you
> project it onto.** A Space is permanently bound to the display it was created on. macOS
> gives us **read + switch + open** — never *move a Space*, *create a Space*, or *move a
> window into a Space*. Every behavior lives inside that envelope.

## Hard platform constraints (proven 2026-06-24 — do not design against these)

- **Cannot move a Space between displays.** SIP-gated (needs Dock injection, yabai-style);
  and macOS 26 forbids it even manually with "separate Spaces" ON. → No "pool desktops on
  the laptop and relocate them" architecture.
- **Cannot create/destroy Spaces programmatically.** `CGSSpaceCreate` is SIP-gated. The user
  creates desktops via Mission Control; each is born bound to the display it was made on.
- **Cannot move an existing window into a Space.** Also SIP-gated. We can only *open new*
  windows (which land on the active display's active Space) — never gather existing ones.
- **No SIP changes required of users** is a hard product constraint; all of the above stay
  off-limits.

## Proven facts this design rests on (verified live, 2026-06-24)

- **Global Ctrl+N reaches any display.** Posting the global index switches the correct
  desktop on the correct display, iPad included; focus follows there. (Control: Ctrl+2
  switched the MacBook; treatment: Ctrl+4 switched the iPad.)
- **The Space UUID is the durable key.** The iPad desktop kept the same UUID all session;
  only the runtime `ManagedSpaceID` churned (761→783→795). The app binds to the UUID.
- **macOS persists Spaces per display device.** `com.apple.spaces.plist` keys desktops by a
  per-device "Display Identifier" and remembers disconnected displays. So a reconnecting
  display usually returns its desktops with the *same UUIDs* → bindings auto-heal.
- **Empty-UUID desktops are real and persisted** (`Collapsed Space`, `uuid: ""`). The
  empty-UUID guard already built is load-bearing.
- **`CGSGetActiveSpace` tracks the focused display** (returns the iPad's space when focus is
  on the iPad) — so "which display am I on" is readable. Drives the `◉`/`◐` distinction.

## The list (menu dropdown)

Lists **all live desktops**, from the live CGS read (`displaysWithDesktops()`), **never** the
persisted plist (an accumulated mess of stale display records). Each row = a **join** of
(live desktop UUID) ⋈ (saved Project by UUID):

- **Named** → project name + icon; keeps links/apps/checklist/profile.
- **Unnamed** → "Desktop N" (the global Ctrl+N number).

### Layout (locked)

A single **flat list, global continuous numbering 1…N**, with a light **divider/label where
the display changes**; a **"Not on any display"** group at the bottom for projects whose
desktop is gone.

```
┌ Parallel Project Desktops ─────────────┐
│ ◉ 1  Build                         ⌃1  │   ◉ = current on the FOCUSED display
│ ○ 2  Main                          ⌃2  │   ◐ = current on ANOTHER display
│ ○ 3  Desktop 3                     ⌃3  │   ○ = not current
│ ··············· Display 2 · iPad ······ │   active rows are highlighted
│ ◐ 4  Research                      ⌃4  │
│ ○ 5  Desktop 5                     ⌃5  │
│ ─────────────  Not on any display ──── │
│ ⚠     Comms          [Open here ▾]      │
└─────────────────────────────────────────┘
```

- The global number triples as **position, name-fallback label, and the Ctrl+N switch key** —
  one number, no per-display renumbering, matches macOS Mission Control. Positional;
  recomputed live on menu-open (counts empty-UUID desktops, as macOS does). A *name* sticks
  to the UUID; "Desktop N" does not.
- **Multiple current markers can show at once** (one `◉` focused + one `◐` per other display)
  — the simultaneous picture a single mirrored `MenuBarExtra` label can't give. Computed for
  free from existing reads: `◉ = uuid == focusedCurrentSpaceUUID`,
  `◐ = isSpaceCurrent(uuid) && uuid != focusedCurrentSpaceUUID`.
- Divider label: ordinal + friendly name when available (`Display 2 · iPad` via
  `NSScreen.localizedName`), else `Display 2`.

## Menu-bar label (the "top")

A single `MenuBarExtra` is one mirrored status item — it cannot show different text per
display. **Decision: the label shows the focused display's current project (single value).**
Accepted, because in practice the icon only renders on the focused display's menu bar (it
gets crowded out elsewhere), so "focused-only" is correct where it appears. The dropdown is
the authoritative "what's active everywhere" view. (Multi-glyph / "+N" label styles were
prototyped and deferred — not needed.)

## Behaviors

### Go to a project — one click, app picks the cheapest path
- **Desktop alive** (common) → **switch** via global Ctrl+N. Instant; **preserves live
  windows**. Always post (the previous "already-current → skip post" special-case is
  removed). No focus logic; whatever macOS does with focus is accepted.
  - The one accepted no-op: clicking a desktop already showing on its (non-focused) display —
    nothing transitions, no visible move. Accepted, no special handling.
- **Desktop gone** → **"Open on this screen"**: bind the project to the focused display's
  current desktop and Bring-up-apps to reconstitute, with a clear message ("couldn't find its
  old desktop — opened your apps here").

### Open / relocate a project onto a chosen display (reopen capability)
Since we can't move a Space to the external screen, we place the *content*: **switch the
target display to one of its desktops, then open the project's recipe there.**
- **High-fidelity for web/links** (the Chrome-profile + URL recipe the app already has) —
  exact tabs, on the chosen desktop, deterministically.
- **Best-effort for native apps** — we can *launch* a closed app onto the target desktop, but
  cannot *gather* an already-open app's existing windows (OS limit). Messaged honestly.
- Optionally rebinds the project's home to the new desktop, so future clicks just switch.

### Name / assign in place
Inline name field on a row (mirrors the existing rename pattern). Naming an unnamed desktop
creates a Project bound to that desktop's UUID. You can name a desktop you're not on (UUID is
known); its **apps** capture only when you are actually on it.

### Auto-heal on connect/disconnect
Observe `NSApplication.didChangeScreenParametersNotification` → recompute drift + display map.
Because UUIDs usually persist across reconnect, a returning display's projects **un-drift
automatically, no user action.** (This is the small piece that makes the iPad workflow feel
seamless; pulled into v1.)

## Edge cases (resolved)

| ID | Situation | Resolution |
|----|-----------|------------|
| E1 | Named project's desktop vanished (Comms) | Keep visible in "Not on any display"; switch disabled; **Open here / Reassign** to any connected display's current desktop. |
| E2 | Click a desktop already current on the other display | **Just post the shortcut; ignore focus.** Accept the one no-op (no visible move). No focus-follow machinery in v1. |
| E3 | More than 9 desktops total | 10th+ shown greyed, "can't switch (Ctrl+N stops at 9)". Posts nothing. |
| E4 | Empty-UUID desktop | "Desktop N — no stable ID"; switch best-effort, **naming disabled** (no stable key). |
| E5 | Secondary display disconnected | Its desktops leave the live list; macOS **migrates their app windows** to a remaining display (not lost). Projects there → "Not on any display". **Reassign rebinds identity, not live windows** (OS can't move windows into a Space); use Bring-up-apps to repopulate. Usually auto-heals on reconnect (UUID persists). |
| E6 | Reboot | Built-in display UUIDs stable across reboot (v1 gate); secondary inherits E5. |
| E7 | Desktop reorder in Mission Control | Global number re-derived each switch and recomputed on menu-open → self-corrects. |

## Scope

**In (v1):**
- All-desktops list (named + unnamed), flat global numbering + display dividers, `◉`/`◐`/`○`
  markers with active-row highlight.
- Click-to-switch (always post global Ctrl+N), the smart "Go" (switch-if-alive,
  open-on-this-screen-if-gone).
- "Open / relocate project on → [display]" via reopen (links high-fidelity; native
  best-effort).
- Name/assign in place; "Not on any display" group + reassign to any connected display.
- Empty-UUID and >9 handling; friendly display labels.
- **Auto-heal on `didChangeScreenParameters`** (recompute drift + display map).
- Menu-bar label = focused-only single value.

**Out (deferred):**
- Focus-follow across displays for the E2 no-op.
- Per-project **Display-Identifier** churn-fallback (UUID auto-heal + reassign covers the
  common case; only the rare new-identity reconnect needs it).
- Multi-glyph / "+N" menu-bar label styles.
- Any window/Space topology mutation (impossible without SIP — see Hard constraints).

## Units of work (for planning)

1. **Read seam (pure, unit-testable):** a desktop-list model that joins live desktops
   (`displaysWithDesktops`) ⋈ saved Projects by UUID → ordered rows tagged {globalIndex,
   displayOrdinal, displayName, project?|unnamed, marker(focused|other|none), trackable,
   keyable(≤9)}, plus the "not on any display" projects set.
2. **AppModel:** expose the joined rows + off-display projects; refresh on
   menu-open / app-activate / drift / **screen-change**. Add the screen-change observer.
3. **Switch simplification:** always post the global Ctrl+N for a clicked desktop (drop the
   any-display short-circuit); keep verification + drift for absent/untrackable.
4. **Reopen/relocate:** generalize `bringUpApps` to target a chosen display's desktop (switch
   there, settle, open recipe); optional rebind-home. Links deterministic, native best-effort.
5. **UI:** rebuild the menu list as the flat grouped switcher (dividers, markers,
   active-row highlight, greyed >9, empty-UUID label, "Not on any display" + open/reassign),
   inline name/assign for unnamed rows, "Open on → [display]" affordance.
6. **Manual acceptance** on the real 2-display (iPad) rig.

---

## Required macOS settings (README-ready)

The app drives macOS's *own* Spaces + "Switch to Desktop N" mechanism — it doesn't
replace it. So a few system settings are prerequisites. All verified this session.

### Must be ON

1. **Displays have separate Spaces** — *System Settings → Desktop & Dock → Mission Control.*
   Gives each display its own independent desktops, so a project can live per-screen. With
   this OFF, all displays share one Space set and the multi-display switcher has nothing to
   do. **Changing it requires logging out and back in.**

2. **"Switch to Desktop N" keyboard shortcuts** — *System Settings → Keyboard → Keyboard
   Shortcuts → Mission Control.* The switch mechanism posts `Ctrl+N` for a desktop's global
   position, so each desktop you want to reach needs its shortcut enabled.
   - macOS enables only the first few by default (often 1–4/5) and **only exposes 1–9**.
   - **Enable `Switch to Desktop 1` through `9`.** A desktop whose shortcut is off can't be
     switched to — the app flags this inline with an "Enable ⌃N" link to this pane.
   - **Hard ceiling: 9 desktops total across all displays.** A 10th is shown but not
     switchable (no macOS shortcut exists).

3. **Accessibility permission** — *System Settings → Privacy & Security → Accessibility.*
   Required to post the switch keystroke and read window context. The app's onboarding banner
   prompts for it.

### Recommended OFF (predictability)

4. **Automatically rearrange Spaces based on most recent use** *(Mission Control)* — keeps
   desktop numbering/order stable (the app re-derives the index each switch, but order churn
   is confusing).

5. **When switching to an application, switch to a Space with open windows for it**
   *(Mission Control)* — avoids the "focus-yank bounce" where app-switching jumps you to
   another desktop unexpectedly.

### Known environment caveats (not settings, but worth a README note)

- **Sidecar/iPad displays churn their Space identities** (UUIDs/IDs change across reconnect)
  more than physical monitors; a project on an iPad desktop may occasionally need
  reassigning after a disconnect. Physical external monitors are stable.
- **Freshly-created desktops can briefly have "no stable ID"** (an uncommitted Space, empty
  UUID). Open a window on it (or relogin) and macOS commits a real ID; the app then lets you
  name it.
