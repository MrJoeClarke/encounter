//
//  World.swift
//  encounter
//

import Foundation
import SwiftData

/// The top-level container for everything a creator builds. A creator can have many worlds.
@Model
final class World {
    var id: UUID = UUID()
    var name: String = ""
    var summary: String = ""
    var systemRaw: String = RuleSystemID.none.rawValue
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \CalendarDefinition.world)
    var calendar: CalendarDefinition?

    @Relationship(deleteRule: .cascade, inverse: \Campaign.world)
    var campaigns: [Campaign]?

    @Relationship(deleteRule: .cascade, inverse: \Page.world)
    var pages: [Page]?

    @Relationship(deleteRule: .cascade, inverse: \WorldMap.world)
    var maps: [WorldMap]?

    @Relationship(deleteRule: .cascade, inverse: \PageImage.world)
    var images: [PageImage]?

    init(name: String, summary: String = "", system: RuleSystemID = .none) {
        self.name = name
        self.summary = summary
        self.systemRaw = system.rawValue
        self.calendar = CalendarDefinition()
    }

    var system: RuleSystemID {
        get { RuleSystemID(rawValue: systemRaw) ?? .none }
        set { systemRaw = newValue.rawValue }
    }
}
