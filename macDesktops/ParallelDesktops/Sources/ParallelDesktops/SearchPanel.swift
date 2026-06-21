import SwiftUI
import AppKit
import ParallelDesktopsCore

/// Spotlight-style type-to-search jump panel (plan U11 / AE4).
@MainActor
final class SearchController {
    private var panel: KeyablePanel?
    private let onEnter: (Project) -> Void

    init(onEnter: @escaping (Project) -> Void) { self.onEnter = onEnter }

    func toggle(projects: [Project]) {
        if panel != nil { close(); return }
        let view = SearchView(
            projects: projects,
            onEnter: { [weak self] p in self?.onEnter(p); self?.close() },
            onClose: { [weak self] in self?.close() }
        )
        let panel = PanelFactory.make(size: NSSize(width: 460, height: 320), content: view)
        PanelFactory.positionTopCenter(panel, topInset: 140)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    private func close() { panel?.close(); panel = nil }
}

private struct SearchView: View {
    let projects: [Project]
    let onEnter: (Project) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @FocusState private var focused: Bool

    private var matches: [Project] { ProjectSearch.match(query: query, in: projects) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Jump to project…", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($focused)
                .padding(14)
                .onSubmit { if let first = matches.first { onEnter(first) } }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, project in
                        HStack(spacing: 8) {
                            Text(project.emoji ?? "🗂")
                            Text(project.name)
                            Spacer()
                            if project.drifted {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(index == 0 ? Color.accentColor.opacity(0.18) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture { onEnter(project) }
                    }
                    if matches.isEmpty {
                        Text("No match").foregroundStyle(.secondary).padding(14)
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onExitCommand { onClose() }       // Esc
        .onAppear { focused = true }
    }
}
