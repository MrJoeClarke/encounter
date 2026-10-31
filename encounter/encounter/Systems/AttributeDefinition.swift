//
//  AttributeDefinition.swift
//  encounter
//

import Foundation

enum AttributeType: Hashable {
    case text
    case number
    case bool
    /// A D&D-style ability score (1 to 30), shown with its modifier. Stored as `AttributeValue.number`.
    case abilityScore
    /// A fixed set of options. The chosen option is stored as `AttributeValue.text`.
    case choice([String])
    /// A reference to a page of the given kind in the same world, or, where the world's rule system has a
    /// content library, to a library entry of the matching kind. A page is stored as a `PageLink` with the given
    /// role, so it appears in backlinks. A library entry is stored by key, in `Page.setLibraryKey(_:role:)`.
    case contentReference(PageKind, role: String)
    /// A subclass chosen from the library, offered once the page's library class (stored with `classRole`) has
    /// subclasses. Stored by key, in `Page.setLibraryKey(_:role:)`.
    case subclassReference(role: String, classRole: String)
    /// A list of named entries, such as a race's traits or a class's features. `showsLevel` adds a level to each.
    case entries(showsLevel: Bool)
}

/// Describes one attribute: how it is labelled, edited and stored.
/// The editor builds its form from these, so rule systems add attributes without new UI.
struct AttributeDefinition: Identifiable {
    /// Stable storage key in `Page.attributes`, e.g. "core.creatureType". Never change a shipped key.
    let key: String
    let label: LocalizedStringResource
    let type: AttributeType
    let appliesTo: Set<PageKind>
    /// Section heading in the editor.
    let group: LocalizedStringResource

    var id: String { key }
}

/// Attributes that apply regardless of rule system.
enum CoreAttributes {
    static let traitsKey = "core.traits"
    static let featuresKey = "core.features"

    static let all: [AttributeDefinition] = [
        // Characters
        .init(key: "core.race", label: "Race", type: .contentReference(.race, role: LinkRole.race), appliesTo: [.character], group: "Details"),
        .init(key: "core.creatureType", label: "Creature Type", type: .text, appliesTo: [.character], group: "Details"),
        .init(key: "core.age", label: "Age", type: .text, appliesTo: [.character], group: "Details"),
        .init(key: "core.occupation", label: "Occupation", type: .text, appliesTo: [.character], group: "Details"),

        // Places
        .init(
            key: "core.placeType",
            label: "Place Type",
            type: .choice(["Region", "Settlement", "Building", "Wilderness", "Point of Interest"]),
            appliesTo: [.place],
            group: "Details"
        ),
        .init(key: "core.population", label: "Population", type: .number, appliesTo: [.place], group: "Details"),

        // Items
        .init(key: "core.itemType", label: "Item Type", type: .text, appliesTo: [.item], group: "Details"),
        .init(key: "core.value", label: "Value", type: .text, appliesTo: [.item], group: "Details"),

        // Organisations
        .init(key: "core.organisationType", label: "Organisation Type", type: .text, appliesTo: [.organisation], group: "Details"),
        .init(key: "core.organisationSize", label: "Size", type: .text, appliesTo: [.organisation], group: "Details"),

        // Races
        .init(key: "core.lifespan", label: "Lifespan", type: .text, appliesTo: [.race], group: "Details"),
        .init(key: "core.raceSize", label: "Size", type: .text, appliesTo: [.race], group: "Details"),
        .init(key: traitsKey, label: "Traits", type: .entries(showsLevel: false), appliesTo: [.race], group: "Traits"),

        // Classes
        .init(key: featuresKey, label: "Features", type: .entries(showsLevel: true), appliesTo: [.characterClass], group: "Features"),
    ]

    static func definitions(for kind: PageKind) -> [AttributeDefinition] {
        all.filter { $0.appliesTo.contains(kind) }
    }
}
