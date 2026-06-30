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
/// Plain `Text` renders reliably in the menu bar (a `Label` often shows icon-only).
/// The label is always the glyph + first letter (`Project.menuBarCompactLabel`) so it
/// stays tiny and never gets pushed off / behind the notch on a crowded menu bar —
/// the full project name shows inside the popover. (Detecting whether the OS has
/// clipped a status item isn't reliably possible, so we never grow large enough to.)
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let project = model.currentProject {
            Text(project.menuBarCompactLabel)
        } else {
            Image(systemName: "square.grid.3x3.fill")  // not on a saved project desktop
        }
    }
}

/// Runtime no-Dock-icon (LSUIElement equivalent until the Xcode/Info.plist step).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
