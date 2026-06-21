import Foundation

/// Pure, testable fuzzy matcher for the type-to-search panel (plan U11 / AE4).
/// Prefix matches rank above mid-string matches; empty query returns all.
public enum ProjectSearch {
    public static func match(query: String, in projects: [Project]) -> [Project] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return projects }
        let scored: [(Project, Int)] = projects.compactMap { p in
            let name = p.name.lowercased()
            if name.hasPrefix(q) { return (p, 0) }
            if name.contains(q) { return (p, 1) }
            return nil
        }
        return scored.sorted { $0.1 < $1.1 }.map { $0.0 }
    }
}
