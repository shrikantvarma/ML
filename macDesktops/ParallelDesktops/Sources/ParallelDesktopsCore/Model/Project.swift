import Foundation

/// Last-known window frame for a blueprint app (passively recorded in v1, not
/// acted on — plan R5/U9; this is the seam for future layout-restore).
public struct WindowFrame: Codable, Equatable {
    public var x: Double, y: Double, w: Double, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
}

/// An important webpage for a project, opened on its desktop via the validated
/// switch→settle→open recipe (plan U1/D1). `url` is constrained to http/https at
/// authoring and open time (KTD8); `title` is user-editable, host-seeded.
public struct Link: Identifiable, Codable, Equatable {
    public var id: UUID
    public var url: String
    public var title: String
    public init(id: UUID = UUID(), url: String, title: String) {
        self.id = id
        self.url = url
        self.title = title
    }
}

/// A short "what's next" item for a project — flat text + a done toggle (plan U1).
/// Real notes live in the linked tool; this is the glanceable next-actions list.
public struct ChecklistItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var text: String
    public var done: Bool
    public init(id: UUID = UUID(), text: String, done: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
    }
}

/// The set of apps that define a project, its passively-recorded frames, the
/// project's ordered links, and its next-actions checklist. `links` and `checklist`
/// are additive and migration-safe: existing `projects.json` files (no key) decode
/// without a schemaVersion bump (KTD1).
public struct Blueprint: Codable, Equatable {
    public var bundleIDs: [String]
    public var frames: [String: WindowFrame]   // bundleID → last frame
    public var links: [Link]                   // ordered; array order is user order
    public var checklist: [ChecklistItem]      // ordered next-actions
    public init(bundleIDs: [String] = [], frames: [String: WindowFrame] = [:],
                links: [Link] = [], checklist: [ChecklistItem] = []) {
        self.bundleIDs = bundleIDs
        self.frames = frames
        self.links = links
        self.checklist = checklist
    }

    private enum CodingKeys: String, CodingKey { case bundleIDs, frames, links, checklist }

    // Custom decode because synthesized Decodable ignores property defaults and would
    // throw keyNotFound on an old file with no `links`/`checklist` key. `decodeIfPresent
    // ?? []` makes a missing key a migration (→ []) while a present-but-malformed value
    // still throws (→ the store quarantines it). encode(to:) stays synthesized.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bundleIDs = try c.decode([String].self, forKey: .bundleIDs)
        self.frames = try c.decode([String: WindowFrame].self, forKey: .frames)
        self.links = try c.decodeIfPresent([Link].self, forKey: .links) ?? []
        self.checklist = try c.decodeIfPresent([ChecklistItem].self, forKey: .checklist) ?? []
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
    /// On-disk Chrome profile *folder* name (e.g. `Default`, `Profile 3`) this
    /// project opens links in. nil = system default browser (KTD2/KTD3). Defaulted
    /// for migration safety (KTD1).
    public var chromeProfileFolder: String?
    /// Chosen SF Symbol name for the project's identity tile. nil = auto-assigned
    /// from the curated set. Optional → migrates cleanly (decodeIfPresent).
    public var iconName: String?

    public init(id: UUID = UUID(), name: String, emoji: String? = nil, colorHex: String? = nil,
                spaceUUID: String, blueprint: Blueprint = Blueprint(),
                resume: ResumeContext = ResumeContext(), drifted: Bool = false,
                chromeProfileFolder: String? = nil, iconName: String? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.spaceUUID = spaceUUID
        self.blueprint = blueprint
        self.resume = resume
        self.drifted = drifted
        self.chromeProfileFolder = chromeProfileFolder
        self.iconName = iconName
    }

    /// Compact, never-clipping menu-bar label: the project's glyph followed by the
    /// first letter of its name, uppercased (e.g. "📊C", "◳C"). Kept tiny on purpose
    /// so it survives a crowded or notched menu bar where the full name would be
    /// pushed off-screen — detecting that clipping isn't reliably possible, so we
    /// simply never grow large enough to clip. The full name still shows in the
    /// popover. Falls back to the glyph alone when the name has no leading letter.
    public var menuBarCompactLabel: String {
        let glyph = emoji ?? "◳"
        let firstLetter = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .first.map { String($0).uppercased() } ?? ""
        return firstLetter.isEmpty ? glyph : "\(glyph)\(firstLetter)"
    }
}
