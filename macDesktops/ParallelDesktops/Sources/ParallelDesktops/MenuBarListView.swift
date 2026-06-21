import SwiftUI
import AppKit
import ParallelDesktopsCore

/// The menu-bar surface: onboarding banner, project list with per-row editing,
/// "save this desktop", and click-to-enter (plan U7/U10/U14).
struct MenuBarListView: View {
    @ObservedObject var model: AppModel
    @State private var newName = ""
    @State private var renamingID: UUID?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Parallel Project Desktops").font(.headline)

            if !model.isReady { OnboardingBanner(model: model) }

            if model.projects.isEmpty {
                Text("No projects yet. Open your apps on a desktop, then save it below.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.projects) { project in projectRow(project) }
            }

            Divider()

            HStack {
                TextField("Save this desktop as…", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Save", action: save)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("To update an existing desktop's apps, use its ••• ▸ Update apps.")
                .font(.caption2).foregroundStyle(.secondary)

            if !model.status.isEmpty {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { model.refreshPermissions() }   // re-check whenever the popover opens
    }

    @ViewBuilder
    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 8) {
            if renamingID == project.id {
                TextField("Name", text: $renameText, onCommit: {
                    model.rename(project, to: renameText); renamingID = nil
                })
                .textFieldStyle(.roundedBorder)
            } else {
                let isCurrent = model.currentProject?.id == project.id
                Button { model.enter(project) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isCurrent ? "largecircle.fill.circle" : "circle")
                            .font(.caption2)
                            .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary.opacity(0.35))
                            .help(isCurrent ? "You're on this desktop" : "")
                        Text(project.emoji ?? "🗂").frame(width: 20)
                        Text(project.name).fontWeight(isCurrent ? .semibold : .regular)
                        Spacer()
                        if project.drifted {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .help("This desktop moved — Recalibrate")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Bring up apps here") { model.bringUpApps(project) }
                    Divider()
                    Button("Rename") { renameText = project.name; renamingID = project.id }
                    Button("Update apps from this desktop") { model.updateApps(project) }
                    if project.drifted {
                        Button("Recalibrate to this desktop") { model.recalibrate(project) }
                    }
                    Divider()
                    Button("Delete", role: .destructive) { model.delete(project) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
        }
    }

    private func save() {
        model.saveCurrentDesktopAsProject(name: newName)
        newName = ""
    }
}

/// Surfaces the two blockers that make switching silently no-op (plan U14/KTD-8).
private struct OnboardingBanner: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Setup needed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.subheadline.bold())
            if !model.accessibilityReady {
                Button("Grant Accessibility…") {
                    _ = Permissions.accessibilityTrusted(prompt: true)
                    open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                }
            }
            if !model.shortcutsReady {
                Button("Enable “Switch to Desktop” shortcuts…") {
                    open("x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts")
                }
                Text("System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Mission Control")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Button("Re-check") { model.refreshPermissions() }
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
