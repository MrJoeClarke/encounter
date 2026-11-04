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
    /// The version of the system the world was last set up or imported under. 0 if never recorded.
    var systemVersion: Int = 0
    /// Numbers the world's system keeps for the whole world, such as the GM's Fear, as JSON text. See `systemState`.
    var systemStateRaw: String = ""
    /// Which edition of the content library the world uses. Only matters for systems that have a library.
    var editionRaw: String = LibraryEdition.default.rawValue
    var createdAt: Date = Date()
    /// The place at the top of the world's hierarchy, whose map is the world map. See `rootPlace`.
    var rootPlaceID: UUID?
    /// The id of the `MapStyle` its vector maps are drawn in, unless a map has its own. Empty is the default style.
    var mapStyleID: String = ""

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
        self.systemVersion = RuleSystems.system(for: system).version
        self.calendar = CalendarDefinition()
    }

    var system: RuleSystemID {
        get { RuleSystemID(rawValue: systemRaw) ?? .none }
        set { systemRaw = newValue.rawValue }
    }

    var edition: LibraryEdition {
        get { LibraryEdition(rawValue: editionRaw) ?? .default }
        set { editionRaw = newValue.rawValue }
    }

    /// The page kinds shown in the sidebar: every kind, except conditional ones (such as Classes) unless the
    /// rule system uses them or the world already has pages of that kind. Pages are never hidden.
    var visibleKinds: [PageKind] {
        let systemKinds = RuleSystems.system(forKey: systemRaw).additionalPageKinds
        let usedKinds = Set((pages ?? []).map(\.kind))
        return PageKind.allCases.filter { kind in
            !kind.isConditional || systemKinds.contains(kind) || usedKinds.contains(kind)
        }
    }
}
