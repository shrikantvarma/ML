# Multi-Display Switch Spike — Messy-State Gate (macOS 26.4.1, separate Spaces ON)

> The LAST spike's pass-bar was too weak (happy path only) and the feature was built
> then reverted. This gate exercised the **messy real-world state** the production path
> actually hits, verifying switches by **window-delta, never by eye**. Driven on a real
> two-display rig (laptop + a second display; the cross-display targeting/identity facts
> were also reproduced via a Sidecar iPad).

## How to run

```
swift run --package-path Spike spike
```
Grant the terminal **Accessibility** first. Two displays, "Displays have separate Spaces" ON.

Commands: `1` symbols · `2` list · `8` direct switch (Approach A) · `9` active-space ·
`i` identity+guard table · `r` recalibrate · `m` identity churn · `s` stale-binding ·
`n` activate-nudge probe · `p` SLPS process-server nudge probe · `b` Approach-B (Ctrl+N) de-risk.

---

## EXIT CHECKLIST — all five PASS ✅

- [x] **1. Switch to a desktop on a NON-FOCUSED secondary display, window-delta verified.**
  Terminal on display 0; `8` → a `1.x` desktop on display 1 → `✓ VISIBLE SWITCH — appeared: ["Calculator"]`,
  then `["TextEdit"]`/`["Safari"]`/`["DuckDuckGo"]` across repeats. Content desktops redraw reliably;
  the only `UNCHANGED` results were switches to **empty** desktops (nothing to composite — a test
  artifact, since real Projects always have a Blueprint). **PASS.**

- [x] **2. A desktop with an EMPTY uuid is guarded — no collision.**
  `i` showed `1.1  uuid=<EMPTY>  id64=602  trackable=NO`, summarized untrackable, never `*current*`.
  `s` → `e` with display 1 sitting on the empty desktop: `Display 1: naive=CURRENT guarded=no
  ⚠️ COLLISION the guard PREVENTS`; display 0 `naive=no guarded=no`. The exact reverted-build bug,
  reproduced and blocked by the two-sided `isTrackable` guard. **PASS.**

- [x] **3. Recalibrate targets the desktop on the FOCUSED display.**
  Focus on display 1: `r` → `CGSGetActiveSpace → 609 ⇒ focused display = Display 1`, bind target =
  display 1's current desktop, `Contrast — Display 0 current` **differed** ⇒ followed focus, not
  display 0. Flipping focus to display 0 flipped the result. **PASS.**

- [x] **4. Switching still correct AFTER the display topology churns.**
  Note: macOS 26 does **not** allow dragging a Space between displays — the real churn event is a
  display **disconnect/reconnect**. Unplug: the empty-uuid desktop (602) vanished; the two trackable
  display-1 desktops migrated to display 0 keeping **both uuid and id64** (531, 609). Replug: a
  **new** empty desktop was minted (id64 650 ≠ 602) and the trackable desktops returned to display 1,
  identity intact. Post-churn `8` → `1.2` (FDFAE5CE) → `✓ VISIBLE SWITCH — appeared: ["Safari"]`.
  No false drift; bound uuid still landed. **PASS.**

- [x] **5. Stale/leftover saved bindings don't cause a wrong "current project".**
  Persisted binding pointed at an absent uuid (simulating a deleted desktop): `s` → `k` →
  `naive=no guarded=no` on every display; `7` resolved it as NOT FOUND (drift). Never falsely
  "current". **PASS.**

### PROBE #3 — is id64 a session-stable fallback for empty-uuid desktops? → **NO.**
Across one disconnect/reconnect, the empty desktop's id64 churned `602 → (destroyed) → 650`. Empty-uuid
desktops have **no** stable identity — not uuid, not even a session id64. **Guarding empties out is the
only correct model** (CONCEPTS.md "untrackable" stands — do NOT soften to "session-trackable"). The
two-class model is confirmed: *durable* desktops keep uuid+id64 through a full unplug/replug; *ephemeral*
empties are minted/destroyed per connection event.

### Symbol resolution (command `1`) — SLS-first hedge validated
All four resolved to the **SkyLight `SLS*`** names on 26.4.1: `SLSMainConnectionID`,
`SLSCopyManagedDisplaySpaces`, `SLSGetActiveSpace`, `SLSManagedDisplaySetCurrentSpace`
(CGS\* fallback unused). The SLPS nudge symbols `_SLPSSetFrontProcessWithOptions` +
`SLPSPostEventRecordTo` also resolved.

---

## THE LOAD-BEARING FINDING — Approach A's menu-bar artifact (and why the choice flipped)

