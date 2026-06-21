import Foundation

/// Classifies how the desktop topology changed between two ordered UUID snapshots
/// (plan U5). Pure functions — fully unit-testable, no system access.
public enum SpaceTopologyChange: Equatable {
    case unchanged          // same set, same order (only the active space changed)
    case reordered          // same set, different order
    case added([String])
    case removed([String])
    case mixed(added: [String], removed: [String])
}

public enum DriftDetector {
    public static func diff(old: [String], new: [String]) -> SpaceTopologyChange {
        let oldSet = Set(old), newSet = Set(new)
        let added = new.filter { !oldSet.contains($0) }
        let removed = old.filter { !newSet.contains($0) }
        switch (added.isEmpty, removed.isEmpty) {
        case (true, true):  return old == new ? .unchanged : .reordered
        case (false, true): return .added(added)
        case (true, false): return .removed(removed)
        case (false, false): return .mixed(added: added, removed: removed)
        }
    }

    /// Which bound UUIDs are no longer present in the current ordered list
    /// (their desktop was removed) — these projects are drifted.
    public static func driftedUUIDs(bound: [String], in ordered: [String]) -> [String] {
        let present = Set(ordered)
        return bound.filter { !present.contains($0) }
    }
}
