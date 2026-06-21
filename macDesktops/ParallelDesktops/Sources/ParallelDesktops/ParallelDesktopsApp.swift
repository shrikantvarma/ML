import SwiftUI
import AppKit
import ParallelDesktopsCore

@main
struct ParallelDesktopsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarListView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)  // hosts a TextField + rich list (plan U10)
    }
}

/// Status-bar label: a compact, glanceable indicator of the current project.
/// Plain `Text` renders reliably in the menu bar (a `Label` often shows icon-only);
/// the name is truncated so it never hogs menu-bar space.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    private static let maxNameChars = 14

    var body: some View {
        if let project = model.currentProject {
            Text(title(for: project))
        } else {
            Image(systemName: "square.grid.3x3.fill")  // not on a saved project desktop
        }
    }

    private func title(for project: Project) -> String {
        let name = project.name
        let shown = name.count > Self.maxNameChars
            ? name.prefix(Self.maxNameChars - 1) + "…"
            : Substring(name)
        // Emoji is the icon when set; otherwise a compact glyph stands in for it.
        let glyph = project.emoji ?? "◳"
        return "\(glyph) \(shown)"
    }
}

/// Runtime no-Dock-icon (LSUIElement equivalent until the Xcode/Info.plist step).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
