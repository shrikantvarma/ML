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
    @State private var didSeedExpansion = false
    /// Inline "Add link" form state (U6), mirroring the rename-field pattern.
    @State private var addingLinkID: UUID?
    @State private var newLinkURL = ""
    @State private var newLinkTitle = ""
    /// Hover tracking for the mock's hover tints (rows, links, "Open all").
    @State private var hoveredRowID: UUID?
    @State private var hoveredLinkID: UUID?
    @State private var hoveredOpenAllID: UUID?
    /// Which project row is showing the inline icon picker (U6 follow-up).
    @State private var iconPickingID: UUID?

    /// Palette carried from the mock (opacity-based so it adapts to light/dark).
    private enum Palette {
        static let accentSoft = Color.accentColor.opacity(0.15)
        static let hover = Color.primary.opacity(0.06)
        static let rail = Color.primary.opacity(0.12)
        static let badge = Color.primary.opacity(0.10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Parallel Project Desktops").font(.headline)

            if !model.isReady { OnboardingBanner(model: model) }

            if model.projects.isEmpty {
                Text("No projects yet. Open your apps on a desktop, then save it below.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(model.projects) { project in projectRow(project) }
                }
            }

            Divider()

            if let current = model.currentProject {
                // This desktop is already a saved project — don't offer to "save" it again.
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor).font(.caption)
                    Text("This desktop is “\(current.name)” — manage it from its row above (•••).")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack {
                    TextField("Save this desktop as…", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                    Button("Save", action: save)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Saves the apps open here as a project bound to this desktop.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

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
            // Auto-expand the current project once — re-seeding every open would
            // re-expand a row the user deliberately collapsed.
            if !didSeedExpansion, let cur = model.currentProject?.id {
                expandedIDs.insert(cur); didSeedExpansion = true
            }
        }
    }

    @ViewBuilder
    private func projectRow(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if renamingID == project.id {
                TextField("Name", text: $renameText, onCommit: {
                    model.rename(project, to: renameText); renamingID = nil
                })
                .textFieldStyle(.roundedBorder)
            } else {
                projectRowMain(project)
            }

            if iconPickingID == project.id {
                iconPicker(project)
            }
            if addingLinkID == project.id {
                addLinkForm(project)
            }
            if renamingID != project.id && addingLinkID != project.id
                && iconPickingID != project.id && expandedIDs.contains(project.id) {
                linksBlock(project)
            }
        }
    }

    /// Inline 8×2 grid of the curated glyphs, tinted to the project color; tap to set.
    @ViewBuilder
    private func iconPicker(_ project: Project) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)
        VStack(alignment: .leading, spacing: 6) {
            Text("Pick an icon for \(project.name)")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Self.projectIcons, id: \.self) { symbol in
                    let selected = projectIcon(project) == symbol
                    Button { model.setIcon(symbol, for: project); iconPickingID = nil } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 13))
                            .foregroundStyle(projectColor(project))
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(projectColor(project).opacity(selected ? 0.28 : 0.10)))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(projectColor(project), lineWidth: selected ? 1.5 : 0))
                    }
                    .buttonStyle(.plain)
                    .help(symbol)
                }
            }
            HStack {
                Spacer()
                Button("Done") { iconPickingID = nil }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.hover))
        .padding(.leading, 24)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func projectRowMain(_ project: Project) -> some View {
        let isCurrent = model.currentProject?.id == project.id
        let links = project.blueprint.links
        let hovered = hoveredRowID == project.id

        HStack(spacing: 6) {
            Button { model.enter(project) } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCurrent ? "largecircle.fill.circle" : "circle")
                        .font(.caption2)
                        .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary.opacity(0.35))
                        .help(isCurrent ? "You're on this desktop" : "")
                    Group {
                        if let emoji = project.emoji, !emoji.isEmpty {
                            Text(emoji).font(.system(size: 15))
                        } else {
                            // Glyph tinted to the project color — identity via shape +
                            // color, no background tile.
                            Image(systemName: projectIcon(project))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(projectColor(project))
                        }
                    }
                    .frame(width: 22, height: 22)
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

            // Count badge: a soft pill with the number; a faint dash when none.
            if links.isEmpty {
                Text("—")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .help("No links")
            } else {
                Text("\(links.count)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Palette.badge))
                    .help("\(links.count) link\(links.count == 1 ? "" : "s")")
            }

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
                        Button("Bring up here") { model.bringUpApps(project) }
                        Button("Add link…") { beginAddLink(project) }
                        if !model.chromeProfiles.isEmpty {
                            Menu("Open links in profile…") {
                                Button("System default browser") { model.setChromeProfile(nil, for: project) }
                                Divider()
                                ForEach(model.chromeProfiles) { prof in
                                    Button { model.setChromeProfile(prof.folder, for: project) } label: {
                                        if project.chromeProfileFolder == prof.folder {
                                            Label("\(prof.displayName) — \(prof.folder)", systemImage: "checkmark")
                                        } else {
                                            Text("\(prof.displayName) — \(prof.folder)")
                                        }
                                    }
                                }
                            }
                        }
                        Divider()
                        Button("Set icon…") { beginPickIcon(project) }
                        Button("Rename") { renameText = project.name; renamingID = project.id }
                        Button("Update apps from this desktop") { model.updateApps(project) }
                        if project.drifted {
                            Button("Recalibrate to this desktop") { model.recalibrate(project) }
                        }
                        Divider()
                        Button("Delete", role: .destructive) { model.delete(project) }
                    } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 22)
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isCurrent ? Palette.accentSoft : (hovered ? Palette.hover : Color.clear))
            )
            .onHover { inside in
                hoveredRowID = inside ? project.id : (hoveredRowID == project.id ? nil : hoveredRowID)
            }
    }

    /// Inline paste-URL form (U6): URL gated to http/https, title auto-fills from the
    /// host (editable). Duplicates accepted silently in v1. Styled as a small card.
    @ViewBuilder
    private func addLinkForm(_ project: Project) -> some View {
        let trimmed = newLinkURL.trimmingCharacters(in: .whitespaces)
        let valid = LinkURL.isAllowed(trimmed)
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("URL").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("https://…", text: $newLinkURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: newLinkURL) { _, url in
                        // Auto-seed the title from the host while it's still untouched.
                        if newLinkTitle.isEmpty, let host = URL(string: url.trimmingCharacters(in: .whitespaces))?.host {
                            newLinkTitle = host
                        }
                    }
                    .onSubmit { if valid { commitAddLink(project) } }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Title").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Title", text: $newLinkTitle)
                    .textFieldStyle(.roundedBorder)
            }
            if !trimmed.isEmpty && !valid {
                Text("Enter a URL starting with https://")
                    .font(.caption2).foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { cancelAddLink() }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Add") { commitAddLink(project) }
                    .buttonStyle(.borderedProminent).controlSize(.small).disabled(!valid)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.hover))
        .padding(.leading, 24)
        .padding(.vertical, 2)
    }

    /// The inline links revealed under an expanded project row (U5).
    @ViewBuilder
    private func linksBlock(_ project: Project) -> some View {
        let links = project.blueprint.links
        if links.isEmpty {
            Text("No links yet — add one with ••• ▸ Add link…")
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.leading, 26).padding(.bottom, 2)
        } else {
            HStack(alignment: .top, spacing: 8) {
                // The mock's indent rail down the inline links.
                RoundedRectangle(cornerRadius: 1).fill(Palette.rail).frame(width: 2)
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(links) { link in
                        Button { model.openLink(link, in: project) } label: {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(faviconColor(link))
                                    .frame(width: 14, height: 14)
                                Text(link.title.isEmpty ? link.url : link.title)
                                    .font(.callout).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(hoveredLinkID == link.id ? Palette.hover : Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { inside in
                            hoveredLinkID = inside ? link.id : (hoveredLinkID == link.id ? nil : hoveredLinkID)
                        }
                        .help(link.url)
                    }
                    Button { model.openLinks(project) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "rectangle.stack.badge.play").font(.caption)
                            Text("Open all here").font(.callout.weight(.semibold))
                            Spacer()
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(hoveredOpenAllID == project.id ? Palette.accentSoft : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        hoveredOpenAllID = inside ? project.id : (hoveredOpenAllID == project.id ? nil : hoveredOpenAllID)
                    }
                }
            }
            .padding(.leading, 24)
            .padding(.bottom, 3)
        }
    }

    /// Curated identity palette for project tiles — chosen to stay distinct and calm.
    private static let projectPalette: [Color] = [
        Color(red: 0.20, green: 0.52, blue: 0.96),  // blue
        Color(red: 0.18, green: 0.70, blue: 0.42),  // green
        Color(red: 0.95, green: 0.55, blue: 0.10),  // orange
        Color(red: 0.60, green: 0.35, blue: 0.90),  // purple
        Color(red: 0.92, green: 0.30, blue: 0.45),  // pink
        Color(red: 0.10, green: 0.65, blue: 0.72),  // teal
        Color(red: 0.85, green: 0.62, blue: 0.13),  // gold
        Color(red: 0.40, green: 0.58, blue: 0.22),  // olive
    ]

    /// Curated identity glyphs — distinct, recognizable, "project-y" (the picker set).
    static let projectIcons: [String] = [
        "folder.fill", "bubble.left.and.bubble.right.fill", "envelope.fill", "cart.fill",
        "chart.line.uptrend.xyaxis", "hammer.fill", "chevron.left.forwardslash.chevron.right", "pencil",
        "paintbrush.fill", "flask.fill", "books.vertical.fill", "megaphone.fill",
        "calendar", "lightbulb.fill", "target", "star.fill",
    ]

    /// The project's glyph: an explicit `iconName` when chosen, else a stable
    /// auto-assignment from the curated set.
    private func projectIcon(_ project: Project) -> String {
        if let chosen = project.iconName, !chosen.isEmpty { return chosen }
        var hash = 5381
        for byte in project.id.uuidString.utf8 { hash = (hash &* 33) &+ Int(byte) }
        return Self.projectIcons[abs(hash) % Self.projectIcons.count]
    }

    /// A project's identity color: its explicit `colorHex` when set (the future
    /// "Set color…" override), else a stable pick from the palette by project id.
    private func projectColor(_ project: Project) -> Color {
        if let hex = project.colorHex, let c = Color(hex: hex) { return c }
        var hash = 5381
        for byte in project.id.uuidString.utf8 { hash = (hash &* 33) &+ Int(byte) }
        return Self.projectPalette[abs(hash) % Self.projectPalette.count]
    }

    /// A brand-ish color for a link's favicon square (no network fetch in v1 — real
    /// favicons are deferred). Known hosts get their brand color; everything else gets
    /// a vivid, stable hue from the host.
    private func faviconColor(_ link: ParallelDesktopsCore.Link) -> Color {
        let host = (URL(string: link.url)?.host ?? link.url).lowercased()
        let brands: [(String, Color)] = [
            ("mail.google",     Color(red: 0.92, green: 0.26, blue: 0.21)),  // Gmail red
            ("calendar.google", Color(red: 0.10, green: 0.45, blue: 0.91)),  // Calendar blue
            ("google",          Color(red: 0.26, green: 0.52, blue: 0.96)),
            ("linkedin",        Color(red: 0.04, green: 0.40, blue: 0.76)),
            ("github",          Color(red: 0.16, green: 0.18, blue: 0.20)),
            ("notion",          Color(red: 0.10, green: 0.10, blue: 0.10)),
            ("slack",           Color(red: 0.29, green: 0.07, blue: 0.39)),
            ("figma",           Color(red: 0.95, green: 0.32, blue: 0.20)),
            ("intercom",        Color(red: 0.11, green: 0.45, blue: 0.95)),
        ]
        for (key, color) in brands where host.contains(key) { return color }
        var hash = 5381
        for byte in host.utf8 { hash = (hash &* 33) &+ Int(byte) }
        return Color(hue: Double(abs(hash) % 360) / 360.0, saturation: 0.72, brightness: 0.90)
    }

    private func toggleExpanded(_ id: UUID) {
        if expandedIDs.contains(id) { expandedIDs.remove(id) } else { expandedIDs.insert(id) }
    }

    private func beginAddLink(_ project: Project) {
        addingLinkID = project.id; newLinkURL = ""; newLinkTitle = ""
        renamingID = nil; iconPickingID = nil
    }

    private func beginPickIcon(_ project: Project) {
        iconPickingID = project.id
        renamingID = nil; addingLinkID = nil
    }

    private func commitAddLink(_ project: Project) {
        model.addLink(newLinkURL, title: newLinkTitle, to: project)
        expandedIDs.insert(project.id)   // reveal the freshly added link
        cancelAddLink()
    }

    private func cancelAddLink() {
        addingLinkID = nil; newLinkURL = ""; newLinkTitle = ""
    }

    private func save() {
        model.saveCurrentDesktopAsProject(name: newName)
        newName = ""
    }
}

extension Color {
    /// Parse `#RRGGBB` / `RRGGBB` (the shape `Project.colorHex` stores). Returns nil
    /// on anything malformed so the caller falls back to the auto palette.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self = Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
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
