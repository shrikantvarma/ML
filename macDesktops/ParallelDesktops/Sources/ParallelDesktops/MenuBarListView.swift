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
    /// Per-project "add a next step" draft text + hover tracking for checklist rows (U4).
    @State private var checklistDrafts: [UUID: String] = [:]
    @State private var hoveredChecklistID: UUID?
    /// Hover + inline-naming state for bare (unnamed) desktop rows (keyed by global index / uuid).
    @State private var hoveredDesktopGI: Int?
    @State private var namingDesktopUUID: String?
    @State private var desktopNameText = ""

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

            let hasRows = model.desktopList.sections.contains { !$0.rows.isEmpty }
            if !hasRows && model.desktopList.offDisplayProjects.isEmpty {
                Text("No desktops found yet.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(model.desktopList.sections) { section in
                        sectionDivider(section.name)
                        ForEach(section.rows) { row in desktopRow(row) }
                    }
                    if !model.desktopList.offDisplayProjects.isEmpty {
                        sectionDivider("Not on any display", warn: true)
                        ForEach(model.desktopList.offDisplayProjects) { offDisplayRow($0) }
                    }
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
            } else if model.focusedDesktopUntrackable {
                // Stabilize-assist: the focused desktop has no stable id yet, so it can't be
                // saved/named. Tell the user the one action that fixes it.
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.yellow).font(.caption)
                    Text("This desktop has no stable ID yet. Open or drag a window onto it, then reopen this menu — macOS will give it an ID and you can name it.")
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
            model.refreshPermissions()       // re-check whenever the popover opens
            model.refreshFocusedProject()    // focus may have moved displays since last Space-change
            ensureCurrentExpanded()
        }
        .onChange(of: model.currentProject?.id) { _, _ in ensureCurrentExpanded() }
    }

    /// A desktop row: dispatches to the rich project row when named, else a light
    /// "Desktop N" row (switch + name) or a static empty-uuid row.
    @ViewBuilder
    private func desktopRow(_ row: DesktopRow) -> some View {
        if let project = row.project {
            projectRow(project, row: row)
        } else {
            bareDesktopRow(row)
        }
    }

    @ViewBuilder
    private func projectRow(_ project: Project, row: DesktopRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if renamingID == project.id {
                TextField("Name", text: $renameText, onCommit: {
                    model.rename(project, to: renameText); renamingID = nil
                })
                .textFieldStyle(.roundedBorder)
            } else {
                projectRowMain(project, row: row)
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
                checklistBlock(project)
            }
        }
    }

    /// On each open (and on desktop change), expand ONLY the project you're on —
    /// every other row collapses. Keeps the list short and focused on "here".
    private func ensureCurrentExpanded() {
        expandedIDs = model.currentProject.map { [$0.id] } ?? []
    }

    // MARK: All-desktops switcher rows (U5)

    private func marker(_ row: DesktopRow) -> some View {
        let glyph: String; let color: Color
        switch row.marker {
        case .focused: glyph = "largecircle.fill.circle";  color = .accentColor
        case .other:   glyph = "smallcircle.filled.circle"; color = .accentColor.opacity(0.6)
        case .none:    glyph = "circle";                     color = .secondary.opacity(0.35)
        }
        return Image(systemName: glyph).font(.caption2).foregroundStyle(color)
            .help(row.marker == .focused ? "You're on this desktop"
                  : row.marker == .other ? "Showing on another display" : "")
    }

    private func numberLabel(_ row: DesktopRow) -> some View {
        Text("\(row.globalIndex)")
            .font(.system(size: 10.5)).monospacedDigit()
            .foregroundStyle(row.keyable ? Color.secondary : Color.secondary.opacity(0.4))
            .frame(minWidth: 13, alignment: .trailing)
    }

    /// Per-display section header (and the "Not on any display" group header).
    @ViewBuilder
    private func sectionDivider(_ name: String, warn: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(name.uppercased())
                .font(.system(size: 9.5, weight: .semibold)).tracking(0.5)
                .foregroundStyle(warn ? Color.yellow.opacity(0.9) : Color.secondary)
            Rectangle().fill(Palette.rail).frame(height: 1)
        }
        .padding(.horizontal, 7).padding(.top, 8).padding(.bottom, 2)
    }

    /// A desktop with no project: switchable "Desktop N" with inline Name…, or a
    /// static "no stable ID" row for empty-uuid desktops.
    @ViewBuilder
    private func bareDesktopRow(_ row: DesktopRow) -> some View {
        let hovered = hoveredDesktopGI == row.globalIndex
        let active = row.marker != .none
        Group {
            if row.isEmptyNoID {
                HStack(spacing: 8) {
                    marker(row); numberLabel(row)
                    Image(systemName: "questionmark.square.dashed").font(.system(size: 13)).foregroundStyle(.tertiary)
                    Text("Desktop \(row.globalIndex) · no stable ID").foregroundStyle(.tertiary)
                    Spacer()
                }
            } else if namingDesktopUUID == row.uuid {
                HStack(spacing: 8) {
                    marker(row); numberLabel(row)
                    TextField("Name this desktop…", text: $desktopNameText, onCommit: {
                        model.assignName(desktopNameText, toDesktopUUID: row.uuid)
                        namingDesktopUUID = nil; desktopNameText = ""
                    })
                    .textFieldStyle(.roundedBorder)
                }
            } else {
                HStack(spacing: 6) {
                    Button {
                        if row.keyable { model.enterDesktop(row.uuid) }
                        else { model.status = "Desktop \(row.globalIndex) is past Ctrl+9 — can’t switch to it." }
                    } label: {
                        HStack(spacing: 8) {
                            marker(row); numberLabel(row)
                            Image(systemName: "square.dashed").font(.system(size: 13)).foregroundStyle(.secondary)
                            Text("Desktop \(row.globalIndex)").italic().foregroundStyle(.secondary)
                            Spacer()
                            if !row.keyable {
                                Text("can't switch").font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button("Name…") { namingDesktopUUID = row.uuid; desktopNameText = ""; renamingID = nil }
                        .buttonStyle(.borderless).controlSize(.small)
                        .opacity(hovered ? 1 : 0)
                }
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7)
            .fill(active ? Palette.accentSoft : (hovered ? Palette.hover : Color.clear)))
        .onHover { inside in
            hoveredDesktopGI = inside ? row.globalIndex : (hoveredDesktopGI == row.globalIndex ? nil : hoveredDesktopGI)
        }
    }

    /// A project whose desktop is gone — switch disabled; reassign / open-here.
    @ViewBuilder
    private func offDisplayRow(_ project: Project) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).font(.caption)
            Text(project.name)
            Spacer()
            Menu {
                Button("Open on this screen") { model.openHere(project) }
                Button("Reassign to this desktop") { model.recalibrate(project) }
                Divider()
                Button("Delete", role: .destructive) { model.delete(project) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 22)
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .help("“\(project.name)” isn't on any connected display")
    }

    /// Where "Open on → [display]" lands: prefer a FREE (unnamed) desktop so the
    /// relocate doesn't collide with a project already hosted there; else that
    /// display's current desktop; else its first trackable desktop.
    private func relocateTarget(in section: DisplaySection) -> String? {
        section.rows.first(where: { $0.isUnnamed })?.uuid
            ?? section.rows.first(where: { $0.marker != .none })?.uuid
            ?? section.rows.first(where: { !$0.isEmptyNoID })?.uuid
    }

    /// The project's "what's next" checklist: toggleable items + an always-present
    /// quick-add field (U4). Real notes live in the linked doc; this is glanceable.
    @ViewBuilder
    private func checklistBlock(_ project: Project) -> some View {
        let items = project.blueprint.checklist
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1).fill(Palette.rail).frame(width: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text("NEXT").font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary).tracking(0.5)
                    .padding(.horizontal, 7).padding(.bottom, 1)

                ForEach(items) { item in
                    HStack(spacing: 7) {
                        Button { model.toggleChecklistItem(item.id, in: project) } label: {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 13))
                                .foregroundStyle(item.done ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        Text(item.text)
                            .font(.callout)
                            .strikethrough(item.done)
                            .foregroundStyle(item.done ? .secondary : .primary)
                            .lineLimit(2)
                        Spacer()
                        Button { model.removeChecklistItem(item.id, from: project) } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .opacity(hoveredChecklistID == item.id ? 1 : 0)
                        .help("Remove")
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(hoveredChecklistID == item.id ? Palette.hover : Color.clear))
                    .contentShape(Rectangle())
                    .onHover { inside in
                        hoveredChecklistID = inside ? item.id : (hoveredChecklistID == item.id ? nil : hoveredChecklistID)
                    }
                }

                // Quick-add — always present under an expanded project.
                HStack(spacing: 7) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    TextField("add a next step…", text: Binding(
                        get: { checklistDrafts[project.id] ?? "" },
                        set: { checklistDrafts[project.id] = $0 }))
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .onSubmit { commitChecklist(project) }
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
            }
        }
        .padding(.leading, 24)
        .padding(.bottom, 3)
    }

    private func commitChecklist(_ project: Project) {
        model.addChecklistItem(checklistDrafts[project.id] ?? "", to: project)
        checklistDrafts[project.id] = ""
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
    private func projectRowMain(_ project: Project, row: DesktopRow) -> some View {
        let isCurrent = row.marker == .focused
        let active = row.marker != .none
        let links = project.blueprint.links
        let hovered = hoveredRowID == project.id

        HStack(spacing: 6) {
            Button {
                if row.keyable { model.enter(project) }
                else { model.status = "“\(project.name)” is past Ctrl+9 — can’t switch to it." }
            } label: {
                HStack(spacing: 8) {
                    marker(row)
                    numberLabel(row)
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
                    // Display membership is now conveyed by the section grouping, so the
                    // per-row "Display N" badge is no longer needed here.
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

            // Chevron is the SOLE expand/collapse control — always available so an
            // empty project can be opened to add its first link / next-step.
            Button { toggleExpanded(project.id) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(expandedIDs.contains(project.id) ? 90 : 0))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                        Button("Bring up here") { model.bringUpApps(project) }
                        if model.desktopList.sections.count > 1 {
                            Menu("Open on display…") {
                                ForEach(model.desktopList.sections) { section in
                                    if let target = relocateTarget(in: section) {
                                        Button(section.name) { model.relocate(project, toDesktopUUID: target) }
                                    }
                                }
                            }
                        }
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
                    .fill(active ? Palette.accentSoft : (hovered ? Palette.hover : Color.clear))
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

    /// The inline links revealed under an expanded project row (U5): links + an
    /// always-present "+ add link…" entry so authoring is discoverable inline.
    @ViewBuilder
    private func linksBlock(_ project: Project) -> some View {
        let links = project.blueprint.links
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1).fill(Palette.rail).frame(width: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text("LINKS").font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary).tracking(0.5)
                    .padding(.horizontal, 7).padding(.bottom, 1)

                ForEach(links) { link in
                    HStack(spacing: 7) {
                        Button { model.openLink(link, in: project) } label: {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(faviconColor(link))
                                    .frame(width: 14, height: 14)
                                Text(link.title.isEmpty ? link.url : link.title)
                                    .font(.callout).lineLimit(1)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(link.url)
                        Button { model.removeLink(link.id, from: project) } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .opacity(hoveredLinkID == link.id ? 1 : 0)
                        .help("Remove link")
                    }
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(hoveredLinkID == link.id ? Palette.hover : Color.clear))
                    .contentShape(Rectangle())
                    .onHover { inside in
                        hoveredLinkID = inside ? link.id : (hoveredLinkID == link.id ? nil : hoveredLinkID)
                    }
                }

                if !links.isEmpty {
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

                // Always-present inline add (web / Obsidian / file link).
                Button { beginAddLink(project) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus.circle").font(.system(size: 13))
                        Text("add link…").font(.callout)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 24)
        .padding(.bottom, 3)
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