**Approach A** (direct `CGSManagedDisplaySetCurrentSpace`) switches the desktop *content* correctly
on a non-focused display, but leaves a **persistent, overlapping menu bar** on the switched display.
It occurs ONLY via the direct CGS call, never via the normal OS switch path, and does not clear on
focus. Root cause: the direct call swaps the space's window list but never tells the WindowServer to
re-evaluate that display's front process / menu bar — the activation bookkeeping the SIP-gated
Dock-mediated path does for free (matches the prior-art SIP boundary: bare switch is no-SIP, the
*clean activated* switch is the Dock/SIP part).

Two no-SIP mitigations tried and **failed**:
- `NSRunningApplication.activate()` (command `n`) — no effect (cooperatively no-ops post-Sonoma).
- SLPS `_SLPSSetFrontProcessWithOptions` + synthetic key events (command `p`) — no effect, **worse**.

Only a genuine user interaction on the target display (click its menu bar, or Ctrl+→ while focused)
clears it. There is **no no-SIP programmatic fix** within reach.

## Approach B-global (Ctrl+N) — de-risked and SELECTED ✅

The shipped v1 already uses Ctrl+N ("Switch to Desktop N"). Extending it to multi-display:

- **Shortcuts**: `Ctrl+1…5 ENABLED`, Secure Input off, Accessibility granted (the shortcut
  onboarding is already a v1 requirement, with UI in `MenuBarListView`).
- **Numbering is GLOBAL across displays and matches CGS order exactly**: `Ctrl+1→0.1 … Ctrl+3→0.3,
  Ctrl+4→1.1, Ctrl+5→1.2`. So a target's Ctrl+N number = its position in the all-displays ordered list.
- **Switches a NON-FOCUSED display**: from laptop focus (`active 3`), `Ctrl+5` switched the iPad
  (`display changed [1]`, `disappeared ["DuckDuckGo"]`) — **clean, no menu-bar overlap** (OS path).
- **Reorder consistency (the key robustness test)**: swapping the iPad's two desktops swapped the
  CGS map (`Ctrl+4→F3291C72, Ctrl+5→2DB7CDA6`), and posting `Ctrl+4` landed on the new target
  (`appeared ["Notion"]`). Map and landing track reorders in lockstep ⇒ **recompute-index-from-uuid-
  each-switch is sound**; identity stays the UUID, the index is a transient lookup.
- **Focus behavior**: switching to a desktop **with apps** (real Projects) pulls focus to that display
  (`active 4 → 697`); switching to an **empty** desktop leaves focus put. So B-global is effectively
  **focus-follows-switch** — acceptable/expected for "switch to a project to use it", and it does NOT
  break per-screen independence (both screens retain their projects; focus just indicates the keyboard).

## GATE DECISION

- [x] **PASS — proceed to plan + build with Approach B-global (Ctrl+N, global index), NOT Approach A.**
  The five functional invariants all hold (they're switch-mechanism-independent: identity guard,
  recalibrate, drift union, stale bindings). The deciding factor is the menu-bar artifact: A leaves an
  unfixable-no-SIP overlap on every cross-screen switch; **B-global is overlap-free** (OS path), is
  robust to moves/reorders (proven), and reuses the shipped v1 engine almost verbatim (only the index
  computation changes from per-display to global).

  **This inverts the design's ranking** (`...-design.md` had A preferred, B fallback) — because the
  original happy-path spike never surfaced A's overlap. The messy-state gate did.

### B-global — known constraints (carry into planning, not blockers)
- **~9-desktop cap on the TOTAL across all displays** (Ctrl+1–9). The one axis where A is better
  (uncapped). Fine for typical use; revisit if a user runs >9 desktops total. `>9` → `.notKeyable`.
- **Global index recomputed each switch** from the live all-displays list (empties count toward the
  position, since macOS numbers them too). Cheap, read-only, no side effects.
- **Verification net**: poll the target display's `currentSpaceUUID == target` after posting, so a
  numbering divergence surfaces as a *failed* switch, never a silent wrong-project.
- **Pre-ship nicety (not a gate blocker)**: re-confirm the clean menu bar on a physical second
  display (de-risked on Sidecar + corroborated by the physical-monitor "normal switching = clean"
  observation; Sidecar's compositor is special so a final physical check is prudent).

---

## Prior run — Approach A happy-path PASS (history, 2026-06-23)

Kept for reference; what the *previous* (too-weak) gate established, now superseded.
- `CGSGetActiveSpace` + `CGSManagedDisplaySetCurrentSpace` found; primary-display clean-desktop switch
  visibly worked (`appeared: ["Calculator"]`). Gap it missed: secondary-display switch, empty-uuid
  desktops, recalibrate-on-focused-display, topology churn, stale bindings — **and the menu-bar overlap
  that ultimately flips the approach choice.**
