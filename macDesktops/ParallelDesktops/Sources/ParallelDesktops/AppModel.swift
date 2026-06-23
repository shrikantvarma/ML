import SwiftUI
import AppKit
import Carbon.HIToolbox
import ParallelDesktopsCore

/// Coordinator: wires the store, spaces read-side, and switch engine to the UI,
/// and owns the desktop observers that drive drift detection (U5), resume capture
/// (U12), and passive frame recording (U9).
@MainActor
final class AppModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var status: String = ""
    @Published var accessibilityReady: Bool = Permissions.accessibilityTrusted()
    @Published var shortcutsReady: Bool = Permissions.anySwitchShortcutEnabled()
    /// The project bound to the desktop you're currently on (nil if none) — drives
    /// the menu-bar title and the "current" marker in the list.
    @Published var currentProject: Project?

    private lazy var resumeCard = ResumeCardController()
    private lazy var recap = RecapController(onEnter: { [weak self] in self?.enter($0) })
    private lazy var search = SearchController(onEnter: { [weak self] in self?.enter($0) })
    private var hotKey: GlobalHotKey?

    private let store = ProjectStore()
    private let spaces: SpacesProvider = CGSSpacesProvider()
    private let engine: SwitchEngine
    private let urlOpener: URLOpening = SystemURLOpener()

    /// Post-switch settle before opening Chrome: a browser window is born on the
    /// Space active at creation, so we must be genuinely settled first (KTD5). 1.5s
    /// is the only on-device-validated value.
    private static let linkSettleNanos: UInt64 = 1_500_000_000

    /// Last-known per-desktop context, refreshed continuously so the OUTGOING
    /// desktop's state is available after activeSpaceDidChange fires (U12 race fix).
    private struct SpaceContext {
        var frontAppBundleID: String?
        var windowTitle: String?
        var frames: [String: WindowFrame] = [:]
    }
    private var contextBySpace: [String: SpaceContext] = [:]
    private var previousSpaceUUID: String?
    private var orderedSnapshot: [String] = []

    var isReady: Bool { accessibilityReady && shortcutsReady }

    init() {
        engine = DirectSwitchEngine(spaces: CGSSpacesProvider())
        projects = store.projects; recomputeCurrent()
        previousSpaceUUID = spaces.currentSpaceUUID()
        orderedSnapshot = spaces.orderedUserSpaceUUIDs()
        refreshCurrentContext()
        registerObservers()
        recomputeDrift()
        registerSearchHotKey()
        loadChromeProfiles()
        DispatchQueue.main.async { [weak self] in self?.maybeShowMorningRecap() }
    }

    /// ⌃⌥Space opens the type-to-search panel from any desktop (U11).
    private func registerSearchHotKey() {
        hotKey = GlobalHotKey(keyCode: UInt32(kVK_Space),
                              modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            guard let self else { return }
            self.search.toggle(projects: self.projects)
        }
    }

    // MARK: Observers (U5 / U9 / U12)

    private func registerObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                             object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.activeSpaceDidChange() }
        }
        wsCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                             object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshCurrentContext()
                self?.refreshPermissions()   // catches return from System Settings
            }
        }
    }

    func refreshPermissions() {
        accessibilityReady = Permissions.accessibilityTrusted()
        shortcutsReady = Permissions.anySwitchShortcutEnabled()
    }

    /// Cache the active desktop's front app, focused-window title, and frames.
    private func refreshCurrentContext() {
        guard let uuid = spaces.currentSpaceUUID() else { return }
        var ctx = contextBySpace[uuid] ?? SpaceContext()
        ctx.frontAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        ctx.windowTitle = AXTitleReader.focusedWindowTitle()
        ctx.frames = AppInspector.framesOnCurrentDesktop()
        contextBySpace[uuid] = ctx
    }

    private func activeSpaceDidChange() {
        // Persist the OUTGOING desktop's cached context into its project (U9/U12).
        if let outgoing = previousSpaceUUID, let ctx = contextBySpace[outgoing] {
            persist(ctx, toSpaceUUID: outgoing)
        }
        recomputeDrift()

        let newUUID = spaces.currentSpaceUUID()
        previousSpaceUUID = newUUID
        refreshCurrentContext()
        recomputeCurrent()

        // Returning to a project desktop → show its resume card (U12).
        if let newUUID, let project = store.project(forSpaceUUID: newUUID),
           project.resume.capturedAt != nil {
            resumeCard.show(project)
        }
    }

    /// Show the morning recap once per day, only if some project has context (U13).
    private func maybeShowMorningRecap() {
        let key = "lastRecapDay"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        guard UserDefaults.standard.string(forKey: key) != today else { return }
        guard projects.contains(where: { $0.resume.capturedAt != nil }) else { return } // empty-state skip
        UserDefaults.standard.set(today, forKey: key)
        recap.show(projects)
    }

    private func persist(_ ctx: SpaceContext, toSpaceUUID uuid: String) {
        guard var project = store.project(forSpaceUUID: uuid) else { return }
        project.resume = ResumeContext(
            frontAppBundleID: ctx.frontAppBundleID,
            windowTitle: ctx.windowTitle,
            note: project.resume.note,          // keep any user note
            capturedAt: Date()
        )
        for (bundleID, frame) in ctx.frames where project.blueprint.bundleIDs.contains(bundleID) {
            project.blueprint.frames[bundleID] = frame
        }
        store.update(project)
        projects = store.projects; recomputeCurrent()
    }

    private func recomputeCurrent() {
        currentProject = spaces.currentSpaceUUID().flatMap { store.project(forSpaceUUID: $0) }
    }

    private func recomputeDrift() {
        let ordered = spaces.orderedUserSpaceUUIDs()
        orderedSnapshot = ordered
        // Drift = bound desktop absent from EVERY display (truly deleted), not merely
        // moved to another screen. Using the cross-display union fixes the false
        // "desktop moved — Recalibrate" flag on multi-display setups.
        let present = spaces.allUserSpaceUUIDs()
        let drifted = Set(DriftDetector.driftedUUIDs(bound: projects.map { $0.spaceUUID }, in: present))
        for i in projects.indices where projects[i].drifted != drifted.contains(projects[i].spaceUUID) {
            projects[i].drifted = drifted.contains(projects[i].spaceUUID)
            store.update(projects[i])
        }
    }

    // MARK: Capture / edit (U7)

    /// Save the current desktop as a project — or, if it's already one, UPDATE its
    /// blueprint to the apps now open (resolves the "overwrite" question, U7).
    func saveCurrentDesktopAsProject(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let uuid = spaces.currentSpaceUUID() else {
            status = "Couldn't read the current desktop."; return
        }
        let bundleIDs = Array(Set(AppInspector.appsOnCurrentDesktop().map { $0.bundleID })).sorted()

        if var existing = store.project(forSpaceUUID: uuid) {
            existing.blueprint.bundleIDs = bundleIDs
            if !trimmed.isEmpty { existing.name = trimmed }   // optional rename on re-save
            store.update(existing)
            projects = store.projects; recomputeCurrent()
            status = "Updated “\(existing.name)” (\(bundleIDs.count) apps)."
            return
        }

        guard !trimmed.isEmpty else { status = "Name the project first."; return }
        let project = Project(name: trimmed, spaceUUID: uuid, blueprint: Blueprint(bundleIDs: bundleIDs))
        do {
            try store.add(project)
            projects = store.projects; recomputeCurrent()
            status = "Saved “\(trimmed)” (\(bundleIDs.count) apps)."
        } catch ProjectStore.StoreError.capExceeded {
            status = "Reached the desktop limit."
        } catch {
            status = "Couldn't save “\(trimmed)” — disk error."
        }
    }

    func rename(_ project: Project, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, var p = projects.first(where: { $0.id == project.id }) else { return }
        p.name = trimmed
        store.update(p); projects = store.projects; recomputeCurrent()
        status = "Renamed to “\(trimmed)”."
    }

    /// Re-capture the blueprint from the current desktop (must be ON that desktop).
    func updateApps(_ project: Project) {
        guard spaces.currentSpaceUUID() == project.spaceUUID else {
            status = "Switch to “\(project.name)” first, then update its apps."; return
        }
        guard var p = projects.first(where: { $0.id == project.id }) else { return }
        p.blueprint.bundleIDs = Array(Set(AppInspector.appsOnCurrentDesktop().map { $0.bundleID })).sorted()
        store.update(p); projects = store.projects; recomputeCurrent()
        status = "Updated “\(p.name)” apps (\(p.blueprint.bundleIDs.count))."
    }

    func delete(_ project: Project) {
        store.remove(id: project.id); projects = store.projects; recomputeCurrent()
        status = "Deleted “\(project.name)”."
    }

    // MARK: Links authoring (U6)

    /// Available Chrome profiles for the "Open links in profile…" picker. Loaded off
    /// the main thread and cached (empty when Chrome isn't installed).
    @Published var chromeProfiles: [ChromeProfile] = []
    /// Chrome's last-used profile folder — the no-setup fallback for projects that
    /// haven't pinned one. nil when Chrome isn't installed (→ default browser).
    private var chromeLastUsedFolder: String?

    private func loadChromeProfiles() {
        Task.detached(priority: .utility) {
            let info = ChromeProfiles.loadInfo()
            await MainActor.run { [weak self] in
                self?.chromeProfiles = info.profiles
                self?.chromeLastUsedFolder = info.lastUsedFolder
            }
        }
    }

    /// Append a link to a project. URL is gated to http/https (KTD8); title defaults
    /// to the URL host when the user leaves it blank.
    func addLink(_ rawURL: String, title rawTitle: String, to project: Project) {
        let url = rawURL.trimmingCharacters(in: .whitespaces)
        guard LinkURL.isAllowed(url), var p = projects.first(where: { $0.id == project.id }) else {
            status = "Enter a URL starting with http:// or https://"; return
        }
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespaces)
        let title = trimmedTitle.isEmpty ? (URL(string: url)?.host ?? url) : trimmedTitle
        p.blueprint.links.append(Link(url: url, title: title))
        store.update(p); projects = store.projects; recomputeCurrent()
        status = "Added “\(title)” to “\(p.name)”."
    }

    /// Remove a single link from a project.
    func removeLink(_ id: UUID, from project: Project) {
        guard var p = projects.first(where: { $0.id == project.id }) else { return }
        p.blueprint.links.removeAll { $0.id == id }
        store.update(p); projects = store.projects; recomputeCurrent()
    }

    // MARK: Checklist (U3)

    /// Append a next-action to a project's checklist (ignores empty text).
    func addChecklistItem(_ text: String, to project: Project) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, var p = projects.first(where: { $0.id == project.id }) else { return }
        p.blueprint.checklist.append(ChecklistItem(text: trimmed))
        store.update(p); projects = store.projects; recomputeCurrent()
    }

    /// Flip an item's done state.
    func toggleChecklistItem(_ id: UUID, in project: Project) {
        guard var p = projects.first(where: { $0.id == project.id }),
              let i = p.blueprint.checklist.firstIndex(where: { $0.id == id }) else { return }
        p.blueprint.checklist[i].done.toggle()
        store.update(p); projects = store.projects; recomputeCurrent()
    }

    /// Remove an item from the checklist.
    func removeChecklistItem(_ id: UUID, from project: Project) {
        guard var p = projects.first(where: { $0.id == project.id }) else { return }
        p.blueprint.checklist.removeAll { $0.id == id }
        store.update(p); projects = store.projects; recomputeCurrent()
    }

    /// Set (or clear → auto) the project's identity icon (an SF Symbol name).
    func setIcon(_ symbol: String?, for project: Project) {
        guard var p = projects.first(where: { $0.id == project.id }) else { return }
        p.iconName = symbol
        store.update(p); projects = store.projects; recomputeCurrent()
    }

    /// Bind (or clear, nil = system default) the Chrome profile a project opens in.
    func setChromeProfile(_ folder: String?, for project: Project) {
        guard var p = projects.first(where: { $0.id == project.id }) else { return }
        p.chromeProfileFolder = folder
        store.update(p); projects = store.projects; recomputeCurrent()
        if let folder, let name = chromeProfiles.first(where: { $0.folder == folder })?.displayName {
            status = "“\(p.name)” links open in \(name)."
        } else {
            status = "“\(p.name)” links open in your default browser."
        }
    }

    /// Rebind a drifted project to the desktop you're currently on (U5 recalibration).
    func recalibrate(_ project: Project) {
        guard let uuid = spaces.currentSpaceUUID() else { return }
        if let other = store.project(forSpaceUUID: uuid), other.id != project.id {
            status = "This desktop already hosts “\(other.name)”."; return
        }
        guard var p = projects.first(where: { $0.id == project.id }) else { return }
        p.spaceUUID = uuid; p.drifted = false
        store.update(p); projects = store.projects; recomputeCurrent()
        recomputeDrift()
        status = "Recalibrated “\(p.name)” to this desktop."
    }

    // MARK: Enter (U8)

    /// Clicking a project SWITCHES only — no side effects (plan U8, refined: boot
    /// is now an explicit on-demand action, see bringUpApps). Navigation never
    /// launches apps, so it respects apps you deliberately closed.
    func enter(_ project: Project) {
        status = "Switching to “\(project.name)”…"
        Task {
            let result = await engine.switch(toSpaceUUID: project.spaceUUID)
            status = describeSwitch(project, result)
            if case .driftDetected = result { recomputeDrift() }
        }
    }

    // MARK: Open links (U4)

    private enum LinkOpenOutcome {
        case noLinks
        case switchFailed(SwitchResult)
        case opened(Int, bounced: Bool)   // bounced: no-profile + cold Space may land elsewhere (Q1)
        case chromeFailed                 // Chrome path returned non-zero (e.g. not installed)
        case defaultFailed
    }

    /// Open every link of a project on its desktop (the "Open all here" action).
    func openLinks(_ project: Project) {
        status = "Switching to “\(project.name)”…"
        Task {
            let outcome = await switchSettleOpen(project, urls: project.blueprint.links.map(\.url))
            status = statusForLinkOpen(project, outcome)
        }
    }

    /// Open one link of a project on its desktop.
    func openLink(_ link: ParallelDesktopsCore.Link, in project: Project) {
        status = "Switching to “\(project.name)”…"
        Task {
            let outcome = await switchSettleOpen(project, urls: [link.url])
            status = statusForLinkOpen(project, outcome)
        }
    }

    /// Switch to the project's Space if needed, verify it landed, settle, then open
    /// the links via the profile recipe or the default browser (KTD2/KTD5/KTD7).
    /// Reused by `bringUpApps` after its app loop (R5).
    private func switchSettleOpen(_ project: Project, urls rawURLs: [String]) async -> LinkOpenOutcome {
        let plan = LinkOpenPlan.make(project: project,
                                     currentSpaceUUID: spaces.currentSpaceUUID(),
                                     urls: rawURLs,
                                     chromeFallbackFolder: chromeLastUsedFolder)
        guard !plan.urls.isEmpty || !plan.nonWebURLs.isEmpty else { return .noLinks }

        if plan.needsSwitch {
            let result = await engine.switch(toSpaceUUID: project.spaceUUID)
            guard case .switched = result else { return .switchFailed(result) }
            try? await Task.sleep(nanoseconds: Self.linkSettleNanos)
        }

        var opened = 0
        var chromeFailed = false

        // Web links: Chrome profile recipe (placed on this desktop) or the default browser.
        if !plan.urls.isEmpty {
            if let folder = plan.profileFolder {
                let urls = plan.urls
                // Run the blocking Process (waitUntilExit) off the main actor so the
                // menu-bar UI never freezes if `open`/Chrome is slow.
                let ok = await Task.detached { [urlOpener] in
                    urlOpener.openChrome(profileFolder: folder, urls: urls)
                }.value
                if ok { opened += plan.urls.count } else { chromeFailed = true }
            } else {
                for url in plan.urls where urlOpener.openDefault(url: url) { opened += 1 }
            }
        }

        // Non-web links (obsidian://, file://): NSWorkspace routes Obsidian/Finder's window.
        for url in plan.nonWebURLs where urlOpener.openDefault(url: url) { opened += 1 }

        if opened > 0 {
            // The bounce note applies only to web links opened via the default browser
            // on a cold switch — not to Obsidian/file opens.
            let bounced = plan.needsSwitch && plan.profileFolder == nil && !plan.urls.isEmpty
            return .opened(opened, bounced: bounced)
        }
        return chromeFailed ? .chromeFailed : .defaultFailed
    }

    private func statusForLinkOpen(_ project: Project, _ outcome: LinkOpenOutcome) -> String {
        switch outcome {
        case .noLinks:
            return "“\(project.name)” has no links yet."
        case .switchFailed(let result):
            if case .driftDetected = result { recomputeDrift() }
            return describeSwitch(project, result)
        case .opened(let n, let bounced):
            let base = "Opened \(n) page\(n == 1 ? "" : "s") in “\(project.name)”."
            return bounced ? base + " (may have opened on another desktop)" : base
        case .chromeFailed:
            return "“\(project.name)”: couldn't open links — Chrome may not be installed."
        case .defaultFailed:
            return "“\(project.name)”: couldn't open the link."
        }
    }

    /// On-demand "set up this desktop": switch there if needed, then
    ///   • launch blueprint apps that are fully closed (windows open here), and
    ///   • for apps running on another desktop, best-effort open a NEW window here
    ///     (browsers only; macOS decides the landing Space).
    /// Apps already windowed here are skipped (no duplicates).
    func bringUpApps(_ project: Project) {
        status = "Setting up “\(project.name)”…"
        Task {
            if spaces.currentSpaceUUID() != project.spaceUUID {
                let result = await engine.switch(toSpaceUUID: project.spaceUUID)
                guard case .switched = result else {
                    status = describeSwitch(project, result)
                    if case .driftDetected = result { recomputeDrift() }
                    return
                }
            }
            let here = AppInspector.bundleIDsOnCurrentDesktop()
            let selfID = Bundle.main.bundleIdentifier
            var openedHere = 0            // launched (quit) or reopened (windowless) onto this desktop
            var elsewhere: [String] = []  // running with windows on another desktop — can't relocate

            for bundleID in project.blueprint.bundleIDs where !here.contains(bundleID) {
                if bundleID == selfID { continue }  // never act on ourselves

                guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
                    // Not running at all → launch; its window opens here.
                    if await AppLauncher.launch(bundleID: bundleID) { openedHere += 1 }
                    else { elsewhere.append(bundleID) }
                    continue
                }
                // Running. ?? 1 = assume "has windows" when AX can't tell us, so we
                // never risk the focus-yank bounce on an uncertain app.
                let windows = AppInspector.windowCount(pid: app.processIdentifier) ?? 1
                if windows == 0 {
                    // Windowless (closed its windows, not quit) → reopen a window HERE.
                    if await AppLauncher.launch(bundleID: bundleID) { openedHere += 1 }
                    else { elsewhere.append(bundleID) }
                } else {
                    // Has windows on another desktop. No programmatic path found that
                    // places a window on THIS Space without bouncing (openApplication,
                    // AppleScript, and AX-driven Dock menu all activate-and-travel). So
                    // we report instead of yanking you away. See SPIKE notes.
                    elsewhere.append(bundleID)
                }
            }

            var parts: [String] = []
            if openedHere > 0 { parts.append("\(openedHere) opened here") }
            var appMsg: String
            if parts.isEmpty && elsewhere.isEmpty {
                appMsg = "“\(project.name)” already set up."
            } else {
                var msg = "Set up “\(project.name)”"
                if !parts.isEmpty { msg += " — " + parts.joined(separator: ", ") }
                if !elsewhere.isEmpty {
                    let names = elsewhere.compactMap { id in
                        NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.localizedName
                    }
                    let label = names.isEmpty ? "\(elsewhere.count)" : names.joined(separator: ", ")
                    msg += "; \(label) open on another desktop (can't relocate)"
                }
                appMsg = msg + "."
            }

            // "Bring up here" = apps + links (R5/D5). We're already settled on the
            // project's Space, so this opens without another switch.
            let linkOutcome = await switchSettleOpen(project, urls: project.blueprint.links.map(\.url))
            status = combineBringUp(appMsg, linkOutcome)
        }
    }

    private func combineBringUp(_ appMsg: String, _ outcome: LinkOpenOutcome) -> String {
        switch outcome {
        case .noLinks, .switchFailed:
            return appMsg
        case .opened(let n, _):
            return appMsg + " Opened \(n) link\(n == 1 ? "" : "s")."
        case .chromeFailed:
            return appMsg + " (Links: Chrome may not be installed.)"
        case .defaultFailed:
            return appMsg + " (Couldn't open links.)"
        }
    }

    private func describeSwitch(_ project: Project, _ result: SwitchResult) -> String {
        switch result {
        case .switched:                  return "Switched to “\(project.name)”."
        case .driftDetected:             return "“\(project.name)”: desktop moved — Recalibrate from its menu."
        case .blocked(.secureInput):     return "“\(project.name)”: blocked by Secure Input (a password field is focused)."
        case .blocked(.shortcutDisabled):return "“\(project.name)”: enable Switch-to-Desktop shortcuts in System Settings."
        case .verificationFailed:        return "“\(project.name)”: switch not confirmed — didn't land in time."
        case .notKeyable(let index):     return "“\(project.name)”: desktop \(index) has no Ctrl+number shortcut."
        }
    }

}
