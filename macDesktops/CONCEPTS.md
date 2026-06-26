# Concepts

Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## Relationships

A Project owns one Blueprint and binds to exactly one Space, by that Space's Space UUID. When the bound Space no longer exists, the Project is in Drift; Recalibrate rebinds it to the Space the user is currently on.

## Project & Space

### Project
A named macOS desktop turned into a workspace: a binding to one Space (by its Space UUID) plus a Blueprint describing what that workspace sets up. The app's central entity — switching, capture, and resume all operate on Projects.

### Space
A macOS virtual desktop. With "Displays have separate Spaces" enabled, each display has its own ordered set of Spaces; the app treats one Space as the home of at most one Project.
*Avoid:* Desktop (user-facing UI says "desktop"; the durable identity is the Space).

### Space UUID
The stable per-Space identifier reported by the WindowServer, and the key a Project binds to — chosen because it survives reboot, unlike a Space's ordinal position (changes on reorder) or its session-scoped managed id.

A Space can lack a Space UUID: macOS reports an empty value for some desktops (seen for desktops churned by dragging between displays). Such a Space is **untrackable** — it cannot host a Project until it acquires a real UUID (recreate the desktop, or re-login).

### Blueprint
The saved contents of a Project — the apps to boot, pinned links, and checklist — that define what the Project sets up when entered.

## Displays

### Display
A physical screen attached to the Mac. With "Displays have separate Spaces" enabled, each Display owns its own ordered set of Spaces and has its own current Space — so a Space, and the Project bound to it, lives on exactly one Display at a time. A read of "the current Space" is meaningless without saying *which* Display; the app must target a specific Display when switching to or opening onto a Project's desktop.

### Focused display
The Display currently receiving keyboard input. Its current Space is what the system's "switch to desktop" shortcut acts on and what an unqualified "current Space" read returns — so a Project on a *non-focused* Display can't be reached by that shortcut, and a new window opens on the focused Display's screen rather than the Project's, unless the app places it explicitly.

## Status & processes

### Drift
The state of a Project whose bound Space is absent from every display (the desktop was deleted, not merely moved to another screen). A drifted Project cannot be switched to until recalibrated.

### Recalibrate
The act of rebinding a drifted Project to the Space the user is currently focused on, clearing its Drift.
