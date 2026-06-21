import Foundation

/// On-disk shape: a version header + the projects (plan KTD-6).
public struct ProjectsFile: Codable {
    public var schemaVersion: Int
    public var projects: [Project]
    public init(schemaVersion: Int = ProjectStore.currentSchemaVersion, projects: [Project] = []) {
        self.schemaVersion = schemaVersion
        self.projects = projects
    }
}

/// Atomic JSON store keyed by Space UUID, capped at the desktop ceiling (R6).
/// Injectable URL so tests run against a temp file.
public final class ProjectStore {
    public static let currentSchemaVersion = 1
    public static let maxProjects = 16   // macOS ceiling; product target is 7–10 (R6)

    public enum StoreError: Error, Equatable { case capExceeded }

    public let url: URL
    public private(set) var projects: [Project]

    public init(url: URL = ProjectStore.defaultURL) {
        self.url = url
        self.projects = ProjectStore.read(from: url)?.projects ?? []
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ParallelDesktops", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("projects.json")
    }

    public func add(_ project: Project) throws {
        guard projects.count < Self.maxProjects else { throw StoreError.capExceeded }
        projects.append(project)
        save()
    }

    public func update(_ project: Project) {
        guard let i = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[i] = project
        save()
    }

    public func remove(id: UUID) {
        projects.removeAll { $0.id == id }
        save()
    }

    public func project(forSpaceUUID uuid: String) -> Project? {
        projects.first { $0.spaceUUID == uuid }
    }

    public func save() {
        let file = ProjectsFile(schemaVersion: Self.currentSchemaVersion, projects: projects)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(file) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func read(from url: URL) -> ProjectsFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        // v1 accepts only schemaVersion 1; future versions branch here.
        return try? dec.decode(ProjectsFile.self, from: data)
    }
}
