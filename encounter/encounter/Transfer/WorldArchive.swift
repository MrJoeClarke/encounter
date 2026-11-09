//
//  WorldArchive.swift
//  encounter
//

import Foundation

/// The contents of a world's `world.json`, as plain value types.
///
/// These are deliberately separate from the SwiftData models, so a change to a model can't silently change
/// the file format. Records refer to each other by UUID. Image data lives in separate files, named by
/// `file` properties relative to the package's `images` folder.
///
/// Evolving the format: bump `currentFormatVersion` for changes older apps can't read. Fields added later
/// should be optional so older files still decode.
nonisolated struct WorldArchive: Codable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int = WorldArchive.currentFormatVersion
    var exportedAt: Date
    var world: WorldRecord
    var campaigns: [CampaignRecord]
    var pages: [PageRecord]
    var links: [LinkRecord]
    var maps: [MapRecord]
}

nonisolated struct WorldRecord: Codable, Sendable {
    var id: UUID
    var name: String
    var summary: String
    /// `RuleSystemID` raw value. Kept as a string so a system this app doesn't know survives a round trip.
    var system: String
    var createdAt: Date
    var calendar: CalendarRecord?
    /// The world's own images. Optional, because files written before world images existed don't have it.
    var images: [ImageRecord]?
    /// `LibraryEdition` raw value. Optional, because files written before editions existed don't have it.
    var edition: String?
    /// The root place, at the top of the place hierarchy. Optional, because older files don't have one, and a
    /// root place is made on import.
    var rootPlaceID: UUID?
    /// The version of the system the world was last set up under. Optional, because older files don't have it.
    var systemVersion: Int?
    /// What the system keeps for the whole world. Optional, because older files don't have it.
    var systemState: [String: Double]?
    /// The world's map style. Optional, because older files don't have it.
    var mapStyle: String?
}

nonisolated struct CalendarRecord: Codable, Sendable {
    var hoursPerDay: Int
    var months: [MonthRecord]
    var weekdays: [String]
}

nonisolated struct MonthRecord: Codable, Sendable {
    var name: String
    var dayCount: Int
}

nonisolated struct CampaignRecord: Codable, Sendable {
    var id: UUID
    var name: String
    var summary: String
    var createdAt: Date
}

nonisolated struct PageRecord: Codable, Sendable {
    var id: UUID
    var title: String
    var summary: String
    /// `PageKind` raw value.
    var kind: String
    /// `CharacterRole` raw value, for characters.
    var characterRole: String?
    var body: AttributedString
    var attributes: [String: AttributeValue]
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    /// `EventOrigin` raw value, for events.
    var eventOrigin: String?
    var startDate: InWorldDate?
    var endDate: InWorldDate?
    var campaignID: UUID?
    var parentID: UUID?
    /// `ParentSource` raw value. Optional, because older files don't have it.
    var parentSource: String?
    /// Where a place is. Optional, because older files don't have it.
    var geometry: PlaceGeometry?
    var images: [ImageRecord]
    /// The library entry this page was made from. Optional, because older files don't have it.
    var basedOnKey: String?
    /// Publishing. Optional, because older files don't have it: their pages come in hidden.
    var isPublished: Bool?
    var publishedData: Data?
    var dmNotes: String?
}

nonisolated struct ImageRecord: Codable, Sendable {
    var id: UUID
    var caption: String
    var sortOrder: Int
    var isDefault: Bool
    /// File name in the package's `images` folder. Nil if the page image had no data.
    var file: String?
}

nonisolated struct LinkRecord: Codable, Sendable {
    var id: UUID
    var role: String
    var sourceID: UUID
    var targetID: UUID
}

nonisolated struct MapRecord: Codable, Sendable {
    var id: UUID
    var name: String
    /// File name in the package's `images` folder.
    var imageFile: String?
    /// `MapKind` raw value. Optional, because older files don't have it.
    var kind: String?
    /// How the map lines up with the world's plane. Optional, because older files and uncalibrated maps don't have it.
    var calibration: MapCalibration?
    /// A scene map's grid. Optional, because older files don't have it.
    var gridColumns: Int?
    var gridRows: Int?
    /// The page this map depicts.
    var placeID: UUID?
    /// A map with no picture, and how big it is in metres. Optional, because older files don't have them.
    var isVector: Bool?
    var extentMetres: Int?
    /// What a settlement map was generated from, so it can be generated again.
    var settlementOptions: SettlementOptions?
    /// What a world map was generated from.
    var worldOptions: WorldOptions?
    /// What a scene map was generated from.
    var sceneOptions: SceneOptions?
    /// The map's own style, if it has one. Optional, because older files don't have it.
    var style: String?
    /// True if the picture of the map is hidden; absent otherwise.
    var hidesPicture: Bool?
}
