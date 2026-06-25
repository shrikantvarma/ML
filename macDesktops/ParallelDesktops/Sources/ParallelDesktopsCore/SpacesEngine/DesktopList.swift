import Foundation

/// The all-desktops switcher model: every live desktop across all displays, joined
/// with the saved Projects bound to them. Pure — computed from the `SpacesProvider`
/// read seam plus the project list, so it is fully unit-testable against fakes.
///
/// The Project is the durable anchor; a desktop is a surface it projects onto. A
/// desktop with a matching trackable Project shows that project; one without shows
/// "Desktop N"; an untrackable (empty/"?") desktop can host nothing.

/// One desktop as presented in the switcher.
public struct DesktopRow: Identifiable {
    /// Which display's *current* desktop this is, relative to keyboard focus.
    public enum Marker: Equatable { case focused, other, none }
    /// What is bound to this desktop.
    public enum Binding {
        case project(Project)   // a named, trackable desktop
        case unnamed            // a trackable desktop with no project → "Desktop N"
        case emptyNoID          // an untrackable ("" / "?") desktop → can't be named
    }

    public let uuid: String
    /// 1-based global Ctrl+N number — position across ALL displays, counting empties.
    public let globalIndex: Int
    public let marker: Marker
    public let binding: Binding

    /// Stable identity for SwiftUI `ForEach`: the global index is unique per row,
    /// unlike the uuid (empty-uuid desktops share "").
    public var id: Int { globalIndex }
    /// macOS only assigns Ctrl+1…9; beyond that the desktop can't be switched-to.
    public var keyable: Bool { globalIndex <= 9 }

    public var project: Project? { if case .project(let p) = binding { return p }; return nil }
    public var isUnnamed: Bool { if case .unnamed = binding { return true }; return false }
    public var isEmptyNoID: Bool { if case .emptyNoID = binding { return true }; return false }
}

/// A display and the desktops on it, in order.
public struct DisplaySection: Identifiable {
    public let ordinal: Int      // 1-based display ordinal
    public let name: String      // friendly name ("iPad") or "Display N"
    public let rows: [DesktopRow]
    public var id: Int { ordinal }
}

public struct DesktopList {
    public let sections: [DisplaySection]
    /// Projects whose bound desktop is not present on any live display (vanished /
    /// disconnected) — shown in the "Not on any display" group for reassign.
    public let offDisplayProjects: [Project]

    /// Pure join of live desktops ⋈ projects-by-UUID.
    /// - `displayNames`: friendly names by 0-based display index; missing → "Display N".
    public static func make(spaces: SpacesProvider,
                            projects: [Project],
                            displayNames: [String] = []) -> DesktopList {
        let displays = spaces.displaysWithDesktops()
        let focused = spaces.focusedCurrentSpaceUUID()
        // Only trackable spaceUUIDs can match a live desktop.
        let projectByUUID = Dictionary(
            projects.filter { SpaceIdentity.isTrackable($0.spaceUUID) }.map { ($0.spaceUUID, $0) },
            uniquingKeysWith: { first, _ in first })

        var globalIndex = 0
        var liveTrackable = Set<String>()
        var sections: [DisplaySection] = []

        for (displayIndex, desktops) in displays.enumerated() {
            var rows: [DesktopRow] = []
            for uuid in desktops {
                globalIndex += 1
                let trackable = SpaceIdentity.isTrackable(uuid)
                let marker: DesktopRow.Marker =
                    !trackable ? .none
                    : uuid == focused ? .focused
                    : spaces.isSpaceCurrent(uuid: uuid) ? .other
                    : .none
                let binding: DesktopRow.Binding
                if !trackable {
                    binding = .emptyNoID
                } else {
                    liveTrackable.insert(uuid)
                    binding = projectByUUID[uuid].map { .project($0) } ?? .unnamed
                }
                rows.append(DesktopRow(uuid: uuid, globalIndex: globalIndex, marker: marker, binding: binding))
            }
            let name = displayIndex < displayNames.count ? displayNames[displayIndex] : "Display \(displayIndex + 1)"
            sections.append(DisplaySection(ordinal: displayIndex + 1, name: name, rows: rows))
        }

        let offDisplay = projects.filter { !liveTrackable.contains($0.spaceUUID) }
        return DesktopList(sections: sections, offDisplayProjects: offDisplay)
    }
}
