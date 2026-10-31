//
//  Page.swift
//  encounter
//

import Foundation
import SwiftData

/// One entity for every kind of content (character, place, event, item, organisation, race).
/// Per-kind behaviour comes from `kind` and the attribute schema, not from separate model types.
@Model
final class Page {
    var id: UUID = UUID()
    var title: String = ""
    var summary: String = ""
    var kindRaw: String = PageKind.character.rawValue
    /// Only meaningful when `kind == .character`.
    var characterRoleRaw: String?
    var body: AttributedString = AttributedString()
    /// Values keyed by stable attribute key, e.g. "dnd5e.armorClass".
    var attributes: [String: AttributeValue] = [:]
    var tags: [String] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Event data. Only meaningful when `kind == .event`.
    var eventOriginRaw: String?
    var startDate: InWorldDate?
    var endDate: InWorldDate?
    var campaign: Campaign?

    var world: World?

    /// The library entry this page was made from with Create Custom Version, if any.
    var basedOnKey: String?

    /// Hierarchy, used mainly for places (region, settlement, building).
    var parent: Page?
    @Relationship(deleteRule: .nullify, inverse: \Page.parent)
    var children: [Page]?

    @Relationship(deleteRule: .cascade, inverse: \PageImage.page)
    var images: [PageImage]?

    @Relationship(deleteRule: .cascade, inverse: \PageLink.source)
    var outgoingLinks: [PageLink]?

    @Relationship(deleteRule: .cascade, inverse: \PageLink.target)
    var incomingLinks: [PageLink]?

    @Relationship(deleteRule: .nullify, inverse: \WorldMap.place)
    var maps: [WorldMap]?

    @Relationship(deleteRule: .cascade, inverse: \MapPin.target)
    var pins: [MapPin]?

    init(title: String, kind: PageKind, summary: String = "") {
        self.title = title
        self.kindRaw = kind.rawValue
        self.summary = summary
        if kind == .character {
            self.characterRoleRaw = CharacterRole.nonPlayable.rawValue
        }
    }

    var kind: PageKind {
        get { PageKind(rawValue: kindRaw) ?? .character }
        set { kindRaw = newValue.rawValue }
    }

    var characterRole: CharacterRole? {
        get { characterRoleRaw.flatMap(CharacterRole.init(rawValue:)) }
        set { characterRoleRaw = newValue?.rawValue }
    }

    var eventOrigin: EventOrigin? {
        get { eventOriginRaw.flatMap(EventOrigin.init(rawValue:)) }
        set { eventOriginRaw = newValue?.rawValue }
    }
}
