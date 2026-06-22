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
    /// Which project rows show their links inline. The current project auto-expands
    /// (seeded onAppear); others start collapsed to keep the list short (U5).
    @State private var expandedIDs: Set<UUID> = []

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
        .onAppear {
            model.refreshPermissions()   // re-check whenever the popover opens
            if let cur = model.currentProject?.id { expandedIDs.insert(cur) }  // auto-expand current
        }
    }

    @ViewBuilder
    private func projectRow(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if renamingID == project.id {
                    TextField("Name", text: $renameText, onCommit: {
                        model.rename(project, to: renameText); renamingID = nil
                    })
                    .textFieldStyle(.roundedBorder)
                } else {
                    let isCurrent = model.currentProject?.id == project.id
                    let links = project.blueprint.links

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

                    // Count badge: number of links, "—" when none.
                    Text(links.isEmpty ? "—" : "\(links.count)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .help(links.isEmpty ? "No links" : "\(links.count) link\(links.count == 1 ? "" : "s")")

                    // Chevron is the SOLE expand/collapse control (non-interactive when empty).
                    Button { toggleExpanded(project.id) } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(expandedIDs.contains(project.id) ? 90 : 0))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(links.isEmpty)
                    .opacity(links.isEmpty ? 0.25 : 1)

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

            if renamingID != project.id && expandedIDs.contains(project.id) {
                linksBlock(project)
            }
        }
    }

    /// The inline links revealed under an expanded project row (U5).
    @ViewBuilder
    private func linksBlock(_ project: Project) -> some View {
        let links = project.blueprint.links
        VStack(alignment: .leading, spacing: 3) {
            if links.isEmpty {
                Text("No links yet — add one with ••• ▸ Add link…")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(links) { link in
                    Button { model.openLink(link, in: project) } label: {
                        HStack(spacing: 7) {
                            Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                            Text(link.title.isEmpty ? link.url : link.title)
                                .font(.callout).lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(link.url)
                }
                Button { model.openLinks(project) } label: {
                    Text("Open all here").font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 26)
        .padding(.bottom, 2)
    }

    private func toggleExpanded(_ id: UUID) {
        if expandedIDs.contains(id) { expandedIDs.remove(id) } else { expandedIDs.insert(id) }
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
