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

    private lazy var resumeCard = ResumeCardController()
    private lazy var recap = RecapController(onEnter: { [weak self] in self?.enter($0) })
    private lazy var search = SearchController(onEnter: { [weak self] in self?.enter($0) })
    private var hotKey: GlobalHotKey?

    private let store = ProjectStore()
    private let spaces: SpacesProvider = CGSSpacesProvider()
    private let engine: SwitchEngine

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
        engine = RealDesktopEngine(spaces: CGSSpacesProvider())
        projects = store.projects
        previousSpaceUUID = spaces.currentSpaceUUID()
        orderedSnapshot = spaces.orderedUserSpaceUUIDs()
        refreshCurrentContext()
        registerObservers()
        recomputeDrift()
        registerSearchHotKey()
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
        projects = store.projects
    }

    private func recomputeDrift() {
        let ordered = spaces.orderedUserSpaceUUIDs()
        orderedSnapshot = ordered
        let drifted = Set(DriftDetector.driftedUUIDs(bound: projects.map { $0.spaceUUID }, in: ordered))
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
            projects = store.projects
            status = "Updated “\(existing.name)” (\(bundleIDs.count) apps)."
            return
        }

        guard !trimmed.isEmpty else { status = "Name the project first."; return }
        let project = Project(name: trimmed, spaceUUID: uuid, blueprint: Blueprint(bundleIDs: bundleIDs))
        do {
            try store.add(project)
            projects = store.projects
            status = "Saved “\(trimmed)” (\(bundleIDs.count) apps)."
        } catch {
            status = "Reached the desktop limit."
        }
    }

    func rename(_ project: Project, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, var p = projects.first(where: { $0.id == project.id }) else { return }
        p.name = trimmed
        store.update(p); projects = store.projects
        status = "Renamed to “\(trimmed)”."
    }

    /// Re-capture the blueprint from the current desktop (must be ON that desktop).
    func updateApps(_ project: Project) {
        guard spaces.currentSpaceUUID() == project.spaceUUID else {
            status = "Switch to “\(project.name)” first, then update its apps."; return
        }
        guard var p = projects.first(where: { $0.id == project.id }) else { return }
        p.blueprint.bundleIDs = Array(Set(AppInspector.appsOnCurrentDesktop().map { $0.bundleID })).sorted()
        store.update(p); projects = store.projects
        status = "Updated “\(p.name)” apps (\(p.blueprint.bundleIDs.count))."
    }

    func delete(_ project: Project) {
        store.remove(id: project.id); projects = store.projects
        status = "Deleted “\(project.name)”."
    }

    /// Rebind a drifted project to the desktop you're currently on (U5 recalibration).
    func recalibrate(_ project: Project) {
        guard let uuid = spaces.currentSpaceUUID() else { return }
        if let other = store.project(forSpaceUUID: uuid), other.id != project.id {
            status = "This desktop already hosts “\(other.name)”."; return
        }
        guard var p = projects.first(where: { $0.id == project.id }) else { return }
        p.spaceUUID = uuid; p.drifted = false
        store.update(p); projects = store.projects
        recomputeDrift()
        status = "Recalibrated “\(p.name)” to this desktop."
    }

    // MARK: Enter (U8)

    func enter(_ project: Project) {
        status = "Switching to “\(project.name)”…"
        Task {
            let result = await engine.switch(toSpaceUUID: project.spaceUUID)
            switch result {
            case .switched:
                // Only launch apps that aren't running anywhere — activating an app
                // running on another desktop would yank us off this one (the bounce).
                let running = AppLauncher.runningBundleIDs()
                let launched = await AppLauncher.launchMissing(
                    blueprint: project.blueprint.bundleIDs, alreadyRunning: running)
                status = launched.isEmpty
                    ? "Entered “\(project.name)”."
                    : "Entered “\(project.name)” — launched \(launched.count) app(s)."
            case .driftDetected:
                status = "“\(project.name)”: desktop moved — Recalibrate from its menu."
                recomputeDrift()
            case .blocked(.secureInput):
                status = "“\(project.name)”: blocked by Secure Input (a password field is focused)."
            case .blocked(.shortcutDisabled):
                status = "“\(project.name)”: enable Switch-to-Desktop shortcuts in System Settings."
            case .verificationFailed:
                status = "“\(project.name)”: switch not confirmed — didn't land in time."
            case .notKeyable(let index):
                status = "“\(project.name)”: desktop \(index) has no Ctrl+number shortcut."
            }
        }
    }
}
