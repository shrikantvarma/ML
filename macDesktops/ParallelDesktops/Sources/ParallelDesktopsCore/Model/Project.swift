import Foundation

/// Last-known window frame for a blueprint app (passively recorded in v1, not
/// acted on — plan R5/U9; this is the seam for future layout-restore).
public struct WindowFrame: Codable, Equatable {
    public var x: Double, y: Double, w: Double, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
}

/// The set of apps that define a project, plus passively-recorded frames.
public struct Blueprint: Codable, Equatable {
    public var bundleIDs: [String]
    public var frames: [String: WindowFrame]   // bundleID → last frame
    public init(bundleIDs: [String] = [], frames: [String: WindowFrame] = [:]) {
        self.bundleIDs = bundleIDs
        self.frames = frames
    }
}

/// "Where I left off" context (plan R10–R12).
public struct ResumeContext: Codable, Equatable {
    public var frontAppBundleID: String?
    public var windowTitle: String?
    public var note: String?
    public var capturedAt: Date?
    public init(frontAppBundleID: String? = nil, windowTitle: String? = nil,
                note: String? = nil, capturedAt: Date? = nil) {
        self.frontAppBundleID = frontAppBundleID
        self.windowTitle = windowTitle
        self.note = note
        self.capturedAt = capturedAt
    }
}

/// A named project bound to a macOS desktop by its stable Space UUID (KTD-2).
public struct Project: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var emoji: String?
    public var colorHex: String?
    public var spaceUUID: String
    public var blueprint: Blueprint
    public var resume: ResumeContext
    public var drifted: Bool

    public init(id: UUID = UUID(), name: String, emoji: String? = nil, colorHex: String? = nil,
                spaceUUID: String, blueprint: Blueprint = Blueprint(),
                resume: ResumeContext = ResumeContext(), drifted: Bool = false) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.spaceUUID = spaceUUID
        self.blueprint = blueprint
        self.resume = resume
        self.drifted = drifted
    }
}
