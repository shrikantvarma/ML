import SwiftUI
import AppKit
import ParallelDesktopsCore

// Shared infrastructure for the app's transient floating surfaces:
// resume card (U12), morning recap (U13), and search panel (U11).

/// An NSPanel that floats above other apps and can become key (so a search
/// field can receive typing) without stealing full app activation.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
enum PanelFactory {
    static func make<Content: View>(size: NSSize, content: Content) -> KeyablePanel {
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView: content)
        return panel
    }

    /// Place near the top-center of the main screen (Spotlight-ish).
    static func positionTopCenter(_ panel: NSPanel, topInset: CGFloat = 120) {
        guard let screen = NSScreen.main else { return }
        let f = panel.frame
        let x = screen.visibleFrame.midX - f.width / 2
        let y = screen.visibleFrame.maxY - f.height - topInset
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// Resolve a human app name from a bundle id for display.
@MainActor
func displayName(forBundleID id: String?) -> String {
    guard let id else { return "—" }
    if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first,
       let name = app.localizedName { return name }
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
        return FileManager.default.displayName(atPath: url.path)
    }
    return id
}

// MARK: - Resume card (U12)

@MainActor
final class ResumeCardController {
    private var panel: KeyablePanel?
    private var dismissTask: Task<Void, Never>?

    func show(_ project: Project) {
        dismissTask?.cancel()
        panel?.close()

        let card = ResumeCardView(project: project)
        let panel = PanelFactory.make(size: NSSize(width: 320, height: 120), content: card)
        PanelFactory.positionTopCenter(panel, topInset: 80)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2; panel.animator().alphaValue = 1
        }
        self.panel = panel

        // Auto-dismiss after 5s with a fade (paused dismissal isn't needed for v1).
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3; panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.panel?.close(); self?.panel = nil
            }
        })
    }
}

private struct ResumeCardView: View {
    let project: Project
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(project.emoji ?? "🗂")
                Text(project.name).font(.headline)
                Spacer()
                Text("where you left off").font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            Text(displayName(forBundleID: project.resume.frontAppBundleID))
                .font(.subheadline)
            if let title = project.resume.windowTitle {
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if let note = project.resume.note, !note.isEmpty {
                Text("“\(note)”").font(.caption).italic()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Morning recap (U13)

@MainActor
final class RecapController {
    private var panel: KeyablePanel?
    private let onEnter: (Project) -> Void

    init(onEnter: @escaping (Project) -> Void) { self.onEnter = onEnter }

    func show(_ projects: [Project]) {
        panel?.close()
        let view = RecapView(projects: projects, onEnter: { [weak self] p in
            self?.onEnter(p); self?.panel?.close(); self?.panel = nil
        }, onClose: { [weak self] in
            self?.panel?.close(); self?.panel = nil
        })
        let height = min(CGFloat(120 + projects.count * 44), 520)
        let panel = PanelFactory.make(size: NSSize(width: 380, height: height), content: view)
        PanelFactory.positionTopCenter(panel)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}

private struct RecapView: View {
    let projects: [Project]
    let onEnter: (Project) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Good morning").font(.title3.bold())
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Text("Pick up where you left off:").font(.caption).foregroundStyle(.secondary)
            ForEach(projects) { project in
                Button { onEnter(project) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text(project.emoji ?? "🗂")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name).font(.subheadline.bold())
                            if project.resume.capturedAt != nil {
                                Text(displayName(forBundleID: project.resume.frontAppBundleID)
                                     + (project.resume.note.map { " · \($0)" } ?? ""))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            } else {
                                Text("No context recorded yet").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
