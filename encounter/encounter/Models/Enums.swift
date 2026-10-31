//
//  Enums.swift
//  encounter
//

import Foundation

/// The kind of content a `Page` holds. Stored on the page as a raw string.
enum PageKind: String, Codable, CaseIterable, Identifiable {
    case character
    case place
    case event
    case item
    case organisation
    case race
    case characterClass = "class"
    case background
    case feat

    var id: String { rawValue }

    /// Plural title used for lists and the sidebar.
    var title: LocalizedStringResource {
        switch self {
        case .character: "Characters"
        case .place: "Places"
        case .event: "Events"
        case .item: "Items"
        case .organisation: "Organisations"
        case .race: "Races & Species"
        case .characterClass: "Classes"
        case .background: "Backgrounds"
        case .feat: "Feats"
        }
    }

    /// Singular title used for "New …" actions and headers.
    var singularTitle: LocalizedStringResource {
        switch self {
        case .character: "Character"
        case .place: "Place"
        case .event: "Event"
        case .item: "Item"
        case .organisation: "Organisation"
        case .race: "Race or Species"
        case .characterClass: "Class"
        case .background: "Background"
        case .feat: "Feat"
        }
    }

    var systemImage: String {
        switch self {
        case .character: "person.fill"
        case .place: "mappin.and.ellipse"
        case .event: "calendar"
        case .item: "shippingbox.fill"
        case .organisation: "building.columns.fill"
        case .race: "pawprint.fill"
        case .characterClass: "shield.lefthalf.filled"
        case .background: "book.closed.fill"
        case .feat: "medal.fill"
        }
    }

    /// Kinds that only appear in a world's sidebar when its rule system uses them, or when the world already
    /// has pages of that kind, so a world on "None" doesn't show an empty Classes category.
    var isConditional: Bool {
        switch self {
        case .characterClass, .background, .feat: true
        default: false
        }
    }
}

/// Whether a character is controlled by a player. Monsters and animals are non-playable.
enum CharacterRole: String, Codable, CaseIterable, Identifiable {
    case playable
    case nonPlayable

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .playable: "Playable"
        case .nonPlayable: "Non-Playable"
        }
    }
}

/// The rule system a world uses. Each system contributes extra attributes (added in a later milestone).
enum RuleSystemID: String, Codable, CaseIterable, Identifiable {
    case none
    case dnd5e

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .none: "None"
        case .dnd5e: "Dungeons & Dragons 5e"
        }
    }
}

/// Whether an event happened before the campaign (backstory) or during it.
enum EventOrigin: String, Codable, CaseIterable, Identifiable {
    case backstory
    case campaign

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .backstory: "Backstory"
        case .campaign: "Campaign"
        }
    }
}
